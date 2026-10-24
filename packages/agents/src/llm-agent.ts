import { ACTION_DESCRIPTIONS, ACTION_SCHEMAS, formatCents, type AgentRole, type Engine, type Invoice, type Quote, type Requisition } from "@ares/engine";
import { z } from "zod";
import { compact, type AgentInput, type Brain, type BrainContext, type Intent } from "./brains.ts";
import type { ToolDef } from "./llm.ts";
import { LOCAL_TIMEOUT_MS, type ModelRouter } from "./router.ts";
import type { Mood, WorldEvent } from "./world.ts";

/**
 * One generic LLM brain per role. At a decision point it gets the triggering event and a short
 * state summary (both written by code from engine state), and a tool list that is exactly the
 * actions policy lets this role propose for that event, plus `say` and `report_issue`.
 *
 * Everything it returns is a proposal: the engine checks it like any other. On timeout, error,
 * an invalid or missing tool call, or an off-script line, the role's rules brain answers instead
 * and the intent is labeled `via: "rules"`. Facts in spoken lines are checked against what the
 * engine provided; a line that states a number or id the engine didn't is replaced.
 */

type DecisionTool = keyof typeof ACTION_SCHEMAS | "say";

/** Which events each role reasons about, and with which tools. Anything else is mechanical and goes to the rules brain. */
const DECISION_POINTS: Record<AgentRole, Record<string, DecisionTool[]>> = {
  requester: {
    "world:need": ["create_requisition", "report_issue", "say"],
    "world:report": ["create_requisition", "report_issue", "say"],
    "engine:escalation_decided": ["say"],
  },
  receiver: {
    "world:delivery": ["record_receipt", "report_issue", "say"],
    "world:report": ["report_issue", "say"],
    "engine:escalation_decided": ["say"],
  },
  ap: {
    "engine:invoice_recorded": ["submit_invoice", "raise_flag", "say"],
    "world:report": ["raise_flag", "report_issue", "say"],
    "engine:escalation_decided": ["say"],
  },
  treasury: {
    "engine:requisition_created": ["confirm_funds", "say"],
    "engine:invoice_approved": ["schedule_payment", "say"],
    "world:report": ["report_issue", "say"],
    "engine:escalation_decided": ["say"],
  },
  controller: {
    "world:rfq_closed": ["approve_requisition", "reject_quote", "request_verification", "escalate", "say"],
    "engine:verification_requested": ["escalate", "say"],
    "engine:invoice_submitted": ["approve_invoice", "reject_invoice", "say"],
    "engine:invoice_held": ["reject_invoice", "request_verification", "say"],
    "engine:verification_answered": ["hold_vendor", "approve_requisition", "say"],
    "world:report": ["hold_vendor", "block_vendor", "escalate", "report_issue", "say"],
    "engine:escalation_decided": ["say"],
  },
};

const PERSONAS: Record<AgentRole, string> = {
  requester: "the Engineer (requester): you turn operational needs into purchase requests for catalog items, and hand anything else to the commander with a recommendation.",
  receiver: "the Cargo Keeper (receiver): you record exactly what physically arrived, as counted, and flag anything odd.",
  ap: "the Bill Checker (accounts payable): you enter documents and propose what should be paid after matching them to the order and the receipt.",
  treasury: "the Money Keeper (treasury): you check affordability and schedule approved payments within the cash you have, life-critical suppliers first.",
  controller: "the Rule Keeper (controller): you approve within your limit, reject bad quotes, ask for verification of changed bank details, and escalate what you can't decide.",
};

export interface LlmBrainOptions {
  role: AgentRole;
  /** Same-role rules brain: fallback and the source of safe lines. */
  rules: Brain;
  router: ModelRouter;
  /** Which (role-keyed) events use the model. Default: all of the role's decision points. */
  points?: string[];
  /** Wall-clock deadline for an action decision (default 8 s) and for a free-text report (default 15 s). */
  actionTimeoutMs?: number;
  reportTimeoutMs?: number;
}

export interface LlmOutcome {
  at: number;
  point: string;
  layer?: "local" | "cloud";
  ms?: number;
  result: "llm" | "fallback";
  reason?: string;
  /** Ollama only: prompt tokens read on this call (small = the prefix cache worked) and tokens generated. */
  usage?: { promptTokens: number; promptMs: number; evalTokens: number; evalMs: number };
  /** What the model returned, for diagnosis: tool names and the first words of any prose. */
  raw?: string;
}

const sayTool: ToolDef = {
  name: "say",
  description: "One short line to the crew, under 140 characters, in character. Use it with an action, or alone when no action is right.",
  parameters: { type: "object", required: ["text"], properties: { text: { type: "string" } } },
};

/** The action's own schema plus a `say` field, so one tool call carries both the decision and the line. The engine's schema strips `say`. */
function actionTool(name: keyof typeof ACTION_SCHEMAS): ToolDef {
  const p = z.toJSONSchema(ACTION_SCHEMAS[name]) as Record<string, unknown> & { properties?: Record<string, unknown> };
  delete p.$schema;
  p.properties = { ...p.properties, say: { type: "string", description: "One short line to the crew about this action, under 140 characters, plain, in character." } };
  return { name, description: ACTION_DESCRIPTIONS[name], parameters: p };
}

