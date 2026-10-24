import { z } from "zod";
import { ACTION_TYPES, type ActionType } from "./actions.ts";

/**
 * The policy is plain data. Editing it (console policy editor, or a JSON file)
 * changes engine behaviour with no code change. Every rule the engine evaluates
 * reads its thresholds from here.
 */

const cents = z.number().int().nonnegative();
const actionEnum = z.enum(ACTION_TYPES as [ActionType, ...ActionType[]]);
const roleEnum = z.enum(["requester", "receiver", "ap", "treasury", "controller", "local_authority", "remote_authority", "system"]);

/** No single role may hold two of these duties (segregation of duties). */
const INCOMPATIBLE: [string, ActionType[], ActionType[]][] = [
  ["approve and pay", ["approve_requisition", "approve_invoice"], ["schedule_payment", "execute_payment"]],
  ["request and approve", ["create_requisition"], ["approve_requisition"]],
  ["request and receive", ["create_requisition"], ["record_receipt"]],
  ["submit and approve invoices", ["submit_invoice"], ["approve_invoice"]],
  ["receive and pay", ["record_receipt"], ["schedule_payment", "execute_payment"]],
  ["request and answer bank verifications", ["request_verification"], ["answer_verification"]],
];

export const policySchema = z.object({
  name: z.string(),
  version: z.number().int(),
  /** Which actions each role may propose. Anything not listed is denied. */
  permissions: z.record(roleEnum, z.array(actionEnum)),
  approval: z.object({
    /** Largest order or invoice the controller agent may approve on its own. */
    agentMaxCents: cents,
    /** Emergency spending limit of the on-site human authority. */
    localAuthorityMaxCents: cents,
    /** Limit of the remote human authority (e.g. CFO). */
    remoteAuthorityMaxCents: cents,
    /** Approvals by the same role for the same vendor and item within this window add up (split-order guard). */
    splitWindowDays: z.number().nonnegative(),
  }),
  match: z.object({
    /** Billed unit price may exceed the PO price by at most this percent. */
    priceTolerancePct: z.number().nonnegative(),
    /** Pay only for quantity actually received and accepted (short-pay the rest). */
    payReceivedQtyOnly: z.boolean(),
  }),
  vendorBankChange: z.object({
    /** Details on a document differ from the vendor master: hold and verify out of band, or block outright. */
    action: z.enum(["hold_and_verify", "block"]),
    /** Time the remote party needs to do the call-back, on top of message latency. */
    verificationProcessingMs: z.number().int().nonnegative(),
  }),
  duplicates: z.object({
    /** Same vendor + same total + same PO within this window is treated as a duplicate. */
    windowDays: z.number().nonnegative(),
  }),
  priceAnomaly: z.object({
    /** Robust z-score (log price vs vendor/item history) above which a price is anomalous. */
    zThreshold: z.number().positive(),
    /** Also anomalous if price / historical median exceeds this ratio. */
    ratioThreshold: z.number().positive(),
    /** Need at least this many past prices to judge. */
    minHistory: z.number().int().nonnegative(),
  }),
  /** Below this amount, a price anomaly is noted but does not need escalation. */
  materialityCents: cents,
  treasury: z.object({
    /** Cash after any commitment must cover this many days of spending. */
    minRunwayDays: z.number().nonnegative(),
  }),
  /** Segregation of duties is not optional: these must stay true. */
  sod: z.object({
    requesterCannotApprove: z.literal(true),
    submitterCannotApprove: z.literal(true),
    approverCannotPay: z.literal(true),
    requesterCannotReceive: z.literal(true),
  }),
}).superRefine((p, ctx) => {
  for (const [role, actions] of Object.entries(p.permissions)) {
    for (const [what, a, b] of INCOMPATIBLE) {
      if (actions.some((x) => a.includes(x)) && actions.some((x) => b.includes(x))) {
        ctx.addIssue({ code: "custom", path: ["permissions", role], message: `role ${role} cannot both ${what} (segregation of duties)` });
      }
    }
  }
});

export type Policy = z.infer<typeof policySchema>;

