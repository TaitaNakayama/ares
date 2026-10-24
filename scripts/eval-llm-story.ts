// LLM agent evaluation: run the full 7-beat story with the LLM brains (local -> cloud -> rules), many
// seeds, and report honestly next to the rules brains on the same seeds: did every beat happen in
// order, how many decisions the model actually made vs fell back, how many lines were replaced
// for stating facts the engine didn't provide, latency, denials, and whether a novel event (the
// broken water pump) reached the commander with a recommendation.
//   [ARES_PREFER=local] node scripts/eval-llm-story.ts --seeds 5 [--mode auto|local|cloud] [--warm] [--roles requester,controller] [--json out.json]
import { writeFileSync } from "node:fs";
import {
  ApWithReader, ControllerRules, EscalationDrafter, LlmBrain, llmRoute, ModelRouter, OllamaProvider, OpenAIProvider, Orchestrator, ReceiverRules, ReportRules, RequesterRules, TreasuryRules,
  type AgentMode, type Brain, type LlmOutcome,
} from "@ares/agents";
import type { AgentRole } from "@ares/engine";
import { MarsWorld } from "@ares/world-mars";

process.loadEnvFile(new URL("../.env", import.meta.url).pathname);
const args = process.argv.slice(2);
const opt = (k: string, d: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1]! : d; };
const SEEDS = Number(opt("--seeds", "5"));
const MODE = opt("--mode", "auto") as AgentMode;
const ROLES = opt("--roles", "requester,receiver,ap,treasury,controller").split(",") as AgentRole[];
const OUT = opt("--json", "");
const WARM = args.includes("--warm"); // warm the local prefix cache per role before the LLM run (as the server does at boot)
const PUMP = "URGENT from Hab-2: crew member Okafor broke the only water pump while clearing a filter. The water recycler is down; stored water covers 9 sols. Kepler Salvage offers a used replacement pump at half the new price ($9,000 instead of $18,000), no warranty, 3 sols delivery. A new pump from Tharsis Supply is $18,000 with 6 sols delivery.";

const local = new OllamaProvider();
const avail = await local.available();
const cloud = process.env.OPENAI_API_KEY ? new OpenAIProvider(process.env.OPENAI_API_KEY) : undefined;
const router = new ModelRouter(avail.up && avail.hasModel ? local : undefined, cloud); // no cache: every seed is a real call
router.mode = MODE;
console.log(`layers: local ${router.local?.model ?? "none"}; cloud ${router.cloud?.model ?? "none"}; mode ${MODE}; roles ${ROLES.join(",")}`);

interface RunResult {
  seed: string;
  brains: "llm" | "rules";
  beats: number[];
  onStory: boolean;
  escalationToCommander: boolean;
  prevented: number;
  paid: number;
  cash: number;
  proposals: Record<string, number>;
  denied: Record<string, number>;
  llm: { decisions: number; fallbacks: number; byReason: Record<string, number>; linesReplaced: number; p50: number; p95: number; max: number; byLayer: Record<string, number>; localPromptTokens?: { median: number; max: number } };
  pump: { reached: boolean; by?: string; urgency?: string; recommendation?: string; ms?: number };
  /** Story outcomes that must hold whoever decides: what the judge is promised to see. */
  checks: Record<string, boolean>;
  wallMs: number;
}

function brainsFor(kind: "llm" | "rules"): Brain[] {
  const rules: Record<AgentRole, Brain> = { requester: new RequesterRules(), receiver: new ReceiverRules(), ap: new ApWithReader(kind === "llm" ? router : undefined), treasury: new TreasuryRules(), controller: new ControllerRules() };
  const list: Brain[] = [];
  for (const role of Object.keys(rules) as AgentRole[]) {
    const use = kind === "llm" && ROLES.includes(role);
    list.push(use ? new LlmBrain({ role, rules: rules[role], router }) : rules[role]);
    if (!use) list.push(new ReportRules(role));
  }
  list.push(new EscalationDrafter(kind === "llm" ? router : undefined));
  return list;
}

const q = (xs: number[], p: number) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))]! : 0; };
const count = (xs: string[]) => xs.reduce<Record<string, number>>((m, x) => ((m[x] = (m[x] ?? 0) + 1), m), {});

