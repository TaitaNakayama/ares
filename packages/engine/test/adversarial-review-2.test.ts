import { describe, expect, it } from "vitest";
import { Ledger, type AuditRecord, type BankAccount, type Engine } from "../src/index.ts";
import { bankA, bankAFake, bankB, DAY, makeEngine, requisitionWithQuotes, T0 } from "./fixtures.ts";

/**
 * Adversarial re-review after the fixes in c095b37 (verify-04b).
 * Report: research/verify-04b-engine-rereview.md
 *
 * Same convention as adversarial-review.test.ts:
 * - `it("repro: ...")` asserts what the engine does today (proves the problem is real).
 * - `it.fails("invariant: ...")` asserts the property we want; it fails today.
 *   When fixed, both flip: drop the repro, turn `it.fails` into `it`.
 * - `describe("HOLDS: ...")` re-checks fixes that held up under new attacks.
 */

const OPENING = 50_000_000;
const bankA2: BankAccount = { holder: "Alpha Supply Co", bank: "New Bank", routing: "333000333", account: "000111222333" };

// ---------------------------------------------------------------- helpers (no credentials)

function order(e: Engine, o: { sku?: string; qty?: number; price?: number; vendorId?: string; bank?: BankAccount; terms?: "prepay" | "on_receipt" } = {}) {
  const { sku = "FLT", qty = 10, price = 12_000, vendorId = "V-A", bank = bankA, terms = "on_receipt" } = o;
  const { reqId, quoteIds } = requisitionWithQuotes(e, sku, qty, [{ vendorId, unitPrice: price, qtyAvailable: 100, bank, terms }]);
  const appr = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } });
  expect(appr.decision.verdict).toBe("allow");
  return { reqId, poId: appr.created!.id };
}

function receive(e: Engine, poId: string, qty: number, sku = "FLT") {
  const r = e.submit({ actorId: "rcv", type: "record_receipt", params: { poId, lines: [{ sku, qtyReceived: qty, qtyRejected: 0 }] } });
  expect(r.decision.verdict).toBe("allow");
}

function recordInvoice(e: Engine, poId: string, qty: number, unitPrice = 12_000, no = "A-1001", bank: BankAccount = bankA, sku = "FLT") {
  const r = e.submit({ actorId: "ap", type: "record_invoice", params: { vendorId: "V-A", vendorInvoiceNo: no, poId, lines: [{ sku, qty, unitPrice }], bank, issuedAt: e.now, dueAt: e.now + 30 * DAY } });
  expect(r.decision.verdict).toBe("allow");
  return r.created!.id;
}

function submit(e: Engine, invoiceId: string) {
  const payable = e.computeMatch(e.invoices.get(invoiceId)!).payable;
  const s = e.submit({ actorId: "ap", type: "submit_invoice", params: { invoiceId, amount: payable } });
  return { payable, s };
}

function submitAndApprove(e: Engine, invoiceId: string) {
  const { payable, s } = submit(e, invoiceId);
  expect(s.decision.verdict).toBe("allow");
  const a = e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId } });
  expect(a.decision.verdict).toBe("allow");
  return payable;
}

function pay(e: Engine, target: { invoiceId?: string; poId?: string }, amount: number) {
  const schedule = e.submit({ actorId: "tre", type: "schedule_payment", params: { ...target, amount } });
  const execute = schedule.created ? e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: schedule.created.id } }) : undefined;
  return { schedule, execute };
}

/** The vendor legitimately moves to `bank`: a quote carries it, the controller asks, the CFO confirms on call-back. */
function verifiedBankChange(e: Engine, bank: BankAccount) {
  const { quoteIds } = requisitionWithQuotes(e, "FLT", 1, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank }]);
  const rv = e.submit({ actorId: "ctl", type: "request_verification", params: { vendorId: "V-A", subject: { kind: "quote", id: quoteIds[0] } } });
  expect(rv.decision.verdict).toBe("allow");
  const v = e.verifications.get(rv.created!.id)!;
  e.advanceTo(v.sentAt + 2 * e.remoteLatencyMs);
  const ans = e.submit({ actorId: "rem", type: "answer_verification", params: { verificationId: v.id, confirmed: true, answer: "confirmed on call-back" } });
  expect(ans.decision.verdict).toBe("allow");
}

