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

## Real agents (in progress, Sat 05:50)
Decision (your call, Sat 04:50): make the agents real, keep the demo reliable. [AUDIT.md](AUDIT.md) has the audit this started from.

**Done and committed**
- **Honest labels** (3bfae8d): each proposal's `source` is what produced it (`rules`, `llm`, `parser`); the Rogue brain is labeled `rules`.
- **Tier 1 spike C-16, local model** (`scripts/spike-local-llm.ts`, [verify-08](research/verify-08-local-llm.md)): three models compared on this Mac. qwen3.5:9b made valid tool calls 100% and right decisions 58/60 with a warm prompt prefix (median 4.3 s), but a cold ~900-token prompt takes 9-17 s. Opus verdict: FAILS as evidenced, HOLDS WITH CAVEATS once three checks pass (see CLAIMS.md C-16). Ollama 0.40.10 installed via Homebrew; models pulled: qwen3.5:9b (default), qwen3:8b, llama3.1:8b.
- **Three model layers** (`packages/agents/src/router.ts`): local Ollama -> cloud OpenAI (when a key is set and online) -> rules. Per-call deadlines 8 s (action) / 15 s (free-text report), breaker after 2 failures in 4, prefix-stable prompts, model prewarmed at boot. Mode `auto|local|cloud|rules`; `rules` is SAFE MODE (console button, `POST /api/agents/mode`), instant, mid-run.
- **One generic LLM brain per role** (`packages/agents/src/llm-agent.ts`): at each decision point the model gets the event and a code-written state summary; its tools are exactly the actions policy permits that role for that event, plus `say` and `report_issue`. Every proposal still goes through `Engine.submit`. Unknown ids, invented subjects and known small-model slips are caught before submit; lines are checked against the facts the engine provided (numbers, ids, length, character) and replaced by the rules' line when they fail. Mechanical events (executing a scheduled payment, entering structured documents) stay on rules.
- **Reports**: a free-text `report` event, routed to one agent (model, keyword fallback), and an engine action `report_issue` that always becomes an escalation to the commander with the agent's recommendation. Live: the broken pump, the injury and the supplier bankruptcy all reached the commander with sensible recommendations (cloud layer, 6-8 s). Console: Inject -> Report, with the three presets.
- **Thinking state** (`thinking` in `vr_state`, push message): robot face dots, halo pulse, nametag suffix in the headset; "X is thinking…" pill in the spectator.
- **Ask an agent**: look at a robot and tap (`vr_ask`), or `POST /api/ask {role}`: it answers live from the current state (validated line, or a code-written status line).
- **Eval harness** `scripts/eval-llm-story.ts`: full story per seed, LLM vs rules, beats in order, fallbacks and reasons, replaced lines, latency, denials, and the pump report.

**Measured so far (honest)**
- Eval `scripts/eval-llm-story.ts`, 3 seeds, cloud layer (gpt-6.1-sol), Sat 07:05 (`.cache/eval-llm-3g.log`, 3e before it): all 8 promised outcomes hold on 3/3 seeds for the LLM brains and the rules brains alike (short delivery paid for 34 only; fake-bank quote never approved; verification requested; fraud confirmed and supplier locked; the commander got the battery decision; the purchase went to the verified account; all 7 beats in order; the pump report reached the commander). 31 model decisions, 2 fell back to rules, 0 lines replaced, 3 model proposals denied by policy (safe; details now recorded), median 3.5 s per decision, p95 8.9 s. Prevented amount identical to rules on 3/3. A 30-seed run is in progress (`.cache/eval-llm-30.log`).
- Live (Sat 07:10): the Rule Keeper asks Earth for verification, then at its focused turn escalates to the commander on its own with its own reason ("Earth's response to VER-0001 is expected in 205 minutes, after the 83-minute order deadline...") and proposes "approve 15 clean modules from Ridgeline" as an option; since that equals the engine's standard option, that option is marked "proposed by Rule Keeper" instead of being listed twice. The headset/spectator card tag is being added.
- Live, auto mode: the cloud answers in 2-8 s. The local model (qwen3.5:9b) failed its live calls at the 8 s deadline on cold prompts even after the boot warm-up; Ollama's log confirms the prefix cache works (737 of 1144 tokens matched), so the remaining cost is reading ~400 tokens of state plus generation. Its memory grew from 8.9 GB to 16 GB over an hour of runs: restart it before the demo with `scripts/start-local-llm.sh`.
- Things the model did that the guards caught or that I fixed: escalated without asking Earth (fixed with the standing procedure and a focused verification turn); dropped the escalation because of my one-action rule (fixed); rejected a matched invoice (prompt fixed); filed a "conflicting amounts" report on a routine payment because my summary showed billed vs approved without labels (fixed: labels, and `report_issue` is no longer offered on routine money steps).
- Earlier runs before the fixes: 0/3 on-story. The 30-seed run is next.

**Decided (you, Sat 06:00):** cloud-first when online, local as the offline fallback, rules as the floor. Keep measuring whether the warm-up makes local reliable; if it does, an offline moment goes into the pitch.

**Also done since:** agent-proposed decision options (`escalate.options`: each action is dry-run through policy as the deciding human; illegal ones vanish, duplicates of the standard options are skipped; `proposedBy` marks them). A rules escalation floor: when the rules brain would escalate and the model neither escalates nor decides, the escalation still happens, labeled rules. Pushed to GitHub (everything since 93da083).

