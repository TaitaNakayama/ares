import type { Cents } from "./util.ts";

/** Simulated time in milliseconds. The engine never reads the wall clock. */
export type Time = number;

export const AGENT_ROLES = ["requester", "receiver", "ap", "treasury", "controller"] as const;
export type AgentRole = (typeof AGENT_ROLES)[number];
export const HUMAN_ROLES = ["local_authority", "remote_authority"] as const;
export type HumanRole = (typeof HUMAN_ROLES)[number];
export type Role = AgentRole | HumanRole | "system";

export interface Actor {
  id: string;
  role: Role;
  /** Name the world gives this actor. The engine only uses it for display. */
  displayName: string;
}

export interface BankAccount {
  holder: string;
  bank: string;
  routing: string;
  account: string;
}

export function bankKey(b: BankAccount): string {
  return `${b.bank}|${b.routing}|${b.account}`.toLowerCase();
}

export type VendorStatus = "active" | "hold" | "blocked";

export interface Vendor {
  id: string;
  name: string;
  /** Bank details on the vendor master file, verified out of band. */
  bank: BankAccount;
  bankVerifiedAt: Time;
  status: VendorStatus;
  statusReason?: string;
}

export interface Item {
  sku: string;
  name: string;
  unit: string;
}

export interface Contract {
  id: string;
  vendorId: string;
  sku: string;
  unitPrice: Cents;
  validFrom: Time;
  validTo: Time;
}

export interface PriceObservation {
  vendorId: string;
  sku: string;
  unitPrice: Cents;
  at: Time;
}

export interface Line {
  sku: string;
  qty: number;
  unitPrice: Cents;
}

export type RequisitionStatus = "open" | "approved" | "rejected" | "escalated" | "ordered" | "cancelled";

export interface Requisition {
  id: string;
  requestedBy: string;
  sku: string;
  qty: number;
  /** Latest time an order can be placed and still arrive when needed. */
  orderBy: Time;
  reason: string;
  status: RequisitionStatus;
  createdAt: Time;
  fundsConfirmedBy?: string;
  /** Free-form figures the requester attached (e.g. telemetry), shown to approvers. */
  context?: Record<string, string | number>;
}

export type PaymentTerms = "prepay" | "on_receipt";

export interface Quote {
  id: string;
  vendorId: string;
  sku: string;
  unitPrice: Cents;
  qtyAvailable: number;
  /** Bank account the quote asks payment to go to. */
  bank: BankAccount;
  terms: PaymentTerms;
  validUntil: Time;
  receivedAt: Time;
  requisitionId?: string;
  docText?: string;
  sourceRef?: string;
}

export type PoStatus = "open" | "partially_received" | "received" | "closed" | "cancelled";

export interface PurchaseOrder {
  id: string;
  requisitionId: string;
  vendorId: string;
  quoteId?: string;
  contractId?: string;
  lines: Line[];
  total: Cents;
  terms: PaymentTerms;
  status: PoStatus;
  approvedBy: string[];
  createdAt: Time;
}

export interface ReceiptLine {
  sku: string;
  qtyReceived: number;
  qtyRejected: number;
}

export interface GoodsReceipt {
  id: string;
  poId: string;
  lines: ReceiptLine[];
  receivedBy: string;
  at: Time;
  note?: string;
}

export type InvoiceStatus = "received" | "submitted" | "approved" | "held" | "rejected" | "paid";

export interface Invoice {
  id: string;
  vendorId: string;
  vendorInvoiceNo: string;
  poId?: string;
  lines: Line[];
  total: Cents;
  bank: BankAccount;
  issuedAt: Time;
  receivedAt: Time;
  dueAt: Time;
  status: InvoiceStatus;
  /** Amount AP proposed and the controller approved; can be below the billed total. */
  approvedAmount?: Cents;
  docText?: string;
  sourceRef?: string;
}

export type PaymentStatus = "scheduled" | "sent" | "cancelled";

export interface Payment {
  id: string;
  /** Invoice being paid, or for prepayment the PO. */
  invoiceId?: string;
  poId?: string;
  vendorId: string;
  amount: Cents;
  bank: BankAccount;
  status: PaymentStatus;
  approvedBy: string[];
  scheduledBy: string;
  executedBy?: string;
  createdAt: Time;
  sentAt?: Time;
}

export type VerificationStatus = "pending" | "confirmed" | "rejected";

export interface Verification {
  id: string;
  vendorId: string;
  claimedBank: BankAccount;
  /** Document that carried the new details. */
  subject: Ref;
  sentAt: Time;
  /** When the request reaches the remote party. */
  arrivesAt: Time;
  status: VerificationStatus;
  answeredAt?: Time;
  answer?: string;
}

export type RefKind = "requisition" | "quote" | "po" | "receipt" | "invoice" | "payment" | "vendor" | "verification" | "escalation" | "proposal" | "report";

/** An agent's report of something no catalog action covers; it always reaches a human. */
export interface Report {
  id: string;
  by: string;
  summary: string;
  recommendation: string;
  urgency: "low" | "normal" | "high" | "critical";
  subject?: Ref;
  at: Time;
  escalationId?: string;
}

export interface Ref {
  kind: RefKind;
  id: string;
}

export type FlagCode =
  | "price_anomaly"
  | "bank_mismatch"
  | "qty_over_receipt"
  | "price_over_po"
  | "price_over_contract"
  | "duplicate"
  | "no_po"
  | "no_receipt"
  | "vendor_not_active"
  | "contract_expired"
  | "insufficient_runway"
  | "over_authority"
  | "agent_concern";

export interface Flag {
  code: FlagCode;
  subject: Ref;
  detail: string;
  /** Amount at stake, used for "money saved" reporting. */
  amountAtRisk: Cents;
  raisedBy: string;
  at: Time;
}
