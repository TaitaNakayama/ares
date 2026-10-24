import type { Engine } from "@ares/engine";
import { ApRules, type AgentInput, type Brain, type BrainContext, type Intent } from "./brains.ts";
import { draftEscalation, readInvoice, type LlmProvider } from "./llm.ts";

/**
 * AP with a reader for messy documents. Structured documents go through the rules
 * brain unchanged; a free-text document (no fields) is read by the LLM (or the
 * deterministic parser) into a `record_invoice` proposal, which policy then checks.
 */
export class ApWithReader implements Brain {
  readonly role = "ap" as const;
  readonly kind: "rules" | "llm";
  private readonly rules = new ApRules();
  private readonly llm?: LlmProvider;

  constructor(llm?: LlmProvider) {
    this.llm = llm;
    this.kind = llm ? "llm" : "rules";
  }

  async react(input: AgentInput, ctx: BrainContext): Promise<Intent[]> {
    if (input.kind === "world" && input.event.type === "document" && input.event.doc.kind === "invoice" && !input.event.doc.fields.invoice) {
      const doc = input.event.doc;
      const got = await readInvoice(doc.text, ctx.engine, this.llm);
      if (!got) return [{ type: "__say", params: {}, rationale: "", say: `I couldn't read document ${doc.id}; it needs a human.`, short: "Can't read this document. Needs a human.", mood: "attentive" }];
      const l = got.params.lines[0]!;
      return [
        {
          type: "record_invoice",
          params: { ...got.params, sourceRef: doc.id },
          rationale: `Read ${doc.id} via ${got.via}${got.notes.length ? ` (${got.notes.join("; ")})` : ""}`,
          say: `Read a free-text invoice (${got.via}): ${l.qty} x ${ctx.itemName(l.sku)} from ${ctx.engine.vendors.get(got.params.vendorId)?.name}.`,
          short: `Read a pasted invoice (${got.via}).`,
        },
      ];
    }
    return this.rules.react(input, ctx);
  }
}

/** Drafts the plain-language note on each new escalation (LLM when available). */
export class EscalationDrafter implements Brain {
  readonly role = "controller" as const;
  readonly kind: "rules" | "llm";
  private readonly llm?: LlmProvider;

  constructor(llm?: LlmProvider) {
    this.llm = llm;
    this.kind = llm ? "llm" : "rules";
  }

  async react(input: AgentInput, ctx: BrainContext): Promise<Intent[]> {
    if (input.kind !== "engine" || input.event.type !== "escalation_created") return [];
    const id = (input.event.data.escalation as { id: string }).id;
    const text = await draftEscalation(ctx.engine as Engine, id, this.llm);
    return text ? [{ type: "__draft", params: { escalationId: id, message: text }, rationale: "" }] : [];
  }
}
