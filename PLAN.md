# PLAN: Ares (Cal Hacks 13.0, solo)

Last updated: Fri 2026-10-23 19:20 PT. Status of every foundational claim lives in [CLAIMS.md](CLAIMS.md); nothing below marked UNVERIFIED is presented as fact. Research reports with sources: [research/](research/).

**One line:** an AI agent team that runs procure-to-pay on its own (requests, receiving, three-way match, approvals, payments) under hard, deterministic controls, shown working on a crewed Mars base that the user commands from inside a Cardboard VR headset.

---

## 1. Tool decisions

Verification status key: SOURCED = research with 2+ dated sources; REVIEWED = Opus adversarial review done; SPIKED = hands-on test passed; VERIFIED = all four checks passed. (C-xx = claim id in CLAIMS.md.)

| Area | Choice + exact version | Why | Rejected alternative | Risk | Status |
|---|---|---|---|---|---|
| VR engine | **Unity 6000.0.85f1** (6.0 LTS, changeset `ee7790f1426a`, Apple Silicon) + iOS Build Support, **Universal 3D (URP)** template | Cardboard plugin's declared line is 6000.0 (README: 6000.0.58f2+); .68+ has UIScene support; latest 6.0 patch | 6000.3.27f1 (Google only confirmed 6.3 on Android); Built-in RP (failing case in cardboard#696) | Google's stated ceiling was 6000.0.62 (Jul 30). Fallback pins: 6000.0.68f1, then 6000.3.27f1 | SOURCED, review running (C-01) |
| XR plugin | **Google Cardboard XR Plugin v1.36.0** (2026-10-15), git tag `#v1.36.0` | Active (releases every 2-3 months), `resolutions.csv` includes iPhone17,1 (16 Pro), tested on iOS 26.x devices | DIY stereo (more work, no lens profile) | Not tested by Google on a 16 Pro specifically; MSAA double-render bug #442 | SOURCED (C-01, C-03, C-04) |
| iOS build | Unity batchmode `-executeMethod` -> Xcode 26.6 project -> `xcodebuild -allowProvisioningUpdates` (automatic signing, team 6M6DG3Y544) -> `xcrun devicectl` install + launch over the network | Fully scriptable, no Xcode GUI in the loop; `ios-deploy` is broken on iOS 17+ | Xcode GUI Run button (manual) | First Xcode sign-in / profile creation may need a click | SOURCED, context-checked (C-02) |
| Unity license | Unity Personal via one Unity Hub sign-in | Personal can't be activated headless (Unity 6.3 manual) | n/a | Needs the user once | SOURCED (C-05) |
| Unity <-> backend | **NativeWebSocket 2.0.7** (endel, Apache-2.0); fallback `System.Net.WebSockets.ClientWebSocket` | Maintained, supports iOS | websocket-sharp (IL2CPP issues), Best HTTP (paid) | No report either way on Unity 6 + IL2CPP + iOS 26 | UNVERIFIED -> spike B (C-06) |
| Network topology | Venue Wi-Fi if phone<->Mac works; else **iPhone Personal Hotspot** with the Mac joined; else **offline replay** bundled in the app | Hotspot avoids client isolation; replay means the demo can't die | Bonjour discovery (entitlement + plist rabbit hole) | Whether an app on the hotspot phone reaches the Mac is unverified | UNVERIFIED -> spike B (C-07, C-08) |
| Server address | Baked into a build-time config file (`StreamingAssets/ares.json`) with a list of candidate URLs; the app tries each and shows which one connected | No typing in VR; works for Wi-Fi + hotspot | QR code with IP (camera already used for lens profile; more code) | Rebuild needed if IP changes: mitigated by trying several candidates incl. hotspot range | design |
| Backend runtime | **Node 26.10** running TypeScript directly (type stripping), **TypeScript 7.0.2** for `tsc --noEmit` | Zero build step; fast iteration | tsx/esbuild build step | TS 7 is new; fallback TS 5.9 | partly spiked (engine typechecks + runs under vitest) (C-12) |
| HTTP + WS server | `node:http` + **ws 8.22.0** | Smallest surface; a dozen endpoints | Fastify 5.12.7 (fine, not needed), Socket.IO | Hand-rolled reconnect: sequence numbers + snapshot resync | SOURCED (C-12) |
| Validation | **zod 4.6.7** | One schema -> action validation, LLM tool JSON schemas, policy file | hand-written JSON schema | none | SPIKED (in tests) |
| Ledger | **Own double-entry ledger in TypeScript**, in-memory, append-only, integer cents, hash-chained, capability-token posting; JSONL export | 0 setup, deterministic seed replay, arbitrary source refs per entry, property-testable | TigerBeetle (overkill, no metadata), Formance v3 (Go+Nix), Blnk (Docker stack), Beancount+Fava (Python bridge) | We own the bugs -> fast-check fuzz + Opus code review | SPIKED (12 tests incl. 300x400-step fuzz), review running (C-10) |
| Tests | **vitest 5.0.5** + **fast-check 4.10.2** | TS-native; property-based invariants | node:test | none | SPIKED |
| LLM agents | Provider-agnostic adapter. **OpenAI** (your credits) via the official `openai` SDK with function calling; Anthropic adapter kept (claude-sonnet-5-5) if sponsor credits appear. **Deterministic rule-based proposer** is the default and the offline fallback | You have OpenAI credits, not Anthropic; the LLM is never in the critical path | LLM in the critical path | Model ID + SDK version to verify; no key in `.env` yet | BLOCKED on key (C-13) |
| Laptop console | **React 19.3.1 + Vite 8.3.5**, plain CSS | Fast to build, one WS feed | Next.js (unneeded) | none | SOURCED |
| Ephemeris | **astronomy-engine 2.1.19** (MIT) for the Earth-Mars distance -> light time | Real number for any date, offline | hard-coded 40 min (wrong today: real round trip is ~25 min) | none | SOURCED (C-12) |
| Mars time | Mars24 (Allison & McEwen 2000), ported from `research/code/mars_sun.py` (validated against the NASA GISS worked example) | Real sun position at Jezero | fixed sun | none | SOURCED |
| Terrain | USGS Mars 2020 TRN: **CTX DEM 20 m** (far, to 25 km) + **HiRISE DTM 1 m** (near, 5 km crop), CTX 5 m + HiRISE 25 cm ortho crops via HTTP range reads (rasterio); polar log-radial meshes (~190k tris for a 150° sector) | Real Jezero view from Octavia E. Butler Landing toward the delta (az ~305°) | Unity Terrain (heavier); full 1.8-7.3 GB downloads | Phone perf; projection stretch (reproject to local AEQD) | SOURCED, data partly downloaded (C-09) |
| Terrain tooling | **rasterio** wheels (bundled GDAL) in a venv | ~30 MB vs brew GDAL's large dependency tree on 0.4 MB/s Wi-Fi | brew `gdal` | none | to spike |
| Unity editor automation | Editor scripts run in batchmode (reproducible, no GUI); **CoplayDev/unity-mcp v10.3.0** (MIT) when the editor is open | Batchmode is deterministic and works headless; MCP for inspecting scenes/console | IvanMurzak Unity-MCP (browser login), Unity official MCP (beta, pricing unclear) | MCP needs editor focus on macOS | SOURCED (C-12) |
| Assets | Quaternius Modular Sci-Fi MegaKit (CC0), Kenney Space Station Kit + Space Kit (CC0), Poly Haven textures (CC0), procedural robots, procedural solar panels + drill, fonts Inter / JetBrains Mono / Rajdhani (OFL 1.1), Kenney UI + sci-fi sounds (CC0) | All CC0/OFL, downloaded (281 MB) | Asset Store (EULA forbids raw files in a public repo) | Triangle counts unchecked | SOURCED |
| Robot faces | Procedural SDF eye shader (openness, squint, pupil offset, color, blink) driven from C# | One material, any expression, cheap | sprite swaps (less expressive) | Shader authoring time | design |

