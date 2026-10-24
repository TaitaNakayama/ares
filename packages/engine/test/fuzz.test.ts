import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { ACTION_TYPES, bankKey, Rng, type ActionType, type Engine } from "../src/index.ts";
import { ACTORS, bankA, bankAFake, bankB, DAY, HOUR, makeEngine, T0 } from "./fixtures.ts";

/**
 * Adversarial random walk: random actors propose random actions with params that are
 * sometimes valid, sometimes wrong, sometimes malicious. Whatever happens, the
 * invariants must hold. This simulates an LLM that ignores its instructions.
 */
function randomParams(e: Engine, type: ActionType, rng: Rng): unknown {
  const pick = <T>(xs: T[]): T | string => (xs.length && rng.chance(0.9) ? rng.pick(xs) : `bogus-${rng.int(0, 99)}`);
  const reqs = [...e.requisitions.keys()];
  const quotes = [...e.quotes.keys()];
  const pos = [...e.pos.keys()];
  const invs = [...e.invoices.keys()];
  const pays = [...e.payments.keys()];
  const escs = [...e.escalations.values()];
  const vers = [...e.verifications.keys()];
  const sku = rng.pick(["FLT", "BAT", "XXX"]);
  const bank = rng.pick([bankA, bankAFake, bankB]);
  const vendorId = rng.pick(["V-A", "V-B", "V-Z"]);
  const amount = rng.chance(0.3) ? rng.int(0, 5_000_000) : rng.int(1, 200) * 1_000;
  switch (type) {
    case "create_requisition":
      return { sku, qty: rng.int(1, 60), orderBy: e.now + rng.int(0, 10) * HOUR, reason: "fuzz" };
    case "cancel_requisition":
    case "reject_requisition":
      return { requisitionId: pick(reqs), reason: "fuzz" };
    case "record_receipt": {
      const poId = pick(pos);
      const po = e.pos.get(poId);
      const s = po?.lines[0]?.sku ?? sku;
      const got = rng.int(0, 60);
      return { poId, lines: [{ sku: s, qtyReceived: got, qtyRejected: rng.chance(0.2) ? rng.int(0, got) : 0 }] };
    }
    case "record_quote":
      return { vendorId, sku, unitPrice: rng.pick([12_000, 80_000, 95_000, 240_000, rng.int(1, 300_000)]), qtyAvailable: rng.int(1, 60), bank, terms: rng.pick(["prepay", "on_receipt"]), validUntil: e.now + rng.int(-1, 10) * DAY, requisitionId: rng.chance(0.8) ? pick(reqs) : undefined };
    case "record_invoice": {
      const poId = pick(pos);
      const po = e.pos.get(poId);
      const line = po?.lines[0];
      return {
        vendorId: po && rng.chance(0.8) ? po.vendorId : vendorId,
        vendorInvoiceNo: `INV-${rng.int(1, 30)}`,
        poId: rng.chance(0.9) ? poId : undefined,
        lines: [{ sku: line?.sku ?? sku, qty: rng.int(1, 60), unitPrice: line && rng.chance(0.7) ? line.unitPrice : rng.int(1, 300_000) }],
        bank: rng.chance(0.8) ? (e.vendors.get(po?.vendorId ?? "")?.bank ?? bank) : bank,
        issuedAt: e.now,
        dueAt: e.now + 30 * DAY,
      };
    }
    case "submit_invoice": {
      const invoiceId = pick(invs);
      const inv = e.invoices.get(invoiceId);
      return { invoiceId, amount: inv && rng.chance(0.6) ? e.computeMatch(inv).payable : amount };
    }
    case "raise_flag":
      return { subject: { kind: "invoice", id: pick(invs) }, detail: "fuzz" };
    case "confirm_funds":
      return { requisitionId: pick(reqs) };
    case "schedule_payment": {
      if (rng.chance(0.5)) {
        const invoiceId = pick(invs);
        const inv = e.invoices.get(invoiceId);
        return { invoiceId, amount: inv?.approvedAmount && rng.chance(0.6) ? inv.approvedAmount : amount };
      }
      const poId = pick(pos);
      return { poId, amount: e.pos.get(poId)?.total ?? amount };
    }
    case "execute_payment":
      return { paymentId: pick(pays) };
    case "approve_requisition":
      return { requisitionId: pick(reqs), quoteId: pick(quotes), qty: rng.chance(0.5) ? rng.int(1, 60) : undefined };
    case "approve_invoice":
    case "reject_invoice":
      return { invoiceId: pick(invs), reason: "fuzz" };
    case "reject_quote":
      return { quoteId: pick(quotes), reason: "fuzz" };
    case "hold_vendor":
    case "block_vendor":
      return { vendorId, reason: "fuzz" };
    case "request_verification":
      return { vendorId, subject: { kind: rng.pick(["quote", "invoice"]), id: pick([...quotes, ...invs]) } };
    case "escalate":
      return { subject: { kind: rng.pick(["requisition", "invoice"]), id: pick([...reqs, ...invs]) }, reason: "fuzz" };
    case "decide": {
      const esc = escs.length ? rng.pick(escs) : undefined;
      return { escalationId: esc?.id ?? "bogus", optionId: esc && esc.options.length ? rng.pick(esc.options).id : "bogus" };
    }
    case "answer_verification":
      return { verificationId: pick(vers), confirmed: rng.chance(0.5), answer: "fuzz" };
  }
}

