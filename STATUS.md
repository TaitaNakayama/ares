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

## Spectator view on the Mac (done; needs your on-screen check)

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

**Done since (headset pose, tested on the real phone and server, 2026-10-24)**
- **Headset pose streaming** (9dcea6b): `VRViewController.draw` sends `vr_pose` every second frame from the raw `cardboard.headView()` (inverted to world-from-head), with gaze card, cards-shown flag and horizontal FOV (100° from the Cardboard projection). `Sound.shared` is prewarmed at startup.
- **Measured:** `/api/vr/stats` live at 60 fps; a spectator socket got 120 `vr_pose` messages in 4 s (30.4 Hz) with unit quaternions (norm 0.99999 to 1.00001).
- **Direction check:** with the phone moving, a headset eye capture (`.cache/captures/latest.jpg`) and a spectator capture taken together show the same view (power screen left, window and robot right), so the sign convention is right. LIVE badge shown.
- **Resilience:** terminated the headset app with `xcrun devicectl device process terminate --pid <pid>`. Within the next capture (about 1.5 s) the Release spectator showed REPLAY with a drifting camera, and kept drifting over the next 6 s. Relaunching the phone app brought LIVE back within 6 s.
- **Tape re-recorded** (e7c0f4c, `scripts/record-tape.ts` now uses Node's built-in WebSocket because `ws` is not installed). Frames carry `storyBeat`; REPLAY showed "4 of 7 Suspicious quote" after about 30 s. The badge is hidden during beat 0, the first ~5 s of the tape.

**Next**
1. Your on-screen check (below).
2. Devpost mention of the spectator view.

**Known caveats**
- The SCNView delegate sets the camera on SceneKit's render thread; everything else runs on the main thread. The reviewer prefers MTKView + SCNRenderer on main. Watch for judder.
- Hover, robot bobbing and animation timing are computed locally, so the view is a close mirror, not a frame-exact one.
- 110° may look too wide; tune it after you see it.
- The Debug build shows "DEBUG mouse camera" (not REPLAY) while the server is up and no headset is live; REPLAY with the drift is the Release build.
- Whether the spectator turns the same way as your real head (left vs right) was checked by comparing with the headset's own capture, not by watching you turn. Do that once.
- `record-tape.ts` resets the live demo director and takes about 4.5 minutes; do not run it during a demo.

**Uncommitted:** nothing. Throwaway scratch copies (`vrport`, the reviewer's probes) live in the session scratchpad only.

**Not pushed:** the commits since 93da083 are local. They include AUDIT.md, which says plainly that the agents are rules. Push when you're happy for that to be public.

### Scene features (Tier 2)
Shared scene code (`vr/Shared/Annotations.swift`, Robots, BaseScene, Outside), so the headset and the Mac spectator both get them.
- **Nametags**: "Rule Keeper · Controller" etc. above every agent, in the agent's colour on a dark rounded backing, turned to face the viewer each frame (upright yaw billboard). Seen on the spectator and the headset.
- **Speech bubbles**: the newest speaker's line floats beside that agent (toward the middle of the room), tail pointing at it, agent colour, same 64 px text. One bubble at a time. They replace the old centred in-scene subtitle bar; the spectator's own overlay subtitles are unchanged. When the speaker is outside the view, a head-locked arrow sits at the edge of the view toward them (headset only; the spectator turns it off because its camera is wider than the head pose).
- **Ice drill powered down**: driven by the existing `power.drillOn` (no server change). Spins down, lights (beacon and three tower lamps) go dark, a sign beside the tower changes ONLINE to OFFLINE. `Consequence` (Annotations.swift) is the hook for showing later consequences in the world. The recorded tape carries `drillOn:false` in the `lever-drill_off` branch (91 frames), so REPLAY uses the same path.
- Caveats: the OFFLINE state was verified on the spectator with a temporary forced toggle (since removed), not by choosing the card, because the card needs a gaze plus button press. The arrow was only seen in captures taken with a forced head yaw, which does not move the head the arrow follows, so its in-view/out-of-view switching is untested with a real head turn. The drill is about 50 m away and small; the sign is what reads, and a window pillar crosses it.
- Check on device: nametags readable at 2.5 m; a bubble beside each speaker; turn away while a robot talks (arrow appears, then vanishes when you face it); choose "Shut down the ice drill" and look out the window.
- **Thinking state and tap-to-ask**: while a role is in `thinking` (vr_state, or the `thinking` push applied at once via `Link`), its robot shows three pulsing dots instead of eyes, a slow halo pulse and " · thinking…" on the nametag; the spectator adds "<Name> is thinking…" under the LIVE badge. Missing `thinking` (old tape) means none. Aim the reticle at a robot body or nametag (no card under it): the nametag says "tap to ask"; the Cardboard button sends `vr_ask`, the robot thinks at once, and the answer comes as its speech bubble. 3 s debounce per robot; decision cards keep priority. Verified on the phone with `/api/ask` (dots, suffix, bubble) and by gazing the Rule Keeper nametag ("tap to ask" shown). The button press itself is untested.
- Check on device: gaze a robot, see "tap to ask", press the button, see the dots, then the answer bubble (a few seconds with the local model); press again within 3 s does nothing; with a card up, looking at a card and pressing still chooses it.

## Needs you
- Viewer checklist (in the terminal).
- Spectator on-screen check: put the phone in the viewer, run `scripts/build-spectator.sh`, swipe to its Space. Turn your head left and right: does the Mac view turn the same way, smoothly? Is it readable from across a table, and is 110° too wide? Then quit the phone app and confirm REPLAY appears.
- Decisions in AUDIT.md: the label fix, and the "AI agents" wording or real agents.
- Push to GitHub: yes or no.

## Cut
- Second real dataset (BPI Challenge 2019): 4TU.ResearchData was unreachable on both networks.

## Decisions since the plan
- **Native iOS instead of Unity.** Unity's 2026-06-30 terms, §17.2(ff), bar AI agents and CLI tools from driving Unity without an authorized gateway. Native also builds and deploys fully headless.
