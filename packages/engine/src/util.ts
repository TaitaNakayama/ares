import { createHash } from "node:crypto";

/** Integer minor currency units (cents). Never floats. */
export type Cents = number;

export function assertCents(v: number, what: string): void {
  if (!Number.isSafeInteger(v)) throw new Error(`${what} must be an integer number of cents, got ${v}`);
}

/** Canonical JSON: sorted keys, so hashes are stable across runs. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const out: Record<string, unknown> = {};
      for (const key of Object.keys(v).sort()) out[key] = (v as Record<string, unknown>)[key];
      return out;
    }
    return v;
  });
}

export function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

/** Deterministic PRNG (sfc32) seeded from any string. Same seed -> same sequence on every machine. */
export class Rng {
  private a: number;
  private b: number;
  private c: number;
  private d: number;

  constructor(seed: string | number) {
    const h = sha256(String(seed));
    this.a = parseInt(h.slice(0, 8), 16) | 0;
    this.b = parseInt(h.slice(8, 16), 16) | 0;
    this.c = parseInt(h.slice(16, 24), 16) | 0;
    this.d = parseInt(h.slice(24, 32), 16) | 0;
    for (let i = 0; i < 12; i++) this.next();
  }

  /** Uniform in [0, 1). */
  next(): number {
    this.a |= 0; this.b |= 0; this.c |= 0; this.d |= 0;
    const t = (((this.a + this.b) | 0) + this.d) | 0;
    this.d = (this.d + 1) | 0;
    this.a = this.b ^ (this.b >>> 9);
    this.b = (this.c + (this.c << 3)) | 0;
    this.c = (this.c << 21) | (this.c >>> 11);
    this.c = (this.c + t) | 0;
    return (t >>> 0) / 4294967296;
  }

  int(minInclusive: number, maxInclusive: number): number {
    return minInclusive + Math.floor(this.next() * (maxInclusive - minInclusive + 1));
  }

  chance(p: number): boolean {
    return this.next() < p;
  }

  pick<T>(items: readonly T[]): T {
    if (items.length === 0) throw new Error("pick from empty list");
    return items[Math.floor(this.next() * items.length)] as T;
  }

  normal(mean = 0, sd = 1): number {
    const u = 1 - this.next();
    const v = this.next();
    return mean + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }

  shuffle<T>(items: readonly T[]): T[] {
    const out = items.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      [out[i], out[j]] = [out[j] as T, out[i] as T];
    }
    return out;
  }

  /** Child stream so adding draws in one subsystem doesn't shift another's. */
  fork(label: string): Rng {
    return new Rng(`${this.int(0, 2 ** 31)}:${label}`);
  }
}

export function median(xs: readonly number[]): number {
  if (xs.length === 0) return NaN;
  const s = xs.slice().sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? (s[mid] as number) : ((s[mid - 1] as number) + (s[mid] as number)) / 2;
}

/** Median absolute deviation, scaled to be comparable to a standard deviation. */
export function mad(xs: readonly number[]): number {
  const m = median(xs);
  return 1.4826 * median(xs.map((x) => Math.abs(x - m)));
}

/**
 * Robust z-score of x against a history: (x - median) / MAD.
 * Uses log prices, since prices are multiplicative. A floor on the spread keeps
 * a perfectly flat history from turning a 1% change into an infinite score.
 */
export function robustLogZ(x: number, history: readonly number[], minRelSpread = 0.02): number {
  const logs = history.map((h) => Math.log(h));
  const spread = Math.max(mad(logs), minRelSpread);
  return (Math.log(x) - median(logs)) / spread;
}

export class IdGen {
  private counters = new Map<string, number>();
  next(prefix: string): string {
    const n = (this.counters.get(prefix) ?? 0) + 1;
    this.counters.set(prefix, n);
    return `${prefix}-${String(n).padStart(4, "0")}`;
  }
}

export function formatCents(c: Cents): string {
  const sign = c < 0 ? "-" : "";
  const abs = Math.abs(c);
  return `${sign}$${Math.floor(abs / 100).toLocaleString("en-US")}.${String(abs % 100).padStart(2, "0")}`;
}