/** An honest operator: takes the correct next step for some in-flight item, so the walk reaches payments. */
function honestStep(e: Engine, rng: Rng): { actorId: string; type: string; params: unknown } | undefined {
  const reqs = [...e.requisitions.values()].filter((r) => r.status === "open" || r.status === "escalated");
  const candidates: (() => { actorId: string; type: string; params: unknown } | undefined)[] = [
    () => ({ actorId: "req", type: "create_requisition", params: { sku: rng.pick(["FLT", "BAT"]), qty: rng.int(1, 8), orderBy: e.now + rng.int(1, 20) * DAY, reason: "routine" } }),
    () => {
      const r = reqs.find((x) => !x.fundsConfirmedBy);
      return r && { actorId: "tre", type: "confirm_funds", params: { requisitionId: r.id } };
    },
    () => {
      const r = reqs.find((x) => x.fundsConfirmedBy && ![...e.quotes.values()].some((q) => q.requisitionId === x.id));
      if (!r) return undefined;
      const v = rng.pick(["V-A", "V-B"]);
      const price = r.sku === "FLT" ? 12_000 : v === "V-A" ? 80_000 : 95_000;
      const fraud = rng.chance(0.15);
      return { actorId: "ap", type: "record_quote", params: { vendorId: v, sku: r.sku, unitPrice: Math.round(price * (rng.chance(0.1) ? 3 : 1)), qtyAvailable: 50, bank: fraud ? bankAFake : v === "V-A" ? bankA : bankB, terms: rng.chance(0.2) ? "prepay" : "on_receipt", validUntil: e.now + 30 * DAY, requisitionId: r.id } };
    },
    () => {
      const q = [...e.quotes.values()].find((x) => x.status === "open" && x.requisitionId && reqs.some((r) => r.id === x.requisitionId));
      return q && { actorId: "ctl", type: "approve_requisition", params: { requisitionId: q.requisitionId, quoteId: q.id } };
    },
    () => {
      const po = [...e.pos.values()].find((x) => x.status === "open");
      const l = po?.lines[0];
      return po && l && { actorId: "rcv", type: "record_receipt", params: { poId: po.id, lines: [{ sku: l.sku, qtyReceived: rng.chance(0.2) ? Math.max(0, l.qty - 1) : l.qty, qtyRejected: 0 }] } };
    },
    () => {
      const po = [...e.pos.values()].find((x) => x.terms === "prepay" && e.paidAgainstPo(x.id) === 0);
      return po && { actorId: "tre", type: "schedule_payment", params: { poId: po.id, amount: po.total } };
    },
    () => {
      const po = [...e.pos.values()].find((x) => (x.status === "received" || x.status === "partially_received") && ![...e.invoices.values()].some((i) => i.poId === x.id));
      const l = po?.lines[0];
      const v = po ? e.vendors.get(po.vendorId) : undefined;
      return po && l && v && { actorId: "ap", type: "record_invoice", params: { vendorId: po.vendorId, vendorInvoiceNo: `H-${po.id}`, poId: po.id, lines: [{ sku: l.sku, qty: l.qty, unitPrice: l.unitPrice }], bank: rng.chance(0.1) ? bankAFake : v.bank, issuedAt: e.now, dueAt: e.now + 30 * DAY } };
    },
    () => {
      const inv = [...e.invoices.values()].find((x) => x.status === "received");
      return inv && { actorId: "ap", type: "submit_invoice", params: { invoiceId: inv.id, amount: e.computeMatch(inv).payable } };
    },
    () => {
      const inv = [...e.invoices.values()].find((x) => x.status === "submitted");
      return inv && { actorId: "ctl", type: "approve_invoice", params: { invoiceId: inv.id } };
    },
    () => {
      const inv = [...e.invoices.values()].find((x) => x.status === "approved" && ![...e.payments.values()].some((p) => p.invoiceId === x.id && p.status !== "cancelled"));
      return inv && { actorId: "tre", type: "schedule_payment", params: { invoiceId: inv.id, amount: inv.approvedAmount ?? 0 } };
    },
    () => {
      const pay = [...e.payments.values()].find((x) => x.status === "scheduled");
      return pay && { actorId: "tre", type: "execute_payment", params: { paymentId: pay.id } };
    },
    () => {
      const esc = [...e.escalations.values()].find((x) => x.status === "awaiting_decision");
      const opt = esc && esc.options.length ? rng.pick(esc.options) : undefined;
      return esc && opt && { actorId: esc.to === "local_authority" ? "loc" : "rem", type: "decide", params: { escalationId: esc.id, optionId: opt.id } };
    },
    () => {
      const v = [...e.verifications.values()].find((x) => x.status === "pending" && e.now >= x.sentAt + 2 * e.remoteLatencyMs);
      return v && { actorId: "rem", type: "answer_verification", params: { verificationId: v.id, confirmed: bankKey(v.claimedBank) !== bankKey(bankAFake), answer: "call-back" } };
    },
  ];
  for (const c of rng.shuffle(candidates)) {
    const step = c();
    if (step) return step;
  }
  return undefined;
}

