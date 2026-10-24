import { describe, expect, it } from "vitest";
import {
  bankKey,
  canonicalJson,
  type PostingAuthorization,
  sha256,
  type Actor,
  type BankAccount,
  type Decision,
  type Engine,
  type JournalEntry,
} from "../src/index.ts";
import { ACTORS, bankA, bankAFake, bankB, DAY, makeEngine, requisitionWithQuotes, T0 } from "./fixtures.ts";

/**
 * Adversarial review of the ledger and permission claims (verify-04).
 * Report: research/verify-04-engine-review.md
 *
 * How to read this file
 * - `it.fails("fixed, exploit blocked: ...")` asserts what the engine does today. It proves the exploit
 *   is real and fails for the right reason, not because of a setup mistake.
 * - `it("invariant: ...")` asserts the claimed property. It fails today, so
 *   vitest reports it as passing ("expected fail"). When a bug is fixed, both
 *   tests flip: delete the repro and turn `it.fails` into `it`.
 * - `describe("HOLDS: ...")` blocks check attacks the engine resists.
 */

const OPENING = 50_000_000;

// ---------------------------------------------------------------- helpers

function order(
  e: Engine,
  o: { sku?: string; qty?: number; price?: number; vendorId?: string; bank?: BankAccount; terms?: "prepay" | "on_receipt"; approver?: string } = {},
) {
  const { sku = "FLT", qty = 10, price = 12_000, vendorId = "V-A", bank = bankA, terms = "on_receipt", approver = "ctl" } = o;
  const { reqId, quoteIds } = requisitionWithQuotes(e, sku, qty, [{ vendorId, unitPrice: price, qtyAvailable: 100, bank, terms }]);
  const appr = e.submit({ actorId: approver, type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
  expect(appr.decision.verdict).toBe("allow");
  return { reqId, quoteId: quoteIds[0]!, poId: appr.created!.id };
}

function receive(e: Engine, poId: string, lines: { sku: string; qtyReceived: number; qtyRejected: number }[], actorId = "rcv") {
  return e.submit({ actorId, type: "record_receipt", params: { poId, lines } });
}

function recordInvoice(e: Engine, poId: string, lines: { sku: string; qty: number; unitPrice: number }[], no = "A-1001", bank: BankAccount = bankA, vendorId = "V-A") {
  const r = e.submit({ actorId: "ap", type: "record_invoice", params: { vendorId, vendorInvoiceNo: no, poId, lines, bank, issuedAt: e.now, dueAt: e.now + 30 * DAY } });
  // Lenient after the fixes: an exploit step may now be denied; the invariant tests check the end state.
  return r.created?.id ?? "INV-NONE";
}

/** AP submits the matched amount, the controller approves. Returns the approved amount. */
function submitAndApprove(e: Engine, invoiceId: string, approver = "ctl") {
  const inv = e.invoices.get(invoiceId);
  if (!inv) return 0;
  const payable = e.computeMatch(inv).payable;
  e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId, amount: payable } });
  e.submit({ actorId: approver, type: "approve_invoice", params: { invoiceId } });
  return payable;
}

function pay(e: Engine, target: { invoiceId?: string; poId?: string }, amount: number, actorId = "tre") {
  const schedule = e.submit({ actorId, type: "schedule_payment", params: { ...target, amount } });
  const execute = schedule.created ? e.submit({ actorId, type: "execute_payment", params: { paymentId: schedule.created.id } }) : undefined;
  return { schedule, execute };
}

const cashOut = (e: Engine) => OPENING - e.ledger.balance("cash");
const verdictOf = (e: Engine, decisionId: string) => e.decisions.find((d) => d.id === decisionId)?.verdict;
/** State that a denied proposal must never touch. */
const stateOf = (e: Engine) =>
  JSON.stringify({
    reqs: [...e.requisitions.values()],
    quotes: [...e.quotes.values()],
    pos: [...e.pos.values()],
    receipts: [...e.receipts.values()],
    invoices: [...e.invoices.values()],
    payments: [...e.payments.values()],
    vendors: [...e.vendors.values()],
    verifications: [...e.verifications.values()],
    escalations: [...e.escalations.values()],
    ledger: e.ledger.all().length,
    flags: e.flags.length,
  });

// =====================================================================================
// CRITICAL
// =====================================================================================

describe("C1 [critical] a `hold` verdict on schedule_payment / execute_payment still moves money", () => {
  // The controller puts the vendor on hold ("stop all payments"). The treasurer schedules and
  // sends anyway: vendor.active fails with effect "hold", submit() only stops on "deny", and the
  // executor for these two actions never looks at the verdict.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    expect(receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]).decision.verdict).toBe("allow");
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    submitAndApprove(e, invId);
    expect(e.submit({ actorId: "ctl", type: "hold_vendor", params: { vendorId: "V-A", reason: "suspected fraud: stop all payments" } }).decision.verdict).toBe("allow");
    const before = e.ledger.balance("cash");
    const { schedule, execute } = pay(e, { invoiceId: invId }, 120_000);
    return { e, before, schedule, execute: execute! };
  }

  it.fails("fixed, exploit blocked: payment to a vendor on hold is scheduled and sent under a `hold` decision", () => {
    const { e, before, schedule, execute } = scenario();
    expect(e.vendors.get("V-A")!.status).toBe("hold");
    expect(schedule.decision.verdict).toBe("hold");
    expect(schedule.executed).toBe(true);
    expect(execute.decision.verdict).toBe("hold");
    expect(execute.executed).toBe(true);
    expect(before - e.ledger.balance("cash")).toBe(120_000);
    const entry = e.ledger.all().at(-1)!;
    expect(entry.memo).toMatch(/^Payment/);
    expect(verdictOf(e, entry.decisionId)).toBe("hold");
  });

  it("invariant: no money leaves cash for a vendor that is not active", () => {
    const { e, before } = scenario();
    expect(e.ledger.balance("cash")).toBe(before);
  });

  it("invariant: every ledger entry comes from an `allow` decision", () => {
    const { e } = scenario();
    for (const entry of e.ledger.all()) if (entry.proposalId !== "opening") expect(verdictOf(e, entry.decisionId)).toBe("allow");
  });
});

