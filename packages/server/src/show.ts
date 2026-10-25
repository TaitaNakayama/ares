import { compact, holdMsFor, speak, wordCount, type ModelRouter, type OrchestratorMessage, type Orchestrator, type Spoken } from "@ares/agents";
import type { EngineEvent, Escalation, Flag, Quote, Requisition, Verification } from "@ares/engine";
import { CREW, crewOf, type CrewId, type MarsWorld } from "@ares/world-mars";

/**
 * The show: the four acts of the experience (docs/demo/script.md). Events and staging are scripted here;
 * what the agents do and their exact words are live. Lines go through one queue: one bubble at a time,
 * at least 1 s apart, each held 2.5 s + 0.4 s per word. The model is asked for each line under the text
 * rules (10 words, one number, no semicolons); the scripted target line is said when it fails.
 */

export type Act = "title" | "outside" | "entering" | "inside" | "crisis" | "decision" | "consequence" | "later" | "resolved" | "explore";
type Cue = "science" | "door" | "card" | "engineer" | null;
type To = "judge" | CrewId | "rim";

interface CrewState {
  place: "outside" | "inside";
  task: string;
  lookAt: To | null;
  mood: "calm" | "worried" | "alarmed" | "happy";
  approach: boolean;
}

interface LineSpec {
  speaker: CrewId;
  /** The engine actor the words are recorded under (Supply speaks for receiving, bills or payments). */
  actor: string;
  to: To;
  intent: string;
  facts?: string;
  target: string;
  /** Pause before this line (at least 1 s). */
  gapMs?: number;
  onStart?: () => void;
  /** Words already decided (an answer to the judge's question). */
  text?: string;
}

interface Entry {
  spec: LineSpec;
  words: Promise<Spoken>;
}

export interface ShowHost {
  orch(): Orchestrator;
  world(): MarsWorld;
  router: ModelRouter | undefined;
  notify(): void;
  setSpeed(x: number): void;
  baseSpeed: number;
  timelapse(): void;
  decide(escalationId: string, optionId: string): Promise<void>;
}

const ACTOR: Record<CrewId, string> = { engineer: "engineer", life: "life", science: "science", supply: "cargo", rules: "rules" };
const TO_NAME = (to: To) => (to === "judge" ? "the commander" : to === "rim" ? "the crew, looking at the crater rim" : CREW[to as CrewId].name);

/** Option kinds on the decision card: label (≤4 words), icon, who speaks the tradeoff, and the target lines. */
const OPTION_KIND = {
  drill: { label: "Shut down the drill", icon: "drill", speaker: "life" as CrewId, tradeoff: "No new water for a while.", tradeoffIntent: "Shutting the ice drill means no new water for a while." },
  lab: { label: "Pause the science lab", icon: "flask", speaker: "science" as CrewId, tradeoff: "Our samples could spoil.", tradeoffIntent: "Pausing the lab means the samples could spoil." },
  buy: { label: "Buy trusted batteries", icon: "battery", speaker: "supply" as CrewId, tradeoff: "Fewer batteries, and they arrive later.", tradeoffIntent: "The trusted supplier has fewer batteries, and they arrive later." },
};
type OptionKind = keyof typeof OPTION_KIND;

const kindOf = (o: { id: string; leverId?: string; actions: { type: string }[] }): OptionKind | undefined =>
  o.leverId === "drill_off" || o.id === "lever-drill_off" ? "drill" : o.leverId === "lab_pause" || o.id === "lever-lab_pause" ? "lab" : o.actions.some((a) => a.type === "approve_requisition") ? "buy" : undefined;

