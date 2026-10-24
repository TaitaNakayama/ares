# CLAIMS: Tier 1 register

A claim is **VERIFIED** only when all four checks pass:
1. Context check against the exact setup.
2. Two or more dated, independent sources.
3. An Opus adversarial review that has not seen our reasoning.
4. A hands-on spike on the real device.

Until then the claim is UNVERIFIED, SOURCED, REVIEWED or SPIKED, and it has a named fallback. Nothing is built on a claim until its spike passes.

Detected setup (context check, 2026-10-23 18:16 PT):
- macOS 26.3 (25D125), MacBook Air M3, 24 GB.
- Xcode 26.6 (17F113) at /Applications/Xcode.app; iOS SDK 26.5 reported; xcode-select points at CLT, so we use `DEVELOPER_DIR`.
- iPhone 16 Pro (iPhone17,1) on **iOS 26.6.1**, Developer Mode on, paired via CoreDevice (network).
- Signing identity "Apple Development: taita@nakayama.io"; team **6M6DG3Y544**, with store and wildcard profiles valid to 2027, so it's a paid team.
- Node 26.10.0, pnpm 10.34.6, Python 3.14.7. Unity not installed.
- Venue Wi-Fi measured at 0.2-0.65 MB/s.

| ID | Claim | Status | Sources (date) | Review | Spike | Fallback |
|---|---|---|---|---|---|---|
| C-01 | Unity 6000.0.85f1 + Cardboard XR Plugin v1.36.0 + URP renders correct stereo with distortion and head tracking on iPhone 16 Pro / iOS 26.6.1, built with Xcode 26.6 (Metal, IL2CPP, MSAA off) | SOURCED | cardboard-xr-plugin releases + package.json (2026-10-15); googlevr/cardboard v1.36.0 notes (2026-10-15); `resolutions.csv` has iPhone17,1 (fetched 2026-10-23); issue #696 compat comments (2026-07-30, 2026-10-01); Unity UIScene notice (2026-10-06) | running (verify-01) | pending (spike A) | 6000.0.68f1 -> 6000.3.27f1 -> native iOS + Cardboard C SDK (STOP and ask before switching) |
| C-02 | Batchmode build -> `xcodebuild -allowProvisioningUpdates` (automatic signing, team 6M6DG3Y544) -> `devicectl` install/launch works from the CLI | SOURCED + context OK (devicectl sees the phone; identity + wildcard profile present) | Unity PlayerSettings.iOS docs (2026-10-23); Unity Hub CLI ref (2026-10-23); ios-deploy broken on iOS 17+ | running (verify-01) | pending (spike A) | Open the generated project in Xcode and press Run [YOU] |
| C-03 | V2 button = touch Began -> `Api.IsTriggerPressed`; camera-center gaze raycast gives gaze + tap | SOURCED | plugin `Runtime/Api.cs` at v1.36.0 (2026-10-07); hellocardboard sample; issue #501 (2025-09-15) | running | pending (spike A) | Read `Touchscreen.current.primaryTouch` directly |
| C-04 | QR lens-profile scan works on iOS 26 and persists; default V2 profile otherwise | SOURCED | sample `CardboardStartup.cs` (v1.36.0); v1.34.0 notes (camera permission fix, 2026-05-28); open #486 (SaveDeviceParams, stale) | running | pending (spike A) | Default V2 profile (brief allows it) |
| C-05 | Unity Personal requires one Unity Hub GUI sign-in; batchmode works afterwards | SOURCED | Unity 6.3 manual "ManualActivationCmdWin" (2026-10-23); Unity CLI ref (2026-10-23) | running | pending | none needed: you sign in once |
| C-06 | NativeWebSocket 2.0.7 works in a Unity 6 IL2CPP iOS build to `ws://<LAN IP>:8787` | UNVERIFIED (no report either way) | GitHub endel/NativeWebSocket release 2.0.7 (2026-08-07) | running (verify-02) | pending (spike B) | `System.Net.WebSockets.ClientWebSocket` -> HTTP long-poll |
| C-07 | Phone <-> Mac connectivity: venue Wi-Fi (if no client isolation) or the phone's own hotspot with the Mac joined; ATS + Local Network permission handled by plist | UNVERIFIED | research/06 (Apple TN3179 failed to load, so it rests on memory) | running (verify-02) | pending (spike B) | Offline replay (C-08) |
| C-08 | Offline fallback: the app replays a bundled event tape of a seeded run, with one branch per decision option | design | n/a (our code) | n/a | pending (spike B) | Screen recording |
| C-09 | USGS Jezero CTX DEM/ortho + HiRISE DTM/ortho crops are accessible (range requests) and usable with credit; the ~190k-tri polar mesh + 2x4K ASTC renders at 60 fps in stereo on the 16 Pro | SOURCED (data); perf UNVERIFIED | astrogeology.usgs.gov product pages (fetched 2026-10-23); S3 HEAD + windowed reads succeeded (2026-10-23); CTX DEM + 5 km HiRISE DTM crop downloaded | running (verify-03) | pending (spike C) | CTX only, decimated to 60k tris; then a painted skybox |
| C-10 | Ledger correctness: every entry balances, the hash chain is tamper-evident, and nothing posts without an `allow` decision (one-shot capability token) | SPIKED | own code; double-entry invariants | running (verify-04) | **PASS** 2026-10-23 19:05: 12 vitest tests incl. fast-check fuzz, 300 seeds x 400 adversarial proposals; ledger.verify + audit.verify clean | n/a: fix bugs |
| C-11 | Permission enforcement: no role executes an action outside its policy permissions; SoD holds; escalations only decidable by the target authority after delivery and within its limit; bank changes never redirect payments without confirmed verification | SPIKED | own code | running (verify-04) | **PASS** (same fuzz: 0 forbidden actions executed; no payment to the unverified account) | n/a: fix bugs |
| C-12 | Libraries exist, are permissively licensed and work here: TS 7.0.2, Node 26 type stripping, vitest 5.0.5, fast-check 4.10.2, zod 4.6.7, ws 8.22.0, React 19.3.1, Vite 8.3.5, astronomy-engine 2.1.19 (MIT), CoplayDev unity-mcp v10.3.0 (MIT), rasterio wheels | SOURCED (npm view, 2026-10-23); TS/vitest/fast-check/zod spiked locally | npm registry (2026-10-23); research/05, research/06 | running (verify-03) | partial PASS (TS 7.0.2 typecheck, vitest, fast-check, zod in use) | TS 5.9; Fastify; hand-rolled ephemeris |
| C-13 | Live LLM agents: OpenAI function calling with your key (model TBD) proposes valid actions; deterministic fallback when absent | BLOCKED (no key yet) | pending | pending | pending | Rules brain (already the default) |
| C-14 | Thermal: steady 60 fps through repeated 5-min sessions for 2 h | UNVERIFIED | research/02 (3DMark stress numbers for the 16 Pro Max, 55-68% stability) | n/a | pending (20-min soak, Sat) | render scale 0.85, fewer transparent layers, cool-down between judges |

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