describe("C2 [critical] duplicate SKU lines on one invoice multiply the three-way-match payable", () => {
  // computeMatch computes `receivable` per invoice line but never subtracts what earlier lines of
  // the SAME invoice already consumed. 10 received, invoice bills 10 + 10 of the same SKU: pays 20.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e); // 10 x 120.00
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const line = { sku: "FLT", qty: 10, unitPrice: 12_000 };
    const invId = recordInvoice(e, poId, [line, line]);
    const payable = submitAndApprove(e, invId);
    const { execute } = pay(e, { invoiceId: invId }, payable);
    return { e, payable, execute: execute! };
  }

  it.fails("fixed, exploit blocked: 10 units received, 20 paid; GRNI flips to a debit balance", () => {
    const { e, payable, execute } = scenario();
    expect(payable).toBe(240_000);
    expect(execute.decision.verdict).toBe("allow");
    expect(cashOut(e)).toBe(240_000);
    expect(e.ledger.balance("grni")).toBe(120_000); // liability account with a debit balance
    expect(e.ledger.verify().ok).toBe(true); // books "balance", so verify() does not notice
  });

  it("invariant: payable never exceeds the PO-priced value of goods received", () => {
    const { e } = scenario();
    expect(cashOut(e)).toBeLessThanOrEqual(10 * 12_000);
  });
});

describe("C3 [critical] a prepaid PO can be paid twice: prepayment + invoice", () => {
  // schedule_payment(poId) only counts prior payments with poId and no invoiceId, and the invoice
  // match only nets prepayments that were already *sent*. Neither path sees the other.
  function prepayScheduledFirst() {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    const pre = e.submit({ actorId: "tre", type: "schedule_payment", params: { poId, amount: 120_000 } }); // at order time
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    const payable = submitAndApprove(e, invId); // prepayment not sent yet -> nothing netted
    const sendPre = e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: pre.created!.id } });
    const inv = pay(e, { invoiceId: invId }, payable);
    return { e, poId, payable, sendPre, inv };
  }
  function invoicePaidFirst() {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    const payable = submitAndApprove(e, invId);
    const inv = pay(e, { invoiceId: invId }, payable);
    const pre = pay(e, { poId }, 120_000); // full PO total is still "remaining" for prepayment
    return { e, poId, payable, inv, pre };
  }

  it.fails("fixed, exploit blocked: prepayment scheduled at order time, invoice approved before it is sent -> paid twice", () => {
    const { e, payable, sendPre, inv } = prepayScheduledFirst();
    expect(payable).toBe(120_000);
    expect(sendPre.decision.verdict).toBe("allow");
    expect(inv.execute!.decision.verdict).toBe("allow");
    expect(cashOut(e)).toBe(240_000);
  });

  it.fails("fixed, exploit blocked: invoice paid in full, then the PO is 'prepaid' again", () => {
    const { e, inv, pre } = invoicePaidFirst();
    expect(inv.execute!.decision.verdict).toBe("allow");
    expect(pre.schedule.decision.verdict).toBe("allow");
    expect(pre.execute!.decision.verdict).toBe("allow");
    expect(cashOut(e)).toBe(240_000);
  });

  it("invariant: total cash paid against a PO never exceeds the PO total (prepay first)", () => {
    const { e, poId } = prepayScheduledFirst();
    expect(cashOut(e)).toBeLessThanOrEqual(e.pos.get(poId)!.total);
  });

  it("invariant: total cash paid against a PO never exceeds the PO total (invoice first)", () => {
    const { e, poId } = invoicePaidFirst();
    expect(cashOut(e)).toBeLessThanOrEqual(e.pos.get(poId)!.total);
  });
});

