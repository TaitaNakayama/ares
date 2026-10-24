# Ares: an AI finance team you can put your hand on the controls of

> Draft for Devpost. Numbers are from `docs/evidence/` and the claims register; regenerate before submitting.
>
> Code: https://github.com/TaitaNakayama/ares

## Inspiration

Small operations buy constantly but can't afford a finance team: research stations, ships, mining camps, restaurants, construction crews. Purchase-to-pay is where money leaks. Three numbers:

- In the ACFE's 2026 occupational-fraud study, billing schemes are 21% of cases, with a median loss of $90k.
- In the AFP's 2026 survey, 74% of organizations were hit by business email compromise. A third of fraud victims saw payment instructions manipulated.
- APQC 2024 puts duplicate or erroneous payments at about 1.5% of disbursements for a median organization.

We wanted to know if an autonomous agent team could run P2P end to end and be **more** trustworthy than a tired human, not less.

We put it on Mars because that's the extreme case. No finance staff on site, the CFO is about 25 light-minutes away (round trip, today's real Earth-Mars distance), and the commander is busy keeping people alive.

## What it does

Five agents run procure-to-pay for a crewed base in Jezero Crater. Each reasons with a language model at its decision points, and every proposal is checked by deterministic code:

- **Engineer**: requests purchases.
- **Cargo Keeper**: counts deliveries.
- **Bill Checker**: reads invoices and quotes and does the three-way match.
- **Money Keeper**: treasury and payments.
- **Rule Keeper**: the controller, which approves, blocks and escalates.

The user stands in the base's control room in a Cardboard VR headset as the **Commander**. The live run goes like this:

1. A delivery arrives 2 air filters short. The invoice bills 36, and the team pays for the 34 that arrived.
2. A dust storm rolls in (real Opportunity 2018 power data). Batteries will run out in 4.6 sols, so the Engineer requests 40 more before the cargo manifest closes.
3. The usual supplier's "quote" arrives at 3x its historical price, asking for payment to a new bank account: classic BEC.
   - The Bill Checker flags both problems with robust statistics.
   - The Rule Keeper blocks payment and asks Earth to verify by call-back.
   - Earth can't answer before the manifest deadline, so the Rule Keeper escalates to the Commander. Every option is checked against policy as the Commander and kept within the emergency limit: buy 15 from a trusted supplier now, wait, or shut down the ice drill. The agent can propose options itself; illegal ones are dropped.
4. The judge chooses with gaze and a tap.
5. Earth's reply arrives after the real light-time round trip: the bank change was fake. The supplier record is locked and $88.9M is saved.

A laptop console shows that it isn't scripted:
- every ledger entry traces back to the request, receipt, invoice, rule results, proposing agent and source document;
- the audit trail is hash-chained;
- a policy editor visibly changes behavior;
- judges can paste any invoice text, or inject events;
- an evaluation scorecard runs hundreds of new seeded scenarios on demand (with the rules brains).

The judge can also steer it:
- Look at an agent in the headset and press: it explains what it is doing, live from current state.
- After the story, type any event on the console, or use a preset (broken water pump, crew injury needing medicine, supplier bankruptcy). Anything no catalog action covers reaches the Commander as an escalation with the agent's recommendation. All three presets reached the Commander in live tests.
- A Mac spectator view shows what the judge sees, full screen, with subtitles in each agent's colour, the decision card and the gazed option, the beat counter and a LIVE or REPLAY badge.

## How we built it

**Core idea: a model proposes, deterministic code decides, rules are the floor.** One generic LLM brain per role gets the event and a state summary written by code. Its tools are exactly the actions policy permits that role (typed, zod schemas), plus `say` and `report_issue`. The flow is `Engine.submit → policy.evaluate → verdict → executor`. Model output never writes state.

**Three model layers.**
- Cloud (OpenAI), used first when online: 2-8 s per decision measured live.
- Local (Ollama qwen3.5:9b on the demo MacBook), the offline fallback. It works, but a cold prompt takes 9-17 s on this fanless M3 Air, so it is slower than the cloud.
- Rules, the deterministic brains. On a timeout, an error, an invalid call or an off-script line the rules brain answers and the proposal is labeled `rules`. A SAFE MODE switch on the console puts every agent on rules instantly.

Statistics, the three-way match, bank verification and escalation routing stay deterministic. Mechanical steps (executing a scheduled payment, entering structured documents) stay on rules by design. Every proposal is labeled `llm`, `rules`, `parser` or `human`.

**On-story guards.** Story beats are triggered by the world, never by agents. Spoken lines are checked against the facts the engine provided (numbers, ids) and replaced by the rules' line if they fail. If the rules would escalate to the human and the model doesn't, the escalation still happens, labeled `rules`.


- Only an `allow` verdict reaches the executor.
- The ledger refuses any posting without a one-shot token that only the executor can mint.
- Agents never choose their own identity: the orchestrator holds per-actor credentials.
- Price anomalies are statistics (robust log z-score against supplier history), not vibes.

**The engine is world-agnostic.** It never mentions Mars. The Mars world is a seeded simulation that plants errors and keeps an answer key the engine never sees.