const SYSTEM_PREFIX =
  "You are one of five procurement agents on a crewed base far from Earth. You act only through the tools given; a deterministic policy engine checks every action and refuses what it must, so propose what you judge right and let it be checked. Use ids, items, vendors and amounts exactly as the state summary gives them; never invent any. Money is in integer cents, times are integer milliseconds. When an action is warranted, call the action tool (its `say` field carries your line) rather than `say` alone. Prefer one action tool call plus one short `say` line (under 140 characters, plain, in character, no markdown; write money as dollars like $632,276.58, never raw cents).";

export class LlmBrain implements Brain {
  readonly role: AgentRole;
  readonly kind = "llm" as const;
  readonly rules: Brain;
  readonly history: LlmOutcome[] = [];
  private readonly router: ModelRouter;
  private readonly points: Set<string>;
  private readonly actionTimeoutMs: number;
  private readonly reportTimeoutMs: number;
  /** Rolling window of recent failures (timeouts, errors, denials): 2 of the last 4 trips the breaker for 60 s. */
  private recent: boolean[] = [];
  private breakerUntil = 0;
  /** The rules' escalation held back while a verification the model asked for gives it a focused chance to escalate with its own options. */
  private pendingFloor?: Intent;
  private lastLlmIntents = new WeakSet<Intent>();

  constructor(opts: LlmBrainOptions) {
    this.role = opts.role;
    this.rules = opts.rules;
    this.router = opts.router;
    this.points = new Set(opts.points ?? Object.keys(DECISION_POINTS[opts.role]));
    this.actionTimeoutMs = opts.actionTimeoutMs ?? LOCAL_TIMEOUT_MS;
    this.reportTimeoutMs = opts.reportTimeoutMs ?? 15_000;
  }

  /** The decision point this input is, if any. */
  pointOf(input: AgentInput): string | undefined {
    const key = `${input.kind}:${input.event.type}`;
    if (!this.points.has(key) || !DECISION_POINTS[this.role][key]) return undefined;
    if (input.kind === "world" && input.event.type === "report" && input.event.to !== this.role) return undefined;
    if (input.kind === "engine" && input.event.type === "escalation_decided") {
      const esc = input.event.data.escalation as { createdBy?: string } | undefined;
      return esc?.createdBy === this.selfId ? key : undefined;
    }
    return key;
  }

  private selfId?: string;

