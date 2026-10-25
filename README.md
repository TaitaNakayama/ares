# Ares

**On Mars, nobody can call Earth for help. An AI crew keeps the base alive on its own (power, air, science, supplies, money) and only brings the commander the decisions that really matter.**

You are the commander, in a Cardboard VR headset (native iOS, iPhone 16 Pro) on the real Jezero Crater terrain. A dust storm hits, power drops, the oxygen makers need it, and a supplier offers batteries at triple the price to a new bank account. The crew catches the scam, then asks you the one thing it cannot decide: what do we give up? Built solo at Cal Hacks 13.0.

What a judge should walk away saying: "The robots kept the base alive, caught a scam, and asked me what to give up."

**A model proposes. Deterministic code decides. Rules are the floor.** Under the crew is a world-agnostic procure-to-pay engine (request, receive, three-way match, approve, pay). Every action an agent takes is a typed proposal that goes through `Engine.submit -> policy.evaluate -> verdict -> executor`. Only an `allow` verdict mints the one-shot ledger token that lets money move. Model output never writes state directly. The engine never mentions Mars; Mars is one swappable simulation.

## The crew

Five agents, all model-backed, each with its own colour and icon:

| Agent | Colour, icon | Job |
|---|---|---|
| Engineer | blue, wrench | power, solar panels, the ice drill, machines |
| Life | white, droplet | oxygen, water, crew health |
| Science | green, microscope | samples and research; owns the real stereo images |
| Supply | orange, box | cargo, orders, bills, payments |
| Rules | purple, shield | approves spending, catches scams, decides what reaches the commander |

- **Engineer, Life and Science act on the base** with their own tools: powering down the drill, rationing power, setting life-support priority, pausing the lab. The world checks every use of a tool the way policy checks money. They can also request purchases through the engine.
- **Supply is one face for three separate engine roles**: receiving, bills and payments, each with its own credentials. Supply never approves its own payments; Rules approves every one, so segregation of duties holds. The console shows which role produced each Supply action (Supply · Receiving / Bills / Payments).
- **Rules is the controller.** It approves spending, blocks the scam, asks Earth to verify, and decides what is worth the commander's attention.
- **Every action keeps an honest source label** (`llm`, `rules`, `parser` or `human`). **SAFE MODE** (console button, `POST /api/agents/mode`) switches every agent to rules instantly.
- Price anomalies are statistics (robust log z-score against supplier history), not the model's opinion. The three-way match, bank verification and escalation routing are deterministic.

## The experience (about 3 minutes)

The presenter says a short intro, then the headset goes on.

1. **Outside.** Title "JEZERO CRATER, MARS · SOL 214". The Engineer welcomes the commander. Science grinds delta rock and offers a closer look: tap it for the real Perseverance stereo image in 3D (Mastcam-Z, sol 1529; NASA/JPL-Caltech/ASU; depth is exaggerated by the 24 cm camera spacing). Supply finds two crates missing at the cargo lander and refuses to pay for them. A dust storm rises over the rim. "Commander, get inside. Now." The judge gazes at the door and taps.
2. **Inside.** Life tends the oxygen machine, Rules sits at the console. The storm hits and power drops. Supply finds batteries on Earth at triple the normal price, payable to a new account. Rules: "That's a scam. Payment blocked." It asks Earth to verify (the real 25-minute round-trip light time), then: "We can't wait, Commander. What do we give up?"
3. **The decision.** A card with three options, proposed by Rules within the rules from the real base state: shut down the drill, pause the science lab, or buy trusted batteries. Gazing at an option makes the affected crew member say the tradeoff. The choice shows in the world. "25 MINUTES LATER": Earth confirms the scam. "SCAM BLOCKED · $1.4M SAVED". The supplier is blocked. End card: "An AI crew that keeps a Mars base alive. And knows when to ask you."
4. **Explore.** The Engineer offers "Want to see where we really are?" Tap, and the base fades into the real Perseverance 360° panorama (Van Zyl Overlook, sols 53-64; the direction is not aligned to our terrain; gaps at the rover deck are filled and labelled SIMULATED) with "This is real Mars. The base isn't built yet." Then tap any robot to ask what it is doing. On the laptop console, type any event or use a preset (broken pump and crew injury go to Life, supplier bankruptcy to Rules) and it comes back as a card from that crew member.

The script with timings, the speaker of every line, the cues and the headset/server contract is [docs/demo/script.md](docs/demo/script.md).

## What is scripted and what is live