**Controls implemented** (all editable policy, and segregation of duties can't be turned off):
- RBAC per role;
- segregation of duties: requester ≠ approver, submitter ≠ approver, approver ≠ payer, requester ≠ receiver;
- tiered approval limits with a split-order guard;
- three-way match with price tolerance, paying for received quantity only;
- duplicate detection by invoice number and by amount;
- bank-detail changes held and verified out of band, with payments always going to the verified master account;
- contract price checks, materiality, and minimum cash runway;
- escalation routing: an escalated item is decided only by its target authority, after the message arrives.

**Real data:**
- Jezero terrain: USGS Astrogeology Mars 2020 HiRISE 1 m DTM and CTX 20 m DEM, reprojected and meshed.
- Sun position: Mars24 (NASA GISS).
- Earth-Mars light time: real ephemeris, 12.5 min one way today.
- Solar power vs dust: calibrated on Opportunity's 2018 storm (JPL).
- Crew consumables: NASA BVAD.
- Freight: Falcon Heavy list price divided by Mars payload.
- Suppliers, prices and budget are labeled SIMULATED.

**Stack:**
- TypeScript on Node 26: engine, agents, world, eval and server (`ws`).
- React 19 + Vite console.
- Native iOS VR: Swift + SceneKit + the Google Cardboard SDK (Metal distortion), 60 fps on an iPhone 16 Pro.
- Agent brains: OpenAI (optional, cloud layer) and Ollama (optional, local layer), with the rules brains as the floor. The Bill Checker's model also reads free-text invoices, with an on-disk cache and a deterministic parser as fallback.
- A macOS spectator app that compiles the same SceneKit scene code as the headset.
- Scene: nametags above each agent, speech bubbles beside the speaker (with an edge arrow when the speaker is out of view), the ice drill visibly powering down (OFFLINE sign), and robot "thinking" faces while a model decides.

## How we know it works

1. **Adversarial review.** Separate Opus reviewers that hadn't seen our reasoning attacked the engine in three rounds. Round 1 broke it with 21 findings, including a hold verdict that still paid, duplicate invoice lines that doubled the payable, and a prepaid PO paid twice. Every finding is fixed, and each one is now a regression test: 76 tests plus 45 blocked-exploit repros.
2. **Rogue agent, live.** A console switch replaces the Rule Keeper's brain with a malicious one. It approves the fraudulent quote, tries to pay it, self-confirms the fake bank details and decides for the commander. Every attempt is refused on stage, and a test asserts it.
3. **Property-based fuzz.** 200 seeds × 400 steps mix an honest driver with an adversary sending random, forbidden and malformed proposals. Result: 0 forbidden actions executed, books always balance, and no payment ever reaches an unverified account.
4. **Agent eval, early.** `scripts/eval-llm-story.ts`, 3 seeds, cloud layer: all 7 beats in order 3/3, the commander's decision reached 3/3, the fraud-prevented amount identical to the rules brains 3/3. 25 model decisions, 4 fell back to rules, 0 lines replaced; median 3.0 s per decision, p95 6.2 s. This is 3 seeds so far; a 30-seed run is next.
5. **Evaluation against the answer key (rules brains).** Held-out seeds 5000-5099 (100 runs × 30 purchase cycles), stress profile: error rates far above real life.
   - 100% recall on duplicates, fake bank details (invoice and quote), inflated quotes and invoices, short deliveries and over-contract quotes.
   - **35% on subtle +3-7% overpricing**, which is the honest limit of statistics at this policy.
   - 0.0% of clean invoices blocked, 0.1% of legitimate quotes falsely flagged, 0 payments to fraudulent accounts, 0 ledger integrity failures.
   - A policy sweep shows the trade-off: tightening z from 4 to 2 lifts subtle-overpricing recall from 39% to 67%, while false flags rise from 0.1% to 1.4%.

## Challenges

- **Unity's terms.** Our planned engine was Unity with the Cardboard XR plugin. Unity's 2026-06-30 terms (§17.2(ff)) bar AI agents and command-line tools from driving Unity without authorized access, and an AI coding agent did most of our building. So we went native: Swift + SceneKit + Google's Cardboard C SDK. It renders each eye offscreen, then runs Google's Metal distortion pass.
- **Getting money controls actually right.** The first adversarial review proved our "ledger always balances" claim was necessary but nowhere near sufficient.
- **Making the agents real without losing the demo.** We started with rule-driven agents (we audited this and said so). The local model passed a warm spike but failed cold prompts live, so the cloud goes first, local is the offline fallback, and rules are the floor. Early model runs skipped the verification step and the story drifted; we fixed it in the controller's prompt and the escalation floor.
- **Venue networking.** The headset talks to the laptop over the phone's own hotspot. If that fails, it replays a recorded run, always labeled REPLAY.

## What's next

- Swap the Mars world for real data: the BPI Challenge 2019 P2P event log (CC BY 4.0) maps onto the same engine through config.
- Bank-account verification through real rails (positive pay, account validation APIs).
- Multi-entity approvals.
- A 30-seed LLM eval next to the rules scorecard, and a faster local model for fully offline runs.

## Built with

TypeScript, Node.js, React, Vite, zod, ws, vitest, fast-check, Swift, SceneKit, Metal, Google Cardboard SDK, USGS Astrogeology data, astronomy-engine, Mars24, OpenAI API, Ollama.

## Credits

- **Terrain:** NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX), USGS Astrogeology Science Center, Mars 2020 TRN products.
- **Sun model:** Mars24, NASA GISS (Allison & McEwen 2000).
- **Power calibration:** JPL Opportunity mission updates (2018).
- **Consumables:** NASA BVAD Rev 1 (2018).
- **3D props and sounds:** Kenney Space Kit, Interface Sounds and Sci-fi Sounds (CC0).
- **Fonts and system:** Apple system fonts.
- No NASA or USGS endorsement is implied.
