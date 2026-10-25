import type { ScheduledWorldEvent, World, WorldEvent, WorldSetup } from "@ares/agents";
import { bankKey, DEFAULT_POLICY, formatCents, Rng, type Actor, type BankAccount, type Engine, type EngineEvent, type Lever, type Policy, type Time, type Vendor } from "@ares/engine";
import { CATALOG, deliveredCents, FREIGHT_USD_PER_KG, generateMarket, randomBank, type GeneratedMarket } from "./catalog.ts";
import { earthMarsDistanceAu, fmtLtst, lightTimeMs, marsSun } from "./mars-time.ts";
import { OPPORTUNITY_POINTS, PowerModel } from "./power.ts";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/**
 * The real Perseverance close-up the scientist's view shows (credited on screen). Filled from CREDITS.md
 * once the imagery is sourced; until then the lines avoid the specific numbers.
 */
export const SCIENCE_REF: { scientist: string; instrument: string; sol?: number; target?: string; credit: string; image?: string; source?: string; caption: string } = {
  scientist: "Science Officer Okonkwo",
  instrument: "the WATSON camera",
  sol: 1526,
  target: "Kenmore",
  credit: "NASA/JPL-Caltech/MSSS",
  image: "perseverance-sol1526-watson-kenmore.jpg",
  source: "NASA/JPL PIA26576",
  caption: "Perseverance, SHERLOC WATSON camera: abrasion patch \"Kenmore\", sol 1526 (2025-06-05). Credit NASA/JPL-Caltech/MSSS, PIA26576.",
};

/** Octavia E. Butler Landing, Jezero crater (research/03). */
export const SITE = { lat: 18.4446, lonE: 77.4509, name: "Jezero Crater, near Octavia E. Butler Landing" };
/** Base founding date used for sol numbering (SIMULATED): the scene's date is the base's sol 214. */
const BASE_EPOCH = Date.UTC(2026, 2, 18);

/**
 * The crew. Engineer, Life and Science are world agents (power, life support, the lab) that may also
 * request purchases. Supply is one face for three separate engine actors (receiving, bills, payments), so
 * segregation of duties holds in the engine. Rules is the controller.
 */
export const MARS_ACTORS: Actor[] = [
  { id: "engineer", role: "requester", displayName: "Engineer" },
  { id: "life", role: "requester", displayName: "Life" },
  { id: "science", role: "requester", displayName: "Science" },
  { id: "cargo", role: "receiver", displayName: "Supply" },
  { id: "bills", role: "ap", displayName: "Supply" },
  { id: "money", role: "treasury", displayName: "Supply" },
  { id: "rules", role: "controller", displayName: "Rules" },
  { id: "commander", role: "local_authority", displayName: "Commander" },
  { id: "cfo", role: "remote_authority", displayName: "Earth CFO" },
];

export type CrewId = "engineer" | "life" | "science" | "supply" | "rules";

/** Crew identity for clients: who is who, which engine actors each crew member speaks for, and the role label the console shows. */
export const CREW: Record<CrewId, { name: string; color: string; icon: string; job: string; actors: Record<string, string> }> = {
  engineer: { name: "Engineer", color: "#4DA3FF", icon: "wrench", job: "Power, solar panels, the ice drill, machines", actors: { engineer: "Requests" } },
  life: { name: "Life", color: "#F2F4F7", icon: "droplet", job: "Oxygen, water, crew health", actors: { life: "Requests" } },
  science: { name: "Science", color: "#3BD16F", icon: "microscope", job: "Samples and research", actors: { science: "Requests" } },
  supply: { name: "Supply", color: "#FF9A3C", icon: "box", job: "Cargo, orders, bills, payments", actors: { cargo: "Receiving", bills: "Bills", money: "Payments" } },
  rules: { name: "Rules", color: "#A97BFF", icon: "shield", job: "Approves spending, catches scams, decides what reaches the commander", actors: { rules: "Controller" } },
};

/** Which crew member speaks for an engine actor. */
export function crewOf(actorId: string): CrewId | undefined {
  return (Object.keys(CREW) as CrewId[]).find((c) => actorId in CREW[c].actors);
}

export const MARS_POLICY: Policy = {
  ...DEFAULT_POLICY,
  name: "Ares Base P2P controls",
  version: 1,
  // Limits scaled with the cargo-era freight assumption (SIMULATED): Rules $125k, the commander $600k, Earth $25M.
  approval: { agentMaxCents: 12_500_000, localAuthorityMaxCents: 60_000_000, remoteAuthorityMaxCents: 2_500_000_000, splitWindowDays: 7 },
  match: { priceTolerancePct: 2, payReceivedQtyOnly: true },
  // Earth's call-back answer comes back after the light-time round trip (the demo world adds no processing time).
  vendorBankChange: { action: "hold_and_verify", verificationProcessingMs: 0 },
  duplicates: { windowDays: 120 },
  priceAnomaly: { zThreshold: 4, ratioThreshold: 1.35, minHistory: 4 },
  materialityCents: 500_000,
  treasury: { minRunwayDays: 120 },
};

export type ErrorType = "duplicate_invoice" | "bank_fraud_invoice" | "bank_fraud_quote" | "inflated_quote" | "subtle_inflated_quote" | "inflated_invoice" | "short_delivery" | "over_contract_quote";
export type DecoyType = "legit_bank_change" | "small_price_rise" | "damaged_rejected" | "genuine_after_fraud";

export interface ErrorRates {
  duplicate_invoice: number;
  bank_fraud_invoice: number;
  bank_fraud_quote: number;
  inflated_quote: number;
  inflated_invoice: number;
  short_delivery: number;
  over_contract_quote: number;
  /** +3-7% over the supplier's usual price: at the edge of what statistics can separate from drift. */
  subtle_inflated_quote: number;
  legit_bank_change: number;
  small_price_rise: number;
  damaged_rejected: number;
}

export const DEFAULT_RATES: ErrorRates = {
  duplicate_invoice: 0.06,
  bank_fraud_invoice: 0.05,
  bank_fraud_quote: 0.05,
  inflated_quote: 0.06,
  inflated_invoice: 0.06,
  short_delivery: 0.1,
  over_contract_quote: 0.05,
  subtle_inflated_quote: 0.06,
  legit_bank_change: 0.05,
  small_price_rise: 0.15,
  damaged_rejected: 0.06,
};

/** Ground truth for one planted document. Never shown to the engine. */
export interface AnswerKeyEntry {
  docId: string;
  cycle: number;
  kind: "quote" | "invoice" | "delivery";
  errors: ErrorType[];
  decoys: DecoyType[];
  vendorId: string;
  /** What a correct process pays for this document (0 for fraud/duplicates). */
  fairCents: number;
  /** What the document asks for. */
  billedCents: number;
  /** For quotes: should a PO ever be issued on it? */
  shouldOrder?: boolean;
  requisitionId?: string;
}