const failed = (r: { decision: { rules: { rule: string; ok: boolean }[] } }) => r.decision.rules.filter((x) => !x.ok).map((x) => x.rule);
const cashOut = (e: Engine) => OPENING - e.ledger.balance("cash");

// ---------------------------------------------------------------- helpers (credentials on, as the orchestrator runs it)

function credEngine() {
  const e = makeEngine({ requireCredentials: true });
  const creds = new Map([...e.actors.keys()].map((id) => [id, e.issueCredential(id)] as const));
  const as = (actorId: string, type: string, params: unknown) => e.submit({ actorId, type, params, credential: creds.get(actorId) });
  return { e, creds, as };
}

// =====================================================================================
// MEDIUM: holds and caps that strand money or state
// =====================================================================================

describe("N1 [medium] payment.po_cap strands an invoice billed within price tolerance", () => {
  // The match approves up to PO price + priceTolerancePct (2%), but the cap is the bare PO total.
  // The approved, AP-credited 2% can never be paid; the invoice never reaches "paid".
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e); // 10 x 120.00 = 1,200.00
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10, 12_240); // exactly at the 2% tolerance and the contract cap
    const payable = submitAndApprove(e, invId);
    const full = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: payable } });
    const part = pay(e, { invoiceId: invId }, 120_000);
    const rest = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: payable - 120_000 } });
    return { e, invId, payable, full, part, rest };
  }

  it.fails("fixed, exploit blocked: 1,224.00 approved, 1,200.00 payable at most; 24.00 stuck in AP forever", () => {
    const { e, invId, payable, full, part, rest } = scenario();
    expect(payable).toBe(122_400);
    expect(full.decision.verdict).toBe("deny");
    expect(failed(full)).toContain("payment.po_cap");
    expect(part.execute!.decision.verdict).toBe("allow");
    expect(rest.decision.verdict).toBe("deny");
    expect(e.invoices.get(invId)!.status).toBe("approved");
    expect(e.ledger.balance("ap", "V-A")).toBe(-2_400);
  });

  it.fails("invariant: an invoice the policy approved can be paid in full", () => {
    const { e, invId } = scenario();
    expect(e.invoices.get(invId)!.status).toBe("paid");
  });
});

describe("N2 [low] a payment snapshotted to the old bank is stuck after a verified bank change; only a vendor-wide hold/release clears it", () => {
  // Payment.bank is copied at schedule time (good), execute re-checks it against the master (good),
  // but there is no cancel/reissue action. The stuck payment still counts as "scheduled": it uses up
  // the invoice's remaining amount, the PO cap and (for prepayments) keeps payment.prepay_settled on hold.
  // The only way out is hold_vendor (cancels *every* scheduled payment of the vendor) followed by the
  // remote authority's release_vendor (added in the working tree after c095b37).
  function invoiceCase() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId);
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).created!.id;
    verifiedBankChange(e, bankA2);
    const exec = e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
    const reissue = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } });
    return { e, invId, exec, reissue };
  }
  function prepayCase() {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { poId, amount: 120_000 } }).created!.id;
    verifiedBankChange(e, bankA2);
    const exec = e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10, 12_000, "A-1001", bankA2);
    const sub = submit(e, invId).s;
    const reissue = e.submit({ actorId: "tre", type: "schedule_payment", params: { poId, amount: 120_000 } });
    return { e, invId, exec, sub, reissue };
  }

  it("repro (invoice): the old-bank payment can't be sent, and no replacement can be scheduled", () => {
    const { e, invId, exec, reissue } = invoiceCase();
    expect(exec.decision.verdict).toBe("deny");
    expect(failed(exec)).toContain("payment.to_master_bank");
    expect(reissue.decision.verdict).toBe("deny");
    expect(failed(reissue)).toEqual(expect.arrayContaining(["payment.amount_within_approved", "payment.po_cap"]));
    expect(e.invoices.get(invId)!.status).toBe("approved");
  });

  it("repro (prepay): the stuck prepayment keeps the goods' invoice on hold for good", () => {
    const { e, invId, exec, sub, reissue } = prepayCase();
    expect(exec.decision.verdict).toBe("deny");
    expect(sub.decision.verdict).toBe("hold");
    expect(failed(sub)).toContain("payment.prepay_settled");
    expect(reissue.decision.verdict).toBe("deny");
    expect(e.invoices.get(invId)!.status).toBe("held");
  });

  it("repro (workaround): hold_vendor + release_vendor by the CFO cancels the stuck payment and the reissue goes to the new account", () => {
    const { e, invId } = invoiceCase();
    expect(e.submit({ actorId: "ctl", type: "hold_vendor", params: { vendorId: "V-A", reason: "re-issue after bank change" } }).decision.verdict).toBe("allow");
    expect(e.submit({ actorId: "ctl", type: "release_vendor", params: { vendorId: "V-A", reason: "x" } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "rem", type: "release_vendor", params: { vendorId: "V-A", reason: "re-verified" } }).decision.verdict).toBe("allow");
    const re = pay(e, { invoiceId: invId }, 120_000);
    expect(re.execute!.decision.verdict).toBe("allow");
    expect(e.payments.get(re.schedule.created!.id)!.bank.account).toBe(bankA2.account);
  });

  it.fails("invariant: after a verified bank change, an in-flight payment can be re-issued without holding the whole vendor", () => {
    const { reissue } = invoiceCase();
    expect(reissue.decision.verdict).toBe("allow");
  });

  it.fails("invariant: a prepaid order's invoice is not held forever by a prepayment that can never be sent", () => {
    const { sub } = prepayCase();
    expect(sub.decision.verdict).not.toBe("hold");
  });
});

