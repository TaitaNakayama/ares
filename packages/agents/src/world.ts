import type { BankAccount, EngineConfig, EngineEvent, Engine, PaymentTerms, ReceiptLine, Time, Line } from "@ares/engine";

/**
 * A world is a swappable simulation that feeds the engine. It owns everything
 * domain-specific (names, physics, story) and the answer key; the engine never sees it.
 */

export interface DocumentFields {
  quote?: {
    vendorId: string;
    sku: string;
    unitPrice: number;
    qtyAvailable: number;
    bank: BankAccount;
    terms: PaymentTerms;
    validUntil: Time;
    requisitionId?: string;
  };
  invoice?: {
    vendorId: string;
    vendorInvoiceNo: string;
    poId?: string;
    lines: Line[];
    bank: BankAccount;
    issuedAt: Time;
    dueAt: Time;
  };
}

export type WorldEvent =
  | { type: "need"; sku: string; qty: number; orderBy: Time; reason: string; context?: Record<string, string | number> }
  /** A document arrives (quote or invoice). `text` is what a person would read; `fields` is what is printed on it. */
  | { type: "document"; doc: { id: string; kind: "quote" | "invoice"; from: string; text: string; fields: DocumentFields } }
  | { type: "delivery"; poId: string; lines: ReceiptLine[]; note: string; docId?: string }
  | { type: "rfq_closed"; requisitionId: string }
  /** Simulated outside party acting through the engine (e.g. remote authority answering). */
  | { type: "external"; actorId: string; action: string; params: unknown; summary: string }
  | { type: "telemetry"; data: Record<string, unknown> }
  | { type: "narration"; agentRole: string; text: string; mood?: Mood };

export type Mood = "calm" | "worried" | "suspicious" | "attentive" | "happy";

export interface ScheduledWorldEvent {
  at: Time;
  event: WorldEvent;
}

export interface WorldSetup {
  config: EngineConfig;
  /** World-specific info for clients (names, base stats, credits). */
  meta: Record<string, unknown>;
}

export interface World {
  readonly id: string;
  readonly seed: string;
  setup(): WorldSetup;
  /** Events the world wants delivered right at the start. */
  initialEvents(engine: Engine): ScheduledWorldEvent[];
  /** React to something the engine did (e.g. send quotes after a request, ship goods after a PO). */
  onEngineEvent(e: EngineEvent, engine: Engine): ScheduledWorldEvent[];
  /** Called as simulated time advances; return telemetry or other time-driven events. */
  onTime?(t: Time, engine: Engine): ScheduledWorldEvent[];
}
