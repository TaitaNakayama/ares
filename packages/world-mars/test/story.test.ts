import { describe, expect, it } from "vitest";
import { defaultRuleBrains, Orchestrator } from "@ares/agents";
import { MarsWorld } from "../src/index.ts";

describe("story beat", () => {
  it("follows the demo from the delivery (1) to Earth's verdict (7), every beat in order", async () => {
    const world = new MarsWorld({ seed: "ares-demo", mode: "demo" });
    const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
    const e = orch.engine;
    const seen: number[] = [];
    const note = () => { const b = world.storyBeat(e); if (b !== seen.at(-1)) seen.push(b); };
    orch.on(() => note());
    await orch.runUntil(world.start);
    note();
    orch.scheduleAll(world.beatDelivery(e));
    await orch.runUntil(e.now + 2 * 3600e3);
    orch.scheduleAll(world.beatStorm(e));
    // Earth's answer comes after the light-time round trip (~25 min), so stop before it: the commander decides first.
    await orch.runUntil(e.now + 35 * 60e3);
    expect(world.storyBeat(e)).toBe(6);
    const esc = [...e.escalations.values()].find((x) => x.status === "awaiting_decision" && x.to === "local_authority")!;
    const buy = esc.options.find((o) => o.id.startsWith("buy-"))!;
    await orch.submitHuman("local_authority", { type: "decide", params: { escalationId: esc.id, optionId: buy.id } });
    await orch.runUntil(e.now + 6 * 3600e3);
    expect(world.storyBeat(e)).toBe(7);
    expect(seen).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });
});
