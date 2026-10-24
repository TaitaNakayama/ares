// Headless run of the demo story (beats 1-7) through the real orchestrator.
import { Orchestrator, defaultRuleBrains } from "@ares/agents";
import { formatCents } from "@ares/engine";
import { MarsWorld } from "@ares/world-mars";

const choice = process.argv[2] ?? "buy";
const world = new MarsWorld({ seed: process.argv[3] ?? "ares-demo", mode: "demo" });
const orch = new Orchestrator({ world, brains: defaultRuleBrains(), fmtTime: world.fmtTime });
orch.on((m) => {
  if (m.type === "narration") console.log(`[${world.fmtTime(m.narration.at)}] ${m.narration.name.padEnd(12)} ${m.narration.outcome === "deny" ? "DENIED " : ""}${m.narration.text}`);
});
const e = orch.engine;
await orch.runUntil(world.start);
console.log("--- beat 1");
orch.scheduleAll(world.beatDelivery(e));
await orch.runUntil(e.now + 2 * 3600e3);
console.log("--- beat 2-5");
orch.scheduleAll(world.beatStorm(e));
await orch.runUntil(e.now + 2 * 3600e3);
const esc = [...e.escalations.values()].find((x) => x.status === "awaiting_decision");
console.log("--- escalation", esc?.id, esc?.to, esc?.reason);
for (const o of esc?.options ?? []) console.log("   option", o.id, "|", o.label, "|", o.detail);
const opt = esc?.options.find((o) => o.id.startsWith(choice)) ?? esc?.options.find((o) => o.id.includes(choice));
console.log("--- beat 6: commander chooses", opt?.id);
if (esc && opt) await orch.submitHuman("local_authority", { type: "decide", params: { escalationId: esc.id, optionId: opt.id } });
console.log("--- beat 7");
await orch.runUntil(e.now + 6 * 3600e3);
console.log("cash", formatCents(e.ledger.balance("cash")), "prevented", formatCents(e.prevented.reduce((s, x) => s + x.amount, 0)), "integrity", e.verifyIntegrity().ok, "entries", e.ledger.size);
