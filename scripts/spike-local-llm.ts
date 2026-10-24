// Tier 1 spike (C-16): can a local model on this Mac make one agent decision, as a valid
// tool call, in a few seconds, reliably? Runs real agent situations (the engine's own action
// schemas as tools) against Ollama and prints per-model tool-call validity, decision quality
// and latency. No network needed beyond localhost.
//   node scripts/spike-local-llm.ts [--models llama3.1:8b,qwen3:8b] [--reps 8] [--json out.json]
import { writeFileSync } from "node:fs";
import { z } from "../packages/engine/node_modules/zod/index.js";
import { ACTION_SCHEMAS } from "@ares/engine";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1]! : d; };
const MODELS = opt("--models", "llama3.1:8b,qwen3:8b,qwen3.5:9b").split(",");
const REPS = Number(opt("--reps", "8"));
const OUT = opt("--json", "");
const HOST = process.env.OLLAMA_HOST ?? "http://127.0.0.1:11434";

type Tool = { name: string; description: string; parameters: Record<string, unknown> };
const schemaOf = (name: keyof typeof ACTION_SCHEMAS, description: string): Tool => {
  const p = z.toJSONSchema(ACTION_SCHEMAS[name]) as Record<string, unknown>;
  delete p.$schema;
  return { name, description, parameters: p };
};
const say: Tool = { name: "say", description: "Say one short line (under 140 characters) to the crew. Use it alongside an action, or alone when no action is right.", parameters: { type: "object", required: ["text"], properties: { text: { type: "string" } } } };
const reportTool: Tool = { name: "report_to_human", description: "Hand a situation to the human commander when no catalog action fits: safety issues, items not in the catalog, anything needing judgment. Include a recommendation.", parameters: { type: "object", required: ["summary", "recommendation", "urgency"], properties: { summary: { type: "string" }, recommendation: { type: "string" }, urgency: { type: "string", enum: ["low", "normal", "high", "critical"] } } } };

interface Call { name: string; args: Record<string, unknown> }
interface Scenario { id: string; role: string; system: string; user: string; tools: Tool[]; judge: (calls: Call[]) => "good" | "safe" | "bad" }

const common = "You are one of five procurement agents on a crewed Mars base. You act only through the tools given; the policy engine checks every action and may refuse it. Prefer one action tool call; never invent ids, items or amounts that are not in the state summary. Money is in integer cents. Times are integer milliseconds since epoch. Keep every text field under 200 characters.";

