import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { z } from "zod";
import { ACTION_SCHEMAS, formatCents, type Engine } from "@ares/engine";

/**
 * LLM layer. The model only ever returns a *proposal* (tool arguments or text); the
 * engine validates every proposal against policy exactly as it does for rule brains.
 * Responses are cached on disk keyed by the full request, so demos replay offline
 * and runs are reproducible.
 */

export interface ToolDef {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface LlmRequest {
  system: string;
  user: string;
  tools?: ToolDef[];
  maxOutputTokens?: number;
}

export interface LlmResponse {
  text: string;
  toolCalls: { name: string; args: unknown }[];
  cached: boolean;
  model: string;
}

export interface LlmProvider {
  readonly name: string;
  readonly model: string;
  complete(req: LlmRequest): Promise<LlmResponse>;
}

/** OpenAI Responses API with function tools (raw fetch: no SDK version risk). */
export class OpenAIProvider implements LlmProvider {
  readonly name = "openai";
  readonly model: string;
  private readonly key: string;
  private readonly timeoutMs: number;

  constructor(key: string, model = process.env.ARES_OPENAI_MODEL ?? "gpt-6.1-sol", timeoutMs = 20_000) {
    this.key = key;
    this.model = model;
    this.timeoutMs = timeoutMs;
  }

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const body = {
      model: this.model,
      input: [
        { role: "system", content: req.system },
        { role: "user", content: req.user },
      ],
      tools: (req.tools ?? []).map((t) => ({ type: "function", name: t.name, description: t.description, parameters: t.parameters })),
      tool_choice: req.tools?.length ? "auto" : undefined,
      max_output_tokens: req.maxOutputTokens ?? 800,
    };
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      const r = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: { authorization: `Bearer ${this.key}`, "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      const j = (await r.json()) as { output?: { type: string; name?: string; arguments?: string; content?: { type: string; text?: string }[] }[]; error?: { message: string } };
      if (!r.ok) throw new Error(`OpenAI ${r.status}: ${j.error?.message ?? "error"}`);
      const toolCalls: LlmResponse["toolCalls"] = [];
      let text = "";
      for (const o of j.output ?? []) {
        if (o.type === "function_call" && o.name) {
          try {
            toolCalls.push({ name: o.name, args: JSON.parse(o.arguments ?? "{}") });
          } catch {
            // malformed arguments are dropped; the caller falls back
          }
        }
        if (o.type === "message") for (const c of o.content ?? []) if (c.type === "output_text" && c.text) text += c.text;
      }
      return { text, toolCalls, cached: false, model: this.model };
    } finally {
      clearTimeout(timer);
    }
  }
}

/** Wraps a provider with an on-disk cache keyed by the exact request. */
export class CachedProvider implements LlmProvider {
  readonly name: string;
  readonly model: string;
  private readonly inner: LlmProvider | undefined;
  private readonly dir: string;

  constructor(inner: LlmProvider | undefined, dir: string) {
    this.inner = inner;
    this.name = inner ? `${inner.name}+cache` : "cache-only";
    this.model = inner?.model ?? "cache";
    this.dir = dir;
    mkdirSync(dir, { recursive: true });
  }

  private key(req: LlmRequest): string {
    return createHash("sha256").update(JSON.stringify({ m: this.model, ...req })).digest("hex").slice(0, 32);
  }

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const file = `${this.dir}/${this.key(req)}.json`;
    if (existsSync(file)) return { ...(JSON.parse(readFileSync(file, "utf8")) as LlmResponse), cached: true };
    if (!this.inner) throw new Error("no LLM available and no cached response");
    const res = await this.inner.complete(req);
    writeFileSync(file, JSON.stringify(res));
    return res;
  }
}

export function providerFromEnv(cacheDir: string): LlmProvider | undefined {
  const key = process.env.OPENAI_API_KEY;
  if (!key && !existsSync(cacheDir)) return undefined;
  return new CachedProvider(key ? new OpenAIProvider(key) : undefined, cacheDir);
}

// ---------------------------------------------------------------- document reading

const invoiceTool = (): ToolDef => ({
  name: "record_invoice",
  description: "Enter the invoice exactly as printed. Use vendorId from the vendor list, amounts in integer cents, times as the given numbers.",
  parameters: z.toJSONSchema(ACTION_SCHEMAS.record_invoice) as Record<string, unknown>,
});

/** Context the model needs to map a document onto system ids. */
function vendorDirectory(e: Engine): string {
  const vs = [...e.vendors.values()].map((v) => `${v.id}: ${v.name}`).join("\n");
  const items = [...e.items.values()].map((i) => `${i.sku}: ${i.name}`).join("\n");
  const pos = [...e.pos.values()].slice(-20).map((p) => `${p.id}: ${p.vendorId} ${p.lines.map((l) => `${l.qty} x ${l.sku} @ ${l.unitPrice}c`).join(", ")}`).join("\n");
  return `Vendors:\n${vs}\n\nItems (sku: name):\n${items}\n\nRecent purchase orders:\n${pos}`;
}

export interface ExtractedInvoice {
  params: z.infer<(typeof ACTION_SCHEMAS)["record_invoice"]>;
  via: "llm" | "parser";
  notes: string[];
  /** Charges left out of the entry because they aren't items we order (e.g. "rush handling"). */
  excluded?: string[];
}