async function run(seed: string, kind: "llm" | "rules"): Promise<RunResult> {
  const t0 = performance.now();
  const world = new MarsWorld({ seed, mode: "demo" });
  const brains = brainsFor(kind);
  const orch = new Orchestrator({ world, brains, fmtTime: world.fmtTime, routeReport: kind === "llm" ? llmRoute(router) : undefined });
  const e = orch.engine;
  const beats: number[] = [];
  const mark = () => { const b = world.storyBeat(e); if (beats.at(-1) !== b) beats.push(b); };
  orch.on(() => mark()); // sample the beat after every event, so skipped or reordered beats show
  // Prologue (pre-story history) on rules, as the server does.
  const mode = router.mode;
  router.mode = "rules";
  await orch.runUntil(world.start);
  router.mode = mode;
  if (kind === "llm" && WARM) {
    const tw = performance.now();
    for (const b of brains) if (b instanceof LlmBrain) { const self = [...e.actors.values()].find((a) => a.role === b.role)!; await b.warmup({ engine: e, self, fmtTime: world.fmtTime, itemName: (sku) => e.items.get(sku)?.name ?? sku }); }
    console.log(`  warm-up ${((performance.now() - tw) / 1000).toFixed(0)}s`);
  }
  mark();
  orch.scheduleAll(world.beatDelivery(e));
  await orch.runUntil(e.now + 2 * 3600e3);
  mark();
  orch.scheduleAll(world.beatStorm(e));
  await orch.runUntil(e.now + 2 * 3600e3);
  mark();
  const esc = [...e.escalations.values()].find((x) => x.status === "awaiting_decision" && x.to === "local_authority" && x.subject.kind === "requisition");
  if (esc) {
    const buy = esc.options.find((o) => o.id.startsWith("buy-")) ?? esc.options[0]!;
    await orch.submitHuman("local_authority", { type: "decide", params: { escalationId: esc.id, optionId: buy.id } });
    mark();
  }
  await orch.runUntil(e.now + 6 * 3600e3);
  mark();
  // A novel event after the story: must reach the commander with a recommendation.
  const tp = performance.now();
  orch.schedule(e.now + 60_000, { type: "report", id: `REP-EVAL-${seed}`, from: "Hab-2", text: PUMP });
  await orch.runUntil(e.now + 10 * 60_000);
  const rep = [...e.reports.values()].at(-1);
  const repEsc = rep ? [...e.escalations.values()].find((x) => x.subject.kind === "report" && x.subject.id === rep.id) : undefined;

  // Outcome checks: the facts the pitch promises, independent of who decided.
  const firstInv = [...e.invoices.values()][0];
  const firstMatch = firstInv ? e.computeMatch(firstInv) : undefined;
  const paidFirst = firstInv ? [...e.payments.values()].filter((p) => p.invoiceId === firstInv.id && p.status === "sent").reduce((s, p) => s + p.amount, 0) : 0;
  const flaggedQuotes = [...e.quotes.values()].filter((q) => e.quoteRules(q).some((r) => !r.ok && r.rule === "vendor.bank_matches_master"));
  const batReq = [...e.requisitions.values()].find((r) => r.sku !== firstInv?.lines[0]?.sku && r.createdAt >= world.start);
  const checks: Record<string, boolean> = {
    "short delivery paid only for the units received": !!firstMatch && paidFirst === firstMatch.payable && firstMatch.payable > 0,
    "fake-bank quote never approved": flaggedQuotes.length > 0 && !flaggedQuotes.some((q) => [...e.pos.values()].some((po) => po.quoteId === q.id)),
    "bank verification requested": [...e.verifications.values()].length > 0,
    "fraud confirmed by Earth, supplier locked": e.prevented.some((x) => x.code === "fraud_confirmed"),
    "commander got the battery decision": !!esc,
    "commander's purchase went through to the verified account": !!batReq && [...e.pos.values()].some((po) => po.requisitionId === batReq.id),
    "all 7 beats in order": [1, 2, 3, 4, 5, 6, 7].every((b) => beats.includes(b)) && beats.join() === [...beats].sort((a, b) => a - b).join(),
    "pump report reached the commander": !!repEsc && repEsc.to === "local_authority",
  };
  const hist: (LlmOutcome & { role?: string })[] = brains.flatMap((b) => (b instanceof LlmBrain ? b.history.filter((h) => !h.point.startsWith("warmup")).map((h) => ({ ...h, role: b.role })) : []));
  const prompts = hist.filter((h) => h.layer === "local" && h.usage).map((h) => h.usage!.promptTokens);
  const ms = hist.filter((h) => h.result === "llm").map((h) => h.ms ?? 0);
  const paid = [...e.payments.values()].filter((p) => p.status === "sent").reduce((s, p) => s + p.amount, 0);
  return {
    seed,
    brains: kind,
    beats,
    onStory: [1, 2, 3, 4, 5, 6, 7].every((b) => beats.includes(b)) && beats.join() === [...beats].sort((a, b) => a - b).join(),
    escalationToCommander: !!esc,
    prevented: e.prevented.reduce((s, x) => s + x.amount, 0),
    paid,
    cash: e.ledger.balance("cash"),
    proposals: count(e.proposals.map((p) => p.source)),
    denied: count(e.decisions.filter((d) => d.verdict === "deny").map((d) => e.proposals.find((p) => p.id === d.proposalId)?.source ?? "?")),
    llm: {
      decisions: hist.filter((h) => h.result === "llm").length,
      fallbacks: hist.filter((h) => h.result === "fallback").length,
      byReason: count(hist.filter((h) => h.result === "fallback").map((h) => `${h.role}:${h.point.replace(/^\w+:/, "")} ${(h.reason ?? "?").replace(/\(.*$/, "").trim().slice(0, 30)}`)),
      localPromptTokens: prompts.length ? { median: q(prompts, 0.5), max: Math.max(...prompts) } : undefined,
      linesReplaced: hist.filter((h) => h.result === "llm" && /line replaced/.test(h.reason ?? "")).length,
      p50: q(ms, 0.5), p95: q(ms, 0.95), max: Math.max(0, ...ms),
      byLayer: count(hist.filter((h) => h.result === "llm").map((h) => h.layer ?? "?")),
    },
    pump: { reached: !!repEsc && repEsc.to === "local_authority", by: rep ? e.actors.get(rep.by)?.role : undefined, urgency: rep?.urgency, recommendation: rep?.recommendation, ms: performance.now() - tp },
    checks,
    wallMs: performance.now() - t0,
  };
}