  async react(input: AgentInput, ctx: BrainContext): Promise<Intent[]> {
    this.selfId = ctx.self.id;
    const point = this.pointOf(input);
    if (!point) return this.rules.react(input, ctx);
    // Safe mode: rules by choice, not a fallback.
    if (this.router.mode === "rules") return this.ruleIntents(input, ctx);
    const fallback = async (reason: string, layer?: "local" | "cloud", ms?: number, raw?: string): Promise<Intent[]> => {
      this.history.push({ at: Date.now(), point, layer, ms, result: "fallback", reason, raw });
      this.router.stats.rulesFallbacks++;
      const out = await this.ruleIntents(input, ctx);
      for (const it of out) it.rationale = `${it.rationale} [rules: ${reason}]`;
      return [...out, ...this.takePendingFloor(point, out)];
    };
    if (Date.now() < this.breakerUntil) return fallback("breaker open");

    const tools = DECISION_POINTS[this.role][point]!.filter((t) => t === "say" || ctx.engine.policy.permissions[this.role]?.includes(t));
    const facts = describeEvent(input, ctx);
    const summary = stateSummary(this.role, ctx);
    const isReport = point === "world:report";
    let res;
    try {
      // Stable text first (persona, catalog, vendors), changing text last: the model server reuses the common prefix.
      res = await this.router.complete(
        {
          system: `${SYSTEM_PREFIX}\nYou are ${PERSONAS[this.role]}`,
          user: `STATE:\n${summary}\n\nEVENT:\n${facts}`,
          tools: tools.map((t) => (t === "say" ? sayTool : actionTool(t))),
          // An escalation with proposed options, or a report, needs room; a plain action with a line does not.
          maxOutputTokens: isReport ? 400 : tools.includes("escalate") || tools.includes("report_issue") ? 450 : 200,
        },
        // Escalations with options and reports are long answers: give them the report deadline, and the cloud a little more.
        (() => {
          const long = isReport || tools.includes("escalate");
          return { prefer: isReport ? "cloud" as const : undefined, localTimeoutMs: long ? this.reportTimeoutMs : this.actionTimeoutMs, cloudTimeoutMs: long ? this.reportTimeoutMs + 5_000 : this.actionTimeoutMs + 4_000 };
        })(),
      );
    } catch (err) {
      this.note(false);
      return fallback((err as Error).message);
    }

    // Validate every tool call against the role's tool list and the engine's schemas.
    const actions: Intent[] = [];
    let line: string | undefined;
    const dropped: string[] = [];
    for (const call of res.toolCalls) {
      if (call.name === "say") {
        const t = (call.args as { text?: unknown } | undefined)?.text;
        if (typeof t === "string" && t.trim()) line = t.trim();
        continue;
      }
      if (!tools.includes(call.name as DecisionTool)) {
        dropped.push(`${call.name}: not a tool for this role`);
        continue;
      }
      const name = call.name as keyof typeof ACTION_SCHEMAS;
      const said = (call.args as { say?: unknown } | undefined)?.say;
      if (!line && typeof said === "string" && said.trim()) line = said.trim();
      const normalized = normalize(name, call.args, ctx.engine);
      const parsed = ACTION_SCHEMAS[name].safeParse(normalized.args);
      if (!parsed.success) {
        dropped.push(`${name}: ${parsed.error.issues.map((i) => `${i.path.join(".")} ${i.message}`).join("; ")}`);
        continue;
      }
      const missing = unknownRefs(parsed.data as Record<string, unknown>, ctx.engine);
      if (missing.length) {
        dropped.push(`${name}: refers to ${missing.join(", ")} which do not exist`);
        continue;
      }
      actions.push({ type: name, params: parsed.data, rationale: `${res.layer} ${res.model} in ${(res.ms / 1000).toFixed(1)} s${normalized.notes.length ? ` (${normalized.notes.join("; ")})` : ""}`, via: "llm" });
    }
    if (!line && res.text.trim()) line = res.text.trim().split("\n")[0]!.trim();

    const ruleIntents = await this.ruleIntents(input, ctx);
    const rulesAct = ruleIntents.some((i) => i.type !== "__say");
    if (actions.length === 0 && rulesAct) {
      this.note(false);
      return fallback(dropped.length ? `invalid tool call (${dropped.join(" | ")})` : "no action proposed", res.layer, res.ms, `${res.toolCalls.map((c) => c.name).join(",") || "-"} ${res.text.slice(0, 160)}`.trim());
    }
    if (actions.length > 3) {
      // A turn is a few related actions at most (e.g. request verification, then escalate).
      dropped.push(`${actions.length - 3} extra call(s) dropped`);
      actions.splice(3);
    }

    // The spoken line: checked against the facts the engine provided; otherwise the rules' line.
    const factText = `${facts}\n${summary}\n${JSON.stringify(actions.map((a) => a.params))}`;
    const verdict = line ? checkLine(line, factText) : "no line";
    const ruleLine = ruleIntents.find((i) => (actions[0] ? i.type === actions[0].type : i.say))?.say ?? ruleIntents.find((i) => i.say)?.say;
    const mood = ruleIntents.find((i) => i.mood)?.mood ?? moodFor(actions[0]?.type);
    const spoken = verdict === "ok" ? line! : ruleLine ?? (actions[0] ? `Proposing: ${actions[0].type.replace(/_/g, " ")}.` : undefined);
    this.history.push({ at: Date.now(), point, layer: res.layer, ms: res.ms, usage: res.usage, raw: `${res.toolCalls.map((c) => c.name).join(",") || "-"} ${res.text.slice(0, 160)}`.trim(), result: "llm", reason: [verdict !== "ok" ? `line replaced: ${verdict}` : undefined, ...dropped].filter(Boolean).join("; ") || undefined });
    this.note(true);

    // Rules as the floor for the human handoff: if the rules brain would escalate now and the model neither
    // escalated nor approved, the escalation still happens, labeled as rules.
    const floor = ruleIntents.find((i) => i.type === "escalate");
    const decided = actions.some((a) => a.type === "escalate" || a.type === "approve_requisition" || a.type === "reject_requisition");
    if (floor && !decided) {
      if (actions.some((a) => a.type === "request_verification")) {
        // The model asked Earth first; it gets one focused turn (verification_requested) to escalate with its own options.
        this.pendingFloor = { ...floor, via: "rules", rationale: `${floor.rationale} [rules: escalation floor]`, say: undefined, short: undefined };
      } else {
        actions.push({ ...floor, via: "rules", rationale: `${floor.rationale} [rules: escalation floor]`, say: undefined, short: undefined });
        dropped.push("escalation added by rules");
      }
    }
    actions.push(...this.takePendingFloor(point, actions));
    if (actions.length === 0) {
      // The role had nothing it must do; the model may still speak (a validated line) or stay quiet.
      return spoken ? [{ type: "__say", params: {}, rationale: "", say: spoken, short: shorten(spoken), mood, via: "llm" }] : [];
    }
    // The line goes with the first action; the others are silent proposals (the engine narrates refusals).
    actions.forEach((it, i) => {
      if (i === 0) {
        it.say = spoken;
        it.short = shorten(spoken ?? "");
        if (verdict !== "ok") it.rationale += ` [line by rules: ${verdict}]`;
      }
      it.mood = mood;
      this.lastLlmIntents.add(it);
    });
    return actions;
  }

