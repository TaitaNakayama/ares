import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import http from "node:http";
import { networkInterfaces } from "node:os";
import { randomBytes } from "node:crypto";
import { dirname, extname, join, normalize } from "node:path";
import { WebSocketServer, type WebSocket } from "ws";
import { ApWithReader, ControllerRules, EscalationDrafter, LlmBrain, llmRoute, ModelRouter, OllamaProvider, OpenAIProvider, Orchestrator, ReceiverRules, ReportRules, RequesterRules, RogueBrain, TreasuryRules, type AgentMode, type Brain, type LlmProvider, type Narration, type OrchestratorMessage } from "@ares/agents";
import { formatCents, RULE_LABELS, type AgentRole, type Escalation, type Policy } from "@ares/engine";
import { runEval } from "@ares/eval";
import { MarsWorld } from "@ares/world-mars";

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
const LLM_ROLES = (process.env.ARES_LLM_ROLES ?? "requester,receiver,ap,treasury,controller").split(",");
console.log(`LLM layers: local ${router.local ? router.local.model : localProvider ? `none (Ollama ${localUp.up ? `up, model ${LOCAL_MODEL} not pulled` : "not running"})` : "off"}; cloud ${router.cloud ? router.cloud.model : "none"}; mode ${router.mode}`);
if (router.local && localProvider) void localProvider.prewarm().then(() => console.log("local model warm"), (e: Error) => console.log(`local model prewarm failed: ${e.message}`));
/** Demo switch: replace the Rule Keeper's brain with a malicious one; policy must hold. */
let rogueController = false;
const brains = (): Brain[] => {
  const rules: Record<AgentRole, Brain> = {
    requester: new RequesterRules(),
    receiver: new ReceiverRules(),
    ap: new ApWithReader(LLM),
    treasury: new TreasuryRules(),
    controller: rogueController ? new RogueBrain("controller", new ControllerRules()) : new ControllerRules(),
  };
  const list: Brain[] = [];
  for (const role of Object.keys(rules) as AgentRole[]) {
    const useLlm = !!LLM && LLM_ROLES.includes(role) && !(role === "controller" && rogueController);
    list.push(useLlm ? new LlmBrain({ role, rules: rules[role], router }) : rules[role]);
    if (!useLlm) list.push(new ReportRules(role)); // reports still reach the commander without a model
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
    this.orch = new Orchestrator({ world: this.world, brains: brains(), fmtTime: this.world.fmtTime, paceMs: 0, routeReport: LLM ? llmRoute(router) : undefined });
    this.simNow = this.world.start - 32 * 86_400_000;
  }

  /** Runs the prologue instantly (no pacing), then enables pacing for the live part. */
  async prepare(): Promise<void> {
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
    broadcast({ type: m.type, ...(m.type === "engine" ? { event: m.event } : m.type === "narration" ? { narration: m.narration } : { at: m.at, data: m.data }) });
    scheduleVrState();
  });
}

const VR_TYPES = new Set(["vr_state", "capture", "reset", "record", "recenter", "scan_viewer", "force_replay", "thinking"]);
const SPECTATOR_TYPES = new Set(["vr_state", "narration", "reset", "headset", "vr_choice", "spectator_capture", "thinking"]);
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
function announceChoice(escalationId: string, optionId: string, by: "headset" | "console", verdict: string): void {
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
function vrState() {
  const s = session;
  const e = s.orch.engine;
  const t = s.world.telemetry(e.now, e);
  const robots: Record<string, Narration | undefined> = {};
  for (const n of s.orch.narration) robots[n.role] = n;
  const waiting = [...e.escalations.values()]
    .filter((x) => x.status === "awaiting_decision" && x.to === "local_authority")
    .map((x: Escalation) => ({ id: x.id, reason: x.reason, decideBy: x.decideBy, decideByText: x.decideBy ? s.world.fmtTime(x.decideBy) : null, options: x.options.map((o) => ({ id: o.id, label: o.label, detail: o.detail })) }));
  const pendingVer = [...e.verifications.values()].filter((v) => v.status === "pending");
  const payments = [...e.payments.values()].filter((p) => p.status === "sent").slice(-4).reverse().map((p) => ({ id: p.id, vendor: e.vendors.get(p.vendorId)?.name, amount: p.amount, amountText: formatCents(p.amount) }));
  return {
    seed: s.seed,
    policyVersion: e.policy.version,
    beat: s.world.beat,
    storyBeat: s.world.storyBeat(e),
    storyBeats: 7,
    thinking: [...s.thinking],
    agentMode: router.mode,
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

async function directorNext(): Promise<string> {
  const s = session;
  const e = s.orch.engine;
  if (s.world.beat === 0) {
    s.orch.scheduleAll(s.world.beatDelivery(e));
    return "beat 1: delivery + invoice";
  }
  if (s.world.beat === 1) {
    s.orch.scheduleAll(s.world.beatStorm(e));
    return "beat 2: dust storm";
  }
  return "no further scripted beats; the rest is up to the agents and the commander";
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
  at(4_000, () => void directorNext());
  at(20_000, () => void directorNext());
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
    return `document queued for the Bill Checker (${LLM ? "LLM reader" : "deterministic parser"})`;
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
      return send(res, 200, { ok: true, rogueController, message: rogueController ? "Rule Keeper is now ROGUE (fresh run). Watch the policy refuse it." : "Rule Keeper is honest again (fresh run)." });
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
      const r = await session.orch.submitHuman(role, { type: "decide", params: { escalationId: b.escalationId, optionId: b.optionId }, source: "console" });
      if (r.executed && session.world.beat >= 2) session.timelapse();
      if (r.executed && role === "local_authority") announceChoice(String(b.escalationId), String(b.optionId), "console", r.decision.verdict);
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
      const m = JSON.parse(text) as { type: string; escalationId?: string; optionId?: string; role?: string; question?: string };
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
      if (m.type === "vr_ask" && typeof m.role === "string" && (headset || local)) {
        // The commander looked at an agent and tapped: it explains itself live from the current state.
        if ((["requester", "receiver", "ap", "treasury", "controller"] as string[]).includes(m.role)) void session.orch.ask(m.role as AgentRole, typeof m.question === "string" ? m.question.slice(0, 300) : undefined).catch((e: Error) => console.log(`[ask] ${e.message}`));
        return;
      }
      if (m.type === "decide" && m.escalationId && m.optionId && (headset || local)) {
        const r = await session.orch.submitHuman("local_authority", { type: "decide", params: { escalationId: m.escalationId, optionId: m.optionId }, source: "human" });
        if (r.executed && session.world.beat >= 2) session.timelapse();
        if (r.executed) announceChoice(m.escalationId, m.optionId, headset ? "headset" : "console", r.decision.verdict);
        ws.send(JSON.stringify({ type: "decided", verdict: r.decision.verdict, summary: r.decision.summary }));
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