const results: RunResult[] = [];
for (let i = 0; i < SEEDS; i++) {
  const seed = `eval-${i + 1}`;
  for (const kind of ["rules", "llm"] as const) {
    if (kind === "llm" && !router.order().length) continue;
    const r = await run(seed, kind);
    results.push(r);
    const failed = Object.entries(r.checks).filter(([, ok]) => !ok).map(([k]) => k);
    const flag = failed.length ? `  FAILED: ${failed.join("; ")}` : "";
    console.log(`${seed.padEnd(8)} ${kind.padEnd(5)} beats ${r.beats.join(">")}${flag}  commander ${r.escalationToCommander ? "yes" : "NO"}  prevented $${(r.prevented / 100).toLocaleString()}  paid $${(r.paid / 100).toLocaleString()}  denied ${JSON.stringify(r.denied)}` + (kind === "llm" ? `  llm ${r.llm.decisions} decisions / ${r.llm.fallbacks} fallbacks ${JSON.stringify(r.llm.byReason)}  lines replaced ${r.llm.linesReplaced}  p50 ${(r.llm.p50 / 1000).toFixed(1)}s p95 ${(r.llm.p95 / 1000).toFixed(1)}s  layers ${JSON.stringify(r.llm.byLayer)}${r.llm.localPromptTokens ? ` local prompt tokens read median ${r.llm.localPromptTokens.median}` : ""}  pump ${r.pump.reached ? `reached via ${r.pump.by} (${r.pump.urgency}, ${((r.pump.ms ?? 0) / 1000).toFixed(0)}s)` : "NOT REACHED"}` : `  pump ${r.pump.reached ? "reached (rules)" : "NOT REACHED"}`) + `  ${(r.wallMs / 1000).toFixed(0)}s`);
  }
}
const llm = results.filter((r) => r.brains === "llm");
const rules = results.filter((r) => r.brains === "rules");
if (llm.length) {
  const allMs = llm.flatMap((r) => [r.llm.p50]);
  const names = Object.keys(llm[0]!.checks);
  console.log("\nOutcome checks (LLM brains / rules brains), seeds passing:");
  for (const n of names) console.log(`  ${n.padEnd(60)} ${llm.filter((r) => r.checks[n]).length}/${llm.length}   ${rules.filter((r) => r.checks[n]).length}/${rules.length}`);
  console.log(`\nLLM brains over ${llm.length} seeds: on-story ${llm.filter((r) => r.onStory).length}/${llm.length}; commander escalation ${llm.filter((r) => r.escalationToCommander).length}/${llm.length}; pump reached ${llm.filter((r) => r.pump.reached).length}/${llm.length}; decisions by model ${llm.reduce((s, r) => s + r.llm.decisions, 0)}, fallbacks ${llm.reduce((s, r) => s + r.llm.fallbacks, 0)}, lines replaced ${llm.reduce((s, r) => s + r.llm.linesReplaced, 0)}; denied llm proposals ${llm.reduce((s, r) => s + (r.denied.llm ?? 0), 0)}; median per-call p50 ${(q(allMs, 0.5) / 1000).toFixed(1)}s, worst p95 ${(Math.max(...llm.map((r) => r.llm.p95)) / 1000).toFixed(1)}s`);
  console.log(`Rules brains over ${rules.length} seeds: on-story ${rules.filter((r) => r.onStory).length}/${rules.length}; pump reached ${rules.filter((r) => r.pump.reached).length}/${rules.length}; prevented same as LLM on ${llm.filter((r) => rules.find((x) => x.seed === r.seed)?.prevented === r.prevented).length}/${llm.length} seeds`);
}
if (OUT) writeFileSync(OUT, JSON.stringify(results, null, 1));