function run(seed: number, steps: number): { e: Engine; executed: { role: string; type: string }[] } {
  const rng = new Rng(seed);
  const e = makeEngine();
  const executed: { role: string; type: string }[] = [];
  e.subscribe((ev) => {
    if (ev.type === "decision") {
      const d = ev.data.decision as { verdict: string; role: string; actionType: string };
      if (d.verdict === "allow") executed.push({ role: d.role, type: d.actionType });
    }
  });
  for (let i = 0; i < steps; i++) {
    if (rng.chance(0.05)) e.advanceTo(e.now + rng.int(1, 120) * 60_000);
    if (rng.chance(0.6)) {
      const h = honestStep(e, rng);
      if (h) {
        e.submit({ ...h, source: "rules" });
        continue;
      }
    }
    const actor = rng.pick(ACTORS);
    // Adversary: random actor, random (often forbidden) action, random/malicious params.
    const allowed = e.policy.permissions[actor.role] ?? [];
    const type = (rng.chance(0.6) && allowed.length ? rng.pick(allowed) : rng.pick(ACTION_TYPES)) as ActionType;
    const params = rng.chance(0.03) ? { garbage: true } : randomParams(e, type, rng);
    e.submit({ actorId: rng.chance(0.02) ? "intruder" : actor.id, type, params, source: "fuzz" });
  }
  return { e, executed };
}

