import { ACTION_TYPES, parseAction, type Action, type ActionParams, type ActionType } from "./actions.ts";
import { AuditLog } from "./audit.ts";
import { Ledger, type JournalEntryInput, type PostingLine } from "./ledger.ts";
import { combineVerdict, freezePolicy, parsePolicy, RULE_LABELS, type Policy, type RuleResult, type Verdict } from "./policy.ts";
import {
  bankKey,
  HUMAN_ROLES,
  type Actor,
  type BankAccount,
  type Contract,
  type Flag,
  type FlagCode,
  type GoodsReceipt,
  type HumanRole,
  type Invoice,
  type Item,
  type Payment,
  type PriceObservation,
  type PurchaseOrder,
  type Quote,
  type Ref,
  type Requisition,
  type Role,
  type Time,
  type Vendor,
  type Verification,
} from "./types.ts";
import { formatCents, IdGen, median, robustLogZ, type Cents } from "./util.ts";

const DAY_MS = 86_400_000;

/** An operational alternative the world can offer in an escalation (no money moves). */
export interface Lever {
  id: string;
  label: string;
  detail: string;
  appliesToSkus?: string[];
}

export interface EngineConfig {
  policy: Policy;
  actors: Actor[];
  vendors: Vendor[];
  items: Item[];
  contracts: Contract[];
  priceHistory: PriceObservation[];
  openingCash: Cents;
  /** Average spending per day, used for the runway rule. */
  burnPerDayCents: Cents;
  startTime: Time;
  /** One-way message latency to the remote authority. */
  remoteLatencyMs: number;
  levers?: Lever[];
  /**
   * When true, every submit must carry the credential issued for its actor
   * (see issueCredential). Hosts that let LLMs or remote clients drive actors turn this on,
   * so a caller holding one role's credential can't act as another.
   */
  requireCredentials?: boolean;
}

export interface ProposalInput {
  actorId: string;
  credential?: string;
  type: string;
  params: unknown;
  rationale?: string;
  source?: "rules" | "llm" | "human" | "console" | "fuzz";
}

export interface Proposal {
  id: string;
  actorId: string;
  role: Role;
  action: Action;
  rationale?: string;
  source: NonNullable<ProposalInput["source"]>;
  at: Time;
}

export interface Decision {
  id: string;
  proposalId: string;
  actorId: string;
  role: Role;
  actionType: string;
  verdict: Verdict;
  rules: RuleResult[];
  summary: string;
  at: Time;
}

export interface EscalationOption {
  id: string;
  label: string;
  detail: string;
  /** Actions executed (each re-checked by policy) as the deciding authority. */
  actions: { type: ActionType; params: unknown }[];
  leverId?: string;
  costCents: Cents;
  withinAuthority: boolean;
  recommended?: boolean;
}

export interface Escalation {
  id: string;
  subject: Ref;
  to: HumanRole;
  reason: string;
  flags: FlagCode[];
  options: EscalationOption[];
  createdAt: Time;
  deliverAt: Time;
  /** Deadline the decision is needed by (e.g. order-by time), if any. */
  decideBy?: Time;
  status: "in_transit" | "awaiting_decision" | "decided" | "superseded";
  decision?: { optionId: string; by: string; at: Time };
  /** Non-final choices made so far (wait, operational levers). */
  history?: { optionId: string; by: string; at: Time }[];
  /** Message drafted for the human (by an LLM agent or a template). */
  message?: string;
  createdBy: string;
}

export interface Prevented {
  subject: Ref;
  code: FlagCode | "fraud_confirmed";
  amount: Cents;
  detail: string;
  at: Time;
}

export interface Document {
  id: string;
  kind: string;
  from: string;
  text: string;
  receivedAt: Time;
}

export interface EngineEvent {
  seq: number;
  at: Time;
  type: string;
  data: Record<string, unknown>;
}

export interface SubmitResult {
  proposal?: Proposal;
  decision: Decision;
  executed: boolean;
  created?: Ref;
  error?: string;
}

export interface MatchResult {
  ok: boolean;
  payable: Cents;
  matchedValue: Cents;
  prepaidApplied: Cents;
  grniRelief: Cents;
  lines: { sku: string; billedQty: number; payQty: number; billedPrice: Cents; poPrice: Cents }[];
  rules: RuleResult[];
}

interface ScheduledInbound {
  at: Time;
  input: ProposalInput;
}

const ENGINE_SECRET = Symbol("engine-ledger-secret");

/** Actions whose executor implements hold/escalate side effects (flags, escalations) without moving money. */
const BLOCKED_SIDE_EFFECTS = new Set<string>(["submit_invoice", "approve_requisition", "approve_invoice", "confirm_funds", "schedule_payment"]);

export class Engine {
  #policy: Policy;
  now: Time;
  remoteLatencyMs: number;
  readonly burnPerDayCents: Cents;

  readonly actors = new Map<string, Actor>();
  readonly vendors = new Map<string, Vendor>();
  readonly items = new Map<string, Item>();
  readonly contracts: Contract[];
  readonly priceHistory: PriceObservation[];
  levers: Lever[];

  readonly requisitions = new Map<string, Requisition>();
  readonly quotes = new Map<string, Quote & { status: "open" | "held" | "used" | "rejected"; flags: FlagCode[] }>();
  readonly pos = new Map<string, PurchaseOrder>();
  readonly receipts = new Map<string, GoodsReceipt>();
  readonly invoices = new Map<string, Invoice & { flags: FlagCode[]; submittedBy?: string; voidedAsFraud?: boolean; matchedQty?: Record<string, number> }>();
  readonly payments = new Map<string, Payment>();
  readonly verifications = new Map<string, Verification>();
  readonly escalations = new Map<string, Escalation>();
  readonly documents = new Map<string, Document>();
  readonly flags: Flag[] = [];
  readonly prevented: Prevented[] = [];
  readonly proposals: Proposal[] = [];
  readonly decisions: Decision[] = [];

  readonly ledger = new Ledger(ENGINE_SECRET);
  readonly audit = new AuditLog();
  private readonly ids = new IdGen();
  private readonly events: EngineEvent[] = [];
  private readonly listeners: ((e: EngineEvent) => void)[] = [];
  private inbound: ScheduledInbound[] = [];
  private eventSeq = 0;
  private depth = 0;
  private flushing = false;
  private pendingEvents: EngineEvent[] = [];
  readonly #requireCredentials: boolean;
  readonly #credentials = new Map<string, string>();
  #credSeq = 0;
  /** Origin of each record, so a ledger entry can be traced back to its proposal and document. */
  private readonly origin = new Map<string, { proposalId: string; decisionId: string; sourceRef?: string }>();

  constructor(cfg: EngineConfig) {
    this.#policy = freezePolicy(parsePolicy(cfg.policy));
    this.#requireCredentials = cfg.requireCredentials ?? false;
    this.now = cfg.startTime;
    this.remoteLatencyMs = cfg.remoteLatencyMs;
    this.burnPerDayCents = cfg.burnPerDayCents;
    for (const a of cfg.actors) this.actors.set(a.id, Object.freeze({ ...a }));
    for (const v of cfg.vendors) this.vendors.set(v.id, { ...v, bank: { ...v.bank } });
    for (const i of cfg.items) this.items.set(i.sku, i);
    this.contracts = cfg.contracts.map((c) => ({ ...c }));
    this.priceHistory = cfg.priceHistory.map((p) => ({ ...p }));
    this.levers = cfg.levers ?? [];
    if (!this.actors.has("system")) this.actors.set("system", { id: "system", role: "system", displayName: "System" });

    if (cfg.openingCash > 0) {
      const decisionId = this.ids.next("DEC");
      const opening: Decision = { id: decisionId, proposalId: "opening", actorId: "system", role: "system", actionType: "opening_balance", verdict: "allow", rules: [], summary: `Opening balance ${formatCents(cfg.openingCash)}`, at: this.now };
      this.decisions.push(opening);
      this.audit.append(this.now, "decision", "system", opening.summary, opening);
      this.postEntry(
        {
          memo: "Opening cash balance",
          lines: [
            { account: "cash", debit: cfg.openingCash, credit: 0 },
            { account: "funding", debit: 0, credit: cfg.openingCash },
          ],
          refs: [{ kind: "proposal", id: "opening" }],
          proposalId: "opening",
          decisionId,
          actorId: "system",
          approvers: [],
          rules: [],
        },
      );
    }
  }

  get policy(): Policy {
    return this.#policy;
  }

