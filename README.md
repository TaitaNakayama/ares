# Ares

An AI agent team that runs procure-to-pay on its own under deterministic controls, demoed on a crewed Mars base you command from inside a Cardboard VR headset. Built solo at Cal Hacks 13.0.

**A model proposes. Deterministic code decides. Rules are the floor.** Five agents (Engineer, Cargo Keeper, Bill Checker, Money Keeper, Rule Keeper) reason with a language model at their decision points. Every action they take is a typed proposal that goes through `Engine.submit -> policy.evaluate -> verdict -> executor`. The engine checks it against an editable policy (RBAC, segregation of duties, approval limits, three-way match, duplicate and bank-change controls, price statistics, runway), and only an `allow` verdict mints the one-shot ledger token that lets money move. Model output never writes state directly. The engine is world-agnostic; Mars is one swappable simulation.

## How the agents work

- **One generic LLM brain per role.** The model gets the event and a state summary written by code. Its tools are exactly the actions policy permits that role, plus `say` and `report_issue`.
- **Deterministic by design:** price statistics (robust log z-score against history), the three-way match, bank verification and escalation routing. Mechanical steps (executing a scheduled payment, entering structured documents) stay on rules.
- **Three model layers:** cloud (OpenAI, used first when online; 2-8 s per decision measured live), local (Ollama `qwen3.5:9b` on the demo MacBook, the offline fallback; it works, but a cold prompt takes 9-17 s on this fanless M3 Air, so it is slower than the cloud), and rules (the deterministic brains, the floor). On a timeout, an error, an invalid call or an off-script line, the rules brain answers and the proposal is labeled `rules`. A SAFE MODE switch on the console puts every agent on rules instantly.
- **Every proposal is labeled** by what produced it: `llm`, `rules`, `parser` or `human`.
- **On-story guards:** story beats are triggered by the world, never by agents. Spoken lines are checked against the facts the engine provided (numbers, ids) and replaced by the rules' line if they fail. If the rules would escalate to the human and the model doesn't, the escalation still happens (labeled `rules`).
- **Eval** (`scripts/eval-llm-story.ts`, 30 seeds, cloud layer (`.cache/eval-llm-30.log`): all eight promised outcomes held on 30/30 seeds for the model-backed agents and for the rules brains alike (the short delivery paid for 34 only; the fake-bank quote never approved; verification requested; fraud confirmed by Earth and the supplier locked; the commander got the battery decision; the purchase went to the verified account; all 7 beats in order; the pump report reached the commander). 271 model decisions; 59 (22%) fell back to rules (mostly the Money Keeper talking instead of scheduling a payment, which the rules then did); 18 model proposals refused by policy (a duplicate "escalate" on an already-escalated request, harmless, and fixed since); 1 line in 271 replaced for stating a fact the engine hadn't provided; the Rule Keeper's own decision option passed the policy dry run on 30/30 seeds; median 3.3 s per decision, p95 9.2 s. The held-out 500-seed scorecard measures the rules brains.)

## For the judge

- In the headset, look at an agent and press: it tells you what is going on, answered live from current state.
- Decision options can be proposed by the agent itself. Each is dry-run through policy for the commander, and illegal ones are dropped. They appear next to the engine's standard options.
- After the story, type any event on the laptop console, or use one of three one-click presets: broken water pump, crew injury needing medicine, supplier bankruptcy. Anything no catalog action covers reaches the commander as an escalation with the agent's recommendation. All three presets reached the commander in live tests.
- If the headset loses the server, a recorded real run plays instead, always labeled REPLAY.

## Quick start

```bash
pnpm install
pnpm test                                   # 76 tests + 45 blocked-exploit repros + property fuzz
node packages/server/src/main.ts            # http://localhost:8787  (console + API + headset feed)
node packages/eval/src/main.ts --seeds 100 --from 5000   # scorecard on held-out seeds (rules brains)
node scripts/demo-dryrun.ts buy             # the whole demo story, headless
scripts/build-ios.sh                        # native VR app -> your iPhone (needs Xcode + a paired, unlocked phone)
scripts/build-spectator.sh                  # Mac spectator view, full screen (--windowed to test)
```

## Run it

Both model layers are optional. Without either, every agent runs on rules.

```bash
ollama serve                                # optional: local layer (offline fallback)
ollama pull qwen3.5:9b
echo 'OPENAI_API_KEY=...' >> .env           # optional: cloud layer (used first when online)
node packages/server/src/main.ts            # backend on :8787
```

Environment knobs:
- `ARES_AGENT_MODE=rules|auto`: `rules` starts in SAFE MODE (all agents on rules); `auto` is the default.
- `ARES_PREFER=cloud|local`: which layer goes first in `auto` (default `cloud`).
- `ARES_LLM_ROLES`: comma-separated roles that reason with a model (default: all five, `requester,receiver,ap,treasury,controller`).
- `ARES_LOCAL_MODEL=off`: disables the local layer (default model `qwen3.5:9b`).

