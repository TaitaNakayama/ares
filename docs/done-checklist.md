# "Done means" checklist

Status as of Fri 2026-10-23 21:45 PT. Re-verify everything Sunday 05:30-08:00.

| # | Item | How to verify | Status |
|---|---|---|---|
| 1 | Evaluation runs on a fresh, never-seen seed range | `node packages/eval/src/main.ts --seeds 100 --from <new>`, or console → Scorecard with a new "from" | ✅ Fri 21:00: seeds 5000-5099. 100% recall on every type except subtle overpricing (35%). 0 fraud payments, 0 integrity failures ([evidence](evidence/eval-heldout-5000.txt)) |
| 2 | Any ledger entry traces to its source | Console → Ledger → click any entry | ✅ The trace shows request/quote/PO/receipt/invoice/payment, every rule, the proposing agent, approvers and the source document text |
| 3 | A policy edit changes behavior | Console → Policy: Commander limit $12M → $5M → Apply → Reset → Autoplay. The option reads "Buy 6" | ⏳ server persistence implemented Fri 21:35; run it on stage Sat |
| 4 | Full demo run on the phone in the viewer at steady fps | Autoplay; headset in the viewer | ⏳ renders at 60 fps (remote captures, stereo verified). **Waiting on your viewer check** |
| 5 | A judge-invented event is handled sensibly | Console → Inject → Paste a document (new bank, overbilling) | ✅ Fri 20:55: the parser read messy text and the controls flagged price/bank/contract/qty, rejected it and opened a verification |
| 6 | Screen-recording backup exists | Director-camera MP4 in `docs/demo/` + your iOS screen recording of a headset run | 🟡 Director MP4 exists (Fri 21:06; re-record after final polish). iOS screen recording still to do **[YOU]** |
| 7 | New seed → different suppliers, prices, errors | Console → Random seed → Autoplay | ✅ Fri 21:00: judge-1, mars-42 and hyphenate all run correctly with different suppliers and amounts |
| 8 | Offline replay works with no server | Debug `/api/headset/replay`, or turn Wi-Fi off and relaunch | ✅ Fri 21:30 (forced replay on the device) |
| 9 | Every number on screen is cited or tagged SIMULATED | Walk the three wall screens and the console | 🟡 Power and Money screens carry captions. Recheck after polish |
| 10 | Devpost submitted with video, repo link and credits | Devpost page | ⏳ draft in `docs/devpost.md` |
| 11 | Thermal: steady fps through repeated sessions | `scripts/soak.sh 20` (on the charger = worst case), then off the charger | ⏳ running Fri 21:45 |
| 12 | Ledger/permission claims reviewed after the last code change | Opus round 3 | ⏳ running Fri 21:45 |
