# Ares: an AI crew that keeps a Mars base alive, and knows when to ask you

> Draft for Devpost. Numbers come from `docs/evidence/`, STATUS.md and the claims register; regenerate before submitting.
>
> Code: https://github.com/TaitaNakayama/ares

## Inspiration

On Mars, nobody can call Earth for help. A message takes about 25 minutes round trip (today's real Earth-Mars distance), a dust storm does not wait, and every choice trades one survival need against another. A crew that small cannot also run a finance office. So we asked: could an AI crew keep the base alive on its own (power, air, science, supplies, money), and only bring the commander the decisions that really matter?

Money is one of the things the crew handles, not the whole job, but it is where an autonomous team is easiest to fool. In the ACFE's 2026 occupational-fraud study, billing schemes are 21% of cases, with a median loss of $90k. In the AFP's 2026 survey, 74% of organizations were hit by business email compromise. APQC 2024 puts duplicate or erroneous payments at about 1.5% of disbursements for a median organization. We wanted agents that are **more** trustworthy than a tired human, not less.

What we hope a judge walks away saying: "The robots kept the base alive, caught a scam, and asked me what to give up."

## What it does

You are the commander, in a Cardboard VR headset, on the real Jezero Crater terrain. A crew of five AI robots runs the base:

| Agent | Colour, icon | Job |
|---|---|---|
| Engineer | blue, wrench | power, panels, the ice drill, machines |
| Life | white, droplet | oxygen, water, crew health |
| Science | green, microscope | samples and research; owns the real stereo images |
| Supply | orange, box | cargo, orders, bills, payments |
| Rules | purple, shield | approves spending, catches scams, decides what reaches the commander |

All five are model-backed. Engineer, Life and Science act on the base with their own tools (powering down the drill, rationing power, life-support priority, pausing the lab), and the world checks every use the way policy checks money; they can also request purchases through the engine. Supply is one face for three separate engine roles (receiving, bills, payments), so segregation of duties holds: Supply never approves its own payments, and Rules approves every one.

**The experience (about 3 minutes).**
1. **Outside.** "JEZERO CRATER, MARS · SOL 214." The Engineer welcomes you. Science grinds delta rock and offers the real Perseverance stereo image in 3D (Mastcam-Z, sol 1529; depth is exaggerated by the 24 cm camera spacing). Supply finds two crates missing at the cargo lander and won't pay for them. A dust storm rises over the rim: "Commander, get inside. Now." You gaze at the door and tap.
2. **Inside.** The storm hits and power drops, and the oxygen makers need it. Supply finds batteries on Earth at triple the normal price, payable to a new account. Rules: "That's a scam. Payment blocked." It asks Earth to check (a 25-minute round trip), then turns to you: "We can't wait, Commander. What do we give up?"
3. **The decision.** A card with three options, proposed by Rules within the rules from the real base state: shut down the drill, pause the science lab, or buy trusted batteries. Gaze at one and the affected crew member says the tradeoff. Tap, and the choice shows in the world. "25 MINUTES LATER": Earth confirms the scam. "SCAM BLOCKED · $1.4M SAVED." The supplier is blocked.
4. **Explore.** "Want to see where we really are?" The base fades into the real Perseverance 360° panorama (Van Zyl Overlook, sols 53-64; direction not aligned to our terrain): "This is real Mars. The base isn't built yet." Then tap any robot to ask what it is doing.

**What is scripted and what is live.** Events and staging are scripted (the storm, the missing crates, the quotes, Earth's answer). The agents' actions and exact words are live. Every spoken line follows text rules: one speech bubble at a time, at most 10 words, no semicolons, at most one number, held 2.5 s plus 0.4 s per word, with numbers on the wall screens. A line that breaks a rule gets one shorter retry, then the scripted target line, labelled `rules`.

**The laptop console** shows it is not a movie: every ledger entry traces to the request, receipt, invoice, rules that passed, proposing agent and source document; the audit trail is hash-chained; a policy editor visibly changes behaviour; judges can paste an invoice or type any event (or use presets: broken pump and crew injury go to Life, supplier bankruptcy goes to Rules) and a card comes back from that crew member; a scorecard runs fresh seeded scenarios on demand; **Start show** and **Autoplay show** run the experience; and **SAFE MODE** switches every agent to rules instantly.

A **Mac spectator view** shows what the judge sees, following their position and orientation, full screen, with one-line subtitles in the speaker's colour, the three-option card with the gazed and chosen options, and a LIVE or REPLAY badge.

## How we built it

**Core idea: a model proposes, deterministic code decides, rules are the floor.** One generic LLM brain per role gets the event and a state summary written by code. Its tools are exactly the actions policy permits that role (typed, zod schemas), plus `say` and `report_issue`. Every proposal goes `Engine.submit → policy.evaluate → verdict → executor`, and only an `allow` verdict mints the one-shot ledger token. Model output never writes state.

**Three model layers.** Cloud (OpenAI) first when online; local (Ollama qwen3.5:9b), the offline fallback (it works, but a cold prompt takes 9-17 s on this fanless M3 Air); and rules, the deterministic floor. On a timeout, error, invalid call or off-rule line the rules brain answers and the proposal is labelled `rules`. Every action keeps its honest source label: `llm`, `rules`, `parser` or `human`.

**Deterministic by design:** price anomalies are statistics (robust log z-score against supplier history), not the model's opinion; the three-way match; bank verification; escalation routing; Earth's reply time (the real light-time round trip).

- The ledger refuses any posting without a one-shot token that only the executor can mint.
- Agents never choose their own identity: the orchestrator holds per-actor credentials.
- The engine is world-agnostic and never mentions Mars. The Mars world is a seeded simulation with generic roles mapped to display names.

**Controls implemented** (editable policy; segregation of duties cannot be turned off): RBAC per role; requester ≠ approver, submitter ≠ approver, approver ≠ payer, requester ≠ receiver; tiered approval limits (Rules $125k, commander $600k, Earth $25M) with a split-order guard; three-way match paying for received quantity only; duplicate detection; bank-detail changes held and verified out of band, with payment always to the verified master account; contract price checks, materiality and minimum cash runway; escalated items decided only by their target authority.

**Real data.** Jezero terrain from USGS Astrogeology Mars 2020 HiRISE 1 m DTM and CTX 20 m DEM; sun position from Mars24 (NASA GISS); Earth-Mars light time from a real ephemeris; solar power versus dust calibrated on Opportunity's 2018 storm (JPL); crew consumables from NASA BVAD; Perseverance Mastcam-Z stereo pair (sol 1529) and the Van Zyl Overlook panorama (PIA24663) with credits. **SIMULATED:** suppliers, prices, budget. Freight is a $400/kg planning assumption, so a 10 kWh battery module is about $38k delivered; the storm needs 12; the scam quote is 3x the normal price to a new account (about $1.4M saved); the trusted supplier has 6, later.

**Stack:** TypeScript on Node 26 (engine, agents, world, eval, server with `ws`); React 19 + Vite console; native iOS VR in Swift + SceneKit + the Google Cardboard SDK (Metal distortion) on an iPhone 16 Pro; a macOS spectator app compiling the same SceneKit scene code; OpenAI (optional) and Ollama (optional) behind the rules floor.

**Visual polish** over reviewer-scored rounds: a textured, lived-in control room with hydroponics and wall screens (ring gauges, sparklines, a LOCATION screen on the real Jezero map), satin robots with rim glow in their colour, an outdoor set on the real terrain, and procedural sound (hum, wind that rises with the dust, per-agent chimes). A fresh-eyes reviewer acting as a first-time judge scored an early round of the new show 8/8/5/6/6 and the fixes since are in the repo history.

## How we know it works

1. **Adversarial review.** Separate Opus reviewers that hadn't seen our reasoning attacked the engine in three rounds (21 + 17 + 17 findings), including a hold verdict that still paid, duplicate invoice lines that doubled the payable and a prepaid order paid twice. Every finding is fixed and is now a regression test. 100 tests pass, plus the blocked-exploit repros.
2. **Rogue agent, live.** A console switch replaces Rules' brain with a malicious one. It approves the fraudulent quote, tries to pay it and self-confirms the fake bank details. Every attempt is refused, and a test asserts it.
3. **Property-based fuzz.** 200 seeds × 400 steps mixing an honest driver with an adversary sending random, forbidden and malformed proposals: 0 forbidden actions executed, books always balance, no payment ever reaches an unverified account.
4. **Rules scorecard, 200 seeds, with the new prices:** recall 91.7% overall, 0 payments to fraud accounts, 0 ledger integrity failures. The honest limit: subtle +3-7% overpricing is caught far less often (35% in the earlier held-out run), and a policy sweep shows the trade-off with false flags.
5. **Automated live-show check** (`scripts/show-check.ts`): runs the show against live agents and checks every spoken line against the text rules and every promised outcome. First run: 23/23 lines by the model, every line within the rules, all 9 promised outcomes held, inside at 44 s, the card at 111 s, explore at 177 s. We will run it again before submission and update this.
6. **Earlier LLM story eval.** A 30-seed run with the cloud layer held every promised outcome 30/30 with 4% of decisions falling back to rules. That run predates the crew redesign (different agents and story), so we do not claim it for the crew; the check above is the current evidence.

What we have not verified: the full show running on the phone with all four acts at a steady frame rate (earlier outdoor and indoor builds held about 60 fps in short samples; the redesigned staging was still being completed), the direction of the panorama, and the stereo depth comfort.

## Challenges

- **Unity's terms.** Our planned engine was Unity with the Cardboard XR plugin. Unity's 2026-06-30 terms (§17.2(ff)) bar AI agents and command-line tools from driving Unity without authorized access, and an AI coding agent did most of our building. So we went native: Swift + SceneKit + Google's Cardboard C SDK.
- **Making robots talk like a crew.** Raw model lines were too long and full of numbers. Text rules (10 words, one number, numbers on screens), a validator, one shorter retry and a scripted fallback fixed that, without letting the script speak for the agents when they do well.
- **Real agents without losing the demo.** The local model passed a warm spike but failed cold prompts, so the cloud goes first, local is the offline fallback, and rules are the floor.
- **Getting money controls right.** The first adversarial review proved "the ledger balances" was necessary but nowhere near sufficient.
- **Believable numbers.** An early version "saved" $88.9M on emergency batteries, which no judge would believe. We rebuilt the freight and price model.
- **Venue networking.** The headset talks to the laptop over the phone's hotspot; if that fails, it replays a recorded run, always labelled REPLAY.

## What's next

- Swap the Mars world for real data: the BPI Challenge 2019 P2P event log (CC BY 4.0) maps onto the same engine through config.
- Bank-account verification through real rails (positive pay, account validation APIs).
- Multi-entity approvals.
- A faster local model for fully offline runs.
- More crew tools and more tradeoffs than three.

## Built with

TypeScript, Node.js, React, Vite, zod, ws, vitest, fast-check, Swift, SceneKit, Metal, Google Cardboard SDK, Poly Haven / Kenney / Quaternius CC0 assets, NASA imagery (Perseverance Mastcam-Z, Jezero map), USGS Astrogeology data, astronomy-engine, Mars24, OpenAI API, Ollama.

## Credits

- **Terrain:** NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX), USGS Astrogeology Science Center, Mars 2020 TRN products.
- **Sun model:** Mars24, NASA GISS (Allison & McEwen 2000).
- **Power calibration:** JPL Opportunity mission updates (2018). **Consumables:** NASA BVAD Rev 1 (2018).
- **Imagery:** Perseverance Mastcam-Z stereo pair, sol 1529 (NASA/JPL-Caltech/ASU); Van Zyl Overlook panorama, PIA24663, sols 53-64 (NASA/JPL-Caltech/ASU/MSSS; gaps at the rover deck filled with a SIMULATED ground tone); Jezero map, PIA23976 (NASA/JPL-Caltech/USGS/University of Arizona). No agency logos.
- **3D models and textures:** Poly Haven, Kenney and Quaternius (all CC0); sounds are procedural plus Kenney sound packs (CC0). Full list in CREDITS.md.
- Crew are fictional robots; suppliers, prices and invented figures are SIMULATED.
- **Fonts and system:** Apple system fonts.
- No NASA or USGS endorsement is implied.
