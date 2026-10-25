import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import http from "node:http";
import { networkInterfaces } from "node:os";
import { randomBytes } from "node:crypto";
import { dirname, extname, join, normalize } from "node:path";
import { WebSocketServer, type WebSocket } from "ws";
import { ApWithReader, ControllerRules, DirectiveRules, keywordRoute, EscalationDrafter, LlmBrain, llmRoute, ModelRouter, OllamaProvider, OpenAIProvider, Orchestrator, ReceiverRules, ReportRules, RequesterRules, RogueBrain, TreasuryRules, type AgentMode, type Brain, type LlmProvider, type Narration, type OrchestratorMessage } from "@ares/agents";
import { formatCents, RULE_LABELS, type AgentRole, type Escalation, type Policy } from "@ares/engine";
import { runEval } from "@ares/eval";
import { CREW, MarsWorld, SCIENCE_REF } from "@ares/world-mars";
import { Show } from "./show.ts";

// Optional repo-root .env (e.g. OPENAI_API_KEY); real environment variables win.
const ENV_FILE = new URL("../../../.env", import.meta.url).pathname;
if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE);

const PORT = Number(process.env.PORT ?? 8787);

/**
 * Access control. The console and every control API are for this Mac only (loopback).
 * The headset authenticates with a per-machine token that scripts/build-ios.sh bakes into
 * the app; it may only decide as the on-site commander and upload frames.
 */
const TOKEN_FILE = new URL("../../../.cache/headset-token", import.meta.url).pathname;
const HEADSET_TOKEN = (() => {
  if (existsSync(TOKEN_FILE)) return readFileSync(TOKEN_FILE, "utf8").trim();
  const t = randomBytes(16).toString("hex");
  mkdirSync(dirname(TOKEN_FILE), { recursive: true });
  writeFileSync(TOKEN_FILE, t);
  return t;
})();
const isLoopback = (a?: string) => a === "127.0.0.1" || a === "::1" || a === "::ffff:127.0.0.1";
const PACE_MS = Number(process.env.ARES_PACE_MS ?? 2200);
const BASE_SPEED = Number(process.env.ARES_SPEED ?? 120);
const CONSOLE_DIR = new URL("../../console/dist/", import.meta.url).pathname;
/**
 * Model layers: local (Ollama, offline) -> cloud (OpenAI, when a key is set and we're online) -> rules.
 * ARES_LOCAL_MODEL=off disables the local layer; ARES_AGENT_MODE=rules is safe mode from the start;
 * ARES_LLM_ROLES limits which roles reason with a model (default: all five).
 */
const CACHE_DIR = new URL("../../../.cache/llm/", import.meta.url).pathname;
const LOCAL_MODEL = process.env.ARES_LOCAL_MODEL ?? "qwen3.5:9b";
const localProvider = LOCAL_MODEL === "off" ? undefined : new OllamaProvider(LOCAL_MODEL);
const localUp = localProvider ? await localProvider.available() : { up: false, hasModel: false };
const cloudProvider = process.env.OPENAI_API_KEY ? new OpenAIProvider(process.env.OPENAI_API_KEY) : undefined;
const router = new ModelRouter(localUp.up && localUp.hasModel ? localProvider : undefined, cloudProvider, CACHE_DIR);
router.mode = (["auto", "local", "cloud", "rules"] as AgentMode[]).find((m) => m === process.env.ARES_AGENT_MODE) ?? "auto";
const LLM: LlmProvider | undefined = router.local || router.cloud ? router : undefined;
const LLM_ROLES = (process.env.ARES_LLM_ROLES ?? "requester,receiver,ap,treasury,controller,life,science").split(",");
console.log(`LLM layers: local ${router.local ? router.local.model : localProvider ? `none (Ollama ${localUp.up ? `up, model ${LOCAL_MODEL} not pulled` : "not running"})` : "off"}; cloud ${router.cloud ? router.cloud.model : "none"}; mode ${router.mode}`);
if (router.local && localProvider) void localProvider.prewarm().then(() => console.log("local model warm"), (e: Error) => console.log(`local model prewarm failed: ${e.message}`));
/** Demo switch: replace Rules' brain with a malicious one; policy must hold. */
let rogueController = false;
const brains = (): Brain[] => {
  const rules: Record<AgentRole, Brain> = {
    requester: new RequesterRules(),
    receiver: new ReceiverRules(),
    ap: new ApWithReader(LLM),
    treasury: new TreasuryRules(),
    controller: rogueController ? new RogueBrain("controller", new ControllerRules()) : new ControllerRules(),
  };
  // The crew's personas: who speaks for each engine role (Supply is one face for receiving, bills and payments).
  const persona: Record<AgentRole, string> = {
    requester: `Engineer (blue, wrench): ${CREW.engineer.job}. You request purchases the base needs.`,
    receiver: "Supply (orange, box), receiving: you count what physically arrived and record it.",
    ap: "Supply (orange, box), checking bills: you enter quotes and invoices and propose what should be paid after the match.",
    treasury: "Supply (orange, box), paying: you check affordability and schedule approved payments to verified accounts. When an invoice is approved, you schedule it: a line alone leaves the supplier unpaid.",
    controller: `Rules (purple, shield): ${CREW.rules.job}. When a submitted invoice passed its match, you approve it: a line alone leaves it stuck.`,
  };
  const list: Brain[] = [];
  for (const role of Object.keys(rules) as AgentRole[]) {
    const useLlm = !!LLM && LLM_ROLES.includes(role) && !(role === "controller" && rogueController);
    list.push(useLlm ? new LlmBrain({ role, actorId: role === "requester" ? "engineer" : undefined, persona: persona[role], rules: rules[role], router }) : rules[role]);
    if (!useLlm) list.push(new ReportRules(role)); // reports still reach the commander without a model
    if (!useLlm && role === "requester") list.push(new DirectiveRules("requester", "engineer"));
  }
  // Life and Science: world agents (life support, the lab) that can also request purchases.
  for (const id of ["life", "science"] as const) {
    const p = `${CREW[id].name} (${id === "life" ? "white, droplet" : "green, microscope"}): ${CREW[id].job}. You act on the base with your own tools and can request purchases.`;
    if (LLM && LLM_ROLES.includes(id)) list.push(new LlmBrain({ role: "requester", actorId: id, persona: p, rules: new DirectiveRules("requester", id), router }));
    else list.push(new DirectiveRules("requester", id), new ReportRules("requester", id));
  }
  list.push(new EscalationDrafter(LLM));
  return list;
};

