# BRIEF: Ares (Cal Hacks 13.0)

You are the lead planner (and later, builder) for my solo hackathon project. Read this entire file before doing anything.

## 0. Situation

- Event: Cal Hacks 13.0, Palace of Fine Arts, San Francisco.
- Hacking: Fri Oct 23 6pm to Sun Oct 25 9:00am (hard Devpost deadline; late = not judged). A Devpost draft should be up by Sat night.
- Rule: the project must be started during the event. No project code before hacking begins.
- Judging: Sun 10:30am-12:30pm at my table, live demo required. The guide recommends a 2-minute pitch; judges may stay longer, and the Hyphenate track may ask me to run a scenario of their own. Plan a tight 2-minute core plus optional deeper segments.
- I'm SOLO. I'm a strong full-stack dev (TypeScript, React, Node, Python) and have shipped a native iOS app, but assume limited Unity experience.
- Targets: (1) Hyphenate track: "Autonomous Systems for Finance," $8K/$5K/$3K, top 5 get expedited interviews. (2) Cal Hacks overall prizes (impact, quality, technical complexity, creativity), plus Best Solo Hack.
- My priority is a project that is genuinely good and plausible as a real product, not one that only looks good to judges. I want to be satisfied with it at the deadline.

## Autonomy: work end to end, stop only when you must

Hacking has started. Work as autonomously as possible: research -> plan -> Tier 1 spikes -> build -> verify, without waiting for my approval between phases. Write PLAN.md and CLAIMS.md first, then keep going.

You do NOT need to ask me before:
- installing standard dev tools and packages (Homebrew, npm, pip, Unity packages, GDAL, open-source libraries with permissive licenses)
- creating the Unity project, repo structure, and backend
- downloading public data (USGS terrain, datasets) and free CC0/permissive assets
- choosing between options; pick the best one, record the reasoning in PLAN.md, and move on
- committing to git (commit at every working milestone)

STOP and ask me only when:
1. You need me physically: plugging in the phone, trusting the developer certificate on the phone, Xcode signing steps that need my Apple account, putting the phone in the viewer and confirming what I see, or any other hands-on check.
2. A Tier 1 spike fails and the fix means changing a foundational choice (e.g., abandoning Unity + Cardboard).
3. Something costs money, needs a new account, or needs an API key you don't have.
4. An action is destructive or hard to undo outside the project folder (deleting files outside the repo, changing system settings, force-pushing).

When you stop for me, batch everything you need into one message, make it quick to answer, and keep working on anything that doesn't depend on my answer.

Keep a STATUS.md updated at each milestone: what works, what's in progress, what's blocked, and what's next, so I can check progress at a glance.

## 1. Verification protocol (applies to everything)

In earlier planning, a web-based VR approach was recommended as fact without checking it against my hardware. It doesn't work: Safari on iPhone has no WebXR support. That class of mistake must not happen again.

### Tier 1: Foundational claims, verified exhaustively

Foundational = anything that, if wrong, forces a rebuild or kills the demo. At minimum:

- Engine/plugin/platform compatibility: Unity version x Google Cardboard XR Plugin version x my iOS version x my Xcode version x iPhone 16 Pro
- The iOS build -> Xcode -> signing -> run-on-device pipeline
- Cardboard input (capacitive button tap + gaze selection) working on this phone and viewer
- Network communication between the phone app, the backend on my MacBook, and the laptop console, on venue Wi-Fi, with an offline fallback
- Mars terrain data import and phone rendering performance
- Ledger correctness (double-entry always balances; nothing executes without passing policy)
- Agent permission enforcement (no agent can perform an action its role forbids)
- Every library, package, MCP server, or tool the plan depends on

Every Tier 1 claim must pass ALL four checks:

