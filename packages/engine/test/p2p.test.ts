import { describe, expect, it } from "vitest";
import { ACTORS, bankA, bankAFake, bankB, DAY, HOUR, makeEngine, requisitionWithQuotes, T0 } from "./fixtures.ts";

function fullCycle(billedQty: number, receivedQty: number, billedPrice = 12_000) {
  const e = makeEngine();
  const { reqId, quoteIds } = requisitionWithQuotes(e, "FLT", 36, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
  const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
  expect(appr.decision.verdict).toBe("allow");
  const poId = appr.created!.id;
  e.submit({ actorId: "rcv", type: "record_receipt", params: { poId, lines: [{ sku: "FLT", qtyReceived: receivedQty, qtyRejected: 0 }] } });
  const inv = e.submit({
    actorId: "ap",
    type: "record_invoice",
    params: { vendorId: "V-A", vendorInvoiceNo: "A-1001", poId, lines: [{ sku: "FLT", qty: billedQty, unitPrice: billedPrice }], bank: bankA, issuedAt: T0, dueAt: T0 + 30 * DAY },
  });
  return { e, poId, invId: inv.created!.id, reqId };
}

describe("procure-to-pay happy path", () => {
  it("short delivery: billed 36, received 34, pays only 34", () => {
    const { e, invId } = fullCycle(36, 34);
    const m = e.computeMatch(e.invoices.get(invId)!);
    expect(m.payable).toBe(34 * 12_000);

    // Proposing the billed total is refused; the matched amount is accepted.
    const wrong = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 36 * 12_000 } });
    expect(wrong.decision.verdict).toBe("deny");
    const ok = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 34 * 12_000 } });
    expect(ok.decision.verdict).toBe("allow");
    expect(e.prevented.reduce((s, p) => s + p.amount, 0)).toBe(2 * 12_000);

    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("allow");
    const sch = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 34 * 12_000 } });
    expect(sch.decision.verdict).toBe("allow");
    const cashBefore = e.ledger.balance("cash");
    const ex = e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: sch.created!.id } });
    expect(ex.decision.verdict).toBe("allow");
    expect(e.ledger.balance("cash")).toBe(cashBefore - 34 * 12_000);
    expect(e.invoices.get(invId)!.status).toBe("paid");
    expect(e.ledger.balance("ap", "V-A")).toBe(0);
    expect(e.ledger.balance("grni")).toBe(0);
    expect(e.ledger.verify().ok).toBe(true);
  });

  it("every ledger entry traces back to its sources, rules and approvers", () => {
    const { e, invId } = fullCycle(36, 34);
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 34 * 12_000 } });
    e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } });
    const sch = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 34 * 12_000 } });
    e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: sch.created!.id } });
    for (const entry of e.ledger.all()) {
      const t = e.trace(entry.id)!;
      expect(t.decision?.verdict ?? "allow").toBe("allow");
      expect(t.sources.length).toBeGreaterThan(0);
    }
    const payEntry = e.ledger.all().at(-1)!;
    const t = e.trace(payEntry.id)!;
    const kinds = t.sources.map((s) => s.ref.kind);
    expect(kinds).toEqual(expect.arrayContaining(["payment", "invoice", "po", "receipt", "proposal"]));
    expect(payEntry.approvers).toEqual(["ctl"]);
    expect(t.decision!.rules.map((r) => r.rule)).toEqual(expect.arrayContaining(["payment.to_master_bank", "sod.approver_not_payer"]));
  });
});