/** Policy edited by the policy owner in the console; survives resets. */
let policyOverride: Policy | undefined;

/** One running scenario: a world, its engine and agents, and a real-time clock. */
class Session {
  world: MarsWorld;
  orch: Orchestrator;
  simNow: number;
  speed = BASE_SPEED;
  paused = false;
  lastTelemetry: Record<string, unknown> = {};
  /** Roles whose LLM brain is deciding right now (shown as "thinking" in the headset and spectator). */
  readonly thinking = new Set<string>();
  /** The experience (docs/demo/script.md): the four acts, the line queue, the decision card. */
  readonly show: Show;
  /** Part 1 pacing: `free` = the judge picks stations (the headset sends `vr_station`); `auto` = the director's fixed order. */
  roam: "free" | "auto" | undefined;
  roamStartedAt = 0;
  readonly startedAt = Date.now();
  /** Real time at which to drop out of a time-lapse. */
  private timelapseUntilAnswer = false;

  readonly seed: string;
  readonly paceMs: number;

  constructor(seed: string, paceMs: number) {
    this.seed = seed;
    this.paceMs = paceMs;
    // A policy edited in the console carries over to every new run until restored.
    this.world = new MarsWorld({ seed, mode: "demo", policy: policyOverride });
    this.orch = new Orchestrator({ world: this.world, brains: brains(), fmtTime: this.world.fmtTime, paceMs: 0, routeReport: LLM ? llmRoute(router, 6000, true) : (t: string) => keywordRoute(t, true) });
    this.simNow = this.world.start - 32 * 86_400_000;
    const self = this;
    this.show = new Show({
      orch: () => self.orch,
      world: () => self.world,
      router: LLM ? router : undefined,
      // Before the server's module finishes initializing (the first prepare()), there is nobody to notify yet.
      notify: () => { try { scheduleVrState(); } catch { /* not ready yet */ } },
      setSpeed: (x) => { self.speed = x; },
      baseSpeed: BASE_SPEED,
      timelapse: () => self.timelapse(),
      decide: (escalationId, optionId) => decideAsCommander(escalationId, optionId, "autoplay"),
    });
  }

  /** Runs the prologue instantly (no pacing), then enables pacing for the live part. */
  async prepare(): Promise<void> {
    this.show.reset();
    // The prologue is the pre-story history: rules only, so a reset takes milliseconds, not minutes of model calls.
    const mode = router.mode;
    router.mode = "rules";
    try {
      await this.orch.runUntil(this.world.start);
    } finally {
      router.mode = mode;
    }
    this.simNow = this.world.start;
    this.orch.setPace(this.paceMs);
  }

  async tick(realDtMs: number): Promise<void> {
    if (this.paused || this.orch.isBusy) return;
    this.simNow = Math.max(this.simNow, this.orch.engine.now) + realDtMs * this.speed;
    await this.orch.runUntil(this.simNow);
    if (this.timelapseUntilAnswer && [...this.orch.engine.verifications.values()].every((v) => v.status !== "pending")) {
      this.timelapseUntilAnswer = false;
      this.speed = BASE_SPEED;
    }
  }

  timelapse(): void {
    this.timelapseUntilAnswer = true;
    this.speed = 2400;
  }

  get isTimelapse(): boolean {
    return this.timelapseUntilAnswer;
  }
}

let session = new Session(process.env.ARES_SEED ?? "ares-demo", PACE_MS);
await session.prepare();
/** Warm the local model's prompt-prefix cache for every agent decision point, one call at a time, off the critical path. */
function warmLocal(s: Session): void {
  if (!router.local || process.env.ARES_WARMUP === "off") return;
  void (async () => {
    const t0 = Date.now();
    for (const b of s.orch.brainList) {
      if (!(b instanceof LlmBrain)) continue;
      const self = [...s.orch.engine.actors.values()].find((a) => a.role === b.role);
      if (self) await b.warmup({ engine: s.orch.engine, self, fmtTime: s.world.fmtTime, itemName: (sku) => s.orch.engine.items.get(sku)?.name ?? sku });
    }
    console.log(`local prefix warm-up done in ${((Date.now() - t0) / 1000).toFixed(0)} s`);
  })();
}
warmLocal(session);
const clients = new Set<WebSocket>();
/** Headset sockets get only what the headset needs (small messages, no engine firehose). */
const vrClients = new WeakSet<WebSocket>();
/** The Mac's spectator view: loopback only, read-only. */
const spectatorClients = new WeakSet<WebSocket>();
/** Token-authenticated headsets; only the newest one's head pose is relayed to spectators. */
const headsets = new Set<WebSocket>();
let activeHeadset: WebSocket | undefined;
let vrStats: Record<string, unknown> = {};
let spectatorStats: Record<string, unknown> = {};
let recDir: string | undefined;
let recSeq = 0;
let recFps = 12;
let unsubscribe = wire(session);

function wire(s: Session): () => void {
  return s.orch.on((m: OrchestratorMessage) => {
    if (m.type === "thinking") {
      if (m.on) s.thinking.add(m.role);
      else s.thinking.delete(m.role);
      broadcast({ type: "thinking", role: m.role, actorId: m.actorId, on: m.on });
      scheduleVrState();
      return;
    }
    if (m.type === "telemetry") s.lastTelemetry = m.data;
    broadcast({ type: m.type, ...(m.type === "engine" ? { event: m.event } : m.type === "narration" ? { narration: m.narration } : m.type === "world_action" ? { action: m } : { at: m.at, data: m.data }) });
    scheduleVrState();
  });
}

const VR_TYPES = new Set(["vr_state", "capture", "reset", "record", "recenter", "scan_viewer", "force_replay", "thinking", "scene"]);
const SPECTATOR_TYPES = new Set(["vr_state", "narration", "reset", "headset", "vr_choice", "spectator_capture", "thinking", "scene"]);
function broadcast(msg: { type: string; [k: string]: unknown }): void {
  const text = JSON.stringify(msg);
  for (const c of clients) {
    if (c.readyState !== 1) continue;
    if (vrClients.has(c) && !VR_TYPES.has(msg.type)) continue;
    if (spectatorClients.has(c) && !SPECTATOR_TYPES.has(msg.type)) continue;
    if (!vrClients.has(c) && !spectatorClients.has(c) && msg.type === "spectator_capture") continue;
    c.send(text);
  }
}

/** Raw frames straight to the spectators (the head pose, 30+ times a second). */
function toSpectators(text: string): void {
  for (const c of clients) if (c.readyState === 1 && spectatorClients.has(c)) c.send(text);
}