describe("C4 [critical, integration precondition] submit() trusts the caller-supplied actorId", () => {
  // The threat model lets the attacker choose actorId. The engine has no notion of caller
  // identity, so one compromised agent can play every role, including the remote authority
  // that "verifies" a bank change. RBAC and SoD then only constrain the ids, not the attacker.
  // Fixed in the host: with requireCredentials (what the orchestrator/server use), a caller holding
  // only the AP credential can't speak as any other actor, so it can't forge the remote "verification".
  function scenario() {
    const e = makeEngine({ requireCredentials: true });
    const cred = Object.fromEntries(ACTORS.map((a) => [a.id, e.issueCredential(a.id)]));
    const host = (actorId: string, type: string, params: unknown) => e.submit({ actorId, type, params, credential: cred[actorId] });
    const attacker = (actorId: string, type: string, params: unknown) => e.submit({ actorId, type, params, source: "llm", credential: cred.ap });
    const { reqId, quoteIds } = (() => {
      const r = host("req", "create_requisition", { sku: "FLT", qty: 10, orderBy: T0 + 30 * DAY, reason: "needed" }).created!.id;
      host("tre", "confirm_funds", { requisitionId: r });
      const q = host("ap", "record_quote", { vendorId: "V-A", sku: "FLT", unitPrice: 12_000, qtyAvailable: 100, bank: bankA, terms: "on_receipt", validUntil: T0 + 60 * DAY, requisitionId: r }).created!.id;
      return { reqId: r, quoteIds: [q] };
    })();
    const poId = host("ctl", "approve_requisition", { requisitionId: reqId, quoteId: quoteIds[0] }).created!.id;
    attacker("rcv", "record_receipt", { poId, lines: [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }] });
    host("rcv", "record_receipt", { poId, lines: [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }] });
    const invId = attacker("ap", "record_invoice", { vendorId: "V-A", vendorInvoiceNo: "A-9", poId, lines: [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], bank: bankAFake, issuedAt: e.now, dueAt: e.now + 30 * DAY }).created!.id;
    attacker("ap", "submit_invoice", { invoiceId: invId, amount: 120_000 }); // held: bank mismatch, verification sent
    const ver = [...e.verifications.values()][0]!;
    e.advanceTo(ver.sentAt + 2 * e.remoteLatencyMs);
    const forged = attacker("rem", "answer_verification", { verificationId: ver.id, confirmed: true, answer: "confirmed on call-back" });
    attacker("ap", "submit_invoice", { invoiceId: invId, amount: 120_000 });
    attacker("ctl", "approve_invoice", { invoiceId: invId });
    const pid = attacker("tre", "schedule_payment", { invoiceId: invId, amount: 120_000 }).created?.id ?? "none";
    attacker("tre", "execute_payment", { paymentId: pid });
    return { e, pid, forged };
  }

  it.fails("fixed, exploit blocked: a single caller diverts a payment to the fraudster's account", () => {
    const { e, pid } = scenario();
    expect(e.payments.get(pid)!.status).toBe("sent");
    expect(bankKey(e.payments.get(pid)!.bank)).toBe(bankKey(bankAFake));
  });

  it("invariant: money never reaches an account whose verification the remote authority did not really give", () => {
    const { e, forged } = scenario();
    expect(forged.decision.rules[0]!.rule).toBe("actor.authenticated");
    const toFake = [...e.payments.values()].filter((p) => p.status === "sent" && bankKey(p.bank) === bankKey(bankAFake));
    expect(toFake).toHaveLength(0);
  });
});

// =====================================================================================
// HIGH
// =====================================================================================

describe("H1 [high] rejecting a partly paid invoice frees its quantity and its invoice number", () => {
  // reject_invoice is allowed on an approved invoice even after a payment went out. Rejected
  // invoices drop out of the `invoiced` quantity, the duplicate-number check and the duplicate-
  // amount check, and the AP credit is never reversed. The vendor re-sends the same number.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const inv1 = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], "A-1001");
    submitAndApprove(e, inv1);
    const part = pay(e, { invoiceId: inv1 }, 60_000);
    const rej = e.submit({ actorId: "ctl", type: "reject_invoice", params: { invoiceId: inv1, reason: "disputed" } });
    const inv2 = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], "A-1001");
    const payable2 = submitAndApprove(e, inv2);
    const full = pay(e, { invoiceId: inv2 }, payable2);
    return { e, part, rej, payable2, full };
  }

  it.fails("fixed, exploit blocked: 120.00 x 10 of goods, 1,800.00 paid; AP still shows 600.00 owed", () => {
    const { e, part, rej, payable2, full } = scenario();
    expect(part.execute!.decision.verdict).toBe("allow");
    expect(rej.decision.verdict).toBe("allow");
    expect(payable2).toBe(120_000);
    expect(full.execute!.decision.verdict).toBe("allow");
    expect(cashOut(e)).toBe(180_000);
    expect(e.ledger.balance("ap", "V-A")).toBe(-60_000);
  });

  it("invariant: total paid on a PO never exceeds the value received", () => {
    const { e } = scenario();
    expect(cashOut(e)).toBeLessThanOrEqual(120_000);
  });
});

describe("H2 [high] re-entrancy: a synchronous listener re-submitting during the `decision` event double-executes", () => {
  // submit(): evaluate -> recordDecision (emits "decision") -> execute. A listener that calls
  // submit() for the same payment in between sees status "scheduled", gets "allow", and sends it.
  // The outer execute then sends it again: two ledger postings for one payment.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    submitAndApprove(e, invId);
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).created!.id;
    let fired = false;
    e.subscribe((ev) => {
      if (ev.type !== "decision" || fired) return;
      const d = ev.data.decision as Decision;
      if (d.actionType === "execute_payment" && d.verdict === "allow") {
        fired = true;
        e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } }); // e.g. an agent loop driven by events
      }
    });
    e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
    return { e, paymentId };
  }

  it.fails("fixed, exploit blocked: one 1,200.00 payment, two postings, 2,400.00 out of cash", () => {
    const { e, paymentId } = scenario();
    expect(e.ledger.all().filter((x) => x.memo.startsWith(`Payment ${paymentId}`))).toHaveLength(2);
    expect(cashOut(e)).toBe(240_000);
  });

  it("invariant: a payment is posted to the ledger at most once", () => {
    const { e, paymentId } = scenario();
    expect(e.ledger.all().filter((x) => x.memo.startsWith(`Payment ${paymentId}`))).toHaveLength(1);
  });
});