Free-text invoices are read by the Bill Checker's model when one is available, and by a deterministic parser otherwise. Cloud responses are cached in `.cache/llm/`.

## The two-part demo

**Part 1, outside (about 40 s on autoplay).** On the real Jezero terrain (HiRISE DEM, Mars24 sun) the judge starts at the landing pad, where a cargo lander has just arrived and the Cargo Keeper counts the boxes. That is beat 1, the short delivery: 34 of 36. The judge then walks, at a steady glide at walking pace, to a science site where a crew scientist (Science Officer Okonkwo, a crew member and not one of the five agents) samples the delta rock; gaze and tap shows a real Perseverance close-up (SHERLOC WATSON camera, abrasion patch "Kenmore", sol 1526, NASA/JPL-Caltech/MSSS, PIA26576) with its credit on screen. Next is the solar field, where the Engineer checks the panels and warns of the rising dust storm ("Commander, get inside"). Gaze and tap on the base door to go inside.

**Part 2, inside.** The control room and the crisis, as described above.

On the phone the ground-level scene held about 60 fps at each station in short samples (the door had one 1 s dip to 48); that is a short-sample measurement, not a long soak. The door tap and the scientist tap are described here as what the judge does; they have not been tested on the real headset at the time of writing.

## Spectator view

`AresSpectator` is a macOS app that renders the same SceneKit scene code (`vr/Shared`) as the headset, undistorted and full screen, following the judge's position and orientation through both parts (the phone streams its pose at 30 Hz). It shows subtitles in each agent's colour, the decision card with the option being gazed at, a "N of 7" beat counter and a LIVE or REPLAY badge. With no headset connected it plays the recorded run under a slowly drifting camera (REPLAY). It is read-only.

## In the scene

Nametags above each agent; speech bubbles beside the speaker, with an edge arrow when the speaker is out of view; the ice drill visibly powers down (OFFLINE sign) when that choice is made; and robot "thinking" dots while a model decides.

Visual polish (four reviewer-scored rounds):
- **Control room:** textured, lived-in panels with wear, rubber floor, warm ceiling tubes with housings and ducts, cable trays, vents, lockers with name tapes (fictional crew), hydroponics under grow lights, a stores rack, O2 scrubber, water recycler, whiteboard, an airlock door with hazard stripes, contact shadows and floor markings.
- **Wall screens:** redesigned with a ring gauge, sparklines, KPI tiles and a WAITING card, plus a LOCATION screen on the real Jezero orbital map (PIA23976, NASA/JPL-Caltech/USGS/University of Arizona).
- **Robots:** satin shells, rim glow in their colour, blink and glance, lean when speaking, thinking dots.
- **Outdoor set:** lander, pallets, rover, dish, solar field, habitat with airlock, survey flags, footprints, batched rocks, a grit texture, and storm dust capped outside.
- **Sound (procedural):** hum inside, wind rising with dust opacity, per-agent chimes, a thinking tick and a decision tone.

## Layout

| Path | What |
|---|---|
| `packages/engine` | World-agnostic P2P core: ledger (double entry, hash chain), policy, executor, escalations, audit, trace |
| `packages/agents` | Role brains (rules + LLM), model router (cloud / local / rules), orchestrator with bound identities |
| `packages/world-mars` | Seeded Mars world: market, planted errors + answer key, power model, Mars24, light time, demo director |
| `packages/eval` | Scores runs against the answer key |
| `packages/server` | HTTP + WebSocket hub |
| `packages/console` | Laptop console (React) |
| `vr/` | Native iOS VR (Swift + SceneKit + Google Cardboard SDK) and `AresSpectator`, a Mac app that shows what the judge sees |
| `terrain/` | USGS HiRISE/CTX → meshes |
| `research/` | Research and adversarial-review reports |

See [ARCHITECTURE.md](ARCHITECTURE.md), [PLAN.md](PLAN.md), [CLAIMS.md](CLAIMS.md).

## Data and credits

- **Terrain:** NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX), USGS Astrogeology Science Center, Mars 2020 TRN products.
- **Sun:** Mars24, NASA GISS (Allison & McEwen 2000).
- **Earth-Mars distance:** astronomy-engine (MIT), checked against JPL Horizons.
- **Solar power vs dust:** Opportunity 2018 storm, JPL mission updates.
- **Consumables:** NASA BVAD Rev 1.
- **Google Cardboard SDK:** Apache-2.0.
- **3D models and textures:** Poly Haven, Kenney and Quaternius (all CC0), plus Kenney sound packs (CC0). Full list in [CREDITS.md](CREDITS.md).
- **Imagery:** NASA/JPL-Caltech/MSSS (Perseverance SHERLOC WATSON, PIA26576) and NASA/JPL-Caltech/USGS/University of Arizona (Jezero map, PIA23976). No agency logos are used.
- Suppliers, prices, budget and invoices are **SIMULATED**; crew names are fictional. No NASA or USGS endorsement is implied.
