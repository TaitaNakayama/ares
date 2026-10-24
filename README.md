# Ares

An AI agent team that runs procure-to-pay on its own under deterministic controls, demoed on a crewed Mars base you command from inside a Cardboard VR headset. Built solo at Cal Hacks 13.0.

**LLM agents only propose. Deterministic code decides.** Every agent action is a typed proposal. The engine checks it against an editable policy (RBAC, segregation of duties, approval limits, three-way match, duplicate and bank-change controls, price statistics, runway) before anything can move money. The engine is world-agnostic; Mars is one swappable simulation.

## Quick start

```bash
pnpm install
pnpm test                                   # 73 tests + 45 blocked-exploit repros + property fuzz
node packages/server/src/main.ts            # http://localhost:8787  (console + API + headset feed)
node packages/eval/src/main.ts --seeds 100 --from 5000   # scorecard on held-out seeds
node scripts/demo-dryrun.ts buy             # the whole demo story, headless
scripts/build-ios.sh                        # native VR app -> your iPhone (needs Xcode + a paired, unlocked phone)
```

Optional: `OPENAI_API_KEY` in `.env` lets the AP agent read free-text invoices with an LLM and draft escalation notes. Without it, a deterministic parser and templates are used. Responses are cached in `.cache/llm/`.

## Layout

| Path | What |
|---|---|
| `packages/engine` | World-agnostic P2P core: ledger (double entry, hash chain), policy, executor, escalations, audit, trace |
| `packages/agents` | Role brains (rules + optional LLM), orchestrator with bound identities |
| `packages/world-mars` | Seeded Mars world: market, planted errors + answer key, power model, Mars24, light time, demo director |
| `packages/eval` | Scores runs against the answer key |
| `packages/server` | HTTP + WebSocket hub |
| `packages/console` | Laptop console (React) |
| `vr/` | Native iOS VR (Swift + SceneKit + Google Cardboard SDK) |
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
