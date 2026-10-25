import { Rng, type BankAccount, type Contract, type Item, type PriceObservation, type Vendor } from "@ares/engine";

/**
 * Freight to the Mars surface, $/kg: a planning assumption for a cargo-ship era (SIMULATED).
 * The 2017 Falcon Heavy expendable list price (US$150M / 16.8 t, about $8,900/kg) made one battery
 * module cost ~$735k delivered, which no judge believes for emergency batteries. Everything here is SIMULATED.
 */
export const FREIGHT_USD_PER_KG = 400;

export interface CatalogItem extends Item {
  massKg: number;
  /** Earth list price in USD before freight (SIMULATED). */
  earthUsd: number;
  category: "power" | "life" | "mining" | "medical" | "spares";
}

export const CATALOG: CatalogItem[] = [
  { sku: "BAT-10", name: "battery modules (10 kWh)", unit: "module", massKg: 75, earthUsd: 8_000, category: "power" },
  { sku: "FLT-HEPA", name: "air filters", unit: "cartridge", massKg: 2, earthUsd: 400, category: "life" },
  { sku: "WTR-CART", name: "water recycler cartridges", unit: "cartridge", massKg: 6, earthUsd: 1_200, category: "life" },
  // 30 crew-days of food at 1.51 kg/crew-day (NASA BVAD Rev1, Table 3-33).
  { sku: "FOOD-30", name: "food packs (30 crew-days)", unit: "pack", massKg: 45.3, earthUsd: 3_000, category: "life" },
  { sku: "CO2-SCR", name: "CO2 scrubber canisters", unit: "canister", massKg: 8, earthUsd: 2_500, category: "life" },
  { sku: "DRL-BIT", name: "ice drill bits", unit: "bit", massKg: 12, earthUsd: 8_000, category: "mining" },
  { sku: "MED-KIT", name: "medical resupply kits", unit: "kit", massKg: 10, earthUsd: 5_000, category: "medical" },
  { sku: "SEAL-KIT", name: "seal and gasket kits", unit: "kit", massKg: 3, earthUsd: 900, category: "spares" },
];

/** Delivered-to-Mars unit price in cents. */
export function deliveredCents(item: CatalogItem): number {
  return Math.round((item.earthUsd + item.massKg * FREIGHT_USD_PER_KG) * 100);
}

const PREFIX = ["Hadley", "Ridgeline", "Tharsis", "Kestrel", "Polaris", "Arcadia", "Meridian", "Bluestone", "Copperleaf", "Northgate", "Halcyon", "Ironwood", "Lumen", "Vantage", "Cobalt", "Juniper", "Sable", "Granite", "Orbitline", "Westfall"];
const SUFFIX: Record<CatalogItem["category"], string[]> = {
  power: ["Power Systems", "Energy Storage", "Electric"],
  life: ["Life Support", "Filtration", "Provisions"],
  mining: ["Drill Works", "Mining Supply", "Industrial"],
  medical: ["Medical", "Health Supply"],
  spares: ["Components", "Parts Co", "Supply Co"],
};
const BANKS = ["First Federal Bank", "Pacific Trust", "Lakeside Bank", "Union Mercantile", "Harbor Savings", "Granite State Bank", "Coastal Credit Union"];
const FRAUD_BANKS = ["Swiftline Digital Bank", "NeoPay Bank", "Quantum Trust", "Crestmark Online"];

export function randomBank(rng: Rng, holder: string, fraud = false): BankAccount {
  const digits = (n: number) => Array.from({ length: n }, () => rng.int(0, 9)).join("");
  return { holder, bank: rng.pick(fraud ? FRAUD_BANKS : BANKS), routing: digits(9), account: digits(rng.int(10, 12)) };
}

export interface GeneratedMarket {
  vendors: Vendor[];
  contracts: Contract[];
  history: PriceObservation[];
  /** vendorId -> sku -> typical unit price (cents) */
  basePrice: Map<string, Map<string, number>>;
  /** sku -> vendor ids that sell it */
  sellers: Map<string, string[]>;
}

export function generateMarket(rng: Rng, start: number): GeneratedMarket {
  const DAY = 86_400_000;
  const vendors: Vendor[] = [];
  const contracts: Contract[] = [];
  const history: PriceObservation[] = [];
  const basePrice = new Map<string, Map<string, number>>();
  const sellers = new Map<string, string[]>();
  const usedNames = new Set<string>();
  const byCategory = new Map<CatalogItem["category"], string[]>();

  // 2-3 vendors per category; each sells every item in its category.
  for (const cat of ["power", "life", "mining", "medical", "spares"] as const) {
    const n = cat === "power" || cat === "life" ? 3 : 2;
    const ids: string[] = [];
    for (let i = 0; i < n; i++) {
      let name = "";
      do name = `${rng.pick(PREFIX)} ${rng.pick(SUFFIX[cat])}`;
      while (usedNames.has(name));
      usedNames.add(name);
      const id = `V-${String(vendors.length + 1).padStart(2, "0")}`;
      vendors.push({ id, name, bank: randomBank(rng, name), bankVerifiedAt: start - rng.int(200, 900) * DAY, status: "active" });
      basePrice.set(id, new Map());
      ids.push(id);
    }
    byCategory.set(cat, ids);
  }

  for (const item of CATALOG) {
    const ids = byCategory.get(item.category) ?? [];
    sellers.set(item.sku, ids);
    for (const vid of ids) {
      const factor = 0.93 + rng.next() * 0.17;
      const p = Math.round(deliveredCents(item) * factor);
      basePrice.get(vid)!.set(item.sku, p);
      // Realistic history: ~3% noise and a slow inflation drift (older prices lower).
      const n = rng.int(6, 12);
      const drift = 0.01 + rng.next() * 0.03; // 1-4% per year
      for (let k = 0; k < n; k++) {
        const ageDays = (k + 1) * rng.int(30, 70);
        const trend = 1 - drift * (ageDays / 365);
        history.push({ vendorId: vid, sku: item.sku, unitPrice: Math.round(p * trend * (1 + rng.normal(0, 0.03))), at: start - ageDays * DAY });
      }
      if (rng.chance(0.4)) {
        contracts.push({ id: `C-${contracts.length + 101}`, vendorId: vid, sku: item.sku, unitPrice: Math.round(p * 1.01), validFrom: start - 300 * DAY, validTo: start + 400 * DAY });
      }
    }
  }
  return { vendors, contracts, history, basePrice, sellers };
}