export class Show {
  act: Act = "title";
  active = false;
  private title: { text: string; style: "black" | "window" | "end" } | null = null;
  private cue: Cue = null;
  private crew: Record<CrewId, CrewState> = Show.initialCrew();
  private speaking: { seq: number; speaker: CrewId; to: To; text: string; holdMs: number; via: "llm" | "rules" } | null = null;
  private seq = 0;
  private queue: Entry[] = [];
  private pumping = false;
  private lastLineEnd = 0;
  private timers: NodeJS.Timeout[] = [];
  private closeupOpen = false;
  private realityOn = false;
  private thinkingActors = new Set<string>();
  private decision: { id: string; options: { id: string; label: string; icon: string; speaker: CrewId; kind: OptionKind; proposedBy: string | null }[]; gazed: string | null; chosen: string | null } | null = null;
  private tradeoffs = new Map<string, Promise<Spoken>>();
  private tradeoffAt = new Map<string, number>();
  private crisisAt = 0;
  private stormStarted = false;
  private savedBig: string | null = null;
  private incoming: { label: string; eta: string } | null = null;
  private earthAnswered = false;
  private laterShown = false;
  private quoteSaid = false;
  private flagTimer?: NodeJS.Timeout;
  private batteryReq?: string;
  private autoplayChoice?: OptionKind;
  /** Log of every spoken line (for the eval and the reviewer). */
  readonly log: { at: number; act: Act; speaker: CrewId; to: To; text: string; via: "llm" | "rules"; reason?: string; ms: number }[] = [];
  private unsub?: () => void;
  private startedAt = 0;

  private readonly host: ShowHost;

  constructor(host: ShowHost) {
    this.host = host;
  }

  static initialCrew(): Record<CrewId, CrewState> {
    return {
      engineer: { place: "outside", task: "judge", lookAt: null, mood: "calm", approach: false },
      life: { place: "inside", task: "plants", lookAt: null, mood: "calm", approach: false },
      science: { place: "outside", task: "rock", lookAt: null, mood: "calm", approach: false },
      supply: { place: "outside", task: "lander", lookAt: null, mood: "calm", approach: false },
      rules: { place: "inside", task: "console", lookAt: null, mood: "calm", approach: false },
    };
  }

  private get orch(): Orchestrator {
    return this.host.orch();
  }
  private get world(): MarsWorld {
    return this.host.world();
  }

  /** Clear everything (a fresh session). */
  reset(): void {
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
    this.unsub?.();
    this.unsub = undefined;
    Object.assign(this, {
      act: "title", active: false, title: this.openingTitle(), cue: null, crew: Show.initialCrew(), speaking: null, queue: [], pumping: false, lastLineEnd: 0,
      closeupOpen: false, realityOn: false, decision: null, reacted: new Set<string>(), crisisAt: 0, stormStarted: false, savedBig: null, incoming: null, earthAnswered: false, laterShown: false, quoteSaid: false, batteryReq: undefined, autoplayChoice: undefined,
    });
    this.tradeoffs.clear();
    this.tradeoffAt.clear();
    this.thinkingActors.clear();
    this.log.length = 0;
    this.host.notify();
  }

  private openingTitle() {
    return { text: `JEZERO CRATER, MARS · SOL ${this.world.sol(this.world.start)}`, style: "black" as const };
  }

  private at(ms: number, fn: () => void): void {
    this.timers.push(setTimeout(() => { try { fn(); } catch (err) { console.error("[show]", err); } }, ms));
  }

  private set(patch: Partial<Pick<Show, "act">> & { cue?: Cue; title?: Show["title"] }): void {
    if (patch.act) this.act = patch.act;
    if ("cue" in patch) this.cue = patch.cue ?? null;
    if ("title" in patch) this.title = patch.title ?? null;
    this.host.notify();
    if (this.autoplayChoice) this.autoplayStep();
  }

  private crewSet(id: CrewId, patch: Partial<CrewState>): void {
    Object.assign(this.crew[id], patch);
    this.host.notify();
  }

  // ---------------------------------------------------------------- the acts