/** Read a free-text invoice into `record_invoice` params: LLM first, deterministic parser as fallback. */
export async function readInvoice(text: string, e: Engine, llm?: LlmProvider): Promise<ExtractedInvoice | undefined> {
  if (llm) {
    try {
      const res = await llm.complete({
        system:
          "You are the accounts-payable clerk of an autonomous procure-to-pay team. You only read documents and propose entries; deterministic controls check everything you propose. Copy what the document says, even if it looks wrong (wrong bank, odd price): flagging is the controls' job. Call record_invoice exactly once.",
        user: `${vendorDirectory(e)}\n\nissuedAt/dueAt: use ${e.now} and ${e.now + 30 * 86_400_000}.\n\nDOCUMENT:\n${text}`,
        tools: [invoiceTool()],
      });
      const call = res.toolCalls.find((c) => c.name === "record_invoice");
      const parsed = call ? ACTION_SCHEMAS.record_invoice.safeParse(call.args) : undefined;
      if (parsed?.success) {
        const notes = [`read by ${res.model}${res.cached ? " (cached)" : ""}`];
        // A charge for something we don't stock is on no order, so it can never be payable. Leave it
        // out of the entry (and say so) so the controls check the rest of the invoice.
        const known = parsed.data.lines.filter((l) => e.items.has(l.sku));
        const excluded = parsed.data.lines.filter((l) => !e.items.has(l.sku)).map((l) => `"${l.sku}" (${formatCents(l.qty * l.unitPrice)})`);
        if (known.length === 0 || excluded.length === 0) return { params: parsed.data, via: "llm", notes };
        return { params: { ...parsed.data, lines: known }, via: "llm", notes: [...notes, `left out ${excluded.join(", ")}: not items we order`], excluded };
      }
    } catch {
      // fall through to the parser
    }
  }
  return parseInvoiceText(text, e);
}

/** Deterministic reader for common invoice layouts (and our generated documents). */
export function parseInvoiceText(rawText: string, e: Engine): ExtractedInvoice | undefined {
  const notes: string[] = [];
  // Bounded input: documents are short; this also keeps the regexes cheap.
  const text = rawText.slice(0, 20_000);
  const lower = text.toLowerCase();
  const vendor = [...e.vendors.values()].sort((a, b) => b.name.length - a.name.length).find((v) => lower.includes(v.name.toLowerCase()));
  if (!vendor) return undefined;
  const no = text.match(/invoice\s*(?:no\.?|number|#)?\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{2,})/i)?.[1] ?? `TXT-${Date.now() % 100000}`;
  const poId = text.match(/\bPO-\d{4}\b/)?.[0];
  const po = poId ? e.pos.get(poId) : undefined;
  const qtyPrice = text.match(/(\d+)\s*(?:x|×|units?|pcs)\s*[^@\n]*@\s*\$?\s*([\d,]+(?:\.\d{2})?)/i);
  const sku = [...e.items.values()].find((i) => lower.includes(i.sku.toLowerCase()) || lower.includes(i.name.toLowerCase()))?.sku ?? po?.lines[0]?.sku;
  if (!qtyPrice || !sku) return undefined;
  const qty = Number(qtyPrice[1]);
  const unitPrice = Math.round(Number(qtyPrice[2]!.replace(/,/g, "")) * 100);
  // Sanity bounds: absurd numbers are a reading problem, not an invoice.
  if (!Number.isSafeInteger(qty) || qty <= 0 || qty > 1_000_000 || !Number.isSafeInteger(unitPrice) || unitPrice <= 0 || unitPrice > 1e11) return undefined;
  const acct = text.match(/account\s*(?:no\.?|number)?\s*[:#]?\s*(\d{6,})/i)?.[1];
  const routing = text.match(/routing\s*[:#]?\s*(\d{9})/i)?.[1];
  const bankName = text.match(/(?:remit to|pay to)[:\s]+(?:[^,\n]*,\s*)?([A-Za-z][A-Za-z ]*?(?:Bank|Trust|Savings|Credit Union|Mercantile))/i)?.[1]?.trim();
  const bank = acct ? { holder: vendor.name, bank: bankName ?? "Unknown bank", routing: routing ?? "000000000", account: acct } : vendor.bank;
  if (!acct) notes.push("no bank details printed; using the master on file");
  return {
    params: { vendorId: vendor.id, vendorInvoiceNo: no, poId, lines: [{ sku, qty, unitPrice }], bank, issuedAt: e.now, dueAt: e.now + 30 * 86_400_000 },
    via: "parser",
    notes,
  };
}

/** Plain-language note for the human authority. LLM-drafted when available; template otherwise. */
export async function draftEscalation(e: Engine, escalationId: string, llm?: LlmProvider): Promise<string | undefined> {
  const esc = e.escalations.get(escalationId);
  if (!esc) return undefined;
  const opts = esc.options.map((o) => `- ${o.label}: ${o.detail}`).join("\n");
  const template = `I need your decision${esc.decideBy ? " before the deadline" : ""}. Why: ${esc.reason}. Options:\n${opts}`;
  if (!llm) return template;
  try {
    const res = await llm.complete({
      system: "You are the controller of an autonomous finance team writing to the human authority. Be brief (max 70 words), plain, factual, no hype. Explain what was blocked and why, then the trade-off between the options. Do not recommend an option the authority cannot take, and do not invent numbers.",
      user: `Escalation ${esc.id} to ${esc.to}.\nReason (from the policy engine): ${esc.reason}\nOptions (already checked against policy):\n${opts}\nCash: ${formatCents(e.ledger.balance("cash"))}.`,
      maxOutputTokens: 300,
    });
    return res.text.trim() || template;
  } catch {
    return template;
  }
}