describe("H3 [high] the one-shot ledger token is forgeable: Ledger.registerAuthorization is public and unchecked", () => {
  // The constructor is private only at the type level, and registerAuthorization() adds any
  // object to the live set without the secret. Any in-process code can post without submit().
  function forge(e: Engine) {
    // Fixed: tokens are minted only by Ledger.authorize with the engine's private secret.
    const forged = Object.freeze({ decisionId: "DEC-FORGED" }) as PostingAuthorization;
    expect(() => e.ledger.authorize("DEC-FORGED", Symbol("guess"))).toThrow();
    return e.ledger.post(
      {
        memo: "forged",
        lines: [
          { account: "ppv", debit: 1_000_000, credit: 0 },
          { account: "cash", debit: 0, credit: 1_000_000 },
        ],
        refs: [{ kind: "proposal", id: "none" }],
        proposalId: "none",
        decisionId: "DEC-FORGED",
        actorId: "nobody",
        approvers: [],
        rules: [],
      },
      e.now,
      forged,
    );
  }

  it.fails("fixed, exploit blocked: 10,000.00 leaves cash with no proposal or decision, and verify() is clean", () => {
    const e = makeEngine();
    forge(e);
    expect(cashOut(e)).toBe(1_000_000);
    expect(e.decisions.find((d) => d.id === "DEC-FORGED")).toBeUndefined();
    expect(e.ledger.verify().ok).toBe(true);
  });

  it("invariant: the ledger refuses a token the engine did not mint", () => {
    const e = makeEngine();
    expect(() => forge(e)).toThrow();
  });
});

// =====================================================================================
// MEDIUM
// =====================================================================================

describe("M1 [medium] escalation routing is advisory: other humans (or the target, before delivery) act directly", () => {
  // decide() checks target and delivery, but both human roles also hold approve_requisition /
  // approve_invoice directly, and the subject in status "escalated" is accepted by those rules.
  function escalated() {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    expect(e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).decision.verdict).toBe("escalate");
    const esc = [...e.escalations.values()][0]!;
    expect(esc.to).toBe("remote_authority");
    expect(esc.status).toBe("in_transit");
    return { e, reqId, quoteId: quoteIds[0]!, esc };
  }

  it.fails("fixed, exploit blocked: the remote authority approves while its escalation is still in transit", () => {
    const { e, reqId, quoteId, esc } = escalated();
    const r = e.submit({ actorId: "rem", type: "approve_requisition", params: { requisitionId: reqId, quoteId } });
    expect(e.now).toBeLessThan(esc.deliverAt);
    expect(r.decision.verdict).toBe("allow");
    expect(esc.status).toBe("superseded");
  });

  it.fails("fixed, exploit blocked: the local authority decides an escalation addressed to the remote authority", () => {
    const { e, reqId, quoteId } = escalated();
    const r = e.submit({ actorId: "loc", type: "approve_requisition", params: { requisitionId: reqId, quoteId } });
    expect(r.decision.verdict).toBe("allow");
    expect(e.pos.get(r.created!.id)!.approvedBy).toEqual(["loc"]);
  });

  it("invariant: an escalated subject is decided only by its target authority, after delivery", () => {
    const { e, reqId, quoteId } = escalated();
    expect(e.submit({ actorId: "rem", type: "approve_requisition", params: { requisitionId: reqId, quoteId } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "loc", type: "approve_requisition", params: { requisitionId: reqId, quoteId } }).decision.verdict).toBe("deny");
  });
});

describe("M2 [medium] the agent's approval limit is per-approval: split orders and self-resolved escalations", () => {
  function split() {
    const e = makeEngine();
    // 10 batteries (8,000.00) is over the controller's 5,000.00 limit and escalates...
    const first = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    expect(e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: first.reqId, quoteId: first.quoteIds[0] } }).decision.verdict).toBe("escalate");
    // ...so the controller approves 6 of the same escalated request itself, and the other 4 as a new one.
    const a = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: first.reqId, quoteId: first.quoteIds[0], qty: 6 } });
    const second = requisitionWithQuotes(e, "BAT", 4, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    const b = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: second.reqId, quoteId: second.quoteIds[0] } });
    const byCtl = [...e.pos.values()].filter((p) => p.approvedBy.includes("ctl")).reduce((s, p) => s + p.total, 0);
    return { e, a, b, byCtl };
  }

  it.fails("fixed, exploit blocked: 8,000.00 to one vendor for one item approved by an agent whose limit is 5,000.00; the human never decides", () => {
    const { e, a, b, byCtl } = split();
    expect(a.decision.verdict).toBe("allow");
    expect(b.decision.verdict).toBe("allow");
    expect(byCtl).toBe(800_000);
    expect([...e.escalations.values()][0]!.status).toBe("superseded");
  });

  it("invariant: one approver's commitments to a vendor/item in a window stay within its limit", () => {
    const { e, byCtl } = split();
    expect(byCtl).toBeLessThanOrEqual(e.policy.approval.agentMaxCents);
  });
});

