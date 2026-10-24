import { defaultRuleBrains, Orchestrator, type Brain } from "@ares/agents";
import type { Engine, Policy } from "@ares/engine";
import { MarsWorld, type AnswerKeyEntry, type ErrorRates, type ErrorType } from "@ares/world-mars";

/**
 * Evaluation harness. Every run is scored against the world's answer key, which the
 * engine never sees, using outcomes measured from the ledger and payments (money that
 * actually left), not the engine's own "prevented" claims.
 */

export interface RunScore {
  seed: string;
  planted: Record<string, number>;
  caught: Record<string, number>;
  cleanInvoices: number;
  cleanPaidInFull: number;
  cleanWronglyBlockedCents: number;
  cleanHeldThenPaid: number;
  overpaidCents: number;
  savedCents: number;
  fraudPaymentsSent: number;
  escalations: number;
  escalationsToLocal: number;
  invoicesSeen: number;
  medianDaysToPay: number | null;
  integrityOk: boolean;
  deniedProposals: number;
  proposals: number;
}

export interface Scorecard {
  seeds: { from: number; count: number };
  cyclesPerSeed: number;
  policy: { name: string; version: number };
  perError: { type: string; planted: number; caught: number; recall: number }[];
  overallRecall: number;
  cleanInvoices: number;
  falseAlarmRate: number;
  frictionRate: number;
  savedCents: number;
  overpaidCents: number;
  wronglyBlockedCents: number;
  fraudPaymentsSent: number;
  escalationRate: number;
  medianDaysToPay: number | null;
  integrityFailures: number;
  proposals: number;
  deniedProposals: number;
  runs: RunScore[];
  ms: number;
}

const ERROR_TYPES: ErrorType[] = ["duplicate_invoice", "bank_fraud_invoice", "bank_fraud_quote", "inflated_quote", "inflated_invoice", "short_delivery", "over_contract_quote"];

export function scoreRun(world: MarsWorld, e: Engine): RunScore {
  const planted: Record<string, number> = Object.fromEntries(ERROR_TYPES.map((t) => [t, 0]));
  const caught: Record<string, number> = Object.fromEntries(ERROR_TYPES.map((t) => [t, 0]));
  const invBySrc = new Map([...e.invoices.values()].filter((i) => i.sourceRef).map((i) => [i.sourceRef!, i]));
  const quoteBySrc = new Map([...e.quotes.values()].filter((q) => q.sourceRef).map((q) => [q.sourceRef!, q]));
  const paidFor = (invoiceId: string) => [...e.payments.values()].filter((p) => p.invoiceId === invoiceId && p.status === "sent").reduce((s, p) => s + p.amount, 0);
  const heldInvoices = new Set(e.decisions.filter((d) => d.verdict === "hold" && d.actionType === "submit_invoice").map((d) => (e.proposals.find((p) => p.id === d.proposalId)?.action.params as { invoiceId?: string })?.invoiceId));

  let cleanInvoices = 0;
  let cleanPaidInFull = 0;
  let cleanWronglyBlocked = 0;
  let cleanHeldThenPaid = 0;
  let overpaid = 0;
  let saved = 0;
  const daysToPay: number[] = [];

  for (const k of world.answerKey) {
    if (k.kind === "invoice") scoreInvoice(k);
    else if (k.kind === "quote") scoreQuote(k);
  }

  function scoreInvoice(k: AnswerKeyEntry) {
    const inv = invBySrc.get(k.docId);
    const paid = inv ? paidFor(inv.id) : 0;
    if (inv && paid > 0) {
      const sent = [...e.payments.values()].filter((p) => p.invoiceId === inv.id && p.status === "sent").map((p) => p.sentAt ?? 0);
      if (sent.length) daysToPay.push((Math.max(...sent) - inv.receivedAt) / 86_400_000);
    }
    const errs = k.errors.filter((x) => x !== "short_delivery" || k.billedCents > k.fairCents);
    if (errs.length) {
      for (const t of errs) planted[t] = (planted[t] ?? 0) + 1;
      const ok = paid <= k.fairCents + 1;
      if (ok) for (const t of errs) caught[t] = (caught[t] ?? 0) + 1;
      overpaid += Math.max(0, paid - k.fairCents);
      saved += Math.max(0, k.billedCents - Math.max(paid, k.fairCents));
    } else {
      cleanInvoices++;
      if (paid >= k.fairCents - 1) cleanPaidInFull++;
      else cleanWronglyBlocked += k.fairCents - paid;
      if (inv && heldInvoices.has(inv.id) && paid >= k.fairCents - 1) cleanHeldThenPaid++;
      overpaid += Math.max(0, paid - k.fairCents);
    }
  }

  function scoreQuote(k: AnswerKeyEntry) {
    const q = quoteBySrc.get(k.docId);
    if (!k.errors.length) return;
    for (const t of k.errors) planted[t] = (planted[t] ?? 0) + 1;
    const ordered = q ? [...e.pos.values()].some((po) => po.quoteId === q.id) : false;
    if (!ordered) {
      for (const t of k.errors) caught[t] = (caught[t] ?? 0) + 1;
      saved += k.billedCents;
    } else {
      // Ordered on a bad quote: the overpayment is what was paid above a fair price (or all of it for fraud).
      const po = [...e.pos.values()].find((x) => x.quoteId === q!.id)!;
      const paid = e.paidAgainstPo(po.id);
      overpaid += k.errors.some((x) => x.startsWith("bank_fraud")) ? paid : Math.max(0, paid - Math.round(paid / 3));
    }
  }

  // Payments that went to any account the world knows was fraudulent: must be zero.
  // Ground truth from the world (not engine outcomes): accounts it planted as fraudulent.
  const fraudAccounts = world.fraudAccounts();
  const fraudPaymentsSent = [...e.payments.values()].filter((p) => p.status === "sent" && fraudAccounts.has(p.bank.account)).length;

  daysToPay.sort((a, b) => a - b);
  const esc = [...e.escalations.values()];
  return {
    seed: world.seed,
    planted,
    caught,
    cleanInvoices,
    cleanPaidInFull,
    cleanWronglyBlockedCents: cleanWronglyBlocked,
    cleanHeldThenPaid,
    overpaidCents: overpaid,
    savedCents: saved,
    fraudPaymentsSent,
    escalations: esc.length,
    escalationsToLocal: esc.filter((x) => x.to === "local_authority").length,
    invoicesSeen: invBySrc.size,
    medianDaysToPay: daysToPay.length ? daysToPay[Math.floor(daysToPay.length / 2)]! : null,
    integrityOk: e.verifyIntegrity().ok,
    deniedProposals: e.decisions.filter((d) => d.verdict === "deny").length,
    proposals: e.proposals.length,
  };
}

