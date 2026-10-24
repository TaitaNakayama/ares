# Ares

An AI agent team that runs procure-to-pay on its own under deterministic controls, demoed on a crewed Mars base you command from inside a Cardboard VR headset. Built solo at Cal Hacks 13.0.

**A model proposes. Deterministic code decides. Rules are the floor.** Five agents (Engineer, Cargo Keeper, Bill Checker, Money Keeper, Rule Keeper) reason with a language model at their decision points. Every action they take is a typed proposal that goes through `Engine.submit -> policy.evaluate -> verdict -> executor`. The engine checks it against an editable policy (RBAC, segregation of duties, approval limits, three-way match, duplicate and bank-change controls, price statistics, runway), and only an `allow` verdict mints the one-shot ledger token that lets money move. Model output never writes state directly. The engine is world-agnostic; Mars is one swappable simulation.

## How the agents work

- **One generic LLM brain per role.** The model gets the event and a state summary written by code. Its tools are exactly the actions policy permits that role, plus `say` and `report_issue`.
- **Deterministic by design:** price statistics (robust log z-score against history), the three-way match, bank verification and escalation routing. Mechanical steps (executing a scheduled payment, entering structured documents) stay on rules.
- **Three model layers:** cloud (OpenAI, used first when online; 2-8 s per decision measured live), local (Ollama `qwen3.5:9b` on the demo MacBook, the offline fallback; it works, but a cold prompt takes 9-17 s on this fanless M3 Air, so it is slower than the cloud), and rules (the deterministic brains, the floor). On a timeout, an error, an invalid call or an off-script line, the rules brain answers and the proposal is labeled `rules`. A SAFE MODE switch on the console puts every agent on rules instantly.
- **Every proposal is labeled** by what produced it: `llm`, `rules`, `parser` or `human`.
- **On-story guards:** story beats are triggered by the world, never by agents. Spoken lines are checked against the facts the engine provided (numbers, ids) and replaced by the rules' line if they fail. If the rules would escalate to the human and the model doesn't, the escalation still happens (labeled `rules`).
- **Eval so far** (`scripts/eval-llm-story.ts`, 3 seeds, cloud layer): all 7 beats in order 3/3, the commander's decision reached 3/3, the fraud-prevented amount identical to the rules brains 3/3; 25 model decisions, 4 fell back to rules, 0 lines replaced; median 3.0 s per decision, p95 6.2 s. That is 3 seeds so far; a 30-seed run is next. The held-out scorecard measures the rules brains.

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

## Spectator view

`AresSpectator` is a macOS app that renders the same SceneKit scene code (`vr/Shared`) as the headset, undistorted and full screen, following the judge's head (the phone streams its orientation at 30 Hz). It shows subtitles in each agent's colour, the decision card with the option being gazed at, a "N of 7" beat counter and a LIVE or REPLAY badge. With no headset connected it plays the recorded run under a slowly drifting camera (REPLAY). It is read-only.

## In the scene

Nametags above each agent; speech bubbles beside the speaker, with an edge arrow when the speaker is out of view; the ice drill visibly powers down (OFFLINE sign) when that choice is made; and robot "thinking" faces while a model decides.

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
- **3D props and sounds:** Kenney Space Kit, Interface Sounds and Sci-fi Sounds (CC0).
- Suppliers, prices, budget and invoices are **SIMULATED**. No NASA or USGS endorsement is implied.