interface CycleState {
  cycle: number;
  sku: string;
  qty: number;
  requisitionId?: string;
  planned: { quotes: PlannedQuote[]; delivery: { short: number; damaged: number }; invoice: PlannedInvoice };
}
interface PlannedQuote {
  vendorId: string;
  unitPrice: number;
  qtyAvailable: number;
  bank: BankAccount;
  terms: "prepay" | "on_receipt";
  errors: ErrorType[];
  decoys: DecoyType[];
  legitNewBank?: BankAccount;
}
interface PlannedInvoice {
  priceFactor: number;
  fraudBank: boolean;
  duplicate: boolean;
  errors: ErrorType[];
  decoys: DecoyType[];
}

export interface MarsWorldOptions {
  seed: string;
  mode: "demo" | "eval";
  start?: Time;
  cycles?: number;
  rates?: Partial<ErrorRates>;
  policy?: Policy;
}

export class MarsWorld implements World {
  readonly id = "mars";
  readonly seed: string;
  readonly mode: "demo" | "eval";
  readonly start: Time;
  readonly market: GeneratedMarket;
  readonly answerKey: AnswerKeyEntry[] = [];
  readonly power: PowerModel;
  private readonly rng: Rng;
  private readonly rates: ErrorRates;
  private readonly policy: Policy;
  private readonly cycles: CycleState[] = [];
  private readonly reqToCycle = new Map<string, CycleState>();
  private readonly poToCycle = new Map<string, CycleState>();
  /** Truth about pending bank changes: account key -> is it legitimate? */
  private readonly bankTruth = new Map<string, boolean>();
  private docSeq = 0;
  private lastPowerT: Time;
  private lastTelemetryT = -Infinity;
  // Demo state
  /** Two-part demo: the judge starts outside (landing pad -> science site -> solar field -> door), then goes inside. */
  part: "outside" | "inside" = "outside";
  station: "pad" | "science" | "solar" | "rover" | "door" | undefined;
  /** Stations whose content has run (free roam runs each once, in the judge's order). */
  readonly visited = new Set<string>();
  private stormWarned = false;
  tau = 0.6;
  private stormFrom?: { t: Time; tau0: number; tau1: number; durMs: number };
  beat = 0;
  readonly cyclesTotal: number;

  constructor(opts: MarsWorldOptions) {
    this.seed = opts.seed;
    this.mode = opts.mode;
    this.start = opts.start ?? Date.UTC(2026, 9, 24, 3, 0);
    this.rng = new Rng(`mars:${opts.seed}`);
    this.rates = { ...DEFAULT_RATES, ...opts.rates };
    this.policy = opts.policy ?? MARS_POLICY;
    this.market = generateMarket(this.rng.fork("market"), this.start);
    this.cyclesTotal = opts.cycles ?? 40;
    // Loads (SIMULATED): life support (the oxygen makers, water recycling, heat) 12 kW, the ice drill 5 kW, the lab 4 kW (freezers, instruments).
    this.power = new PowerModel({ arrayScale: 934, capacityKWh: 1600, socFraction: 0.85, loads: { lifeSupport: 12, iceDrill: 5, science: 4 } });
    this.lastPowerT = this.mode === "demo" ? this.start - 32 * DAY : this.start;
    for (const v of this.market.vendors) this.bankTruth.set(bankKey(v.bank), true);
  }

  setup(): WorldSetup {
    return {
      config: {
        policy: this.policy,
        actors: MARS_ACTORS,
        vendors: this.market.vendors,
        items: CATALOG.map(({ sku, name, unit }) => ({ sku, name, unit })),
        contracts: this.market.contracts,
        priceHistory: this.market.history,
        openingCash: 900_000_000,
        burnPerDayCents: 3_000_000,
        // The demo starts a month early so the routine filter order (the prologue) really happens in sim time.
        startTime: this.mode === "demo" ? this.start - 32 * DAY : this.start,
        remoteLatencyMs: lightTimeMs(this.start),
        levers: [this.drillLever(), this.labLever()],
      },
      meta: {
        world: "mars",
        seed: this.seed,
        mode: this.mode,
        site: SITE,
        start: this.start,
        freightUsdPerKg: Math.round(FREIGHT_USD_PER_KG),
        credits: [
          "Terrain: NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX); USGS Astrogeology Mars 2020 TRN products",
          "Sun: Mars24, NASA GISS (Allison & McEwen 2000)",
          "Earth-Mars distance: astronomy-engine (MIT), checked against JPL Horizons",
          "Solar power vs dust: Opportunity 2018 storm, JPL mission updates",
          "Crew consumables: NASA BVAD Rev1 (2018)",
          "Freight: $400/kg to the surface, a cargo-ship-era planning assumption (SIMULATED)",
          "Suppliers, prices, budget, invoices: SIMULATED",
        ],
        powerCalibration: OPPORTUNITY_POINTS,
      },
    };
  }

  // ---------------------------------------------------------------- time & physics

  /** Local sol number since the base was founded; rolls over at local mean midnight at Jezero. */
  sol(t: Time): number {
    const local = (x: Time) => marsSun(x, SITE.lat, SITE.lonE).msd + SITE.lonE / 360;
    return Math.floor(local(t)) - Math.floor(local(BASE_EPOCH));
  }

  fmtTime = (t: Time): string => {
    const s = marsSun(t, SITE.lat, SITE.lonE);
    return `Sol ${this.sol(t)} ${fmtLtst(s.ltst)}`;
  };

  private tauAt(t: Time): number {
    const st = this.stormFrom;
    if (!st || t < st.t) return this.tau;
    const f = Math.min(1, (t - st.t) / st.durMs);
    return st.tau0 + (st.tau1 - st.tau0) * (1 - Math.cos(Math.PI * f)) / 2;
  }

  private drillLever(): Lever {
    const tau = this.tauAt(this.lastPowerT);
    const st = this.power.state(tau);
    const saved = this.power.loads.iceDrill * 24.6597;
    const net = st.solarKWhPerSol - st.loadKWhPerSol;
    const after = net + saved >= 0 ? "no deficit" : `${(st.socKWh / -(net + saved)).toFixed(1)} sols`;
    return {
      id: "drill_off",
      label: "Shut down the ice drill",
      detail: `Saves about ${Math.round(saved)} kWh per sol (ESTIMATE). Water production pauses. Reserve goes from ${Number.isFinite(st.solsLeft) ? `${st.solsLeft.toFixed(1)} sols` : "no deficit"} to ${after}.`,
      appliesToSkus: ["BAT-10"],
    };
  }

