# What is scripted, and what the agents produce at runtime

_For the pitch. Checked against the code on Sat 2026-10-24 (world: `packages/world-mars/src/world.ts`; agents: `packages/agents/src/llm-agent.ts`, `brains.ts`; engine: `packages/engine`)._

## Scripted or pre-written (the world and the engine, not the agents)

**The situation (the world writes it; the agents don't choose it):**
- The prologue: a routine order of 36 air filters a month ago, with its reason sentence.
- Beat 1: exactly 34 of 36 filters arrive ("2 cartridges missing from the cargo manifest") and the invoice bills 36.
- The dust storm: tau fixed at 4.6, ramping over 20 simulated minutes; the need for exactly 40 battery modules with a 90-minute order deadline; the need's reason and headline sentences are templates filled with numbers from the power model.
- The two battery quotes: the usual supplier at exactly 3x its historical price with a freshly generated fake bank account, and the trusted supplier at its normal price for min(15, commander's limit / price) units.
- Earth's answer to the bank verification: looked up in the world's answer key, with pre-written sentences ("Supplier says it never changed its bank details. The request was fraudulent."), delivered after the real light-time round trip plus processing time.
- The Earth CFO simulator (buy, then approve, then wait), the automatic release of a locked supplier two days later, and the "Ice drill powered down…" line.
- Part 1 outside: the four stations and their order on autoplay; the crew scientist's two lines (world-written, with the real Perseverance reference filled in by code); the Engineer's panel-check line and the storm warning ("Commander, get inside") at the solar field (world-written from the power model).
- The judge's decision options that the engine builds: "Buy N now from X", "Wait for verification", "Shut down the ice drill", "Reject the request", and the two options on a report ("Approve the recommendation", "No action now"); their wording is template text with engine numbers.
- The card text when nothing is pending ("ALL CLEAR … Nothing needs you"), the "ENTER THE BASE" prompt, screen labels, the beat names ("Short delivery", "Suspicious quote", …).
- The REPLAY tape: a recording of one real run (the agents' lines in it were produced by the model at recording time; on playback nothing is live).
- Mechanical steps stay on the rules brains by design: entering structured quotes and invoices, executing an already scheduled payment, voicing a flag the engine raised, the escalation note on a report (the agent's own recommendation is used).

**Deterministic controls (never the model):** every policy verdict, the three-way match, price statistics (robust log z-score), bank-change detection and verification routing, approval limits, segregation of duties, the ledger, "$ saved", the audit trail.

## Produced by the agents at runtime (the model decides, policy checks)

At each decision point the agent gets the event and a code-written state summary and chooses among the actions policy allows it:
- **Engineer:** whether and what to request on an operational need; what to do with any free-text report (a catalog request, or a report to the commander with its own recommendation); its spoken lines.
- **Cargo:** how to record a delivery from the counted lines and the note; its lines.
- **Bills:** what amount to submit after the match (with the match figures provided); whether to raise a flag; reading free-text invoices; its lines.
- **Money:** whether funds cover a request; what to schedule when an invoice is approved; its lines.
- **Rules:** at quote time: approve, reject, request verification, or escalate — and the **options it proposes to the commander** (each dry-run through policy); on a submitted or held invoice: approve or reject; after Earth's answer: hold the supplier or approve; its lines, including the escalation's reason text.
- **Any agent:** the answer when the judge looks at it and presses ("what's going on"), from the current state.
- **Reports:** which agent handles a typed event (model routing, keyword fallback) and the recommendation that reaches the commander.

**Guards that can replace model output (labelled `rules` in the audit trail when they do):** a timeout, an error, an invalid or unknown tool call, an id the engine doesn't have, a line that states a number or id the engine didn't provide (replaced by the rules' line), no action where the rules would act, and the escalation floor (if the rules would hand the decision to the human and the model doesn't, the escalation still happens). In the 30-seed eval, 22% of decisions were taken by rules this way, 1 line in 271 was replaced, and 0 lines with wrong facts reached the display.

## How to say it in one breath
"The world throws the events — the short delivery, the storm, the fake quote, Earth's answer. The five agents decide what to do about them with a language model, inside a policy engine that checks every proposal and keeps the money deterministic. When the model is slow or wrong, plain rules take the turn and the audit trail says so."