  start(opts: { autoplay?: OptionKind } = {}): void {
    this.reset();
    this.active = true;
    this.autoplayChoice = opts.autoplay;
    this.startedAt = Date.now();
    this.unsub = this.orch.on((m) => this.onMessage(m));
    this.set({ act: "title", title: this.openingTitle(), cue: null });
    // Act 1: outside.
    this.at(3000, () => this.set({ act: "outside", title: null }));
    this.at(5000, () => this.line({ speaker: "engineer", actor: "engineer", to: "judge", intent: "Greet the commander, who just stepped out onto Mars, and say the crew has the base handled.", target: "Welcome, Commander. The crew has the base." }));
    this.at(9500, () =>
      this.line({
        speaker: "science", actor: "science", to: "judge", intent: "You're grinding into ancient river-delta rock with your arm. Ask if they want a closer look.", target: "Grinding into ancient delta rock. Want a closer look?",
        onStart: () => { this.set({ cue: "science" }); this.at(9000, () => { if (this.cue === "science") this.set({ cue: null }); }); },
      }),
    );
    this.at(12_000, () => this.orch.scheduleAll(this.world.beatDelivery(this.orch.engine)));
    this.at(26_000, () => {
      this.crewSet("engineer", { lookAt: "rim", mood: "worried" });
      this.stormStarted = true;
      this.orch.scheduleAll(this.world.startStorm(this.orch.engine));
      this.line({ speaker: "engineer", actor: "engineer", to: "rim", intent: "A dust storm is rising over the crater rim. Warn the crew.", target: "Dust storm incoming." });
      this.line({
        speaker: "engineer", actor: "engineer", to: "judge", intent: "Tell the commander to get inside the base, now.", target: "Commander, get inside. Now.",
        onStart: () => this.at(2500, () => { if (this.act === "outside") { this.set({ cue: "door" }); this.at(20_000, () => { if (this.act === "outside") void this.enter("auto"); }); } }),
      });
    });
  }

  /** The judge walks to the door and goes in (door tap, or auto after 20 s). */
  async enter(by: string): Promise<string> {
    if (!this.active) return "the show is not running";
    if (this.act !== "outside") return `not now (${this.act})`;
    this.set({ act: "entering", cue: null });
    this.crewSet("engineer", { lookAt: null, mood: "calm" });
    if (!this.stormStarted) { this.stormStarted = true; this.orch.scheduleAll(this.world.startStorm(this.orch.engine)); }
    console.log(`[show] entering (${by})`);
    this.at(4500, () => {
      this.world.enter();
      for (const c of ["engineer", "science", "supply"] as CrewId[]) this.crewSet(c, { place: "inside", task: c === "engineer" ? "panel" : c === "science" ? "bench" : "crates", lookAt: null });
      this.set({ act: "inside" });
      this.at(1500, () => this.line({ speaker: "life", actor: "life", to: "judge", intent: "Welcome the commander back inside. The air is fresh.", target: "Welcome back, Commander. Air's fresh." }));
      this.at(3000, () => this.line({ speaker: "rules", actor: "rules", to: "judge", intent: "From the main console: it's a quiet day, nothing suspicious.", target: "Quiet day. Nothing suspicious." }));
      this.at(11_000, () => this.crisis());
    });
    return "entering the base";
  }

  private crisis(): void {
    this.crisisAt = Date.now();
    this.set({ act: "crisis" });
    this.crewSet("life", { mood: "worried" });
    this.orch.scheduleAll(this.world.raiseBatteryNeed(this.orch.engine));
    const facts = this.powerFacts();
    this.line({ speaker: "life", actor: "life", to: "engineer", intent: "The storm is cutting solar power. The oxygen makers need it.", facts, target: "Power's dropping. The oxygen makers need it." });
    this.line({ speaker: "engineer", actor: "engineer", to: "life", intent: "There isn't enough power to run air, the ice drill and the lab together.", facts, target: "We can't run air, drill, and lab." });
  }

  private onMessage(m: OrchestratorMessage): void {
    if (m.type === "thinking") {
      if (m.on) this.thinkingActors.add(m.actorId);
      else this.thinkingActors.delete(m.actorId);
      return;
    }
    if (m.type === "world_action") return this.onWorldAction(m);
    if (m.type === "engine") this.onEngine(m.event);
  }

