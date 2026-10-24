import { Engine, type AgentRole, type EngineEvent, type ProposalInput, type SubmitResult, type Time } from "@ares/engine";
import type { AgentInput, Brain, BrainContext, Intent } from "./brains.ts";
import type { Mood, ScheduledWorldEvent, World, WorldEvent } from "./world.ts";

export interface Narration {
  seq: number;
  at: Time;
  actorId: string;
  role: string;
  name: string;
  text: string;
  mood: Mood;
  outcome: "said" | "allow" | "deny" | "hold" | "escalate";
  proposalId?: string;
  decisionId?: string;
}

export type OrchestratorMessage =
  | { type: "narration"; narration: Narration }
  | { type: "telemetry"; at: Time; data: Record<string, unknown> }
  | { type: "engine"; event: EngineEvent };

export interface OrchestratorOptions {
  world: World;
  brains: Brain[];
  fmtTime?: (t: Time) => string;
  /** Real-time pause after each spoken action, so a live audience can follow. 0 in eval. */
  paceMs?: number;
  /** Hard cap on cascaded events per run, in case of a feedback loop. */
  maxSteps?: number;
}

/**
 * Discrete-event loop: delivers world events in time order, lets each role's brain
 * propose, submits proposals to the engine, and feeds engine events back to the
 * world and the agents until everything settles.
 */
export class Orchestrator {
  readonly engine: Engine;
  readonly meta: Record<string, unknown>;
  readonly world: World;
  readonly narration: Narration[] = [];
  private readonly brains: Brain[];
  private readonly fmtTime: (t: Time) => string;
  private readonly paceMs: number;
  private readonly maxSteps: number;
  private timeline: { at: Time; seq: number; event: WorldEvent }[] = [];
  private queue: EngineEvent[] = [];
  private listeners: ((m: OrchestratorMessage) => void)[] = [];
  private seq = 0;
  private narrSeq = 0;
  private steps = 0;
  private busy = false;
  /** Per-actor credentials. Never handed to brains: an agent can only ever act as itself. */
  readonly #creds = new Map<string, string>();

  constructor(opts: OrchestratorOptions) {
    this.world = opts.world;
    this.brains = opts.brains;
    this.fmtTime = opts.fmtTime ?? ((t) => new Date(t).toISOString());
    this.paceMs = opts.paceMs ?? 0;
    this.maxSteps = opts.maxSteps ?? 50_000;
    const setup = this.world.setup();
    this.meta = setup.meta;
    this.engine = new Engine({ ...setup.config, requireCredentials: true });
    for (const a of this.engine.actors.values()) this.#creds.set(a.id, this.engine.issueCredential(a.id));
    this.engine.subscribe((e) => {
      this.queue.push(e);
      this.emit({ type: "engine", event: e });
    });
    this.scheduleAll(this.world.initialEvents(this.engine));
  }

