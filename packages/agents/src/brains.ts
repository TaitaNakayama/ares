import { formatCents, type Actor, type AgentRole, type Engine, type EngineEvent, type Invoice, type Time } from "@ares/engine";
import type { Mood, WorldEvent } from "./world.ts";

export type AgentInput = { kind: "engine"; event: EngineEvent } | { kind: "world"; event: WorldEvent; at: Time };

/** What an agent wants to do. It becomes a proposal; the engine decides. */
export interface Intent {
  type: string;
  params: unknown;
  rationale: string;
  /** Line the agent says if the proposal goes through. */
  say?: string;
  /** Headline version for small displays (VR speech bubbles): about 60 characters. */
  short?: string;
  mood?: Mood;
  /** What actually produced this intent, recorded as the proposal's `source`. Default: rules code. */
  via?: "rules" | "llm" | "parser";
}

export interface BrainContext {
  engine: Engine;
  self: Actor;
  fmtTime: (t: Time) => string;
  itemName: (sku: string) => string;
  /** The world's domain tools for this actor (power, life support, the lab), when it has any. */
  worldTools?: { name: string; description: string; parameters: Record<string, unknown> }[];
  /** Read-only world state for prompts (power level, reserves, the lab). */
  worldState?: Record<string, unknown>;
}

export interface Brain {
  readonly role: AgentRole;
  readonly kind: "rules" | "llm";
  /** The engine actor this brain speaks for, when a role has several (Engineer, Life and Science are all requesters). */
  readonly actorId?: string;
  react(input: AgentInput, ctx: BrainContext): Promise<Intent[]> | Intent[];
}

const ev = (input: AgentInput, type: string): Record<string, unknown> | undefined =>
  input.kind === "engine" && input.event.type === type ? input.event.data : undefined;

/** Requester: turns operational needs into purchase requests. */
export class RequesterRules implements Brain {
  readonly role = "requester" as const;
  readonly kind = "rules" as const;
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    if (input.kind !== "world" || input.event.type !== "need") return [];
    const n = input.event;
    return [
      {
        type: "create_requisition",
        params: { sku: n.sku, qty: n.qty, orderBy: n.orderBy, reason: n.reason, context: n.context },
        rationale: n.reason,
        say: `Requesting ${n.qty} ${plainName(ctx.itemName(n.sku))}.`,
        short: `Requesting ${n.qty} ${plainName(ctx.itemName(n.sku))}.`,
        mood: "worried",
      },
    ];
  }
}

/** Receiver: records what physically arrived. */
export class ReceiverRules implements Brain {
  readonly role = "receiver" as const;
  readonly kind = "rules" as const;
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    if (input.kind !== "world" || input.event.type !== "delivery") return [];
    const d = input.event;
    const po = ctx.engine.pos.get(d.poId);
    const parts = d.lines.map((l) => {
      const ordered = po?.lines.find((x) => x.sku === l.sku)?.qty;
      const good = l.qtyReceived - l.qtyRejected;
      return `${good}${ordered !== undefined ? ` of ${ordered}` : ""} ${ctx.itemName(l.sku)}${l.qtyRejected ? ` (${l.qtyRejected} damaged)` : ""}`;
    });
    const short = po ? d.lines.some((l) => l.qtyReceived - l.qtyRejected < (po.lines.find((x) => x.sku === l.sku)?.qty ?? 0)) : false;
    const missing = po ? d.lines.reduce((n, l) => n + Math.max(0, (po.lines.find((x) => x.sku === l.sku)?.qty ?? 0) - (l.qtyReceived - l.qtyRejected)), 0) : 0;
    return [
      {
        type: "record_receipt",
        params: { poId: d.poId, lines: d.lines, note: d.note, sourceRef: d.docId },
        rationale: `Counted delivery for ${d.poId}`,
        say: short ? `${missing} missing from this delivery. Counted the rest.` : "Delivery counted. Everything arrived.",
        short: short ? `${missing} missing from this delivery. Counted the rest.` : "Delivery counted. Everything arrived.",
        mood: short ? "attentive" : "calm",
      },
    ];
  }
}