describe("M3 [medium] request_verification does not tie the vendor to the subject document", () => {
  // The controller files Alpha's document (with Alpha's new bank) as a verification *for Beta*.
  // When the call-back confirms the document's change, Beta's master bank is overwritten.
  function scenario() {
    const e = makeEngine();
    const { quoteIds } = requisitionWithQuotes(e, "FLT", 10, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankAFake }]);
    const rv = e.submit({ actorId: "ctl", type: "request_verification", params: { vendorId: "V-B", subject: { kind: "quote", id: quoteIds[0] } } });
    return { e, rv };
  }

  it.fails("fixed, exploit blocked: Beta's master becomes the account printed on Alpha's quote, and Beta's next payment goes there", () => {
    const { e, rv } = scenario();
    expect(rv.decision.verdict).toBe("allow");
    const ver = e.verifications.get(rv.created!.id)!;
    expect(ver.vendorId).toBe("V-B");
    e.advanceTo(ver.arrivesAt);
    expect(e.submit({ actorId: "rem", type: "answer_verification", params: { verificationId: ver.id, confirmed: true, answer: "sender confirmed the new account" } }).decision.verdict).toBe("allow");
    expect(bankKey(e.vendors.get("V-B")!.bank)).toBe(bankKey(bankAFake));
    expect(bankKey(e.vendors.get("V-A")!.bank)).toBe(bankKey(bankA));
    // A normal Beta order now pays into the account from Alpha's document.
    const { poId } = order(e, { sku: "BAT", qty: 5, price: 95_000, vendorId: "V-B", bank: bankAFake });
    receive(e, poId, [{ sku: "BAT", qtyReceived: 5, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "BAT", qty: 5, unitPrice: 95_000 }], "B-1", bankAFake, "V-B");
    const payable = submitAndApprove(e, invId);
    const { execute } = pay(e, { invoiceId: invId }, payable);
    expect(execute!.decision.verdict).toBe("allow");
    expect(bankKey([...e.payments.values()].at(-1)!.bank)).toBe(bankKey(bankAFake));
  });

  it("invariant: a verification can only be requested for the vendor that sent the document", () => {
    const { rv } = scenario();
    expect(rv.decision.verdict).toBe("deny");
  });
});

describe("M4 [medium] duplicate SKU lines on a receipt inflate inventory and GRNI", () => {
  // The executor caps each line at `pl.qty - already`, but `already` is read before the receipt is
  // stored, so every duplicate line gets the full cap. (The match caps payable at PO qty, so cash
  // is safe on its own; combined with C2 it is not.)
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e); // 10 x 120.00 = 1,200.00
    const r = receive(e, poId, [
      { sku: "FLT", qtyReceived: 10, qtyRejected: 0 },
      { sku: "FLT", qtyReceived: 10, qtyRejected: 0 },
    ]);
    return { e, r, poId };
  }

  it.fails("fixed, exploit blocked: 2,400.00 of inventory booked on a 1,200.00 order", () => {
    const { e, r } = scenario();
    expect(r.decision.verdict).toBe("allow");
    expect(e.ledger.balance("inventory")).toBe(240_000);
    expect(e.ledger.balance("grni")).toBe(-240_000);
  });

  it("invariant: inventory booked on a PO never exceeds the PO value", () => {
    const { e, poId } = scenario();
    expect(e.ledger.balance("inventory")).toBeLessThanOrEqual(e.pos.get(poId)!.total);
  });
});

describe("M5 [medium] hash chain: truncation and suffix rewrites pass verify()", () => {
  // No external anchor (head hash is not checkpointed), and verify() never recomputes per-account
  // balances from the entries to compare with the cached balance map.
  function cycle() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    submitAndApprove(e, invId);
    pay(e, { invoiceId: invId }, 120_000);
    return e;
  }
  const recomputedCash = (e: Engine) => e.ledger.all().flatMap((x) => x.lines).filter((l) => l.account === "cash").reduce((s, l) => s + l.debit - l.credit, 0);

  it.fails("fixed, exploit blocked: deleting the payment entry leaves verify() clean, while cash no longer matches the entries", () => {
    const e = cycle();
    (e.ledger.all() as JournalEntry[]).pop();
    expect(e.ledger.verify().ok).toBe(true);
    expect(recomputedCash(e)).not.toBe(e.ledger.balance("cash"));
  });

  it.fails("fixed, exploit blocked: rewriting the last entry and re-hashing it leaves verify() clean", () => {
    const e = cycle();
    const last = (e.ledger.all() as JournalEntry[]).at(-1)!;
    last.lines = last.lines.map((l) => ({ ...l, debit: l.debit ? 1 : 0, credit: l.credit ? 1 : 0 }));
    const { hash: _old, ...body } = last;
    last.hash = sha256(canonicalJson(body));
    expect(e.ledger.verify().ok).toBe(true);
  });

  it("invariant: the ledger can't be truncated from outside, and the head is cross-checked against the audit log", () => {
    const e = cycle();
    const n = e.ledger.size;
    (e.ledger.all() as JournalEntry[]).pop(); // all() is a copy
    expect(e.ledger.size).toBe(n);
    expect(e.verifyIntegrity().ok).toBe(true);
    expect(e.ledger.verify({ seq: n + 1, hash: "x" }).ok).toBe(false); // a recorded head that doesn't match is detected
  });

  it("invariant: entries are immutable, so a tail can't be rewritten and re-hashed", () => {
    const e = cycle();
    const last = (e.ledger.all() as JournalEntry[]).at(-1)!;
    expect(() => {
      last.lines = last.lines.map((l) => ({ ...l, debit: l.debit ? 1 : 0, credit: l.credit ? 1 : 0 }));
    }).toThrow(TypeError);
    expect(() => {
      last.hash = sha256(canonicalJson({}));
    }).toThrow(TypeError);
    expect(e.verifyIntegrity().ok).toBe(true);
  });
});