export const DEFAULT_POLICY: Policy = {
  name: "Standard P2P controls",
  version: 1,
  permissions: {
    requester: ["create_requisition", "cancel_requisition"],
    receiver: ["record_receipt"],
    ap: ["record_quote", "record_invoice", "submit_invoice", "raise_flag"],
    treasury: ["confirm_funds", "schedule_payment", "execute_payment", "raise_flag"],
    controller: [
      "approve_requisition",
      "reject_requisition",
      "approve_invoice",
      "reject_invoice",
      "reject_quote",
      "hold_vendor",
      "block_vendor",
      "request_verification",
      "escalate",
      "raise_flag",
    ],
    local_authority: ["decide", "approve_requisition", "reject_requisition", "approve_invoice", "reject_invoice"],
    remote_authority: [
      "decide",
      "answer_verification",
      "approve_requisition",
      "reject_requisition",
      "approve_invoice",
      "reject_invoice",
      "reject_quote",
      "hold_vendor",
      "block_vendor",
      "release_vendor",
    ],
    system: [],
  },
  approval: {
    agentMaxCents: 500_000,
    localAuthorityMaxCents: 1_500_000,
    remoteAuthorityMaxCents: 100_000_000,
    splitWindowDays: 7,
  },
  match: { priceTolerancePct: 2, payReceivedQtyOnly: true },
  vendorBankChange: { action: "hold_and_verify", verificationProcessingMs: 20 * 60_000 },
  duplicates: { windowDays: 90 },
  priceAnomaly: { zThreshold: 4, ratioThreshold: 1.35, minHistory: 4 },
  materialityCents: 50_000,
  treasury: { minRunwayDays: 90 },
  sod: {
    requesterCannotApprove: true,
    submitterCannotApprove: true,
    approverCannotPay: true,
    requesterCannotReceive: true,
  },
};

export function parsePolicy(input: unknown): Policy {
  return policySchema.parse(input);
}

export function freezePolicy(p: Policy): Policy {
  const freeze = (o: unknown): unknown => {
    if (o && typeof o === "object" && !Object.isFrozen(o)) {
      Object.freeze(o);
      for (const v of Object.values(o)) freeze(v);
    }
    return o;
  };
  return freeze(p) as Policy;
}

export type Verdict = "allow" | "deny" | "hold" | "escalate";

/** Result of one rule. `effect` says what happens when the rule does not pass. */
export interface RuleResult {
  rule: string;
  ok: boolean;
  detail: string;
  effect: Exclude<Verdict, "allow">;
}

export function combineVerdict(results: readonly RuleResult[]): Verdict {
  const failed = results.filter((r) => !r.ok);
  if (failed.some((r) => r.effect === "deny")) return "deny";
  if (failed.some((r) => r.effect === "hold")) return "hold";
  if (failed.some((r) => r.effect === "escalate")) return "escalate";
  return "allow";
}

/** Human-readable label for each rule id, shown in the console and on the VR screens. */
export const RULE_LABELS: Record<string, string> = {
  "rbac.permitted": "Role is allowed to take this action",
  "actor.known": "Actor is registered",
  "sod.requester_not_approver": "Requester cannot approve their own request",
  "sod.submitter_not_approver": "Whoever submitted an invoice cannot approve it",
  "sod.approver_not_payer": "Whoever approved cannot send the payment",
  "sod.requester_not_receiver": "Requester cannot confirm receipt of their own order",
  "approval.limit": "Amount within approver's limit",
  "match.po_exists": "Invoice references a valid purchase order",
  "match.vendor_matches_po": "Invoice vendor matches the purchase order",
  "match.receipt_exists": "Goods were received",
  "match.qty_within_receipt": "Billed quantity within received quantity",
  "match.price_within_tolerance": "Billed price within tolerance of order price",
  "match.amount_within_payable": "Amount to pay within matched amount",
  "contract.price": "Price within contract",
  "dup.invoice_number": "Invoice number not already billed",
  "dup.same_amount": "No identical invoice for the same order",
  "vendor.active": "Supplier is active",
  "vendor.bank_matches_master": "Bank details match the verified vendor master",
  "price.anomaly": "Price consistent with supplier history",
  "treasury.min_runway": "Cash stays above minimum runway",
  "treasury.funds_confirmed": "Funds confirmed by treasury",
  "treasury.cash_available": "Cash available",
  "payment.invoice_approved": "Invoice approved for payment",
  "payment.amount_within_approved": "Payment within approved amount",
  "payment.to_master_bank": "Payment goes to the verified bank account on file",
  "state.valid": "Record exists and is in the right state",
  "escalation.authority": "Decision made by the authority it was escalated to",
  "escalation.delivered": "Escalation has reached its recipient",
  "escalation.routing": "Escalated items are decided only by their target authority",
  "payment.po_cap": "Total paid on an order stays within the order total",
  "payment.prepay_settled": "No prepayment in flight on this order",
  "actor.authenticated": "Caller is authenticated as this actor",
  "schema.valid": "Proposal is well-formed",
  "engine.error": "Proposal could be processed",
  "verification.arrived": "Verification request has reached the remote party",
};