/** AP: enters documents, runs the three-way match, submits the matched amount. */
export class ApRules implements Brain {
  readonly role = "ap" as const;
  readonly kind = "rules" as const;
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    const e = ctx.engine;
    if (input.kind === "world" && input.event.type === "document") {
      const { doc } = input.event;
      if (doc.kind === "quote" && doc.fields.quote) {
        const q = doc.fields.quote;
        return [
          {
            type: "record_quote",
            params: { ...q, sourceRef: doc.id },
            rationale: `Quote document ${doc.id} from ${doc.from}`,
            say: `Quote in from ${e.vendors.get(q.vendorId)?.name ?? doc.from}.`,
            short: `Quote in from ${e.vendors.get(q.vendorId)?.name ?? doc.from}.`,
          },
        ];
      }
      if (doc.kind === "invoice" && doc.fields.invoice) {
        const inv = doc.fields.invoice;
        return [
          {
            type: "record_invoice",
            params: { ...inv, sourceRef: doc.id },
            rationale: `Invoice document ${doc.id} from ${doc.from}`,
            say: `Invoice in from ${e.vendors.get(inv.vendorId)?.name ?? doc.from}.`,
            short: `Invoice in from ${e.vendors.get(inv.vendorId)?.name ?? doc.from}.`,
          },
        ];
      }
      return [];
    }
    const flag = ev(input, "flag_raised");
    if (flag) {
      const f = flag.flag as { code: string; detail: string; raisedBy: string; subject: { kind: string } };
      if (f.raisedBy !== ctx.self.id || f.code === "qty_over_receipt") return [];
      // Narration only: the engine already recorded the flag.
      const shortFlag: Record<string, string> = {
        bank_mismatch: "New bank account on this document. Suspicious!",
        price_anomaly: `Price far above this supplier's history!`,
        price_over_contract: "Price above the contract!",
        price_over_po: "Billed above the order price!",
        duplicate: "This looks like a duplicate!",
      };
      const line = shortFlag[f.code] ?? `Flag: ${f.code.replace(/_/g, " ")}.`;
      return [{ type: "__say", params: {}, rationale: `Flag: ${f.detail}`, say: line, short: line, mood: "suspicious" }];
    }
    const recorded = ev(input, "invoice_recorded");
    if (recorded) return this.trySubmit(recorded.invoice as Invoice, ctx);
    const receipt = ev(input, "receipt_recorded");
    if (receipt) {
      const poId = (receipt.po as { id: string }).id;
      return [...e.invoices.values()].filter((i) => i.poId === poId && (i.status === "received" || i.status === "submitted")).flatMap((i) => this.trySubmit(i, ctx));
    }
    const vs = ev(input, "vendor_status_changed");
    if (vs) {
      const v = vs.vendor as { id: string; status: string };
      // A released supplier's held invoices go back through the full match.
      if (v.status === "active") return [...e.invoices.values()].filter((i) => i.vendorId === v.id && i.status === "held").flatMap((i) => this.trySubmit(i, ctx));
      return [];
    }
    const answered = ev(input, "verification_answered");
    if (answered) {
      const v = answered.verification as { status: string; subject: { kind: string; id: string } };
      if (v.status === "confirmed" && v.subject.kind === "invoice") {
        const inv = e.invoices.get(v.subject.id);
        if (inv) return this.trySubmit(inv, ctx);
      }
    }
    return [];
  }

  private trySubmit(invRef: Invoice, ctx: BrainContext): Intent[] {
    const e = ctx.engine;
    const inv = e.invoices.get(invRef.id);
    if (!inv || (inv.status !== "received" && inv.status !== "held" && inv.status !== "submitted")) return [];
    // A submitted invoice is only re-submitted when the match changed (e.g. goods arrived late).
    if (inv.status === "submitted" && e.computeMatch(inv).payable === inv.approvedAmount) return [];
    const po = inv.poId ? e.pos.get(inv.poId) : undefined;
    const hasReceipt = po ? [...e.receipts.values()].some((g) => g.poId === po.id) : false;
    if (po && !hasReceipt && po.terms === "on_receipt") return []; // wait for the goods
    const m = e.computeMatch(inv);
    const billed = inv.lines.reduce((s, l) => s + l.qty, 0);
    const paying = m.lines.reduce((s, l) => s + l.payQty, 0);
    const earlier = m.lines.reduce((s, l) => s + l.alreadyBilled, 0);
    const detail =
      paying < billed
        ? earlier > 0
          ? `Invoice bills ${billed}, but ${earlier} were already paid on earlier invoices. Paying only for the ${paying} received since: ${formatCents(m.payable)}.`
          : `Invoice bills ${billed}, we received ${paying}. Paying only for ${paying}: ${formatCents(m.payable)}.`
        : `Invoice matches order and receipt. Submitting ${formatCents(m.payable)}.`;
    const say = paying < billed ? (earlier > 0 ? "Some were paid already. Paying only the rest." : `${billed - paying} never arrived. I won't pay for those.`) : "Invoice matches. Sending it for approval.";
    return [{ type: "submit_invoice", params: { invoiceId: inv.id, amount: m.payable }, rationale: detail, say, short: say, mood: paying < billed ? "attentive" : "calm" }];
  }
}