describe("M6 [medium] SoD is a policy toggle, and setPolicy() has no authorization", () => {
  // Any caller can pass any actorId as the "editor"; `engine.policy` is also a public mutable field
  // that skips validation and audit entirely. Nothing requires the sod flags to stay on.
  function scenario() {
    const e = makeEngine();
    const p = structuredClone(e.policy);
    (p as { sod: Record<string, boolean> }).sod = { requesterCannotApprove: false, submitterCannotApprove: false, approverCannotPay: false, requesterCannotReceive: false };
    p.permissions.controller = [...p.permissions.controller, "execute_payment"];
    e.setPolicy(p, "any-string-is-accepted-as-the-editor");
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    const payable = submitAndApprove(e, invId, "ctl");
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: payable } }).created!.id;
    const execute = e.submit({ actorId: "ctl", type: "execute_payment", params: { paymentId } });
    return { e, execute };
  }

  it.fails("fixed, exploit blocked: after one unauthenticated policy edit, the controller approves an invoice and releases its payment", () => {
    const { e, execute } = scenario();
    expect(execute.decision.verdict).toBe("allow");
    const p = [...e.payments.values()][0]!;
    expect(p.approvedBy).toContain("ctl");
    expect(p.executedBy).toBe("ctl");
  });

  it("invariant: SoD can't be switched off and policy edits need the policy owner", () => {
    expect(() => scenario()).toThrow(/remote authority/);
    const e = makeEngine();
    const p = structuredClone(e.policy) as { sod: Record<string, boolean>; permissions: Record<string, string[]> };
    p.sod.approverCannotPay = false;
    expect(() => e.setPolicy(p, "rem")).toThrow();
    const q = structuredClone(e.policy) as { permissions: Record<string, string[]> };
    q.permissions.controller = [...(q.permissions.controller ?? []), "execute_payment"];
    expect(() => e.setPolicy(q, "rem")).toThrow(/segregation of duties/);
    expect(() => {
      (e.policy as { materialityCents: number }).materialityCents = 0;
    }).toThrow(TypeError);
  });
});

describe("M7 [medium] action types that are Object.prototype keys crash submit() and leave no audit trace", () => {
  // parseAction uses `type in ACTION_SCHEMAS`, which is true for inherited keys.
  const keys = ["toString", "constructor", "__proto__", "hasOwnProperty", "valueOf"];

  it.fails("fixed, exploit blocked: submit throws a TypeError and nothing is audited", () => {
    const e = makeEngine();
    for (const type of keys) {
      const n = e.audit.all().length;
      expect(() => e.submit({ actorId: "ap", type, params: {} })).toThrow(TypeError);
      expect(e.audit.all().length).toBe(n);
    }
  });

  it("invariant: any malformed proposal is denied and audited, never thrown", () => {
    const e = makeEngine();
    for (const type of keys) expect(e.submit({ actorId: "ap", type, params: {} }).decision.verdict).toBe("deny");
  });
});

// =====================================================================================
// LOW
// =====================================================================================

describe("L1 [low] a quote recorded for one requisition can be used to approve another", () => {
  function scenario() {
    const e = makeEngine();
    const first = requisitionWithQuotes(e, "FLT", 10, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankA }]);
    const r2 = e.submit({ actorId: "req", type: "create_requisition", params: { sku: "FLT", qty: 10, orderBy: T0 + 30 * DAY, reason: "second request" } }).created!.id;
    e.submit({ actorId: "tre", type: "confirm_funds", params: { requisitionId: r2 } });
    const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: r2, quoteId: first.quoteIds[0] } });
    return { e, first, appr };
  }

  it.fails("fixed, exploit blocked: REQ-2 is ordered on REQ-1's quote; REQ-1 is left with none", () => {
    const { e, first, appr } = scenario();
    expect(appr.decision.verdict).toBe("allow");
    expect(e.quotes.get(first.quoteIds[0]!)!.requisitionId).toBe(first.reqId);
  });

  it("invariant: a quote is only usable for the requisition it was recorded against", () => {
    const { appr } = scenario();
    expect(appr.decision.verdict).toBe("deny");
  });
});

describe("L2 [low] a verification answer is accepted on one-way latency, before a reply could physically arrive", () => {
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], "A-7", bankAFake);
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 120_000 } });
    const v = [...e.verifications.values()][0]!;
    e.advanceTo(v.arrivesAt);
    const ans = e.submit({ actorId: "rem", type: "answer_verification", params: { verificationId: v.id, confirmed: true, answer: "ok" } });
    return { e, v, ans };
  }

  it.fails("fixed, exploit blocked: answer accepted at sentAt + latency; the engine's own expected reply time is latency + processing later", () => {
    const { e, v, ans } = scenario();
    expect(ans.decision.verdict).toBe("allow");
    expect(e.now).toBeLessThan(e.expectedVerificationReply(v));
  });

  it("invariant: no answer is accepted before the earliest possible reply time", () => {
    const { ans } = scenario();
    expect(ans.decision.verdict).toBe("deny");
  });
});

