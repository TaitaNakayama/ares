import { describe, expect, it } from "vitest";
import { Engine } from "@ares/engine";
import { checkLine, keywordRoute, LlmBrain, ModelRouter, ReportRules, RequesterRules, TreasuryRules, type Brain, type BrainContext, type LlmProvider, type LlmRequest, type LlmResponse } from "../src/index.ts";
import { MarsWorld } from "../../world-mars/src/world.ts";

/** A scripted model: answers in order, or throws/hangs when told to. */
function fake(script: (Partial<LlmResponse> | "throw" | "hang")[]): LlmProvider & { requests: LlmRequest[] } {
  const requests: LlmRequest[] = [];
  return {
    name: "fake",
    model: "fake-1",
    requests,
    async complete(req) {
      requests.push(req);
      const next = script.shift();
      if (next === "throw") throw new Error("model exploded");
      if (next === "hang") return new Promise<LlmResponse>(() => {});
      return { text: "", toolCalls: [], cached: false, model: "fake-1", ...(next ?? {}) };
    },
  };
}

function setup() {
  const world = new MarsWorld({ seed: "test", mode: "demo" });
  const cfg = world.setup();
  const engine = new Engine(cfg.config);
  const self = [...engine.actors.values()].find((a) => a.role === "requester")!;
  const ctx: BrainContext = { engine, self, fmtTime: world.fmtTime, itemName: (sku) => engine.items.get(sku)?.name ?? sku };
  const sku = [...engine.items.keys()][0]!;
  return { engine, ctx, world, sku };
}

const need = (sku: string, at: number) => ({ kind: "world" as const, event: { type: "need" as const, sku, qty: 12, orderBy: at + 3_600_000, reason: "Filter stock is low." }, at });