  on(fn: (m: OrchestratorMessage) => void): () => void {
    this.listeners.push(fn);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== fn);
    };
  }

  private emit(m: OrchestratorMessage): void {
    for (const l of this.listeners) l(m);
  }

  schedule(at: Time, event: WorldEvent): void {
    this.timeline.push({ at, seq: ++this.seq, event });
    this.timeline.sort((a, b) => a.at - b.at || a.seq - b.seq);
  }

  scheduleAll(evs: ScheduledWorldEvent[]): void {
    for (const s of evs) this.schedule(s.at, s.event);
  }

  get isBusy(): boolean {
    return this.busy;
  }

  nextEventAt(): Time | undefined {
    const a = this.timeline[0]?.at;
    const b = this.engine.pendingInbound().reduce<Time | undefined>((m, x) => (m === undefined || x.at < m ? x.at : m), undefined);
    const c = [...this.engine.escalations.values()].filter((x) => x.status === "in_transit").reduce<Time | undefined>((m, x) => (m === undefined || x.deliverAt < m ? x.deliverAt : m), undefined);
    return [a, b, c].filter((x): x is Time => x !== undefined).sort((x, y) => x - y)[0];
  }

  /** Process everything due up to simulated time t. */
  async runUntil(t: Time): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      for (;;) {
        const next = this.timeline[0];
        if (!next || next.at > t) break;
        this.timeline.shift();
        if (next.at > this.engine.now) this.engine.advanceTo(next.at);
        await this.drain();
        await this.dispatchWorld(next.event);
        await this.drain();
      }
      this.engine.advanceTo(Math.max(t, this.engine.now));
      await this.drain();
      if (this.world.onTime) this.scheduleAll(this.world.onTime(this.engine.now, this.engine));
    } finally {
      this.busy = false;
    }
  }

  /** Run until nothing is left to do (eval mode). */
  async runToQuiescence(limit: Time): Promise<void> {
    for (;;) {
      const next = this.nextEventAt();
      if (next === undefined || next > limit) break;
      await this.runUntil(next);
    }
    await this.runUntil(Math.min(limit, Math.max(this.engine.now, limit)));
  }

  /**
   * A human acted (VR decision or console). The host decides which human role the
   * caller is; the credential is attached here, never taken from the caller.
   */
  /** Policy edits come from the console acting as the policy owner (remote authority). */
  setPolicy(policy: unknown): void {
    const owner = this.roleActor("remote_authority");
    if (!owner) throw new Error("no policy owner");
    this.engine.setPolicy(policy, owner, this.#creds.get(owner));
  }

  async submitHuman(role: "local_authority" | "remote_authority", input: Omit<ProposalInput, "actorId" | "credential">): Promise<SubmitResult> {
    const actorId = this.roleActor(role);
    if (!actorId) throw new Error(`no actor for ${role}`);
    const res = this.engine.submit({ ...input, actorId, credential: this.#creds.get(actorId), source: input.source ?? "human" });
    const actor = this.engine.actors.get(actorId);
    let text = input.type.replace(/_/g, " ");
    if (input.type === "decide") {
      const { escalationId, optionId } = input.params as { escalationId: string; optionId: string };
      text = `Decision: ${this.engine.escalations.get(escalationId)?.options.find((o) => o.id === optionId)?.label ?? optionId}`;
    }
    if (actor) this.narrate(actor.id, res.decision.verdict === "deny" ? `Refused: ${res.decision.summary}` : text, res.decision.verdict === "deny" ? "attentive" : "calm", res);
    await this.drain();
    return res;
  }

  private async dispatchWorld(event: WorldEvent): Promise<void> {
    if (event.type === "telemetry") {
      this.emit({ type: "telemetry", at: this.engine.now, data: event.data });
      return;
    }
    if (event.type === "narration") {
      const actor = [...this.engine.actors.values()].find((a) => a.role === event.agentRole);
      if (actor) this.narrate(actor.id, event.text, event.mood ?? "calm");
      return;
    }
    if (event.type === "external") {
      const res = this.engine.submit({ actorId: event.actorId, type: event.action, params: event.params, source: "human", credential: this.#creds.get(event.actorId) });
      this.narrate(event.actorId, res.decision.verdict === "deny" ? `Refused: ${res.decision.summary}` : event.summary, "calm", res);
      return;
    }
    if (event.type === "document") {
      this.engine.ingestDocument({ id: event.doc.id, kind: event.doc.kind, from: event.doc.from, text: event.doc.text });
    }
    await this.toBrains({ kind: "world", event, at: this.engine.now });
  }

  private async drain(): Promise<void> {
    while (this.queue.length) {
      if (++this.steps > this.maxSteps) throw new Error("orchestrator step limit reached (feedback loop?)");
      const e = this.queue.shift()!;
      this.scheduleAll(this.world.onEngineEvent(e, this.engine));
      await this.toBrains({ kind: "engine", event: e });
    }
  }

  private async toBrains(input: AgentInput): Promise<void> {
    for (const brain of this.brains) {
      const self = [...this.engine.actors.values()].find((a) => a.role === brain.role);
      if (!self) continue;
      const ctx: BrainContext = { engine: this.engine, self, fmtTime: this.fmtTime, itemName: (sku) => this.engine.items.get(sku)?.name ?? sku };
      let intents: Intent[];
      try {
        intents = await brain.react(input, ctx);
      } catch (err) {
        this.narrate(self.id, `(${brain.kind} brain error: ${(err as Error).message})`, "attentive");
        continue;
      }
      for (const it of intents) await this.act(self.id, brain, it);
    }
  }

  private async act(actorId: string, brain: Brain, it: Intent): Promise<void> {
    if (it.type === "__say") {
      if (it.say) this.narrate(actorId, it.say, it.mood ?? "calm");
      await this.pace();
      return;
    }
    const res = this.engine.submit({ actorId, type: it.type, params: it.params, rationale: it.rationale, source: brain.kind, credential: this.#creds.get(actorId) });
    const v = res.decision.verdict;
    if (v === "deny") {
      const failed = res.decision.rules.filter((r) => !r.ok).map((r) => r.detail).join("; ");
      this.narrate(actorId, `Policy refused my ${it.type.replace(/_/g, " ")}: ${failed}`, "attentive", res);
    } else if (it.say) {
      this.narrate(actorId, it.say, it.mood ?? (v === "allow" ? "calm" : "attentive"), res);
    }
    await this.pace();
  }

  private narrate(actorId: string, text: string, mood: Mood, res?: SubmitResult): void {
    const actor = this.engine.actors.get(actorId);
    const n: Narration = {
      seq: ++this.narrSeq,
      at: this.engine.now,
      actorId,
      role: actor?.role ?? "system",
      name: actor?.displayName ?? actorId,
      text,
      mood,
      outcome: res ? res.decision.verdict : "said",
      proposalId: res?.proposal?.id,
      decisionId: res?.decision.id,
    };
    this.narration.push(n);
    this.emit({ type: "narration", narration: n });
  }

  private async pace(): Promise<void> {
    if (this.paceMs > 0) await new Promise((r) => setTimeout(r, this.paceMs));
  }

  roleActor(role: AgentRole | "local_authority" | "remote_authority"): string | undefined {
    return [...this.engine.actors.values()].find((a) => a.role === role)?.id;
  }
}