## 2. Architecture

```
                       +-------------------- MacBook Air (venue) --------------------+
 Mars world (seed) --> |  packages/world-mars   seed -> suppliers, prices, history,     |
  power model, tau,    |                         planted errors + ANSWER KEY (private), |
  sols, light time     |                         demo director (beats), levers           |
                       |        | world events (documents, deliveries, needs, telemetry)|
                       |        v                                                       |
                       |  packages/agents   5 role agents: rules brain (default) or     |
                       |                    LLM brain (OpenAI/Anthropic) -> PROPOSALS   |
                       |        | proposals only                                         |
                       |        v                                                       |
                       |  packages/engine   policy.evaluate -> verdict -> executor ->    |
                       |  (world-agnostic)  ledger (double entry, hash chain), audit,   |
                       |                    escalations w/ delay, verifications         |
                       |        | engine events + snapshots                              |
                       |        v                                                       |
                       |  packages/server   node:http + ws  :8787                       |
                       +-----------|------------------------------|---------------------+
                                   | ws (Wi-Fi or hotspot)        | ws (localhost)
                   iPhone 16 Pro in Cardboard                Laptop console (React)
                   Unity: control room, wall screens,        ledger + trace, audit, queues,
                   robots, window view; gaze+tap decisions   policy editor, scenario launcher,
                   offline: bundled replay tape              event/invoice injector, scorecard
                                                             packages/eval: N seeds vs answer key
```