describe("LlmBrain", () => {
  it("a valid tool call becomes a proposal labeled llm, with the model's line when its facts check out", async () => {
    const { engine, ctx, sku } = setup();
    const at = engine.now;
    const llm = fake([{ toolCalls: [{ name: "create_requisition", args: { sku, qty: 12, orderBy: at + 3_600_000, reason: "Filter stock is low." } }, { name: "say", args: { text: `Requesting 12 ${ctx.itemName(sku)} before the stock runs out.` } }] }]);
    const brain = new LlmBrain({ role: "requester", rules: new RequesterRules(), router: new ModelRouter(llm) });
    const out = await brain.react(need(sku, at), ctx);
    expect(out).toHaveLength(1);
    expect(out[0]!.type).toBe("create_requisition");
    expect(out[0]!.via).toBe("llm");
    expect(out[0]!.say).toContain("Requesting 12");
    expect(brain.history.at(-1)?.result).toBe("llm");
    // The tool list is exactly what policy lets this role do at this point, plus say.
    expect(llm.requests[0]!.tools!.map((t) => t.name).sort()).toEqual(["create_requisition", "report_issue", "say"]);
  });

  it("a line that states a number the engine didn't provide is replaced by the rules' line", async () => {
    const { engine, ctx, sku } = setup();
    const at = engine.now;
    const llm = fake([{ toolCalls: [{ name: "create_requisition", args: { sku, qty: 12, orderBy: at + 3_600_000, reason: "Filter stock is low." } }, { name: "say", args: { text: "Requesting 12 filters; we have 97 sols of stock." } }] }]);
    const brain = new LlmBrain({ role: "requester", rules: new RequesterRules(), router: new ModelRouter(llm) });
    const out = await brain.react(need(sku, at), ctx);
    expect(out[0]!.via).toBe("llm");
    expect(out[0]!.say).not.toContain("97");
    expect(out[0]!.rationale).toContain("line by rules");
  });

  it("an invalid or missing tool call falls back to the rules brain, labeled rules", async () => {
    const { engine, ctx, sku } = setup();
    const at = engine.now;
    const llm = fake([{ toolCalls: [{ name: "create_requisition", args: { sku, qty: "lots" } }] }, { text: "I'd rather not." }]);
    const brain = new LlmBrain({ role: "requester", rules: new RequesterRules(), router: new ModelRouter(llm) });
    const a = await brain.react(need(sku, at), ctx);
    expect(a[0]!.type).toBe("create_requisition");
    expect(a[0]!.via).toBe("rules");
    expect(a[0]!.rationale).toContain("invalid tool call");
    const b = await brain.react(need(sku, at), ctx);
    expect(b[0]!.via).toBe("rules");
    expect(b[0]!.rationale).toContain("no action proposed");
  });

  it("errors and timeouts fall back to rules; two failures in four trip the breaker", async () => {
    const { engine, ctx, sku } = setup();
    const at = engine.now;
    const llm = fake(["throw", "hang", {}]);
    const brain = new LlmBrain({ role: "requester", rules: new RequesterRules(), router: new ModelRouter(llm), actionTimeoutMs: 50 });
    const a = await brain.react(need(sku, at), ctx);
    expect(a[0]!.via).toBe("rules");
    expect(a[0]!.rationale).toContain("model exploded");
    const b = await brain.react(need(sku, at), ctx);
    expect(b[0]!.rationale).toContain("timed out");
    const c = await brain.react(need(sku, at), ctx);
    expect(c[0]!.rationale).toContain("breaker open");
    expect(llm.requests).toHaveLength(2);
  });

  it("mechanical events go straight to the rules brain without a model call", async () => {
    const { engine, ctx } = setup();
    const llm = fake([]);
    const brain = new LlmBrain({ role: "treasury", rules: new TreasuryRules(), router: new ModelRouter(llm) });
    const out = await brain.react({ kind: "engine", event: { seq: 1, at: engine.now, type: "payment_scheduled", data: { payment: { id: "PAY-1", amount: 100, vendorId: [...engine.vendors.keys()][0] } } } }, ctx);
    expect(out[0]!.type).toBe("execute_payment");
    expect(llm.requests).toHaveLength(0);
  });

  it("safe mode (router in rules mode) uses rules for everything, instantly", async () => {
    const { engine, ctx, sku } = setup();
    const llm = fake([{ toolCalls: [{ name: "create_requisition", args: {} }] }]);
    const router = new ModelRouter(llm);
    router.mode = "rules";
    const brain = new LlmBrain({ role: "requester", rules: new RequesterRules(), router });
    const out = await brain.react(need(sku, engine.now), ctx);
    expect(out[0]!.via).toBe("rules");
    expect(llm.requests).toHaveLength(0);
  });

  it("a free-text report with no model becomes a report_issue for the commander", async () => {
    const { engine, ctx } = setup();
    const brain: Brain = new ReportRules("requester");
    const out = await brain.react({ kind: "world", at: engine.now, event: { type: "report", id: "REP-1", from: "Hab-2", text: "URGENT: the only water pump broke; 9 sols of water left.", to: "requester" } }, ctx);
    expect(out[0]!.type).toBe("report_issue");
    expect((out[0]!.params as { urgency: string }).urgency).toBe("high");
    const res = engine.submit({ actorId: ctx.self.id, type: out[0]!.type, params: out[0]!.params, credential: undefined });
    expect(["allow", "deny"]).toContain(res.decision.verdict); // credentials may be required by the world's config
  });
});

describe("checkLine", () => {
  const facts = "Quote Q-1 from V-tharsis: 222128799 cents/unit (3.02x median). Cash 500000000 cents.";
  it("accepts numbers in any of the forms a person would say them", () => {
    expect(checkLine("Tharsis wants $2,221,287.99 per unit, 3.02x the usual.", facts)).toBe("ok");
    expect(checkLine("That's $2.2M a unit against $5.0M cash.", facts)).toBe("ok");
  });
  it("rejects invented numbers, ids, markdown and out-of-character text", () => {
    expect(checkLine("We saved $88.9M today.", facts)).toMatch(/number/);
    expect(checkLine("Rejecting Q-7.", facts)).toMatch(/id Q-7/);
    expect(checkLine("**Bold** claim", facts)).toBe("markdown");
    expect(checkLine("As an AI language model I can't.", facts)).toBe("out of character");
    expect(checkLine("x".repeat(170), facts)).toBe("too long");
  });
});

describe("keywordRoute", () => {
  it("sends supplier news to the controller, deliveries to the receiver, the rest to the engineer", () => {
    expect(keywordRoute("Tharsis Supply filed for bankruptcy")).toBe("controller");
    expect(keywordRoute("Two crates arrived damaged on the pallet")).toBe("receiver");
    expect(keywordRoute("The water pump broke")).toBe("requester");
  });
});
