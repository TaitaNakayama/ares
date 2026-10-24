# STATUS

_Updated Fri 2026-10-23 21:12 PT_

## Works
- **Engine** (world-agnostic): double-entry ledger, policy engine, three-way match, escalations, verifications, audit trail, trace-to-source, per-actor credentials.
  - Opus adversarial review, two rounds: 21 + 17 findings, all cash exploits fixed.
  - 63 tests pass, plus 39 blocked-exploit repros and a property-based fuzz.
- **Agents:** rule brains for all five roles. The orchestrator binds each agent's identity, so the LLM can never choose its own.
- **Mars world:**
  - real Mars24 sun, real Earth-Mars light time (12.5 min);
  - power model calibrated to Opportunity's 2018 storm;
  - seeded suppliers and prices, planted errors with an answer key;
  - Earth CFO and commander simulators, demo director.
- **Demo story (beats 1-7)** runs end to end from the real engine, headless and live through the server.
- **Eval harness:** 20 seeds x 30 cycles. 100% recall on 7 error types, 0% false alarms, $0 overpaid, 0 payments to fraud accounts, integrity OK.
- **Server:** HTTP + WebSocket on :8787, director with time-lapse, console API, event injection, remote frame capture from the headset.
- **Laptop console** (React): live feed, ledger trace, audit, queues, policy editor, injector, scorecard.
- **Terrain:** Jezero near/far OBJ meshes (88k + 68k triangles) plus textures from USGS HiRISE/CTX.
- **Native VR app (AresVR):** stereo through the Cardboard distortion at 60 fps on the iPhone 16 Pro, gaze reticle, tap handling, live link over the hotspot.

## In progress
- Re-recording the offline tape with current prices.
- Demo video tooling: the headset streams a mono 16:9 director-camera view to the Mac (`/api/record/start` and `/api/record/stop` produce an MP4 in `docs/demo/`).
- Spike A viewer check, with you. The full control room build is installed and renders at 60 fps (remote capture).
- Opus review of the native renderer **done**. Critical: no stereo (fixed and verified, disparity -7 to -28 px on near objects). Plus recenter, the QR-hold trap, the profile string, debounce and link fixes.

## Done since the last update
- Control room scene: window onto Jezero terrain, tau-driven sky, fog and sun, panels and drill, five robots with expressive faces and speech bubbles, three wall screens, 2x2 decision cards.
- Offline replay tape (4 branches), recorded from the live server.
- LLM layer (OpenAI Responses API, cached) plus a deterministic parser. Judges can paste any invoice text in the console.
- Honest eval: subtle overpricing recall 35-67% depending on policy; false-flag trade-off in docs/evidence/eval-sweep.txt.

## Needs you
- Viewer checklist for the Ares app (in the terminal).
- Optional: `OPENAI_API_KEY` in `.env`.

## Decisions since the plan
- **Native iOS instead of Unity.** Unity's 2026-06-30 terms, §17.2(ff), bar AI agents and CLI tools from driving Unity without an authorized gateway. Native also builds and deploys fully headless. Proceeding unless you object.