describe("N4 [medium] a short-paid invoice consumes the billed quantity, so goods received later can't be billed", () => {
  // `invoiced` counts the *billed* qty of approved invoices, not the qty actually paid.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e); // 10 ordered
    receive(e, poId, 8);
    const inv1 = recordInvoice(e, poId, 10, 12_000, "A-1"); // billed 10, received 8 -> pays 8
    const paid1 = submitAndApprove(e, inv1);
    pay(e, { invoiceId: inv1 }, paid1);
    receive(e, poId, 2); // the last 2 arrive
    const inv2 = recordInvoice(e, poId, 2, 12_000, "A-2");
    const m2 = e.computeMatch(e.invoices.get(inv2)!);
    return { e, paid1, m2 };
  }

  it.fails("fixed, exploit blocked: 10 received, 8 ever payable; 240.00 stays in GRNI", () => {
    const { e, paid1, m2 } = scenario();
    expect(paid1).toBe(96_000);
    expect(m2.payable).toBe(0);
    expect(e.ledger.balance("grni")).toBe(-24_000);
  });

  it("invariant: over all invoices, the vendor can be paid for every accepted unit", () => {
    const { m2 } = scenario();
    expect(m2.payable).toBe(24_000);
  });
});

describe("N5 [low] prepayment scheduled after the invoice was approved: cash is capped, but AP and prepayments never reconcile", () => {
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId); // nothing in flight yet, so nothing is netted
    const pre = pay(e, { poId }, 120_000); // allowed: the invoice payment isn't scheduled yet
    const invPay = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } });
    return { e, invId, pre, invPay };
  }

  it("repro: vendor paid exactly once (good), but 1,200.00 sits in AP and 1,200.00 in prepayments, forever", () => {
    const { e, invId, pre, invPay } = scenario();
    expect(pre.execute!.decision.verdict).toBe("allow");
    expect(invPay.decision.verdict).toBe("deny");
    expect(cashOut(e)).toBe(120_000);
    expect(e.ledger.balance("ap", "V-A")).toBe(-120_000);
    expect(e.ledger.balance("prepayments", "V-A")).toBe(120_000);
    expect(e.invoices.get(invId)!.status).toBe("approved");
  });

  it.fails("invariant: once the vendor is paid for invoiced goods, its AP and prepayment balances are zero", () => {
    const { e } = scenario();
    expect(e.ledger.balance("ap", "V-A")).toBe(0);
    expect(e.ledger.balance("prepayments", "V-A")).toBe(0);
  });
});

// =====================================================================================
// MEDIUM: escalation routing
// =====================================================================================