  telemetry(t: Time, engine: Engine): Record<string, unknown> {
    const tau = this.tauAt(t);
    const p = this.power.state(tau);
    const sun = marsSun(t, SITE.lat, SITE.lonE);
    return {
      sol: this.sol(t),
      ltst: fmtLtst(sun.ltst),
      sun: { elevation: sun.elevation, azimuth: sun.azimuth, ls: sun.ls },
      tau,
      solarKWhPerSol: p.solarKWhPerSol,
      loadKWhPerSol: p.loadKWhPerSol,
      socKWh: p.socKWh,
      socPct: (100 * p.socKWh) / p.capacityKWh,
      solsLeft: Number.isFinite(p.solsLeft) ? p.solsLeft : null,
      drillOn: p.drillOn,
      base: this.baseState(t),
      lightTimeMin: lightTimeMs(t) / MIN,
      earthDistanceAu: earthMarsDistanceAu(t),
      cash: engine.ledger.balance("cash"),
      runwayDays: engine.runwayDays(),
      preventedTotal: engine.prevented.reduce((s, x) => s + x.amount, 0),
      beat: this.beat,
    };
  }

  onTime(t: Time, engine: Engine): ScheduledWorldEvent[] {
    if (t > this.lastPowerT) {
      this.power.step(t - this.lastPowerT, this.tauAt(t));
      this.lastPowerT = t;
    }
    engine.setRemoteLatency(lightTimeMs(t));
    if (t - this.lastTelemetryT < (this.mode === "demo" ? 0 : 6 * HOUR)) return [];
    this.lastTelemetryT = t;
    return [{ at: t, event: { type: "telemetry", data: this.telemetry(t, engine) } }];
  }

  // ---------------------------------------------------------------- documents

  private docId(prefix: string): string {
    return `${prefix}-${this.seed}-${String(++this.docSeq).padStart(4, "0")}`;
  }

  private quoteDoc(engine: Engine, reqId: string, q: PlannedQuote, cycle: number): WorldEvent {
    const v = engine.vendors.get(q.vendorId) ?? this.market.vendors.find((x) => x.id === q.vendorId)!;
    const item = CATALOG.find((i) => i.sku === this.cycleOf(reqId)?.sku)!;
    const id = this.docId("DOC-Q");
    const validUntil = engine.now + 10 * DAY;
    const bankLine = `Remit to: ${q.bank.holder}, ${q.bank.bank}, routing ${q.bank.routing}, account ${q.bank.account}`;
    const changed = q.bank.account !== v.bank.account;
    const text = [
      `QUOTATION from ${v.name}`,
      `Re: your request ${reqId}`,
      `${item.name}: ${q.qtyAvailable} available at ${formatCents(q.unitPrice)} per ${item.unit}, delivered to the Jezero cargo manifest.`,
      `Terms: ${q.terms === "prepay" ? "100% prepayment to secure manifest space" : "net 30 after delivery"}.`,
      changed ? "Please note our banking details have changed; update your records and use the account below." : "",
      bankLine,
      `Valid until ${new Date(validUntil).toISOString().slice(0, 10)}.`,
    ]
      .filter(Boolean)
      .join("\n");
    const total = q.unitPrice * Math.min(q.qtyAvailable, this.cycleOf(reqId)?.qty ?? q.qtyAvailable);
    this.answerKey.push({
      docId: id,
      cycle,
      kind: "quote",
      errors: q.errors,
      decoys: q.decoys,
      vendorId: q.vendorId,
      fairCents: q.errors.length ? 0 : total,
      billedCents: total,
      shouldOrder: q.errors.length === 0,
      requisitionId: reqId,
    });
    return {
      type: "document",
      doc: { id, kind: "quote", from: v.name, text, fields: { quote: { vendorId: q.vendorId, sku: item.sku, unitPrice: q.unitPrice, qtyAvailable: q.qtyAvailable, bank: q.bank, terms: q.terms, validUntil, requisitionId: reqId } } },
    };
  }

  private invoiceDoc(engine: Engine, poId: string, cs: CycleState, opts: { bank: BankAccount; unitPrice: number; qty: number; no: string; errors: ErrorType[]; decoys: DecoyType[]; fair: number }): WorldEvent {
    const po = engine.pos.get(poId)!;
    const v = engine.vendors.get(po.vendorId)!;
    const item = CATALOG.find((i) => i.sku === cs.sku)!;
    const id = this.docId("DOC-I");
    const total = opts.qty * opts.unitPrice;
    const text = [
      `INVOICE ${opts.no} from ${v.name}`,
      `Purchase order: ${poId}`,
      `${opts.qty} x ${item.name} @ ${formatCents(opts.unitPrice)} = ${formatCents(total)}`,
      `Payment due in 30 days to: ${opts.bank.holder}, ${opts.bank.bank}, routing ${opts.bank.routing}, account ${opts.bank.account}`,
    ].join("\n");
    this.answerKey.push({ docId: id, cycle: cs.cycle, kind: "invoice", errors: opts.errors, decoys: opts.decoys, vendorId: v.id, fairCents: opts.fair, billedCents: total });
    return {
      type: "document",
      doc: { id, kind: "invoice", from: v.name, text, fields: { invoice: { vendorId: v.id, vendorInvoiceNo: opts.no, poId, lines: [{ sku: cs.sku, qty: opts.qty, unitPrice: opts.unitPrice }], bank: opts.bank, issuedAt: engine.now, dueAt: engine.now + 30 * DAY } } },
    };
  }

  private cycleOf(reqId: string): CycleState | undefined {
    return this.reqToCycle.get(reqId);
  }

  // ---------------------------------------------------------------- planning (eval)

