import { formatCents } from "@ares/engine";
import { runEval } from "./index.ts";

const arg = (name: string, def: number) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? Number(process.argv[i + 1]) : def;
};
const sc = await runEval({
  from: arg("from", 1000),
  count: arg("seeds", 100),
  cycles: arg("cycles", 40),
  onProgress: (d, t) => {
    if (d % 25 === 0 || d === t) process.stderr.write(`  ${d}/${t} seeds\n`);
  },
});

const pct = (x: number) => `${(100 * x).toFixed(1)}%`;
console.log(`\nAres evaluation: seeds ${sc.seeds.from}..${sc.seeds.from + sc.seeds.count - 1} (${sc.seeds.count} runs x ${sc.cyclesPerSeed} purchase cycles), policy "${sc.policy.name}" v${sc.policy.version}`);
console.log(`  ${"error type".padEnd(22)} planted  caught  recall`);
for (const p of sc.perError) console.log(`  ${p.type.padEnd(22)} ${String(p.planted).padStart(7)} ${String(p.caught).padStart(7)}  ${pct(p.recall)}`);
console.log(`  overall recall            ${pct(sc.overallRecall)}`);
console.log(`  clean invoices            ${sc.cleanInvoices}  false alarms (not paid in full): ${pct(sc.falseAlarmRate)}  held-then-paid: ${pct(sc.frictionRate)}`);
console.log(`  money saved               ${formatCents(sc.savedCents)}`);
console.log(`  overpaid                  ${formatCents(sc.overpaidCents)}`);
console.log(`  wrongly blocked           ${formatCents(sc.wronglyBlockedCents)}`);
console.log(`  payments to fraud accts   ${sc.fraudPaymentsSent}`);
console.log(`  escalations per cycle     ${sc.escalationRate.toFixed(3)}`);
console.log(`  median days to pay        ${sc.medianDaysToPay?.toFixed(1) ?? "-"}`);
console.log(`  ledger integrity failures ${sc.integrityFailures}`);
console.log(`  proposals ${sc.proposals}, denied by policy ${sc.deniedProposals}`);
console.log(`  took ${(sc.ms / 1000).toFixed(1)} s`);