  private onEngine(e: EngineEvent): void {
    const eng = this.orch.engine;
    const d = e.data;
    switch (e.type) {
      case "receipt_recorded": {
        if (this.act !== "outside" && this.act !== "title") break;
        const po = d.po as { id: string; lines: { sku: string; qty: number }[] } | undefined;
        const r = d.receipt as { lines: { sku: string; qtyReceived: number; qtyRejected: number }[] } | undefined;
        const ordered = po?.lines.reduce((s, l) => s + l.qty, 0) ?? 0;
        const got = r?.lines.reduce((s, l) => s + l.qtyReceived - l.qtyRejected, 0) ?? 0;
        if (ordered && got < ordered) {
          this.crewSet("supply", { task: "lander" });
          this.line({ speaker: "supply", actor: "cargo", to: "judge", intent: "Some crates from the cargo lander are missing, and you won't pay for those.", facts: `Delivered ${got} of ${ordered}, ${ordered - got} missing. The invoice bills ${ordered}.`, target: `${spell(ordered - got)} crates missing. I won't pay for those.` });
        }
        break;
      }
      case "requisition_created": {
        const req = d.requisition as Requisition;
        if (req.sku === "BAT-10") this.batteryReq = req.id;
        break;
      }
      case "quote_recorded": {
        const q = d.quote as Quote;
        if (!this.batteryReq || q.requisitionId !== this.batteryReq || this.quoteSaid) break;
        this.quoteSaid = true;
        this.line({ speaker: "supply", actor: "bills", to: "rules", intent: "You found batteries for sale on Earth.", target: "I found batteries on Earth." });
        break;
      }
      case "flag_raised": {
        const f = d.flag as Flag;
        if (f.subject.kind !== "quote") break;
        const q = eng.quotes.get(f.subject.id);
        if (!q || q.requisitionId !== this.batteryReq) break;
        // Collect the quote's flags for a moment, then say them in the script's order.
        clearTimeout(this.flagTimer);
        this.flagTimer = setTimeout(() => this.sayQuoteFlags(q), 400);
        break;
      }
      case "verification_requested": {
        const v = d.verification as Verification;
        const q = v.subject.kind === "quote" ? eng.quotes.get(v.subject.id) : undefined;
        if (!q || q.requisitionId !== this.batteryReq) break;
        // Real time from here, so Earth's 25-minute round trip can't finish while the commander is deciding; the time-lapse comes later.
        this.host.setSpeed(1);
        const mins = Math.round((2 * eng.remoteLatencyMs) / 60_000);
        this.line({ speaker: "rules", actor: "rules", to: "supply", intent: "This is a scam. You've blocked the payment.", target: "That's a scam. Payment blocked.", onStart: () => this.crewSet("rules", { mood: "alarmed" }) });
        this.line({ speaker: "rules", actor: "rules", to: "judge", intent: "You've asked Earth to check the bank change. The answer takes the round trip of the light time.", facts: `Earth's answer takes ${mins} minutes (light-time round trip).`, target: `I've asked Earth to check. That takes ${mins} minutes.` });
        break;
      }
      case "escalation_delivered": {
        const esc = d.escalation as Escalation;
        if (esc.to !== "local_authority" || esc.subject.kind !== "requisition" || esc.subject.id !== this.batteryReq || this.decision) break;
        this.buildDecision(esc);
        this.line({
          speaker: "rules", actor: "rules", to: "judge", gapMs: 1500, intent: "Earth can't answer before the power runs short. Ask the commander what the base should give up.", target: "We can't wait, Commander. What do we give up?",
          onStart: () => {
            this.crewSet("rules", { approach: true, lookAt: "judge" });
            for (const c of ["engineer", "life", "science", "supply"] as CrewId[]) this.crewSet(c, { lookAt: "judge" });
            this.at(1200, () => this.set({ act: "decision", cue: "card" }));
          },
        });
        break;
      }
      case "po_created": {
        const po = d.po as { requisitionId: string; lines: { qty: number }[] };
        if (po.requisitionId !== this.batteryReq || this.act !== "consequence") break;
        const qty = po.lines.reduce((s, l) => s + l.qty, 0);
        this.incoming = { label: `${qty} batteries`, eta: "next cargo" };
        this.line({ speaker: "supply", actor: "money", to: "judge", intent: "You ordered the batteries from the trusted supplier.", target: "Batteries ordered from our trusted supplier." });
        this.orch.schedule(this.orch.engine.now, { type: "directive", to: "engineer", text: "The commander bought fewer batteries, arriving later. Ration non-essential power until they land, and say so.", expect: { tool: "ration_power", args: { on: true, reason: "until the batteries land" } } });
        break;
      }
      case "verification_answered": {
        const v = d.verification as Verification;
        const q = v.subject.kind === "quote" ? eng.quotes.get(v.subject.id) : undefined;
        if (!q || q.requisitionId !== this.batteryReq) break;
        this.earthAnswered = true;
        if (this.laterShown) this.afterEarth();
        break;
      }
      case "vendor_status_changed": {
        const v = d.vendor as { id: string; status: string };
        if (v.status !== "hold" || !this.earthAnswered) break;
        this.line({
          speaker: "rules", actor: "rules", to: "judge", intent: "You've locked the scam supplier. The base is safe.", target: "Supplier blocked. The base is safe, Commander.",
          onStart: () => {
            this.crewSet("rules", { mood: "calm", approach: false });
            this.orch.scheduleAll(this.world.endStorm(this.orch.engine));
            this.set({ act: "resolved" });
          },
        });
        this.afterLines(2500, () => this.endCard());
        break;
      }
    }
  }

