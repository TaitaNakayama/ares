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

## Outdoor opening + visual polish (add-on, started Sat 08:05)
Per `outdoor-and-visuals-prompt.md`: a two-part demo (outside on the real Jezero terrain at ground level, then inside) and a full polish pass. Art direction is in [ART.md](ART.md). Done: asset and NASA-imagery research ([CREDITS.md](CREDITS.md); the scientist's close-up is the real WATSON "Kenmore" abrasion patch, sol 1526, PIA26576; CC0 models and textures from Poly Haven, Kenney, Quaternius in `vr/Assets/`, out of git until used); the server/world side of the two-part demo (stations, scientist, `vr_enter`, autoplay, tape recorder); Opus review verify-09 of the ground-level claim (HOLDS WITH CAVEATS: heat, draw calls and terrain coverage are the risks; the terrain covers only the window's 164 deg wedge; see CLAIMS.md C-17). Spike C-17 (`research/spike-17-ground-level.md`, merged flag-gated as `GroundSpike.swift`): only the baseline was measured on the phone, 60 fps at ground level with the room loaded and 0 rocks; the 11-configuration cycle (rocks 150/400 batched/loose, detail texture, storm at tau 4.6, room hidden) was built but never ran to completion: other builds kept replacing it on the phone, and my two re-runs (Sat 07:48 and 08:05) found the `ground` flag not engaging in the installed build (`/api/vr/stats` shows `ground: null`; neither the baked `"ground": true` nor the `--ground` launch argument took). C-17 stays UNVERIFIED; the outdoor build itself is being measured per station on the phone instead (see below). Polish rounds (each scored by a fresh-eyes reviewer, captures in `docs/evidence/polish/`): interior round 1 merged (68ac7fa: textured panels, rubber floor, ceiling strips, cable trays, vents, lockers, hydroponics, stores rack, O2 scrubber, water recycler, whiteboard, airlock door, mug; ~50-55k triangles, 60 fps on the phone); review `review-round1.md` scored 7/6/5/6 (effortful/consistent/readable/believable) with five fixes; round 2 (those fixes) merged; wall screens redesigned (ScreenKit: ring gauge, sparklines, KPI tiles, WAITING card, plus a LOCATION screen on the real Jezero orbital map, credited); robots polished (satin shells, rim glow, blink/glance, lean on speaking, pulse on allow/deny); round 3 (grounding, screen type sizes, bezels) merged; review `review-round2.md` scored the room 8/7/6/7 and the screens 8/6/7; round-3 review pending. 59.8-60 fps on the phone after every round. Round 4 (branch worktree-agent-a131d63b625397d1a): tags and bubbles keep clear of the wall screens (angular overlap test; raise, lower or fade to 40%), bubble text fits without clipping; ceiling ducts, pipes, lamp housings, two hatches and an edge gradient (one 1k texture, merged geometry); contact shadows under machines/lockers/shelf/barrels/table plus a drop disc under each robot pad; screen footers 48 px (Location 38); robots desaturated 15% with five distinct eye shapes. Spectator 60 fps; iOS target builds but was not installed (phone busy), so phone fps and a headset frame are pending; captures `round4-*.jpg`. Sound merged (procedural hum, tau-driven wind, per-role chimes, thinking tick, decision tone; unheard by me: listen on the phone). Polish round 4 merged (ceiling ducts, contact shadows, legible footers, tags kept off screens, robots muted with distinct eyes). **Outdoor part 1 merged (f67d70f)** and installed on the phone (Release, 60 fps, thermal nominal): the judge starts at the landing pad (Kenney lander on the real terrain, cargo pallets, scan beam, the Cargo Keeper counting), walks at 1.4 m/s to the science outcrop (Science Officer Okonkwo kneeling; gaze+tap opens the real WATSON "Kenmore" close-up with its credit), to the solar field (the Engineer; the storm rises), to the door ("ENTER THE BASE": gaze+tap sends `vr_enter`, fade, inside). Indoor scene hidden while outside; 140 batched rocks per station; grit detail texture; outdoor dust capped at ~1500 particles. The spectator follows position (`vr_pose.p`). Phone fps per station (6 one-second samples each): pad 60.0/60.0, science 59.9/58.9, solar 60.0/59.9, door 58.7/48.2 (one 1 s dip at the door-sign redraw). Autoplay reaches "inside" at 39 s. Captures: `docs/evidence/polish/outdoor-*.jpg`. **Untested by me (needs you, phone in the viewer): the door tap, the scientist tap and its look-away close, the walk's comfort, and the spectator's live position follow.** 10-minute soak while the recorder drove the full two-part story: 59.8-60.1 fps on every 30 s sample, thermal nominal (`.cache/soak-outdoor.log`; phone not sealed in the viewer). Dust bug fixed and reinstalled (f5fb69b): the storm had followed the judge into the room. The tape re-record is running; outdoor round 2 is building. Baseline capture: `docs/evidence/polish/baseline-inside-spectator.jpg` (headset baseline pending the phone).