  private planCycle(i: number, rng: Rng): CycleState {
    const item = rng.pick(CATALOG);
    const sellers = this.market.sellers.get(item.sku) ?? [];
    const qty = item.sku === "BAT-10" ? rng.int(2, 6) : rng.int(5, 40);
    const r = this.rates;
    const quotes: PlannedQuote[] = rng.shuffle(sellers).slice(0, Math.max(2, Math.min(3, sellers.length))).map((vid) => {
      const v = this.market.vendors.find((x) => x.id === vid)!;
      const base = this.market.basePrice.get(vid)!.get(item.sku)!;
      return { vendorId: vid, unitPrice: Math.round(base * (1 + rng.normal(0, 0.006))), qtyAvailable: qty + rng.int(0, 20), bank: v.bank, terms: "on_receipt" as const, errors: [], decoys: [] };
    });
    // Plant at most one quote problem per cycle, on the quote that would otherwise win.
    const target = quotes.reduce((a, b) => (a.unitPrice <= b.unitPrice ? a : b));
    const roll = rng.next();
    let acc = 0;
    const pickQuote = (p: number) => {
      acc += p;
      return roll < acc;
    };
    if (pickQuote(r.bank_fraud_quote)) {
      target.bank = randomBank(rng, target.bank.holder, true);
      target.unitPrice = Math.round(target.unitPrice * 0.97);
      target.terms = "prepay";
      target.errors.push("bank_fraud_quote");
    } else if (pickQuote(r.inflated_quote)) {
      target.unitPrice = Math.round(target.unitPrice * (1.5 + rng.next() * 2));
      target.errors.push("inflated_quote");
      for (const q of quotes) if (q !== target) q.qtyAvailable = Math.max(1, Math.floor(qty / 2)); // others can't cover it
    } else if (pickQuote(r.subtle_inflated_quote)) {
      target.unitPrice = Math.round(target.unitPrice * (1.03 + rng.next() * 0.04));
      target.errors.push("subtle_inflated_quote");
      for (const q of quotes) if (q !== target) q.qtyAvailable = Math.max(1, Math.floor(qty / 2)); // force a real decision
    } else if (pickQuote(r.over_contract_quote) && this.market.contracts.some((c) => c.vendorId === target.vendorId && c.sku === item.sku)) {
      const c = this.market.contracts.find((x) => x.vendorId === target.vendorId && x.sku === item.sku)!;
      target.unitPrice = Math.round(c.unitPrice * (1.06 + rng.next() * 0.1));
      target.errors.push("over_contract_quote");
    } else if (pickQuote(r.legit_bank_change)) {
      target.legitNewBank = randomBank(rng, target.bank.holder);
      target.bank = target.legitNewBank;
      target.decoys.push("legit_bank_change");
    } else if (pickQuote(r.small_price_rise)) {
      target.unitPrice = Math.round(target.unitPrice * (1.01 + rng.next() * 0.015));
      target.decoys.push("small_price_rise");
    }
    const short = rng.chance(r.short_delivery) ? rng.int(1, Math.max(1, Math.floor(qty * 0.25))) : 0;
    const damaged = !short && rng.chance(r.damaged_rejected) ? rng.int(1, Math.max(1, Math.floor(qty * 0.15))) : 0;
    const inv: PlannedInvoice = { priceFactor: 1, fraudBank: false, duplicate: false, errors: [], decoys: [] };
    const iroll = rng.next();
    if (iroll < r.inflated_invoice) {
      inv.priceFactor = 1.05 + rng.next() * 0.2;
      inv.errors.push("inflated_invoice");
    } else if (iroll < r.inflated_invoice + r.bank_fraud_invoice) {
      inv.fraudBank = true;
      inv.errors.push("bank_fraud_invoice");
    }
    if (rng.chance(r.duplicate_invoice)) inv.duplicate = true;
    if (short) inv.errors.push("short_delivery");
    if (damaged) inv.decoys.push("damaged_rejected");
    return { cycle: i, sku: item.sku, qty, planned: { quotes, delivery: { short, damaged }, invoice: inv } };
  }

  initialEvents(engine: Engine): ScheduledWorldEvent[] {
    if (this.mode === "demo") return this.demoPrologue(engine);
    const rng = this.rng.fork("cycles");
    const out: ScheduledWorldEvent[] = [];
    for (let i = 0; i < this.cyclesTotal; i++) {
      const cs = this.planCycle(i, rng);
      this.cycles.push(cs);
      const item = CATALOG.find((x) => x.sku === cs.sku)!;
      out.push({ at: this.start + i * 2 * DAY + rng.int(0, 20) * HOUR, event: { type: "need", sku: cs.sku, qty: cs.qty, orderBy: this.start + i * 2 * DAY + 20 * DAY, reason: `Stock of ${item.name} below reorder point.`, context: { cycle: i } } });
    }
    return out;
  }

  // ---------------------------------------------------------------- reacting to the engine