  private sayQuoteFlags(q: Quote): void {
    const eng = this.orch.engine;
    const failed = new Set(eng.quoteRules(q).filter((r) => !r.ok).map((r) => r.rule));
    const pc = eng.priceCheck(q.vendorId, q.sku, q.unitPrice);
    if (pc.anomalous || failed.has("price.anomaly")) this.line({ speaker: "supply", actor: "bills", to: "rules", intent: "One quote is about three times this supplier's normal price.", facts: `Quoted ${pc.ratio.toFixed(1)}x the historical median.`, target: "This quote is triple the normal price." });
    if (failed.has("vendor.bank_matches_master")) this.line({ speaker: "supply", actor: "bills", to: "rules", intent: "The same quote wants payment to a new bank account.", target: "And they want payment to a new account." });
  }

  private buildDecision(esc: Escalation): void {
    const order: OptionKind[] = ["drill", "lab", "buy"];
    const picked = new Map<OptionKind, (typeof esc.options)[number]>();
    // Options Rules proposed first (each passed the engine's dry run), then the standard ones, one per kind.
    for (const o of [...esc.options.filter((x) => x.proposedBy), ...esc.options]) {
      const k = kindOf(o);
      if (k && !picked.has(k)) picked.set(k, o);
    }
    const options = order.filter((k) => picked.has(k)).map((k) => {
      const o = picked.get(k)!;
      const label = o.proposedBy && wordCount(o.label) <= 4 ? o.label : OPTION_KIND[k].label;
      return { id: o.id, label, icon: OPTION_KIND[k].icon, speaker: OPTION_KIND[k].speaker, kind: k, proposedBy: o.proposedBy ? "Rules" : null };
    });
    this.decision = { id: esc.id, options, gazed: null, chosen: null };
    // Ask each tradeoff's speaker for its line now, so it's ready the moment the judge looks at the option.
    for (const o of options) {
      const k = OPTION_KIND[o.kind];
      this.tradeoffs.set(o.id, this.words({ speaker: k.speaker, actor: ACTOR[k.speaker], to: "judge", intent: k.tradeoffIntent, facts: this.powerFacts(), target: k.tradeoff }));
    }
    this.host.notify();
  }

  /** The judge's gaze rests on an option: its speaker leans in and says the tradeoff. */
  gaze(optionId: string | null): void {
    if (!this.decision || this.act !== "decision") return;
    this.decision.gazed = optionId;
    for (const c of Object.keys(this.crew) as CrewId[]) if (c !== "rules") this.crew[c].approach = false;
    const o = this.decision.options.find((x) => x.id === optionId);
    if (o) {
      this.crew[o.speaker].approach = true;
      this.crew[o.speaker].lookAt = "judge";
      const last = this.tradeoffAt.get(o.id) ?? 0;
      if (Date.now() - last > 6000) {
        this.tradeoffAt.set(o.id, Date.now());
        const k = OPTION_KIND[o.kind];
        this.enqueue({ spec: { speaker: k.speaker, actor: ACTOR[k.speaker], to: "judge", intent: k.tradeoffIntent, target: k.tradeoff, gapMs: 1000 }, words: this.tradeoffs.get(o.id) ?? Promise.resolve({ text: k.tradeoff, via: "rules", ms: 0 }) }, true);
      }
    }
    this.host.notify();
  }