  /**
   * Warm the model server's prompt-prefix cache for every decision point of this role, so the first
   * real decision doesn't pay for reading ~900 tokens of persona and tool schemas. Local layer only.
   */
  async warmup(ctx: BrainContext): Promise<void> {
    if (!this.router.local) return;
    const summary = stateSummary(this.role, ctx);
    for (const [point, toolNames] of Object.entries(DECISION_POINTS[this.role])) {
      if (!this.points.has(point)) continue;
      const tools = toolNames.filter((t) => t === "say" || ctx.engine.policy.permissions[this.role]?.includes(t));
      const t0 = Date.now();
      try {
        const res = await this.router.complete(
          { system: `${SYSTEM_PREFIX}\nYou are ${PERSONAS[this.role]}`, user: `STATE:\n${summary}\n\nEVENT:\n(warm-up: nothing has happened; reply with say only)`, tools: tools.map((t) => (t === "say" ? sayTool : actionTool(t))), maxOutputTokens: 20 },
          { only: "local", localTimeoutMs: 60_000 },
        );
        this.history.push({ at: t0, point: `warmup ${point}`, layer: res.layer, ms: res.ms, usage: res.usage, result: "llm" });
      } catch (err) {
        this.history.push({ at: t0, point: `warmup ${point}`, result: "fallback", reason: (err as Error).message });
      }
    }
  }

  /**
   * The commander looked at this agent and asked what's going on (or typed a question).
   * Answered live from the current state: a validated line, or the deterministic status line.
   */
  async answer(ctx: BrainContext, question?: string): Promise<{ text: string; via: "llm" | "rules" }> {
    this.selfId = ctx.self.id;
    const summary = stateSummary(this.role, ctx);
    const fallback = statusLine(this.role, ctx);
    if (this.router.mode === "rules" || Date.now() < this.breakerUntil) return { text: fallback, via: "rules" };
    try {
      const res = await this.router.complete(
        {
          system: `${SYSTEM_PREFIX}\nYou are ${PERSONAS[this.role]}`,
          user: `STATE:\n${summary}\n\nThe commander ${question ? `asks: "${question.slice(0, 300)}"` : "looks at you and asks what's going on"}. Answer in one line (under 140 characters) with the facts above: what you are doing or watching right now, and what you need from them, if anything.`,
          tools: [sayTool],
          maxOutputTokens: 120,
        },
        { localTimeoutMs: this.actionTimeoutMs, cloudTimeoutMs: this.actionTimeoutMs },
      );
      const said = (res.toolCalls.find((c) => c.name === "say")?.args as { text?: string } | undefined)?.text ?? res.text.trim().split("\n")[0];
      const line = said?.trim();
      if (line && checkLine(line, `${summary}\n${question ?? ""}`) === "ok") {
        this.history.push({ at: Date.now(), point: "ask", layer: res.layer, ms: res.ms, result: "llm" });
        return { text: line, via: "llm" };
      }
      this.history.push({ at: Date.now(), point: "ask", layer: res.layer, ms: res.ms, result: "fallback", reason: line ? `line replaced: ${checkLine(line, summary)}` : "no line" });
    } catch (err) {
      this.history.push({ at: Date.now(), point: "ask", result: "fallback", reason: (err as Error).message });
    }
    return { text: fallback, via: "rules" };
  }

  /** At the verification_requested turn, the held-back rules escalation goes through unless the model escalated itself. */
  private takePendingFloor(point: string, actions: Intent[]): Intent[] {
    if (point !== "engine:verification_requested" || !this.pendingFloor) return [];
    const floor = this.pendingFloor;
    this.pendingFloor = undefined;
    return actions.some((a) => a.type === "escalate") ? [] : [floor];
  }

  /** Called by the orchestrator with the engine's verdict on one of our intents. */
  observe(intent: Intent, verdict: string): void {
    if (!this.lastLlmIntents.has(intent)) return;
    if (verdict === "deny") {
      this.note(false);
      const last = this.history.at(-1);
      if (last) last.reason = [last.reason, "denied by policy"].filter(Boolean).join("; ");
    }
  }

  private note(ok: boolean): void {
    this.recent = [...this.recent.slice(-3), !ok];
    if (this.recent.filter(Boolean).length >= 2 && this.recent.length >= 2) {
      this.breakerUntil = Date.now() + 60_000;
      this.recent = [];
    }
  }

  private async ruleIntents(input: AgentInput, ctx: BrainContext): Promise<Intent[]> {
    if (input.kind === "world" && input.event.type === "report") return reportFallback(input.event, ctx);
    const out = await this.rules.react(input, ctx);
    return out.map((i) => ({ ...i, via: i.via ?? "rules" }));
  }
}

/** Deterministic handling of a free-text report when no model is available: it always reaches the commander. */
export function reportFallback(ev: Extract<WorldEvent, { type: "report" }>, ctx: BrainContext): Intent[] {
  const urgent = /urgent|critical|injur|down|broke|leak|fire|bankrupt/i.test(ev.text);
  const summary = ev.text.replace(/\s+/g, " ").trim().slice(0, 300);
  return [
    {
      type: "report_issue",
      params: { summary, recommendation: "No catalog action covers this. Needs a human decision.", urgency: urgent ? "high" : "normal" },
      rationale: `report from ${ev.from}`,
      say: `Report from ${ev.from} needs the commander: ${summary.slice(0, 90)}${summary.length > 90 ? "..." : ""}`,
      short: "Report for the commander.",
      mood: urgent ? "worried" : "attentive",
      via: "rules",
    },
  ];
}