describe("L3 [low] shared mutable objects: actor records and snapshot() alias engine state", () => {
  it("invariant: mutating the actor list passed to the engine does not change RBAC", () => {
    const actors: Actor[] = ACTORS.map((a) => ({ ...a }));
    const e = makeEngine({ actors });
    actors.find((a) => a.id === "ap")!.role = "remote_authority";
    expect(e.submit({ actorId: "ap", type: "hold_vendor", params: { vendorId: "V-B", reason: "x" } }).decision.verdict).toBe("deny");
  });

  it("invariant: mutating a snapshot does not change the verified vendor master", () => {
    const e = makeEngine();
    e.snapshot().vendors.find((v) => v.id === "V-A")!.bank = { ...bankAFake };
    expect(bankKey(e.vendors.get("V-A")!.bank)).toBe(bankKey(bankA));
  });
});

// =====================================================================================
// HOLDS: attacks the engine resists
// =====================================================================================

describe("HOLDS: ledger arithmetic and in-place tampering", () => {
  it("every entry balances, the trial balance sums to zero, and editing a middle entry is detected", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 11_900 }]); // PPV credit path
    submitAndApprove(e, invId);
    pay(e, { invoiceId: invId }, 119_000);
    expect(e.ledger.verify().ok).toBe(true);
    for (const x of e.ledger.all()) expect(x.lines.reduce((s, l) => s + l.debit, 0)).toBe(x.lines.reduce((s, l) => s + l.credit, 0));
    const mid = (e.ledger.all() as JournalEntry[])[1]!;
    // Entries are frozen now: in-place edits throw instead of needing detection.
    expect(() => {
      mid.lines[0]!.debit += 1;
    }).toThrow(TypeError);
    expect(e.verifyIntegrity().ok).toBe(true);
  });

  it("the schema rejects negative, fractional, unsafe and non-numeric amounts", () => {
    const e = makeEngine();
    for (const amount of [-1, 0.5, 2 ** 60, 1e300, Number.NaN, Number.POSITIVE_INFINITY, "100"]) {
      const r = e.submit({ actorId: "tre", type: "schedule_payment", params: { poId: "PO-0001", amount } });
      expect(r.decision.verdict).toBe("deny");
    }
    for (const qty of [0, -5, 1.5, 2 ** 60]) {
      expect(e.submit({ actorId: "req", type: "create_requisition", params: { sku: "FLT", qty, orderBy: T0, reason: "x" } }).decision.verdict).toBe("deny");
    }
  });
});

describe("HOLDS: double payment through repeated schedule/execute", () => {
  it("a second schedule_payment over the approved amount and a second execute are denied", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    submitAndApprove(e, invId);
    const p1 = pay(e, { invoiceId: invId }, 120_000);
    expect(p1.execute!.decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 1 } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: p1.schedule.created!.id } }).decision.verdict).toBe("deny");
    // Two scheduled halves can't exceed the approved amount either.
    expect(cashOut(e)).toBe(120_000);
  });

  it("two invoices for the same goods: the second no longer matches once the first is approved", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const a = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], "A-1");
    const b = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_001 }], "A-2");
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: a, amount: 120_000 } });
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: b, amount: 120_010 } });
    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: a } }).decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: b } }).decision.verdict).toBe("deny");
  });
});

describe("HOLDS: bank details on documents never redirect a payment by themselves", () => {
  it("an invoice with new bank details is held, cannot be scheduled, and the payment bank is always the master", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }], "A-5", bankAFake);
    expect(e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 120_000 } }).decision.verdict).toBe("hold");
    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).decision.verdict).toBe("deny");
    // Early answers and answers from the wrong role are refused.
    const v = [...e.verifications.values()][0]!;
    expect(e.submit({ actorId: "rem", type: "answer_verification", params: { verificationId: v.id, confirmed: true, answer: "x" } }).decision.verdict).toBe("deny");
    e.advanceTo(v.arrivesAt);
    expect(e.submit({ actorId: "ctl", type: "answer_verification", params: { verificationId: v.id, confirmed: true, answer: "x" } }).decision.verdict).toBe("deny");
    expect(bankKey(e.vendors.get("V-A")!.bank)).toBe(bankKey(bankA));
  });

  it("caller-held objects are copied: mutating params or the config after the fact changes nothing", () => {
    const vendors = [
      { id: "V-A", name: "Alpha Supply Co", bank: { ...bankA }, bankVerifiedAt: T0, status: "active" as const },
      { id: "V-B", name: "Beta Parts Ltd", bank: { ...bankB }, bankVerifiedAt: T0, status: "active" as const },
    ];
    const e = makeEngine({ vendors });
    vendors[0]!.bank.account = "999999999999";
    expect(bankKey(e.vendors.get("V-A")!.bank)).toBe(bankKey(bankA));
    const bank = { ...bankA };
    const q = e.submit({ actorId: "ap", type: "record_quote", params: { vendorId: "V-A", sku: "FLT", unitPrice: 12_000, qtyAvailable: 5, bank, terms: "on_receipt", validUntil: T0 + DAY } });
    bank.account = "999999999999";
    expect(bankKey(e.quotes.get(q.created!.id)!.bank)).toBe(bankKey(bankA));
  });
});

