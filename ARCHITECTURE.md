# ARCHITECTURE

_Kept current with the build. Last updated Fri 2026-10-23 20:45 PT._

## The idea in one diagram

```
 WORLD (swappable)                 AGENTS (propose only)              ENGINE (world-agnostic, deterministic)
 packages/world-mars               packages/agents                    packages/engine
 ┌──────────────────────┐  events  ┌───────────────────────┐ proposal ┌──────────────────────────────────────┐
 │ seed -> suppliers,    │────────▶ │ requester  (Engineer) │────────▶ │ parseAction (zod)                     │
 │ prices, history,      │          │ receiver   (Cargo)    │          │ authenticate actor (credential)        │
 │ planted errors        │          │ ap         (Bills)    │          │ policy.evaluate -> RuleResult[]        │
 │ ANSWER KEY (private)  │          │ treasury   (Money)    │          │   verdict: allow | hold | escalate |   │
 │ power(tau), Mars24,   │◀──────── │ controller (Rules)    │◀──────── │            deny                        │
 │ light time, director, │  engine  └───────────────────────┘  events  │ executor (only path to state + ledger) │
 │ Earth/commander sims  │  events     rules brain (default)           │   ledger: double entry, hash chain,     │
 └──────────────────────┘             LLM brain (optional)            │           one-shot posting tokens       │
                                                                       │   audit log, escalations, verifications │
                                                                       └──────────────────────────────────────┘
                          packages/server (node:http + ws :8787): real-time clock, demo director, APIs
                              │ vr_state (compact)                         │ full state + events
                     iPhone 16 Pro, AresVR (native)                  Laptop console (React)
```

## Packages

| Package | Role | Key files |
|---|---|---|
| `packages/engine` | Generic P2P core. Never mentions Mars. | `engine.ts` (submit → evaluate → execute, escalations, trace), `policy.ts` (schema + defaults + rule labels), `ledger.ts`, `audit.ts`, `actions.ts` (zod schemas = LLM tool schemas) |
| `packages/agents` | Role brains + orchestrator (discrete-event loop) | `brains.ts` (rules brains), `orchestrator.ts` (binds identities, routes events, narration), `world.ts` (World interface) |
| `packages/world-mars` | The Mars simulation and story | `world.ts` (setup, planted errors, answer key, Earth/commander sims, demo beats), `catalog.ts` (seeded market), `power.ts` (Opportunity-calibrated), `mars-time.ts` (Mars24, light time) |
| `packages/eval` | Scores runs against the answer key | `index.ts` (`runEval`, `scoreRun`), `main.ts` (CLI) |
| `packages/server` | Hub for the headset and console | `main.ts` |
| `packages/console` | Laptop console (React 19 + Vite 8) | `app/` |
| `vr/` | Native iOS VR app (Swift + SceneKit + Google Cardboard SDK) | `AresVR/Sources/*`, `project.yml` (XcodeGen) |
| `terrain/` | USGS DEM/ortho → OBJ meshes + textures | `build.py` |

## Invariants and where they are enforced

