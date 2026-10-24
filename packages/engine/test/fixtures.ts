import { DEFAULT_POLICY, Engine, type Actor, type BankAccount, type EngineConfig, type Policy, type PriceObservation } from "../src/index.ts";

export const HOUR = 3_600_000;
export const DAY = 24 * HOUR;
export const T0 = Date.UTC(2030, 0, 1);

export const bankA: BankAccount = { holder: "Alpha Supply Co", bank: "First Bank", routing: "111000111", account: "000123456789" };
export const bankAFake: BankAccount = { holder: "Alpha Supply Co", bank: "Quick Bank", routing: "999000999", account: "555566667777" };
export const bankB: BankAccount = { holder: "Beta Parts Ltd", bank: "Second Bank", routing: "222000222", account: "000987654321" };

export const ACTORS: Actor[] = [
  { id: "req", role: "requester", displayName: "Requester" },
  { id: "rcv", role: "receiver", displayName: "Receiver" },
  { id: "ap", role: "ap", displayName: "AP clerk" },
  { id: "tre", role: "treasury", displayName: "Treasurer" },
  { id: "ctl", role: "controller", displayName: "Controller" },
  { id: "loc", role: "local_authority", displayName: "Site manager" },
  { id: "rem", role: "remote_authority", displayName: "CFO" },
];

export function history(vendorId: string, sku: string, price: number, n = 8): PriceObservation[] {
  return Array.from({ length: n }, (_, i) => ({ vendorId, sku, unitPrice: Math.round(price * (1 + ((i % 3) - 1) * 0.01)), at: T0 - (i + 1) * 30 * DAY }));
}

export function makeEngine(overrides: Partial<EngineConfig> = {}, policy: Partial<Policy> = {}): Engine {
  return new Engine({
    policy: { ...DEFAULT_POLICY, ...policy },
    actors: ACTORS,
    vendors: [
      { id: "V-A", name: "Alpha Supply Co", bank: bankA, bankVerifiedAt: T0 - 400 * DAY, status: "active" },
      { id: "V-B", name: "Beta Parts Ltd", bank: bankB, bankVerifiedAt: T0 - 400 * DAY, status: "active" },
    ],
    items: [
      { sku: "FLT", name: "Air filter", unit: "ea" },
      { sku: "BAT", name: "Battery module", unit: "ea" },
    ],
    contracts: [{ id: "C-1", vendorId: "V-A", sku: "FLT", unitPrice: 12_000, validFrom: T0 - 365 * DAY, validTo: T0 + 365 * DAY }],
    priceHistory: [...history("V-A", "FLT", 12_000), ...history("V-A", "BAT", 80_000), ...history("V-B", "BAT", 95_000)],
    openingCash: 50_000_000,
    burnPerDayCents: 100_000,
    startTime: T0,
    remoteLatencyMs: 12.5 * 60_000,
    levers: [{ id: "shed", label: "Shed load", detail: "Turn off a non-essential load", appliesToSkus: ["BAT"] }],
    ...overrides,
  });
}

/** Runs a requisition through funds check and quote intake; returns ids. */
export function requisitionWithQuotes(
  e: Engine,
  sku: string,
  qty: number,
  quotes: { vendorId: string; unitPrice: number; qtyAvailable: number; bank: BankAccount; terms?: "prepay" | "on_receipt" }[],
  orderBy = T0 + 30 * DAY,
) {
  const r = e.submit({ actorId: "req", type: "create_requisition", params: { sku, qty, orderBy, reason: "needed" } });
  const reqId = r.created!.id;
  e.submit({ actorId: "tre", type: "confirm_funds", params: { requisitionId: reqId } });
  const quoteIds = quotes.map((q) => {
    const res = e.submit({
      actorId: "ap",
      type: "record_quote",
      params: { vendorId: q.vendorId, sku, unitPrice: q.unitPrice, qtyAvailable: q.qtyAvailable, bank: q.bank, terms: q.terms ?? "on_receipt", validUntil: T0 + 60 * DAY, requisitionId: reqId },
    });
    return res.created!.id;
  });
  return { reqId, quoteIds };
}