describe("HOLDS: RBAC and segregation of duties with widened permissions (SoD flags on)", () => {
  it("approver != payer, submitter != approver, requester != receiver, requester != approver", () => {
    const e = makeEngine();
    const p = structuredClone(e.policy) as { permissions: Record<string, string[]> };
    p.permissions.controller = [...(p.permissions.controller ?? []), "schedule_payment", "execute_payment"];
    p.permissions.ap = [...(p.permissions.ap ?? []), "approve_invoice"];
    p.permissions.treasury = [...(p.permissions.treasury ?? []), "approve_invoice"];
    p.permissions.requester = [...(p.permissions.requester ?? []), "record_receipt"];
    p.permissions.local_authority = [...(p.permissions.local_authority ?? []), "create_requisition"];
    // Since the fix, conflicting widenings are rejected outright; the checks below run on the default policy.
    expect(() => e.setPolicy(p, "rem")).toThrow(/segregation of duties/);
    const { poId } = order(e);
    expect(receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }], "req").decision.verdict).toBe("deny");
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId: invId, amount: 120_000 } });
    expect(e.submit({ actorId: "ap", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "tre", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("deny");
    expect(e.invoices.get(invId)!.status).toBe("submitted");
    expect(e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } }).decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "ctl", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).decision.verdict).toBe("deny");
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).created!.id;
    expect(e.submit({ actorId: "ctl", type: "execute_payment", params: { paymentId } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } }).decision.verdict).toBe("allow");

    // A human who raised the request cannot approve it, directly or through an escalation.
    // Humans can't raise requests at all under the default policy (request + approve would conflict).
    expect(e.submit({ actorId: "loc", type: "create_requisition", params: { sku: "BAT", qty: 10, orderBy: T0 + 40 * 60_000, reason: "mine" } }).decision.verdict).toBe("deny");
  });

  it("forbidden or malformed proposals are denied and leave state untouched", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, [{ sku: "FLT", qtyReceived: 10, qtyRejected: 0 }]);
    const invId = recordInvoice(e, poId, [{ sku: "FLT", qty: 10, unitPrice: 12_000 }]);
    const before = stateOf(e);
    const attempts: [string, string, unknown][] = [
      ["ap", "approve_invoice", { invoiceId: invId }],
      ["ap", "execute_payment", { paymentId: "PAY-0001" }],
      ["rcv", "answer_verification", { verificationId: "VER-0001", confirmed: true, answer: "x" }],
      ["ctl", "decide", { escalationId: "ESC-0001", optionId: "buy" }],
      ["system", "schedule_payment", { invoiceId: invId, amount: 1 }],
      ["intruder", "hold_vendor", { vendorId: "V-A", reason: "x" }],
      ["tre", "schedule_payment", { invoiceId: invId, amount: 120_000 }], // not approved yet
      ["ap", "submit_invoice", { invoiceId: invId, amount: 999_999 }], // not the matched amount
      ["ctl", "approve_invoice", { invoiceId: invId }], // not submitted yet
      ["rcv", "record_receipt", { poId, lines: [{ sku: "FLT", qtyReceived: 1, qtyRejected: 2 }] }],
      ["ap", "record_quote", { vendorId: "V-A", sku: "FLT", unitPrice: 1, qtyAvailable: 1, bank: { ...bankA, account: "" }, terms: "prepay", validUntil: T0 }],
    ];
    for (const [actorId, type, params] of attempts) expect(e.submit({ actorId, type, params }).decision.verdict).toBe("deny");
    expect(stateOf(e)).toBe(before);
  });
});

describe("HOLDS: escalation decisions via decide()", () => {
  it("wrong authority and undelivered escalations are denied; a decision is final", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
    const esc = [...e.escalations.values()][0]!;
    const buy = esc.options.find((o) => o.id.startsWith("buy-"))!;
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: buy.id } }).decision.verdict).toBe("deny");
    e.advanceTo(esc.deliverAt);
    expect(e.submit({ actorId: "loc", type: "decide", params: { escalationId: esc.id, optionId: buy.id } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: "no-such-option" } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: buy.id } }).decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: buy.id } }).decision.verdict).toBe("deny");
    expect(e.pos.size).toBe(1);
  });

  it("an option that has drifted over the authority's limit creates no PO (re-checked at decision time)", () => {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }], T0 + 40 * 60_000);
    e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
    const esc = [...e.escalations.values()][0]!;
    expect(esc.to).toBe("local_authority");
    const buy = esc.options.find((o) => o.id.startsWith("buy-"))!;
    const p = structuredClone(e.policy);
    p.approval.localAuthorityMaxCents = 100_000;
    e.setPolicy(p, "rem");
    const d = e.submit({ actorId: "loc", type: "decide", params: { escalationId: esc.id, optionId: buy.id } });
    expect(d.decision.verdict).toBe("escalate"); // not executed; since the L4 fix the escalation stays open
    expect(esc.status).toBe("awaiting_decision");
    expect(e.pos.size).toBe(0);
  });
});