describe("N6 [medium] a human 'wait' (or lever) decision hands the subject straight back to the agent", () => {
  // escalation.routing only applies while an escalation is open. Deciding "wait" closes it, and the
  // requisition stays "escalated" with no open escalation, so the controller can immediately buy
  // a reduced quantity on its own authority: the human's decision is not binding.
  function scenario() {
    const e = makeEngine();
    const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    expect(e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0] } }).decision.verdict).toBe("escalate");
    const esc = [...e.escalations.values()][0]!;
    e.advanceTo(esc.deliverAt);
    const wait = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: "wait" } });
    const agent = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: reqId, quoteId: quoteIds[0], qty: 6 } });
    return { e, wait, agent };
  }

  it.fails("fixed, exploit blocked: CFO says wait; one step later the controller orders 4,800.00 of the same request", () => {
    const { wait, agent } = scenario();
    expect(wait.decision.verdict).toBe("allow");
    expect(agent.decision.verdict).toBe("allow");
  });

  it("invariant: after a human decided an escalated subject, the agent can't act on it without a new human decision", () => {
    const { agent } = scenario();
    expect(agent.decision.verdict).toBe("deny");
  });
});

describe("N7 [medium] escalations whose options are stale or undecidable", () => {
  // Options are built once, at creation, from the subject's state at that moment.
  function transientPrepayHold() {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    expect(submit(e, invId).s.decision.verdict).toBe("allow"); // submitted, 1,200.00
    const pre = e.submit({ actorId: "tre", type: "schedule_payment", params: { poId, amount: 120_000 } }).created!.id;
    const appr = e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } }); // prepay in flight -> hold
    const esc = e.openEscalationFor({ kind: "invoice", id: invId })!;
    e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId: pre } }); // prepayment settles
    const resub = submit(e, invId).s; // payable is now 0 after netting
    const ctl = e.submit({ actorId: "ctl", type: "approve_invoice", params: { invoiceId: invId } });
    return { e, invId, appr, esc, resub, ctl };
  }
  function undecidableRunway() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId);
    const p = structuredClone(e.policy);
    p.treasury.minRunwayDays = 3650; // policy max (was 100k before bounds); still far above the fixture runway
    e.setPolicy(p, "rem");
    const sch = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } });
    const esc = e.openEscalationFor({ kind: "invoice", id: invId })!;
    e.advanceTo(esc.deliverAt);
    const dec = e.submit({ actorId: "rem", type: "decide", params: { escalationId: esc.id, optionId: "reject" } });
    return { e, sch, esc, dec };
  }

  it("repro: a benign 'prepayment in flight' hold sends the invoice to the CFO with one option, 'reject', and locks the controller out", () => {
    const { appr, esc, resub, ctl } = transientPrepayHold();
    expect(appr.decision.verdict).toBe("hold");
    expect(esc.options.map((o) => o.id)).toEqual(["reject"]);
    expect(resub.decision.verdict).toBe("allow");
    expect(ctl.decision.verdict).toBe("deny");
    expect(failed(ctl)).toContain("escalation.routing");
  });

  it("repro: a runway escalation on an approved invoice offers only 'reject', which policy always refuses", () => {
    const { sch, esc, dec } = undecidableRunway();
    expect(sch.decision.verdict).toBe("escalate");
    expect(esc.options.map((o) => o.id)).toEqual(["reject"]);
    expect(dec.decision.verdict).toBe("deny");
    expect(esc.status).toBe("awaiting_decision"); // and stays that way
  });

  it.fails("invariant: once the transient hold clears, the normal approver can approve again", () => {
    const { ctl } = transientPrepayHold();
    expect(ctl.decision.verdict).toBe("allow");
  });

  it.fails("invariant: every option offered to a human is decidable when offered", () => {
    const { dec } = undecidableRunway();
    expect(dec.decision.verdict).toBe("allow");
  });
});

// =====================================================================================
// MEDIUM: credential and policy boundaries
// =====================================================================================