  onEngineEvent(e: EngineEvent, engine: Engine): ScheduledWorldEvent[] {
    const out: ScheduledWorldEvent[] = [];
    const d = e.data as Record<string, never>;
    switch (e.type) {
      case "requisition_created": {
        const req = d.requisition as unknown as { id: string; sku: string; qty: number; context?: { cycle?: number } };
        const cs = this.mode === "demo" ? this.demoCycleFor(req) : this.cycles[req.context?.cycle ?? -1];
        if (!cs) break;
        cs.requisitionId = req.id;
        this.reqToCycle.set(req.id, cs);
        // Demo time is compressed so the story fits a 2-minute pitch; eval uses realistic gaps.
        const gap = this.mode === "demo" ? 2 * MIN : 5 * MIN;
        let t = e.at + (this.mode === "demo" ? 3 * MIN : 20 * MIN);
        for (const q of cs.planned.quotes) {
          if (q.legitNewBank) this.bankTruth.set(bankKey(q.legitNewBank), true);
          if (q.errors.includes("bank_fraud_quote")) this.bankTruth.set(bankKey(q.bank), false);
          out.push({ at: t, event: this.quoteDoc(engine, req.id, q, cs.cycle) });
          t += gap;
        }
        out.push({ at: t, event: { type: "rfq_closed", requisitionId: req.id } });
        break;
      }
      case "po_created": {
        const po = d.po as unknown as { id: string; requisitionId: string; lines: { sku: string; qty: number; unitPrice: number }[]; vendorId: string };
        const cs = this.reqToCycle.get(po.requisitionId);
        if (!cs) break;
        this.poToCycle.set(po.id, cs);
        const ordered = po.lines[0]!.qty;
        const { short, damaged } = this.mode === "demo" && cs.cycle === 0 ? { short: 2, damaged: 0 } : cs.planned.delivery;
        const got = Math.max(0, ordered - Math.min(short, ordered - 1));
        const deliverAt = e.at + (this.mode === "demo" ? (cs.cycle === 0 ? 30 * DAY : 2 * HOUR) : (3 + this.rng.int(0, 4)) * DAY);
        const delivDoc = this.docId("DOC-D");
        this.answerKey.push({ docId: delivDoc, cycle: cs.cycle, kind: "delivery", errors: short ? ["short_delivery"] : [], decoys: damaged ? ["damaged_rejected"] : [], vendorId: po.vendorId, fairCents: (got - damaged) * po.lines[0]!.unitPrice, billedCents: ordered * po.lines[0]!.unitPrice });
        if (this.mode === "demo" && cs.cycle === 1) {
          // Battery order rides the cargo flight; it lands months after the demo ends.
        } else if (!(this.mode === "demo" && cs.cycle === 0)) {
          out.push({ at: deliverAt, event: { type: "delivery", poId: po.id, lines: [{ sku: cs.sku, qtyReceived: got, qtyRejected: damaged }], note: short ? `${ordered - got} missing from manifest` : damaged ? `${damaged} damaged in landing` : "complete", docId: delivDoc } });
        } else {
          this.demoFilterPo = { poId: po.id, got, ordered, deliverDoc: delivDoc };
        }
        // Invoice follows the delivery (vendor bills what was ordered).
        break;
      }
      case "receipt_recorded": {
        // Vendors bill after delivery, using whatever bank account they have on file at that time.
        const po = d.po as unknown as { id: string };
        const cs = this.poToCycle.get(po.id);
        if (this.mode !== "eval" || !cs || this.invoiced.has(po.id)) break;
        this.invoiced.add(po.id);
        out.push(...this.invoicesFor(engine, po.id, cs, e.at + 6 * HOUR, this.acceptedQty(engine, po.id)));
        break;
      }
      case "verification_requested": {
        // The remote authority (Earth) does the call-back and answers truthfully after the round trip.
        const v = d.verification as unknown as { id: string; claimedBank: BankAccount; sentAt: Time };
        // Truth is keyed on the full bank identity: a real account number with someone else's routing is not the vendor's account.
        const legit = this.bankTruth.get(bankKey(v.claimedBank)) ?? false;
        const at = (d.expectedReplyAt as unknown as number) ?? v.sentAt + 2 * engine.remoteLatencyMs + this.policy.vendorBankChange.verificationProcessingMs;
        out.push({ at, event: { type: "external", actorId: "cfo", action: "answer_verification", params: { verificationId: v.id, confirmed: legit, answer: legit ? "Supplier confirmed the new account on a call-back to the number on file." : "Supplier says it never changed its bank details. The request was fraudulent." }, summary: legit ? "Earth: call-back confirms the new bank account." : "Earth: the bank change was fake. The real supplier never sent it.", short: legit ? "Earth: the new bank account is genuine." : "Earth: the bank change was FAKE." } });
        break;
      }
      case "escalation_delivered": {
        const esc = d.escalation as unknown as { id: string; to: string; options: { id: string }[] };
        // In eval both humans are simulated. In the demo only Earth is; the commander is the person in the headset.
        if (esc.to === "remote_authority" || this.mode === "eval") {
          const choice = esc.options.find((o) => o.id.startsWith("buy-")) ?? esc.options.find((o) => o.id === "approve") ?? esc.options.find((o) => o.id === "wait") ?? esc.options[0];
          if (choice) {
            const actorId = esc.to === "remote_authority" ? "cfo" : "commander";
            const delay = esc.to === "remote_authority" ? 30 * MIN + engine.remoteLatencyMs : 10 * MIN;
            out.push({ at: e.at + delay, event: { type: "external", actorId, action: "decide", params: { escalationId: esc.id, optionId: choice.id }, summary: `${actorId === "cfo" ? "Earth CFO" : "Commander"} chose ${choice.id}` } });
          }
        }
        break;
      }
      case "vendor_status_changed": {
        // Earth re-verifies a locked supplier's details on file by call-back, then releases it.
        const v = d.vendor as unknown as { id: string; name: string; status: string };
        if (v.status !== "hold") break;
        out.push({ at: e.at + 2 * engine.remoteLatencyMs + 2 * DAY, event: { type: "external", actorId: "cfo", action: "release_vendor", params: { vendorId: v.id, reason: "Details on file re-verified by call-back; supplier contacts secured." }, summary: `Earth: ${v.name} re-verified and released.` } });
        break;
      }
      case "lever_activated": {
        // The commander's decision authorizes the crew member whose job it is; that agent then acts with its own tool.
        const lever = d.leverId as unknown as string;
        if (lever === "drill_off") {
          this.authorized.add("drill_off");
          out.push({ at: e.at, event: { type: "directive", to: "engineer", lever, text: "The commander chose to shut down the ice drill. Power it down now and say so.", expect: { tool: "set_equipment", args: { equipment: "ice_drill", on: false, reason: "commander's decision" } } } });
        }
        if (lever === "lab_pause") {
          this.authorized.add("lab_pause");
          out.push({ at: e.at, event: { type: "directive", to: "science", lever, text: "The commander chose to pause the science lab. Pause it now and say so.", expect: { tool: "set_lab", args: { state: "paused", reason: "commander's decision" } } } });
        }
        break;
      }
      case "invoice_rejected": {
        // A vendor whose invoice was rejected for price sends a corrected one at the agreed price.
        const inv = d.invoice as unknown as { id: string; poId?: string; lines: { qty: number }[]; vendorInvoiceNo: string };
        const reason = String(d.reason ?? "");
        const cs = inv.poId ? this.poToCycle.get(inv.poId) : undefined;
        if (cs && /price/i.test(reason) && !this.corrected.has(inv.poId!)) {
          this.corrected.add(inv.poId!);
          const po = engine.pos.get(inv.poId!)!;
          const v = engine.vendors.get(po.vendorId)!;
          const accepted = this.acceptedQty(engine, po.id);
          out.push({ at: e.at + 2 * DAY, event: this.invoiceDoc(engine, po.id, cs, { bank: v.bank, unitPrice: po.lines[0]!.unitPrice, qty: po.lines[0]!.qty, no: `${inv.vendorInvoiceNo}-C`, errors: [], decoys: [], fair: accepted * po.lines[0]!.unitPrice }) });
        }
        break;
      }
    }
    return out;
  }

  private corrected = new Set<string>();
  private invoiced = new Set<string>();

  /** Accounts the world planted as fraudulent (ground truth for scoring). */
  fraudAccounts(): Set<string> {
    return new Set([...this.bankTruth.entries()].filter(([, legit]) => !legit).map(([acct]) => acct));
  }

  private acceptedQty(engine: Engine, poId: string): number {
    let n = 0;
    for (const g of engine.receipts.values()) if (g.poId === poId) for (const l of g.lines) n += l.qtyReceived - l.qtyRejected;
    return n;
  }

  private invoicesFor(engine: Engine, poId: string, cs: CycleState, at: Time, acceptedQty: number): ScheduledWorldEvent[] {
    const po = engine.pos.get(poId)!;
    const v = engine.vendors.get(po.vendorId)!;
    const p = cs.planned.invoice;
    const ordered = po.lines[0]!.qty;
    const price = Math.round(po.lines[0]!.unitPrice * p.priceFactor);
    const bank = p.fraudBank ? randomBank(this.rng, v.bank.holder, true) : v.bank;
    if (p.fraudBank) this.bankTruth.set(bankKey(bank), false);
    const no = `${v.name.split(" ")[0]!.slice(0, 3).toUpperCase()}-${10_000 + cs.cycle * 7 + this.rng.int(0, 6)}`;
    const fair = p.fraudBank ? 0 : acceptedQty * po.lines[0]!.unitPrice;
    const out: ScheduledWorldEvent[] = [{ at, event: this.invoiceDoc(engine, poId, cs, { bank, unitPrice: price, qty: ordered, no, errors: p.errors, decoys: p.decoys, fair }) }];
    if (p.duplicate) {
      // After a fraudulent copy, the second invoice is the real supplier's genuine bill: paying it once is correct.
      const genuine = p.fraudBank;
      // Otherwise it's an exact copy of the original (same price), re-sent under the same or a suffixed number.
      out.push({ at: at + (1 + this.rng.int(0, 5)) * DAY, event: this.invoiceDoc(engine, poId, cs, { bank: v.bank, unitPrice: genuine ? po.lines[0]!.unitPrice : price, qty: ordered, no: this.rng.chance(0.5) ? no : `${no}A`, errors: genuine ? [] : ["duplicate_invoice"], decoys: genuine ? ["genuine_after_fraud" as DecoyType] : [], fair: genuine ? acceptedQty * po.lines[0]!.unitPrice : 0 }) });
    }
    return out;
  }