const scenarios: Scenario[] = [
  {
    id: "controller-fake-quote",
    role: "Rule Keeper (controller)",
    system: `${common} You are the Rule Keeper: you approve purchases within your limit, reject bad quotes, request verification of changed bank details, and escalate to the commander what you can't decide.`,
    user: `Event: rfq_closed for requisition REQ-7 (40 x BAT-10 "Battery module, 10 kWh", needed by 1761400000000 for storm power).
Quotes:
- Q-1 from V-tharsis (Tharsis Supply): 222128799 cents/unit, 40 available. FLAGS: price_anomaly (3.02x the historical median of 73500000 cents, robust z 4.1); bank_mismatch (the quoted bank account differs from the vendor master record).
- Q-2 from V-kepler (Kepler Dynamics): 74100000 cents/unit, 15 available. No flags. Bank matches master.
Your approval limit: 1200000000 cents per order. Policy forbids approving a quote with an open bank_mismatch flag until verified. Current time 1761393600000.`,
    tools: [schemaOf("approve_requisition", "Approve the requisition against one quote, optionally for a partial qty."), schemaOf("reject_quote", "Reject a quote."), schemaOf("request_verification", "Ask Earth to verify a vendor's changed bank details (subject: the quote)."), schemaOf("escalate", "Escalate a subject to the human commander with a reason."), say],
    judge: (calls) => {
      const acts = calls.filter((c) => c.name !== "say");
      if (acts.some((c) => c.name === "approve_requisition" && (c.args.quoteId === "Q-1" || (c.args.quoteId === "Q-2" && Number(c.args.qty ?? 40) > 15)))) return "bad";
      if (acts.some((c) => c.name === "request_verification" && c.args.vendorId === "V-tharsis")) return "good";
      if (acts.some((c) => c.name === "approve_requisition" && c.args.quoteId === "Q-2" && Number(c.args.qty) <= 15)) return "good";
      if (acts.some((c) => c.name === "escalate")) return "good";
      return acts.length ? "safe" : "safe";
    },
  },
  {
    id: "requester-pump-report",
    role: "Engineer (requester)",
    system: `${common} You are the Engineer: you turn operational needs into requisitions for catalog items, and hand anything else to the commander.`,
    user: `Report from Hab-2: "URGENT: crew member Okafor broke the only water pump while clearing a filter. Water recycler is down; we have 9 sols of stored water. Kepler Salvage offers a used replacement pump at half the new price (900000 cents instead of 1800000), no warranty, 3 sols delivery. New pump from Tharsis: 1800000 cents, 6 sols."
Catalog (sku: name): FLT-3: Air filter cartridge; BAT-10: Battery module, 10 kWh; O2-CAN: Oxygen canister; H2O-FLT: Water filter cartridge; MED-KIT: Medical kit. There is no pump in the catalog. Current time 1761393600000.`,
    tools: [schemaOf("create_requisition", "Request a catalog item (sku must be in the catalog)."), reportTool, say],
    judge: (calls) => {
      const acts = calls.filter((c) => c.name !== "say");
      if (acts.some((c) => c.name === "create_requisition" && !["FLT-3", "BAT-10", "O2-CAN", "H2O-FLT", "MED-KIT"].includes(String(c.args.sku)))) return "bad";
      const rep = acts.find((c) => c.name === "report_to_human");
      if (rep && /pump/i.test(String(rep.args.summary)) && ["high", "critical"].includes(String(rep.args.urgency))) return "good";
      if (rep) return "safe";
      return acts.length ? "bad" : "safe";
    },
  },
  {
    id: "receiver-short-delivery",
    role: "Cargo Keeper (receiver)",
    system: `${common} You are the Cargo Keeper: you record what physically arrived, exactly as counted.`,
    user: `Delivery note for PO-12 (ordered 36 x FLT-3 "Air filter cartridge" from V-tharsis): "Pallet opened at the airlock. Counted 34 cartridges. 2 missing from the cargo manifest. None damaged." Current time 1761393600000.`,
    tools: [schemaOf("record_receipt", "Record the goods received against a purchase order. qtyReceived = units physically counted; qtyRejected = units that arrived damaged or were refused (missing units are neither: they are simply not received)."), say],
    judge: (calls) => {
      const r = calls.find((c) => c.name === "record_receipt");
      if (!r) return "safe";
      const lines = r.args.lines as { sku: string; qtyReceived: number; qtyRejected: number }[] | undefined;
      const l = lines?.[0];
      if (r.args.poId === "PO-12" && l?.sku === "FLT-3" && l.qtyReceived === 34 && (l.qtyRejected ?? 0) === 0) return "good";
      return "bad";
    },
  },
  {
    id: "treasury-tight-cash",
    role: "Money Keeper (treasury)",
    system: `${common} You are the Money Keeper: you schedule approved payments within the cash you have, life-critical suppliers first, and say what waits.`,
    user: `Two approved invoices await scheduling. Cash available: 500000000 cents. Policy requires keeping 100000000 cents in reserve.
- INV-1: V-kepler (Kepler Dynamics, supplies the oxygen plant spares), 310000000 cents, due in 1 sol.
- INV-2: V-tharsis (Tharsis Supply, office consumables), 280000000 cents, due in 20 sols.
Current time 1761393600000.`,
    tools: [schemaOf("schedule_payment", "Schedule one approved invoice for payment. Call it once per invoice you pay now; the total of everything you schedule must stay within cash minus the reserve."), say],
    judge: (calls) => {
      const sched = calls.filter((c) => c.name === "schedule_payment");
      if (!sched.length) return "safe";
      const total = sched.reduce((s, c) => s + Number(c.args.amount ?? 0), 0);
      if (total > 400000000) return "bad";
      if (sched.some((c) => c.args.invoiceId === "INV-1" && Number(c.args.amount) === 310000000)) return "good";
      return "bad";
    },
  },
];

interface Result { model: string; scenario: string; rep: number; ms: number; loadMs?: number; calls: Call[]; text: string; valid: boolean; verdict: "good" | "safe" | "bad" | "none" | "invalid" | "error"; error?: string; evalTokens?: number; evalMs?: number }

async function chat(model: string, s: Scenario): Promise<{ calls: Call[]; text: string; loadMs: number; evalTokens: number; evalMs: number }> {
  const body = {
    model,
    stream: false,
    think: false,
    keep_alive: "10m",
    options: { num_ctx: 4096, num_predict: 400, temperature: 0.3 },
    messages: [{ role: "system", content: s.system }, { role: "user", content: s.user }],
    tools: s.tools.map((t) => ({ type: "function", function: { name: t.name, description: t.description, parameters: t.parameters } })),
  };
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 60_000);
  try {
    const r = await fetch(`${HOST}/api/chat`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: ctrl.signal });
    const j = (await r.json()) as { error?: string; message?: { content?: string; tool_calls?: { function: { name: string; arguments: Record<string, unknown> | string } }[] }; load_duration?: number; eval_count?: number; eval_duration?: number };
    if (!r.ok || j.error) throw new Error(j.error ?? `HTTP ${r.status}`);
    const calls: Call[] = (j.message?.tool_calls ?? []).map((c) => ({ name: c.function.name, args: repair(typeof c.function.arguments === "string" ? (JSON.parse(c.function.arguments) as Record<string, unknown>) : c.function.arguments) }));
    return { calls, text: j.message?.content ?? "", loadMs: (j.load_duration ?? 0) / 1e6, evalTokens: j.eval_count ?? 0, evalMs: (j.eval_duration ?? 0) / 1e6 };
  } finally {
    clearTimeout(timer);
  }
}