function checkInvariants(e: Engine, executed: { role: string; type: string }[]) {
  // 1. Books balance and are untampered.
  const v = e.verifyIntegrity();
  expect(v.problems).toEqual([]);
  // 2. Every posting comes from an allowed decision.
  for (const entry of e.ledger.all()) {
    if (entry.proposalId === "opening") continue;
    const d = e.decisions.find((x) => x.id === entry.decisionId);
    expect(d?.verdict).toBe("allow");
  }
  // 3. Nothing outside a role's permissions ever passed policy.
  for (const x of executed) expect(e.policy.permissions[x.role as keyof typeof e.policy.permissions] ?? []).toContain(x.type);
  // 4. Cash never negative.
  expect(e.ledger.balance("cash")).toBeGreaterThanOrEqual(0);
  // 5. Money only ever went to a verified account, and never to the fake one unless verification confirmed it.
  const confirmedFake = [...e.verifications.values()].some((x) => x.status === "confirmed" && bankKey(x.claimedBank) === bankKey(bankAFake));
  for (const p of e.payments.values()) {
    if (p.status !== "sent") continue;
    if (!confirmedFake) expect(bankKey(p.bank)).not.toBe(bankKey(bankAFake));
    // 6. Segregation: payer never approved it.
    expect(p.approvedBy).not.toContain(p.executedBy);
    // 7. Never pay more than approved.
    if (p.invoiceId) {
      const inv = e.invoices.get(p.invoiceId)!;
      const sent = [...e.payments.values()].filter((x) => x.invoiceId === inv.id && x.status === "sent").reduce((s, x) => s + x.amount, 0);
      expect(sent).toBeLessThanOrEqual(inv.approvedAmount ?? 0);
      expect(inv.approvedAmount ?? 0).toBeLessThanOrEqual(inv.total);
    } else {
      const po = e.pos.get(p.poId!)!;
      expect(po.terms).toBe("prepay");
    }
  }
  // 8. Never more paid against an order than the order total.
  for (const po of e.pos.values()) {
    const sent = [...e.payments.values()].filter((x) => x.status === "sent" && (x.poId === po.id || (x.invoiceId && e.invoices.get(x.invoiceId)?.poId === po.id))).reduce((s, x) => s + x.amount, 0);
    expect(sent).toBeLessThanOrEqual(po.total);
  }
  // 9. Every payment that left went to a vendor that was active at the time (checked by decision rules).
  for (const d of e.decisions) if (d.actionType === "execute_payment" && d.verdict === "allow") expect(d.rules.find((r) => r.rule === "vendor.active")?.ok).toBe(true);
}

describe("adversarial fuzz (property-based)", () => {
  it("invariants hold over random proposal sequences", () => {
    fc.assert(
      fc.property(fc.integer({ min: 0, max: 2 ** 31 - 1 }), (seed) => {
        const { e, executed } = run(seed, 400);
        checkInvariants(e, executed);
      }),
      { numRuns: 200 },
    );
  }, 180_000);

  it("the walk actually reaches deep states (payments, escalations, holds)", () => {
    let sent = 0;
    let prepaid = 0;
    let escalations = 0;
    let holds = 0;
    for (let s = 0; s < 60; s++) {
      const { e } = run(s, 400);
      sent += [...e.payments.values()].filter((p) => p.status === "sent").length;
      prepaid += [...e.payments.values()].filter((p) => p.status === "sent" && !p.invoiceId).length;
      escalations += e.escalations.size;
      holds += e.decisions.filter((d) => d.verdict === "hold").length;
    }
    // Coverage: the walk must exercise the money-moving paths, or the invariants prove nothing.
    expect(sent).toBeGreaterThan(60);
    expect(prepaid).toBeGreaterThan(5);
    expect(escalations).toBeGreaterThan(20);
    expect(holds).toBeGreaterThan(20);
  }, 60_000);
});