| Invariant | Enforced in | Tested by |
|---|---|---|
| Only an `allow` decision changes money | `Engine.submitInner` gating + `postEntry` asserts the decision's verdict | `adversarial-review*.test.ts` (C1), fuzz |
| Nothing posts to the ledger without a minted one-shot token | `Ledger.authorize` (private secret, #private fields) | review H3 |
| Every entry balances, the chain is intact, and the head matches the audit log | `Ledger.post`, `Ledger.verify`, `Engine.verifyIntegrity` | p2p tests, fuzz, eval (integrity failures = 0) |
| A role can only propose its permitted actions | `evaluate` RBAC first (nothing else is evaluated on failure) | fuzz (0 forbidden actions executed) |
| Segregation of duties can't be configured away | `policySchema`: SoD flags are `z.literal(true)` + incompatible permission pairs | p2p, review M6/N9 |
| Agents can't choose their identity | `requireCredentials`; the orchestrator holds credentials, brains never see them | review C4 |
| Pay only what was matched, to the verified account | `computeMatch` (per-SKU aggregate, matched qty), `payment.po_cap`, `payment.to_master_bank` | review C2/C3/H1/N1/N4 |
| An escalated item is decided only by its target, after delivery | `escalation.routing` + `decideRules` | review M1/M2/N6 |
| Bank changes never redirect money without an out-of-band check | `vendor.bank_matches_master` → hold + verification (≥ 1 round trip) | p2p, fuzz, eval (fraud payments = 0) |

## Data flow of the main demo (beats 1-7)

1. World delivers 34 of 36 filters, then an invoice for 36. AP submits the matched amount (34 units). The policy denies anything else. The controller approves and treasury pays the verified account.
2. The world ramps tau 0.6 → 4.6. Power drops (Opportunity calibration), and the requester files a need for 40 batteries before the manifest closes.
3. Treasury `confirm_funds` (runway rule).
4. Two quotes arrive. The usual supplier's quote asks for a new bank account at 3x the price. AP's flags come from policy rules: bank mismatch, robust z-score, contract.
5. The controller requests an out-of-band verification and escalates. The engine routes the decision to the **local** authority because Earth's answer (2 × 12.5 min light time + 3 h call-back) can't arrive before the deadline. Options are built from state: buy N within the emergency limit, wait, the operational lever (drill), reject.
6. The commander decides with gaze + tap. `decide` re-checks every sub-action against policy as the commander.
7. Earth's answer arrives after the round trip: fake. The quote is voided, the vendor is put on hold, and the saved amount is recorded.

## The headset (vr/)

- Scene code lives in `vr/Shared` (shared with the Mac spectator view); iOS-only code in `vr/AresVR/Sources`.

- `CardboardSession` wraps the Cardboard C API: head pose, eye matrices, lens distortion and the Metal distortion renderer. The V2 viewer profile is the default when no QR has been scanned.
- `VRViewController` runs the MTKView loop: two SceneKit offscreen passes (one per eye), then the distortion pass, at 60 fps. Touch-down is the button, and long-press rescans the QR.
- `BaseScene` holds the room (`Room`) and the window view (`Outside`: terrain, a cube-map sky from tau and sun, fog, sun light, panels, drill, dust). It also holds `WallScreens`, the five robots (`Robots`) and the 2×2 decision cards.
- `Link` is a WebSocket client with several baked addresses, reconnects, stats and frame capture. If no server answers it plays the bundled tape (`tape.json`, recorded from the live server for each choice).

## The spectator view (vr/Spectator, macOS)

- `vr/Shared` holds the scene and link code compiled by both apps. `Platform.swift` maps UIKit/AppKit colour, font and image types and gives one top-left-origin bitmap drawing helper.
- The headset streams `vr_pose` at 30 Hz: head rotation, gazed card, whether cards are up, eye FOV. The server relays it only from the newest token-authenticated headset to loopback `client=spectator` sockets. Spectators are read-only.
- `SpectatorController`:
  - renders the same `BaseScene` through one camera at the head position, smoothed toward the judge's pose (time constant 0.1 s) with the FOV 10° wider than the headset's;
  - runs `BaseScene.update` with the judge's raw pose, so hover and robots behave as in the headset;
  - overlays the gaze dot, subtitles from the `narration` stream, the enlarged decision card, the beat and the LIVE/REPLAY badge.
- **Modes:**
  - LIVE: the headset is connected and its pose is under 1 s old.
  - REPLAY: the demo build with no live headset. It plays the bundled tape under a slow drifting camera.
  - DEBUG: the debug build only, with the live state under a mouse camera while no headset is live. The mouse code is behind `#if DEBUG`, so it doesn't exist in the Release build.

## Networking

- Primary: the iPhone Personal Hotspot with the Mac joined. The app reaches the Mac at 172.20.10.x (verified).
- Also: venue Wi-Fi if it doesn't isolate clients. The app tries each address baked into `ares.json`.
- Last resort: offline replay.
