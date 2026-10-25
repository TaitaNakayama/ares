import { describe, expect, it } from "vitest";
import { ApRules, ControllerRules, Orchestrator, ReceiverRules, RequesterRules, TreasuryRules } from "@ares/agents";
import { MarsWorld } from "../src/index.ts";

/**
 * The orchestrator's step budget guards one run against a feedback loop. It must be per run, not per session:
 * a server left in Act 4 at 120x sim speed used to reach 50,000 lifetime events within minutes, after which every
 * tick threw "step limit reached" forever (the judge-run server died this way).
 */
describe("step budget", () => {
  it("a small budget is enough for each run, however many runs the session makes", async () => {
    const world = new MarsWorld({ seed: "ares-demo", mode: "demo" });
    const orch = new Orchestrator({ world, brains: [new RequesterRules(), new ReceiverRules(), new ApRules(), new TreasuryRules(), new ControllerRules()], fmtTime: world.fmtTime, maxSteps: 60 });
    const e = orch.engine;
    await orch.runUntil(world.start);
    orch.scheduleAll(world.beatDelivery(e));
    orch.scheduleAll(world.beatStorm(e));
    let events = 0;
    orch.on((m) => { if (m.type === "engine") events++; });
    // A whole sol in one-minute ticks (how the server runs): far more than 60 engine events in all, never 60 in one tick.
    for (let i = 0; i < 24 * 60; i++) await orch.runUntil(e.now + 60_000);
    expect(events).toBeGreaterThan(60);
  });
});
