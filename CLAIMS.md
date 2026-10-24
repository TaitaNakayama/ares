# CLAIMS: Tier 1 register

A claim is **VERIFIED** only when all four checks pass:
1. Context check against the exact setup.
2. Two or more dated, independent sources.
3. An Opus adversarial review that has not seen our reasoning.
4. A hands-on spike on the real device.

Until then the claim is UNVERIFIED, SOURCED, REVIEWED or SPIKED, and it has a named fallback. Nothing is built on a claim until its spike passes.

Last updated: 2026-10-23 19:55 PT.

Detected setup (context check, 2026-10-23 18:16 PT):
- macOS 26.3 (25D125), MacBook Air M3, 24 GB.
- Xcode 26.6 (17F113) at /Applications/Xcode.app; iOS SDK 26.5 reported; xcode-select points at CLT, so we use `DEVELOPER_DIR`.
- iPhone 16 Pro (iPhone17,1) on **iOS 26.6.1**, Developer Mode on, paired via CoreDevice (network).
- Signing identity "Apple Development: taita@nakayama.io"; team **6M6DG3Y544**, with store and wildcard profiles valid to 2027, so it's a paid team.
- Node 26.10.0, pnpm 10.34.6, Python 3.14.7. Unity not installed.
- Venue Wi-Fi measured at 0.2-0.65 MB/s.