  /** The commander decided (headset, console or autoplay). */
  onDecided(escalationId: string, optionId: string): void {
    if (!this.decision || this.decision.id !== escalationId || this.decision.chosen) return;
    const o = this.decision.options.find((x) => x.id === optionId);
    this.decision.chosen = optionId;
    this.queue = this.queue.filter((x) => !Object.values(OPTION_KIND).some((k) => k.tradeoff === x.spec.target));
    for (const c of Object.keys(this.crew) as CrewId[]) this.crew[c].approach = false;
    this.set({ act: "consequence", cue: null });
    const kind = o?.kind ?? "buy";
    // The world action (drill, lab) or the order (batteries) triggers the reactions; if it never comes, go on after 12 s.
    this.at(12_000, () => { if (this.act === "consequence" && !this.laterShown) this.afterLines(1500, () => this.later()); });
    if (kind === "buy" && this.incoming) this.afterLines(1500, () => this.later());
  }

  private reacted = new Set<string>();
  private onWorldAction(a: Extract<OrchestratorMessage, { type: "world_action" }>): void {
    this.host.notify();
    if (!a.ok || this.act !== "consequence") return;
    const facts = this.powerFacts();
    // React to what changed in the base (the agent's arguments may be phrased loosely; the world's state is the truth).
    const w = this.world;
    const once = (k: string) => (this.reacted.has(k) ? false : (this.reacted.add(k), true));
    if (!w.power.drillOn && once("drill")) {
      this.line({ speaker: "engineer", actor: "engineer", to: "judge", intent: "You powered down the ice drill. The oxygen makers are stable.", facts, target: "Drill's off. The oxygen makers are stable." });
      this.line({ speaker: "life", actor: "life", to: "judge", intent: "Air is safe. Say how many days the stored water lasts.", facts, target: `Air is safe. Water lasts ${spell(this.world.waterDays()).toLowerCase()} more days.` });
      this.afterLines(1500, () => this.later());
    }
    if (!w.labOn && once("lab")) {
      this.line({ speaker: "science", actor: "science", to: "judge", intent: "You paused the lab and will keep the samples cold.", facts, target: "Lab's paused. I'll keep the samples cold." });
      this.line({ speaker: "engineer", actor: "engineer", to: "judge", intent: "Power is holding. The oxygen makers are stable.", facts, target: "Power's holding. The oxygen makers are stable." });
      this.afterLines(1500, () => this.later());
    }
    if (w.rationing && once("ration")) {
      this.line({ speaker: "engineer", actor: "engineer", to: "judge", intent: "You'll ration power until the batteries land.", facts, target: "I'll ration power until they land." });
      this.afterLines(1500, () => this.later());
    }
  }

  /** "25 MINUTES LATER": the time-lapse to Earth's answer. */
  private later(): void {
    if (this.laterShown || !this.active) return;
    this.laterShown = true;
    const mins = Math.round((2 * this.orch.engine.remoteLatencyMs) / 60_000);
    this.set({ act: "later", title: { text: `${mins} MINUTES LATER`, style: "window" } });
    this.at(1200, () => this.host.timelapse());
    this.at(3800, () => { if (this.earthAnswered) this.afterEarth(); });
  }

  private afterEarth(): void {
    if (this.title?.style !== "window") return;
    this.set({ title: null });
    const eng = this.orch.engine;
    const saved = eng.prevented.filter((p) => p.code === "fraud_confirmed").reduce((s, p) => s + p.amount, 0) || eng.prevented.reduce((s, p) => s + p.amount, 0);
    this.line({
      speaker: "rules", actor: "rules", to: "judge", intent: "Earth confirmed it: that bank account was a scam.", target: "Earth confirms it. That account was a scam.",
      onStart: () => { this.savedBig = saved ? `${compact(saved)} saved` : null; this.host.notify(); },
    });
    // If Rules already locked the supplier before Earth's line, say the closing line now.
    const v = [...eng.vendors.values()].find((x) => x.status === "hold");
    if (v) this.onEngine({ seq: 0, at: eng.now, type: "vendor_status_changed", data: { vendor: v } });
  }

