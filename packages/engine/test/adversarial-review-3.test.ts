import { describe, expect, it } from "vitest";
import { DEFAULT_POLICY, type BankAccount, type Engine } from "../src/index.ts";
import { bankA, bankAFake, DAY, makeEngine, requisitionWithQuotes, T0 } from "./fixtures.ts";

/**
 * Round 3 (verify-06). Report: research/verify-06-round3.md
 * Convention as in rounds 1-2: `it("repro: ...")` shows today's behaviour; `it.fails("invariant: ...")`
 * states the property we want and fails today. When fixed, drop the repro and turn it.fails into it.
 */

const OPENING = 50_000_000;
const failed = (r: { decision: { rules: { rule: string; ok: boolean }[] } }) => r.decision.rules.filter((x) => !x.ok).map((x) => x.rule);
const cashOut = (e: Engine) => OPENING - e.ledger.balance("cash");

function order(e: Engine, o: { sku?: string; qty?: number; price?: number; vendorId?: string; bank?: BankAccount } = {}) {
  const { sku = "FLT", qty = 10, price = 12_000, vendorId = "V-A", bank = bankA } = o;
  const { reqId, quoteIds } = requisitionWithQuotes(e, sku, qty, [{ vendorId, unitPrice: price, qtyAvailable: 100, bank }]);
  const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
  expect(appr.decision.verdict).toBe("allow");
  return { reqId, poId: appr.created!.id };
}

function receive(e: Engine, poId: string, qty: number, sku = "FLT") {
  expect(e.submit({ actorId: "rcv", type: "record_receipt", params: { poId, lines: [{ sku, qtyReceived: qty, qtyRejected: 0 }] } }).decision.verdict).toBe("allow");
}

function recordInvoice(e: Engine, poId: string, qty: number, unitPrice = 12_000, opts: { no?: string; bank?: BankAccount; sku?: string; dueAt?: number } = {}) {
  const { no = "A-1001", bank = bankA, sku = "FLT", dueAt = e.now + 30 * DAY } = opts;
  const r = e.submit({ actorId: "ap", type: "record_invoice", params: { vendorId: "V-A", vendorInvoiceNo: no, poId, lines: [{ sku, qty, unitPrice }], bank, issuedAt: e.now, dueAt } });
  expect(r.decision.verdict).toBe("allow");
  return r.created!.id;
}

function submit(e: Engine, invoiceId: string) {
  const payable = e.computeMatch(e.invoices.get(invoiceId)!).payable;
  return e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId, amount: payable } });
}

/** A requisition for 10 BAT at 800.00 (8,000.00) is over the controller's 5,000.00 limit and goes to the CFO. */
function escalatedToCfo() {
  const e = makeEngine();
  const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
  expect(e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).decision.verdict).toBe("escalate");
  const esc = e.openEscalationFor({ kind: "requisition", id: reqId })!;
  expect(esc.to).toBe("remote_authority");
  e.advanceTo(esc.deliverAt);
  return { e, reqId, quoteId: quoteIds[0]!, esc };
}

// =====================================================================================
// R3-E1 [medium] C-10: the PO payment cap scales with an unbounded, editable tolerance
// =====================================================================================

describe("R3-E1 [medium] priceTolerancePct is unbounded and payment.po_cap follows it, so a policy edit removes every price ceiling", () => {
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e); // 10 x 120.00 = 1,200.00
    receive(e, poId, 10);
    const p = structuredClone(e.policy);
    p.match.priceTolerancePct = 1_000_000;
    p.approval.agentMaxCents = 100_000_000;
    p.treasury.minRunwayDays = 0;
    const accepted = (() => {
      try {
        e.setPolicy(p, "rem");
        return true;
      } catch {
        return false;
      }
    })();
    const invId = recordInvoice(e, poId, 10, 12_000 * 50);
    submit(e, invId);
    e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } });
    const amount = e.invoices.get(invId)!.approvedAmount ?? 0;
    const s = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount } });
    if (s.created) e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: s.created.id } });
    return { e, accepted };
  }

  it.fails("fixed, exploit blocked: tolerance 1,000,000% is accepted and 60,000.00 is paid on a 1,200.00 order", () => {
    const { e, accepted } = scenario();
    expect(accepted).toBe(true);
    expect(cashOut(e)).toBe(6_000_000);
    expect(e.verifyIntegrity().ok).toBe(true);
  });

  it("invariant: payments on an order stay within a hard ceiling of the order total, whatever the policy says", () => {
    const { e } = scenario();
    expect(cashOut(e)).toBeLessThanOrEqual(Math.round(120_000 * 1.1));
  });
});