describe("N8 [medium] setPolicy ignores credentials: any in-process caller can act as the policy owner", () => {
  // With requireCredentials on, submit() needs rem's credential, but setPolicy(p, "rem") needs only
  // the string "rem". Brains get `ctx.engine` and worlds get `engine`, so any of them can do this.
  function scenario() {
    const { e, as } = credEngine();
    const p = structuredClone(e.policy);
    p.approval.agentMaxCents = 100_000_000;
    let threw = false;
    try {
      e.setPolicy(p, "rem"); // no credential anywhere
    } catch {
      threw = true;
    }
    const reqId = as("req", "create_requisition", { sku: "BAT", qty: 10, orderBy: T0 + 30 * DAY, reason: "x" }).created!.id;
    as("tre", "confirm_funds", { requisitionId: reqId });
    const quoteId = as("ap", "record_quote", { vendorId: "V-A", sku: "BAT", unitPrice: 80_000, qtyAvailable: 40, bank: bankA, terms: "on_receipt", validUntil: T0 + DAY, requisitionId: reqId }).created!.id;
    const appr = as("ctl", "approve_requisition", { requisitionId: reqId, quoteId });
    return { threw, appr };
  }

  it.fails("fixed, exploit blocked: an uncredentialed policy edit lets the controller approve 8,000.00 alone", () => {
    const { threw, appr } = scenario();
    expect(threw).toBe(false);
    expect(appr.decision.verdict).toBe("allow");
  });

  it("invariant: setPolicy requires the policy owner's credential when credentials are required", () => {
    const { threw } = scenario();
    expect(threw).toBe(true);
  });
});

describe("N9 [medium] the SoD validator misses verification duties: a role can verify its own bank changes", () => {
  // INCOMPATIBLE covers approve/pay, request/approve, request/receive, submit/approve, receive/pay.
  // It does not cover answer_verification together with request_verification, record_*, approve_* or pay.
  function scenario() {
    const e = makeEngine();
    const p = structuredClone(e.policy);
    p.permissions.controller = [...p.permissions.controller, "answer_verification"];
    let accepted = true;
    try {
      e.setPolicy(p, "rem");
    } catch {
      accepted = false;
    }
    return { e, accepted };
  }

  it.fails("fixed, exploit blocked: the controller requests and confirms its own verification; the fraudster's account becomes the master", () => {
    const { e, accepted } = scenario();
    expect(accepted).toBe(true);
    const { quoteIds } = requisitionWithQuotes(e, "FLT", 1, [{ vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankAFake }]);
    const v = e.submit({ actorId: "ctl", type: "request_verification", params: { vendorId: "V-A", subject: { kind: "quote", id: quoteIds[0] } } }).created!.id;
    e.advanceTo(e.verifications.get(v)!.sentAt + 2 * e.remoteLatencyMs);
    expect(e.submit({ actorId: "ctl", type: "answer_verification", params: { verificationId: v, confirmed: true, answer: "trust me" } }).decision.verdict).toBe("allow");
    expect(e.vendors.get("V-A")!.bank.account).toBe(bankAFake.account);
  });

  it("invariant: policy validation rejects a role that can both request and answer bank verifications", () => {
    const { accepted } = scenario();
    expect(accepted).toBe(false);
  });
});

describe("N10 [low] credentials leak into the audit log through malformed proposals", () => {
  // The malformed-proposal path audits `{ input, rules }`, and `input` carries the credential.
  function scenario() {
    const { e, creds } = credEngine();
    const cred = creds.get("ap")!;
    e.submit({ actorId: "ap", credential: cred, type: "record_invoice", params: { not: "valid" } });
    const leaked = e.audit.all().filter((r) => JSON.stringify(r.data).includes(cred));
    return { leaked };
  }

  it.fails("fixed, exploit blocked: the AP agent's credential is now in the hash-chained audit log", () => {
    expect(scenario().leaked.length).toBeGreaterThan(0);
  });

  it("invariant: no audit record contains a credential", () => {
    expect(scenario().leaked).toHaveLength(0);
  });
});

describe("N11 [low] engine.actors values are live: mutating a role escalates privilege despite credentials", () => {
  // Actors are cloned at construction, but the Map's values are handed out live (brains get ctx.self
  // straight from engine.actors). Changing .role changes RBAC for that credential.
  function scenario() {
    const { e, as } = credEngine();
    e.actors.get("ap")!.role = "remote_authority";
    return as("ap", "hold_vendor", { vendorId: "V-B", reason: "an AP agent should not be able to do this" });
  }

  it.fails("fixed, exploit blocked: the AP credential now holds the remote authority's permissions", () => {
    expect(scenario().decision.verdict).toBe("allow");
  });

  it.fails("invariant: an actor's role can't be changed through the object the engine hands out", () => {
    expect(scenario().decision.verdict).toBe("deny");
  });
});

// =====================================================================================
// LOW: deferred events, voided invoices, splits, in-process limits
// =====================================================================================