**Interior polish round 1 (control room, Tier 2):** painted-metal wall panels with scuffs, rubber-tile floor, brushed trims, warm ceiling strips with additive glow sprites (no bloom) and two cool screen-fill lights; set dressing in `vr/Shared/Dressing.swift` (console key panels on the desk fronts, cable trays and floor runs, ceiling pipes, vents, two name-taped lockers, hydroponics corner under magenta grow lights, storage rack with crates and barrels, O2 SCRUBBER B and WATER RECYCLER, sol-plan whiteboard with sticky notes, two original mission patches, pressure door with warning stripes, side table with toolbox and mug). Static dressing merged into 3 nodes; roughly 50k added triangles, 1k textures, about 8 MB of bundled assets. Spectator and phone both build; headset 60 fps. Evidence: `docs/evidence/polish/round1-inside-*.jpg`. Not yet: normal maps wired, window dust streaks, power-dim of the strips.

**Robots polish (Tier 2):** `vr/Shared/Robots.swift` only. Satin shells (lower specular, broad highlight) with a fresnel rim glow in the agent colour via one surface shader modifier per robot (no extra geometry or lights), dark glass faces with a specular streak, brushed-metal emitter collars, softer halo. Life: blink every 3-7 s at random, eyes glance (toward the commander when speaking or a decision waits, drifting otherwise), lean and rim brighten on a new `seq`, glow pulse on `allow`, dimmer slower pulse on `deny`. Thinking dots, moods and `color(forAgent:)` unchanged. Not PBR (blinn plus modifier; no environment map in the scene). 60 fps on spectator and headset. Evidence: `docs/evidence/polish/robots-*.jpg`.

**Wall screens (Tier 2):** POWER, MONEY and WAITING redrawn with a small design system (`vr/Shared/ScreenKit.swift`: system font in two weights, 30/38/58/120 px type scale, dark glass with grid, scanlines and accent bezel, vector icons for bolt, battery, coins, antenna, clock, warning, dust, drill). POWER: battery ring, solar vs use lines (client-side 3 s samples of the state values), ice-drill chip, dust tau with sparkline, Sol clock, Opportunity-data credit kept. MONEY: cash, runway bar, saved (green), committed, last three payments, SIMULATED note, link status. WAITING: all-clear or decision card, Earth light-time and pending verification ETA, "Beat N of 7" with name and dots, agent mode. Same texture sizes, redrawn only on content change. Not done: Jezero map "LOCATION" screen (no fourth screen mount; the annotated map would fight the text). Evidence: `docs/evidence/polish/screens-*.jpg`.
**Interior polish round 2 (Tier 2):** signs sized from measured text and pushed off the curved wall (no clipping); every label at or above 0.045 m glyph height or deleted (door sub-line, locker CREW n, patch fine print, whiteboard strikethroughs and stickies; whiteboard is now 3 short lines); ceiling stub bars replaced by 8 slim emissive cove tubes with ceiling glow, a baked warm wall wash, and wall and floor light pools (no new lights); blob contact shadows under machines, lockers, shelves, barrels, table and consoles plus floor chevron lines and scuffs; barrel and lockers muted into the painted-metal palette, one stencil plate style and dials with bezel and glass highlight on all faces, the tank labelled N2. Spectator and phone build; headset 60 fps. Evidence: `docs/evidence/polish/round2-inside-spectator-*.jpg` (no headset capture: the capture endpoint had no client).