/** Rules brain for reports in rules-only mode (no model at all). */
export class ReportRules implements Brain {
  readonly role: AgentRole;
  readonly kind = "rules" as const;
  constructor(role: AgentRole = "requester") {
    this.role = role;
  }
  react(input: AgentInput, ctx: BrainContext): Intent[] {
    if (input.kind !== "world" || input.event.type !== "report" || input.event.to !== this.role) return [];
    return reportFallback(input.event, ctx);
  }
}

// ---------------------------------------------------------------- deterministic repairs of known small-model slips

/** snake_case keys and a few synonyms models like (quantity, vendor) -> the schema's camelCase names. */
const KEY_ALIASES: Record<string, string> = { quantity: "qty", amount_cents: "amount", unit_price: "unitPrice", order_by: "orderBy", vendor: "vendorId", invoice: "invoiceId", quote: "quoteId", requisition: "requisitionId" };
function camelKeys(v: unknown, notes: string[]): unknown {
  if (Array.isArray(v)) return v.map((x) => camelKeys(x, notes));
  if (!v || typeof v !== "object") return v;
  const out: Record<string, unknown> = {};
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    const camel = k.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
    const key = KEY_ALIASES[camel] ?? KEY_ALIASES[k] ?? camel;
    if (key !== k) notes.push(`${k} -> ${key}`);
    out[key] = camelKeys(val, notes);
  }
  return out;
}

function normalize(name: keyof typeof ACTION_SCHEMAS, raw: unknown, e: Engine): { args: unknown; notes: string[] } {
  const notes: string[] = [];
  if (!raw || typeof raw !== "object") return { args: raw, notes };
  const renamed: string[] = [];
  const a = camelKeys(raw, renamed) as Record<string, unknown>;
  if (renamed.length) notes.push(`renamed ${[...new Set(renamed)].join(", ")}`);
  if (name === "report_issue" && a.subject !== undefined) {
    // Models like to "attach" the report to the sender or an invented id; a report needs no subject.
    const s = a.subject as { kind?: string; id?: string } | null;
    if (!s || !s.kind || !s.id || e.lookup(s as never) === undefined) {
      delete a.subject;
      notes.push("dropped subject: not an existing record");
    }
  }
  if (name === "schedule_payment" && a.invoiceId && a.poId) {
    delete a.poId; // the engine wants exactly one reference; the invoice is the one the event named
    notes.push("dropped poId: an invoice payment references only the invoice");
  }
  if (name === "record_receipt" && Array.isArray(a.lines)) {
    a.lines = (a.lines as Record<string, unknown>[]).map((l) => ({ ...l, qtyRejected: l.qtyRejected ?? 0 }));
  }
  for (const k of ["qty", "amount", "unitPrice", "orderBy", "qtyAvailable"]) if (typeof a[k] === "string" && /^\d+$/.test(a[k] as string)) a[k] = Number(a[k]);
  return { args: a, notes };
}

const REF_KEYS: Record<string, string> = { requisitionId: "requisition", quoteId: "quote", invoiceId: "invoice", poId: "po", paymentId: "payment", vendorId: "vendor", escalationId: "escalation", verificationId: "verification" };

/** Ids in the proposal that name records the engine doesn't have (a model slip the engine would refuse anyway). */
function unknownRefs(params: Record<string, unknown>, e: Engine): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(params)) {
    const kind = REF_KEYS[k];
    if (kind && typeof v === "string" && e.lookup({ kind: kind as never, id: v }) === undefined) out.push(`${kind} ${v}`);
    if (k === "subject" && v && typeof v === "object" && e.lookup(v as never) === undefined) out.push(`${(v as { kind: string }).kind} ${(v as { id: string }).id}`);
    if (k === "sku" && typeof v === "string" && !e.items.has(v)) out.push(`item ${v}`);
  }
  return out;
}

// ---------------------------------------------------------------- line validation

/** Numbers and ids a line may state: only those in the facts the engine provided. */
const ID_RE = /\b[A-Z]{1,5}-[A-Z0-9][A-Z0-9-]*\b/g;