function headsetStatus() {
  return { type: "headset", connected: [...headsets].some((h) => h.readyState === 1) };
}

/** What the commander chose, for the spectator's decision card. */
function announceChoice(escalationId: string, optionId: string, by: string, verdict: string): void {
  const label = session.orch.engine.escalations.get(escalationId)?.options.find((o) => o.id === optionId)?.label ?? optionId;
  broadcast({ type: "vr_choice", escalationId, optionId, label, by, verdict });
}

/** A pose message: unit quaternion `q` [x, y, z, w], optional gazed card index. Anything else is dropped. */
function validPose(m: Record<string, unknown>): boolean {
  const q = m.q;
  return Array.isArray(q) && q.length === 4 && q.every((x) => typeof x === "number" && Number.isFinite(x) && Math.abs(x) <= 1.001);
}

let vrStateTimer: NodeJS.Timeout | undefined;
function scheduleVrState(): void {
  if (vrStateTimer) return;
  vrStateTimer = setTimeout(() => {
    vrStateTimer = undefined;
    try {
      broadcast({ type: "vr_state", state: vrState() });
    } catch (err) {
      console.error("vr_state failed", err);
    }
  }, 150);
}

/** Compact state for the headset: three wall screens, five robots, the decision panel, the window. */
/** Development only (loopback): fields merged over the live vr_state so the scene can be built before the server drives them. */
let devPatch: Record<string, unknown> = {};

function vrState() {
  return { ...vrStateLive(), ...devPatch };
}

function vrStateLive() {
  const s = session;
  const e = s.orch.engine;
  const t = s.world.telemetry(e.now, e);
  const robots: Record<string, Narration | undefined> = {};
  for (const n of s.orch.narration) robots[n.role] = n;
  const waiting = [...e.escalations.values()]
    .filter((x) => x.status === "awaiting_decision" && x.to === "local_authority")
    .map((x: Escalation) => ({ id: x.id, reason: x.reason, decideBy: x.decideBy, decideByText: x.decideBy ? s.world.fmtTime(x.decideBy) : null, options: x.options.map((o) => ({ id: o.id, label: o.label, detail: o.detail, proposedBy: o.proposedBy ? (e.actors.get(o.proposedBy)?.displayName ?? o.proposedBy) : null })) }));
  const pendingVer = [...e.verifications.values()].filter((v) => v.status === "pending");
  const payments = [...e.payments.values()].filter((p) => p.status === "sent").slice(-4).reverse().map((p) => ({ id: p.id, vendor: e.vendors.get(p.vendorId)?.name, amount: p.amount, amountText: formatCents(p.amount) }));
  const base = {
    seed: s.seed,
    policyVersion: e.policy.version,
    beat: s.world.beat,
    storyBeat: s.world.storyBeat(e),
    storyBeats: 7,
    thinking: [...s.thinking],
    agentMode: router.mode,
    /** Two-part demo: where the judge is and which outdoor station the story is at; the scientist's real reference image. */
    scene: { part: s.world.part, station: s.world.station ?? null, mode: s.roam ?? null, visited: [...s.world.visited], science: SCIENCE_REF },
    timelapse: s.isTimelapse,
    time: s.world.fmtTime(e.now),
    sol: t.sol,
    ltst: t.ltst,
    tau: t.tau,
    sun: t.sun,
    lightTimeMin: t.lightTimeMin,
    power: { socPct: t.socPct, solarKWhPerSol: t.solarKWhPerSol, loadKWhPerSol: t.loadKWhPerSol, solsLeft: t.solsLeft, drillOn: t.drillOn },
    money: {
      cash: e.ledger.balance("cash"),
      cashText: formatCents(e.ledger.balance("cash")),
      runwayDays: Math.floor(e.runwayDays()),
      committedText: formatCents(e.openCommitments()),
      savedText: formatCents(e.prevented.reduce((a, b) => a + b.amount, 0)),
      payments,
    },
    waiting,
    earth: pendingVer.map((v) => ({ id: v.id, vendor: e.vendors.get(v.vendorId)?.name, replyEtaText: s.world.fmtTime(e.expectedVerificationReply(v)), replyInMin: Math.max(0, Math.round((e.expectedVerificationReply(v) - e.now) / 60_000)) })),
    robots: Object.fromEntries(Object.entries(robots).map(([role, n]) => [role, n && { name: n.name, text: n.text, short: n.short, mood: n.mood, outcome: n.outcome, seq: n.seq }])),
  };
  // The show (docs/demo/script.md): the crew, the one spoken line, acts/title/cue, the base, the decision card.
  return { ...base, ...showFields(s, base) };
}

function showFields(s: Session, live: Record<string, unknown>): Record<string, unknown> {
  const f = s.show.vrFields() as { moneyExtra: Record<string, unknown>; scene: Record<string, unknown> } & Record<string, unknown>;
  const { moneyExtra, ...rest } = f;
  // While the show runs, the legacy card is off (the show's `decision` is the card) and the scene is the show's.
  return { ...rest, money: { ...(live.money as object), ...moneyExtra }, ...(s.show.active ? { waiting: [] } : { scene: { ...(live.scene as object), ...f.scene, mode: "title" } }) };
}

function fullState() {
  const s = session;
  const e = s.orch.engine;
  return {
    seed: s.seed,
    speed: s.speed,
    paused: s.paused,
    beat: s.world.beat,
    meta: s.orch.meta,
    telemetry: s.world.telemetry(e.now, e),
    snapshot: e.snapshot(),
    narration: s.orch.narration.slice(-300),
    audit: e.audit.all().slice(-400),
    documents: [...e.documents.values()],
    ruleLabels: RULE_LABELS,
    integrity: e.verifyIntegrity(),
    rogueController,
    agentMode: router.mode,
    agents: router.status(),
    thinking: [...s.thinking],
    policyCustom: policyOverride !== undefined,
    headset: { connected: [...clients].filter((c) => vrClients.has(c) && c.readyState === 1).length, stats: vrStats },
    llm: LLM ? `${router.mode}: ${[router.local && `local ${router.local.model}`, router.cloud && `cloud ${router.cloud.model}`].filter(Boolean).join(", ")}` : null,
    vr: vrState(),
  };
}

// ---------------------------------------------------------------- director