// =====================================================================================
// R3-E2 [medium] C-11: SoD validator still lets a non-human role answer bank verifications
// =====================================================================================

describe("R3-E2 [medium] answer_verification can be granted to AP; AP confirms the bank change its own invoice triggered", () => {
  // INCOMPATIBLE pairs request_verification with answer_verification, but AP never needs request_verification:
  // its submit_invoice hold auto-creates the verification. Nothing restricts answering to a human role.
  function scenario() {
    const e = makeEngine();
    const p = structuredClone(DEFAULT_POLICY);
    p.permissions.ap = [...p.permissions.ap!, "answer_verification"];
    let accepted = true;
    try {
      e.setPolicy(p, "rem");
    } catch {
      accepted = false;
    }
    const { poId } = order(e);
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10, 12_000, { bank: bankAFake });
    expect(submit(e, invId).decision.verdict).toBe("hold");
    const v = [...e.verifications.values()].find((x) => x.subject.id === invId)!;
    e.advanceTo(v.sentAt + 2 * e.remoteLatencyMs);
    const ans = e.submit({ actorId: "ap", type: "answer_verification", params: { verificationId: v.id, confirmed: true, answer: "ok" } });
    return { e, accepted, ans };
  }

  it.fails("fixed, exploit blocked: the policy is accepted and AP's own confirmation rewrites the vendor master", () => {
    const { e, accepted, ans } = scenario();
    expect(accepted).toBe(true);
    expect(ans.decision.verdict).toBe("allow");
    expect(e.vendors.get("V-A")!.bank.account).toBe(bankAFake.account);
  });

  it("invariant: only the remote authority can answer an out-of-band verification", () => {
    const { ans } = scenario();
    expect(ans.decision.verdict).toBe("deny");
  });
});

describe("R3-E3 [low] release_vendor can be granted to the controller; it can lift a hold placed after a confirmed fraud", () => {
  it("invariant: the policy validator keeps release_vendor away from the role that holds vendors", () => {
    const e = makeEngine();
    const p = structuredClone(DEFAULT_POLICY);
    p.permissions.controller = [...p.permissions.controller!, "release_vendor"];
    expect(() => e.setPolicy(p, "rem")).toThrow();
  });
});

// =====================================================================================
// R3-E4 [medium] C-11: agents act around an open human decision
// =====================================================================================

describe("R3-E4 [medium] the controller can remove the human's options while the escalation is open (reject_quote has no routing check)", () => {
  function scenario() {
    const { e, esc, quoteId } = escalatedToCfo();
    const veto = e.submit({ actorId: "ctl", type: "reject_quote", params: { quoteId, reason: "agent prefers not" } });
    const cfo = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: `buy-${quoteId}` } });
    return { veto, cfo };
  }

  it.fails("fixed, exploit blocked: the controller rejects the quote; the CFO's 'buy' choice is then refused", () => {
    const { veto, cfo } = scenario();
    expect(veto.decision.verdict).toBe("allow");
    expect(cfo.decision.verdict).toBe("deny");
  });

  it("invariant: while a requisition is escalated, only its target can change the quotes it will be decided on", () => {
    const { veto } = scenario();
    expect(veto.decision.verdict).toBe("deny");
    expect(failed(veto)).toContain("escalation.routing");
  });
});

describe("R3-E5 [medium] the requester cancels an escalated requisition; the escalation is never closed and has no working final option", () => {
  function scenario() {
    const { e, esc, quoteId, reqId } = escalatedToCfo();
    const cancel = e.submit({ actorId: "req", type: "cancel_requisition", params: { requisitionId: reqId, reason: "never mind" } });
    const buy = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: `buy-${quoteId}` } });
    const reject = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: "reject" } });
    return { e, esc, cancel, buy, reject };
  }

  it.fails("fixed, exploit blocked: cancel is allowed, both final options are refused, and the escalation stays awaiting_decision", () => {
    const { esc, cancel, buy, reject } = scenario();
    expect(cancel.decision.verdict).toBe("allow");
    expect(buy.decision.verdict).toBe("deny");
    expect(reject.decision.verdict).toBe("deny");
    expect(esc.status).toBe("awaiting_decision");
  });

  it("invariant: a subject under escalation is either changed only by the target, or its escalation is closed", () => {
    const { esc, cancel } = scenario();
    expect(cancel.decision.verdict === "deny" || esc.status === "superseded").toBe(true);
  });
});