/** Treasury: funds checks, schedules and sends approved payments. */
export class TreasuryRules implements Brain {
  readonly role = "treasury" as const;
  readonly kind = "rules" as const;
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    const e = ctx.engine;
    const created = ev(input, "requisition_created");
    if (created) {
      const r = created.requisition as { id: string; qty: number; sku: string; orderBy: Time };
      const est = r.qty * e.marketPrice(r.sku);
      const after = Math.floor((e.ledger.balance("cash") - e.openCommitments() - est) / Math.max(1, e.burnPerDayCents));
      return [
        {
          type: "confirm_funds",
          params: { requisitionId: r.id },
          rationale: `Estimated ${formatCents(est)}`,
          say: "We can afford it.",
          short: "We can afford it.",
        },
      ];
    }
    const approved = ev(input, "invoice_approved");
    if (approved) {
      const inv = approved.invoice as Invoice;
      const already = [...e.payments.values()].filter((p) => p.invoiceId === inv.id && p.status !== "cancelled").reduce((s, p) => s + p.amount, 0);
      const amount = (inv.approvedAmount ?? 0) - already;
      if (amount <= 0) return [];
      return [{ type: "schedule_payment", params: { invoiceId: inv.id, amount }, rationale: "Approved invoice", say: "Paying the verified account on file.", short: "Paying the verified account on file." }];
    }
    const po = ev(input, "po_created");
    if (po) {
      const p = po.po as { id: string; terms: string; total: number };
      if (p.terms !== "prepay") return [];
      return [{ type: "schedule_payment", params: { poId: p.id, amount: p.total }, rationale: "Prepaid order", say: "Prepaying the verified account on file.", short: "Prepaying the verified account on file." }];
    }
    const sched = ev(input, "payment_scheduled");
    if (sched) {
      const p = sched.payment as { id: string; amount: number; vendorId: string };
      return [{ type: "execute_payment", params: { paymentId: p.id }, rationale: "Scheduled payment due", say: `Paid ${e.vendors.get(p.vendorId)?.name}.`, short: `Paid ${e.vendors.get(p.vendorId)?.name}.`, mood: "happy" }];
    }
    return [];
  }
}

/** Controller: chooses quotes, approves, blocks, verifies and escalates. */
export class ControllerRules implements Brain {
  readonly role = "controller" as const;
  readonly kind = "rules" as const;
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    const e = ctx.engine;
    if (input.kind === "world" && input.event.type === "rfq_closed") return this.source(input.event.requisitionId, ctx);

