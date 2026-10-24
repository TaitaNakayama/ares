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

/**
 * Capability token. Only the engine's executor can mint one, after the policy
 * decision allowed the proposal. The ledger refuses any post without a live token,
 * so nothing (including an LLM tool call) can write to it directly.
 */
export class PostingAuthorization {
  readonly decisionId: string;
  private constructor(decisionId: string) {
    this.decisionId = decisionId;
  }
  static mint(decisionId: string, secret: symbol, ledger: Ledger): PostingAuthorization {
    if (!ledger.checkSecret(secret)) throw new Error("only the engine can authorize postings");
    const auth = new PostingAuthorization(decisionId);
    ledger.registerAuthorization(auth);
    return auth;
  }
}

export class LedgerError extends Error {}

export class Ledger {
  private readonly entries: JournalEntry[] = [];
  private readonly balances = new Map<string, Cents>();
  private readonly live = new WeakSet<PostingAuthorization>();
  private readonly secret: symbol;

  constructor(secret: symbol) {
    this.secret = secret;
  }

  checkSecret(s: symbol): boolean {
    return s === this.secret;
  }

  registerAuthorization(auth: PostingAuthorization): void {
    this.live.add(auth);
  }

  post(input: JournalEntryInput, at: Time, auth: PostingAuthorization): JournalEntry {
    if (!this.live.has(auth)) throw new LedgerError("posting refused: no valid authorization");
    if (auth.decisionId !== input.decisionId) throw new LedgerError("posting refused: authorization is for a different decision");
    // One-shot: a token can't be reused for a second posting.
    this.live.delete(auth);

    if (input.lines.length < 2) throw new LedgerError("an entry needs at least two lines");
    let debits = 0;
    let credits = 0;
    for (const l of input.lines) {
      if (!(l.account in ACCOUNTS)) throw new LedgerError(`unknown account ${l.account}`);
      assertCents(l.debit, "debit");
      assertCents(l.credit, "credit");
      if (l.debit < 0 || l.credit < 0) throw new LedgerError("negative amounts are not allowed; swap debit and credit");
      if ((l.debit > 0) === (l.credit > 0)) throw new LedgerError("each line is either a debit or a credit");
      debits += l.debit;
      credits += l.credit;
    }
    if (debits !== credits) throw new LedgerError(`entry does not balance: debits ${debits} != credits ${credits}`);
    if (input.refs.length === 0) throw new LedgerError("every entry must trace to at least one source");

    const prevHash = this.entries.at(-1)?.hash ?? "genesis";
    const seq = this.entries.length + 1;
    const id = `JE-${String(seq).padStart(4, "0")}`;
    const body = { ...structuredClone(input), id, seq, at, prevHash };
    const entry: JournalEntry = { ...body, hash: sha256(canonicalJson(body)) };
    this.entries.push(entry);
    for (const l of input.lines) {
      this.bump(l.account, l.debit - l.credit);
      if (l.vendorId) this.bump(`${l.account}:${l.vendorId}`, l.debit - l.credit);
    }
    return entry;
  }

  private bump(key: string, delta: Cents): void {
    this.balances.set(key, (this.balances.get(key) ?? 0) + delta);
  }

  /** Debit-positive balance. Liabilities and equity are therefore negative. */
  balance(account: AccountId, vendorId?: string): Cents {
    return this.balances.get(vendorId ? `${account}:${vendorId}` : account) ?? 0;
  }

  all(): readonly JournalEntry[] {
    return this.entries;
  }

  get(id: string): JournalEntry | undefined {
    return this.entries.find((e) => e.id === id);
  }

  trialBalance(): { account: AccountId; name: string; balance: Cents }[] {
    return (Object.keys(ACCOUNTS) as AccountId[]).map((a) => ({ account: a, name: ACCOUNTS[a].name, balance: this.balance(a) }));
  }

  /** Recomputes everything from the entries: balance per entry, totals, and the hash chain. */
  verify(): { ok: boolean; problems: string[] } {
    const problems: string[] = [];
    let prev = "genesis";
    let total = 0;
    for (const e of this.entries) {
      const d = e.lines.reduce((s, l) => s + l.debit, 0);
      const c = e.lines.reduce((s, l) => s + l.credit, 0);
      if (d !== c) problems.push(`${e.id} unbalanced`);
      total += d - c;
      if (e.prevHash !== prev) problems.push(`${e.id} breaks the hash chain`);
      const { hash, ...body } = e;
      if (sha256(canonicalJson(body)) !== hash) problems.push(`${e.id} hash mismatch (tampered)`);
      prev = e.hash;
    }
    if (total !== 0) problems.push(`ledger total ${total} != 0`);
    const sum = (Object.keys(ACCOUNTS) as AccountId[]).reduce((s, a) => s + this.balance(a), 0);
    if (sum !== 0) problems.push(`trial balance sums to ${sum}`);
    return { ok: problems.length === 0, problems };
  }
}