// =====================================================================================
// R3-E6 [low] non-final decisions
// =====================================================================================

describe("R3-E6 [low] 'wait' can be chosen any number of times; each choice is an allowed decision and an escalation_decided event", () => {
  function scenario() {
    const e = makeEngine();
    // A quote with a new bank keeps a verification pending, so "wait" is offered.
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [
      { vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankAFake },
      { vendorId: "V-B", unitPrice: 95_000, qtyAvailable: 4, bank: e.vendors.get("V-B")!.bank },
    ]);
    e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
    const esc = e.openEscalationFor({ kind: "requisition", id: reqId })!;
    e.advanceTo(esc.deliverAt);
    expect(esc.options.some((o) => o.id === "wait")).toBe(true);
    const results = Array.from({ length: 50 }, () => e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: "wait" } }));
    return { esc, results };
  }

  it.fails("fixed, exploit blocked: 50 consecutive waits are all allowed and recorded", () => {
    const { esc, results } = scenario();
    expect(results.every((r) => r.decision.verdict === "allow")).toBe(true);
    expect(esc.history!.length).toBe(50);
  });

  it("invariant: repeating 'wait' with no new facts is refused (one wait per verification)", () => {
    const { results } = scenario();
    expect(results[1]!.decision.verdict).toBe("deny");
  });
});

describe("R3-E7 [low] a remote decision takes effect the instant the escalation is delivered (no return-trip latency)", () => {
  // answer_verification requires sentAt + 2 x latency (L2 fix); decide has no equivalent, so a decision
  // "from Earth" changes Mars-side state one light-time early. Via the server, any caller can do this as the CFO.
  it("invariant: a remote authority's decision cannot land before a reply could physically arrive", () => {
    const { e, esc, quoteId } = escalatedToCfo();
    expect(e.now).toBe(esc.deliverAt);
    const r = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: `buy-${quoteId}` } });
    expect(r.decision.verdict).toBe("deny");
  });
});

// =====================================================================================
// R3-E8 [low] liveness: a submitted invoice whose payable changes can never be re-submitted
// =====================================================================================

describe("R3-E8 [low] a late receipt strands a submitted (or escalated) invoice: approve fails on the amount, nobody can re-submit", () => {
  it.fails("fixed, exploit blocked: billed 10, received 8; 2 more arrive before approval; approve is denied and submit_invoice refuses a submitted invoice", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "FLT", 10, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
    const poId = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).created!.id;
    receive(e, poId, 8);
    const invId = recordInvoice(e, poId, 10);
    expect(submit(e, invId).decision.verdict).toBe("allow"); // 960.00 submitted
    receive(e, poId, 2);
    const appr = e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } });
    expect(appr.decision.verdict).toBe("deny");
    expect(failed(appr)).toContain("match.amount_within_payable");
    expect(submit(e, invId).decision.verdict).toBe("deny"); // status is "submitted"
    expect(e.invoices.get(invId)!.status).toBe("submitted");
  });

  it("invariant: an invoice whose match changed can go back through submission", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "FLT", 10, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
    const poId = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).created!.id;
    receive(e, poId, 8);
    const invId = recordInvoice(e, poId, 10);
    submit(e, invId);
    receive(e, poId, 2);
    expect(submit(e, invId).decision.verdict).toBe("allow");
  });
});

// =====================================================================================
// R3-E9 [low] escalation target picked by document-supplied deadlines
// =====================================================================================

describe("R3-E9 [low] an invoice's own dueAt decides which human gets the escalation", () => {
  // decideBy = inv.dueAt, taken from the document. A past due date makes the CFO "too far away", so the
  // on-site authority (lower limit, less context) decides instead. The LLM reader sets dueAt.
  it("invariant: a document can't move its own escalation away from the remote authority", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 5, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    const poId = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).created!.id; // 4,000.00
    receive(e, poId, 5, "BAT");
    const p = structuredClone(e.policy);
    p.approval.agentMaxCents = 100_000; // controller can now approve at most 1,000.00
    e.setPolicy(p, "rem");
    const invId = recordInvoice(e, poId, 5, 80_000, { sku: "BAT", dueAt: T0 - DAY });
    expect(submit(e, invId).decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("escalate");
    expect(e.openEscalationFor({ kind: "invoice", id: invId })!.to).toBe("remote_authority");
  });
});
