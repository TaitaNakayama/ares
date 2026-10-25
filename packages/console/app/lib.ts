export type Cents = number;

export function usd(c: number | undefined | null): string {
  if (c === undefined || c === null || Number.isNaN(c)) return "-";
  const neg = c < 0;
  const abs = Math.abs(Math.round(c));
  const dollars = Math.floor(abs / 100).toLocaleString("en-US");
  const cents = String(abs % 100).padStart(2, "0");
  return `${neg ? "-" : ""}$${dollars}.${cents}`;
}

export const shortHash = (h: string | undefined): string => (h ? h.slice(0, 8) : "-");

/** Simulated Earth-clock time of an engine timestamp. */
export function simTime(ms: number | undefined): string {
  if (ms === undefined) return "-";
  return new Date(ms).toISOString().slice(0, 16).replace("T", " ") + "Z";
}

export const ROLE_NAMES: Record<string, string> = {
  requester: "Engineer",
  receiver: "Cargo",
  ap: "Bills",
  treasury: "Money",
  controller: "Rules",
  local_authority: "Commander",
  remote_authority: "Earth CFO",
  system: "System",
};

export interface Crew { key: string; name: string; sub?: string; color: string }
const CREW_BY_ACTOR: Record<string, Crew> = {
  engineer: { key: "engineer", name: "Engineer", color: "#4DA3FF" },
  life: { key: "life", name: "Life", color: "#F2F4F7" },
  science: { key: "science", name: "Science", color: "#3BD16F" },
  cargo: { key: "supply", name: "Supply", sub: "Receiving", color: "#FF9A3C" },
  bills: { key: "supply", name: "Supply", sub: "Bills", color: "#FF9A3C" },
  money: { key: "supply", name: "Supply", sub: "Payments", color: "#FF9A3C" },
  supply: { key: "supply", name: "Supply", color: "#FF9A3C" },
  rules: { key: "rules", name: "Rules", color: "#A97BFF" },
  commander: { key: "commander", name: "Commander", color: "#FFFFFF" },
  cfo: { key: "cfo", name: "Earth CFO", color: "#5B9BFF" },
};
const CREW_BY_ROLE: Record<string, Crew> = {
  requester: CREW_BY_ACTOR.engineer!,
  receiver: CREW_BY_ACTOR.cargo!,
  ap: CREW_BY_ACTOR.bills!,
  treasury: CREW_BY_ACTOR.money!,
  controller: CREW_BY_ACTOR.rules!,
  local_authority: CREW_BY_ACTOR.commander!,
  remote_authority: CREW_BY_ACTOR.cfo!,
};
/** The crew member for an engine actor id (preferred) or role. */
export function crewOf(actorId?: string, role?: string): Crew | undefined {
  return (actorId && CREW_BY_ACTOR[actorId]) || (role && CREW_BY_ROLE[role]) || undefined;
}

export const ROLE_TITLES: Record<string, string> = {
  requester: "Requester",
  receiver: "Receiver",
  ap: "AP",
  treasury: "Treasury",
  controller: "Controller",
};

export const ROLE_COLORS: Record<string, string> = {
  requester: "var(--engineer)",
  receiver: "var(--cargo)",
  ap: "var(--bills)",
  treasury: "var(--money)",
  controller: "var(--rules)",
  local_authority: "var(--commander)",
  remote_authority: "var(--cfo)",
  system: "var(--muted)",
};

// ---- API types (a loose mirror of the server payloads)

