/**
 * Solar power vs dust opacity, calibrated on Opportunity's 2018 storm
 * (JPL mission updates: tau ~1.0 -> 468 Wh/sol, 2.1 -> 345, 10.5 -> 21; pre-storm ~650).
 * Fit: E(tau) = 650 * exp(-0.31 * tau) Wh/sol for Opportunity's array (research/08-mars-numbers.md).
 * The base array is that output scaled by `arrayScale` (SIMULATED size).
 */
export const OPPORTUNITY_FIT = { e0Wh: 650, k: 0.31 };

export const OPPORTUNITY_POINTS = [
  { tau: 1.0, wh: 468, source: "JPL MER update, sol 5105 (2018-06-03)" },
  { tau: 2.1, wh: 345, source: "JPL MER update, sol 5106 (2018-06-04)" },
  { tau: 10.5, wh: 21, source: "NASA 'On Mars, light is energy', sol 5111 (2018-06-10)" },
];

export function opportunityWhPerSol(tau: number): number {
  return OPPORTUNITY_FIT.e0Wh * Math.exp(-OPPORTUNITY_FIT.k * tau);
}

export interface BaseLoads {
  /** kW, continuous */
  lifeSupport: number;
  /** Ice-mining / water plant (ISRU). ESTIMATE: no sourced figure for an ice drill. */
  iceDrill: number;
  science: number;
}

export interface PowerState {
  tau: number;
  solarKWhPerSol: number;
  loadKWhPerSol: number;
  socKWh: number;
  capacityKWh: number;
  /** Sols until batteries are empty at current balance (Infinity if positive). */
  solsLeft: number;
  drillOn: boolean;
}

export const SOL_HOURS = 24.6597;

export class PowerModel {
  arrayScale: number;
  capacityKWh: number;
  socKWh: number;
  loads: BaseLoads;
  drillOn = true;

  constructor(opts: { arrayScale: number; capacityKWh: number; socFraction: number; loads: BaseLoads }) {
    this.arrayScale = opts.arrayScale;
    this.capacityKWh = opts.capacityKWh;
    this.socKWh = opts.capacityKWh * opts.socFraction;
    this.loads = opts.loads;
  }

  solarKWhPerSol(tau: number): number {
    return (opportunityWhPerSol(tau) * this.arrayScale) / 1000;
  }

  loadKWhPerSol(): number {
    const kw = this.loads.lifeSupport + this.loads.science + (this.drillOn ? this.loads.iceDrill : 0);
    return kw * SOL_HOURS;
  }

  /** Integrate battery state over `ms` of simulated time at opacity `tau`. */
  step(ms: number, tau: number): void {
    const sols = ms / (SOL_HOURS * 3_600_000);
    const net = (this.solarKWhPerSol(tau) - this.loadKWhPerSol()) * sols;
    this.socKWh = Math.max(0, Math.min(this.capacityKWh, this.socKWh + net));
  }

  state(tau: number): PowerState {
    const solar = this.solarKWhPerSol(tau);
    const load = this.loadKWhPerSol();
    const net = solar - load;
    return {
      tau,
      solarKWhPerSol: solar,
      loadKWhPerSol: load,
      socKWh: this.socKWh,
      capacityKWh: this.capacityKWh,
      solsLeft: net >= 0 ? Infinity : this.socKWh / -net,
      drillOn: this.drillOn,
    };
  }
}