  // ---------------------------------------------------------------- demo director

  private demoFilterPo?: { poId: string; got: number; ordered: number; deliverDoc: string };
  private demoCycles: CycleState[] = [];

  private demoCycleFor(req: { sku: string; qty: number }): CycleState | undefined {
    return this.demoCycles.find((c) => c.sku === req.sku && c.qty === req.qty && !c.requisitionId);
  }

  /** Before the demo: a routine air-filter order a month ago (quotes, approval, PO). */
  private demoPrologue(engine: Engine): ScheduledWorldEvent[] {
    const filterSellers = this.market.sellers.get("FLT-HEPA") ?? [];
    const quotes = filterSellers.slice(0, 2).map((vid) => {
      const v = this.market.vendors.find((x) => x.id === vid)!;
      return { vendorId: vid, unitPrice: this.market.basePrice.get(vid)!.get("FLT-HEPA")!, qtyAvailable: 60, bank: v.bank, terms: "on_receipt" as const, errors: [], decoys: [] };
    });
    this.demoCycles.push({ cycle: 0, sku: "FLT-HEPA", qty: 36, planned: { quotes, delivery: { short: 2, damaged: 0 }, invoice: { priceFactor: 1, fraudBank: false, duplicate: false, errors: ["short_delivery"], decoys: [] } } });

    // Battery order for beat 2-7: usual supplier compromised (3x price, new bank), trusted alternative has 15.
    const batSellers = this.market.sellers.get("BAT-10") ?? [];
    const usual = this.market.vendors.find((x) => x.id === batSellers[0])!;
    const alt = this.market.vendors.find((x) => x.id === batSellers[1])!;
    const usualPrice = this.market.basePrice.get(usual.id)!.get("BAT-10")!;
    const altPrice = this.market.basePrice.get(alt.id)!.get("BAT-10")!;
    const fraudBank = randomBank(this.rng.fork("fraud"), usual.name, true);
    this.bankTruth.set(bankKey(fraudBank), false);
    const altQty = Math.min(6, Math.floor(this.policy.approval.localAuthorityMaxCents / altPrice));
    this.demoCycles.push({
      cycle: 1,
      sku: "BAT-10",
      qty: 12,
      planned: {
        quotes: [
          { vendorId: usual.id, unitPrice: Math.round(usualPrice * 3), qtyAvailable: 12, bank: fraudBank, terms: "prepay", errors: ["bank_fraud_quote", "inflated_quote"], decoys: [] },
          // Manifest space is paid up front, so the trusted supplier also quotes prepayment.
          { vendorId: alt.id, unitPrice: altPrice, qtyAvailable: altQty, bank: alt.bank, terms: "prepay", errors: [], decoys: [] },
        ],
        delivery: { short: 0, damaged: 0 },
        invoice: { priceFactor: 1, fraudBank: false, duplicate: false, errors: [], decoys: [] },
      },
    });
    const t0 = this.start - 31 * DAY;
    return [{ at: t0, event: { type: "need", sku: "FLT-HEPA", qty: 36, orderBy: t0 + 10 * DAY, reason: "Routine resupply: air filter stock covers 40 sols.", context: {} } }];
  }

  /** Part 1, station 1: the cargo lander at the pad. The short delivery (beat 1) is seen physically. */
  beatPad(engine: Engine): ScheduledWorldEvent[] {
    this.station = "pad";
    return this.beatDelivery(engine);
  }

  /**
   * Part 1, station 2: a crew scientist sampling the delta rock. Not one of the five agents; the lines are
   * the world's, with the real Perseverance reference the close-up view shows (SCIENCE_REF, credited).
   */
  beatScience(engine: Engine): ScheduledWorldEvent[] {
    this.station = "science";
    const t = engine.now;
    const r = SCIENCE_REF;
    const where = r.target ? ` at ${r.target}` : "";
    return [
      { at: t, event: { type: "narration", agentRole: "scientist", name: r.scientist, text: `Taking a sample of the delta rock${where}. Look at me and press to see what Perseverance saw up close.`, short: "Sampling the delta rock. Tap me for the close-up.", mood: "happy" } },
      { at: t + 2 * MIN, event: { type: "narration", agentRole: "scientist", name: r.scientist, text: r.sol ? `Perseverance abraded a patch like this on sol ${r.sol} with ${r.instrument}; ours goes to the lab tonight.` : `Perseverance imaged rock like this with ${r.instrument}; our sample goes to the lab tonight.`, short: "Our sample goes to the lab tonight.", mood: "calm" } },
    ];
  }

  /** Part 1, station 3: the Engineer checks the solar field, then sees the storm rising over the rim (beat 2 starts). */
  beatSolar(engine: Engine, rampMs = 20 * MIN): ScheduledWorldEvent[] {
    const check = this.beatSolarCheck(engine);
    const warning = this.beatStormWarning(engine, rampMs, 2 * MIN);
    return [...check, ...warning];
  }

  /** The Engineer's panel check at the solar field (no storm yet). */
  beatSolarCheck(engine: Engine): ScheduledWorldEvent[] {
    this.station = "solar";
    const t = engine.now;
    const before = this.power.state(this.tauAt(t));
    return [
      { at: t, event: { type: "narration", agentRole: "requester", text: `Panels read ${Math.round(before.solarKWhPerSol)} kWh per sol at tau ${this.tauAt(t).toFixed(1)}; load is ${Math.round(before.loadKWhPerSol)}. Dust coating is light.`, short: `Solar ${Math.round(before.solarKWhPerSol)} kWh/sol. Panels fine.`, mood: "calm" } },
    ];
  }

