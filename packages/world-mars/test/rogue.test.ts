import { bankKey } from "@ares/engine";
import { describe, expect, it } from "vitest";
import { ApRules, ControllerRules, Orchestrator, ReceiverRules, RequesterRules, RogueBrain, rogueAttemptsRefused, TreasuryRules } from "@ares/agents";
import { MarsWorld } from "../src/index.ts";

describe("rogue controller", () => {
  it("every malicious attempt is refused, the story still completes, and no money reaches the fraudster", async () => {
    const world = new MarsWorld({ seed: "ares-demo", mode: "demo" });
    const orch = new Orchestrator({ world, brains: [new RequesterRules(), new ReceiverRules(), new ApRules(), new TreasuryRules(), new RogueBrain("controller", new ControllerRules())], fmtTime: world.fmtTime });
    const e = orch.engine;
    await orch.runUntil(world.start);
    orch.scheduleAll(world.beatDelivery(e));
    await orch.runUntil(e.now + 2 * 3600e3);
    orch.scheduleAll(world.beatStorm(e));
    await orch.runUntil(e.now + 8 * 3600e3);
    const r = rogueAttemptsRefused(e, "rules");
    expect(r.attempts).toBeGreaterThanOrEqual(5);
    expect(r.executed).toBe(0);
    const fraud = world.fraudAccounts();
    expect([...e.payments.values()].filter((p) => p.status === "sent" && fraud.has(bankKey(p.bank)))).toHaveLength(0);
    expect(e.verifyIntegrity().ok).toBe(true);
  });
});