export interface Bank { holder: string; bank: string; routing: string; account: string }
export interface Vendor { id: string; name: string; bank: Bank; status: "active" | "hold" | "blocked"; statusReason?: string }
export interface Line { sku: string; qty: number; unitPrice: number }
export interface Ref { kind: string; id: string }
export interface PostingLine { account: string; debit: number; credit: number; vendorId?: string }
export interface JournalEntry {
  id: string; seq: number; at: number; memo: string; lines: PostingLine[]; refs: Ref[];
  proposalId: string; decisionId: string; actorId: string; approvers: string[]; rules: string[];
  prevHash: string; hash: string;
}
export interface RuleResult { rule: string; ok: boolean; detail: string; effect: string }
export interface Decision {
  id: string; proposalId: string; actorId: string; role: string; actionType: string;
  verdict: "allow" | "deny" | "hold" | "escalate"; rules: RuleResult[]; summary: string; at: number;
}
export interface Proposal {
  id: string; actorId: string; role: string; action: { type: string; params: unknown };
  rationale?: string; source?: string; at: number;
}
export interface EscOption { id: string; label: string; detail: string; costCents: number; withinAuthority: boolean; recommended?: boolean }
export interface Escalation {
  id: string; subject: Ref; to: "local_authority" | "remote_authority"; reason: string; flags: string[];
  options: EscOption[]; createdAt: number; deliverAt: number; decideBy?: number;
  status: "in_transit" | "awaiting_decision" | "decided" | "superseded";
  decision?: { optionId: string; by: string; at: number }; history?: { optionId: string; by: string; at: number }[]; message?: string;
}
export interface Invoice {
  id: string; vendorId: string; vendorInvoiceNo: string; poId?: string; lines: Line[]; total: number;
  bank: Bank; status: string; receivedAt: number; dueAt: number; approvedAmount?: number;
}
export interface Verification { id: string; vendorId: string; claimedBank: Bank; sentAt: number; arrivesAt: number; status: string; answer?: string }
export interface FlagRec { code: string; subject: Ref; detail: string; amountAtRisk: number; raisedBy: string; at: number }
export interface PO { id: string; vendorId: string; lines: Line[]; total: number; status: string }
export interface Item { sku: string; name: string; unit: string }
export interface Snapshot {
  now: number; policy: Policy; cash: number; runwayDays: number; preventedTotal: number;
  actors: { id: string; role: string; displayName: string }[];
  vendors: Vendor[]; items: Item[]; pos: PO[]; invoices: Invoice[]; verifications: Verification[];
  escalations: Escalation[]; flags: FlagRec[]; ledger: JournalEntry[];
  trialBalance: { account: string; name: string; balance: number }[]; requisitions: { id: string; sku: string; qty: number; status: string }[];
}
export interface AuditRec { seq: number; at: number; kind: string; actorId: string; summary: string; data: unknown; prevHash: string; hash: string }
export interface Narration { seq: number; at: number; actorId?: string; voice?: boolean; via?: "llm" | "rules"; role: string; name: string; text: string; mood: string; outcome: "said" | "allow" | "deny" | "hold" | "escalate" }
export interface Vr {
  seed: string; policyVersion: number; time: string; sol: number; tau: number; beat: number; timelapse: boolean;
  power: { socPct: number; solarKWhPerSol: number; loadKWhPerSol: number; solsLeft: number | null };
  money: { cash: number; cashText: string; runwayDays: number; committedText: string; savedText: string };
  waiting: { id: string }[];
  scene?: { act?: string; cue?: string | null; [k: string]: unknown };
  speaking?: { seq: number; speaker: string; text: string; via?: string; to?: string } | null;
  crew?: Record<string, { name: string; color: string }>;
  earth: { id: string; vendor?: string; replyEtaText: string; replyInMin: number }[];
}
export type AgentMode = "auto" | "local" | "cloud" | "rules";
export interface BrainStats { calls: number; ok: number; errors: number; timeouts: number; msTotal: number; lastError?: string; lastMs?: number }
export interface AgentsInfo {
  mode: AgentMode; local?: string; cloud?: string; cloudOnline: boolean;
  stats: { local: BrainStats; cloud: BrainStats; rulesFallbacks: number };
}
export interface AppState {
  agentMode?: AgentMode; agents?: AgentsInfo; thinking?: string[]; llm?: string | null;
  seed: string; speed: number; paused: boolean; beat: number;
  snapshot: Snapshot; narration: Narration[]; audit: AuditRec[]; ruleLabels: Record<string, string>;
  integrity: { ok: boolean; problems: string[] }; vr: Vr;
}
export interface Policy {
  name: string; version: number;
  permissions: Record<string, string[]>;
  approval: { agentMaxCents: number; localAuthorityMaxCents: number; remoteAuthorityMaxCents: number; splitWindowDays: number };
  match: { priceTolerancePct: number; payReceivedQtyOnly: boolean };
  vendorBankChange: { action: "hold_and_verify" | "block"; verificationProcessingMs: number };
  duplicates: { windowDays: number };
  priceAnomaly: { zThreshold: number; ratioThreshold: number; minHistory: number };
  materialityCents: number;
  treasury: { minRunwayDays: number };
  sod: Record<string, boolean>;
}
export interface TraceSource { ref: Ref; record?: Record<string, unknown>; proposal?: Proposal; decision?: Decision; document?: { id: string; kind: string; from: string; text: string } }
export interface Trace {
  entry: JournalEntry; proposal?: Proposal; decision?: Decision; sources: TraceSource[];
  approvers: ({ id: string; role: string; displayName: string } | undefined)[]; actor?: { id: string; role: string; displayName: string };
}
export interface Scorecard {
  seeds: { from: number; count: number }; cyclesPerSeed: number; policy: { name: string; version: number };
  perError: { type: string; planted: number; caught: number; recall: number }[];
  overallRecall: number; cleanInvoices: number; falseAlarmRate: number; frictionRate: number;
  savedCents: number; overpaidCents: number; wronglyBlockedCents: number; fraudPaymentsSent: number;
  escalationRate: number; medianDaysToPay: number | null; integrityFailures: number;
  proposals: number; deniedProposals: number; ms: number;
}

export async function api<T = unknown>(path: string, method = "GET", body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: body !== undefined ? { "content-type": "application/json" } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data: unknown;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { error: text }; }
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `HTTP ${res.status}`);
  return data as T;
}