export function checkLine(line: string, facts: string): "ok" | string {
  if (line.length > 160) return "too long";
  if (/\n|```|\*\*|#{1,6}\s/.test(line)) return "markdown";
  if (/\b(as an ai|language model|as an assistant|i cannot|i'm sorry)\b/i.test(line)) return "out of character";
  const known = new Set(facts.match(ID_RE) ?? []);
  for (const id of line.match(ID_RE) ?? []) if (!known.has(id)) return `id ${id} not in the facts`;
  const have = numberTokens(facts);
  for (const m of line.replace(ID_RE, "").match(/\d[\d,]*(?:\.\d+)?/g) ?? []) {
    const clean = m.replace(/,/g, "");
    if (!have.has(clean) && !have.has(clean.replace(/\.0+$/, ""))) return `number ${m} not in the facts`;
  }
  return "ok";
}

/** Digit strings in a text, plus the plain-dollar forms of every cents figure, so "$2.2M", "$2,221,288" and "222128799" all count as the same fact. */
function numberTokens(text: string): Set<string> {
  const out = new Set<string>();
  for (const m of text.match(/\d[\d,]*(?:\.\d+)?/g) ?? []) {
    const clean = m.replace(/,/g, "");
    out.add(clean);
    out.add(clean.replace(/\.0+$/, ""));
    const n = Number(clean);
    if (Number.isFinite(n) && Number.isInteger(n) && n >= 1000) {
      // Treat an integer as a cents figure and add how a person would say it.
      const dollars = n / 100;
      for (const v of [formatCents(n), compact(n), String(Math.round(dollars)), dollars.toFixed(2), dollars.toFixed(1)]) for (const d of v.match(/\d[\d,]*(?:\.\d+)?/g) ?? []) out.add(d.replace(/,/g, ""));
    }
  }
  return out;
}

function shorten(s: string): string {
  const first = s.split(/(?<=[.!?])\s/)[0] ?? s;
  return first.length <= 64 ? first : `${first.slice(0, 61)}...`;
}

function moodFor(type?: string): Mood {
  if (!type) return "calm";
  if (/reject|hold|block|verification|escalate|raise_flag/.test(type)) return "suspicious";
  if (/report_issue/.test(type)) return "worried";
  return "calm";
}

// ---------------------------------------------------------------- what the model is told (all written by code from engine state)

function describeEvent(input: AgentInput, ctx: BrainContext): string {
  const e = ctx.engine;
  if (input.kind === "world") {
    const ev = input.event;
    switch (ev.type) {
      case "need":
        return `Operational need: ${ev.qty} x ${ev.sku} (${ctx.itemName(ev.sku)}) must be ordered by ${ev.orderBy} (${ctx.fmtTime(ev.orderBy)}). Reason: ${ev.reason}${ev.context ? ` Context: ${Object.entries(ev.context).map(([k, v]) => `${k}=${v}`).join(", ")}` : ""}`;
      case "delivery": {
        const po = e.pos.get(ev.poId);
        return `Delivery for ${ev.poId}${po ? ` (ordered ${po.lines.map((l) => `${l.qty} x ${l.sku}`).join(", ")} from ${e.vendors.get(po.vendorId)?.name})` : ""}. Counted: ${ev.lines.map((l) => `${l.qtyReceived} x ${l.sku} received, ${l.qtyRejected} rejected`).join("; ")}. Note: "${ev.note}"`;
      }
      case "rfq_closed": {
        const req = e.requisitions.get(ev.requisitionId);
        const minsLeft = req ? Math.round((req.orderBy - e.now) / 60_000) : undefined;
        const replyMins = Math.round((2 * e.remoteLatencyMs + e.policy.vendorBankChange.verificationProcessingMs) / 60_000);
        const cmdLimit = e.limitFor("local_authority");
        return `Quotes are in for requisition ${ev.requisitionId}; decide how to source it.${minsLeft !== undefined ? ` It must be ordered within ${minsLeft} minutes.` : ""} Earth's answer to a bank verification takes about ${replyMins} minutes (light-time round trip plus processing). The on-site commander can approve up to ${cmdLimit} cents (${formatCents(cmdLimit)}) per order. Standing procedure: buy the cheapest quote that passed every policy check and covers the full quantity; a quote whose bank details differ from the vendor master is never approved or rejected on the spot: request_verification (Earth calls the supplier back) AND, when the deadline comes before Earth's answer or no clean quote covers the need within your limit, escalate to the commander now, proposing concrete options with the exact action for each (e.g. approve_requisition of a clean quote for its available quantity within the commander's limit).`;
      }
      case "report":
        return `Report from ${ev.from}: "${ev.text.slice(0, 1500)}"`;
      default:
        return `${ev.type}`;
    }
  }
  const ev = input.event;
  const d = ev.data;
  switch (ev.type) {
    case "requisition_created": {
      const r = d.requisition as Requisition;
      return `New requisition ${r.id}: ${r.qty} x ${r.sku} (${ctx.itemName(r.sku)}), order by ${ctx.fmtTime(r.orderBy)}; estimated cost ${r.qty * e.marketPrice(r.sku)} cents (${formatCents(r.qty * e.marketPrice(r.sku))}). Decide whether funds can cover it.`;
    }
    case "invoice_recorded": {
      const inv = d.invoice as Invoice;
      return `Invoice ${inv.id} recorded: ${invoiceLine(inv, ctx)}. Decide what amount to submit for approval.`;
    }
    case "invoice_submitted": {
      const inv = d.invoice as Invoice;
      return `Invoice ${inv.id} submitted for approval: ${invoiceLine(inv, ctx)}. The three-way match passed policy, and the submitted amount is already the matched amount: approving pays only for what was received, at the agreed price, to the verified account. Standing procedure: approve a submitted invoice whose match passed; reject only one that policy held for a price above the agreement or a missing order.`;
    }
    case "invoice_held": {
      const inv = d.invoice as Invoice;
      const reasons = (d.reasons as { rule: string; detail: string }[]) ?? [];
      return `Invoice ${inv.id} is on hold: ${invoiceLine(inv, ctx)}. Policy reasons: ${reasons.map((r) => `${r.rule}: ${r.detail}`).join("; ")}`;
    }
    case "invoice_approved": {
      const inv = d.invoice as Invoice;
      const already = [...e.payments.values()].filter((p) => p.invoiceId === inv.id && p.status !== "cancelled").reduce((s, p) => s + p.amount, 0);
      return `Invoice ${inv.id} (${inv.vendorInvoiceNo}, ${e.vendors.get(inv.vendorId)?.name}) is approved. It billed ${inv.total} cents (${formatCents(inv.total)}); the approved, payable amount after the three-way match is ${inv.approvedAmount ?? 0} cents (${formatCents(inv.approvedAmount ?? 0)}); ${already} cents already scheduled. Schedule the unpaid approved amount with schedule_payment (invoiceId only; the payment always goes to the verified account on file), or say why you wait.`;
    }
    case "verification_requested": {
      const v = d.verification as { id: string; vendorId: string; subject: { kind: string; id: string } };
      const replyAt = d.expectedReplyAt as number | undefined;
      const q = v.subject.kind === "quote" ? e.quotes.get(v.subject.id) : undefined;
      const req = q?.requisitionId ? e.requisitions.get(q.requisitionId) : undefined;
      const minsReply = replyAt ? Math.round((replyAt - e.now) / 60_000) : undefined;
      const minsLeft = req ? Math.round((req.orderBy - e.now) / 60_000) : undefined;
      const cmdLimit = e.limitFor("local_authority");
      return `Verification ${v.id} is out to Earth for vendor ${v.vendorId} (${e.vendors.get(v.vendorId)?.name}) on ${v.subject.kind} ${v.subject.id}${minsReply !== undefined ? `; the answer is expected in about ${minsReply} minutes` : ""}.${req ? ` Requisition ${req.id} (${req.qty} x ${req.sku}) must be ordered within ${minsLeft} minutes.` : ""} If the deadline comes before Earth's answer, or no clean quote covers the full need within your limit, escalate to the commander now with the reason and up to three concrete options, each with the exact action (e.g. approve_requisition of a clean quote for its available quantity, within the commander's limit of ${cmdLimit} cents = ${formatCents(cmdLimit)}). Otherwise say briefly that you are waiting.`;
    }
    case "verification_answered": {
      const v = d.verification as { id: string; status: string; vendorId: string; subject: { kind: string; id: string }; answer: string };
      return `Verification ${v.id} answered for vendor ${v.vendorId} (${e.vendors.get(v.vendorId)?.name}) on ${v.subject.kind} ${v.subject.id}: status ${v.status}. Answer: "${v.answer}"`;
    }
    case "escalation_decided": {
      const esc = d.escalation as { id: string; subject: { kind: string; id: string }; reason: string };
      const opt = d.option as { label: string; detail: string };
      return `The commander decided your escalation ${esc.id} (${esc.reason.slice(0, 200)}): chose "${opt.label}" (${opt.detail}). Say one line acknowledging it.`;
    }
    default:
      return `${ev.type}: ${JSON.stringify(d).slice(0, 600)}`;
  }
}