/** Free roam: the judge looked at a station marker and pressed. Content runs once per station; the storm interrupts later. */
const ROAM_STORM_AFTER_MS = Number(process.env.ARES_ROAM_STORM_MS ?? 45_000);
async function roamTo(station: string, by: string): Promise<string> {
  const s = session;
  const w = s.world;
  if (w.part !== "outside") return "already inside";
  if (s.roam === "auto") return "the director is driving part 1; stations follow its order";
  if (!(["pad", "science", "solar", "rover"] as const).some((x) => x === station)) return `unknown station ${station}`;
  if (w.station === "door") return "the storm is here: go to the door";
  const st = station as "pad" | "science" | "solar" | "rover";
  if (!s.roam) {
    s.roam = "free";
    s.roamStartedAt = Date.now();
    autoplayTimer.push(setTimeout(() => { if (session === s) void stormInterrupt("timer"); }, ROAM_STORM_AFTER_MS));
  }
  s.orch.scheduleAll(w.visit(st, s.orch.engine));
  broadcast({ type: "scene", part: "outside", station: st, by });
  scheduleVrState();
  console.log(`[scene] station ${st} (${by})`);
  // Seen enough: the three content stations visited, so the storm comes now rather than at the timer.
  if (["pad", "science", "solar"].every((x) => w.visited.has(x))) autoplayTimer.push(setTimeout(() => { if (session === s) void stormInterrupt("seen enough"); }, 6_000));
  return `station ${st}`;
}

/** The storm warning cuts part 1 short wherever the judge is; beat 1 runs in the background if the pad was never visited. */
async function stormInterrupt(by: string): Promise<void> {
  const s = session;
  const w = s.world;
  const e = s.orch.engine;
  if (w.part !== "outside" || w.station === "door") return;
  if (!w.visited.has("pad")) { w.visited.add("pad"); s.orch.scheduleAll(w.beatDelivery(e)); }
  s.orch.scheduleAll(w.beatStormWarning(e));
  s.orch.scheduleAll(w.beatDoor());
  autoplayTimer.push(setTimeout(() => { if (session === s && s.world.part === "outside") void enterBase("auto"); }, 30_000));
  broadcast({ type: "scene", part: "outside", station: "door", by });
  scheduleVrState();
  console.log(`[scene] storm interrupt (${by}) -> door`);
}

/** Part 1 outside on the director's fixed order: pad (beat 1) -> science -> solar (beat 2 starts) -> door -> inside. Part 2 continues with the agents and the commander. */
async function directorNext(): Promise<string> {
  const s = session;
  const e = s.orch.engine;
  const w = s.world;
  if (w.part === "outside") {
    if (!s.roam) s.roam = "auto";
    if (s.roam === "free") {
      // The judge is choosing stations; "next" from the console means: bring the storm now.
      await stormInterrupt("director");
      return "free roam: storm warning now, then the door";
    }
    if (!w.station) {
      s.orch.scheduleAll(w.beatPad(e));
      return "part 1, landing pad: the cargo lander (beat 1: short delivery)";
    }
    if (w.station === "pad") {
      s.orch.scheduleAll(w.beatScience(e));
      return "part 1, science site: sampling the delta rock";
    }
    if (w.station === "science") {
      s.orch.scheduleAll(w.beatSolar(e));
      return "part 1, solar field: panel check, then the storm warning (beat 2)";
    }
    if (w.station === "solar") {
      s.orch.scheduleAll(w.beatDoor());
      // Resilience: if the judge doesn't tap the door, the story goes inside anyway.
      autoplayTimer.push(setTimeout(() => { if (session === s && s.world.part === "outside") void enterBase("auto"); }, 25_000));
      scheduleVrState();
      return "part 1, the door: gaze at the base door and press to go inside (auto in 25 s)";
    }
    return await enterBase("director");
  }
  if (w.beat < 2) {
    s.orch.scheduleAll(w.beatStorm(e));
    return "beat 2: dust storm";
  }
  return "no further scripted beats; the rest is up to the agents and the commander";
}

/** The commander decides (headset, console, or the show's autoplay): the engine checks it, then the show plays the consequence. */
async function decideAsCommander(escalationId: string, optionId: string, by: string): Promise<void> {
  const s = session;
  // The show switches to the consequence first: the crew member may act on the decision before submit returns.
  s.show.onDecided(escalationId, optionId);
  const r = await s.orch.submitHuman("local_authority", { type: "decide", params: { escalationId, optionId }, source: by === "console" ? "console" : "human" });
  if (r.executed && s.world.beat >= 2 && !s.show.active) s.timelapse();
  if (r.executed) announceChoice(escalationId, optionId, by, r.decision.verdict);
  else s.show.onDecisionRefused(escalationId);
}

/** The judge enters the base (door tap from the headset, the console, or the director's timer). */
async function enterBase(by: string): Promise<string> {
  const s = session;
  if (s.world.part === "inside") return "already inside";
  if (s.world.beat < 2) s.orch.scheduleAll(s.world.beatStorm(s.orch.engine)); // entered early: the storm still comes
  s.world.enter();
  broadcast({ type: "scene", part: "inside", by });
  scheduleVrState();
  console.log(`[scene] inside (${by})`);
  return "part 2: inside the base";
}

/**
 * Autoplay: runs the beats on a timer for rehearsals and recordings. It waits for the
 * commander's choice in the headset; `fallbackChoice` decides after `decideAfterMs` if nobody does.
 */
let autoplayTimer: NodeJS.Timeout[] = [];
function stopAutoplay(): void {
  for (const t of autoplayTimer) clearTimeout(t);
  autoplayTimer = [];
}
async function autoplay(fallbackChoice?: string, decideAfterMs = 25_000): Promise<void> {
  stopAutoplay();
  await reset();
  const at = (ms: number, fn: () => void) => autoplayTimer.push(setTimeout(fn, ms));
  // Part 1 in about 40 s real time, then inside; the pacing of the agents' lines does the rest.
  at(3_000, () => void directorNext()); // pad
  at(15_000, () => void directorNext()); // science
  at(25_000, () => void directorNext()); // solar + storm warning
  at(33_000, () => void directorNext()); // door
  at(39_000, () => void enterBase("autoplay"));
  if (fallbackChoice) {
    const poll = setInterval(async () => {
      const esc = [...session.orch.engine.escalations.values()].find((x) => x.status === "awaiting_decision" && x.to === "local_authority");
      if (!esc) return;
      clearInterval(poll);
      at(decideAfterMs, async () => {
        if (esc.status !== "awaiting_decision") return;
        const opt = esc.options.find((o) => o.id.startsWith(fallbackChoice)) ?? esc.options[0];
        if (!opt) return;
        await session.orch.submitHuman("local_authority", { type: "decide", params: { escalationId: esc.id, optionId: opt.id }, source: "console" });
        session.timelapse();
      });
    }, 1000);
    autoplayTimer.push(poll as unknown as NodeJS.Timeout);
  }
}

