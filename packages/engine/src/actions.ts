import { z } from "zod";

/**
 * Every state change in the engine starts as one of these actions, proposed by an
 * actor. The schemas validate both deterministic and LLM proposals, and double as
 * the JSON schemas for LLM tools, so an agent's tool list is exactly its role's
 * allowed actions.
 */

const cents = z.number().int().nonnegative();
const qty = z.number().int().positive();
const time = z.number().int();

export const bankAccountSchema = z.object({
  holder: z.string().min(1),
  bank: z.string().min(1),
  routing: z.string().min(1),
  account: z.string().min(1),
});

const refSchema = z.object({
  kind: z.enum(["requisition", "quote", "po", "receipt", "invoice", "payment", "vendor", "verification", "escalation", "proposal", "report"]),
  id: z.string(),
});

const lineSchema = z.object({ sku: z.string(), qty, unitPrice: cents });

export const ACTION_SCHEMAS = {
  // requester
  create_requisition: z.object({
    sku: z.string(),
    qty,
    orderBy: time,
    reason: z.string().min(1),
    context: z.record(z.string(), z.union([z.string(), z.number()])).optional(),
  }),
  cancel_requisition: z.object({ requisitionId: z.string(), reason: z.string() }),

  // receiver
  record_receipt: z.object({
    poId: z.string(),
    lines: z.array(z.object({ sku: z.string(), qtyReceived: z.number().int().nonnegative(), qtyRejected: z.number().int().nonnegative() })).min(1),
    note: z.string().optional(),
    sourceRef: z.string().optional(),
  }),

  // ap
  record_quote: z.object({
    vendorId: z.string(),
    sku: z.string(),
    unitPrice: cents,
    qtyAvailable: qty,
    bank: bankAccountSchema,
    terms: z.enum(["prepay", "on_receipt"]),
    validUntil: time,
    requisitionId: z.string().optional(),
    sourceRef: z.string().optional(),
  }),
  record_invoice: z.object({
    vendorId: z.string(),
    vendorInvoiceNo: z.string(),
    poId: z.string().optional(),
    lines: z.array(lineSchema).min(1),
    bank: bankAccountSchema,
    issuedAt: time,
    dueAt: time,
    sourceRef: z.string().optional(),
  }),
  submit_invoice: z.object({ invoiceId: z.string(), amount: cents, note: z.string().optional() }),
  raise_flag: z.object({ subject: refSchema, detail: z.string() }),

  // treasury
  confirm_funds: z.object({ requisitionId: z.string() }),
  schedule_payment: z.object({ invoiceId: z.string().optional(), poId: z.string().optional(), amount: cents }),
  execute_payment: z.object({ paymentId: z.string() }),

  // controller
  approve_requisition: z.object({ requisitionId: z.string(), quoteId: z.string(), qty: qty.optional() }),
  reject_requisition: z.object({ requisitionId: z.string(), reason: z.string() }),
  approve_invoice: z.object({ invoiceId: z.string() }),
  reject_invoice: z.object({ invoiceId: z.string(), reason: z.string() }),
  reject_quote: z.object({ quoteId: z.string(), reason: z.string() }),
  hold_vendor: z.object({ vendorId: z.string(), reason: z.string() }),
  block_vendor: z.object({ vendorId: z.string(), reason: z.string() }),
  release_vendor: z.object({ vendorId: z.string(), reason: z.string() }),
  request_verification: z.object({ vendorId: z.string(), subject: refSchema }),
  escalate: z.object({ subject: refSchema, reason: z.string() }),

  // any agent: something no catalog action covers (safety, an item we don't stock, a judgment call).
  // It always becomes an escalation to the local human authority.
  report_issue: z.object({
    summary: z.string().min(1).max(400),
    recommendation: z.string().min(1).max(400),
    urgency: z.enum(["low", "normal", "high", "critical"]),
    subject: refSchema.optional(),
  }),

  // humans
  decide: z.object({ escalationId: z.string(), optionId: z.string() }),
  answer_verification: z.object({ verificationId: z.string(), confirmed: z.boolean(), answer: z.string() }),
} as const;

export type ActionType = keyof typeof ACTION_SCHEMAS;
export const ACTION_TYPES = Object.keys(ACTION_SCHEMAS) as ActionType[];
export type ActionParams<T extends ActionType> = z.infer<(typeof ACTION_SCHEMAS)[T]>;

export type Action = { [T in ActionType]: { type: T; params: ActionParams<T> } }[ActionType];

export function parseAction(type: string, params: unknown): { ok: true; action: Action } | { ok: false; error: string } {
  if (typeof type !== "string" || !Object.hasOwn(ACTION_SCHEMAS, type)) return { ok: false, error: `unknown action "${String(type)}"` };
  const res = ACTION_SCHEMAS[type as ActionType].safeParse(params);
  if (!res.success) return { ok: false, error: res.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") };
  return { ok: true, action: { type, params: res.data } as Action };
}

/** Plain-language description of each action, used for LLM tool descriptions and the console. */
export const ACTION_DESCRIPTIONS: Record<ActionType, string> = {
  create_requisition: "Request a purchase of an item: quantity, the latest time the order can be placed, and why it is needed.",
  cancel_requisition: "Withdraw a purchase request you made.",
  record_receipt: "Record what physically arrived against a purchase order: quantity received and quantity rejected (damaged/wrong) per item.",
  record_quote: "Enter a supplier quote from a received document into the system, exactly as the document states.",
  record_invoice: "Enter a supplier invoice from a received document into the system, exactly as the document states.",
  submit_invoice: "Submit a recorded invoice for payment approval, proposing the amount that should be paid after matching it against the order and the receipt.",
  raise_flag: "Raise a concern about a document or record for the controller to review.",
  report_issue: "Report something no other action covers (a safety problem, an item not in the catalog, a judgment call) to the human in charge, with a recommendation. Always reaches a human.",
  confirm_funds: "Confirm that cash can cover a purchase request without breaking the minimum cash runway.",
  schedule_payment: "Schedule a payment for an approved invoice (or an approved prepaid order).",
  execute_payment: "Send a scheduled payment.",
  approve_requisition: "Approve a purchase request with a specific quote, which issues a purchase order.",
  reject_requisition: "Reject a purchase request.",
  approve_invoice: "Approve a submitted invoice for payment at the submitted amount.",
  reject_invoice: "Reject an invoice so it is never paid.",
  reject_quote: "Reject a quote so it can never be used for an order.",
  hold_vendor: "Put a supplier on hold: no new orders or payments until released.",
  block_vendor: "Block a supplier permanently: no orders or payments.",
  release_vendor: "Release a supplier from hold after its details on file were re-verified out of band.",
  request_verification: "Ask the remote authority to verify a supplier's changed bank details out of band (call-back on file).",
  escalate: "Escalate a decision to a human authority with the reason.",
  decide: "Choose one option of an escalation.",
  answer_verification: "Report the result of an out-of-band verification.",
};