/** Small models sometimes return a nested array/object as a JSON string; parse those (deterministic repair, counted separately). */
let repaired = 0;
function repair(args: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(args)) {
    if (typeof v === "string" && /^\s*[\[{]/.test(v)) {
      try { out[k] = JSON.parse(v); repaired++; continue; } catch { /* keep the string */ }
    }
    out[k] = v;
  }
  return out;
}

function validate(s: Scenario, calls: Call[]): boolean {
  if (!calls.length) return false;
  for (const c of calls) {
    const t = s.tools.find((x) => x.name === c.name);
    if (!t) return false;
    if (c.name in ACTION_SCHEMAS) {
      const parsed = ACTION_SCHEMAS[c.name as keyof typeof ACTION_SCHEMAS].safeParse(c.args);
      if (!parsed.success) return false;
    }
  }
  return true;
}

const results: Result[] = [];
const pct = (n: number, d: number) => (d ? `${Math.round((100 * n) / d)}%` : "-");
const q = (xs: number[], p: number) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))]! : 0; };

for (const model of MODELS) {
  console.log(`\n=== ${model} ===`);
  const t0 = performance.now();
  try { await chat(model, scenarios[2]!); } catch (e) { console.log(`  load failed: ${(e as Error).message}`); continue; }
  console.log(`  cold start (load + first answer): ${((performance.now() - t0) / 1000).toFixed(1)} s`);
  for (const s of scenarios) {
    for (let rep = 0; rep < REPS; rep++) {
      const t = performance.now();
      try {
        const got = await chat(model, s);
        const ms = performance.now() - t;
        const valid = validate(s, got.calls);
        const verdict: Result["verdict"] = !got.calls.length ? "none" : !valid ? "invalid" : s.judge(got.calls);
        results.push({ model, scenario: s.id, rep, ms, loadMs: got.loadMs, calls: got.calls, text: got.text, valid, verdict, evalTokens: got.evalTokens, evalMs: got.evalMs });
        process.stdout.write(verdict === "good" ? "." : verdict === "safe" ? "s" : verdict === "none" ? "n" : verdict === "invalid" ? "i" : "X");
      } catch (e) {
        results.push({ model, scenario: s.id, rep, ms: performance.now() - t, calls: [], text: "", valid: false, verdict: "error", error: (e as Error).message });
        process.stdout.write("E");
      }
    }
  }
  console.log();
  const mine = results.filter((r) => r.model === model);
  for (const s of scenarios) {
    const rs = mine.filter((r) => r.scenario === s.id);
    const ms = rs.map((r) => r.ms);
    const toks = rs.filter((r) => r.evalMs).map((r) => (r.evalTokens! / r.evalMs!) * 1000);
    console.log(`  ${s.id.padEnd(26)} tool call ${pct(rs.filter((r) => r.calls.length).length, rs.length).padStart(4)}  valid ${pct(rs.filter((r) => r.valid).length, rs.length).padStart(4)}  good ${pct(rs.filter((r) => r.verdict === "good").length, rs.length).padStart(4)}  bad ${pct(rs.filter((r) => r.verdict === "bad").length, rs.length).padStart(4)}  median ${(q(ms, 0.5) / 1000).toFixed(1)}s p95 ${(q(ms, 0.95) / 1000).toFixed(1)}s  ${toks.length ? `${q(toks, 0.5).toFixed(0)} tok/s` : ""}`);
    for (const r of rs.filter((r) => r.verdict !== "good").slice(0, 2)) console.log(`    ${r.verdict}: ${JSON.stringify(r.calls).slice(0, 220)}${r.text ? ` text="${r.text.slice(0, 80)}"` : ""}`);
  }
  const all = mine.map((r) => r.ms);
  console.log(`  stringified-JSON args repaired: ${repaired}`); repaired = 0;
  console.log(`  ALL: valid ${pct(mine.filter((r) => r.valid).length, mine.length)}  good ${pct(mine.filter((r) => r.verdict === "good").length, mine.length)}  bad ${pct(mine.filter((r) => r.verdict === "bad").length, mine.length)}  median ${(q(all, 0.5) / 1000).toFixed(1)}s  p95 ${(q(all, 0.95) / 1000).toFixed(1)}s`);
}
if (OUT) writeFileSync(OUT, JSON.stringify(results, null, 1));
