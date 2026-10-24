# STATUS

_Updated Sat 2026-10-24 04:25 PT_

## Works
- **Engine** (world-agnostic): double-entry ledger, policy engine, three-way match, escalations, verifications, audit trail, trace-to-source, per-actor credentials.
  - Opus adversarial review, three rounds: 21 + 17 + 17 findings, all fixed, including the two low-severity items (E7, E9).
  - 76 tests pass, plus 45 blocked-exploit repros and a property-based fuzz.
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

- **Headset link with the token, verified on the device** (23:00): live over the venue Wi-Fi (10.20.50.20) and over the USB cable, 60 fps, thermal nominal. It reconnects by itself after a server restart.
  - Bug found and fixed on the way: the app never appended its token, because "client=vr" already contains "t=".
- **LLM reader live** (OpenAI key in `.env`, gpt-6.1-sol, cached). Pasted messy invoices are read by the model. Charges for things we don't stock are left out deterministically and named, so the bank and quantity controls still run.
- **Public repo:** https://github.com/TaitaNakayama/ares. Checked before pushing: no secrets or headset token in history, no Claude attribution, largest file 28 MB.

## Agent audit
- See [AUDIT.md](AUDIT.md). In short, the five agents are deterministic rule brains with templated dialogue. The LLM reads pasted invoices and drafts one escalation note (1 call in the whole story), and decides nothing. Two misleading `llm` labels and the "Five AI agents" claims are flagged there, awaiting your decision.

## Spectator view on the Mac (in progress)

**Done and committed**
- **Server relay** (971636c):
  - read-only `client=spectator` sockets, loopback only;
  - they receive `vr_state`, every agent line (`narration`), the commander's choice (`vr_choice`) and headset connect/disconnect;
  - the head pose (`vr_pose`) is relayed only from the newest token-authenticated headset, after validation;
  - spectators can't decide or steer.
  - `node scripts/spectator-probe.ts` passes 9/9 against the live server.
  - Story beat 1-7 is derived from engine records (`storyBeat`, `world.ts:642`), with a test for the exact order.
- **Shared scene code** (2341c22):
  - the headset's scene files moved to `vr/Shared/`, plus a `Platform.swift` shim. Both apps compile them, and the iOS app still builds (Release).
  - `Link` gains `candidates`, `onMessage`, `setReplay` and `sendPose`; `BaseScene` gains `showsReticle`, `gazedCard` and `cardsShown`; `Sound` gains `muted`.
- **`AresSpectator` macOS app** (`vr/Spectator/`):
  - full screen in its own Space (`--windowed` / `--background` for testing);
  - one undistorted camera at the head position; smoothing time constant 0.10 s when live and 1.2 s easing into the drift; horizontal FOV = headset + 10° (110° by default);
  - overlays: gaze dot, subtitles (every line, at most two at once, 3-9 s reading time), enlarged decision card with the gazed option and the final choice, "N of 7" beat, LIVE/REPLAY badge;
  - demo build: no headset pose, so it plays the recorded run with a drifting camera under REPLAY. Debug build: the live server state with a mouse camera, only while no headset is live.
  - The Release binary has no mouse symbols (`nm`), so the debug camera is compiled out of the demo build.
  - Build: `scripts/build-spectator.sh` (Release) or `--debug`.
- **Tier 1 C-15:** Opus review verify-07 says HOLDS WITH CAVEATS. Offscreen spike passed: the Debug app renders the scene and overlays correctly at 60 fps ([frame](docs/evidence/spectator-spike.jpg)).

**Not done yet (next steps, in order)**
1. **Headset pose streaming.** `VRViewController.draw` must call `link.sendPose(...)` every second frame (30 Hz):
   - pose: the raw `cardboard.headView()`, never the forced or director pose;
   - `gaze: world.gazedCard`, `cards: world.cardsShown`;
   - `fovX = 2·atan(1/projection[0].columns.0.x)` in degrees.

   `Link.sendPose` already exists. Then reinstall with `scripts/build-ios.sh`.
2. **End-to-end test with the phone in hand:** LIVE badge, the camera follows, the gaze dot, the gazed option highlighted, the choice shown on tap.
3. **Resilience test:** quit the headset app or drop Wi-Fi, and the view should show REPLAY with a drift within about 1 s and never freeze. On reconnect, LIVE again.
4. **Re-record the offline tape** (`node scripts/record-tape.ts`), so REPLAY frames carry `storyBeat`. The old tape has none, so the beat badge is hidden during REPLAY.
5. **Your on-screen check** of the full-screen view (below).
6. **ARCHITECTURE.md:** spectator section written; README and Devpost mentions still to add.

**Known caveats**
- The SCNView delegate sets the camera on SceneKit's render thread; everything else runs on the main thread. The reviewer prefers MTKView + SCNRenderer on main. Watch for judder.
- Hover, robot bobbing and animation timing are computed locally, so the view is a close mirror, not a frame-exact one.
- 110° may look too wide; tune it after you see it.
- First-use `Sound.shared` causes a 150 ms hitch on the headset. Prewarm it in `VRViewController`.

**Uncommitted:** nothing. Throwaway scratch copies (`vrport`, the reviewer's probes) live in the session scratchpad only.

**Not pushed:** the commits since 93da083 are local. They include AUDIT.md, which says plainly that the agents are rules. Push when you're happy for that to be public.

## Needs you
- Viewer checklist (in the terminal).
- Spectator on-screen check: `scripts/build-spectator.sh --debug`, then swipe to its Space and drag the view with the mouse. Is it smooth, readable from across a table, and is the 110° view too wide?
- Decisions in AUDIT.md: the label fix, and the "AI agents" wording or real agents.
- Push to GitHub: yes or no.

## Cut
- Second real dataset (BPI Challenge 2019): 4TU.ResearchData was unreachable on both networks.

## Decisions since the plan
- **Native iOS instead of Unity.** Unity's 2026-06-30 terms, §17.2(ff), bar AI agents and CLI tools from driving Unity without an authorized gateway. Native also builds and deploys fully headless.
