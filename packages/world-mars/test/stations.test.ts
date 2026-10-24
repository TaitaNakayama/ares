import { describe, expect, it } from "vitest";
import { MarsWorld } from "../src/world.ts";
import { Orchestrator, defaultRuleBrains } from "@ares/agents";

/** Part 1 of the demo: pad (beat 1) -> science -> solar (beat 2) -> door -> inside. The story beats are unchanged. */
describe("outdoor stations", () => {
  it("runs the stations in order, the scientist speaks without being an agent, and entering starts part 2", async () => {
    const world = new MarsWorld({ seed: "stations", mode: "demo" });
    const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
    const e = orch.engine;
    await orch.runUntil(world.start);
    expect(world.part).toBe("outside");
    expect(world.station).toBeUndefined();
    orch.scheduleAll(world.beatPad(e));
    await orch.runUntil(e.now + 30 * 60_000);
    expect(world.station).toBe("pad");
    expect(world.beat).toBe(1);
    expect(e.receipts.size).toBe(1);
    orch.scheduleAll(world.beatScience(e));
    await orch.runUntil(e.now + 5 * 60_000);
    const sci = orch.narration.filter((n) => n.role === "scientist");
    expect(sci.length).toBe(2);
    expect(sci[0]!.name).toBe("Science Officer Okonkwo");
    expect(e.proposals.some((p) => p.actorId === "scientist")).toBe(false);
    orch.scheduleAll(world.beatSolar(e));
    await orch.runUntil(e.now + 3 * 60_000);
    expect(world.station).toBe("solar");
    expect(world.beat).toBe(2);
    expect(orch.narration.filter((n) => n.role === "requester").at(-1)?.text).toContain("get inside");
    orch.scheduleAll(world.beatDoor());
    expect(world.station).toBe("door");
    world.enter();
    expect(world.part).toBe("inside");
    await orch.runUntil(e.now + 30 * 60_000);
    expect(e.requisitions.size).toBe(2); // the battery need arrived with the storm
  });
});
