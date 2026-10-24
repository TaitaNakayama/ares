import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import http from "node:http";
import { networkInterfaces } from "node:os";
import { randomBytes } from "node:crypto";
import { dirname, extname, join, normalize } from "node:path";
import { WebSocketServer, type WebSocket } from "ws";
import { ApWithReader, ControllerRules, EscalationDrafter, Orchestrator, providerFromEnv, ReceiverRules, RequesterRules, RogueBrain, TreasuryRules, type Narration, type OrchestratorMessage } from "@ares/agents";
import { formatCents, RULE_LABELS, type Escalation, type Policy } from "@ares/engine";
import { runEval } from "@ares/eval";
import { MarsWorld } from "@ares/world-mars";

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
const LLM = providerFromEnv(new URL("../../../.cache/llm/", import.meta.url).pathname);
console.log(LLM ? `LLM: ${LLM.name} (${LLM.model})` : "LLM: none (rules brains + deterministic document parser)");
/** Demo switch: replace the Rule Keeper's brain with a malicious one; policy must hold. */
let rogueController = false;
const brains = () => [new RequesterRules(), new ReceiverRules(), new ApWithReader(LLM), new TreasuryRules(), rogueController ? new RogueBrain("controller", new ControllerRules()) : new ControllerRules(), new EscalationDrafter(LLM)];

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
    this.orch = new Orchestrator({ world: this.world, brains: brains(), fmtTime: this.world.fmtTime, paceMs: 0 });
    this.simNow = this.world.start - 32 * 86_400_000;
  }

  /** Runs the prologue instantly (no pacing), then enables pacing for the live part. */
  async prepare(): Promise<void> {
    await this.orch.runUntil(this.world.start);
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
const clients = new Set<WebSocket>();
/** Headset sockets get only what the headset needs (small messages, no engine firehose). */
const vrClients = new WeakSet<WebSocket>();
let vrStats: Record<string, unknown> = {};
let recDir: string | undefined;
let recSeq = 0;
let recFps = 12;
let unsubscribe = wire(session);

function wire(s: Session): () => void {
  return s.orch.on((m: OrchestratorMessage) => {
    if (m.type === "telemetry") s.lastTelemetry = m.data;
    broadcast({ type: m.type, ...(m.type === "engine" ? { event: m.event } : m.type === "narration" ? { narration: m.narration } : { at: m.at, data: m.data }) });
    scheduleVrState();
  });
}

const VR_TYPES = new Set(["vr_state", "capture", "reset", "record", "recenter", "scan_viewer", "force_replay"]);
function broadcast(msg: { type: string; [k: string]: unknown }): void {
  const text = JSON.stringify(msg);
  for (const c of clients) {
    if (c.readyState !== 1) continue;
    if (vrClients.has(c) && !VR_TYPES.has(msg.type)) continue;
    c.send(text);
  }
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
    headset: { connected: [...clients].filter((c) => vrClients.has(c) && c.readyState === 1).length, stats: vrStats },
    llm: LLM ? `${LLM.name} (${LLM.model})` : null,
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

interface InjectBody {
  kind: "invoice" | "quote" | "need" | "storm" | "delivery" | "text";
  text?: string;
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
  clients.add(ws);
  if (client === "vr") vrClients.add(ws);
  console.log(`[ws] ${client} connected from ${req.socket.remoteAddress} (${clients.size} clients)`);
  ws.send(JSON.stringify({ type: "hello", client, seed: session.seed, meta: session.orch.meta, state: client === "vr" ? undefined : fullState(), vr: vrState() }));
  ws.on("message", async (raw) => {
    try {
      const m = JSON.parse(String(raw)) as { type: string; escalationId?: string; optionId?: string };
      if (m.type === "ping") ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
      if (m.type === "vr_stats") {
        vrStats = { ...m, receivedAt: new Date().toISOString() };
        if (process.env.ARES_LOG_VR) console.log("[vr]", JSON.stringify(m));
      }
      // The headset is the on-site commander: it can only decide escalations sent to the local authority.
      if (m.type === "decide" && m.escalationId && m.optionId && (headset || local)) {
        const r = await session.orch.submitHuman("local_authority", { type: "decide", params: { escalationId: m.escalationId, optionId: m.optionId }, source: "human" });
        if (r.executed && session.world.beat >= 2) session.timelapse();
        ws.send(JSON.stringify({ type: "decided", verdict: r.decision.verdict, summary: r.decision.summary }));
      }
    } catch (err) {
      ws.send(JSON.stringify({ type: "error", error: (err as Error).message }));
    }
  });
  ws.on("close", (code) => {
    clients.delete(ws);
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

server.listen(PORT, "0.0.0.0", () => {
  const ips = Object.values(networkInterfaces()).flat().filter((i) => i && i.family === "IPv4" && !i.internal).map((i) => i!.address);
  console.log(`Ares server on :${PORT}  seed=${session.seed}  ips=${ips.join(", ")}`);
});