  /** Issue the one credential for an actor. Can be called once per actor; the host hands it to that actor's session. */
  issueCredential(actorId: string): string {
    if (!this.actors.has(actorId)) throw new Error(`unknown actor ${actorId}`);
    if (this.#credentials.has(actorId)) throw new Error(`credential for ${actorId} already issued`);
    const c = `cred-${++this.#credSeq}-${Math.random().toString(36).slice(2)}${Math.random().toString(36).slice(2)}`;
    this.#credentials.set(actorId, c);
    return c;
  }

  // ---------------------------------------------------------------- events

  subscribe(fn: (e: EngineEvent) => void): () => void {
    this.listeners.push(fn);
    return () => {
      const i = this.listeners.indexOf(fn);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /**
   * Events are delivered only after the current submit has fully executed, so a listener
   * can never act between a decision and its execution (no re-entrancy). Payloads are copies.
   */
  private emit(type: string, data: Record<string, unknown>): void {
    const e: EngineEvent = { seq: ++this.eventSeq, at: this.now, type, data: structuredClone(data) };
    this.events.push(e);
    this.pendingEvents.push(e);
    if (this.depth === 0) this.flush();
  }

  private flush(): void {
    if (this.flushing) return;
    this.flushing = true;
    try {
      while (this.pendingEvents.length) {
        const e = this.pendingEvents.shift()!;
        for (const l of [...this.listeners]) {
          try {
            l(e);
          } catch (err) {
            // A faulty listener must not affect execution that already happened.
            this.audit.append(this.now, "message", "system", `listener error on ${e.type}: ${(err as Error).message}`, { seq: e.seq });
          }
        }
      }
    } finally {
      this.flushing = false;
    }
  }

  eventsSince(seq: number): EngineEvent[] {
    return this.events.filter((e) => e.seq > seq);
  }

  // ---------------------------------------------------------------- time

  /** Move the clock forward, delivering escalations and inbound messages that are due. */
  advanceTo(t: Time): SubmitResult[] {
    if (t < this.now) return [];
    this.depth++;
    try {
      return this.advanceInner(t);
    } finally {
      this.depth--;
      if (this.depth === 0) this.flush();
    }
  }

  private advanceInner(t: Time): SubmitResult[] {
    const results: SubmitResult[] = [];
    for (;;) {
      const nextEsc = [...this.escalations.values()].filter((e) => e.status === "in_transit" && e.deliverAt <= t).sort((a, b) => a.deliverAt - b.deliverAt)[0];
      const nextIn = this.inbound.filter((m) => m.at <= t).sort((a, b) => a.at - b.at)[0];
      if (!nextEsc && !nextIn) break;
      if (nextEsc && (!nextIn || nextEsc.deliverAt <= nextIn.at)) {
        this.now = Math.max(this.now, nextEsc.deliverAt);
        nextEsc.status = "awaiting_decision";
        this.audit.append(this.now, "escalation", "system", `${nextEsc.id} delivered to ${this.humanName(nextEsc.to)}`, { escalationId: nextEsc.id });
        this.emit("escalation_delivered", { escalation: nextEsc });
      } else if (nextIn) {
        this.now = Math.max(this.now, nextIn.at);
        this.inbound = this.inbound.filter((m) => m !== nextIn);
        results.push(this.submit(nextIn.input));
      }
    }
    this.now = t;
    this.emit("clock", { now: t });
    return results;
  }

  /** Queue a message from a remote party; it is processed when the clock reaches `at`. */
  scheduleInbound(input: ProposalInput, at: Time): void {
    this.inbound.push({ at, input });
  }

  pendingInbound(): readonly ScheduledInbound[] {
    return this.inbound;
  }

  /** Worlds refresh lever descriptions as conditions change (e.g. power saved at current dust levels). */
  setLevers(levers: Lever[]): void {
    this.levers = levers.map((l) => ({ ...l }));
  }

  setRemoteLatency(ms: number): void {
    this.remoteLatencyMs = ms;
  }

  /** Only the remote authority (policy owner) may change policy; the change is validated and audited. */
  setPolicy(input: unknown, actorId: string, credential?: string): Policy {
    const actor = this.actors.get(actorId);
    if (!actor || actor.role !== "remote_authority") throw new Error(`policy can only be changed by the remote authority, not "${actorId}"`);
    if (this.#requireCredentials && this.#credentials.get(actorId) !== credential) throw new Error(`policy change not authenticated as "${actorId}"`);
    const next = freezePolicy(parsePolicy(input));
    const prev = this.#policy;
    this.#policy = next;
    this.audit.append(this.now, "policy", actorId, `Policy changed: ${prev.name} v${prev.version} -> ${next.name} v${next.version}`, { prev, next });
    this.emit("policy_changed", { policy: next });
    return next;
  }

  ingestDocument(doc: Omit<Document, "receivedAt"> & { receivedAt?: Time }): Document {
    const d: Document = { ...doc, receivedAt: doc.receivedAt ?? this.now };
    this.documents.set(d.id, d);
    this.audit.append(this.now, "document", d.from, `Document ${d.id} (${d.kind}) from ${d.from}`, d);
    this.emit("document_received", { document: d });
    return d;
  }

  // ---------------------------------------------------------------- submit

  submit(input: ProposalInput): SubmitResult {
    this.depth++;
    try {
      return this.submitInner(input);
    } catch (err) {
      // Never throw at a caller: deny and audit instead.
      const rules = [fail("engine.error", (err as Error).message, "deny")];
      const decision = this.recordDecision(undefined, String(input?.actorId), "system", String(input?.type), rules);
      this.audit.append(this.now, "proposal", String(input?.actorId), `Proposal failed: ${(err as Error).message}`, { type: String(input?.type) });
      return { decision, executed: false, error: (err as Error).message };
    } finally {
      this.depth--;
      if (this.depth === 0) this.flush();
    }
  }

  private submitInner(input: ProposalInput): SubmitResult {
    if (this.#requireCredentials && (!input.credential || this.#credentials.get(input.actorId) !== input.credential)) {
      const rules = [fail("actor.authenticated", `caller is not authenticated as "${input.actorId}"`, "deny")];
      const decision = this.recordDecision(undefined, String(input.actorId), "system", String(input.type), rules);
      this.audit.append(this.now, "proposal", "unauthenticated", `Rejected unauthenticated proposal ${String(input.type)} as ${String(input.actorId)}`, { type: String(input.type) });
      return { decision, executed: false, error: rules[0]!.detail };
    }
    const actor = this.actors.get(input.actorId);
    const source = input.source ?? "rules";
    const parsed = parseAction(input.type, input.params);
    if (!actor || !parsed.ok) {
      const rules: RuleResult[] = [];
      if (!actor) rules.push(fail("actor.known", `unknown actor "${input.actorId}"`, "deny"));
      if (!parsed.ok) rules.push(fail("schema.valid", parsed.error, "deny"));
      const decision = this.recordDecision(undefined, input.actorId, actor?.role ?? "system", input.type, rules);
      this.audit.append(this.now, "proposal", input.actorId, `Rejected malformed proposal ${input.type}`, { type: String(input.type), actorId: String(input.actorId), params: input.params, rules });
      return { decision, executed: false, error: rules.map((r) => r.detail).join("; ") };
    }

    const proposal: Proposal = {
      id: this.ids.next("PRP"),
      actorId: actor.id,
      role: actor.role,
      action: parsed.action,
      rationale: input.rationale,
      source,
      at: this.now,
    };
    this.proposals.push(proposal);
    this.audit.append(this.now, "proposal", actor.id, `${actor.displayName} proposes ${proposal.action.type}`, proposal);
    this.emit("proposal", { proposal });

    let rules: RuleResult[];
    try {
      rules = this.evaluate(proposal);
    } catch (err) {
      rules = [fail("state.valid", (err as Error).message, "deny")];
    }
    const decision = this.recordDecision(proposal, actor.id, actor.role, proposal.action.type, rules);
    if (decision.verdict === "deny") return { proposal, decision, executed: false };
    // Only `allow` executes, except actions whose executor records the hold/escalation itself.
    if (decision.verdict !== "allow" && !BLOCKED_SIDE_EFFECTS.has(proposal.action.type)) return { proposal, decision, executed: false };

    const created = this.execute(proposal, decision);
    return { proposal, decision, executed: true, created };
  }

  private recordDecision(proposal: Proposal | undefined, actorId: string, role: Role, actionType: string, rules: RuleResult[]): Decision {
    const verdict = combineVerdict(rules);
    const failed = rules.filter((r) => !r.ok);
    const summary =
      verdict === "allow"
        ? `${actionType} allowed (${rules.length} checks passed)`
        : `${actionType} ${verdict}: ${failed.map((r) => r.detail).join("; ")}`;
    const decision: Decision = {
      id: this.ids.next("DEC"),
      proposalId: proposal?.id ?? "none",
      actorId,
      role,
      actionType,
      verdict,
      rules,
      summary,
      at: this.now,
    };
    this.decisions.push(decision);
    this.audit.append(this.now, "decision", "policy", summary, decision);
    this.emit("decision", { decision });
    return decision;
  }

  // ---------------------------------------------------------------- evaluation (pure)

  /** Every check for a proposal. Does not change state. */
  evaluate(p: Proposal): RuleResult[] {
    const allowed = this.#policy.permissions[p.role] ?? [];
    const rbac = allowed.includes(p.action.type)
      ? pass("rbac.permitted", `${p.role} may ${p.action.type}`)
      : fail("rbac.permitted", `role ${p.role} is not allowed to ${p.action.type}`, "deny");
    // Stop at RBAC: a forbidden action is never evaluated further, so it can't have side effects.
    if (!rbac.ok) return [rbac];
    return [rbac, ...this.actionRules(p)];
  }

  private actionRules(p: Proposal): RuleResult[] {
    const a = p.action;
    switch (a.type) {
      case "create_requisition": {
        const r: RuleResult[] = [];
        r.push(this.items.has(a.params.sku) ? pass("state.valid", `item ${a.params.sku} exists`) : fail("state.valid", `unknown item ${a.params.sku}`, "deny"));
        return r;
      }
      case "cancel_requisition": {
        const req = this.requisitions.get(a.params.requisitionId);
        if (!req) return [fail("state.valid", `no requisition ${a.params.requisitionId}`, "deny")];
        return [
          req.requestedBy === p.actorId ? pass("state.valid", "own request") : fail("state.valid", "only the requester can cancel", "deny"),
          ["open", "escalated"].includes(req.status) ? pass("state.valid", `status ${req.status}`) : fail("state.valid", `cannot cancel a ${req.status} request`, "deny"),
          this.escalationRoutingRule(p, { kind: "requisition", id: req.id }),
        ];
      }
      case "record_receipt":
        return this.receiptRules(p, a.params);
      case "record_quote": {
        const r: RuleResult[] = [];
        r.push(this.vendors.has(a.params.vendorId) ? pass("state.valid", "known vendor") : fail("state.valid", `unknown vendor ${a.params.vendorId}`, "deny"));
        r.push(this.items.has(a.params.sku) ? pass("state.valid", "known item") : fail("state.valid", `unknown item ${a.params.sku}`, "deny"));
        if (a.params.requisitionId && !this.requisitions.has(a.params.requisitionId)) r.push(fail("state.valid", `no requisition ${a.params.requisitionId}`, "deny"));
        return r;
      }
      case "record_invoice": {
        const r: RuleResult[] = [];
        r.push(this.vendors.has(a.params.vendorId) ? pass("state.valid", "known vendor") : fail("state.valid", `unknown vendor ${a.params.vendorId}`, "deny"));
        for (const l of a.params.lines) if (!this.items.has(l.sku)) r.push(fail("state.valid", `unknown item ${l.sku}`, "deny"));
        if (new Set(a.params.lines.map((l) => l.sku)).size !== a.params.lines.length) r.push(fail("state.valid", "an item appears on more than one line; one line per item", "deny"));
        return r;
      }
      case "submit_invoice": {
        const inv = this.invoices.get(a.params.invoiceId);
        if (!inv) return [fail("state.valid", `no invoice ${a.params.invoiceId}`, "deny")];
        // "submitted" can be re-matched (e.g. goods arrived after the first submission).
        if (inv.status !== "received" && inv.status !== "held" && inv.status !== "submitted") return [fail("state.valid", `invoice is ${inv.status}`, "deny")];
        const m = this.computeMatch(inv);
        const r = [...m.rules, ...this.invoiceDocRules(inv), this.prepayInFlightRule(inv)];
        r.push(
          a.params.amount === m.payable
            ? pass("match.amount_within_payable", `amount ${formatCents(a.params.amount)} equals matched payable`)
            : fail("match.amount_within_payable", `proposed ${formatCents(a.params.amount)} but matched payable is ${formatCents(m.payable)}`, "deny"),
        );
        return r;
      }
      case "raise_flag":
        return [pass("state.valid", "flags are informational")];
      case "confirm_funds": {
        const req = this.requisitions.get(a.params.requisitionId);
        if (!req) return [fail("state.valid", `no requisition ${a.params.requisitionId}`, "deny")];
        const est = req.qty * this.marketPrice(req.sku);
        return [this.runwayRule(est, `estimated ${formatCents(est)}`)];
      }
      case "schedule_payment":
        return this.schedulePaymentRules(p, a.params);
      case "execute_payment":
        return this.executePaymentRules(p, a.params);
      case "approve_requisition":
        return this.approveRequisitionRules(p, a.params);
      case "reject_requisition": {
        const req = this.requisitions.get(a.params.requisitionId);
        if (!req) return [fail("state.valid", `no requisition ${a.params.requisitionId}`, "deny")];
        return [
          ["open", "escalated"].includes(req.status) ? pass("state.valid", `status ${req.status}`) : fail("state.valid", `request is ${req.status}`, "deny"),
          this.escalationRoutingRule(p, { kind: "requisition", id: req.id }),
        ];
      }
      case "approve_invoice":
        return this.approveInvoiceRules(p, a.params);
      case "reject_invoice": {
        const inv = this.invoices.get(a.params.invoiceId);
        if (!inv) return [fail("state.valid", `no invoice ${a.params.invoiceId}`, "deny")];
        // Once approved (AP credited) an invoice is settled or reversed with a credit note, never just rejected.
        return [
          ["received", "submitted", "held"].includes(inv.status) ? pass("state.valid", `status ${inv.status}`) : fail("state.valid", `invoice is ${inv.status}; use a credit note`, "deny"),
          this.escalationRoutingRule(p, { kind: "invoice", id: inv.id }),
        ];
      }
      case "reject_quote": {
        const q = this.quotes.get(a.params.quoteId);
        if (!q) return [fail("state.valid", `no quote ${a.params.quoteId}`, "deny")];
        return [
          q.status !== "used" && q.status !== "rejected" ? pass("state.valid", `quote is ${q.status}`) : fail("state.valid", `quote is ${q.status}`, "deny"),
          ...(q.requisitionId ? [this.escalationRoutingRule(p, { kind: "requisition", id: q.requisitionId })] : []),
        ];
      }
      case "hold_vendor":
      case "block_vendor":
        return [this.vendors.has(a.params.vendorId) ? pass("state.valid", "known vendor") : fail("state.valid", `unknown vendor ${a.params.vendorId}`, "deny")];
      case "release_vendor": {
        const v = this.vendors.get(a.params.vendorId);
        if (!v) return [fail("state.valid", `unknown vendor ${a.params.vendorId}`, "deny")];
        return [v.status === "hold" ? pass("state.valid", "vendor is on hold") : fail("state.valid", `vendor is ${v.status}; only a hold can be released`, "deny")];
      }
      case "request_verification": {
        const v = this.vendors.get(a.params.vendorId);
        if (!v) return [fail("state.valid", `unknown vendor ${a.params.vendorId}`, "deny")];
        const claimed = this.bankOf(a.params.subject);
        if (!claimed) return [fail("state.valid", "subject has no bank details", "deny")];
        if (this.vendorOf(a.params.subject) !== v.id) return [fail("state.valid", `${a.params.subject.id} was not sent by ${v.id}`, "deny")];
        const open = [...this.verifications.values()].some((x) => x.status === "pending" && x.vendorId === v.id && bankKey(x.claimedBank) === bankKey(claimed));
        return [
          bankKey(claimed) !== bankKey(v.bank) ? pass("state.valid", "bank details differ from master") : fail("state.valid", "bank details already match the master", "deny"),
          open ? fail("state.valid", "verification already pending", "deny") : pass("state.valid", "no pending verification"),
        ];
      }
      case "escalate": {
        if (!this.refExists(a.params.subject)) return [fail("state.valid", `no ${a.params.subject.kind} ${a.params.subject.id}`, "deny")];
        const open = this.openEscalationFor(a.params.subject);
        return [open ? fail("state.valid", `already escalated as ${open.id}`, "deny") : pass("state.valid", "not yet escalated")];
      }
      case "decide":
        return this.decideRules(p, a.params);
      case "answer_verification": {
        const v = this.verifications.get(a.params.verificationId);
        if (!v) return [fail("state.valid", `no verification ${a.params.verificationId}`, "deny")];
        return [
          v.status === "pending" ? pass("state.valid", "pending") : fail("state.valid", `already ${v.status}`, "deny"),
          this.now >= v.sentAt + 2 * this.remoteLatencyMs ? pass("verification.arrived", "a reply could have made the round trip") : fail("verification.arrived", "too early: a reply cannot have made the round trip yet", "deny"),
        ];
      }
    }
  }

  private receiptRules(p: Proposal, params: ActionParams<"record_receipt">): RuleResult[] {
    const po = this.pos.get(params.poId);
    if (!po) return [fail("state.valid", `no purchase order ${params.poId}`, "deny")];
    const r: RuleResult[] = [];
    r.push(po.status === "open" || po.status === "partially_received" ? pass("state.valid", `PO is ${po.status}`) : fail("state.valid", `PO is ${po.status}`, "deny"));
    if (new Set(params.lines.map((l) => l.sku)).size !== params.lines.length) r.push(fail("state.valid", "an item appears on more than one receipt line", "deny"));
    for (const l of params.lines) {
      if (!po.lines.some((pl) => pl.sku === l.sku)) r.push(fail("state.valid", `${l.sku} is not on ${po.id}`, "deny"));
      if (l.qtyRejected > l.qtyReceived) r.push(fail("state.valid", "rejected more than received", "deny"));
    }
    const req = this.requisitions.get(po.requisitionId);
    if (this.#policy.sod.requesterCannotReceive && req) {
      r.push(req.requestedBy !== p.actorId ? pass("sod.requester_not_receiver", "receiver is not the requester") : fail("sod.requester_not_receiver", "requester cannot confirm receipt of their own order", "deny"));
    }
    return r;
  }

  /** Checks that depend on the invoice document itself (vendor, bank, duplicates, contract). */
  private invoiceDocRules(inv: Invoice): RuleResult[] {
    const r: RuleResult[] = [];
    const vendor = this.vendors.get(inv.vendorId);
    if (!vendor) return [fail("state.valid", "unknown vendor", "deny")];
    r.push(this.vendorActiveRule(vendor));
    r.push(
      bankKey(inv.bank) === bankKey(vendor.bank)
        ? pass("vendor.bank_matches_master", "bank details match vendor master")
        : fail("vendor.bank_matches_master", `bank on invoice (${maskAccount(inv.bank)}) differs from verified master (${maskAccount(vendor.bank)})`, this.#policy.vendorBankChange.action === "block" ? "deny" : "hold"),
    );
    const all = [...this.invoices.values()].filter((o) => o.id !== inv.id && o.vendorId === inv.vendorId);
    const others = all.filter((o) => o.status !== "rejected");
    // A number stays used even if that invoice was rejected, unless it was voided as a fraudulent copy.
    const sameNo = all.filter((o) => !o.voidedAsFraud).find((o) => o.vendorInvoiceNo.trim().toLowerCase() === inv.vendorInvoiceNo.trim().toLowerCase());
    r.push(sameNo ? fail("dup.invoice_number", `invoice number ${inv.vendorInvoiceNo} already recorded as ${sameNo.id}`, "deny") : pass("dup.invoice_number", "invoice number is new"));
    const windowMs = this.#policy.duplicates.windowDays * DAY_MS;
    const sameAmt = others.find((o) => o.poId === inv.poId && o.total === inv.total && Math.abs(o.issuedAt - inv.issuedAt) <= windowMs);
    r.push(sameAmt ? fail("dup.same_amount", `same amount ${formatCents(inv.total)} on the same order already billed as ${sameAmt.id}`, "deny") : pass("dup.same_amount", "no identical invoice"));
    for (const l of inv.lines) {
      const c = this.contractFor(inv.vendorId, l.sku, inv.issuedAt);
      if (c) {
        const cap = c.unitPrice * (1 + this.#policy.match.priceTolerancePct / 100);
        r.push(l.unitPrice <= cap ? pass("contract.price", `${l.sku} within contract ${c.id}`) : fail("contract.price", `${l.sku} billed ${formatCents(l.unitPrice)} vs contract ${formatCents(c.unitPrice)}`, "hold"));
      }
    }
    return r;
  }

  /** Three-way match: invoice vs purchase order vs goods receipts. */
  computeMatch(inv: Invoice): MatchResult {
    const rules: RuleResult[] = [];
    const empty: MatchResult = { ok: false, payable: 0, matchedValue: 0, prepaidApplied: 0, grniRelief: 0, lines: [], rules };
    const po = inv.poId ? this.pos.get(inv.poId) : undefined;
    if (!po) {
      rules.push(fail("match.po_exists", inv.poId ? `PO ${inv.poId} not found` : "invoice has no PO reference", "hold"));
      return empty;
    }
    rules.push(pass("match.po_exists", `references ${po.id}`));
    rules.push(po.vendorId === inv.vendorId ? pass("match.vendor_matches_po", "same vendor") : fail("match.vendor_matches_po", `PO is with ${po.vendorId}, invoice from ${inv.vendorId}`, "deny"));

    const accepted = new Map<string, number>();
    const poReceipts = [...this.receipts.values()].filter((g) => g.poId === po.id);
    for (const g of poReceipts) for (const l of g.lines) accepted.set(l.sku, (accepted.get(l.sku) ?? 0) + l.qtyReceived - l.qtyRejected);
    const invoiced = new Map<string, number>();
    for (const o of this.invoices.values()) {
      if (o.id === inv.id || o.poId !== po.id || !["approved", "paid"].includes(o.status)) continue;
      // Count what was actually matched (paid for), not what was billed, so a short-paid
      // invoice doesn't block billing for goods that arrive later.
      for (const l of o.lines) invoiced.set(l.sku, (invoiced.get(l.sku) ?? 0) + (o.matchedQty?.[l.sku] ?? l.qty));
    }
    if (po.terms === "on_receipt" || poReceipts.length > 0) {
      rules.push(poReceipts.length > 0 ? pass("match.receipt_exists", `${poReceipts.length} receipt(s)`) : fail("match.receipt_exists", "nothing received yet", "hold"));
    }

    const tol = this.#policy.match.priceTolerancePct / 100;
    const lines: MatchResult["lines"] = [];
    let matchedValue = 0;
    let grniRelief = 0;
    // One line per SKU, so repeated lines can't each claim the full received quantity.
    const bySku = new Map<string, { sku: string; qty: number; value: number }>();
    for (const l of inv.lines) {
      const agg = bySku.get(l.sku) ?? { sku: l.sku, qty: 0, value: 0 };
      agg.qty += l.qty;
      agg.value += l.qty * l.unitPrice;
      bySku.set(l.sku, agg);
    }
    const merged = [...bySku.values()].map((x) => ({ sku: x.sku, qty: x.qty, unitPrice: x.qty ? Math.round(x.value / x.qty) : 0 }));
    for (const l of merged) {
      const pl = po.lines.find((x) => x.sku === l.sku);
      if (!pl) {
        rules.push(fail("match.po_exists", `${l.sku} is not on ${po.id}`, "hold"));
        continue;
      }
      const receivable = Math.max(0, Math.min(accepted.get(l.sku) ?? 0, pl.qty) - (invoiced.get(l.sku) ?? 0));
      let payQty = l.qty;
      if (l.qty > receivable) {
        if (this.#policy.match.payReceivedQtyOnly) {
          payQty = receivable;
          rules.push(pass("match.qty_within_receipt", `${l.sku}: billed ${l.qty}, received ${receivable}; paying for ${receivable}`));
        } else {
          rules.push(fail("match.qty_within_receipt", `${l.sku}: billed ${l.qty} but only ${receivable} received`, "hold"));
        }
      } else {
        rules.push(pass("match.qty_within_receipt", `${l.sku}: billed ${l.qty} of ${receivable} received`));
      }
      const cap = Math.round(pl.unitPrice * (1 + tol));
      rules.push(
        l.unitPrice <= cap
          ? pass("match.price_within_tolerance", `${l.sku}: ${formatCents(l.unitPrice)} vs PO ${formatCents(pl.unitPrice)}`)
          : fail("match.price_within_tolerance", `${l.sku}: billed ${formatCents(l.unitPrice)} vs PO ${formatCents(pl.unitPrice)} (over ${this.#policy.match.priceTolerancePct}% tolerance)`, "hold"),
      );
      matchedValue += payQty * l.unitPrice;
      grniRelief += payQty * pl.unitPrice;
      lines.push({ sku: l.sku, billedQty: l.qty, payQty, billedPrice: l.unitPrice, poPrice: pl.unitPrice });
    }
    const prepaidRemaining = this.prepaidBalance(po.id);
    const prepaidApplied = Math.min(prepaidRemaining, matchedValue);
    const payable = matchedValue - prepaidApplied;
    const ok = rules.every((r) => r.ok);
    return { ok, payable, matchedValue, prepaidApplied, grniRelief, lines, rules };
  }

  private approveInvoiceRules(p: Proposal, params: ActionParams<"approve_invoice">): RuleResult[] {
    const inv = this.invoices.get(params.invoiceId);
    if (!inv) return [fail("state.valid", `no invoice ${params.invoiceId}`, "deny")];
    if (inv.status !== "submitted") return [fail("state.valid", `invoice is ${inv.status}, not submitted`, "deny")];
    const m = this.computeMatch(inv);
    const r = [...m.rules, ...this.invoiceDocRules(inv), this.prepayInFlightRule(inv), this.escalationRoutingRule(p, { kind: "invoice", id: inv.id })];
    const amount = inv.approvedAmount ?? 0;
    r.push(amount === m.payable ? pass("match.amount_within_payable", "submitted amount still matches") : fail("match.amount_within_payable", `submitted ${formatCents(amount)} but matched payable is now ${formatCents(m.payable)}`, "deny"));
    if (this.#policy.sod.submitterCannotApprove) {
      r.push(inv.submittedBy !== p.actorId ? pass("sod.submitter_not_approver", "approver did not submit it") : fail("sod.submitter_not_approver", "you submitted this invoice", "deny"));
    }
    const po = inv.poId ? this.pos.get(inv.poId) : undefined;
    const req = po ? this.requisitions.get(po.requisitionId) : undefined;
    if (this.#policy.sod.requesterCannotApprove && req) {
      r.push(req.requestedBy !== p.actorId ? pass("sod.requester_not_approver", "approver is not the requester") : fail("sod.requester_not_approver", "you requested this purchase", "deny"));
    }
    r.push(this.limitRule(p.role, amount));
    r.push(this.runwayRule(amount, "invoice", true));
    return r;
  }

  private approveRequisitionRules(p: Proposal, params: ActionParams<"approve_requisition">): RuleResult[] {
    const req = this.requisitions.get(params.requisitionId);
    if (!req) return [fail("state.valid", `no requisition ${params.requisitionId}`, "deny")];
    const q = this.quotes.get(params.quoteId);
    if (!q) return [fail("state.valid", `no quote ${params.quoteId}`, "deny")];
    const r: RuleResult[] = [];
    r.push(["open", "escalated"].includes(req.status) ? pass("state.valid", `request is ${req.status}`) : fail("state.valid", `request is ${req.status}`, "deny"));
    r.push(q.status === "open" || q.status === "held" ? pass("state.valid", `quote is ${q.status}`) : fail("state.valid", `quote is ${q.status}`, "deny"));
    r.push(q.sku === req.sku ? pass("state.valid", "quote is for the requested item") : fail("state.valid", `quote is for ${q.sku}, request is for ${req.sku}`, "deny"));
    r.push(q.validUntil >= this.now ? pass("state.valid", "quote still valid") : fail("state.valid", "quote expired", "deny"));
    r.push(q.requisitionId === req.id ? pass("state.valid", "quote was requested for this purchase") : fail("state.valid", `quote ${q.id} belongs to ${q.requisitionId ?? "no request"}`, "deny"));
    r.push(this.escalationRoutingRule(p, { kind: "requisition", id: req.id }));
    const qty = params.qty ?? req.qty;
    r.push(qty <= req.qty ? pass("state.valid", `qty ${qty} within request`) : fail("state.valid", `qty ${qty} exceeds requested ${req.qty}`, "deny"));
    r.push(qty <= q.qtyAvailable ? pass("state.valid", `supplier has ${q.qtyAvailable}`) : fail("state.valid", `supplier only has ${q.qtyAvailable}`, "deny"));
    r.push(req.fundsConfirmedBy ? pass("treasury.funds_confirmed", "funds confirmed") : fail("treasury.funds_confirmed", "treasury has not confirmed funds", "deny"));
    if (this.#policy.sod.requesterCannotApprove) {
      r.push(req.requestedBy !== p.actorId ? pass("sod.requester_not_approver", "approver is not the requester") : fail("sod.requester_not_approver", "you requested this purchase", "deny"));
    }
    r.push(...this.quoteRules(q));
    const amount = qty * q.unitPrice;
    // Split-order guard: same approver role, vendor and item within the window count together.
    const windowMs = this.#policy.approval.splitWindowDays * DAY_MS;
    const recent = [...this.pos.values()]
      .filter((po) => po.status !== "cancelled" && po.vendorId === q.vendorId && po.lines.some((l) => l.sku === q.sku) && this.now - po.createdAt <= windowMs)
      .filter((po) => po.approvedBy.some((id) => this.actors.get(id)?.role === p.role))
      .reduce((s, po) => s + po.total, 0);
    r.push(this.limitRule(p.role, amount + recent, recent > 0 ? `incl. ${formatCents(recent)} approved for the same vendor and item in the last ${this.#policy.approval.splitWindowDays} days` : undefined));
    r.push(this.runwayRule(amount, `order ${formatCents(amount)}`));
    return r;
  }

  /** Checks on a quote: supplier status, bank details, price history, contract. */
  quoteRules(q: Quote): RuleResult[] {
    const r: RuleResult[] = [];
    const vendor = this.vendors.get(q.vendorId);
    if (!vendor) return [fail("state.valid", "unknown vendor", "deny")];
    r.push(this.vendorActiveRule(vendor));
    r.push(
      bankKey(q.bank) === bankKey(vendor.bank)
        ? pass("vendor.bank_matches_master", "bank details match vendor master")
        : fail("vendor.bank_matches_master", `quote asks payment to ${maskAccount(q.bank)}, master is ${maskAccount(vendor.bank)}`, this.#policy.vendorBankChange.action === "block" ? "deny" : "hold"),
    );
    const pa = this.priceCheck(q.vendorId, q.sku, q.unitPrice);
    const material = (pa.median > 0 ? (q.unitPrice - pa.median) * q.qtyAvailable : 0) >= this.#policy.materialityCents;
    r.push(pa.anomalous && material ? fail("price.anomaly", pa.detail, "escalate") : pass("price.anomaly", pa.detail));
    const c = this.contractFor(q.vendorId, q.sku, this.now);
    if (c) {
      const cap = c.unitPrice * (1 + this.#policy.match.priceTolerancePct / 100);
      r.push(q.unitPrice <= cap ? pass("contract.price", `within contract ${c.id}`) : fail("contract.price", `quote ${formatCents(q.unitPrice)} vs contract ${formatCents(c.unitPrice)}`, "escalate"));
    }
    return r;
  }

  /** Statistical price check against the supplier's history (falls back to all suppliers of the item). */
  priceCheck(vendorId: string, sku: string, unitPrice: Cents): { anomalous: boolean; z: number; ratio: number; median: number; n: number; detail: string } {
    let hist = this.priceHistory.filter((h) => h.vendorId === vendorId && h.sku === sku).map((h) => h.unitPrice);
    let scope = "this supplier";
    if (hist.length < this.#policy.priceAnomaly.minHistory) {
      hist = this.priceHistory.filter((h) => h.sku === sku).map((h) => h.unitPrice);
      scope = "all suppliers";
    }
    if (hist.length < this.#policy.priceAnomaly.minHistory) {
      return { anomalous: false, z: 0, ratio: 1, median: 0, n: hist.length, detail: `not enough history (${hist.length})` };
    }
    const med = median(hist);
    const z = robustLogZ(unitPrice, hist);
    const ratio = unitPrice / med;
    const anomalous = z > this.#policy.priceAnomaly.zThreshold || ratio > this.#policy.priceAnomaly.ratioThreshold;
    const detail = `${formatCents(unitPrice)} is ${ratio.toFixed(2)}x the median ${formatCents(Math.round(med))} of ${hist.length} past prices from ${scope} (z=${z.toFixed(1)})`;
    return { anomalous, z, ratio, median: med, n: hist.length, detail };
  }

  private schedulePaymentRules(p: Proposal, params: ActionParams<"schedule_payment">): RuleResult[] {
    const r: RuleResult[] = [];
    if (!!params.invoiceId === !!params.poId) return [fail("state.valid", "give exactly one of invoiceId or poId", "deny")];
    let vendorId: string;
    let remaining: Cents;
    let approvers: string[];
    let po: PurchaseOrder | undefined;
    if (params.invoiceId) {
      const inv = this.invoices.get(params.invoiceId);
      if (!inv) return [fail("state.valid", `no invoice ${params.invoiceId}`, "deny")];
      r.push(inv.status === "approved" ? pass("payment.invoice_approved", "invoice approved") : fail("payment.invoice_approved", `invoice is ${inv.status}`, "deny"));
      vendorId = inv.vendorId;
      remaining = (inv.approvedAmount ?? 0) - this.paidOrScheduled({ invoiceId: inv.id });
      approvers = this.approversOf({ kind: "invoice", id: inv.id });
      po = inv.poId ? this.pos.get(inv.poId) : undefined;
    } else {
      po = this.pos.get(params.poId as string);
      if (!po) return [fail("state.valid", `no PO ${params.poId}`, "deny")];
      r.push(po.terms === "prepay" ? pass("payment.invoice_approved", "prepaid order approved") : fail("payment.invoice_approved", "order is not on prepayment terms; pay against an approved invoice", "deny"));
      r.push(po.status !== "cancelled" ? pass("state.valid", `PO is ${po.status}`) : fail("state.valid", "PO cancelled", "deny"));
      vendorId = po.vendorId;
      remaining = po.total - this.paidOrScheduled({ poId: po.id });
      approvers = po.approvedBy;
    }
    r.push(params.amount > 0 && params.amount <= remaining ? pass("payment.amount_within_approved", `${formatCents(params.amount)} of ${formatCents(remaining)} remaining`) : fail("payment.amount_within_approved", `${formatCents(params.amount)} exceeds remaining approved ${formatCents(remaining)}`, "deny"));
    if (po) {
      const paid = this.paidAgainstPo(po.id);
      // Invoice payments may use the match's price tolerance; prepayments never exceed the order total.
      const cap = params.invoiceId ? Math.round(po.total * (1 + this.#policy.match.priceTolerancePct / 100)) : po.total;
      r.push(paid + params.amount <= cap ? pass("payment.po_cap", `${formatCents(paid + params.amount)} of order cap ${formatCents(cap)}`) : fail("payment.po_cap", `would bring payments on ${po.id} to ${formatCents(paid + params.amount)}, over the order cap ${formatCents(cap)}`, "deny"));
    }
    const vendor = this.vendors.get(vendorId);
    if (vendor) r.push(this.vendorActiveRule(vendor, "deny"));
    if (this.#policy.sod.approverCannotPay) {
      r.push(!approvers.includes(p.actorId) ? pass("sod.approver_not_payer", "payer did not approve") : fail("sod.approver_not_payer", "you approved this; someone else must pay", "deny"));
    }
    r.push(this.runwayRule(params.amount, "payment", true));
    return r;
  }

  private executePaymentRules(p: Proposal, params: ActionParams<"execute_payment">): RuleResult[] {
    const pay = this.payments.get(params.paymentId);
    if (!pay) return [fail("state.valid", `no payment ${params.paymentId}`, "deny")];
    const r: RuleResult[] = [];
    r.push(pay.status === "scheduled" ? pass("state.valid", "payment scheduled") : fail("state.valid", `payment is ${pay.status}`, "deny"));
    const vendor = this.vendors.get(pay.vendorId);
    if (!vendor) return [fail("state.valid", "unknown vendor", "deny")];
    r.push(this.vendorActiveRule(vendor, "deny"));
    r.push(bankKey(pay.bank) === bankKey(vendor.bank) ? pass("payment.to_master_bank", `to verified account ${maskAccount(vendor.bank)}`) : fail("payment.to_master_bank", "payment account differs from the verified master", "deny"));
    if (this.#policy.sod.approverCannotPay) {
      r.push(!pay.approvedBy.includes(p.actorId) ? pass("sod.approver_not_payer", "payer did not approve") : fail("sod.approver_not_payer", "you approved this; someone else must pay", "deny"));
    }
    const cash = this.ledger.balance("cash");
    r.push(cash >= pay.amount ? pass("treasury.cash_available", `cash ${formatCents(cash)}`) : fail("treasury.cash_available", `cash ${formatCents(cash)} below ${formatCents(pay.amount)}`, "deny"));
    if (pay.invoiceId) {
      const inv = this.invoices.get(pay.invoiceId);
      r.push(inv?.status === "approved" ? pass("payment.invoice_approved", "invoice approved") : fail("payment.invoice_approved", `invoice is ${inv?.status}`, "deny"));
    }
    return r;
  }

  private decideRules(p: Proposal, params: ActionParams<"decide">): RuleResult[] {
    const esc = this.escalations.get(params.escalationId);
    if (!esc) return [fail("state.valid", `no escalation ${params.escalationId}`, "deny")];
    const r: RuleResult[] = [];
    r.push(esc.to === p.role ? pass("escalation.authority", `escalated to ${esc.to}`) : fail("escalation.authority", `escalated to ${esc.to}, not ${p.role}`, "deny"));
    r.push(esc.status === "awaiting_decision" ? pass("escalation.delivered", "awaiting decision") : fail("escalation.delivered", `escalation is ${esc.status}`, "deny"));
    const opt = esc.options.find((o) => o.id === params.optionId);
    r.push(opt ? pass("state.valid", `option ${opt.label}`) : fail("state.valid", `no option ${params.optionId}`, "deny"));
    const lastChoice = esc.history?.at(-1)?.optionId;
    if (opt && lastChoice === opt.id) r.push(fail("escalation.repeat", `"${opt.label}" was already chosen; pick a different option`, "deny"));
    if (opt) {
      // Each underlying action must itself pass policy for this human authority.
      for (const sub of opt.actions) {
        const parsed = parseAction(sub.type, sub.params);
        if (!parsed.ok) {
          r.push(fail("state.valid", parsed.error, "deny"));
          continue;
        }
        const subRules = this.evaluate({ ...p, action: parsed.action });
        for (const s of subRules) if (!s.ok) r.push({ ...s, detail: `${sub.type}: ${s.detail}` });
      }
    }
    return r;
  }

  private limitRule(role: Role, amount: Cents, note?: string): RuleResult {
    const limit = this.limitFor(role);
    const n = note ? ` (${note})` : "";
    return amount <= limit
      ? pass("approval.limit", `${formatCents(amount)} within ${role} limit ${formatCents(limit)}${n}`)
      : fail("approval.limit", `${formatCents(amount)} exceeds ${role} limit ${formatCents(limit)}${n}`, "escalate");
  }

  /** While a subject is escalated, only its target authority may act on it, and only once delivered. */
  private escalationRoutingRule(p: Proposal, subject: Ref): RuleResult {
    const open = this.openEscalationFor(subject);
    if (!open) return pass("escalation.routing", "not escalated");
    if (p.role === open.to && open.status === "awaiting_decision") return pass("escalation.routing", `decided by ${open.to}`);
    return fail("escalation.routing", `${subject.id} is escalated to ${open.to} (${open.status}); only that authority can act on it`, "deny");
  }

  private prepayInFlightRule(inv: Invoice): RuleResult {
    const inFlight = inv.poId ? [...this.payments.values()].some((x) => x.poId === inv.poId && !x.invoiceId && x.status === "scheduled") : false;
    return inFlight ? fail("payment.prepay_settled", "a prepayment on this order is still in flight; match after it settles", "hold") : pass("payment.prepay_settled", "no prepayment in flight");
  }

  /** Everything paid or scheduled against an order: prepayments plus payments of its invoices. */
  paidAgainstPo(poId: string): Cents {
    return [...this.payments.values()]
      .filter((x) => x.status !== "cancelled" && (x.poId === poId || (x.invoiceId && this.invoices.get(x.invoiceId)?.poId === poId)))
      .reduce((s, x) => s + x.amount, 0);
  }

  limitFor(role: Role): Cents {
    const a = this.#policy.approval;
    if (role === "controller") return a.agentMaxCents;
    if (role === "local_authority") return a.localAuthorityMaxCents;
    if (role === "remote_authority") return a.remoteAuthorityMaxCents;
    return 0;
  }

  /**
   * Cash after this amount (and all other open commitments) must cover the minimum
   * runway. `alreadyCommitted` means the amount is part of the open commitments
   * (paying an approved invoice), so it must not be counted twice.
   */
  private runwayRule(amount: Cents, what: string, alreadyCommitted = false): RuleResult {
    const after = this.ledger.balance("cash") - this.openCommitments() - (alreadyCommitted ? 0 : amount);
    const days = this.burnPerDayCents > 0 ? after / this.burnPerDayCents : Infinity;
    const min = this.#policy.treasury.minRunwayDays;
    return days >= min
      ? pass("treasury.min_runway", `after ${what}: ${Math.floor(days)} days of runway (min ${min})`)
      : fail("treasury.min_runway", `after ${what}: only ${Math.floor(days)} days of runway (min ${min})`, "escalate");
  }

  private vendorActiveRule(v: Vendor, holdEffect: "hold" | "deny" = "hold"): RuleResult {
    if (v.status === "active") return pass("vendor.active", `${v.name} active`);
    return fail("vendor.active", `${v.name} is ${v.status}${v.statusReason ? `: ${v.statusReason}` : ""}`, v.status === "blocked" ? "deny" : holdEffect);
  }

  // ---------------------------------------------------------------- execution

  private execute(p: Proposal, d: Decision): Ref | undefined {
    const a = p.action;
    const held = d.verdict === "hold";
    const escalate = d.verdict === "escalate";
    let created: Ref | undefined;
    switch (a.type) {
      case "create_requisition": {
        const req: Requisition = {
          id: this.ids.next("REQ"),
          requestedBy: p.actorId,
          sku: a.params.sku,
          qty: a.params.qty,
          orderBy: a.params.orderBy,
          reason: a.params.reason,
          status: "open",
          createdAt: this.now,
          context: a.params.context,
        };
        this.requisitions.set(req.id, req);
        created = { kind: "requisition", id: req.id };
        this.emit("requisition_created", { requisition: req });
        break;
      }
      case "cancel_requisition": {
        const req = this.requisitions.get(a.params.requisitionId)!;
        req.status = "cancelled";
        this.emit("requisition_updated", { requisition: req });
        break;
      }
      case "record_receipt": {
        const po = this.pos.get(a.params.poId)!;
        const g: GoodsReceipt = { id: this.ids.next("GR"), poId: po.id, lines: a.params.lines, receivedBy: p.actorId, at: this.now, note: a.params.note };
        const lines: PostingLine[] = [];
        let value = 0;
        for (const l of g.lines) {
          const pl = po.lines.find((x) => x.sku === l.sku)!;
          const already = this.acceptedQty(po.id, l.sku);
          const good = l.qtyReceived - l.qtyRejected;
          const take = Math.max(0, Math.min(good, pl.qty - already));
          value += take * pl.unitPrice;
          if (good > take) this.raise("qty_over_receipt", { kind: "po", id: po.id }, `${l.sku}: ${good - take} more than ordered arrived; not booked`, 0, p.actorId);
        }
        this.receipts.set(g.id, g);
        created = { kind: "receipt", id: g.id };
        this.origin.set(g.id, { proposalId: p.id, decisionId: d.id, sourceRef: a.params.sourceRef });
        const fully = po.lines.every((pl) => this.acceptedQty(po.id, pl.sku) >= pl.qty);
        po.status = fully ? "received" : "partially_received";
        if (value > 0) {
          lines.push({ account: "inventory", debit: value, credit: 0 }, { account: "grni", debit: 0, credit: value });
          this.postEntry(this.entry(p, d, `Goods received ${g.id} on ${po.id}`, lines, [{ kind: "receipt", id: g.id }, { kind: "po", id: po.id }, ...this.srcRef(a.params.sourceRef)]));
        }
        this.emit("receipt_recorded", { receipt: g, po });
        break;
      }
      case "record_quote": {
        const q: Quote & { status: "open" | "held" | "used" | "rejected"; flags: FlagCode[] } = {
          id: this.ids.next("QT"),
          ...a.params,
          receivedAt: this.now,
          status: "open",
          flags: [],
        };
        this.quotes.set(q.id, q);
        this.origin.set(q.id, { proposalId: p.id, decisionId: d.id, sourceRef: a.params.sourceRef });
        created = { kind: "quote", id: q.id };
        for (const rule of this.quoteRules(q)) {
          if (rule.ok) continue;
          const code = ruleToFlag(rule.rule);
          if (!code) continue;
          q.flags.push(code);
          const atRisk = code === "price_anomaly" ? this.overpay(q) : q.unitPrice * q.qtyAvailable;
          this.raise(code, { kind: "quote", id: q.id }, rule.detail, atRisk, p.actorId);
        }
        this.emit("quote_recorded", { quote: q });
        break;
      }
      case "record_invoice": {
        const lines = a.params.lines;
        const inv: Invoice & { flags: FlagCode[] } = {
          id: this.ids.next("INV"),
          vendorId: a.params.vendorId,
          vendorInvoiceNo: a.params.vendorInvoiceNo,
          poId: a.params.poId,
          lines,
          total: lines.reduce((s, l) => s + l.qty * l.unitPrice, 0),
          bank: a.params.bank,
          issuedAt: a.params.issuedAt,
          receivedAt: this.now,
          dueAt: a.params.dueAt,
          status: "received",
          sourceRef: a.params.sourceRef,
          flags: [],
        };
        this.invoices.set(inv.id, inv);
        this.origin.set(inv.id, { proposalId: p.id, decisionId: d.id, sourceRef: a.params.sourceRef });
        created = { kind: "invoice", id: inv.id };
        this.emit("invoice_recorded", { invoice: inv });
        break;
      }
      case "submit_invoice": {
        const inv = this.invoices.get(a.params.invoiceId)!;
        inv.approvedAmount = a.params.amount;
        inv.submittedBy = p.actorId;
        const m = this.computeMatch(inv);
        // Flags for anything that didn't pass, plus the short-pay if any.
        for (const rule of [...m.rules, ...this.invoiceDocRules(inv)]) {
          if (rule.ok) continue;
          const code = ruleToFlag(rule.rule);
          if (code && !inv.flags.includes(code)) {
            inv.flags.push(code);
            this.raise(code, { kind: "invoice", id: inv.id }, rule.detail, this.invoiceAtRisk(inv, code, m), p.actorId);
          }
        }
        const shortPaid = m.lines.reduce((s, l) => s + (l.billedQty - l.payQty) * l.billedPrice, 0);
        if (shortPaid > 0 && !inv.flags.includes("qty_over_receipt")) {
          inv.flags.push("qty_over_receipt");
          const detail = m.lines.filter((l) => l.billedQty > l.payQty).map((l) => `${l.sku}: billed ${l.billedQty}, received ${l.payQty}`).join("; ");
          this.raise("qty_over_receipt", { kind: "invoice", id: inv.id }, `${detail}; short-paying ${formatCents(shortPaid)}`, shortPaid, p.actorId);
          this.prevent({ kind: "invoice", id: inv.id }, "qty_over_receipt", shortPaid, detail);
        }
        if (held) {
          inv.status = "held";
          this.autoVerifyBank({ kind: "invoice", id: inv.id }, p.actorId);
          this.emit("invoice_held", { invoice: inv, reasons: d.rules.filter((r) => !r.ok) });
        } else {
          inv.status = "submitted";
          this.emit("invoice_submitted", { invoice: inv, match: m });
        }
        break;
      }
      case "raise_flag": {
        this.raise("agent_concern", a.params.subject, a.params.detail, 0, p.actorId);
        break;
      }
      case "confirm_funds": {
        const req = this.requisitions.get(a.params.requisitionId)!;
        if (escalate) {
          this.emit("funds_insufficient", { requisition: req, reasons: d.rules.filter((r) => !r.ok) });
          this.autoEscalate({ kind: "requisition", id: req.id }, d, p.actorId);
        } else {
          req.fundsConfirmedBy = p.actorId;
          this.emit("funds_confirmed", { requisition: req, runway: this.runwayDays() });
        }
        break;
      }
      case "approve_requisition": {
        const req = this.requisitions.get(a.params.requisitionId)!;
        const q = this.quotes.get(a.params.quoteId)!;
        if (held || escalate) {
          req.status = "escalated";
          if (held) q.status = "held";
          this.autoVerifyBank({ kind: "quote", id: q.id }, p.actorId);
          this.autoEscalate({ kind: "requisition", id: req.id }, d, p.actorId);
          this.emit("approval_blocked", { requisition: req, quote: q, verdict: d.verdict, reasons: d.rules.filter((r) => !r.ok) });
          break;
        }
        const qty = a.params.qty ?? req.qty;
        const po: PurchaseOrder = {
          id: this.ids.next("PO"),
          requisitionId: req.id,
          vendorId: q.vendorId,
          quoteId: q.id,
          contractId: this.contractFor(q.vendorId, q.sku, this.now)?.id,
          lines: [{ sku: q.sku, qty, unitPrice: q.unitPrice }],
          total: qty * q.unitPrice,
          terms: q.terms,
          status: "open",
          approvedBy: [p.actorId],
          createdAt: this.now,
        };
        this.pos.set(po.id, po);
        this.origin.set(po.id, { proposalId: p.id, decisionId: d.id });
        q.status = "used";
        req.status = "ordered";
        created = { kind: "po", id: po.id };
        this.supersedeEscalations({ kind: "requisition", id: req.id }, p.actorId);
        this.emit("po_created", { po, requisition: req, approvedBy: p.actorId });
        break;
      }
      case "reject_requisition": {
        const req = this.requisitions.get(a.params.requisitionId)!;
        req.status = "rejected";
        this.supersedeEscalations({ kind: "requisition", id: req.id }, p.actorId);
        this.emit("requisition_updated", { requisition: req, reason: a.params.reason });
        break;
      }
      case "approve_invoice": {
        const inv = this.invoices.get(a.params.invoiceId)!;
        if (held || escalate) {
          if (held) inv.status = "held";
          this.autoVerifyBank({ kind: "invoice", id: inv.id }, p.actorId);
          this.autoEscalate({ kind: "invoice", id: inv.id }, d, p.actorId);
          this.emit("approval_blocked", { invoice: inv, verdict: d.verdict, reasons: d.rules.filter((r) => !r.ok) });
          break;
        }
        const m = this.computeMatch(inv);
        inv.status = "approved";
        inv.matchedQty = Object.fromEntries(m.lines.map((l) => [l.sku, l.payQty]));
        const lines: PostingLine[] = [];
        if (m.grniRelief > 0) lines.push({ account: "grni", debit: m.grniRelief, credit: 0 });
        const ppv = m.matchedValue - m.grniRelief;
        if (ppv > 0) lines.push({ account: "ppv", debit: ppv, credit: 0 });
        if (ppv < 0) lines.push({ account: "ppv", debit: 0, credit: -ppv });
        if (m.prepaidApplied > 0) lines.push({ account: "prepayments", debit: 0, credit: m.prepaidApplied, vendorId: inv.vendorId });
        if (m.payable > 0) lines.push({ account: "ap", debit: 0, credit: m.payable, vendorId: inv.vendorId });
        if (lines.length >= 2) {
          this.postEntry(this.entry(p, d, `Invoice ${inv.vendorInvoiceNo} approved (${inv.id})`, lines, [{ kind: "invoice", id: inv.id }, ...(inv.poId ? [{ kind: "po" as const, id: inv.poId }] : []), ...this.receiptRefs(inv.poId), ...this.srcRef(inv.sourceRef)]));
        }
        this.recordPrice(inv);
        this.supersedeEscalations({ kind: "invoice", id: inv.id }, p.actorId);
        this.emit("invoice_approved", { invoice: inv, match: m, approvedBy: p.actorId });
        break;
      }
      case "reject_invoice": {
        const inv = this.invoices.get(a.params.invoiceId)!;
        inv.status = "rejected";
        const atRisk = inv.flags.length ? inv.total - (inv.flags.includes("price_over_po") ? this.fairValue(inv) : 0) : 0;
        // No purchase order means no obligation: rejecting it isn't "money saved".
        if (inv.flags.length && inv.poId && this.pos.has(inv.poId)) this.prevent({ kind: "invoice", id: inv.id }, inv.flags[0] as FlagCode, atRisk, a.params.reason);
        this.supersedeEscalations({ kind: "invoice", id: inv.id }, p.actorId);
        this.emit("invoice_rejected", { invoice: inv, reason: a.params.reason });
        break;
      }
      case "reject_quote": {
        const q = this.quotes.get(a.params.quoteId)!;
        q.status = "rejected";
        this.emit("quote_rejected", { quote: q, reason: a.params.reason });
        break;
      }
      case "hold_vendor":
      case "block_vendor": {
        const v = this.vendors.get(a.params.vendorId)!;
        v.status = a.type === "hold_vendor" ? "hold" : "blocked";
        v.statusReason = a.params.reason;
        for (const pay of this.payments.values()) if (pay.vendorId === v.id && pay.status === "scheduled") pay.status = "cancelled";
        this.emit("vendor_status_changed", { vendor: v, reason: a.params.reason });
        break;
      }
      case "release_vendor": {
        const v = this.vendors.get(a.params.vendorId)!;
        v.status = "active";
        v.statusReason = undefined;
        this.emit("vendor_status_changed", { vendor: v, reason: a.params.reason });
        break;
      }
      case "request_verification": {
        created = this.createVerification(a.params.vendorId, a.params.subject, p.actorId);
        break;
      }
      case "escalate": {
        created = this.createEscalation(a.params.subject, a.params.reason, [], p.actorId, p.rationale);
        break;
      }
      case "schedule_payment": {
        if (held || escalate) {
          if (escalate) this.autoEscalate(params2ref(a.params), d, p.actorId);
          break;
        }
        const inv = a.params.invoiceId ? this.invoices.get(a.params.invoiceId) : undefined;
        const po = a.params.poId ? this.pos.get(a.params.poId) : undefined;
        const vendor = this.vendors.get((inv?.vendorId ?? po?.vendorId) as string)!;
        const pay: Payment = {
          id: this.ids.next("PAY"),
          invoiceId: inv?.id,
          poId: po?.id,
          vendorId: vendor.id,
          amount: a.params.amount,
          // Always the verified master account, never the one printed on the document.
          bank: { ...vendor.bank },
          status: "scheduled",
          approvedBy: inv ? this.approversOf({ kind: "invoice", id: inv.id }) : (po?.approvedBy ?? []),
          scheduledBy: p.actorId,
          createdAt: this.now,
        };
        this.payments.set(pay.id, pay);
        this.origin.set(pay.id, { proposalId: p.id, decisionId: d.id });
        created = { kind: "payment", id: pay.id };
        this.emit("payment_scheduled", { payment: pay });
        break;
      }
      case "execute_payment": {
        const pay = this.payments.get(a.params.paymentId)!;
        pay.status = "sent";
        pay.executedBy = p.actorId;
        pay.sentAt = this.now;
        const debit: PostingLine = pay.invoiceId
          ? { account: "ap", debit: pay.amount, credit: 0, vendorId: pay.vendorId }
          : { account: "prepayments", debit: pay.amount, credit: 0, vendorId: pay.vendorId };
        const refs: Ref[] = [{ kind: "payment", id: pay.id }];
        if (pay.invoiceId) refs.push({ kind: "invoice", id: pay.invoiceId });
        if (pay.poId) refs.push({ kind: "po", id: pay.poId });
        const inv = pay.invoiceId ? this.invoices.get(pay.invoiceId) : undefined;
        if (inv?.poId) refs.push({ kind: "po", id: inv.poId }, ...this.receiptRefs(inv.poId));
        this.postEntry({ ...this.entry(p, d, `Payment ${pay.id} to ${this.vendors.get(pay.vendorId)?.name}`, [debit, { account: "cash", debit: 0, credit: pay.amount }], refs), approvers: pay.approvedBy });
        if (inv && this.paidOrScheduled({ invoiceId: inv.id }, true) >= (inv.approvedAmount ?? 0)) inv.status = "paid";
        this.emit("payment_sent", { payment: pay, cash: this.ledger.balance("cash") });
        break;
      }
      case "decide": {
        const esc = this.escalations.get(a.params.escalationId)!;
        const opt = esc.options.find((o) => o.id === a.params.optionId)!;
        // Sub-actions run while the escalation is still awaiting this authority's decision.
        for (const sub of opt.actions) {
          this.submit({ actorId: p.actorId, type: sub.type, params: sub.params, rationale: `Decision on ${esc.id}: ${opt.label}`, source: "human", credential: this.#credentials.get(p.actorId) });
        }
        esc.history = [...(esc.history ?? []), { optionId: opt.id, by: p.actorId, at: this.now }];
        // "Wait" and operational levers don't settle the purchase: the escalation stays with
        // this authority (nobody else can act on the subject) until a final choice.
        const final = opt.id !== "wait" && !opt.leverId;
        if (final) {
          esc.status = "decided";
          esc.decision = { optionId: opt.id, by: p.actorId, at: this.now };
        } else if (esc.status === "awaiting_decision") {
          if (opt.leverId) esc.options = esc.options.filter((o) => o.id !== opt.id);
          this.emit("escalation_updated", { escalation: esc });
        }
        this.audit.append(this.now, "escalation", p.actorId, `${this.actors.get(p.actorId)?.displayName} chose "${opt.label}" on ${esc.id}`, { escalationId: esc.id, option: opt });
        this.emit("escalation_decided", { escalation: esc, option: opt });
        if (opt.leverId) {
          this.audit.append(this.now, "lever", p.actorId, `Operational action: ${opt.label}`, { leverId: opt.leverId, escalationId: esc.id });
          this.emit("lever_activated", { leverId: opt.leverId, escalationId: esc.id, by: p.actorId });
        }
        break;
      }
      case "answer_verification": {
        const v = this.verifications.get(a.params.verificationId)!;
        v.status = a.params.confirmed ? "confirmed" : "rejected";
        v.answeredAt = this.now;
        v.answer = a.params.answer;
        const vendor = this.vendors.get(v.vendorId)!;
        if (a.params.confirmed) {
          vendor.bank = { ...v.claimedBank };
          vendor.bankVerifiedAt = this.now;
          if (v.subject.kind === "quote") {
            const q = this.quotes.get(v.subject.id);
            if (q && q.status === "held") q.status = "open";
          }
          if (v.subject.kind === "invoice") {
            const inv = this.invoices.get(v.subject.id);
            if (inv && inv.status === "held") inv.status = "received";
          }
        } else {
          const amount = this.amountOf(v.subject);
          this.prevent(v.subject, "fraud_confirmed", amount, `bank change rejected by ${vendor.name} call-back: ${a.params.answer}`);
          if (v.subject.kind === "quote") {
            const q = this.quotes.get(v.subject.id);
            if (q) q.status = "rejected";
          }
          if (v.subject.kind === "invoice") {
            const inv = this.invoices.get(v.subject.id);
            if (inv) {
              inv.status = "rejected";
              inv.voidedAsFraud = true;
            }
          }
        }
        this.audit.append(this.now, "verification", p.actorId, `Verification ${v.id}: ${v.status} (${a.params.answer})`, v);
        this.emit("verification_answered", { verification: v, vendor });
        // Open escalations on the affected purchase get options rebuilt from the new facts.
        const reqId = v.subject.kind === "quote" ? this.quotes.get(v.subject.id)?.requisitionId : undefined;
        const esc = reqId ? this.openEscalationFor({ kind: "requisition", id: reqId }) : undefined;
        if (esc) {
          const used = new Set((esc.history ?? []).map((h) => h.optionId));
          esc.options = this.buildOptions(esc.subject, esc.to).filter((o) => !(o.leverId && used.has(o.id)));
          this.emit("escalation_updated", { escalation: esc });
        }
        break;
      }
    }
    if (created) this.emit("created", { ref: created, proposalId: p.id, decisionId: d.id });
    return created;
  }

  // ---------------------------------------------------------------- escalation & verification

  private autoVerifyBank(subject: Ref, actorId: string): void {
    if (this.#policy.vendorBankChange.action !== "hold_and_verify") return;
    const claimed = this.bankOf(subject);
    const vendorId = this.vendorOf(subject);
    if (!claimed || !vendorId) return;
    const vendor = this.vendors.get(vendorId);
    if (!vendor || bankKey(claimed) === bankKey(vendor.bank)) return;
    const open = [...this.verifications.values()].some((x) => x.status === "pending" && x.vendorId === vendorId && bankKey(x.claimedBank) === bankKey(claimed));
    if (!open) this.createVerification(vendorId, subject, actorId);
  }

  private createVerification(vendorId: string, subject: Ref, actorId: string): Ref {
    const claimed = this.bankOf(subject)!;
    const v: Verification = {
      id: this.ids.next("VER"),
      vendorId,
      claimedBank: claimed,
      subject,
      sentAt: this.now,
      arrivesAt: this.now + this.remoteLatencyMs,
      status: "pending",
    };
    this.verifications.set(v.id, v);
    this.audit.append(this.now, "verification", actorId, `Verification ${v.id} sent to ${this.humanName("remote_authority")} for ${this.vendors.get(vendorId)?.name}`, v);
    this.emit("verification_requested", { verification: v, expectedReplyAt: this.expectedVerificationReply(v) });
    return { kind: "verification", id: v.id };
  }

  expectedVerificationReply(v: Verification): Time {
    return v.sentAt + 2 * this.remoteLatencyMs + this.#policy.vendorBankChange.verificationProcessingMs;
  }

  private autoEscalate(subject: Ref, d: Decision, actorId: string): void {
    if (this.openEscalationFor(subject)) return;
    const failed = d.rules.filter((r) => !r.ok);
    const reason = failed.map((r) => RULE_LABELS[r.rule] ? `${RULE_LABELS[r.rule]}: ${r.detail}` : r.detail).join(" | ");
    this.createEscalation(subject, reason, failed.map((r) => ruleToFlag(r.rule)).filter((x): x is FlagCode => !!x), actorId);
  }

  private createEscalation(subject: Ref, reason: string, flags: FlagCode[], actorId: string, message?: string): Ref {
    const decideBy = subject.kind === "requisition" ? this.requisitions.get(subject.id)?.orderBy : subject.kind === "invoice" ? this.invoices.get(subject.id)?.dueAt : undefined;
    // Normally the remote authority decides. If it can't answer before the deadline,
    // the local authority decides instead, with options limited to its emergency limit.
    const remoteAnswerAt = this.now + 2 * this.remoteLatencyMs + this.#policy.vendorBankChange.verificationProcessingMs;
    const urgent = decideBy !== undefined && remoteAnswerAt > decideBy;
    const to: HumanRole = urgent ? "local_authority" : "remote_authority";
    const options = this.buildOptions(subject, to);
    const esc: Escalation = {
      id: this.ids.next("ESC"),
      subject,
      to,
      reason,
      flags,
      options,
      createdAt: this.now,
      deliverAt: to === "remote_authority" ? this.now + this.remoteLatencyMs : this.now,
      decideBy,
      status: to === "remote_authority" ? "in_transit" : "awaiting_decision",
      createdBy: actorId,
      message,
    };
    this.escalations.set(esc.id, esc);
    this.audit.append(this.now, "escalation", actorId, `${esc.id} to ${this.humanName(to)}: ${reason}`, esc);
    this.emit("escalation_created", { escalation: esc });
    if (esc.status === "awaiting_decision") this.emit("escalation_delivered", { escalation: esc });
    return { kind: "escalation", id: esc.id };
  }

  /** Attach a drafted message (e.g. from an LLM agent) to an escalation. */
  setEscalationMessage(id: string, message: string, actorId: string): void {
    const esc = this.escalations.get(id);
    if (!esc) return;
    esc.message = message;
    this.audit.append(this.now, "message", actorId, `Message drafted for ${id}`, { id, message });
    this.emit("escalation_updated", { escalation: esc });
  }

  /** Options for a human, built deterministically from state and policy. */
  buildOptions(subject: Ref, to: HumanRole): EscalationOption[] {
    const limit = this.limitFor(to);
    const opts: EscalationOption[] = [];
    if (subject.kind === "requisition") {
      const req = this.requisitions.get(subject.id);
      if (!req) return opts;
      const quotes = [...this.quotes.values()].filter((q) => q.requisitionId === req.id && (q.status === "open" || q.status === "held"));
      const pending = [...this.verifications.values()].filter((v) => v.status === "pending" && v.subject.kind === "quote" && quotes.some((q) => q.id === v.subject.id));
      const replyAt = pending.length ? Math.max(...pending.map((v) => this.expectedVerificationReply(v))) : this.now + 2 * this.remoteLatencyMs + this.#policy.vendorBankChange.verificationProcessingMs;
      for (const q of quotes) {
        const rules = this.quoteRules(q);
        if (!rules.every((r) => r.ok)) continue;
        const qty = Math.min(req.qty, q.qtyAvailable, Math.floor(limit / q.unitPrice));
        if (qty <= 0) continue;
        const vendor = this.vendors.get(q.vendorId);
        opts.push({
          id: `buy-${q.id}`,
          label: `Buy ${qty} now from ${vendor?.name}`,
          detail: `${qty} x ${formatCents(q.unitPrice)} = ${formatCents(qty * q.unitPrice)} to the verified account on file. ${qty < req.qty ? `Covers ${qty} of ${req.qty} requested.` : "Covers the full request."}`,
          actions: [{ type: "approve_requisition", params: { requisitionId: req.id, quoteId: q.id, qty } }],
          costCents: qty * q.unitPrice,
          withinAuthority: qty * q.unitPrice <= limit,
        });
      }
      // Waiting only makes sense while an out-of-band check is still outstanding.
      if (pending.length) opts.push({
        id: "wait",
        label: "Wait for verification",
        detail: `Keep everything on hold until the out-of-band check comes back (expected in about ${Math.round((replyAt - this.now) / 60_000)} min).`,
        actions: [],
        costCents: 0,
        withinAuthority: true,
      });
      for (const lever of this.levers.filter((l) => !l.appliesToSkus || l.appliesToSkus.includes(req.sku))) {
        opts.push({ id: `lever-${lever.id}`, label: lever.label, detail: lever.detail, actions: [], leverId: lever.id, costCents: 0, withinAuthority: true });
      }
      opts.push({
        id: "reject",
        label: "Reject the request",
        detail: "Cancel this purchase request.",
        actions: [{ type: "reject_requisition", params: { requisitionId: req.id, reason: "rejected by authority" } }],
        costCents: 0,
        withinAuthority: true,
      });
    } else if (subject.kind === "invoice") {
      const inv = this.invoices.get(subject.id);
      if (!inv) return opts;
      const amount = inv.approvedAmount ?? inv.total;
      if (inv.status === "submitted") {
        opts.push({
          id: "approve",
          label: `Approve ${formatCents(amount)}`,
          detail: "Approve the matched amount for payment.",
          actions: [{ type: "approve_invoice", params: { invoiceId: inv.id } }],
          costCents: amount,
          withinAuthority: amount <= limit,
        });
      }
      opts.push({ id: "reject", label: "Reject the invoice", detail: "It will never be paid.", actions: [{ type: "reject_invoice", params: { invoiceId: inv.id, reason: "rejected by authority" } }], costCents: 0, withinAuthority: true });
    }
    return opts.filter((o) => o.withinAuthority);
  }

  private supersedeEscalations(subject: Ref, actorId: string): void {
    for (const e of this.escalations.values()) {
      if (e.subject.kind === subject.kind && e.subject.id === subject.id && (e.status === "awaiting_decision" || e.status === "in_transit")) {
        e.status = "superseded";
        this.audit.append(this.now, "escalation", actorId, `${e.id} superseded`, { id: e.id });
        this.emit("escalation_updated", { escalation: e });
      }
    }
  }

  openEscalationFor(subject: Ref): Escalation | undefined {
    return [...this.escalations.values()].find((e) => e.subject.kind === subject.kind && e.subject.id === subject.id && (e.status === "in_transit" || e.status === "awaiting_decision"));
  }

  // ---------------------------------------------------------------- helpers

  private postEntry(input: JournalEntryInput): void {
    const d = this.decisions.find((x) => x.id === input.decisionId);
    if (d?.verdict !== "allow") throw new Error(`refusing to post: decision ${input.decisionId} is ${d?.verdict ?? "missing"}`);
    const auth = this.ledger.authorize(input.decisionId, ENGINE_SECRET);
    const e = this.ledger.post(input, this.now, auth);
    this.audit.append(this.now, "execution", input.actorId, `Posted ${e.id}: ${e.memo}`, { entryId: e.id, hash: e.hash });
    this.emit("ledger_posted", { entry: e });
  }

  private entry(p: Proposal, d: Decision, memo: string, lines: PostingLine[], refs: Ref[]): JournalEntryInput {
    return {
      memo,
      lines,
      refs: [...refs, { kind: "proposal", id: p.id }],
      proposalId: p.id,
      decisionId: d.id,
      actorId: p.actorId,
      approvers: refs.flatMap((r) => this.approversOf(r)).filter((x, i, arr) => arr.indexOf(x) === i),
      rules: d.rules.map((r) => r.rule).filter((x, i, arr) => arr.indexOf(x) === i),
    };
  }

  private srcRef(sourceRef?: string): Ref[] {
    return sourceRef ? [{ kind: "proposal", id: `doc:${sourceRef}` }] : [];
  }

  private receiptRefs(poId?: string): Ref[] {
    if (!poId) return [];
    return [...this.receipts.values()].filter((g) => g.poId === poId).map((g) => ({ kind: "receipt" as const, id: g.id }));
  }

  approversOf(ref: Ref): string[] {
    if (ref.kind === "po") return this.pos.get(ref.id)?.approvedBy ?? [];
    if (ref.kind === "invoice") {
      return this.proposals
        .filter((p) => p.action.type === "approve_invoice" && (p.action.params as { invoiceId: string }).invoiceId === ref.id)
        .filter((p) => this.decisions.some((d) => d.proposalId === p.id && d.verdict === "allow"))
        .map((p) => p.actorId);
    }
    return [];
  }

  private raise(code: FlagCode, subject: Ref, detail: string, amountAtRisk: Cents, raisedBy: string): void {
    const f: Flag = { code, subject, detail, amountAtRisk, raisedBy, at: this.now };
    this.flags.push(f);
    this.emit("flag_raised", { flag: f });
  }

  private prevent(subject: Ref, code: Prevented["code"], amount: Cents, detail: string): void {
    if (amount <= 0) return;
    if (this.prevented.some((x) => x.subject.kind === subject.kind && x.subject.id === subject.id && x.code === code)) return;
    const pr: Prevented = { subject, code, amount, detail, at: this.now };
    this.prevented.push(pr);
    this.emit("loss_prevented", { prevented: pr, total: this.prevented.reduce((s, x) => s + x.amount, 0) });
  }

  private overpay(q: Quote): Cents {
    const pc = this.priceCheck(q.vendorId, q.sku, q.unitPrice);
    return pc.median > 0 ? Math.max(0, Math.round((q.unitPrice - pc.median) * q.qtyAvailable)) : 0;
  }

  private fairValue(inv: Invoice): Cents {
    const po = inv.poId ? this.pos.get(inv.poId) : undefined;
    if (!po) return 0;
    return inv.lines.reduce((s, l) => s + l.qty * (po.lines.find((x) => x.sku === l.sku)?.unitPrice ?? 0), 0);
  }

  private invoiceAtRisk(inv: Invoice, code: FlagCode, m: MatchResult): Cents {
    if (code === "price_over_po" || code === "price_over_contract") return Math.max(0, inv.total - this.fairValue(inv));
    if (code === "qty_over_receipt") return Math.max(0, inv.total - m.matchedValue);
    return inv.total;
  }

  private recordPrice(inv: Invoice): void {
    for (const l of inv.lines) this.priceHistory.push({ vendorId: inv.vendorId, sku: l.sku, unitPrice: l.unitPrice, at: inv.issuedAt });
  }

  private acceptedQty(poId: string, sku: string): number {
    let n = 0;
    for (const g of this.receipts.values()) if (g.poId === poId) for (const l of g.lines) if (l.sku === sku) n += l.qtyReceived - l.qtyRejected;
    return n;
  }

  private prepaidBalance(poId: string): Cents {
    const po = this.pos.get(poId);
    if (!po) return 0;
    const paid = [...this.payments.values()].filter((p) => p.poId === poId && p.status === "sent").reduce((s, p) => s + p.amount, 0);
    const applied = [...this.invoices.values()]
      .filter((i) => i.poId === poId && (i.status === "approved" || i.status === "paid"))
      .reduce((s, i) => s + this.computeMatchApplied(i), 0);
    return Math.max(0, paid - applied);
  }

  private computeMatchApplied(inv: Invoice): Cents {
    const e = this.ledger.all().find((x) => x.refs.some((r) => r.kind === "invoice" && r.id === inv.id) && x.memo.startsWith("Invoice"));
    return e?.lines.filter((l) => l.account === "prepayments").reduce((s, l) => s + l.credit, 0) ?? 0;
  }

  private paidOrScheduled(by: { invoiceId?: string; poId?: string }, sentOnly = false): Cents {
    return [...this.payments.values()]
      .filter((p) => (by.invoiceId ? p.invoiceId === by.invoiceId : p.poId === by.poId && !p.invoiceId))
      .filter((p) => (sentOnly ? p.status === "sent" : p.status !== "cancelled"))
      .reduce((s, p) => s + p.amount, 0);
  }

  /** Open purchase commitments not yet paid. */
  openCommitments(): Cents {
    let total = 0;
    for (const po of this.pos.values()) {
      if (po.status === "cancelled" || po.status === "closed") continue;
      const paid = [...this.payments.values()]
        .filter((p) => p.status === "sent" && (p.poId === po.id || (p.invoiceId && this.invoices.get(p.invoiceId)?.poId === po.id)))
        .reduce((s, p) => s + p.amount, 0);
      const rejectedShort = [...this.invoices.values()].filter((i) => i.poId === po.id && i.status === "paid").reduce((s, i) => s + (i.total - (i.approvedAmount ?? i.total)), 0);
      total += Math.max(0, po.total - paid - rejectedShort);
    }
    return total;
  }

  runwayDays(): number {
    if (this.burnPerDayCents <= 0) return Infinity;
    return (this.ledger.balance("cash") - this.openCommitments()) / this.burnPerDayCents;
  }

  marketPrice(sku: string): Cents {
    const h = this.priceHistory.filter((x) => x.sku === sku).map((x) => x.unitPrice);
    return h.length ? Math.round(median(h)) : 0;
  }

  contractFor(vendorId: string, sku: string, at: Time): Contract | undefined {
    return this.contracts.find((c) => c.vendorId === vendorId && c.sku === sku && c.validFrom <= at && at <= c.validTo);
  }

  private refExists(ref: Ref): boolean {
    const maps: Partial<Record<Ref["kind"], Map<string, unknown>>> = {
      requisition: this.requisitions,
      quote: this.quotes,
      po: this.pos,
      receipt: this.receipts,
      invoice: this.invoices,
      payment: this.payments,
      vendor: this.vendors,
      verification: this.verifications,
      escalation: this.escalations,
    };
    return !!maps[ref.kind]?.has(ref.id);
  }

  private bankOf(ref: Ref): BankAccount | undefined {
    if (ref.kind === "quote") return this.quotes.get(ref.id)?.bank;
    if (ref.kind === "invoice") return this.invoices.get(ref.id)?.bank;
    return undefined;
  }

  private vendorOf(ref: Ref): string | undefined {
    if (ref.kind === "quote") return this.quotes.get(ref.id)?.vendorId;
    if (ref.kind === "invoice") return this.invoices.get(ref.id)?.vendorId;
    if (ref.kind === "po") return this.pos.get(ref.id)?.vendorId;
    return undefined;
  }

  amountOf(ref: Ref): Cents {
    if (ref.kind === "quote") {
      const q = this.quotes.get(ref.id);
      if (!q) return 0;
      const req = q.requisitionId ? this.requisitions.get(q.requisitionId) : undefined;
      return q.unitPrice * Math.min(q.qtyAvailable, req?.qty ?? q.qtyAvailable);
    }
    if (ref.kind === "invoice") {
      const inv = this.invoices.get(ref.id);
      return inv?.approvedAmount ?? inv?.total ?? 0;
    }
    if (ref.kind === "requisition") {
      const req = this.requisitions.get(ref.id);
      if (!req) return 0;
      const qs = [...this.quotes.values()].filter((q) => q.requisitionId === req.id).map((q) => q.unitPrice);
      return req.qty * (qs.length ? Math.min(...qs) : this.marketPrice(req.sku));
    }
    if (ref.kind === "po") return this.pos.get(ref.id)?.total ?? 0;
    return 0;
  }

  humanName(role: HumanRole): string {
    return [...this.actors.values()].find((a) => a.role === role)?.displayName ?? role;
  }

  // ---------------------------------------------------------------- read models

  /** Everything that led to a ledger entry: proposal, decision with rules, source records, documents, approvers. */
  trace(entryId: string) {
    const e = this.ledger.get(entryId);
    if (!e) return undefined;
    const proposal = this.proposals.find((p) => p.id === e.proposalId);
    const decision = this.decisions.find((d) => d.id === e.decisionId);
    const sources = e.refs.map((r) => {
      const record = this.lookup(r);
      const origin = this.origin.get(r.id);
      const originProposal = origin ? this.proposals.find((p) => p.id === origin.proposalId) : undefined;
      const originDecision = origin ? this.decisions.find((d) => d.id === origin.decisionId) : undefined;
      const docId = origin?.sourceRef ?? (r.id.startsWith("doc:") ? r.id.slice(4) : undefined);
      return { ref: r, record, proposal: originProposal, decision: originDecision, document: docId ? this.documents.get(docId) : undefined };
    });
    const approvers = e.approvers.map((id) => this.actors.get(id));
    return { entry: e, proposal, decision, sources, approvers, actor: this.actors.get(e.actorId) };
  }

  lookup(r: Ref): unknown {
    switch (r.kind) {
      case "requisition":
        return this.requisitions.get(r.id);
      case "quote":
        return this.quotes.get(r.id);
      case "po":
        return this.pos.get(r.id);
      case "receipt":
        return this.receipts.get(r.id);
      case "invoice":
        return this.invoices.get(r.id);
      case "payment":
        return this.payments.get(r.id);
      case "vendor":
        return this.vendors.get(r.id);
      case "verification":
        return this.verifications.get(r.id);
      case "escalation":
        return this.escalations.get(r.id);
      case "proposal":
        return this.proposals.find((p) => p.id === r.id);
    }
  }

  /** Ledger + audit integrity, cross-checking the ledger head against the audit log. */
  verifyIntegrity(): { ok: boolean; problems: string[] } {
    const posted = this.audit.all().filter((r) => r.kind === "execution" && (r.data as { entryId?: string }).entryId);
    const last = posted.at(-1)?.data as { hash?: string } | undefined;
    const l = this.ledger.verify({ seq: posted.length, hash: last?.hash ?? "genesis" });
    const a = this.audit.verify();
    return { ok: l.ok && a.ok, problems: [...l.problems, ...a.problems] };
  }

  snapshot() {
    return structuredClone(this.snapshotLive());
  }

  private snapshotLive() {
    return {
      now: this.now,
      policy: this.policy,
      remoteLatencyMs: this.remoteLatencyMs,
      cash: this.ledger.balance("cash"),
      openCommitments: this.openCommitments(),
      runwayDays: this.runwayDays(),
      burnPerDayCents: this.burnPerDayCents,
      prevented: this.prevented,
      preventedTotal: this.prevented.reduce((s, x) => s + x.amount, 0),
      actors: [...this.actors.values()],
      vendors: [...this.vendors.values()],
      items: [...this.items.values()],
      requisitions: [...this.requisitions.values()],
      quotes: [...this.quotes.values()],
      pos: [...this.pos.values()],
      receipts: [...this.receipts.values()],
      invoices: [...this.invoices.values()],
      payments: [...this.payments.values()],
      verifications: [...this.verifications.values()],
      escalations: [...this.escalations.values()],
      flags: this.flags,
      trialBalance: this.ledger.trialBalance(),
      ledger: this.ledger.all(),
      ledgerOk: this.ledger.verify().ok,
      auditCount: this.audit.all().length,
      lastEventSeq: this.eventSeq,
    };
  }
}

function pass(rule: string, detail: string): RuleResult {
  return { rule, ok: true, detail, effect: "deny" };
}

function fail(rule: string, detail: string, effect: RuleResult["effect"]): RuleResult {
  return { rule, ok: false, detail, effect };
}

function ruleToFlag(rule: string): FlagCode | undefined {
  const map: Record<string, FlagCode> = {
    "vendor.bank_matches_master": "bank_mismatch",
    "price.anomaly": "price_anomaly",
    "contract.price": "price_over_contract",
    "match.price_within_tolerance": "price_over_po",
    "match.qty_within_receipt": "qty_over_receipt",
    "dup.invoice_number": "duplicate",
    "dup.same_amount": "duplicate",
    "match.po_exists": "no_po",
    "match.receipt_exists": "no_receipt",
    "vendor.active": "vendor_not_active",
    "treasury.min_runway": "insufficient_runway",
    "approval.limit": "over_authority",
  };
  return map[rule];
}

function params2ref(p: { invoiceId?: string; poId?: string }): Ref {
  return p.invoiceId ? { kind: "invoice", id: p.invoiceId } : { kind: "po", id: p.poId as string };
}

export function maskAccount(b: BankAccount): string {
  return `${b.bank} ****${b.account.slice(-4)}`;
}

export { ACTION_TYPES, HUMAN_ROLES };
