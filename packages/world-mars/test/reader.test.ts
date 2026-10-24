import { describe, expect, it } from "vitest";
import { ApWithReader, ControllerRules, Orchestrator, readInvoice, ReceiverRules, RequesterRules, TreasuryRules, type LlmProvider } from "@ares/agents";
import { MarsWorld } from "../src/index.ts";

/** A model that returns a fixed record_invoice call, like the cached gpt-6.1-sol reply to a pasted invoice. */
const fakeLlm = (args: unknown): LlmProvider => ({
  name: "fake",
  model: "fake-model",
  complete: async () => ({ text: "", toolCalls: [{ name: "record_invoice", args }], cached: false, model: "fake-model" }),
});

async function afterDelivery() {
  const world = new MarsWorld({ seed: "ares-demo", mode: "demo" });
  const brains = (llm?: LlmProvider) => [new RequesterRules(), new ReceiverRules(), new ApWithReader(llm), new TreasuryRules(), new ControllerRules()];
  return { world, brains };
}

describe("pasted invoice read by an LLM", () => {
  it("a charge for something we don't stock is left out, and the controls still catch the new bank and the overbilling", async () => {
    const { world, brains } = await afterDelivery();
    let llm: LlmProvider | undefined;
    const orch = new Orchestrator({ world, brains: brains({ name: "lazy", model: "lazy", complete: (req) => llm!.complete(req) }), fmtTime: world.fmtTime });
    const e = orch.engine;
    await orch.runUntil(world.start);
    orch.scheduleAll(world.beatDelivery(e));
    await orch.runUntil(e.now + 3600e3);
    const po = [...e.pos.values()][0]!;
    const line = po.lines[0]!;
    llm = fakeLlm({
      vendorId: po.vendorId,
      vendorInvoiceNo: "HX-20917",
      poId: po.id,
      lines: [{ sku: line.sku, qty: line.qty + 4, unitPrice: line.unitPrice }, { sku: "rush handling", qty: 1, unitPrice: 250_000 }],
      bank: { holder: "Holdings LLC", bank: "First Meridian Bank", routing: "121000358", account: "5550012345" },
      issuedAt: e.now,
      dueAt: e.now + 15 * 86_400_000,
      sourceRef: "pasted",
    });

    const got = await readInvoice("(pasted text)", e, llm);
    expect(got!.params.lines.map((l) => l.sku)).toEqual([line.sku]);
    expect(got!.excluded).toEqual(['"rush handling" ($2,500.00)']);

    const before = e.invoices.size;
    orch.schedule(e.now, { type: "document", doc: { id: "DOC-TXT-1", kind: "invoice", from: "pasted", text: "(pasted text)", fields: {} } });
    await orch.runUntil(e.now + 600e3);
    expect(e.invoices.size).toBe(before + 1);
    const inv = [...e.invoices.values()].at(-1)!;
    expect(inv.status).not.toBe("paid");
    expect(inv.flags).toEqual(expect.arrayContaining(["bank_mismatch", "qty_over_receipt"]));
    expect([...e.verifications.values()].some((v) => v.status === "pending")).toBe(true);
    expect([...e.payments.values()].filter((p) => p.invoiceId === inv.id)).toHaveLength(0);
  });

  it("an invoice made only of unknown items is passed through unchanged, so policy refuses it", async () => {
    const { world } = await afterDelivery();
    const e = new Orchestrator({ world, brains: [], fmtTime: world.fmtTime }).engine;
    const vendorId = [...e.vendors.keys()][0]!;
    const got = await readInvoice("x", e, fakeLlm({ vendorId, vendorInvoiceNo: "X-1", lines: [{ sku: "consulting", qty: 1, unitPrice: 100 }], bank: { holder: "a", bank: "b", routing: "1", account: "2" }, issuedAt: 0, dueAt: 0 }));
    expect(got?.excluded).toBeUndefined();
    expect(got?.params.lines[0]!.sku).toBe("consulting");
  });
});