describe("controls", () => {
  it("duplicate invoice number is denied", () => {
    const { e, poId, invId } = fullCycle(34, 34);
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 34 * 12_000 } });
    e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } });
    const dup = e.submit({
      actorId: "ap",
      type: "record_invoice",
      params: { vendorId: "V-A", vendorInvoiceNo: "a-1001 ", poId, lines: [{ sku: "FLT", qty: 34, unitPrice: 12_000 }], bank: bankA, issuedAt: T0, dueAt: T0 + 30 * DAY },
    });
    const sub = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: dup.created!.id, amount: 0 } });
    expect(sub.decision.verdict).toBe("deny");
    expect(sub.decision.rules.find((r) => r.rule === "dup.invoice_number")?.ok).toBe(false);
  });

  it("price above PO beyond tolerance is held", () => {
    const { e, invId } = fullCycle(34, 34, 12_600);
    const m = e.computeMatch(e.invoices.get(invId)!);
    const sub = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: m.payable } });
    expect(sub.decision.verdict).toBe("hold");
    expect(e.invoices.get(invId)!.status).toBe("held");
    expect(e.invoices.get(invId)!.flags).toContain("price_over_po");
  });

  it("changed bank details on an invoice hold payment and trigger verification", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "FLT", 10, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
    const poId = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).created!.id;
    e.submit({ actorId: "rcv", type: "record_receipt", params: { poId, lines: [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }] } });
    const invId = e.submit({
      actorId: "ap",
      type: "record_invoice",
      params: { vendorId: "V-A", vendorInvoiceNo: "A-2", poId, lines: [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], bank: bankAFake, issuedAt: T0, dueAt: T0 + 30 * DAY },
    }).created!.id;
    const sub = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 120_000 } });
    expect(sub.decision.verdict).toBe("hold");
    expect([...e.verifications.values()]).toHaveLength(1);
    // The treasurer can't pay a held invoice.
    expect(e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).decision.verdict).toBe("deny");
  });

  it("the main scenario: inflated quote with new bank details -> hold, verify, escalate locally with options", () => {
    const e = makeEngine();
    // Order deadline is sooner than the remote authority can answer, so the local authority decides.
    const orderBy = T0 + 40 * 60_000;
    const { reqId, quoteIds } = requisitionWithQuotes(
      e,
      "BAT",
      40,
      [
        { vendorId: "V-A", unitPrice: 240_000, qtyAvailable: 40, bank: bankAFake, terms: "prepay" },
        { vendorId: "V-B", unitPrice: 96_000, qtyAvailable: 20, bank: bankB },
      ],
      orderBy,
    );
    const [bad, good] = quoteIds as [string, string];
    expect(e.quotes.get(bad)!.flags).toEqual(expect.arrayContaining(["bank_mismatch", "price_anomaly"]));
    expect(e.quotes.get(good)!.flags).toEqual([]);

    const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: bad } });
    expect(appr.decision.verdict).toBe("hold");
    expect(e.pos.size).toBe(0);
    const ver = [...e.verifications.values()];
    expect(ver).toHaveLength(1);
    const esc = [...e.escalations.values()];
    expect(esc).toHaveLength(1);
    expect(esc[0]!.to).toBe("local_authority");
    expect(esc[0]!.status).toBe("awaiting_decision");
    const labels = esc[0]!.options.map((o) => o.id);
    expect(labels).toEqual(expect.arrayContaining([`buy-${good}`, "wait", "lever-shed", "reject"]));
    const buy = esc[0]!.options.find((o) => o.id === `buy-${good}`)!;
    // 15,000.00 limit / 960.00 = 15 units
    expect(buy.label).toContain("Buy 15");

    // A forged decision from the wrong authority is refused.
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc[0]!.id, optionId: buy.id } }).decision.verdict).toBe("deny");
    const dec = e.submit({ actorId: "loc", type: "decide", params: { escalationId: esc[0]!.id, optionId: buy.id } });
    expect(dec.decision.verdict).toBe("allow");
    const po = [...e.pos.values()][0]!;
    expect(po.vendorId).toBe("V-B");
    expect(po.lines[0]!.qty).toBe(15);
    expect(po.approvedBy).toEqual(["loc"]);

    // The remote party answers after the round trip: the bank change was fake.
    e.scheduleInbound({ actorId: "rem", type: "answer_verification", params: { verificationId: ver[0]!.id, confirmed: false, answer: "Supplier never changed bank details" }, source: "human" }, ver[0]!.arrivesAt + 3 * HOUR);
    e.advanceTo(T0 + 6 * HOUR);
    expect(ver[0]!.status).toBe("rejected");
    expect(e.quotes.get(bad)!.status).toBe("rejected");
    const saved = e.prevented.find((p) => p.code === "fraud_confirmed")!;
    expect(saved.amount).toBe(240_000 * 40);
    expect(e.vendors.get("V-A")!.bank).toEqual(bankA);
    expect(e.ledger.verify().ok).toBe(true);
  });

  it("over the agent's approval limit escalates to the remote authority when there is time", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
    expect(appr.decision.verdict).toBe("escalate");
    const esc = [...e.escalations.values()][0]!;
    expect(esc.to).toBe("remote_authority");
    expect(esc.status).toBe("in_transit");
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: esc.options[0]!.id } }).decision.verdict).toBe("deny");
    e.advanceTo(esc.deliverAt);
    expect(esc.status).toBe("awaiting_decision");
    const buy = esc.options.find((o) => o.id.startsWith("buy-"))!;
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: buy.id } }).decision.verdict).toBe("allow");
    expect(e.pos.size).toBe(1);
  });

  it("policy edit changes behaviour: lower agent limit forces escalation", () => {
    const e = makeEngine({}, { approval: { agentMaxCents: 100_000, localAuthorityMaxCents: 1_500_000, remoteAuthorityMaxCents: 100_000_000 } });
    const { reqId, quoteIds } = requisitionWithQuotes(e, "FLT", 36, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
    expect(e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).decision.verdict).toBe("escalate");
  });

  it("segregation of duties holds even when a policy grants extra permissions", () => {
    const e = makeEngine();
    const p = structuredClone(e.policy);
    p.permissions.controller = [...(p.permissions.controller ?? []), "create_requisition", "schedule_payment"];
    e.setPolicy(p, "admin");
    const r = e.submit({ actorId: "ctl", type: "create_requisition", params: { sku: "FLT", qty: 5, orderBy: T0 + 30 * DAY, reason: "self-dealing" } });
    e.submit({ actorId: "tre", type: "confirm_funds", params: { requisitionId: r.created!.id } });
    const q = e.submit({
      actorId: "ap",
      type: "record_quote",
      params: { vendorId: "V-A", sku: "FLT", unitPrice: 12_000, qtyAvailable: 10, bank: bankA, terms: "on_receipt", validUntil: T0 + DAY, requisitionId: r.created!.id },
    });
    const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: r.created!.id, quoteId: q.created!.id } });
    expect(appr.decision.verdict).toBe("deny");
    expect(appr.decision.rules.find((x) => x.rule === "sod.requester_not_approver")?.ok).toBe(false);
  });

  it("forbidden actions are denied for every role", () => {
    const e = makeEngine();
    for (const a of ACTORS) {
      const allowed = new Set(e.policy.permissions[a.role] ?? []);
      for (const t of ["approve_invoice", "execute_payment", "create_requisition", "record_receipt", "decide", "answer_verification"]) {
        if (allowed.has(t as never)) continue;
        const res = e.submit({ actorId: a.id, type: t, params: {} });
        expect(res.executed).toBe(false);
      }
    }
  });
});
