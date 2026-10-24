// Finds held-out seeds with missed duplicates or wrongly blocked clean invoices and explains them.
import { defaultRuleBrains, Orchestrator } from "@ares/agents";
import { formatCents } from "@ares/engine";
import { scoreRun } from "@ares/eval";
import { MarsWorld } from "@ares/world-mars";
for (let n = 5000; n < 5100; n++) {
  const seed = `eval-${n}`; const cycles = 30;
  const world = new MarsWorld({ seed, mode: "eval", cycles });
  const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
  await orch.runToQuiescence(world.start + (cycles * 2 + 90) * 86_400_000);
  const e = orch.engine;
  const r = scoreRun(world, e);
  const missedDup = (r.planted.duplicate_invoice ?? 0) - (r.caught.duplicate_invoice ?? 0);
  if (!missedDup && !r.cleanWronglyBlockedCents) continue;
  console.log(`== ${seed}: missed dups ${missedDup}, wrongly blocked ${formatCents(r.cleanWronglyBlockedCents)}`);
  for (const k of world.answerKey.filter((k) => k.kind === "invoice")) {
    const inv = [...e.invoices.values()].find((i) => i.sourceRef === k.docId);
    const paid = inv ? [...e.payments.values()].filter((p) => p.invoiceId === inv.id && p.status === "sent").reduce((s, p) => s + p.amount, 0) : 0;
    const bad = k.errors.includes("duplicate_invoice") ? paid > k.fairCents + 1 : !k.errors.length && paid < k.fairCents - 1;
    if (!bad) continue;
    const sibs = inv?.poId ? [...e.invoices.values()].filter((i) => i.poId === inv.poId).map((i) => `${i.id}:${i.vendorInvoiceNo}:${i.status}:${i.flags.join("/")}:${world.answerKey.find((x) => x.docId === i.sourceRef)?.errors.join("+") || "clean"}`) : [];
    const vendor = inv ? e.vendors.get(inv.vendorId) : undefined;
    console.log(`  ${k.docId} errors=[${k.errors}] decoys=[${k.decoys}] fair ${formatCents(k.fairCents)} paid ${formatCents(paid)} inv=${inv?.id}:${inv?.status} vendor=${vendor?.status}\n    siblings: ${sibs.join(" | ")}`);
    const ds = inv ? e.decisions.filter((d) => (e.proposals.find((p) => p.id === d.proposalId)?.action.params as { invoiceId?: string })?.invoiceId === inv.id) : [];
    for (const d of ds) console.log(`    ${d.actionType}: ${d.verdict} ${d.rules.filter((x) => !x.ok).map((x) => x.rule + "=" + x.detail).join(" | ")}`);
  }
}