function invoiceLine(inv: Invoice, ctx: BrainContext): string {
  const e = ctx.engine;
  const m = e.computeMatch(inv);
  return `${inv.vendorInvoiceNo} from ${e.vendors.get(inv.vendorId)?.name} (${inv.vendorId})${inv.poId ? ` against ${inv.poId}` : ""}: bills ${inv.lines.map((l) => `${l.qty} x ${l.sku} @ ${l.unitPrice}`).join(", ")}, total ${inv.total} cents (${formatCents(inv.total)}). Match: ${m.lines.map((l) => `${l.sku} billed ${l.billedQty}, payable ${l.payQty}${l.alreadyBilled ? `, ${l.alreadyBilled} already paid earlier` : ""}`).join("; ")}; payable total ${m.payable} cents (${formatCents(m.payable)}); ${m.ok ? "match passed" : `issues: ${m.rules.filter((r) => !r.ok).map((r) => r.detail).join("; ")}`}`;
}

/** What an agent says about its work when asked, written by code from engine state. */
export function statusLine(role: AgentRole, ctx: BrainContext): string {
  const e = ctx.engine;
  const open = [...e.requisitions.values()].filter((r) => r.status === "open" || r.status === "escalated");
  const vers = [...e.verifications.values()].filter((v) => v.status === "pending");
  const escs = [...e.escalations.values()].filter((x) => x.status === "awaiting_decision" && x.to === "local_authority");
  const inv = [...e.invoices.values()].filter((i) => i.status === "received" || i.status === "held" || i.status === "submitted");
  const sched = [...e.payments.values()].filter((p) => p.status === "scheduled");
  switch (role) {
    case "requester":
      return open.length ? `${open.length} open request${open.length > 1 ? "s" : ""}: ${open.map((r) => `${r.qty} ${ctx.itemName(r.sku)}`).join(", ")}. Watching the base's needs.` : "No open requests. Watching the base's needs.";
    case "receiver":
      return `${e.receipts.size} deliveries counted so far. ${[...e.pos.values()].filter((p) => p.status === "open" || p.status === "partially_received").length} orders still to arrive.`;
    case "ap":
      return inv.length ? `${inv.length} invoice${inv.length > 1 ? "s" : ""} in checking (${inv.map((i) => i.status).join(", ")}). Every one is matched to order and receipt.` : "No invoices waiting. Everything matched so far.";
    case "treasury":
      return `Cash ${compact(e.ledger.balance("cash"))}, runway ${Math.floor(e.runwayDays())} days${sched.length ? `, ${sched.length} payment${sched.length > 1 ? "s" : ""} scheduled` : ""}. Only verified accounts get paid.`;
    case "controller":
      return escs.length ? `Waiting on your decision: ${escs.length} escalation${escs.length > 1 ? "s" : ""}. ${vers.length ? `${vers.length} bank check${vers.length > 1 ? "s" : ""} out to Earth.` : ""}`.trim() : vers.length ? `${vers.length} bank verification${vers.length > 1 ? "s" : ""} pending with Earth. Nothing moves until they answer.` : `${e.prevented.length ? `${compact(e.prevented.reduce((s, x) => s + x.amount, 0))} kept from going out so far. ` : ""}Checking every approval against policy.`;
  }
}