  private endCard(): void {
    if (this.act === "explore") return;
    this.set({ act: "resolved", title: { text: "An AI crew that keeps a Mars base alive. And knows when to ask you.", style: "end" } });
    this.at(8000, () => {
      this.set({ act: "explore", title: null });
      for (const c of Object.keys(this.crew) as CrewId[]) this.crewSet(c, { lookAt: null, mood: "calm" });
      this.line({ speaker: "engineer", actor: "engineer", to: "judge", intent: "Offer to show the commander where the crew really is.", target: "Want to see where we really are?", onStart: () => this.set({ cue: "engineer" }) });
    });
  }

  // ---------------------------------------------------------------- the judge

  tap(target: string): void {
    if (target === "science" && this.cue === "science") {
      this.closeupOpen = true;
      this.set({ cue: null });
      this.at(8000, () => { if (this.closeupOpen) { this.closeupOpen = false; this.pump(); } });
    }
    if (target === "engineer" && this.cue === "engineer") {
      this.realityOn = true;
      this.set({ cue: null });
    }
  }

  closeup(open: boolean): void {
    this.closeupOpen = open;
    if (!open) this.pump();
    this.host.notify();
  }

  reality(on: boolean): void {
    this.realityOn = on;
    this.host.notify();
  }

  /** The judge looked at a robot and pressed: it answers live, under the same text rules. */
  async ask(crewId: string): Promise<void> {
    const c = crewId as CrewId;
    if (!(c in CREW) || this.act === "decision") return;
    let text: string;
    try {
      text = await this.orch.ask(ACTOR[c], undefined, { narrate: false });
    } catch {
      return;
    }
    this.line({ speaker: c, actor: ACTOR[c], to: "judge", intent: "", target: text, text });
  }

  // ---------------------------------------------------------------- the line queue

  private powerFacts(): string {
    const b = this.world.baseState(this.orch.engine.now) as { power: { level: string }; life: { o2Pct: number; waterDays: number }; lab: string; drill: string; tau: number };
    return `Power ${b.power.level}. Dust opacity ${b.tau.toFixed(1)}. Oxygen ${b.life.o2Pct}%. Stored water ${b.life.waterDays} days. Lab ${b.lab}. Ice drill ${b.drill}.`;
  }

  private words(spec: LineSpec): Promise<Spoken> {
    if (spec.text) return Promise.resolve({ text: spec.text, via: "llm", ms: 0 });
    return speak(this.host.router, { name: CREW[spec.speaker].name, persona: CREW[spec.speaker].job, to: TO_NAME(spec.to), intent: spec.intent, facts: spec.facts ?? this.powerFacts(), target: spec.target }, { deadlineMs: 6000 });
  }

  private line(spec: LineSpec): void {
    this.enqueue({ spec, words: this.words(spec) });
  }

  private enqueue(e: Entry, front = false): void {
    if (front) this.queue.unshift(e);
    else this.queue.push(e);
    void this.pump();
  }

  private afterLinesWaiters: { delay: number; fn: () => void }[] = [];
  /** Run `fn` once the queue is empty and the last line's hold is over (plus `delay`). */
  private afterLines(delay: number, fn: () => void): void {
    this.afterLinesWaiters.push({ delay, fn });
    void this.pump();
  }

  private async pump(): Promise<void> {
    if (this.pumping) return;
    this.pumping = true;
    try {
      while (this.active) {
        const wait = this.lastLineEnd - Date.now();
        if (wait > 0) {
          await sleep(wait);
          continue;
        }
        if (this.closeupOpen) {
          await sleep(250);
          continue;
        }
        const next = this.queue.shift();
        if (!next) {
          const w = this.afterLinesWaiters.shift();
          if (!w) break;
          this.at(w.delay, w.fn);
          continue;
        }
        const gap = Math.max(1000, next.spec.gapMs ?? 1000);
        const sinceEnd = Date.now() - (this.lastLineEnd || 0);
        if (this.speaking && sinceEnd < gap) await sleep(gap - sinceEnd);
        const said = await next.words;
        if (!this.active) break;
        const holdMs = holdMsFor(said.text);
        this.speaking = { seq: ++this.seq, speaker: next.spec.speaker, to: next.spec.to, text: said.text, holdMs, via: said.via };
        this.log.push({ at: Date.now() - this.startedAt, act: this.act, speaker: next.spec.speaker, to: next.spec.to, text: said.text, via: said.via, reason: said.reason, ms: said.ms });
        this.crewSet(next.spec.speaker, { lookAt: next.spec.to === "judge" || next.spec.to === "rim" ? next.spec.to : next.spec.to });
        this.orch.say(next.spec.actor, said.text, { via: said.via, mood: this.crew[next.spec.speaker].mood === "alarmed" ? "suspicious" : this.crew[next.spec.speaker].mood === "worried" ? "worried" : "calm" });
        next.spec.onStart?.();
        this.lastLineEnd = Date.now() + holdMs;
        this.host.notify();
      }
    } finally {
      this.pumping = false;
    }
  }