  /** The storm warning (beat 2 starts): wherever the judge is, the Engineer tells them to get inside. Runs once. */
  beatStormWarning(engine: Engine, rampMs = 20 * MIN, delayMs = 0): ScheduledWorldEvent[] {
    if (this.stormWarned) return [];
    this.stormWarned = true;
    const t = engine.now;
    const storm = this.beatStorm(engine, rampMs);
    const after = this.power.state(4.6);
    return [
      { at: t + delayMs, event: { type: "narration", agentRole: "requester", text: `Dust storm rising over the crater rim: tau climbing toward 4.6. Solar will drop to about ${Math.round(after.solarKWhPerSol)} kWh per sol. Commander, get inside.`, short: "Dust storm coming. Commander, get inside!", mood: "worried" } },
      ...storm,
    ];
  }

  /**
   * Free roam: the judge chose a station. Its content runs the first time it is visited (the pad is beat 1,
   * the science site is the scientist, the solar field is the panel check); the rover has no story content.
   */
  visit(station: "pad" | "science" | "solar" | "rover", engine: Engine): ScheduledWorldEvent[] {
    this.station = station;
    if (this.visited.has(station)) return [];
    this.visited.add(station);
    switch (station) {
      case "pad": return this.beatDelivery(engine);
      case "science": return this.beatScience(engine);
      case "solar": return this.beatSolarCheck(engine);
      case "rover": return [];
    }
  }

  /** Part 1, station 4: the judge is at the door; `enter()` when they tap it (or the director auto-enters). */
  beatDoor(): ScheduledWorldEvent[] {
    this.station = "door";
    return [];
  }

  enter(): void {
    this.part = "inside";
    this.station = undefined;
  }

  /** Beat 1: the filters arrive (34 of 36) and the vendor bills 36. */
  beatDelivery(engine: Engine): ScheduledWorldEvent[] {
    this.beat = 1;
    const f = this.demoFilterPo;
    if (!f) return [];
    const cs = this.demoCycles[0]!;
    const po = engine.pos.get(f.poId)!;
    const v = engine.vendors.get(po.vendorId)!;
    const t = engine.now;
    return [
      { at: t, event: { type: "delivery", poId: f.poId, lines: [{ sku: "FLT-HEPA", qtyReceived: f.got, qtyRejected: 0 }], note: `${f.ordered - f.got} cartridges missing from the cargo manifest`, docId: f.deliverDoc } },
      { at: t + 5 * MIN, event: this.invoiceDoc(engine, f.poId, cs, { bank: v.bank, unitPrice: po.lines[0]!.unitPrice, qty: f.ordered, no: `${v.name.split(" ")[0]!.slice(0, 3).toUpperCase()}-20417`, errors: ["short_delivery"], decoys: [], fair: f.got * po.lines[0]!.unitPrice }) },
    ];
  }

  /** Beat 2 (legacy, eval): the storm and the battery need together. */
  beatStorm(engine: Engine, rampMs = 20 * MIN): ScheduledWorldEvent[] {
    return [...this.startStorm(engine, rampMs), ...this.raiseBatteryNeed(engine, rampMs)];
  }

  /** The dust storm rolls in over the rim (tau ramps to 4.6); the drill and lab become things the commander can give up. */
  startStorm(engine: Engine, rampMs = 20 * MIN): ScheduledWorldEvent[] {
    this.beat = 2;
    const t = engine.now;
    this.stormFrom = { t, tau0: this.tauAt(t), tau1: 4.6, durMs: rampMs };
    this.tau = 4.6;
    engine.setLevers([this.drillLeverAt(4.6), this.labLeverAt(4.6)]);
    return [{ at: t, event: { type: "telemetry", data: this.telemetry(t, engine) } }];
  }

  /** The Engineer needs batteries now: the oxygen makers need power through the storm, so it must be ordered within minutes. */
  raiseBatteryNeed(engine: Engine, afterMs = 0, orderWithinMs = 10 * MIN): ScheduledWorldEvent[] {
    const t = engine.now + afterMs;
    const st = this.power.state(4.6);
    const reason = `Dust storm at tau 4.6: solar ${Math.round(st.solarKWhPerSol)} kWh per sol against ${Math.round(st.loadKWhPerSol)} used. The oxygen makers need storage now.`;
    return [{ at: t, event: { type: "need", by: "engineer", sku: "BAT-10", qty: 12, orderBy: t + orderWithinMs, reason, short: "Storm. We need batteries now.", context: { tau: 4.6, solsLeft: Number(st.solsLeft.toFixed(1)) } } }];
  }

  /** The storm thins (tau back to 0.6). */
  endStorm(engine: Engine, rampMs = 30 * MIN): ScheduledWorldEvent[] {
    const t = engine.now;
    this.stormFrom = { t, tau0: this.tauAt(t), tau1: 0.6, durMs: rampMs };
    this.tau = 0.6;
    return [{ at: t, event: { type: "telemetry", data: this.telemetry(t, engine) } }];
  }

  private drillLeverAt(tau: number): Lever {
    const saved = this.power.loads.iceDrill * 24.6597;
    const st = this.power.state(tau);
    const net = st.solarKWhPerSol - st.loadKWhPerSol;
    return {
      id: "drill_off",
      label: "Shut down the drill",
      detail: `Saves about ${Math.round(saved)} kWh per sol (ESTIMATE). Water production pauses. Reserve goes from ${st.solsLeft.toFixed(1)} to ${(st.socKWh / -(net + saved)).toFixed(1)} sols.`,
      appliesToSkus: ["BAT-10"],
    };
  }

  private labLever(): Lever {
    return this.labLeverAt(this.tauAt(this.lastPowerT));
  }

  private labLeverAt(tau: number): Lever {
    const saved = this.power.loads.science * 24.6597;
    const st = this.power.state(tau);
    const net = st.solarKWhPerSol - st.loadKWhPerSol;
    const after = net + saved >= 0 ? "no deficit" : `${(st.socKWh / -(net + saved)).toFixed(1)} sols`;
    return {
      id: "lab_pause",
      label: "Pause the science lab",
      detail: `Saves about ${Math.round(saved)} kWh per sol (ESTIMATE). Samples in the freezers may spoil. Reserve goes from ${Number.isFinite(st.solsLeft) ? `${st.solsLeft.toFixed(1)} sols` : "no deficit"} to ${after}.`,
      appliesToSkus: ["BAT-10"],
    };
  }

  // ---------------------------------------------------------------- life support, the lab, and the crew's world tools

  /** Stored water, in days, when the drill stops producing more (SIMULATED). */
  readonly waterReserveDays = 9;
  /** The lab: on, or paused (its freezers and instruments off). */
  labOn = true;
  /** Non-essential loads cut by the Engineer (lights, heaters in empty modules): 4 kW. */
  rationing = false;
  /** Decisions the commander made that authorize a crew action (lever id -> who should act). */
  private readonly authorized = new Set<string>();
  /** What the crew did to the base (for the console). */
  readonly actions: { at: Time; by: string; tool: string; args: unknown; ok: boolean; detail: string }[] = [];

