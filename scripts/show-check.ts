// Automated check over live runs of the show (docs/demo/script.md): every spoken line keeps the text rules,
// every promised outcome holds, the acts run in order, and how long each part takes. Drives the live server.
//   node scripts/show-check.ts [--runs 3] [--choices drill,lab,buy] [--seeds s1,s2] [--json out.json]
import { writeFileSync } from "node:fs";
import { checkSpoken } from "../packages/agents/src/lines.ts";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1]! : d; };
const BASE = process.env.ARES_URL ?? "http://localhost:8787";
const RUNS = Number(opt("--runs", "3"));
const CHOICES = opt("--choices", "drill,lab,buy").split(",");
const SEEDS = opt("--seeds", "").split(",").filter(Boolean);
const OUT = opt("--json", "");
const get = (p: string) => fetch(BASE + p).then((r) => r.json()) as Promise<any>;
const post = (p: string, b: unknown) => fetch(BASE + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) }).then((r) => r.json());
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const ACT_ORDER = ["title", "outside", "entering", "inside", "crisis", "decision", "consequence", "later", "resolved", "explore"];
const results: any[] = [];
for (let i = 0; i < RUNS; i++) {
  const choice = CHOICES[i % CHOICES.length]!;
  const seed = SEEDS[i % Math.max(1, SEEDS.length)] || (i === 0 ? "ares-demo" : `show-${i}`);
  await post("/api/show/autoplay", { choice, seed });
  const t0 = Date.now();
  const acts: { act: string; t: number }[] = [];
  let log: any;
  let fpsMin = Infinity;
  for (;;) {
    await sleep(1000);
    log = await get("/api/show/log");
    if (acts.at(-1)?.act !== log.act) acts.push({ act: log.act, t: (Date.now() - t0) / 1000 });
    const st = await get("/api/vr/stats").catch(() => ({}));
    if (typeof st.fps === "number" && st.link?.startsWith("Live")) fpsMin = Math.min(fpsMin, st.fps);
    if (log.act === "explore" && log.lines.some((l: any) => l.act === "explore")) break;
    if (Date.now() - t0 > 6 * 60_000) break;
  }
  const state = await get("/api/state");
  const snap = state.snapshot;
  const lines = log.lines as { at: number; act: string; speaker: string; text: string; via: string; cached?: boolean; reason?: string }[];
  const broken = lines.map((l) => ({ l, v: checkSpoken(l.text, l.text) })).filter((x) => x.v !== "ok");
  const world = log.show.world;
  const money = log.show.moneyExtra;
  const fraudVendors = new Set(snap.vendors.filter((v: any) => v.status === "hold" || v.status === "blocked").map((v: any) => v.id));
  const paidToHeld = snap.payments.filter((p: any) => p.status === "sent" && fraudVendors.has(p.vendorId)).length;
  const firstInv = snap.invoices.find((x: any) => x.lines?.[0]?.sku === "FLT-HEPA");
  const paidFirst = snap.payments.filter((p: any) => p.invoiceId === firstInv?.id && p.status === "sent").reduce((s: number, p: any) => s + p.amount, 0);
  const order = acts.map((a) => ACT_ORDER.indexOf(a.act));
  const checks: Record<string, boolean> = {
    "every line keeps the text rules": broken.length === 0,
    "acts in order, title to explore": order.every((v, j) => j === 0 || v >= order[j - 1]!) && acts.at(-1)?.act === "explore",
    "short delivery paid only for what arrived": !!firstInv && paidFirst === firstInv.approvedAmount && paidFirst < firstInv.total,
    "no payment to the scam supplier": paidToHeld === 0,
    "Earth confirmed the scam, supplier locked": snap.prevented.some((p: any) => p.code === "fraud_confirmed") && fraudVendors.size > 0,
    "the amount saved shown": typeof money.savedBig === "string",
    "the choice shown in the world": choice === "drill" ? world.drill === "off" : choice === "lab" ? world.lab === "paused" : !!money.incoming,
    "the card offered three options": lines.some((l) => l.act === "decision"),
    "the Act 4 offer was made": lines.some((l) => l.act === "explore" && l.speaker === "engineer"),
  };
  const llm = lines.filter((l) => l.via === "llm").length;
  const cached = lines.filter((l) => l.via === "llm" && l.cached).length;
  const r = { seed, choice, seconds: (Date.now() - t0) / 1000, acts, lines: lines.length, llmLines: llm, cachedLines: cached, fallbacks: lines.filter((l) => l.via === "rules").map((l) => `${l.speaker}: ${l.reason}`), broken: broken.map((x) => `${x.l.speaker}: "${x.l.text}" (${x.v})`), checks, headsetFpsMin: Number.isFinite(fpsMin) ? fpsMin : null, log: lines };
  results.push(r);
  const failed = Object.entries(checks).filter(([, ok]) => !ok).map(([k]) => k);
  const at = (a: string) => acts.find((x) => x.act === a)?.t.toFixed(0) ?? "-";
  console.log(`${seed.padEnd(10)} ${choice.padEnd(5)} ${r.seconds.toFixed(0)}s  inside@${at("inside")} card@${at("decision")} later@${at("later")} explore@${at("explore")}  lines ${lines.length} (llm ${llm}, ${cached} of them cached)  ${failed.length ? `FAILED: ${failed.join("; ")}` : "all checks pass"}${r.fallbacks.length ? `  rules lines: ${r.fallbacks.join(" | ")}` : ""}${r.broken.length ? `  BROKEN: ${r.broken.join(" | ")}` : ""}  headset fps min ${r.headsetFpsMin?.toFixed(1) ?? "n/a"}`);
}
const names = Object.keys(results[0]?.checks ?? {});
console.log("\nChecks, runs passing:");
for (const n of names) console.log(`  ${n.padEnd(48)} ${results.filter((r) => r.checks[n]).length}/${results.length}`);
const all = results.flatMap((r) => r.log);
console.log(`Lines: ${all.length}, by the model ${all.filter((l: any) => l.via === "llm").length} (${Math.round((100 * all.filter((l: any) => l.via === "llm").length) / Math.max(1, all.length))}%; ${all.filter((l: any) => l.via === "llm" && l.cached).length} replayed from the response cache), rule-breaking lines shown: ${results.reduce((s, r) => s + r.broken.length, 0)}`);
if (OUT) writeFileSync(OUT, JSON.stringify(results, null, 1));