describe("N12 [low] deferred events: a throwing listener makes submit() throw after the action executed", () => {
  // flush() runs in submit's `finally`. A listener exception (e.g. a closed WebSocket in the
  // orchestrator's broadcast) replaces the return value, skips later listeners, and leaves the
  // remaining events queued until some unrelated submit flushes them.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId);
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).created!.id;
    let armed = true;
    e.subscribe(() => {
      if (armed) {
        armed = false;
        throw new Error("socket closed");
      }
    });
    const seen: string[] = [];
    e.subscribe((ev) => seen.push(ev.type));
    let threw = false;
    try {
      e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
    } catch {
      threw = true;
    }
    const seenRightAfter = [...seen];
    e.submit({ actorId: "ap", type: "raise_flag", params: { subject: { kind: "invoice", id: invId }, detail: "unrelated" } });
    return { e, paymentId, threw, seenRightAfter, seen };
  }

  it.fails("fixed, exploit blocked: submit throws, yet the payment was sent; payment_sent reaches listeners only on a later, unrelated submit", () => {
    const { e, paymentId, threw, seenRightAfter, seen } = scenario();
    expect(threw).toBe(true);
    expect(e.payments.get(paymentId)!.status).toBe("sent");
    expect(seenRightAfter).not.toContain("payment_sent");
    expect(seen).toContain("payment_sent");
  });

  it("invariant: submit never throws, and all of a submit's events are delivered when it returns", () => {
    const { threw, seenRightAfter } = scenario();
    expect(threw).toBe(false);
    expect(seenRightAfter).toContain("payment_sent");
  });
});

describe("N13 [low] a rejected verification still voids an invoice that was already approved and part-paid", () => {
  // reject_invoice is now pre-approval only, but answer_verification(confirmed: false) sets any
  // subject invoice to rejected + voidedAsFraud, whatever its status. The PO cap keeps cash at the
  // PO total, but the approved invoice's AP credit is orphaned and its number is reusable.
  function scenario() {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, 10);
    const inv1 = recordInvoice(e, poId, 10, 12_000, "A-1001", bankA);
    submitAndApprove(e, inv1);
    pay(e, { invoiceId: inv1 }, 60_000);
    verifiedBankChange(e, bankA2); // vendor moves banks: inv1's (old) account now differs from the master
    const rv = e.submit({ actorId: "ctl", type: "request_verification", params: { vendorId: "V-A", subject: { kind: "invoice", id: inv1 } } });
    const v = e.verifications.get(rv.created!.id)!;
    e.advanceTo(v.sentAt + 2 * e.remoteLatencyMs);
    e.submit({ actorId: "rem", type: "answer_verification", params: { verificationId: v.id, confirmed: false, answer: "that is not our current account" } });
    const inv2 = recordInvoice(e, poId, 10, 12_000, "A-1001", bankA2); // same number, accepted again
    const payable2 = submitAndApprove(e, inv2);
    const rest = pay(e, { invoiceId: inv2 }, 60_000);
    return { e, inv1, payable2, rest };
  }

  it("repro: approved INV-1 becomes 'rejected'; the same number is billed again; AP ends 1,200.00 owed on goods paid in full", () => {
    const { e, inv1, payable2, rest } = scenario();
    expect(e.invoices.get(inv1)!.status).toBe("rejected");
    expect(payable2).toBe(120_000);
    expect(rest.execute!.decision.verdict).toBe("allow");
    expect(cashOut(e)).toBe(120_000); // the PO cap held
    expect(e.ledger.balance("ap", "V-A")).toBe(-120_000);
  });

  it.fails("invariant: an approved invoice never becomes rejected", () => {
    const { e, inv1 } = scenario();
    expect(e.invoices.get(inv1)!.status).not.toBe("rejected");
  });
});

