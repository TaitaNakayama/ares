# What is scripted, and what the agents decide live

_For the pitch. The show: `packages/server/src/show.ts`; text rules: `packages/agents/src/lines.ts`; world: `packages/world-mars`; spec: [demo/script.md](demo/script.md). Checked against STATUS.md and the script on 2026-10-24; I did not re-read the code line by line._

**In one breath:** the world and the show script the events and the staging. The five crew agents decide what to do about them and say it in their own words, inside a policy engine that checks every proposal and keeps the money deterministic. When a model is slow, wrong or too wordy, plain rules take the turn and the label says so.

## Scripted (the world and the show, not the agents)

- **The situation:** Sol 214 at Jezero; the delivery of 34 of 36 filters against an invoice for 36 (the missing crates); the dust storm and its timing; the need for 12 battery modules in a short window; the two quotes (the usual supplier at 3x its price to a fresh bank account, the trusted supplier at its normal price with 6, later); Earth's answer after the real round-trip light time (25 minutes), played as the "25 MINUTES LATER" time-lapse; the supplier lock afterwards.
- **The staging:** the four acts and their order; the title, the door, the window going dark, the Power screen dropping into red, the alarm, the end card, the "SCAM BLOCKED · $1.4M SAVED" payoff; where each robot stands and what job it mimes; the cues (the one glowing thing at a time); the real Perseverance stereo image and panorama and their credits.
- **The target lines:** every scene has a scripted line of the same intent. It is spoken only if the live line fails.
- **The three standard options** (shut down the drill, pause the lab, buy trusted batteries) fill any slot Rules leaves empty.
- **Presentation rules:** one bubble at a time, at least 1 s apart, held 2.5 s plus 0.4 s per word, a held beat before Rules asks the question.
- **Numbers:** freight $400/kg, a 10 kWh module about $38k delivered, limits Rules $125k / commander $600k / Earth $25M. All SIMULATED.
- **The recorded REPLAY tape:** one real run; nothing on it is live.

## Deterministic controls (never a model)
Every policy verdict, the three-way match, price statistics (robust log z-score), bank-change detection and verification routing, approval limits, segregation of duties, the ledger and its one-shot tokens, the amount saved, the audit trail, and the world's check on every use of an agent's base tool (can the drill be powered down, can the lab be paused).

## Live: what the agents decide
At each decision point an agent gets the event and a code-written state summary, and chooses among the actions allowed for its role.
- **Engineer, Life, Science:** whether and how to act on the base with their own tools (power the drill down, ration power, set life-support priority, pause the lab), whether to request a purchase, and their spoken lines. Each tool use is checked by the world.
- **Supply:** how to record the delivery, what to bill and pay (as three separate engine roles: receiving, bills, payments), what to flag, and its lines.
- **Rules:** approve, reject, request verification or escalate; the options it proposes to the commander (each dry-run through policy, illegal ones dropped); holding the supplier after Earth's answer; its lines.
- **Any agent:** the answer when the judge looks at it and presses; and for typed console events, which crew member handles it and the recommendation on its card (pump and injury to Life, supplier bankruptcy to Rules).
- **The exact words** of every line, within the text rules. The model's answers are kept in an on-disk response cache keyed by the exact request (`packages/agents/src/llm.ts`, `CachedProvider`), so the venue's network can drop without losing them: when a scene's facts are the same as in an earlier run, the line is the model's earlier answer, replayed. Those lines are labelled `cached` in `/api/show/log`, the subtitles file and `scripts/show-check.ts`; a scene with new facts (a different seed, a judge's question, a different choice) asks the model again.

## What can replace model output (labelled `rules`)
A timeout, an error, an invalid or unknown tool call, an id the engine doesn't have, a line that breaks the text rules (more than 10 words, a semicolon, more than one number, a fact the engine didn't provide) after one shorter retry, no action where the rules would act, and the escalation floor. SAFE MODE does this for every agent at once. In the round-2 checked runs (three seeds, all three choices), 78 of 78 lines came from the model and all were within the rules; most were replayed from the cache because the scenes' facts repeat across seeds, so run `scripts/show-check.ts` with a cleared cache (`.cache/llm`) before quoting a live rate.

The earlier 30-seed LLM story eval (30/30 promised outcomes, 4% rules fallbacks) predates the crew redesign and has not been repeated on it.
