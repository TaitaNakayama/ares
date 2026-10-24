import { describe, expect, it } from "vitest";
import { ControllerRules, LlmBrain, ModelRouter, type BrainContext, type LlmProvider, type LlmResponse } from "../src/index.ts";
import { bankAFake, makeEngine, requisitionWithQuotes, T0 } from "../../engine/test/fixtures.ts";

/**
 * The human handoff never depends on the model. If the Rule Keeper asks Earth for verification
 * but doesn't escalate, it gets one focused turn (verification_requested) to escalate with its own
 * options; if it still doesn't, the rules' escalation goes through, labeled rules.
 */
function scripted(responses: Partial<LlmResponse>[]): LlmProvider {
  return { name: "fake", model: "fake-1", async complete() { return { text: "", toolCalls: [], cached: false, model: "fake-1", ...(responses.shift() ?? {}) }; } };
}

function setup() {
  const e = makeEngine();
  const { reqId, quoteIds } = requisitionWithQuotes(e, "BAT", 10, [{ vendorId: "V-A", unitPrice: 80_000, qtyAvailable: 100, bank: bankAFake }], T0 + 10 * 60_000);
  const self = [...e.actors.values()].find((a) => a.role === "controller")!;
  const ctx: BrainContext = { engine: e, self, fmtTime: (t) => new Date(t).toISOString(), itemName: (sku) => e.items.get(sku)?.name ?? sku };
  return { e, ctx, reqId, quoteId: quoteIds[0]! };
}

describe("escalation floor", () => {
  it("model requests verification only, then says it is waiting: the rules' escalation follows", async () => {
    const { e, ctx, reqId, quoteId } = setup();
    const brain = new LlmBrain({ role: "controller", rules: new ControllerRules(), router: new ModelRouter(scripted([
      { toolCalls: [{ name: "request_verification", args: { vendorId: "V-A", subject: { kind: "quote", id: quoteId }, say: "Asking Earth to verify the new bank details." } }] },
      { text: "Waiting for Earth." },
    ])) });
    const first = await brain.react({ kind: "world", at: e.now, event: { type: "rfq_closed", requisitionId: reqId } }, ctx);
    expect(first.map((i) => [i.type, i.via])).toEqual([["request_verification", "llm"]]);
    const ver = e.submit({ actorId: ctx.self.id, type: first[0]!.type, params: first[0]!.params });
    expect(ver.decision.verdict).toBe("allow");
    const second = await brain.react({ kind: "engine", event: { seq: 1, at: e.now, type: "verification_requested", data: { verification: e.verifications.get(ver.created!.id), expectedReplyAt: e.now + 60 * 60_000 } } }, ctx);
    expect(second.map((i) => [i.type, i.via])).toEqual([["escalate", "rules"]]);
    expect(second[0]!.rationale).toContain("escalation floor");
    expect(e.submit({ actorId: ctx.self.id, type: "escalate", params: second[0]!.params }).decision.verdict).toBe("allow");
  });

  it("model escalates itself at the verification turn, with options: no rules escalation is added", async () => {
    const { e, ctx, reqId, quoteId } = setup();
    const brain = new LlmBrain({ role: "controller", rules: new ControllerRules(), router: new ModelRouter(scripted([
      { toolCalls: [{ name: "request_verification", args: { vendorId: "V-A", subject: { kind: "quote", id: quoteId } } }] },
      { toolCalls: [{ name: "escalate", args: { subject: { kind: "requisition", id: reqId }, reason: "Deadline before Earth's answer.", options: [{ label: "Reject for now", action: { type: "reject_requisition", params: { requisitionId: reqId, reason: "no clean quote" } } }], say: "Commander, your call: Earth can't answer in time." } }] },
    ])) });
    const first = await brain.react({ kind: "world", at: e.now, event: { type: "rfq_closed", requisitionId: reqId } }, ctx);
    e.submit({ actorId: ctx.self.id, type: first[0]!.type, params: first[0]!.params });
    const second = await brain.react({ kind: "engine", event: { seq: 1, at: e.now, type: "verification_requested", data: { verification: [...e.verifications.values()][0], expectedReplyAt: e.now + 60 * 60_000 } } }, ctx);
    expect(second.map((i) => [i.type, i.via])).toEqual([["escalate", "llm"]]);
    expect(second[0]!.say).toContain("Commander");
    const res = e.submit({ actorId: ctx.self.id, type: "escalate", params: second[0]!.params });
    expect(res.decision.verdict).toBe("allow");
    const esc = e.escalations.get(res.created!.id)!;
    expect(esc.options.some((o) => o.proposedBy === ctx.self.id && o.label === "Reject for now")).toBe(true);
  });

  it("model neither verifies nor escalates at rfq_closed: the rules' escalation is added at once", async () => {
    const { e, ctx, reqId } = setup();
    const brain = new LlmBrain({ role: "controller", rules: new ControllerRules(), router: new ModelRouter(scripted([{ text: "Hmm." }])) });
    const out = await brain.react({ kind: "world", at: e.now, event: { type: "rfq_closed", requisitionId: reqId } }, ctx);
    // No action from the model where the rules act: the whole rules answer is used (verification + escalation).
    expect(out.map((i) => i.type)).toEqual(["request_verification", "escalate"]);
    expect(out.every((i) => i.via === "rules")).toBe(true);
  });
});
