import { defaultRuleBrains, Orchestrator } from "@ares/agents";
import { bankKey, formatCents } from "@ares/engine";
import { MarsWorld } from "@ares/world-mars";
const seed = process.argv[2] ?? "eval-1";
const cycles = 30;
const world = new MarsWorld({ seed, mode: "eval", cycles });
const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
await orch.runToQuiescence(world.start + (cycles * 2 + 90) * 86_400_000);
const e = orch.engine;
const inv = new Map([...e.invoices.values()].map((i) => [i.sourceRef, i]));
const statusCount: Record<string, number> = {};
for (const k of world.answerKey.filter((k) => k.kind === "invoice" && k.errors.filter((x) => x !== "short_delivery" || k.billedCents > k.fairCents).length === 0)) {
  const i = inv.get(k.docId);
  const paid = i ? [...e.payments.values()].filter((p) => p.invoiceId === i.id && p.status === "sent").reduce((s, p) => s + p.amount, 0) : 0;
  if (paid >= k.fairCents - 1) continue;
  const key = `${i?.status ?? "missing"} flags=${i?.flags.join(",")} decoys=${k.decoys.join(",")}`;
  statusCount[key] = (statusCount[key] ?? 0) + 1;
  if ((statusCount[key] ?? 0) <= 1) {
    const ds = !i ? [] : e.decisions.filter((d) => (e.proposals.find((p) => p.id === d.proposalId)?.action.params as any)?.invoiceId === i.id).map((d) => `${d.actionType}:${d.verdict}:${d.rules.filter((r) => !r.ok).map((r) => r.rule + "=" + r.detail).join("|")}`);
    console.log("UNPAID", k.docId, key, "fair", formatCents(k.fairCents), "paid", formatCents(paid), "\n   ", ds.join("\n    "));
  }
}
console.log(statusCount);
const fraud = new Set<string>();
for (const v of e.verifications.values()) if (v.status === "rejected") fraud.add(bankKey(v.claimedBank));
for (const i of e.invoices.values()) if (i.voidedAsFraud) fraud.add(bankKey(i.bank));
for (const p of e.payments.values()) if (p.status === "sent" && fraud.has(bankKey(p.bank))) console.log("FRAUD PAYMENT", p, e.vendors.get(p.vendorId));
console.log("cash", formatCents(e.ledger.balance("cash")), "runway", e.runwayDays().toFixed(0));
