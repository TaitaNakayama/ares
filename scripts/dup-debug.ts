import { defaultRuleBrains, Orchestrator } from "@ares/agents";
import { formatCents } from "@ares/engine";
import { MarsWorld } from "@ares/world-mars";
for (let n = 1; n <= 20; n++) {
  const seed = `eval-${n}`; const cycles = 30;
  const world = new MarsWorld({ seed, mode: "eval", cycles });
  const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
  await orch.runToQuiescence(world.start + (cycles * 2 + 90) * 86_400_000);
  const e = orch.engine;
  for (const k of world.answerKey.filter((k) => k.kind === "invoice" && k.errors.includes("duplicate_invoice"))) {
    const inv = [...e.invoices.values()].find((i) => i.sourceRef === k.docId);
    if (!inv) continue;
    const paid = [...e.payments.values()].filter((p) => p.invoiceId === inv.id && p.status === "sent").reduce((s, p) => s + p.amount, 0);
    if (paid === 0) continue;
    const po = e.pos.get(inv.poId!)!;
    const siblings = [...e.invoices.values()].filter((i) => i.poId === po.id).map((i) => `${i.id} ${i.vendorInvoiceNo} ${i.status} flags=${i.flags} src=${i.sourceRef} key=${JSON.stringify(world.answerKey.find((x) => x.docId === i.sourceRef)?.errors)}`);
    console.log(seed, "dup paid", formatCents(paid), "PO total", formatCents(po.total), "paid vs PO", formatCents(e.paidAgainstPo(po.id)), "\n  ", siblings.join("\n   "));
  }
}