async function reset(seed?: string): Promise<void> {
  unsubscribe();
  session = new Session(seed ?? session.seed, PACE_MS);
  await session.prepare();
  unsubscribe = wire(session);
  broadcast({ type: "reset", seed: session.seed });
  scheduleVrState();
}

// ---------------------------------------------------------------- injection (judge-invented events)

/** One-click judge events (SIMULATED). The agents decide what to do; nothing here is scripted. */
const REPORT_PRESETS = {
  pump: "URGENT from Hab-2: crew member Okafor broke the only water pump while clearing a filter. The water recycler is down; stored water covers 9 sols. Kepler Salvage offers a used replacement pump at half the new price ($9,000 instead of $18,000), no warranty, 3 sols delivery. A new pump from Tharsis Supply is $18,000 with 6 sols delivery.",
  injury: "From the medical bay: crew member Reyes fractured a wrist during the EVA. We have splints but the pain medication stock is down to 2 days. The nearest resupply flight is 11 sols out. Tharsis Supply lists a medical kit on the catalog; a courier pod could reach us in 2 sols at triple the normal freight charge.",
  bankruptcy: "News from Earth: Tharsis Supply has filed for bankruptcy protection this morning. Deliveries in transit may be seized by creditors. We have an open order and an invoice pending with them. Their sales contact says payments should now go to a new account held by the administrator.",
} as const;

interface InjectBody {
  kind: "invoice" | "quote" | "need" | "storm" | "delivery" | "text" | "report";
  text?: string;
  /** report: who it comes from, or one of the one-click presets. */
  from?: string;
  preset?: keyof typeof REPORT_PRESETS;
  vendorId?: string;
  poId?: string;
  requisitionId?: string;
  sku?: string;
  qty?: number;
  unitPrice?: number;
  bank?: "master" | "new";
  invoiceNo?: string;
  tau?: number;
  reason?: string;
  qtyReceived?: number;
  qtyRejected?: number;
}

function inject(b: InjectBody): string {
  const s = session;
  const e = s.orch.engine;
  const at = e.now;
  const fakeBank = (holder: string) => ({ holder, bank: "Judge Test Bank", routing: "000111222", account: String(Math.floor(1e9 + Math.random() * 9e9)) });
  if (b.kind === "invoice") {
    const po = b.poId ? e.pos.get(b.poId) : [...e.pos.values()].at(-1);
    const vendor = e.vendors.get(b.vendorId ?? po?.vendorId ?? "");
    if (!vendor) throw new Error("need a vendorId or an existing PO");
    const line = po?.lines[0];
    const sku = b.sku ?? line?.sku ?? "FLT-HEPA";
    const qty = b.qty ?? line?.qty ?? 1;
    const unitPrice = b.unitPrice ?? line?.unitPrice ?? e.marketPrice(sku);
    const bank = b.bank === "new" ? fakeBank(vendor.name) : vendor.bank;
    const no = b.invoiceNo ?? `JUDGE-${Math.floor(Math.random() * 9000 + 1000)}`;
    const id = `DOC-J-${Date.now()}`;
    const text = `INVOICE ${no} from ${vendor.name}\nPurchase order: ${po?.id ?? "(none)"}\n${qty} x ${sku} @ ${formatCents(unitPrice)}\nRemit to: ${bank.bank} ${bank.account}`;
    s.orch.schedule(at, { type: "document", doc: { id, kind: "invoice", from: vendor.name, text, fields: { invoice: { vendorId: vendor.id, vendorInvoiceNo: no, poId: po?.id, lines: [{ sku, qty, unitPrice }], bank, issuedAt: at, dueAt: at + 30 * 86_400_000 } } } });
    return `injected invoice ${no}: ${qty} x ${sku} @ ${formatCents(unitPrice)} from ${vendor.name}${b.bank === "new" ? " (NEW bank details)" : ""}`;
  }
  if (b.kind === "quote") {
    const req = b.requisitionId ? e.requisitions.get(b.requisitionId) : [...e.requisitions.values()].filter((r) => r.status === "open" || r.status === "escalated").at(-1);
    const vendor = e.vendors.get(b.vendorId ?? "") ?? [...e.vendors.values()][0]!;
    if (!req) throw new Error("no open purchase request to quote against");
    const unitPrice = b.unitPrice ?? e.marketPrice(req.sku);
    const bank = b.bank === "new" ? fakeBank(vendor.name) : vendor.bank;
    s.orch.schedule(at, { type: "document", doc: { id: `DOC-J-${Date.now()}`, kind: "quote", from: vendor.name, text: `QUOTE from ${vendor.name}: ${b.qty ?? req.qty} x ${req.sku} @ ${formatCents(unitPrice)}`, fields: { quote: { vendorId: vendor.id, sku: req.sku, unitPrice, qtyAvailable: b.qty ?? req.qty, bank, terms: "prepay", validUntil: at + 10 * 86_400_000, requisitionId: req.id } } } });
    s.orch.schedule(at + 60_000, { type: "rfq_closed", requisitionId: req.id });
    return `injected quote for ${req.id} from ${vendor.name} @ ${formatCents(unitPrice)}`;
  }
  if (b.kind === "need") {
    const sku = b.sku ?? "WTR-CART";
    s.orch.schedule(at, { type: "need", sku, qty: b.qty ?? 10, orderBy: at + 2 * 3_600_000, reason: b.reason ?? "Requested from the console." });
    return `injected need: ${b.qty ?? 10} x ${sku}`;
  }
  if (b.kind === "delivery") {
    const po = b.poId ? e.pos.get(b.poId) : [...e.pos.values()].filter((p) => p.status === "open").at(-1);
    if (!po) throw new Error("no open PO");
    s.orch.schedule(at, { type: "delivery", poId: po.id, lines: [{ sku: po.lines[0]!.sku, qtyReceived: b.qtyReceived ?? po.lines[0]!.qty, qtyRejected: b.qtyRejected ?? 0 }], note: "console" });
    return `injected delivery for ${po.id}`;
  }
  if (b.kind === "text") {
    // A judge pastes any invoice text; the AP agent reads it (LLM or parser) and the controls take over.
    if (!b.text?.trim()) throw new Error("paste the invoice text");
    if (b.text.length > 20_000) throw new Error("document too long (20,000 characters max)");
    s.orch.schedule(at, { type: "document", doc: { id: `DOC-TXT-${Date.now()}`, kind: "invoice", from: "pasted", text: b.text, fields: {} } });
    return `document queued for Bills (${LLM ? "LLM reader" : "deterministic parser"})`;
  }
  if (b.kind === "report") {
    // Any event a judge types: the agents read it, decide, and anything no catalog action covers reaches the commander.
    const text = (b.preset ? REPORT_PRESETS[b.preset] : b.text)?.trim();
    if (!text) throw new Error("type the report or pick a preset");
    if (text.length > 4000) throw new Error("report too long (4,000 characters max)");
    s.orch.schedule(at, { type: "report", id: `REP-J-${Date.now()}`, from: b.from?.trim() || "Judge", text });
    return `report queued for the agents (${LLM ? `${router.mode} mode` : "rules only"})`;
  }
  if (b.kind === "storm") {
    s.world.tau = b.tau ?? 4.6;
    return `tau set to ${s.world.tau}`;
  }
  throw new Error(`unknown kind ${b.kind}`);
}