Events and staging are scripted (the storm, the missing crates, the quotes, Earth's answer). The agents' actions and exact words are live. Details in [docs/scripted-vs-runtime.md](docs/scripted-vs-runtime.md).

**Text rules for everything the crew says**, including live model lines: one speech bubble at a time (at least 1 s apart); at most 10 words, no semicolons, at most one number; a line stays up 2.5 s plus 0.4 s per word; numbers live on the wall screens, not in speech. A line that breaks a rule gets one shorter retry, then the scripted target line, labelled `rules`.

## Numbers

All SIMULATED unless cited. Freight assumption $400 per kg; a 10 kWh battery module is about $38k delivered; the storm needs 12; the scam quote is 3x the normal price to a new account (about $1.4M saved); the trusted supplier has 6, later. Approval limits: Rules $125k, commander $600k, Earth $25M. Sol 214. Earth's reply time is the real round-trip light time for the date.

## How the agents work

- **One generic LLM brain per role.** The model gets the event and a state summary written by code. Its tools are exactly the actions policy permits that role, plus `say` and `report_issue`.
- **Three model layers:** cloud (OpenAI, first when online), local (Ollama `qwen3.5:9b`, the offline fallback; slower, a cold prompt takes 9-17 s on this fanless M3 Air), and rules (the floor). On a timeout, an error, an invalid call or an off-script line, the rules brain answers and the proposal is labelled `rules`.
- **Guards:** story events are triggered by the world, never by agents. Spoken lines are checked against the facts the engine provided and the text rules. If the rules would escalate to the human and the model doesn't, the escalation still happens (labelled `rules`).
- Agents can propose decision options; each is dry-run through policy as the deciding human, and illegal ones vanish.

## Evidence

- **Tests:** 100 pass, plus the blocked-exploit repros and a property-based fuzz. Three adversarial Opus review rounds on the engine (21 + 17 + 17 findings, all fixed).
- **Rules scorecard, 200 seeds, new prices:** recall 91.7% overall, 0 payments to fraud accounts, 0 ledger integrity failures. Subtle +3-7% overpricing is caught far less often (35% in the earlier held-out run); that is the honest limit of statistics at this policy.
- **Automated live-show check** (`scripts/show-check.ts`) verifies every spoken line against the text rules and every promised outcome over live runs. First run: 23/23 lines by the model, every line within the rules, all 9 promised outcomes held. Run it again before submission; the latest numbers are in [STATUS.md](STATUS.md).
- **Earlier LLM story eval (30 seeds)** predates the crew redesign: all promised outcomes held 30/30, 4% of decisions fell back to rules. It measured the old five-agent story, not this crew, and has not been re-run on it.
- **Not yet verified on the headset:** the full show on the phone (door tap, card gaze, reality check) and the frame rate across all four acts. See [STATUS.md](STATUS.md) and [CLAIMS.md](CLAIMS.md) (C-15 to C-19).

## Quick start

```bash
pnpm install
pnpm test                                   # engine scenarios, exploit repros, fuzz
node packages/server/src/main.ts            # http://localhost:8787  (console + API + headset feed)
node packages/eval/src/main.ts --seeds 200  # rules scorecard
scripts/build-ios.sh                        # native VR app -> your iPhone (Xcode + a paired, unlocked phone)
scripts/build-spectator.sh                  # Mac spectator view, full screen (--windowed to test)
```

Start the show from the console (**Start show**, or **Autoplay show** for a hands-free run), or with `POST /api/show/start` and `POST /api/show/autoplay {choice: drill|lab|buy}`. See [docs/demo/runbook.md](docs/demo/runbook.md).

Both model layers are optional; without either, every agent runs on rules.

```bash
ollama serve && ollama pull qwen3.5:9b      # optional: local layer
echo 'OPENAI_API_KEY=...' >> .env           # optional: cloud layer
```

Knobs: `ARES_AGENT_MODE=rules|auto` (`rules` starts in SAFE MODE), `ARES_PREFER=cloud|local`, `ARES_LLM_ROLES`, `ARES_LOCAL_MODEL=off`.

## Spectator view and network

`AresSpectator` is a macOS app that renders the same SceneKit scene code (`vr/Shared`) as the headset, undistorted and full screen, following the judge's position and orientation (the phone streams its pose at 30 Hz). It shows one-line subtitles in the speaker's colour with name and icon, the three-option card with the gazed and chosen options, and a LIVE or REPLAY badge. With no headset it plays a recorded run (REPLAY). It is read-only. The phone's Personal Hotspot is the primary network (venue Wi-Fi is slow); if the headset loses the server, a recorded run plays, always labelled REPLAY.

## Console

Live feed, ledger trace to the source document, hash-chained audit, policy editor, event injector (free text, pasted invoices, presets), scorecard, Rogue Rules switch (a malicious Rules brain whose every attempt is refused), SAFE MODE, and the show controls.

## Layout

| Path | What |
|---|---|
| `packages/engine` | World-agnostic P2P core: ledger (double entry, hash chain), policy, executor, escalations, audit, trace |
| `packages/agents` | Role brains (rules + LLM), model router (cloud / local / rules), orchestrator with bound identities, line validator |
| `packages/world-mars` | Seeded Mars world: market, planted errors + answer key, power model, Mars24, light time |
| `packages/server` | HTTP + WebSocket hub and the show director |
| `packages/eval` | Scores runs against the answer key |
| `packages/console` | Laptop console (React) |
| `vr/` | Native iOS VR (Swift + SceneKit + Google Cardboard SDK) and `AresSpectator` |
| `terrain/` | USGS HiRISE/CTX to meshes |
| `research/` | Research and adversarial-review reports |

See [ARCHITECTURE.md](ARCHITECTURE.md) (parts of its two-part-demo section predate the crew redesign), [PLAN.md](PLAN.md), [CLAIMS.md](CLAIMS.md), [STATUS.md](STATUS.md).

## Data and credits

- **Terrain:** NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX), USGS Astrogeology Science Center, Mars 2020 TRN products.
- **Sun:** Mars24, NASA GISS (Allison & McEwen 2000).
- **Earth-Mars distance:** astronomy-engine (MIT), checked against JPL Horizons.
- **Solar power vs dust:** Opportunity 2018 storm, JPL mission updates.
- **Consumables:** NASA BVAD Rev 1.
- **Imagery:** Perseverance Mastcam-Z stereo pair, sol 1529 (NASA/JPL-Caltech/ASU); Van Zyl Overlook 360° panorama, PIA24663, sols 53-64 (NASA/JPL-Caltech/ASU/MSSS); Jezero map, PIA23976 (NASA/JPL-Caltech/USGS/University of Arizona). No agency logos are used.
- **Google Cardboard SDK:** Apache-2.0. **3D models and textures:** Poly Haven, Kenney, Quaternius (CC0). Full list in [CREDITS.md](CREDITS.md).
- Suppliers, prices, budget and invoices are **SIMULATED**; the crew are fictional robots. No NASA or USGS endorsement is implied.