Rules that shape the code:
- `packages/engine` never mentions Mars. Roles are generic (`requester`, `receiver`, `ap`, `treasury`, `controller`, `local_authority`, `remote_authority`); the world supplies display names (Engineer, Cargo Keeper, Bill Checker, Money Keeper, Rule Keeper, Commander, Earth CFO).
- Agents (LLM or rules) can only **propose** typed actions; each role's tool list is exactly its permitted actions. `Engine.submit` runs every check in `policy.ts`, and only an `allow` verdict reaches the executor. The ledger refuses any posting without a one-shot capability token that only the executor can mint.
- Price anomalies are robust statistics (log-price median/MAD z-score + ratio) against supplier history, not the LLM.
- The world's answer key never enters the engine; the eval harness compares engine outcomes to it.

Repo layout:
```
ares/
  BRIEF.md PLAN.md CLAIMS.md CLAUDE.md ARCHITECTURE.md STATUS.md
  research/                 research + verifier reports, prototype scripts
  packages/engine/          world-agnostic P2P core (TS) + tests
  packages/agents/          role agents: rules brains, LLM adapter, orchestrator
  packages/world-mars/      Mars simulation, power/sun/light-time models, demo director
  packages/world-bpi/       (stretch) BPI Challenge 2019 real event log as a second world
  packages/server/          http + ws hub
  packages/console/         React laptop console
  packages/eval/            evaluation harness + scorecard
  policy/                   editable policy JSON files
  unity/AresVR/             Unity project (Library/ etc. gitignored)
  terrain/                  terrain pipeline scripts (outputs to unity/AresVR/Assets/Terrain)
  scripts/                  build-ios.sh, deploy.sh, record-tape.ts
  data/                     raw downloads (gitignored)
```

## 3. Phone performance budget (iPhone 16 Pro, stereo)