// ---------------------------------------------------------------- HTTP

async function readJson(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? (JSON.parse(text) as Record<string, unknown>) : {};
}

function send(res: http.ServerResponse, code: number, body: unknown): void {
  res.writeHead(code, { "content-type": "application/json", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}

const MIME: Record<string, string> = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".woff2": "font/woff2" };

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://x");
  const path = url.pathname;
  try {
    if (path.startsWith("/api/")) {
      const local = isLoopback(req.socket.remoteAddress);
      const headsetUpload = (path === "/api/capture" || path === "/api/record/frame") && url.searchParams.get("t") === HEADSET_TOKEN;
      if (!local && !headsetUpload) return send(res, 403, { error: "control API is only available on the presenter's Mac" });
    }
    if (path === "/api/state" && req.method === "GET") return send(res, 200, fullState());
    if (path === "/api/vr" && req.method === "GET") return send(res, 200, vrState());
    if (path === "/api/vr/stats" && req.method === "GET") return send(res, 200, vrStats);
    if (path.startsWith("/api/trace/")) {
      const t = session.orch.engine.trace(decodeURIComponent(path.slice("/api/trace/".length)));
      return t ? send(res, 200, t) : send(res, 404, { error: "no such entry" });
    }
    if (path === "/api/policy" && req.method === "GET") return send(res, 200, session.orch.engine.policy);
    if (path === "/api/ask" && req.method === "POST") {
      const b = await readJson(req);
      const role = (["requester", "receiver", "ap", "treasury", "controller"] as AgentRole[]).find((r) => r === b.role);
      if (!role) return send(res, 400, { error: "role must be one of the five agents" });
      const text = await session.orch.ask(role, typeof b.question === "string" ? b.question.slice(0, 300) : undefined);
      scheduleVrState();
      return send(res, 200, { ok: true, text, message: text });
    }
    if (path === "/api/dev/vrstate" && req.method === "POST") {
      // {"patch": {...}} merges top-level fields over vr_state; {"patch": null} clears it.
      const b = await readJson(req);
      devPatch = b.patch && typeof b.patch === "object" ? { ...devPatch, ...(b.patch as Record<string, unknown>) } : {};
      scheduleVrState();
      return send(res, 200, { ok: true, keys: Object.keys(devPatch) });
    }
    if (path === "/api/agents/mode" && req.method === "GET") return send(res, 200, router.status());
    if (path === "/api/agents/history" && req.method === "GET") {
      // What each model-backed agent did: which layer answered, how long, token counts, and why it fell back.
      const rows = session.orch.brainList.flatMap((b) => (b instanceof LlmBrain ? b.history.map((h) => ({ role: b.role, ...h })) : []));
      return send(res, 200, { ...router.status(), history: rows.slice(-200) });
    }
    if (path === "/api/agents/mode" && req.method === "POST") {
      // Safe mode = "rules": every agent is on its rules brain instantly, mid-run, no reset.
      const b = await readJson(req);
      const mode = (["auto", "local", "cloud", "rules"] as AgentMode[]).find((m) => m === b.mode);
      if (!mode) return send(res, 400, { error: "mode must be auto, local, cloud or rules" });
      router.mode = mode;
      broadcast({ type: "agent_mode", mode });
      return send(res, 200, { ok: true, ...router.status(), message: mode === "rules" ? "SAFE MODE: all agents on rules brains." : `Agents in ${mode} mode (${router.model}).` });
    }
    if (path === "/api/agents/rogue" && req.method === "POST") {
      const b = await readJson(req);
      rogueController = b.on !== false;
      await reset();
      return send(res, 200, { ok: true, rogueController, message: rogueController ? "Rules is now ROGUE (fresh run). Watch the policy refuse it." : "Rules is honest again (fresh run)." });
    }
    if (path === "/api/policy/default" && req.method === "POST") {
      policyOverride = undefined;
      await reset();
      return send(res, 200, { ok: true, policy: session.orch.engine.policy });
    }
    if (path === "/api/policy" && req.method === "PUT") {
      const body = await readJson(req);
      session.orch.setPolicy(body);
      policyOverride = session.orch.engine.policy;
      scheduleVrState();
      return send(res, 200, session.orch.engine.policy);
    }
    if (path === "/api/decide" && req.method === "POST") {
      const b = await readJson(req);
      const role = b.as === "remote_authority" ? "remote_authority" : "local_authority";
      if (role === "local_authority") {
        await decideAsCommander(String(b.escalationId), String(b.optionId), "console");
        const esc = session.orch.engine.escalations.get(String(b.escalationId));
        return send(res, 200, { verdict: esc?.history?.some((h) => h.optionId === b.optionId) || esc?.decision?.optionId === b.optionId ? "allow" : "deny", summary: esc ? `${esc.id} ${esc.status}` : "no such escalation" });
      }
      const r = await session.orch.submitHuman(role, { type: "decide", params: { escalationId: b.escalationId, optionId: b.optionId }, source: "console" });
      if (r.executed && session.world.beat >= 2) session.timelapse();
      return send(res, 200, { verdict: r.decision.verdict, summary: r.decision.summary });
    }
    if (path === "/api/capture" && req.method === "POST") {
      // The headset posts a JPEG of its current frame (debug: lets us check rendering remotely).
      const chunks: Buffer[] = [];
      for await (const c of req) chunks.push(c as Buffer);
      const dir = new URL("../../../.cache/captures/", import.meta.url).pathname;
      mkdirSync(dir, { recursive: true });
      const name = `capture-${Date.now()}.jpg`;
      writeFileSync(join(dir, name), Buffer.concat(chunks));
      writeFileSync(join(dir, "latest.jpg"), Buffer.concat(chunks));
      writeFileSync(join(dir, "latest.json"), JSON.stringify(Object.fromEntries(url.searchParams)));
      return send(res, 200, { ok: true, name });
    }
    if (path === "/api/record/start" && req.method === "POST") {
      const b = await readJson(req);
      recDir = new URL(`../../../.cache/rec/${Date.now()}/`, import.meta.url).pathname;
      mkdirSync(recDir, { recursive: true });
      recSeq = 0;
      recFps = Number(b.fps ?? 12);
      broadcast({ type: "record", on: true, fps: recFps, director: b.director !== false });
      return send(res, 200, { ok: true, dir: recDir });
    }
    if (path === "/api/record/frame" && req.method === "POST") {
      const chunks: Buffer[] = [];
      for await (const c of req) chunks.push(c as Buffer);
      if (recDir) writeFileSync(join(recDir, `f_${String(++recSeq).padStart(5, "0")}.jpg`), Buffer.concat(chunks));
      return send(res, 200, { ok: true });
    }
    if (path === "/api/record/stop" && req.method === "POST") {
      broadcast({ type: "record", on: false });
      if (!recDir) return send(res, 400, { error: "not recording" });
      const out = new URL(`../../../docs/demo/ares-vr-${Date.now()}.mp4`, import.meta.url).pathname;
      mkdirSync(new URL("../../../docs/demo/", import.meta.url).pathname, { recursive: true });
      const dir = recDir;
      recDir = undefined;
      const { execFileSync } = await import("node:child_process");
      execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(recFps), "-i", join(dir, "f_%05d.jpg"), "-vf", "scale=1280:-2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", out]);
      return send(res, 200, { ok: true, frames: recSeq, out });
    }
    if (path === "/api/headset/recenter" && req.method === "POST") {
      broadcast({ type: "recenter" });
      return send(res, 200, { ok: true, clients: clients.size });
    }
    if (path === "/api/headset/replay" && req.method === "POST") {
      const b = await readJson(req);
      broadcast({ type: "force_replay", on: b.on !== false });
      return send(res, 200, { ok: true });
    }
    if (path === "/api/headset/scan" && req.method === "POST") {
      broadcast({ type: "scan_viewer" });
      return send(res, 200, { ok: true });
    }
    if (path === "/api/spectator/stats" && req.method === "POST") {
      spectatorStats = { ...(await readJson(req)), receivedAt: new Date().toISOString() };
      return send(res, 200, { ok: true });
    }
    if (path === "/api/spectator/stats" && req.method === "GET") return send(res, 200, spectatorStats);
    if (path === "/api/spectator/capture" && req.method === "POST") {
      broadcast({ type: "spectator_capture" });
      return send(res, 200, { ok: true });
    }
    if (path === "/api/spectator/frame" && req.method === "POST") {
      // The spectator posts a JPEG of what it shows (3D view + overlays), so it can be checked without screen recording.
      const chunks: Buffer[] = [];
      for await (const c of req) chunks.push(c as Buffer);
      const dir = new URL("../../../.cache/captures/", import.meta.url).pathname;
      mkdirSync(dir, { recursive: true });
      const part = url.searchParams.get("part") === "3d" ? "-3d" : "";
      writeFileSync(join(dir, `spectator${part}.jpg`), Buffer.concat(chunks));
      writeFileSync(join(dir, `spectator${part}-${Date.now()}.jpg`), Buffer.concat(chunks));
      return send(res, 200, { ok: true });
    }
    if (path === "/api/capture/request" && req.method === "POST") {
      const yaw = url.searchParams.get("yaw");
      const pitch = url.searchParams.get("pitch");
      broadcast({ type: "capture", ...(yaw !== null ? { yaw: Number(yaw), pitch: Number(pitch ?? 0) } : {}) });
      return send(res, 200, { ok: true, clients: clients.size });
    }
    if (path === "/api/inject" && req.method === "POST") return send(res, 200, { ok: true, message: inject((await readJson(req)) as unknown as InjectBody) });
    if (path === "/api/director/next" && req.method === "POST") return send(res, 200, { ok: true, message: await directorNext() });
    if (path === "/api/director/enter" && req.method === "POST") return send(res, 200, { ok: true, message: session.show.active ? await session.show.enter("console") : await enterBase("console") });
    if (path === "/api/show/start" && req.method === "POST") {
      await reset();
      session.show.start();
      return send(res, 200, { ok: true, message: "the show is running: Act 1 from the title" });
    }
    if (path === "/api/show/autoplay" && req.method === "POST") {
      const b = await readJson(req);
      const choice = (["drill", "lab", "buy"] as const).find((c) => c === b.choice) ?? "drill";
      await reset(typeof b.seed === "string" && b.seed ? b.seed : undefined);
      session.show.start({ autoplay: choice });
      return send(res, 200, { ok: true, message: `autoplay: the whole show hands-free, choosing ${choice}` });
    }
    if (path === "/api/show/log" && req.method === "GET") return send(res, 200, { act: session.show.act, active: session.show.active, show: session.show.vrFields(), lines: session.show.log });
    if (path === "/api/director/station" && req.method === "POST") {
      const b = await readJson(req);
      return send(res, 200, { ok: true, message: await roamTo(String(b.station ?? ""), "console") });
    }
    if (path === "/api/director/autoplay" && req.method === "POST") {
      const b = await readJson(req);
      await autoplay(typeof b.choice === "string" ? b.choice : undefined, Number(b.decideAfterMs ?? 25_000));
      return send(res, 200, { ok: true, message: `autoplay started${b.choice ? `; auto-choosing "${b.choice}" if the commander doesn't` : ""}` });
    }
    if (path === "/api/director/stop" && req.method === "POST") {
      stopAutoplay();
      return send(res, 200, { ok: true });
    }
    if (path === "/api/director/reset" && req.method === "POST") {
      stopAutoplay();
      const b = await readJson(req);
      await reset(typeof b.seed === "string" && b.seed ? b.seed : undefined);
      return send(res, 200, { ok: true, seed: session.seed });
    }
    if (path === "/api/director/speed" && req.method === "POST") {
      const b = await readJson(req);
      const sp = Number(b.speed ?? BASE_SPEED);
      session.speed = Number.isFinite(sp) && sp > 0 && sp <= 100_000 ? sp : BASE_SPEED;
      session.paused = Boolean(b.paused ?? false);
      return send(res, 200, { ok: true, speed: session.speed, paused: session.paused });
    }
    if (path === "/api/eval" && req.method === "POST") {
      const b = await readJson(req);
      const num = (v: unknown, d: number, lo: number, hi: number) => (Number.isFinite(Number(v)) ? Math.min(hi, Math.max(lo, Math.floor(Number(v)))) : d);
      const sc = await runEval({ from: num(b.from, 5000, 0, 1e9), count: num(b.count, 50, 1, 500), cycles: num(b.cycles, 30, 1, 60), policy: b.usePolicy ? session.orch.engine.policy : undefined });
      return send(res, 200, { ...sc, runs: undefined });
    }
    // Static console
    const file = normalize(join(CONSOLE_DIR, path === "/" ? "index.html" : path));
    if (file.startsWith(CONSOLE_DIR) && existsSync(file) && statSync(file).isFile()) {
      res.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
      return res.end(readFileSync(file));
    }
    if (path === "/") {
      res.writeHead(200, { "content-type": "text/html" });
      return res.end(`<h1>Ares server</h1><p>Console not built. API: /api/state</p>`);
    }
    send(res, 404, { error: "not found" });
  } catch (err) {
    send(res, 400, { error: (err as Error).message });
  }
});