    const submitted = ev(input, "invoice_submitted");
    if (submitted) {
      const inv = submitted.invoice as Invoice;
      return [{ type: "approve_invoice", params: { invoiceId: inv.id }, rationale: "Three-way match passed", say: "Match passed. Invoice approved.", short: "Match passed. Invoice approved." }];
    }
    const held = ev(input, "invoice_held");
    if (held) {
      const inv = held.invoice as Invoice;
      const reasons = held.reasons as { rule: string; detail: string }[];
      const priceIssue = reasons.find((r) => r.rule === "match.price_within_tolerance" || r.rule === "contract.price");
      if (priceIssue) {
        return [{ type: "reject_invoice", params: { invoiceId: inv.id, reason: `Billed above agreed price: ${priceIssue.detail}. Request a corrected invoice.` }, rationale: priceIssue.detail, say: "Rejected. Billed above the agreed price.", short: "Rejected. Billed above the agreed price.", mood: "suspicious" }];
      }
      if (reasons.some((r) => r.rule === "match.po_exists")) {
        return [{ type: "reject_invoice", params: { invoiceId: inv.id, reason: "No matching purchase order." }, rationale: "no PO", say: "Rejected. There's no matching order.", short: "Rejected. There's no matching order.", mood: "suspicious" }];
      }
      const bank = reasons.find((r) => r.rule === "vendor.bank_matches_master");
      if (bank) return [{ type: "__say", params: {}, rationale: "", say: "Holding this bill. Asking Earth about the bank.", short: "Holding this bill. Asking Earth about the bank.", mood: "suspicious" }];
      return [];
    }
    const decision = ev(input, "decision");
    if (decision) {
      const d = decision.decision as { verdict: string; actionType: string; rules: { rule: string; ok: boolean; detail: string }[]; proposalId: string };
      const dup = d.rules.find((r) => !r.ok && r.rule.startsWith("dup."));
      if (d.verdict === "deny" && d.actionType === "submit_invoice" && dup) {
        const p = e.proposals.find((x) => x.id === d.proposalId);
        const invoiceId = (p?.action.params as { invoiceId?: string } | undefined)?.invoiceId;
        const inv = invoiceId ? e.invoices.get(invoiceId) : undefined;
        if (inv && inv.status === "received") {
          return [{ type: "reject_invoice", params: { invoiceId: inv.id, reason: `Duplicate: ${dup.detail}` }, rationale: dup.detail, say: "Duplicate invoice blocked.", short: "Duplicate invoice blocked.", mood: "suspicious" }];
        }
      }
      return [];
    }
    const answered = ev(input, "verification_answered");
    if (answered) {
      const v = answered.verification as { status: string; vendorId: string; subject: { kind: string; id: string }; answer: string };
      const vendor = e.vendors.get(v.vendorId);
      if (v.status === "rejected") {
        const saved = e.amountOf(v.subject as never);
        return [
          {
            type: "hold_vendor",
            params: { vendorId: v.vendorId, reason: "Bank-change request was fraudulent (impersonation). Vendor record locked pending re-verification." },
            rationale: v.answer,
            say: "The bank change was fake. Supplier locked.",
            short: "The bank change was fake. Supplier locked.",
            mood: "suspicious",
          },
        ];
      }
      if (v.status === "confirmed" && v.subject.kind === "quote") {
        const q = e.quotes.get(v.subject.id);
        const req = q?.requisitionId ? e.requisitions.get(q.requisitionId) : undefined;
        // If a human already holds the decision, the rebuilt escalation options carry it; don't act around them.
        if (q && req && (req.status === "open" || req.status === "escalated") && !e.openEscalationFor({ kind: "requisition", id: req.id })) {
          return [{ type: "approve_requisition", params: { requisitionId: req.id, quoteId: q.id }, rationale: "Bank change verified", say: "Bank change verified. Approving the order.", short: "Bank change verified. Approving the order." }];
        }
      }
      return [];
    }
    return [];
  }

  private source(requisitionId: string, ctx: BrainContext): Intent[] {
    const e = ctx.engine;
    const req = e.requisitions.get(requisitionId);
    if (!req || (req.status !== "open" && req.status !== "escalated")) return [];
    const quotes = [...e.quotes.values()].filter((q) => q.requisitionId === req.id && q.status === "open" && q.validUntil >= e.now);
    if (quotes.length === 0) {
      return [{ type: "escalate", params: { subject: { kind: "requisition", id: req.id }, reason: "No valid quotes received." }, rationale: "no quotes", say: "No valid quotes. Escalating.", mood: "attentive" }];
    }
    const assessed = quotes.map((q) => ({ q, failed: e.quoteRules(q).filter((r) => !r.ok) }));
    const cleanFull = assessed.filter((a) => a.failed.length === 0 && a.q.qtyAvailable >= req.qty).sort((a, b) => a.q.unitPrice - b.q.unitPrice);
    if (cleanFull[0]) {
      const q = cleanFull[0].q;
      return [{ type: "approve_requisition", params: { requisitionId: req.id, quoteId: q.id }, rationale: "Cheapest clean quote covering the full request", say: `Ordering from ${e.vendors.get(q.vendorId)?.name}.`, short: `Ordering from ${e.vendors.get(q.vendorId)?.name}.` }];
    }
    const intents: Intent[] = [];
    const problems: string[] = [];
    for (const a of assessed) {
      if (a.failed.some((r) => r.rule === "vendor.bank_matches_master")) {
        intents.push({ type: "request_verification", params: { vendorId: a.q.vendorId, subject: { kind: "quote", id: a.q.id } }, rationale: "Bank details differ from vendor master", say: "That's a scam. Payment blocked.", short: "That's a scam. Payment blocked.", mood: "suspicious" });
      }
      if (a.failed.length) problems.push(`${e.vendors.get(a.q.vendorId)?.name}: ${a.failed.map((r) => r.detail).join("; ")}`);
    }
    const partial = assessed.filter((a) => a.failed.length === 0 && a.q.qtyAvailable < req.qty);
    if (partial.length) problems.push(`clean quotes cover only ${Math.max(...partial.map((p) => p.q.qtyAvailable))} of ${req.qty}`);
    intents.push({
      type: "escalate",
      params: { subject: { kind: "requisition", id: req.id }, reason: problems.join(" | ") || "No acceptable quote." },
      rationale: problems.join(" | "),
      say: "I can't approve this. Commander, your call.",
      short: "I can't approve this. Commander, your call.",
      mood: "suspicious",
    });
    return intents;
  }
}

/** "battery modules (10 kWh)" -> "battery modules": a name to say out loud (no extra numbers). */
export function plainName(name: string): string {
  return name.replace(/\s*\([^)]*\)/g, "").trim();
}

/** "$9,896,697.15" -> "$9.9M": headline money. */
export function compact(cents: number): string {
  const v = cents / 100;
  if (v >= 1e9) return `$${(v / 1e9).toFixed(2)}B`;
  if (v >= 1e6) return `$${(v / 1e6).toFixed(1)}M`;
  if (v >= 1e3) return `$${Math.round(v / 1e3)}k`;
  return `$${Math.round(v)}`;
}

export function defaultRuleBrains(): Brain[] {
  return [new RequesterRules(), new ReceiverRules(), new ApRules(), new TreasuryRules(), new ControllerRules()];
}