| ID | Claim | Status | Sources (date) | Review | Spike | Fallback |
|---|---|---|---|---|---|---|
| C-01 | Unity 6000.0.85f1 + Cardboard XR Plugin v1.36.0 + URP renders correct stereo with distortion and head tracking on iPhone 16 Pro / iOS 26.6.1, built with Xcode 26.6 (Metal, IL2CPP, MSAA off) | SOURCED; **ON HOLD**: Unity ToS (2026-06-30) §17.2(ff) bars AI-agent/CLI invocation of Unity except via "Authorized Agentic Access"; decision pending with you (native iOS recommended) | as before + Unity ToS (2026-06-30), roboin.io (2026-07-02) | verify-01: LIKELY HOLDS (Google ceiling 6000.0.62; needs TrackedPoseDriver; Metal Toolchain may be missing) | not run | native iOS with the same Cardboard SDK (C-01n) |
| C-01n | Native iOS (Swift + SceneKit/Metal) + Google Cardboard SDK v1.36.0 renders correct stereo + head tracking on the 16 Pro | **REVIEWED + SPIKED (render path)**. Opus review (verify-05) found that both eyes rendered one stale camera, because SceneKit draws committed transaction state. Fixed with two eye cameras under a head node plus `SCNTransaction.flush()`. Device capture disparity is now -7 to -28 px for near objects and 0 for the terrain ([evidence](docs/evidence/stereo-disparity.txt)). 60 fps at 2622x1206. **Pending your viewer check:** comfort, tracking direction in the headset, legibility, the button | googlevr/cardboard v1.36.0 (2026-10-15), `cardboard.h`, Google GVR docs (V2 URI) | verify-05: C1 fixed; H1 (recenter), H2 (hold opened the camera), H3 (URI not NUL-terminated), M1, M2, M4 and M6 fixed | [stereo](docs/evidence/stereo-verified.jpg) | Unity path (B) |
| C-02 | CLI pipeline: build -> sign (automatic, team 6M6DG3Y544) -> `devicectl` install + launch works headless | **SPIKED (native)**: `xcodebuild -allowProvisioningUpdates` built + signed HelloCardboard; `devicectl device install/process launch` succeeded over the network (19:43) | Apple devicectl; verify-01 | verify-01: LIKELY HOLDS (signing ready; network pairing can drop: USB fallback) | **PASS** (native) | USB cable; Xcode Run button [YOU] |
| C-03 | V2 button = touch Began -> `Api.IsTriggerPressed`; camera-center gaze raycast gives gaze + tap | SOURCED | plugin `Runtime/Api.cs` at v1.36.0 (2026-10-07); hellocardboard sample; issue #501 (2025-09-15) | running | pending (spike A) | Read `Touchscreen.current.primaryTouch` directly |
| C-04 | QR lens-profile scan works on iOS 26 and persists | SOURCED; **correction**: without a scan the SDK loads Cardboard **V1** params, not V2 (verify-01). Fix: first launch saves the V2 profile from its official QR URL, or you scan your viewer | sample `CardboardStartup.cs` (v1.36.0); v1.34.0 notes (2026-05-28); verify-01 | verify-01: FALSE as originally stated | pending (your checklist) | bundled V2 params |
| C-05 | Unity Personal requires one Unity Hub GUI sign-in; batchmode works afterwards | SOURCED | Unity 6.3 manual "ManualActivationCmdWin" (2026-10-23); Unity CLI ref (2026-10-23) | running | pending | none needed: you sign in once |
| C-06 | NativeWebSocket 2.0.7 / ClientWebSocket works in an iOS build to `ws://<LAN IP>:8787` | REVIEWED: LIKELY HOLDS (verify-02). For native iOS: `URLSessionWebSocketTask` (Apple API, iOS 13+) replaces it | endel/NativeWebSocket 2.0.7 (2026-08-07); Apple URLSessionWebSocketTask docs | verify-02 | pending (spike B) | HTTP long-poll |
| C-07 | Phone <-> Mac connectivity: venue Wi-Fi or the phone's own hotspot; Local Network permission | **HOTSPOT SPIKED** 20:09: the app on the hotspot iPhone holds a WebSocket to the Mac at 172.20.10.13 (server sees it from 172.20.10.1) and streams stats; venue Wi-Fi not yet tested. REVIEWED: hotspot LIKELY HOLDS (works, not guaranteed); venue Wi-Fi client isolation real; ATS keys don't govern raw sockets; `NSLocalNetworkUsageDescription` required; first connection may be denied, so retry | verify-02 (Apple TN3179, Unity docs, dated) | verify-02 | pending (spike B) | USB tethering; Cloudflare quick tunnel (`wss://`, no account); offline replay |
| C-08 | Offline fallback: the app replays a bundled tape of a seeded run (four branches, one per choice) when no server answers within 12 s | **SPIKED** 21:30: forced-replay test on the device shows the recorded story reaching the decision cards at about 58 s, labelled "Offline replay". The tape was re-recorded with current prices (1.37 MB) | own code; verify-02 (rejoin branches, don't fall back on the first failure) | verify-05 M6 (link state after replay) fixed | [capture](docs/evidence/offline-replay.jpg) | Screen recording / director video in docs/demo |
| C-09 | USGS Jezero CTX DEM/ortho + HiRISE DTM/ortho crops are accessible (range requests) and usable with credit; the ~190k-tri polar mesh + 2x4K ASTC renders at 60 fps in stereo on the 16 Pro | SOURCED (data); perf UNVERIFIED | astrogeology.usgs.gov product pages (fetched 2026-10-23); S3 HEAD + windowed reads succeeded (2026-10-23); CTX DEM + 5 km HiRISE DTM crop downloaded | running (verify-03) | pending (spike C) | CTX only, decimated to 60k tris; then a painted skybox |
| C-10 | Ledger correctness: entries balance, the chain is tamper-evident, nothing posts without `allow`, and payments never exceed what was approved and matched, to the verified account | **REVIEWED x3 + SPIKED**. Round 1 BROKEN (21 findings), round 2 held with caveats, round 3 (21:45) found the engine holds but the system as deployed was broken: S1 no server auth, W1 Earth simulator keyed bank truth on the account number only, E1 unbounded tolerance. All fixed: loopback-only control API plus a headset token (LAN probe 403/4401 verified), full bank identity, bounded policy | own code | verify-04, 04b, 06 | **PASS** 22:00: 71 tests + 47 blocked-exploit repros + fuzz; held-out eval 0 fraud payments, 0 integrity failures | n/a |
| C-11 | Permission enforcement: no role acts outside policy; SoD can't be disabled; escalations decided only by their target; agents can't choose their identity; human-only powers stay human | **REVIEWED x3 + SPIKED**. Round 3 fixes: human-only actions (`decide`, `answer_verification`, `release_vendor`) enforced by the policy validator; escalation routing on reject-quote and cancel; no repeating a non-final choice; network callers can't act as CFO or commander | own code | verify-04, 04b, 06 | **PASS** (same suite); rogue controller test: every malicious attempt refused | n/a |
| C-12 | Libraries exist, permissive, work here | REVIEWED: HOLDS (verify-03) — TS 7.0.2, Node 26 type stripping (incl. pnpm symlinks), vitest, fast-check, zod, ws, React 19.3.1, Vite 8.3.5, astronomy-engine (dormant since 2023-12, still correct: 12.51 min today), rasterio 1.5.2 wheel w/ GDAL 3.12.2. openai SDK 7.43.0: tool calling needs the **Responses API** (gpt-6.1-sol / gpt-6-astra) | npm/PyPI/GitHub (2026-10-23) | verify-03 | PASS (in use) | — |
| C-13 | Live LLM agents: OpenAI Responses API tool calling with your key proposes valid actions; rules brain when absent | BLOCKED (no key in `.env` yet) | verify-03 (openai 7.43.0, Responses API) | pending | pending | Rules brain (default) |
| C-14 | Thermal: steady fps through repeated sessions | **PARTLY SPIKED** 21:22-21:42: 20-minute autoplay loop on a **MagSafe charger** (worst case): 41 samples, all 59.9-60.1 fps, thermal 'fair' throughout ([log](docs/evidence/soak-2122.log)). Still to do: off-charger soak in the viewer | research/02 | n/a | partial PASS | render scale 0.85, cool-down between judges |

## Data claims (Tier 2, cited on screen)

| Quantity | Value used | Source (date) | Note |
|---|---|---|---|
| Opportunity energy vs tau (2018) | pre-storm about 650 Wh/sol; tau 1.0 -> 468; 2.1 -> 345; 10.5 -> 21 | JPL Opportunity mission updates (research/08) | The brief's 0.6 -> 645 and 1.5 -> 345 pairs come from WRAL news and conflict with JPL |
| Fit | E = 650·exp(-0.31·tau) Wh/sol (Opportunity array) | fitted to the JPL points (±15 Wh/sol) | 2007 point (tau 4.12 -> 280) sits above the curve because the arrays were cleaner |
| Earth-Mars light time 2026-10-23 | 1.504 AU -> 12.5 min one way, 25 min round trip | JPL Horizons (2026-10-23) | computed live with astronomy-engine |
| Launch window | current Earth->Mars window opens Nov 2026; next about Dec 2028-Jan 2029 | research/08 (secondary sources) | |
| Crew consumption | O2 0.816 kg, food 1.51 kg, water 4.48 kg per crew-day | NASA BVAD (Jan 2018) | |
| Battery specific energy | 100-150 Wh/kg (Li-ion cell) | NASA BVAD | |
| Habitat power | about 20 kWe for a crew-phase base | NASA 2009 Mars DRA power paper | |
| Ice drill / ISRU load | ESTIMATE | none found | shown as ESTIMATE |
| Duplicate-payment base rate | about 0.3% (sweep 0.01-2%) | APQC 2024; Coventry/Berkeley audits | per-document rates are design choices |
| BEC / bank-change fraud prevalence | 74% of orgs affected by BEC; 33% of fraud victims saw manipulated ACH/wire instructions | AFP 2026 | organization-level, not per-invoice |
| Billing schemes | 21% of cases, median loss $90k | ACFE 2026 | |
| Suppliers, prices, budget, invoices | invented | n/a | tagged SIMULATED |