1. **Context check:** confirm it applies to MY exact setup (section 2). Detect what you can yourself (e.g., `xcodebuild -version`, `sw_vers`, the connected iPhone's iOS version via `xcrun devicectl list devices`). Never assume a version; if you can't detect it, ask.
2. **Sources:** at least two independent, current sources (official docs, release notes, the actual GitHub repo with its recent commits and open issues). Record each with its date. Forum posts alone don't count. Flag anything archived, unmaintained, or with unresolved breaking issues.
3. **Adversarial review:** a separate verifier subagent that has NOT seen your reasoning receives only the claim plus my setup and tries to prove it wrong (known bugs, deprecations, version conflicts, iOS restrictions, license problems). Use a strong model (Opus) for this reviewer.
4. **Hands-on spike:** a minimal throwaway test proving the claim on the real device/setup. Run it as early as possible. Nothing is built on a Tier 1 claim until its spike passes. When a spike needs me (e.g., looking through the viewer), give me one clear checklist of what to confirm.

Run checks 1-3 in parallel with other work; don't block the whole project waiting on reviews.

A Tier 1 claim is VERIFIED only when all four pass. Until then it's labeled UNVERIFIED and must have a named fallback.

### Tier 2: Routine work, verified at milestones

Normal feature code, UI, styling, content: don't verify line by line. Test at milestone checkpoints (end-to-end runs, the evaluation harness, on-device playthroughs). Fix what breaks.

### Claims register

Maintain CLAIMS.md: every Tier 1 claim with status (UNVERIFIED / SOURCED / REVIEWED / VERIFIED), sources with dates, reviewer verdict, spike result, and fallback. Never present an UNVERIFIED claim as fact in the plan or to me.

### Self-checks before handing anything to me

- Re-read the plan against section 2 (my setup) and section 4 (constraints). List anything that conflicts.
- For every recommendation, ask: "What would make this fail on my iPhone, at the venue, at 3am?" Write the answer down.

## 2. My setup (fixed)

- Phone: iPhone 16 Pro (detect the exact iOS version once it's connected).
- Viewer: Google Cardboard V2.3.3. Case off, phone centered on the lens divider. Use the viewer's QR-code lens profile; fall back to the default V2 profile.
- Computer: MacBook Air 15" M3, 24GB RAM. Homebrew for tools. (Detect the Xcode and macOS versions yourself.)
- Apple: paid developer account. Run directly on my phone via Xcode; no App Store or TestFlight.
- Demo: judges use my phone in the viewer. Auto-lock off, max brightness, screen recording kept as backup.
- Engine: Unity with Google's open-source Cardboard SDK as the XR plugin (stereo rendering, lens distortion, head tracking). This is my chosen direction, but verify it under Tier 1. If it's broken on current versions, say so plainly and propose the best fallback.
- Input: ONLY the viewer's capacitive button as a single tap, plus gaze selection (look at something, tap to act). No controllers, no voice.
- Tools: Claude Code. I want full use of available tools: subagents, MCP servers, skills, open-source libraries.

## 3. The project: Ares

### One line

An AI agent team that runs a company's procure-to-pay process on its own, shown working on a crewed Mars base that the user stands in through VR.

### The real product underneath

Procure-to-pay (P2P) is a real business process: someone requests a purchase -> goods are received and counted -> the invoice is checked against the order and the delivery (three-way match) -> payment is approved -> payment is sent. Ares is an autonomous team that runs P2P for an operation with no finance staff on site. Real-world fits: remote operations (Antarctic stations, research ships, mining camps, offshore rigs) and small businesses that buy supplies constantly but can't afford a finance team (restaurants, construction crews, small labs). Mars is the most extreme, most memorable version.

### The Mars story (simple version)

People live and work on a Mars base: they mine ice for water and do science. The base orders everything from stores on Earth (batteries, food, parts, filters, medicine). Nobody on Mars handles money; the commander runs the base and is busy keeping people alive. The finance staff, bank, and suppliers are on Earth, and a message there and back takes about 40 minutes. So a team of AI helpers runs the base's purchasing and money, and only asks the commander for the rare decisions a human must make.

### The user

The person in the headset is the base COMMANDER. They stand in the base's control room: a round room with a large window onto Jezero Crater (real NASA terrain), with solar panels, an ice drill, and the crater walls outside. Three large wall screens show Power, Money, and "Waiting for you."

### The 5 agents (strict permissions; each acts during the demo)

1. **Engineer:** runs power, batteries, ice drill; watches weather; REQUESTS purchases. Cannot approve or pay.
2. **Cargo Keeper:** receives rocket deliveries, counts what arrived, tracks inventory. Cannot order or pay.
3. **Bill Checker (accounts payable):** reads invoices and quotes; three-way match (contract / purchase order / receipt); knows each supplier's price history and bank details on file. Cannot pay or approve.
4. **Money Keeper (treasury):** cash, runway, launch-window deadlines; sends payments once approved. Cannot approve its own payments.
5. **Rule Keeper (controller):** approves or blocks; fraud checks; segregation of duties; escalates to the commander (within an emergency spending limit) or to the Earth CFO (with communication delay); owns the audit trail. Cannot order or pay.

### Robot design

Original design only, NOT copied from any existing character (no Disney/Pixar or other IP). Small floating robots with a screen for a face showing simple expressive eyes. Distinct shape and color per role. Faces show state: calm normally, worried (Engineer) when power drops, suspicious squint and red glow (Rule Keeper) when it catches fraud, looking at the user when a decision is needed.

### The demo run

1. Calm: Cargo Keeper reports a delivery of 34 air filters; Bill Checker sees the invoice billed 36 and pays only for 34 (routine, automatic).
2. A dust storm rolls in; through the window the sky darkens and the solar panels dim. Engineer: power runs out in N sols; requests 40 batteries.
3. Money Keeper: affordable, but must be ordered by sol X to make the next launch window.
4. A quote arrives at 3x the supplier's normal price, with a changed bank account. Bill Checker flags both.
5. Rule Keeper blocks payment, sends verification to Earth (40-minute round trip), and escalates to the commander with options: wait for Earth / buy 15 batteries now from a trusted supplier (within the commander's limit) / shut off the ice drill to save power.
6. The judge chooses by gaze + tap. The base reacts visibly (order placed and paid, or drill powers down outside the window).
7. Earth replies: the bank change was fake. Rule Keeper blocks the supplier; money saved.

### Real data (verify each, cite on screen where relevant)

- Terrain: USGS Astrogeology Mars 2020 Jezero products (HiRISE DTM ~1m + 25cm orthomosaic for nearby detail; CTX DEM 20m + 5m ortho for the wider crater). HiRISE mosaic is ~1.8GB: plan a crop and download early.
- Power model: calibrate solar output vs dust opacity (tau) on Opportunity's 2018 storm data (tau 0.6 -> 645 Wh/sol; tau ~1.5 -> 345; tau 10.8 -> 22) and 2007 storm data (tau 4.12 -> 280 Wh/sol). Scale to the base's array size.
- Sun position and time: Mars24 algorithm; sol = 24h 39m 35s.
- Communication delay from the real Earth-Mars distance; launch windows on the ~26-month cycle; launch cost per kg from a cited published price.
- Crew consumption from NASA human-mission planning figures.
- Anything invented (suppliers, budget, prices) is clearly labeled SIMULATED.

## 4. Non-negotiable architecture

- **Core engine is world-agnostic and must never mention Mars:** the 5 agent roles (as generic P2P roles), a double-entry ledger, a policy file (limits, approval levels, segregation of duties, three-way match tolerance, bank-change = hold and verify, materiality, minimum runway), escalation queues with delay, and an audit trail.
- **Mars world is a swappable simulation** that feeds the core events. Everything is generated from a seed, with planted errors: duplicate invoices, changed bank details, inflated prices, short deliveries, contract violations.
- **LLM agents only PROPOSE.** Deterministic code validates against policy and executes. The LLM never writes to the ledger directly.
- Price anomalies use statistics against supplier history, not the LLM. The LLM handles messy documents, deciding which conflicting source to trust, explanations, and drafting escalations.
- **Proof it isn't hardcoded:**
  - Evaluation harness: hundreds of seeded scenarios vs an answer key; report catch rate, false alarms, money saved, escalations.
  - Random seeds shown on screen; new seed = new suppliers, prices, errors.
  - Policy is an editable config; changing it visibly changes behavior.
  - Any ledger entry traces to its source (request, receipt, invoice, rule, approver).
  - A laptop console where a judge can inject their own event or invoice.
  - Stretch: the same engine running a second real-world dataset (e.g., a public invoice/reconciliation dataset or a Stripe sandbox) via config only.
- **Two clients:** the Unity VR app (commander view) and a laptop console (ledger, audit trail, queues, policy editor, scenario launcher, scorecard). Both stay in sync with the backend live.
- **Explicitly NOT building:** multiplayer, voice, real payments, real suppliers, payroll, revenue, period close.

## 5. Research tracks

You (Opus) orchestrate. Run independent tracks as parallel subagents, defaulting to Sonnet; escalate a track to a stronger model only if its output is thin or contradictory. Tier 1 verifier reviews always use Opus.

1. **Unity + Cardboard on iOS:** which Unity version and Cardboard XR Plugin version work together on my iOS and Xcode today? Maintenance status, open issues, iOS build steps, signing, the QR profile flow, known gotchas. If broken, the best fallback.
2. **Looking great on mobile VR:** URP settings for Cardboard (anti-aliasing, frame-rate target, render scale, baked vs real-time lighting, cheap glow instead of bloom, fog and particles for the storm), text legibility at Cardboard resolution, gaze reticle and selection patterns, avoiding motion sickness, keeping the phone from overheating during repeated demos.
3. **Mars terrain and sky:** GDAL pipeline from USGS data to a Unity terrain or mesh; crop sizes; triangle budget; near-detail vs horizon handling for a view through a window; real sun position; a realistic Mars sky (dusty day, blue sunset) and how the storm changes it, all driven by one tau value shared with the power model.
4. **Assets:** free CC0/permissive sources (e.g., Poly Haven, Kenney, Quaternius, free Unity Asset Store items) for the habitat interior, control room, solar panels, ice drill, robot bodies. A cheap way to build expressive screen faces (texture swap or shader). Verify licenses.
5. **Claude Code tooling:** available Unity MCP servers (which is most reliable and maintained, what it can actually do in the editor), other useful MCP servers or skills, and how to structure the repo so Claude Code works efficiently across Unity C# and the backend.
6. **Backend and agents:** TypeScript engine design; Claude API tool use for the 5 agents; real-time link to Unity on iOS (a WebSocket package that works on iOS builds) and to the laptop console; running everything locally on my MacBook at the venue with an offline fallback; ledger choice (write my own vs Formance, TigerBeetle, Beancount + Fava, Blnk), weighing setup time for a solo 36-hour build.
7. **Evaluation and realism:** generating realistic P2P data with planted errors and an answer key; whether a public dataset (e.g., Invoice Sandbox Benchmark, BenchRec, a Stripe sandbox) could serve as the second world.

## 6. Deliverables

### CLAIMS.md

The claims register from section 1.

### PLAN.md

1. Final tool decisions: choice, exact version, why, alternative rejected, risk, and verification status.
2. Architecture diagram (text) and repo layout.
3. Phone performance budget: frame rate, triangles, textures, draw calls.
4. Visual direction for the control room, window view, robots, and wall screens, with references.
5. Hour-by-hour solo timeline, Fri 6pm to Sun 9am, including sleep (at least 4-5 hours), with checkpoints. The FIRST checkpoint is the Tier 1 spike: a Unity scene running on my iPhone in the Cardboard with head tracking and a working gaze + tap. Then the other Tier 1 spikes (backend <-> phone networking, terrain on device) before feature work.
6. Cut list in priority order if I fall behind. NEVER cut: the core engine, the policy enforcement, the evaluation scorecard, the main demo moment (blocked fake-bank-change payment and the commander's choice).
7. Top 10 risks, each with a mitigation.
8. A "done means" checklist to verify Sunday morning, including: evaluation runs on a fresh seed; any ledger entry traces to its source; a policy edit changes behavior; the full demo run plays on the phone in the viewer at a steady frame rate; a judge-invented event is handled sensibly; the screen recording backup exists.
9. Decisions you made on my behalf, so I can override any of them later (don't wait for me to proceed).

### CLAUDE.md

Create a short CLAUDE.md (under ~60 lines): one-line project summary, the verification protocol in brief, key rules (work autonomously and stop only for the cases in "Autonomy"; LLM agents only propose; core engine never mentions Mars; no Tier 1 work proceeds without a passing spike), common commands, and pointers to BRIEF.md, PLAN.md, CLAIMS.md, ARCHITECTURE.md, and STATUS.md.

### ARCHITECTURE.md

Create ARCHITECTURE.md once the plan is written and keep it current as the build changes.

### STATUS.md

Updated at every milestone (see "Autonomy").

### Order of work

1. Write PLAN.md, CLAIMS.md, CLAUDE.md. Give me a short summary of the key decisions and the Tier 1 claims with their status, then continue without waiting.
2. Run the Tier 1 spikes, starting with the Unity + Cardboard scene on my iPhone. Batch everything you need me to do physically into one checklist.
3. Build in the order of the PLAN.md timeline, committing at each milestone and updating STATUS.md.
4. Before Sunday 8am, walk through the "done means" checklist and report what passes and what doesn't.