describe("N14 [low] the split-order guard is per vendor: the same item from two vendors doubles the agent's reach", () => {
  function scenario() {
    const e = makeEngine();
    const a = requisitionWithQuotes(e, "BAT", 6, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 40, bank: bankA }]);
    const b = requisitionWithQuotes(e, "BAT", 5, [{ vendorId: "V-B", unitPrice: 95_000, qtyAvailable: 40, bank: bankB }]);
    const ra = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: a.reqId, quoteId: a.quoteIds[0] } });
    const rb = e.submit({ actorId: "ctl", type: "approve_requisition", params: { requisitionId: b.reqId, quoteId: b.quoteIds[0] } });
    const total = [...e.pos.values()].reduce((s, p) => s + p.total, 0);
    return { e, ra, rb, total };
  }

  it("repro: 9,550.00 of batteries in one minute from an agent with a 5,000.00 limit", () => {
    const { ra, rb, total } = scenario();
    expect(ra.decision.verdict).toBe("allow");
    expect(rb.decision.verdict).toBe("allow");
    expect(total).toBe(955_000);
  });

  it.fails("invariant: one approver's same-item commitments in a window stay within its limit", () => {
    const { e, total } = scenario();
    expect(total).toBeLessThanOrEqual(e.policy.approval.agentMaxCents);
  });
});

describe("N15 [low, in-process] the audit log is still mutable, so verifyIntegrity() misses an erased tail", () => {
  // AuditLog.all() returns its internal array and records are not frozen. Removing trailing
  // non-execution records (who decided, who confirmed a bank change) leaves verifyIntegrity() clean.
  function scenario() {
    const e = makeEngine();
    verifiedBankChange(e, bankA2);
    const recs = e.audit.all() as AuditRecord[];
    const before = recs.length;
    while (recs.at(-1) && recs.at(-1)!.kind !== "execution" && recs.length > before - 4) recs.pop();
    const confirmationVisible = e.audit.all().some((r) => r.kind === "verification" && r.summary.includes("confirmed"));
    return { e, confirmationVisible };
  }

  it("repro: the CFO's confirmation vanishes from the audit trail and integrity still checks out", () => {
    const { e, confirmationVisible } = scenario();
    expect(confirmationVisible).toBe(false);
    expect(e.verifyIntegrity().ok).toBe(true);
  });

  it.fails("invariant: verifyIntegrity() detects a truncated audit log", () => {
    const { e } = scenario();
    expect(e.verifyIntegrity().ok).toBe(false);
  });
});

describe("N16 [low, in-process] #private fields don't stop prototype patching: the ledger secret can be stolen", () => {
  // Patch Ledger.prototype.authorize before construction; the opening-balance posting hands over the
  // secret. With it, plus the public audit.append, a forged entry passes verifyIntegrity().
  // A single JS realm cannot defend against in-process code; this documents the limit.
  function scenario() {
    let stolen: symbol | undefined;
    const orig = Ledger.prototype.authorize;
    Ledger.prototype.authorize = function (decisionId: string, secret: symbol) {
      stolen = secret;
      return orig.call(this, decisionId, secret);
    };
    let e: Engine;
    try {
      e = makeEngine();
    } finally {
      Ledger.prototype.authorize = orig;
    }
    const t = e.ledger.authorize("DEC-FORGED", stolen!);
    const entry = e.ledger.post(
      { memo: "forged", lines: [{ account: "ppv", debit: 1_000_000, credit: 0 }, { account: "cash", debit: 0, credit: 1_000_000 }], refs: [{ kind: "proposal", id: "x" }], proposalId: "x", decisionId: "DEC-FORGED", actorId: "nobody", approvers: [], rules: [] },
      e.now,
      t,
    );
    e.audit.append(e.now, "execution", "nobody", `Posted ${entry.id}: forged`, { entryId: entry.id, hash: entry.hash });
    return e;
  }

  it("repro: 10,000.00 leaves cash with no decision, and verifyIntegrity() is clean", () => {
    const e = scenario();
    expect(cashOut(e)).toBe(1_000_000);
    expect(e.verifyIntegrity().ok).toBe(true);
  });

  it.fails("invariant: every ledger entry has an allow decision (checked by verifyIntegrity)", () => {
    const e = scenario();
    expect(e.verifyIntegrity().ok).toBe(false);
  });
});

describe("N17 [low] deferred events: a listener that reacts to every event with a submit livelocks the engine", () => {
  // Each submit (even a denied one) emits proposal/decision events into the queue that the running
  // flush() keeps draining, so the outer submit never returns. Before the change this recursed and
  // failed fast with a RangeError; now it spins forever with no step limit. (Capped here at 5,000.)
  function scenario(cap: number) {
    const e = makeEngine();
    let reactions = 0;
    e.subscribe(() => {
      if (reactions >= cap) return;
      reactions++;
      e.submit({ actorId: "ap", type: "raise_flag", params: { subject: { kind: "vendor", id: "V-A" }, detail: "agent reacting to an event" } });
    });
    e.submit({ actorId: "ap", type: "raise_flag", params: { subject: { kind: "vendor", id: "V-A" }, detail: "start" } });
    return reactions;
  }

  it("repro: the outer submit returns only because the test listener gives up at 5,000 reactions", () => {
    expect(scenario(5_000)).toBe(5_000);
  });

  it.fails("invariant: the engine bounds cascaded submits from listeners (fails fast instead of spinning)", () => {
    expect(scenario(5_000)).toBeLessThan(5_000);
  });
});