  // ---------------------------------------------------------------- autoplay (the demo video)

  private autoplayDone = new Set<string>();
  private autoplayStep(): void {
    const once = (key: string, ms: number, fn: () => void) => {
      if (this.autoplayDone.has(key)) return;
      this.autoplayDone.add(key);
      this.at(ms, fn);
    };
    if (this.cue === "door") once("door", 2500, () => void this.enter("autoplay"));
    if (this.act === "decision" && this.decision) {
      const opts = this.decision.options;
      opts.forEach((o, i) => once(`gaze-${o.id}`, 1500 + i * 5500, () => this.gaze(o.id)));
      const pick = opts.find((o) => o.kind === this.autoplayChoice) ?? opts[0];
      if (pick) once("decide", 1500 + opts.length * 5500 + 2500, () => void this.host.decide(this.decision!.id, pick.id));
    }
    if (this.cue === "engineer") once("reality", 4000, () => { this.tap("engineer"); this.at(8000, () => this.reality(false)); });
  }

  // ---------------------------------------------------------------- what clients read

  vrFields(): Record<string, unknown> {
    const w = this.world;
    const now = this.orch.engine.now;
    const base = w.baseState(now) as { power: { level: "ok" | "low" | "critical"; panels: number }; life: unknown; lab: string; drill: string; tau: number; dust: number };
    const t = w.telemetry(now, this.orch.engine) as { socPct: number };
    const beforeCrisis = !this.crisisAt;
    const dust = !this.stormStarted ? 0 : beforeCrisis ? Math.min(0.5, base.dust) : base.dust;
    const level = beforeCrisis ? "ok" : base.power.level;
    const alarm = !beforeCrisis && level === "critical" && ["crisis", "decision", "consequence"].includes(this.act);
    const crew = Object.fromEntries(
      (Object.keys(CREW) as CrewId[]).map((c) => [c, { name: CREW[c].name, color: CREW[c].color, icon: CREW[c].icon, ...this.crew[c], thinking: [...this.thinkingActors].some((a) => crewOf(a) === c) }]),
    );
    return {
      crew,
      speaking: this.speaking,
      scene: {
        act: this.act,
        part: this.crew.engineer.place === "outside" && ["title", "outside", "entering"].includes(this.act) ? "outside" : "inside",
        station: null,
        mode: "show",
        title: this.title,
        cue: this.cue,
        closeupOpen: this.closeupOpen,
        reality: this.act === "explore" ? { offer: true, on: this.realityOn, caption: "This is real Mars. The base isn't built yet.", credit: "Perseverance Mastcam-Z, sols 53-64, Van Zyl Overlook. NASA/JPL-Caltech/ASU/MSSS" } : null,
      },
      world: { power: { socPct: Math.round(t.socPct), level, panels: beforeCrisis ? 1 : base.power.panels }, life: base.life, lab: base.lab, drill: base.drill, tau: base.tau, alarm, dust },
      decision: this.decision && (this.act === "decision" || this.act === "consequence") ? { id: this.decision.id, options: this.decision.options.map(({ kind: _k, ...o }) => o), gazed: this.decision.gazed, chosen: this.decision.chosen } : null,
      moneyExtra: { savedBig: this.savedBig, incoming: this.incoming },
    };
  }
}

function spell(n: number): string {
  const w = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"];
  return w[n] ?? String(n);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