**Next, in order**
1. Eval re-run with the floor and options (`.cache/eval-llm-3c.log`), then 30 seeds; report honestly next to the rules scorecard. Confirm live that the controller proposes options and they show on the card.
2. Local warm-up measurement (`ARES_PREFER=local node scripts/eval-llm-story.ts --warm --seeds 2`): does the second call per decision point read fewer prompt tokens, and does it land under 8 s?
3. Re-record the REPLAY tape with the final agent setup.
4. README, pitch, Devpost to match exactly what runs.
5. Hotspot networking test (needs your phone's Personal Hotspot on, Mac joined; the app already tries 172.20.10.2-14).

**Needs you**: see "Needs you" below (phone in the viewer: thinking face, tap-to-ask, nametags, bubbles, drill OFFLINE; the spectator on screen).

## Agent audit
- See [AUDIT.md](AUDIT.md): the starting point (rules engine with personas). Labels fixed Sat 04:45; the "Five AI agents" wording is now being made true (section above) and the pitch/README/Devpost will be updated to exactly what runs.

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
- **Proposed-by tag**: decision-card options carry `proposedBy` (optional in `VRState.Option`, so old tapes still decode); a "proposed by Rule Keeper" line in that agent's colour sits under the label on the headset cards and the spectator `DecisionCardView`. Standard options show no tag.
- **Nametags**: "Rule Keeper · Controller" etc. above every agent, in the agent's colour on a dark rounded backing, turned to face the viewer each frame (upright yaw billboard). Seen on the spectator and the headset.
- **Speech bubbles**: the newest speaker's line floats beside that agent (toward the middle of the room), tail pointing at it, agent colour, same 64 px text. One bubble at a time. They replace the old centred in-scene subtitle bar; the spectator's own overlay subtitles are unchanged. When the speaker is outside the view, a head-locked arrow sits at the edge of the view toward them (headset only; the spectator turns it off because its camera is wider than the head pose).
- **Ice drill powered down**: driven by the existing `power.drillOn` (no server change). Spins down, lights (beacon and three tower lamps) go dark, a sign beside the tower changes ONLINE to OFFLINE. `Consequence` (Annotations.swift) is the hook for showing later consequences in the world. The recorded tape carries `drillOn:false` in the `lever-drill_off` branch (91 frames), so REPLAY uses the same path.
- Caveats: the OFFLINE state was verified on the spectator with a temporary forced toggle (since removed), not by choosing the card, because the card needs a gaze plus button press. The arrow was only seen in captures taken with a forced head yaw, which does not move the head the arrow follows, so its in-view/out-of-view switching is untested with a real head turn. The drill is about 50 m away and small; the sign is what reads, and a window pillar crosses it.
- Check on device: nametags readable at 2.5 m; a bubble beside each speaker; turn away while a robot talks (arrow appears, then vanishes when you face it); choose "Shut down the ice drill" and look out the window.
- **Thinking state and tap-to-ask**: while a role is in `thinking` (vr_state, or the `thinking` push applied at once via `Link`), its robot shows three pulsing dots instead of eyes, a slow halo pulse and " · thinking…" on the nametag; the spectator adds "<Name> is thinking…" under the LIVE badge. Missing `thinking` (old tape) means none. Aim the reticle at a robot body or nametag (no card under it): the nametag says "tap to ask"; the Cardboard button sends `vr_ask`, the robot thinks at once, and the answer comes as its speech bubble. 3 s debounce per robot; decision cards keep priority. Verified on the phone with `/api/ask` (dots, suffix, bubble) and by gazing the Rule Keeper nametag ("tap to ask" shown). The button press itself is untested.
- Check on device: gaze a robot, see "tap to ask", press the button, see the dots, then the answer bubble (a few seconds with the local model); press again within 3 s does nothing; with a card up, looking at a card and pressing still chooses it.

## Needs you
- **Phone in the viewer** (everything below is built and installed; the Cardboard button press itself is untested by me):
  - Gaze at a robot: nametag says "tap to ask"; press: thinking dots, then an answer bubble; a second press within 3 s does nothing; card taps still choose cards.
  - Nametags readable; speech bubble beside the speaker with its tail; the edge arrow when the speaker is behind you.
  - The decision card at the storm beat: the "Buy 15 now" option carries "proposed by Rule Keeper" (small tag); choose "Shut down the ice drill" and look out of the window: OFFLINE sign, lights dark.
  - Quit the headset app: the Mac spectator shows REPLAY within ~1.5 s; relaunch: LIVE again.
- **Spectator on screen**: `scripts/build-spectator.sh`, swipe to its Space. Does it turn with your head, smoothly? Readable across a table? Is 110° too wide?
- **Console** (reload): SAFE MODE button and mode group; Inject → Report presets; "thinking…" rows.
- **Hotspot**: turn on your iPhone's Personal Hotspot, join the Mac to it, restart the server (`node packages/server/src/main.ts`), relaunch the headset app: it should find the Mac on 172.20.10.x within a minute (the app tries .2-.14 after the baked addresses). If it doesn't, rebuild once while the Mac is on the hotspot (`scripts/build-ios.sh` bakes the current IPs).
- Before the demo: `scripts/start-local-llm.sh` (fresh Ollama, memory back to ~9 GB), close Chrome and other heavy apps, Mac on power.

## Cut
- Second real dataset (BPI Challenge 2019): 4TU.ResearchData was unreachable on both networks.

## Decisions since the plan
- **Native iOS instead of Unity.** Unity's 2026-06-30 terms, §17.2(ff), bar AI agents and CLI tools from driving Unity without an authorized gateway. Native also builds and deploys fully headless.