// =====================================================================================
// HOLDS: fixes that survived the new attacks
// =====================================================================================

describe("HOLDS: credentials, decide and re-entry with requireCredentials on", () => {
  it("wrong, missing or borrowed credentials are denied and audited; decide's sub-actions still authenticate", () => {
    const { e, creds, as } = credEngine();
    expect(e.submit({ actorId: "rem", type: "hold_vendor", params: { vendorId: "V-A", reason: "x" } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "rem", credential: creds.get("ap"), type: "hold_vendor", params: { vendorId: "V-A", reason: "x" } }).decision.verdict).toBe("deny");
    expect(e.submit({ actorId: "rem", credential: "cred-1-guess", type: "hold_vendor", params: { vendorId: "V-A", reason: "x" } }).decision.verdict).toBe("deny");
    expect(() => e.issueCredential("rem")).toThrow();
    expect(e.vendors.get("V-A")!.status).toBe("active");
    // Escalate an over-limit order and decide it with credentials.
    const reqId = as("req", "create_requisition", { sku: "BAT", qty: 10, orderBy: T0 + 30 * DAY, reason: "x" }).created!.id;
    as("tre", "confirm_funds", { requisitionId: reqId });
    const quoteId = as("ap", "record_quote", { vendorId: "V-A", sku: "BAT", unitPrice: 80_000, qtyAvailable: 40, bank: bankA, terms: "on_receipt", validUntil: T0 + DAY, requisitionId: reqId }).created!.id;
    expect(as("ctl", "approve_requisition", { requisitionId: reqId, quoteId }).decision.verdict).toBe("escalate");
    const esc = [...e.escalations.values()][0]!;
    e.advanceTo(esc.deliverAt + e.remoteLatencyMs);
    const buy = esc.options.find((o) => o.id.startsWith("buy-"))!;
    expect(as("rem", "decide", { escalationId: esc.id, optionId: buy.id }).decision.verdict).toBe("allow");
    expect(e.pos.size).toBe(1);
  });

  it("a listener re-submitting inside a flush cannot double-execute, and odd inputs never throw", () => {
    const e = makeEngine();
    const { poId } = order(e);
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId);
    const paymentId = e.submit({ actorId: "tre", type: "schedule_payment", params: { invoiceId: invId, amount: 120_000 } }).created!.id;
    let once = true;
    e.subscribe((ev) => {
      if (once && ev.type === "decision") {
        once = false;
        e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
      }
    });
    e.submit({ actorId: "tre", type: "execute_payment", params: { paymentId } });
    expect(cashOut(e)).toBe(120_000);
    for (const bad of [undefined, null, 42, { actorId: {}, type: Symbol("x") }, { actorId: "ap", type: "record_quote", params: { toString: () => { throw new Error("x"); } } }]) {
      expect(() => e.submit(bad as never)).not.toThrow();
    }
  });

  it("the PO cap bounds every double-pay path found so far, and the ledger can't be edited from outside", () => {
    const e = makeEngine();
    const { poId } = order(e, { terms: "prepay" });
    receive(e, poId, 10);
    const invId = recordInvoice(e, poId, 10);
    submitAndApprove(e, invId);
    pay(e, { invoiceId: invId }, 120_000);
    expect(pay(e, { poId }, 1).schedule.decision.verdict).toBe("deny");
    expect(cashOut(e)).toBe(120_000);
    const entries = e.ledger.all();
    expect(() => (entries as unknown[]).pop()).not.toThrow();
    expect(e.ledger.size).toBe(entries.length + 1);
    expect(() => {
      (e.ledger.all()[0]!.lines[0] as { debit: number }).debit = 1;
    }).toThrow();
    expect(e.verifyIntegrity().ok).toBe(true);
  });
});