export function stateSummary(role: AgentRole, ctx: BrainContext): string {
  const e = ctx.engine;
  const lines: string[] = [];
  lines.push(`Catalog: ${[...e.items.values()].map((i) => `${i.sku}=${i.name}`).join("; ")}.`);
  lines.push(`Vendors: ${[...e.vendors.values()].map((v) => `${v.id}=${v.name} (${v.status})`).join("; ")}.`);
  lines.push(`Your approval limit: ${e.limitFor(role)} cents (${formatCents(e.limitFor(role))}).`);
  lines.push(`Time ${e.now} (${ctx.fmtTime(e.now)}). Cash ${e.ledger.balance("cash")} cents (${formatCents(e.ledger.balance("cash"))}), open commitments ${formatCents(e.openCommitments())}, runway ${Math.floor(e.runwayDays())} days.`);
  const reqs = [...e.requisitions.values()].filter((r) => r.status === "open" || r.status === "escalated").slice(-4);
  if (reqs.length) {
    lines.push("Open requisitions:");
    for (const r of reqs) {
      lines.push(`- ${r.id}: ${r.qty} x ${r.sku}, status ${r.status}, order by ${ctx.fmtTime(r.orderBy)}`);
      for (const q of [...e.quotes.values()].filter((q) => q.requisitionId === r.id && (q.status === "open" || q.status === "held"))) lines.push(`  quote ${quoteLine(q, ctx)}`);
    }
  }
  const invs = [...e.invoices.values()].filter((i) => ["received", "held", "submitted", "approved"].includes(i.status)).slice(-4);
  if (invs.length && (role === "ap" || role === "controller" || role === "treasury")) lines.push(`Invoices in progress: ${invs.map((i) => `${i.id} ${i.vendorInvoiceNo} ${i.status}, billed ${i.total} cents${i.approvedAmount !== undefined ? `, approved for payment ${i.approvedAmount} cents` : ""}`).join("; ")}.`);
  const pays = [...e.payments.values()].filter((p) => p.status === "scheduled").slice(-4);
  if (pays.length && role === "treasury") lines.push(`Scheduled payments: ${pays.map((p) => `${p.id} ${p.amount} cents to ${p.vendorId}`).join("; ")}.`);
  const vers = [...e.verifications.values()].filter((v) => v.status === "pending");
  if (vers.length) lines.push(`Pending verifications: ${vers.map((v) => `${v.id} for ${v.vendorId} on ${v.subject.kind} ${v.subject.id}`).join("; ")}.`);
  const escs = [...e.escalations.values()].filter((x) => x.status === "awaiting_decision" || x.status === "in_transit");
  if (escs.length) lines.push(`Open escalations: ${escs.map((x) => `${x.id} on ${x.subject.kind} ${x.subject.id} to ${x.to}`).join("; ")}.`);
  return lines.join("\n");
}

function quoteLine(q: Quote, ctx: BrainContext): string {
  const e = ctx.engine;
  const rules = e.quoteRules(q);
  const failed = rules.filter((r) => !r.ok);
  const pc = e.priceCheck(q.vendorId, q.sku, q.unitPrice);
  return `${q.id} from ${q.vendorId} (${e.vendors.get(q.vendorId)?.name}): ${q.unitPrice} cents/unit (${formatCents(q.unitPrice)}), ${q.qtyAvailable} available, terms ${q.terms}, price ${pc.ratio.toFixed(2)}x the historical median${pc.anomalous ? " (ANOMALOUS)" : ""}; policy checks: ${failed.length ? `FAILED ${failed.map((r) => `${r.rule} (${r.detail})`).join("; ")}` : "all passed"}`;
}
