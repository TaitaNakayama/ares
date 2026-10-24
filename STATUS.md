# STATUS

_Updated Fri 2026-10-23 22:35 PT_

## Works
- **Engine** (world-agnostic): double-entry ledger, policy engine, three-way match, escalations, verifications, audit trail, trace-to-source, per-actor credentials.
  - Opus adversarial review, three rounds: 21 + 17 + 19 findings, all fixed, including the two low-severity items (E7, E9).
  - 73 tests pass, plus 45 blocked-exploit repros and a property-based fuzz.
- **Agents:** rule brains for all five roles. The orchestrator binds each agent's identity, so the LLM can never choose its own. Rogue mode swaps in a malicious Rule Keeper; a test proves every attempt is refused.
- **Mars world:**
  - real Mars24 sun, real Earth-Mars light time (12.5 min);
  - power model calibrated to Opportunity's 2018 storm;
  - seeded suppliers and prices, planted errors with an answer key;
  - Earth CFO and commander simulators, demo director.
- **Demo story (beats 1-7)** runs end to end from the real engine, headless and live through the server.
- **Eval harness**, held-out seeds 5000-5099: 100% recall on every blatant error type, 35% on subtle +3-7% overpricing, 0 payments to fraud accounts, 0 integrity failures.
- **Server:** HTTP + WebSocket on :8787.
  - The control API answers only on loopback. The headset authenticates with a per-machine token that `scripts/build-ios.sh` bakes into the app.
  - Verified from the LAN: the API returns 403, a WebSocket without the token closes with 4401, and a WebSocket with the token is accepted.
- **Laptop console** (React): live feed, ledger trace, audit, queues, policy editor, injector, scorecard. The header now shows headset status (fps, or "not connected").
- **Native VR app (AresVR):** stereo through the Cardboard distortion at 60 fps on the iPhone 16 Pro, gaze reticle, tap handling, live link, offline replay.
  - Soak test on the charger: 20 min at 59.9-60.1 fps, thermal "fair".

## Blocked right now
- **The phone isn't reachable.** The Mac moved to the 10.20.50.x Wi-Fi, and devicectl shows the phone as "unavailable".
  - The app currently on the phone predates the headset token, so the server will refuse it off loopback.
  - The new build is compiled and ready. It tries the Mac's current IP, its `.local` name and the whole hotspot range 172.20.10.2-14.

## Needs you
- Put the phone and the Mac on the same network (same Wi-Fi, or the Mac back on the iPhone hotspot). Keep the phone unlocked so I can reinstall it.
- Viewer checklist (in the terminal).
- Yes or no on a public GitHub repo.
- Optional: `OPENAI_API_KEY` in `.env`.

## Cut
- Second real dataset (BPI Challenge 2019): 4TU.ResearchData was unreachable on both networks.

## Decisions since the plan
- **Native iOS instead of Unity.** Unity's 2026-06-30 terms, §17.2(ff), bar AI agents and CLI tools from driving Unity without an authorized gateway. Native also builds and deploys fully headless.
