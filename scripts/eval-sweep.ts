// Policy sensitivity: how the anomaly threshold trades misses for false alarms.
import { runEval } from "@ares/eval";
import { MARS_POLICY } from "@ares/world-mars";
for (const z of [4, 3, 2.5, 2]) {
  for (const mat of [10_000_000]) {
    const policy = { ...MARS_POLICY, version: 1, priceAnomaly: { ...MARS_POLICY.priceAnomaly, zThreshold: z }, materialityCents: mat };
    const sc = await runEval({ from: 2000, count: 40, cycles: 30, policy });
    const subtle = sc.perError.find((p) => p.type === "subtle_inflated_quote")!;
    console.log(`z>${z} materiality $${mat / 100}: subtle recall ${(100 * subtle.recall).toFixed(0)}%  overall ${(100 * sc.overallRecall).toFixed(1)}%  invoice false alarms ${(100 * sc.falseAlarmRate).toFixed(1)}%  clean quotes flagged ${(100 * sc.quoteFalseFlagRate).toFixed(1)}%  escalations/cycle ${sc.escalationRate.toFixed(2)}  overpaid $${(sc.overpaidCents / 1e8).toFixed(2)}M`);
  }
}