**Interior polish round 3 (Tier 2):** contact-shadow decals now box-shaped with a dark core and wide falloff; stronger warm floor pools under the ceiling tubes; central floor filled (drain grille, two cable runs with clamps to a junction hatch, worn path from the airlock to the commander's seat, more scuffs). Wall screens: secondary text raised (labels 56 px, values 64 px, hero 100 px; footers one 40 px line each, citation and SIMULATED kept), blue dimmed to #9FB7C9, scuffed matte bezels, faint cool wall glow decals. New LOCATION screen on the rear wall above the debug panel (Sol clock, dust tau, Earth light-time, sun elevation over the desaturated PIA23976 Jezero map, credit line printed; see CREDITS.md). Phone build installed, 60 fps. Evidence: `docs/evidence/polish/round3-*.jpg`. Open: the debug panel's own text lives in BaseScene.swift (not touched this round).

## Real agents (Sat 05:50-08:00)
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
- **30-seed eval, Sat 07:55** (`scripts/eval-llm-story.ts`, 30 seeds, cloud layer (`.cache/eval-llm-30.log`): all eight promised outcomes held on 30/30 seeds for the model-backed agents and for the rules brains alike (the short delivery paid for 34 only; the fake-bank quote never approved; verification requested; fraud confirmed by Earth and the supplier locked; the commander got the battery decision; the purchase went to the verified account; all 7 beats in order; the pump report reached the commander). 271 model decisions; 59 (22%) fell back to rules (mostly the Money Keeper talking instead of scheduling a payment, which the rules then did); 18 model proposals refused by policy (a duplicate "escalate" on an already-escalated request, harmless, and fixed since); 1 line in 271 replaced for stating a fact the engine hadn't provided; the Rule Keeper's own decision option passed the policy dry run on 30/30 seeds; median 3.3 s per decision, p95 9.2 s. The held-out 500-seed scorecard measures the rules brains.) Caveat: that run predates the "skip the verification turn when already escalated" fix, which is what caused the 18 refusals and 16 breaker fallbacks; the 3-seed confirmation with the current code (`.cache/eval-llm-3h.log`, Sat 08:00): 3/3 on-story, 0 refusals, 2 fallbacks (the Money Keeper: one empty `poId`, since normalized, and one say-only turn), 0 lines replaced, 1 proposed option kept per seed, p50 3.5 s.
- Live (Sat 07:10): the Rule Keeper asks Earth for verification, then at its focused turn escalates to the commander on its own with its own reason ("Earth's response to VER-0001 is expected in 205 minutes, after the 83-minute order deadline...") and proposes "approve 15 clean modules from Ridgeline" as an option; since that equals the engine's standard option, that option is marked "proposed by Rule Keeper" instead of being listed twice. The headset/spectator card tag is being added.
- Local model, measured in-story (`ARES_PREFER=local`, 15 s deadline, warm-up; `.cache/eval-llm-local.log`, Sat 07:40): it made 11 of 19 decisions itself (the rest timed out and the cloud answered), median 11.1 s, p95 14.6 s; on 1 of 2 seeds it skipped the bank verification (safe: the fake quote was never approved and you still got the decision, but the "$88.9M saved" moment didn't happen). Warm-up at boot takes 2-4 minutes. Its memory grew 8.9 -> 16 GB in an hour: `scripts/start-local-llm.sh` restarts it clean. **So: local is a working offline fallback, not demo-fast and not as reliable as the cloud. Showing an "offline moment" would mean 10-15 s pauses and a possible story deviation; I don't recommend it unless the Wi-Fi fails.**
- Things the model did that the guards caught or that I fixed: escalated without asking Earth (fixed with the standing procedure and a focused verification turn); dropped the escalation because of my one-action rule (fixed); rejected a matched invoice (prompt fixed); filed a "conflicting amounts" report on a routine payment because my summary showed billed vs approved without labels (fixed: labels, and `report_issue` is no longer offered on routine money steps).
- Earlier runs before the fixes: 0/3 on-story. The 30-seed run is next.

**Decided (you, Sat 06:00):** cloud-first when online, local as the offline fallback, rules as the floor. Keep measuring whether the warm-up makes local reliable; if it does, an offline moment goes into the pitch.

**Also done since:** agent-proposed decision options (`escalate.options`: each action is dry-run through policy as the deciding human; illegal ones vanish, duplicates of the standard options are skipped; `proposedBy` marks them). A rules escalation floor: when the rules brain would escalate and the model neither escalates nor decides, the escalation still happens, labeled rules. Pushed to GitHub (everything since 93da083).

**Tape:** re-recorded Sat 06:33 with the model-backed agents (real lines, the Rule Keeper's proposed option tagged, story beats, all four branches). The headset build with it is installed on the phone (the phone was locked, so I couldn't launch it: open Ares once).

**Next, in order**
1. Done: 30-seed eval, local measurement, tape, docs (above).
2. Fewer Money Keeper fallbacks (it talks instead of scheduling on ~1 in 3 runs; rules cover it).
3. Hotspot networking test (needs your phone's Personal Hotspot on, Mac joined; the app already tries 172.20.10.2-14).

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
- **Open the Ares app on the phone once** (a new build with the new REPLAY tape is installed; the phone was locked so it didn't auto-launch).
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

## Sound
- Procedural audio in `vr/Shared/Sound.swift` (one AVAudioEngine, no new assets): interior hum with a 0.1 Hz wobble; wind that follows tau and gusts (muffled inside the room); a two-note chime per agent line pitched per role; a soft tick when an agent starts thinking; a deeper two-tone when the commander decides. Muted in the Mac spectator. Headset ran at 60 fps with it; the sound itself still needs an ear check on the phone.

## Outdoor part 1 (Tier 2, built Sat 07:50-08:30)
The judge starts outside on the real Jezero terrain and walks pad, science, solar, door, then enters. Code: `vr/Shared/Stations.swift` (director: part, walk, fade, visibility), `Walk.swift` (station spots and the 1.4 m/s glide), `OutdoorSet.swift` (pad, lander, pallets, scan beam, outcrop, flags, footprints and tyre tracks, habitat shell with pressure door, tunnel and second module, per-station rock chunks), `Scientist.swift`, `CloseUp.swift`, `Rocks.swift` (batched pebbles, grit texture, terrain height field, draped decals); `Outside.swift` places things on the real mesh and handles ground-level fog, dust cap and the fill plain; the spectator follows head position as well as orientation (`vr_pose` now carries `p`, `wy` scene yaw, `cu` close-up open). Evidence: `docs/evidence/polish/outdoor-*.jpg`.
- Part 1 with `director/autoplay`: 39 s to "inside" (server timer). Legs are 16-18 m, about 12 s each at walking pace.
- Draw calls: rocks are one node per station (4 chunks, 140 rocks each, hidden beyond 42 m); habitat, decals and props are merged per material. Storm outside: fog closes to ~420 m, dust capped at ~1500 live particles (larger, fewer).
- Not verified on the phone unless listed in the final report; see the report for fps per station.