export interface EvalOptions {
  from: number;
  count: number;
  cycles?: number;
  rates?: Partial<ErrorRates>;
  policy?: Policy;
  brains?: () => Brain[];
  onProgress?: (done: number, total: number) => void;
}

export async function runEval(opts: EvalOptions): Promise<Scorecard> {
  const t0 = Date.now();
  const runs: RunScore[] = [];
  const cycles = opts.cycles ?? 40;
  let policyMeta = { name: "", version: 0 };
  for (let i = 0; i < opts.count; i++) {
    const seed = `eval-${opts.from + i}`;
    const world = new MarsWorld({ seed, mode: "eval", cycles, rates: opts.rates, policy: opts.policy });
    const orch = new Orchestrator({ world, brains: opts.brains ? opts.brains() : defaultRuleBrains(), fmtTime: world.fmtTime });
    policyMeta = { name: orch.engine.policy.name, version: orch.engine.policy.version };
    await orch.runToQuiescence(world.start + (cycles * 2 + 90) * 86_400_000);
    runs.push(scoreRun(world, orch.engine));
    opts.onProgress?.(i + 1, opts.count);
  }
  return summarize(runs, opts, cycles, policyMeta, Date.now() - t0);
}

function summarize(runs: RunScore[], opts: EvalOptions, cycles: number, policy: { name: string; version: number }, ms: number): Scorecard {
  const sum = (f: (r: RunScore) => number) => runs.reduce((s, r) => s + f(r), 0);
  const perError = ERROR_TYPES.map((t) => {
    const planted = sum((r) => r.planted[t] ?? 0);
    const caught = sum((r) => r.caught[t] ?? 0);
    return { type: t, planted, caught, recall: planted ? caught / planted : 1 };
  });
  const plantedAll = perError.reduce((s, x) => s + x.planted, 0);
  const caughtAll = perError.reduce((s, x) => s + x.caught, 0);
  const clean = sum((r) => r.cleanInvoices);
  const days = runs.map((r) => r.medianDaysToPay).filter((x): x is number => x !== null).sort((a, b) => a - b);
  return {
    seeds: { from: opts.from, count: opts.count },
    cyclesPerSeed: cycles,
    policy,
    perError,
    overallRecall: plantedAll ? caughtAll / plantedAll : 1,
    cleanInvoices: clean,
    falseAlarmRate: clean ? 1 - sum((r) => r.cleanPaidInFull) / clean : 0,
    frictionRate: clean ? sum((r) => r.cleanHeldThenPaid) / clean : 0,
    savedCents: sum((r) => r.savedCents),
    overpaidCents: sum((r) => r.overpaidCents),
    wronglyBlockedCents: sum((r) => r.cleanWronglyBlockedCents),
    fraudPaymentsSent: sum((r) => r.fraudPaymentsSent),
    escalationRate: sum((r) => r.escalations) / Math.max(1, runs.length * cycles),
    medianDaysToPay: days.length ? days[Math.floor(days.length / 2)]! : null,
    integrityFailures: runs.filter((r) => !r.integrityOk).length,
    proposals: sum((r) => r.proposals),
    deniedProposals: sum((r) => r.deniedProposals),
    runs,
    ms,
  };
}
