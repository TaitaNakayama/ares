import type { Ref, Time } from "./types.ts";
import { assertCents, canonicalJson, sha256, type Cents } from "./util.ts";

export const ACCOUNTS = {
  cash: { name: "Cash", type: "asset" },
  inventory: { name: "Inventory", type: "asset" },
  prepayments: { name: "Supplier prepayments", type: "asset" },
  grni: { name: "Goods received not invoiced", type: "liability" },
  ap: { name: "Accounts payable", type: "liability" },
  ppv: { name: "Purchase price variance", type: "expense" },
  funding: { name: "Funding (equity)", type: "equity" },
} as const;

export type AccountId = keyof typeof ACCOUNTS;

export interface PostingLine {
  account: AccountId;
  debit: Cents;
  credit: Cents;
  /** Sub-ledger key, e.g. the vendor for AP lines. */
  vendorId?: string;
}

export interface JournalEntryInput {
  memo: string;
  lines: PostingLine[];
  /** Source documents and records this entry comes from. */
  refs: Ref[];
  proposalId: string;
  decisionId: string;
  actorId: string;
  approvers: string[];
  rules: string[];
}

export interface JournalEntry extends JournalEntryInput {
  id: string;
  seq: number;
  at: Time;
  prevHash: string;
  hash: string;
}

/** Opaque one-shot token. Only `Ledger.authorize` (which needs the owner's secret) creates live ones. */
export interface PostingAuthorization {
  readonly decisionId: string;
}

export class LedgerError extends Error {}

function deepFreeze<T>(o: T): T {
  if (o && typeof o === "object" && !Object.isFrozen(o)) {
    Object.freeze(o);
    for (const v of Object.values(o as Record<string, unknown>)) deepFreeze(v);
  }
  return o;
}

/**
 * Append-only double-entry ledger. Nothing can post without a token minted by the
 * holder of the secret (the engine's executor, after an `allow` decision).
 */
export class Ledger {
  readonly #entries: JournalEntry[] = [];
  readonly #balances = new Map<string, Cents>();
  readonly #live = new WeakSet<object>();
  readonly #secret: symbol;

  constructor(secret: symbol) {
    this.#secret = secret;
  }

  authorize(decisionId: string, secret: symbol): PostingAuthorization {
    if (secret !== this.#secret) throw new LedgerError("only the engine can authorize postings");
    const token = Object.freeze({ decisionId });
    this.#live.add(token);
    return token;
  }

  post(input: JournalEntryInput, at: Time, auth: PostingAuthorization): JournalEntry {
    if (!this.#live.has(auth)) throw new LedgerError("posting refused: no valid authorization");
    if (auth.decisionId !== input.decisionId) throw new LedgerError("posting refused: authorization is for a different decision");
    // One-shot: a token can't be reused for a second posting.
    this.#live.delete(auth);

    if (input.lines.length < 2) throw new LedgerError("an entry needs at least two lines");
    let debits = 0;
    let credits = 0;
    for (const l of input.lines) {
      if (!Object.hasOwn(ACCOUNTS, l.account)) throw new LedgerError(`unknown account ${l.account}`);
      assertCents(l.debit, "debit");
      assertCents(l.credit, "credit");
      if (l.debit < 0 || l.credit < 0) throw new LedgerError("negative amounts are not allowed; swap debit and credit");
      if ((l.debit > 0) === (l.credit > 0)) throw new LedgerError("each line is either a debit or a credit");
      debits += l.debit;
      credits += l.credit;
    }
    if (debits !== credits) throw new LedgerError(`entry does not balance: debits ${debits} != credits ${credits}`);
    if (input.refs.length === 0) throw new LedgerError("every entry must trace to at least one source");

    const prevHash = this.#entries.at(-1)?.hash ?? "genesis";
    const seq = this.#entries.length + 1;
    const id = `JE-${String(seq).padStart(4, "0")}`;
    const body = { ...structuredClone(input), id, seq, at, prevHash };
    const entry: JournalEntry = deepFreeze({ ...body, hash: sha256(canonicalJson(body)) });
    this.#entries.push(entry);
    for (const l of entry.lines) {
      this.#bump(l.account, l.debit - l.credit);
      if (l.vendorId) this.#bump(`${l.account}:${l.vendorId}`, l.debit - l.credit);
    }
    return entry;
  }

  #bump(key: string, delta: Cents): void {
    this.#balances.set(key, (this.#balances.get(key) ?? 0) + delta);
  }

  /** Debit-positive balance. Liabilities and equity are therefore negative. */
  balance(account: AccountId, vendorId?: string): Cents {
    return this.#balances.get(vendorId ? `${account}:${vendorId}` : account) ?? 0;
  }

  all(): readonly JournalEntry[] {
    return this.#entries.slice();
  }

  get size(): number {
    return this.#entries.length;
  }

  head(): { seq: number; hash: string } {
    return { seq: this.#entries.length, hash: this.#entries.at(-1)?.hash ?? "genesis" };
  }

  get(id: string): JournalEntry | undefined {
    return this.#entries.find((e) => e.id === id);
  }

  trialBalance(): { account: AccountId; name: string; balance: Cents }[] {
    return (Object.keys(ACCOUNTS) as AccountId[]).map((a) => ({ account: a, name: ACCOUNTS[a].name, balance: this.balance(a) }));
  }

  /**
   * Recomputes everything from the entries: per-entry balance, hash chain, and every
   * cached balance. Pass an externally recorded head (e.g. from the audit log) to also
   * detect truncation or a rewritten tail.
   */
  verify(expectedHead?: { seq: number; hash: string }): { ok: boolean; problems: string[] } {
    const problems: string[] = [];
    let prev = "genesis";
    const recomputed = new Map<string, Cents>();
    for (const e of this.#entries) {
      const d = e.lines.reduce((s, l) => s + l.debit, 0);
      const c = e.lines.reduce((s, l) => s + l.credit, 0);
      if (d !== c) problems.push(`${e.id} unbalanced`);
      if (e.prevHash !== prev) problems.push(`${e.id} breaks the hash chain`);
      const { hash, ...body } = e;
      if (sha256(canonicalJson(body)) !== hash) problems.push(`${e.id} hash mismatch (tampered)`);
      prev = e.hash;
      for (const l of e.lines) {
        recomputed.set(l.account, (recomputed.get(l.account) ?? 0) + l.debit - l.credit);
        if (l.vendorId) recomputed.set(`${l.account}:${l.vendorId}`, (recomputed.get(`${l.account}:${l.vendorId}`) ?? 0) + l.debit - l.credit);
      }
    }
    const keys = new Set([...recomputed.keys(), ...this.#balances.keys()]);
    for (const k of keys) if ((recomputed.get(k) ?? 0) !== (this.#balances.get(k) ?? 0)) problems.push(`cached balance ${k} does not match entries`);
    const sum = [...recomputed.entries()].filter(([k]) => !k.includes(":")).reduce((s, [, v]) => s + v, 0);
    if (sum !== 0) problems.push(`trial balance sums to ${sum}`);
    if (expectedHead) {
      const h = this.head();
      if (h.seq !== expectedHead.seq || h.hash !== expectedHead.hash) problems.push(`ledger head ${h.seq}/${h.hash.slice(0, 8)} != recorded ${expectedHead.seq}/${expectedHead.hash.slice(0, 8)} (truncated or rewritten)`);
    }
    return { ok: problems.length === 0, problems };
  }
}
