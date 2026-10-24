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

## The agents (packages/agents)

Three model layers, one generic LLM brain per role, rules as the floor.

```
event (world or engine) ─▶ LlmBrain.react ──▶ router.complete ──▶ cloud (OpenAI)  ─┐
                              │                     │ (auto: cloud first when online)  │ one valid answer
                              │                     └──▶ local (Ollama, offline)   ───┤
                              │  timeout / error / invalid call / off-script line     │
                              └──▶ rules brain (same role) ◀──────────────────────────┘
                                          │
                                   Intent[] (via: llm | rules | parser)
                                          │
                                   Engine.submit ─▶ policy.evaluate ─▶ verdict ─▶ executor
```

- **`router.ts`**: `ModelRouter` picks the layer and enforces deadlines (8 s per action, 15 s per free-text report; `ARES_LOCAL_TIMEOUT_MS`), marks the cloud offline for 60 s after a network error, and counts calls, errors and timeouts per layer. Mode `auto | local | cloud | rules`; `rules` is SAFE MODE (console button, `POST /api/agents/mode`), instant and mid-run. `ARES_PREFER` chooses the first layer in `auto` (default cloud: measured 2-8 s live; local needs a warm prompt prefix). `OllamaProvider` talks to `/api/chat` with `think:false`, `num_ctx 4096`, and reports prompt tokens read, which is how we see whether the prefix cache worked.
- **`llm-agent.ts`**: `LlmBrain` reasons only at its role's decision points (a fixed table: the Engineer on needs and reports, Rules on closed RFQs, held invoices, verification answers, and so on). Mechanical events stay on the rules brain. The model gets the event and a state summary, both written by code from engine state (catalog, vendors, limits, open requisitions with each quote's policy results and price ratio, invoices with their match, pending verifications, open escalations), and a tool list that is exactly the actions policy permits that role for that event, plus `say` and `report_issue`. Each action tool carries a `say` field so one call holds the decision and the line.
- **Checks before anything is proposed**: unknown tool, schema failure, ids the engine doesn't have, invented report subjects. Known small-model slips are repaired deterministically and noted in the rationale (a `poId` next to an `invoiceId`, a missing `qtyRejected`, nested JSON as strings). Every spoken line is checked against the facts the engine provided: numbers (in cents, dollars, or compact form), ids, length, markdown, character. A failed line is replaced by the rules brain's line and the rationale says so. If the model proposes no action where the rules would act, the rules act (`via: rules`). If the rules would escalate and the model neither escalates nor decides, the escalation is added, labeled rules (the floor for the human handoff).
- **Breaker**: two failures (timeout, error, policy denial) in the last four calls put that brain on rules for 60 s.
- **Reports** (`world.ts` `report` event, `routing.ts`): any free text is routed to one agent (the model with one tiny `route` tool, keywords as fallback). The engine action `report_issue` (allowed to every agent role) always becomes an escalation to the on-site human with the agent's recommendation and two options (approve the recommendation, no action). `ReportRules` handles reports when a role has no model.
- **Options proposed by agents**: `escalate.options` lets the escalating agent propose up to three options, each with the exact action it would take. The engine dry-runs each action through the full policy as the deciding human, keeps the clean ones next to its standard options (`proposedBy` set), and the decide step re-checks them.
- **Thinking and asking**: the orchestrator emits `thinking` on/off around each model call (headset face, spectator pill). `Orchestrator.ask(role)` (`vr_ask` from the headset, `POST /api/ask`) makes an agent explain itself live from the current state: a validated line, or a code-written status line.
- **Labels**: each proposal's `source` is what produced it (`rules`, `llm`, `parser`, `human`, `console`), never the brain's capability. `/api/agents/history` lists every model call: layer, time, prompt tokens read, and why it fell back.
- **Eval**: `scripts/eval-llm-story.ts` runs the full story per seed with the LLM brains and the rules brains, and reports beats in order, fallbacks by role and reason, replaced lines, latency, denials, and whether the pump report reached the commander.

## The two-part demo (outside, then inside)

The judge starts outside on the real Jezero terrain at ground level and walks in as the storm rises. Everything the scene shows comes from `vr_state`:

- `scene.part`: `outside` | `inside`; `scene.station`: `pad` | `science` | `solar` | `door` | null. The server's director (`POST /api/director/next`) advances: **pad** (the cargo lander; the world runs beat 1, the short delivery, so Cargo's counting line is said beside the boxes) → **science** (a crew scientist, `robots.scientist`, not one of the five agents, with world-written lines and the real Perseverance reference in `scene.science`) → **solar** (the Engineer's panel-check line, then the storm warning; beat 2 starts, tau ramps) → **door** (the judge gazes at the base door and presses; the headset sends `{"type":"vr_enter"}`; the director auto-enters after 25 s if nobody does) → `part: inside` (a `scene` push message too). Autoplay runs part 1 in about 40 s.
- Lines follow the same rules as everything else: agents' lines come from their brains (model or rules), the scientist's and the Engineer's station lines are written by the world from the power model and the credited reference; nothing outside states a number the engine or world didn't provide.
- The spectator follows through both parts: the headset's pose stream carries orientation plus the head position (`vr_pose.p`), the scene yaw of the walk (`wy`) and whether the science close-up is open (`cu`), so the Mac camera moves along the same path (camera = `Rot(wy) * q` at `p`, lightly smoothed). Without a live headset the spectator runs the same walk from the server's `scene.station`.
- The REPLAY tape records part 1 too (`scripts/record-tape.ts` drives the four stations and `enter`).

Scene-side contract for the builders (vr/Shared): the outdoor set (lander with pallets at the pad, the science site, the solar field, the habitat with its pressure door) is laid out on the real terrain with the judge's path pad → science → solar → door at steady walking speed (no sudden acceleration; a few seconds per leg), the robots that belong outside (Cargo at the pad, Engineer at the solar field) stand at their stations while the others stay inside; the scientist is a labelled crew figure whose gaze-tap opens the credited close-up; the door tap triggers `vr_enter`; the storm (tau) drives sky colour, dust particles and the dimming of panels and lights, inside and out. Art direction: [ART.md](ART.md); third-party assets and NASA imagery: [CREDITS.md](CREDITS.md).

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