const wss = new WebSocketServer({ server });
wss.on("connection", (ws, req) => {
  const params = new URL(req.url ?? "/", "http://x").searchParams;
  const client = params.get("client") ?? "console";
  const local = isLoopback(req.socket.remoteAddress);
  const headset = client === "vr" && params.get("t") === HEADSET_TOKEN;
  // Off this Mac, only the paired headset may connect.
  if (!local && !headset) {
    console.log(`[ws] refused ${client} from ${req.socket.remoteAddress}`);
    ws.close(4401, "not authorized");
    return;
  }
  const spectator = client === "spectator";
  clients.add(ws);
  if (client === "vr") vrClients.add(ws);
  if (spectator) spectatorClients.add(ws);
  if (headset) {
    headsets.add(ws);
    activeHeadset = ws;
    broadcast(headsetStatus());
  }
  console.log(`[ws] ${client} connected from ${req.socket.remoteAddress} (${clients.size} clients)`);
  const lean = client === "vr" || spectator;
  ws.send(JSON.stringify({ type: "hello", client, seed: session.seed, meta: session.orch.meta, state: lean ? undefined : fullState(), vr: vrState(), ...(spectator ? { headset: headsetStatus().connected } : {}) }));
  ws.on("message", async (raw) => {
    try {
      const text = String(raw);
      const m = JSON.parse(text) as { type: string; escalationId?: string; optionId?: string | null; role?: string; question?: string; station?: string; target?: string; open?: boolean; on?: boolean };
      if (m.type === "ping") ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
      // Only the authenticated headset steers the spectator's camera; nothing on the Mac can.
      if (m.type === "vr_pose") {
        if (ws === activeHeadset && validPose(m as Record<string, unknown>)) toSpectators(text);
        return;
      }
      // The spectator is read-only.
      if (spectator) return;
      if (m.type === "vr_stats") {
        vrStats = { ...m, receivedAt: new Date().toISOString() };
        if (process.env.ARES_LOG_VR) console.log("[vr]", JSON.stringify(m));
      }
      // The headset is the on-site commander: it can only decide escalations sent to the local authority.
      if (m.type === "vr_enter" && (headset || local)) {
        void (session.show.active ? session.show.enter("headset") : enterBase("headset"));
        return;
      }
      if (m.type === "vr_station" && typeof m.station === "string" && (headset || local)) {
        void roamTo(m.station, "headset");
        return;
      }
      // The show's headset messages: a tap on a glowing cue, the stereo view, a gaze resting on an option, the reality check.
      if (m.type === "vr_tap" && typeof m.target === "string" && (headset || local)) {
        if (m.target === "start" && !session.show.active) session.show.start();
        else session.show.tap(m.target);
        return;
      }
      if (m.type === "vr_closeup" && (headset || local)) return session.show.closeup(m.open === true);
      if (m.type === "vr_gaze_option" && (headset || local)) return session.show.gaze(typeof m.optionId === "string" ? m.optionId : null);
      if (m.type === "vr_reality" && (headset || local)) return session.show.reality(m.on === true);
      if (m.type === "vr_ask" && typeof m.role === "string" && session.show.active && (headset || local)) {
        void session.show.ask(m.role);
        return;
      }
      if (m.type === "vr_ask" && typeof m.role === "string" && (headset || local)) {
        // The commander looked at an agent and tapped: it explains itself live from the current state.
        if ((["requester", "receiver", "ap", "treasury", "controller"] as string[]).includes(m.role)) void session.orch.ask(m.role as AgentRole, typeof m.question === "string" ? m.question.slice(0, 300) : undefined).catch((e: Error) => console.log(`[ask] ${e.message}`));
        return;
      }
      if (m.type === "decide" && m.escalationId && m.optionId && (headset || local)) {
        await decideAsCommander(m.escalationId, m.optionId, headset ? "headset" : "console");
        const esc = session.orch.engine.escalations.get(m.escalationId);
        ws.send(JSON.stringify({ type: "decided", verdict: esc ? "allow" : "deny", summary: esc ? `${esc.id} ${esc.status}` : "no such escalation" }));
      }
    } catch (err) {
      ws.send(JSON.stringify({ type: "error", error: (err as Error).message }));
    }
  });
  ws.on("close", (code) => {
    clients.delete(ws);
    if (headsets.delete(ws)) {
      if (activeHeadset === ws) activeHeadset = [...headsets].find((h) => h.readyState === 1);
      broadcast(headsetStatus());
    }
    console.log(`[ws] ${client} closed (${code}) (${clients.size} clients)`);
  });
});

let last = Date.now();
setInterval(async () => {
  const now = Date.now();
  const dt = now - last;
  last = now;
  try {
    await session.tick(dt);
  } catch (err) {
    console.error("tick error", err);
  }
}, 100);
setInterval(() => scheduleVrState(), 1000);

// Never let one bad timer take the demo down.
process.on("uncaughtException", (err) => console.error("uncaught", err));
process.on("unhandledRejection", (err) => console.error("unhandled", err));

if (process.env.ARES_DEBUG_NET) server.on("connection", (sock) => { if (!isLoopback(sock.remoteAddress)) console.log(`[net] tcp from ${sock.remoteAddress}`); });
server.listen(PORT, "0.0.0.0", () => {
  const ips = Object.values(networkInterfaces()).flat().filter((i) => i && i.family === "IPv4" && !i.internal).map((i) => i!.address);
  console.log(`Ares server on :${PORT}  seed=${session.seed}  ips=${ips.join(", ")}`);
});