| Item | Budget | Notes |
|---|---|---|
| Frame rate | steady **60 fps** (16.7 ms), no ProMotion | XR SDK owns pacing; also set `Application.targetFrameRate = 60` (mobile default is 30) |
| GPU frame time | <= 11 ms | headroom for thermal throttling |
| Triangles (both eyes, after culling) | <= 250k per eye-pass, ~500k drawn per frame | assume multi-pass stereo; terrain ~190k + room <= 60k + robots 5 x 5k |
| Draw calls | <= 120 per eye-pass | static batching for the room, instancing for repeated props |
| SetPass calls | <= 25 | few shaders: URP SimpleLit/Unlit + 3 custom (sky, face, screen) |
| Textures | <= 200 MB GPU, ASTC 6x6 (albedo), 4x4 (text/icons), 8x8 (sky/lightmaps) | terrain near+far 2 x 4096², room atlas 2048² |
| Transparent layers | <= 3 overlapping (storm cards, glass, halos) | overdraw is the storm's real cost |
| Lighting | baked lightmaps for the room, light probes for robots, 1 realtime directional (sun), no realtime shadows | emissive + additive halo quads instead of bloom |
| Post-processing | none. MSAA **off** at first (cardboard#442), try 2x in the spike if text shimmers | |
| Thermal | log `ProcessInfo.thermalState`; drop render scale to 0.85 at "fair" | 20-minute soak test before Sunday |

## 4. Visual direction

- **Control room:** a round, warm, lived-in room about 8 m across. Off-white curved panels with rounded corners (Quaternius MegaKit), dusty-orange trim, soft warm interior light, consoles in a ring. One big curved window takes about 120° of the view toward the delta (WNW). Reference look: NASA HERA/HI-SEAS habitats, *The Martian* (2015) hab interiors, Kenney Space Station Kit simplicity. Calm, not grimdark.
- **Window view:** real Jezero terrain from Octavia E. Butler Landing. The delta scarp is about 2.2 km out, the crater rim 10-12 km away and 3-4° up. Solar panel field (procedural) and the ice-drill rig in the foreground, 30-80 m out. The sky is one shader driven by `tau`:
  - clear day: butterscotch zenith fading to a pale tan horizon, with a faint blue halo near the sun at low elevation;
  - storm: darker, redder and flatter, with the sun disc fading and fog closing in;
  - the solar panels lose their specular glint as tau rises.
- **Wall screens** (three large 16:9 panels at 2.5-3 m, bold sans text with cap height ≥ 1.5°):
  - POWER: battery %, Wh/sol in vs out, tau, sols of reserve, with a tau sparkline;
  - MONEY: cash, runway days, committed, money saved, recent payments;
  - WAITING FOR YOU: escalations with countdowns.
  Each screen carries small data-source captions ("SIMULATED" tag for invented values).
- **Robots:** small floating bodies at eye height, slowly bobbing. Each has a dark rounded screen face with two expressive SDF eyes and an emissive rim in its role color:
  - **Engineer:** orange, a rounded cube with a small antenna dish;
  - **Cargo Keeper:** green, a wide capsule with a "cargo bay" belly band;
  - **Bill Checker:** cyan, a tall slim pill with a scanner visor line;
  - **Money Keeper:** gold, a coin-like disc on edge;
  - **Rule Keeper:** violet, a hexagonal prism. Its face goes to a red-glow squint when it catches fraud.

  They're original designs: no EVE, BB-8 or Baymax silhouettes. Expressions: calm (default), worried (Engineer when power drops), suspicious squint + red (Rule Keeper on fraud), looking at the user (when a decision is needed), happy blink (payment saved).
- **Decision UI:** three large cards at 1.5 m in front of the user, each about 20° wide. The gaze reticle grows on hover, the card lifts and outlines, and a single tap confirms. A one-line hint reads "Look at a choice, tap the button".

## 5. Timeline (Fri 18:00 -> Sun 09:00, all PT)

Checkpoints are bold. Anything that needs you physically is marked **[YOU]**.

| When | Work |
|---|---|
| Fri 18:15-19:30 | Research (8 parallel tracks) done. Engine core + 12 tests (incl. fuzz) done. PLAN/CLAIMS/CLAUDE.md. Unity download started (venue Wi-Fi 0.4-0.65 MB/s, ETA ~21:15 unless the hotspot is OK'd) |
| 19:30-21:15 | While Unity downloads: agents (rules brains + orchestrator), Mars world generator + power model + demo director, server (ws), terrain pipeline (rasterio crops -> meshes), offline replay tape format. Opus reviewers run in parallel |
| 21:15-21:45 | Install editor + iOS module; **[YOU]** Unity Hub sign-in + Personal license; create project, add Cardboard plugin + NativeWebSocket via manifest; batchmode iOS build of hello scene |
| **21:45-22:30** | **CHECKPOINT 1 = Tier 1 spike A: hello scene on the iPhone in the Cardboard: stereo, head tracking, gaze reticle, button tap, QR lens profile. [YOU] one checklist** |
| 22:30-23:30 | **Spike B (network):** phone <-> Mac WebSocket on venue Wi-Fi and on hotspot, console live, offline replay. **Spike C (terrain):** terrain meshes on the phone at 60 fps. **[YOU]** short checks |
| 23:30-02:30 | Unity: control room blockout (editor scripts), window + terrain + tau sky, wall screens bound to live data; robots v1 (bodies + face shader); decision cards (gaze + tap -> `decide`) |
| **02:30** | **CHECKPOINT 2: demo beats 1-7 run end to end from the server, visible on the phone (rough visuals)** |
| Sat 02:30-07:30 | **[YOU] sleep 5 h.** Claude keeps going headless: console (ledger + trace, audit, queues, policy editor, injector, scorecard), eval harness (500 seeds, decoys, held-out seeds), LLM adapter, replay tape recording, batch iOS builds (no device runs) |
| 07:30-08:00 | **[YOU]** on-device check of overnight builds |
| 08:00-12:00 | Robot expressions + animations, storm (sky, fog cards, panel dimming, drill shutdown visible), screen layouts + legibility pass, audio |
| **12:00** | **CHECKPOINT 3: full demo on the phone in the viewer at 60 fps; console shows trace/policy/inject/scorecard live** |
| 12:00-16:00 | Hardening: judge-invented events (free-text invoice via LLM or form), policy edit visibly changes behavior, new-seed runs, reset button, error states; 20-min thermal soak |
| 16:00-19:00 | Polish visuals; real-data citations on screen; "proof it isn't hardcoded" panel (seed, policy version, eval score) |
| **19:00-21:00** | **CHECKPOINT 4: Devpost draft up** (text, architecture image, screenshots, eval numbers); pitch script v1; screen-recording backup v1 **[YOU: wear it once]** |
| 21:00-01:00 | Stretch: second world (BPI 2019) via config; anti-circularity eval; bug bash; record final replay tapes |
| Sun 01:00-01:30 | **Feature freeze.** |
| 01:30-05:30 | **[YOU] sleep 4 h** (total 9 h; cut to 2.5 h if behind). Claude: final eval run, docs, Devpost text |
| 05:30-08:00 | Rehearse the 2-min pitch + deeper segments x5; final screen recording; Devpost final with video link |
| **08:30** | **Submit on Devpost** (30-min buffer before the 09:00 hard deadline) |
| 10:30-12:30 | Judging at the table |

## 6. Cut list (cut from the top first)

1. Second real-world dataset (BPI 2019)
2. Audio
3. HiRISE near-terrain detail (keep CTX only)
4. Live LLM calls in the demo (keep deterministic proposer + cached explanations)
5. Real-time Mars24 sun motion (keep a fixed, correct sun angle for the scenario time)
6. Storm particles (keep sky/fog darkening + panel dimming)
7. Extra robot expressions beyond calm / worried / suspicious / looking-at-you
8. QR lens profile scan (use the default V2 profile)
9. Console visual polish (keep every function)

**NEVER cut:** the core engine, policy enforcement, the evaluation scorecard, the main demo moment (the blocked fake-bank-change payment and the commander's gaze+tap choice).

## 7. Top 10 risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Venue Wi-Fi (0.4-0.65 MB/s) delays the 5.35 GB Unity download | Resumable fetch running now; hotspot for the download if you allow it; all non-Unity work first |
| 2 | Cardboard plugin misbehaves on Unity 6000.0.85f1 / iOS 26.6.1 | Spike A first; pinned fallbacks 6000.0.68f1 -> 6000.3.27f1; last resort native iOS (Swift + Metal + Cardboard C SDK). Changing the engine is a STOP-and-ask |
| 3 | Phone can't reach the Mac at the venue (client isolation) | Hotspot topology; app tries several baked URLs; offline replay tape keeps the VR demo alive |
| 4 | iOS Local Network prompt / ATS blocks `ws://` | Plist keys via post-build script; tap Allow at first launch; spike B checks it |
| 5 | Thermal throttling across 2 h of judging | 60 fps cap, budget above, no post-processing, brightness about 70%, cool-down between judges, thermal-state log + auto render-scale drop |
| 6 | Text unreadable in the viewer | Bold fonts, cap height ≥ 1.5°, high contrast, check in spike A with a sample screen |
| 7 | LLM latency or outage, or no key | Rules brain is the default; LLM only adds explanations and document parsing, with timeouts and cached replies |
| 8 | Judge-invented scenario breaks the flow | All behavior comes from engine + policy, not scripts; injector validated by zod; fuzz tests; reset + new-seed buttons |
| 9 | Signing / provisioning hiccup on the first build | Wildcard profile already exists; automatic signing; do it at checkpoint 1 with you present |
| 10 | Exhaustion / scope creep for a solo build | Checkpoints with cut list, two sleep blocks, feature freeze Sun 01:00, submit 08:30 |

What would make this fail on my iPhone, at the venue, at 3am:
- **A black screen after a plugin or URP setting change.** Keep the last known-good build installed and a git tag at each passing spike.
- **The phone silently on a different network than the Mac.** The app's HUD shows which URL it connected to, or OFFLINE.
- **iOS locks or dims mid-demo.** `Screen.sleepTimeout = NeverSleep`, plus Auto-Lock set to Never on the phone.
- **The Local Network permission was denied once.** Settings > Privacy > Local Network > Ares to re-enable; the HUD shows a hint.
- **The developer profile expires or "Untrusted Developer" appears.** It's a paid team, so it's valid for a year; check that it's trusted in Settings once.
- **The Mac sleeps and kills the server.** Run it under `caffeinate -dims`.

## 8. "Done means" checklist (verify Sunday 05:30-08:00)

- [ ] Evaluation runs on a fresh, never-seen seed range and prints the scorecard: catch rate per error type, false alarms on clean and decoy docs, money saved, money wrongly blocked, escalation rate, 0 policy violations executed, ledger balanced
- [ ] Any ledger entry, clicked in the console, traces to its request, receipt, invoice, rule results, proposal (agent + rationale), approver and source document
- [ ] A policy edit in the console (e.g. emergency limit or price tolerance) visibly changes the next run's behavior and the commander's options
- [ ] The full demo run (beats 1-7) plays on the phone in the viewer at a steady 60 fps, both choices tested
- [ ] A judge-invented event or invoice from the console is handled sensibly (flagged / matched / escalated with reasons)
- [ ] New seed -> different suppliers, prices and planted errors on screen
- [ ] Offline replay works with Wi-Fi off
- [ ] Screen-recording backup of the full run exists on the Mac and the phone
- [ ] Devpost submitted with video, repo link and credits (NASA/USGS/JPL/UArizona, CC0 asset authors, OFL fonts)
- [ ] Every number on screen is either cited or tagged SIMULATED

## 9. Decisions made on your behalf (override any of them)

1. **Unity 6000.0.85f1 + Cardboard 1.36.0 + URP.** This is your direction, pinned to exact versions, with fallback pins listed.
2. **OpenAI as the live LLM provider,** because you have credits. The adapter is provider-agnostic and the rules brain is the default, so judges never wait on an API.
3. **Earth-Mars delay uses the real ephemeris:** about 12.5 min one way, 25 min round trip on 2026-10-24, not the 40 min in the brief.
4. **Power curve uses JPL's Opportunity 2018 values** (tau 1.0 -> 468, 2.1 -> 345, 10.5 -> 21 Wh/sol; about 645-650 before the storm). The brief's 0.6 -> 645 and 1.5 -> 345 pairs trace to a news site and conflict with JPL. Fit: E = 650·e^(-0.31·tau) Wh/sol for Opportunity's array, scaled by area.
5. **Story tweak for logic:**
   - The battery order is for the cargo flight in the **real November 2026 Earth-to-Mars launch window**, so the manifest deadline makes the decision urgent.
   - Earth verification needs a call-back to the supplier during business hours, so it can't come back before the manifest closes. That is why the commander decides, within an emergency limit.
   - "Rule Keeper blocks the supplier" becomes: the fraudulent payment instruction is rejected and the supplier's record is locked on hold. The real supplier was impersonated (classic BEC), so blocking them outright would be wrong.
6. **"Ice drill" lever:** no sourced ice-drill power figure exists. It's shown as the ISRU water/ice plant with an estimated load, tagged ESTIMATE.
7. **Own ledger** (no TigerBeetle/Formance/Blnk/Beancount).
8. **No Bonjour.** Server URLs are baked at build time with several candidates, and an offline replay is bundled.
9. **MSAA off** to start, because of Cardboard bug #442, although the visuals research suggested 4x. We'll test 2x on the device.
10. **rasterio** instead of brew GDAL, because the Wi-Fi is slow.
11. **Default policy numbers:**
    - controller agent limit $5,000;
    - commander emergency limit $15,000; CFO $1,000,000;
    - price tolerance 2%;
    - price anomaly at robust z > 4 or more than 1.35x the median;
    - materiality $500;
    - minimum runway 90 days.

    All are editable in `policy/` and in the console.
12. **Simulated base rates** (duplicates about 0.3%, sweep 0.01-2%; BEC bank change; inflated prices; short deliveries) come from ACFE 2026, AFP 2026 and APQC. Per-document rates are labeled as design choices.