  /** Power level the screens and the alarm follow: critical while the storm drains the batteries faster than they can last. */
  powerLevel(t: Time): "ok" | "low" | "critical" {
    const st = this.power.state(this.tauAt(t));
    if (!Number.isFinite(st.solsLeft) || st.solsLeft >= 4.6) return "ok";
    return st.solsLeft < 4.0 ? "critical" : "low";
  }

  /** The domain tools each world agent has. Engine actions (requests, reports) come from the engine's policy; these change the base itself. */
  worldTools(actorId: string): { name: string; description: string; parameters: Record<string, unknown> }[] {
    const reason = { type: "string", description: "Why, in a few words" };
    switch (actorId) {
      case "engineer":
        return [
          { name: "set_equipment", description: "Power a machine down or up. The ice drill can only be powered down when the commander decided it.", parameters: { type: "object", required: ["equipment", "on"], properties: { equipment: { type: "string", enum: ["ice_drill"] }, on: { type: "boolean" }, reason } } },
          { name: "ration_power", description: "Cut or restore non-essential loads (lights and heaters in empty modules, about 4 kW). The oxygen makers are never cut.", parameters: { type: "object", required: ["on"], properties: { on: { type: "boolean" }, reason } } },
        ];
      case "life":
        return [
          { name: "set_life_support", description: "Set what life support protects first when power is short.", parameters: { type: "object", required: ["priority"], properties: { priority: { type: "string", enum: ["air", "water", "balanced"] }, reason } } },
          { name: "report_reserves", description: "Read the oxygen and water reserves.", parameters: { type: "object", properties: {} } },
        ];
      case "science":
        return [
          { name: "set_lab", description: "Pause the lab (freezers and instruments off) or run it. Pausing needs the commander's decision.", parameters: { type: "object", required: ["state"], properties: { state: { type: "string", enum: ["on", "paused"] }, reason } } },
          { name: "report_sample_risk", description: "Read how long the samples last without the lab's freezers.", parameters: { type: "object", properties: {} } },
        ];
      default:
        return [];
    }
  }

  /** A world agent used one of its tools. The world checks it (like policy does for money) and changes the base. */
  act(actorId: string, tool: string, args: Record<string, unknown>, engine: Engine): { ok: boolean; detail: string; events: ScheduledWorldEvent[] } {
    const t = engine.now;
    const done = (ok: boolean, detail: string, changed = false) => {
      this.actions.push({ at: t, by: actorId, tool, args, ok, detail });
      return { ok, detail, events: changed ? [{ at: t, event: { type: "telemetry", data: this.telemetry(t, engine) } } as ScheduledWorldEvent] : [] };
    };
    const allowed = this.worldTools(actorId).some((x) => x.name === tool);
    if (!allowed) return done(false, `${actorId} has no tool ${tool}`);
    switch (tool) {
      case "set_equipment": {
        const on = args.on === true;
        if (!on && !this.authorized.has("drill_off")) return done(false, "the drill stays on until the commander decides");
        this.power.drillOn = on;
        return done(true, on ? "ice drill on" : "ice drill powered down", true);
      }
      case "ration_power": {
        const on = args.on === true;
        if (on === this.rationing) return done(true, on ? "already rationing" : "not rationing");
        this.rationing = on;
        this.power.loads.lifeSupport += on ? -4 : 4; // the 4 kW of non-essentials ride on the life-support bus
        return done(true, on ? "non-essential loads cut, about 4 kW" : "non-essential loads restored", true);
      }
      case "set_life_support":
        return done(true, `life support protects ${String(args.priority ?? "air")} first`);
      case "report_reserves":
        return done(true, `oxygen ${this.o2Pct(t)}%, water ${this.waterDays()} days without the drill`);
      case "set_lab": {
        const paused = args.state === "paused";
        if (paused && !this.authorized.has("lab_pause")) return done(false, "the lab keeps running until the commander decides");
        this.labOn = !paused;
        this.power.loads.science = paused ? 0 : 4;
        return done(true, paused ? "lab paused, freezers off" : "lab running", true);
      }
      case "report_sample_risk":
        return done(true, this.labOn ? "samples are frozen and safe" : "samples warm up within a few sols");
    }
    return done(false, `unknown tool ${tool}`);
  }

  o2Pct(t: Time): number {
    return this.powerLevel(t) === "critical" ? 97 : 99;
  }

  waterDays(): number {
    return this.waterReserveDays;
  }

  /** What the crew's world agents and the clients read: power, life support, the lab, the storm. */
  baseState(t: Time): Record<string, unknown> {
    const tau = this.tauAt(t);
    const solar0 = this.power.solarKWhPerSol(0.6);
    return {
      power: { level: this.powerLevel(t), panels: Math.max(0.05, Math.min(1, this.power.solarKWhPerSol(tau) / solar0)) },
      life: { o2Pct: this.o2Pct(t), waterDays: this.waterDays() },
      lab: this.labOn ? "on" : "paused",
      drill: this.power.drillOn ? "on" : "off",
      rationing: this.rationing,
      tau,
      dust: Math.max(0, Math.min(1, (tau - 0.6) / 4.0)),
    };
  }

  /**
   * Where the demo story is (0-7), read from the engine's records rather than a script:
   * 1 delivery, 2 storm, 3 battery request, 4 quote flagged, 5 blocked and sent to Earth or escalated,
   * 6 the commander decides, 7 Earth's verdict on the bank change.
   */
  storyBeat(engine: Engine): number {
    if (this.beat < 2 || !this.stormFrom) return this.beat;
    const since = this.stormFrom.t;
    const req = [...engine.requisitions.values()].find((r) => r.sku === "BAT-10" && r.createdAt >= since);
    if (!req) return 2;
    const quoteIds = new Set([...engine.quotes.values()].filter((q) => q.requisitionId === req.id).map((q) => q.id));
    if (!engine.flags.some((f) => f.subject.kind === "quote" && quoteIds.has(f.subject.id))) return 3;
    const ver = [...engine.verifications.values()].find((v) => v.sentAt >= since);
    if (ver && ver.status !== "pending") return 7;
    const esc = [...engine.escalations.values()].filter((x) => x.createdAt >= since);
    if (esc.some((x) => x.to === "local_authority" && x.status !== "in_transit")) return 6;
    return ver || esc.length ? 5 : 4;
  }

  /** Mars-side vendor record helper for clients. */
  vendor(id: string): Vendor | undefined {
    return this.market.vendors.find((v) => v.id === id);
  }

  deliveredPrice(sku: string): number {
    const item = CATALOG.find((i) => i.sku === sku);
    return item ? deliveredCents(item) : 0;
  }
}
