# AUDIT: how the agents actually work

_Written Sat 2026-10-24 04:20 PT, at commit 2341c22. Everything here was checked in code and by running it; nothing is from memory._

## Verdict

Today the five agents are a **rules engine with personas**. Each one is a deterministic event handler with templated dialogue. Only two things call an LLM, and neither changes what happens:
- the Bill Checker reads a *pasted* free-text invoice;
- a helper drafts the plain-language note on an escalation.

The controls are real: every action goes through `Engine.submit → policy.evaluate → verdict → executor`, and money moves only on `allow`. The "AI agents" are not real yet.

## 1. Each agent in code

All money logic is deterministic engine code:
- the policy check: `Engine.evaluate`, `packages/engine/src/engine.ts:482`;
- the three-way match: `computeMatch`, `engine.ts:665`;
- the price statistics (robust log z-score): `priceCheck`, `engine.ts:816`;
- the escalation options: `buildOptions`, `engine.ts:1438`.

The server wires the brains at `packages/server/src/main.ts:39`.

| Agent | Code | What it does | LLM |
|---|---|---|---|
| **Engineer** (requester) | `RequesterRules`, `packages/agents/src/brains.ts:35` | Copies a world `need` event straight into `create_requisition`. The item, quantity, deadline and reason sentence all come from the event. It never decides whether or what to buy. | none |
| **Cargo Keeper** (receiver) | `ReceiverRules`, `brains.ts:55` | Copies the delivery's counted lines into `record_receipt` and adds "Short!" if fewer arrived than ordered. | none |
| **Bill Checker** (AP) | `ApRules`, `brains.ts:82` (submission in `trySubmit`, `brains.ts:154`); `ApWithReader`, `packages/agents/src/llm-brains.ts:10` | Structured documents: enters them, then submits the matched amount. It voices flags the engine raised. Free-text documents only: hands them to the reader. | `readInvoice`, `packages/agents/src/llm.ts:153`. One tool, `record_invoice`, and the prompt says "Call record_invoice exactly once" (`llm.ts:158`). Fallback: the regex parser, `parseInvoiceText`, `llm.ts:181`. |
| **Money Keeper** (treasury) | `TreasuryRules`, `brains.ts:179` | Confirms funds for every request (estimate = quantity × market price). Schedules every approved payment and executes every scheduled one. No prioritization or timing judgment. | none |
| **Rule Keeper** (controller) | `ControllerRules`, `brains.ts:223`; sourcing in `source`, `brains.ts:294` | A fixed procedure. Buy the cheapest clean quote that covers the full quantity. Otherwise request verification for bank mismatches and escalate. Approve anything that passes the match; reject price issues and duplicates; lock the supplier when Earth says the bank change was fake. | Only the separate `EscalationDrafter` (`llm-brains.ts:42` → `draftEscalation`, `llm.ts:211`). It writes the note text and decides nothing. |

**Misleading labels found, fixed Sat 04:45:**
- `RogueBrain` declared `kind = "llm"` (`packages/agents/src/rogue.ts`), but it is a hard-coded script with no model call. Now `"rules"`.
- The orchestrator recorded each proposal's `source` as the brain's kind (`packages/agents/src/orchestrator.ts`). With an OpenAI key set, every Bill Checker proposal was labeled `llm` in the audit trail, including those the rules wrote (6 in a full demo run, none written by a model). Now each `Intent` carries `via` (`rules` | `llm` | `parser`), set by whatever produced it, and the proposal's `source` comes from that.

## 2. The LLM during the 7-beat demo

Measured with `node scripts/audit-llm-calls.ts`: the full story, the production brain setup, a call counter and the real key.
- **1 call in total**, during beats 2-5. It drafts the escalation note: "Tharsis payment is blocked: the quoted account differs from the supplier master, and the $2,221,287.99 quote is 3.02× historical median… Options: Buy 15 verified units…"
- **It decides nothing.** The options are built by the engine.
- **It shows only in the console** (Queues tab, "Note drafted for the human"), never in the headset.
- **Nothing else calls the model.** All story documents arrive with structured fields, so the Bill Checker's reader is never used.
- **Replays are cached.** The same request is answered from `.cache/llm/`, so a rehearsed demo may make zero live calls.

## 3. A novel event: the broken water pump

Run against the live server with the LLM on. There is no inject type for a free-form event; free text can only be pasted as an *invoice* (`main.ts:348`).

**Pasted as text:** "URGENT from Hab-2: crew member Okafor broke the only water pump…; Kepler Salvage offers a used replacement pump at half the new price ($9,000 instead of $18,000), no warranty…"
- The model, offered only `record_invoice`, invented an invoice: `vendorId: ""`, `lines: [{sku: "used replacement pump", qty: 1, unitPrice: 900000}]`, bank "Not provided".
- The Bill Checker said: *"Policy refused my record invoice: unknown vendor; unknown item used replacement pump"*.

**As a need for an item not in the catalog** (`main.ts:337`):
- The Engineer said: *"Policy refused my create requisition: unknown item PUMP-H2O"*.

**Result:** 0 escalations, 0 flags, and no human told that the water recycler is down. It's safe (nothing paid) but useless: the event just dies.

## 4. What is scripted

**Story inputs, written by the Mars world (`packages/world-mars/src/world.ts`):**
- **Prologue** (`:563`): the routine 36-filter order, with its reason sentence "Routine resupply: air filter stock covers 40 sols."
- **Battery quotes** (`:571-593`):
  - the usual supplier at exactly 3× its price, with a freshly generated fake bank account marked fraudulent in the world's answer key;
  - the trusted supplier at its normal price, quantity min(15, Commander limit ÷ price).
- **Beat 1** (`:599`): exactly 34 of 36 arrive ("2 cartridges missing from the cargo manifest"), and the invoice bills 36.
- **Beat 2** (`:614`):
  - storm strength fixed at tau 4.6, ramping over 20 minutes;
  - a need for exactly 40 batteries, with the deadline 90 minutes out;
  - the reason and headline sentences are templates, with numbers from the power model.

**Outcomes decided by the world:**
- **Earth's verification answer** (`:463`): looked up in the answer key (`bankTruth`). The sentences are pre-written: "Supplier says it never changed its bank details. The request was fraudulent." and "Earth: the bank change was fake. The real supplier never sent it." Only the timing is computed (real light-time round trip plus processing).
- **Earth CFO simulator** (`:472`): always picks buy, then approve, then wait. It doesn't act in the main story, whose decision goes to the judge.
- **Auto-release** of a locked supplier two days later (`:485`), and the "Ice drill powered down…" line (`:496`).

**Agent dialogue:** every line is a template string in `brains.ts` with computed numbers filled in.

**Produced at runtime:**
- every verdict, flag, match amount, ledger entry and statistic;
- the escalation options and routing;
- "$88.9M saved";
- the story-beat counter (`storyBeat`, `world.ts:642`);
- the judge's own choice.

## 5. Smallest change to genuine LLM judgment (proposed, not implemented)

One generic LLM brain per role. It gets:
- the triggering event and a short state summary;
- only the actions that role's policy permits, as tools, plus `say` and `escalate`;
- the existing rules brain as the fallback on timeout or error;
- the response cache, for repeatable demos.

Every proposal still goes through `Engine.submit`. Statistics, match math, bank verification and the escalation options stay deterministic, and proposals get honest per-proposal source labels.

| Agent | Smallest real change |
|---|---|
| Engineer | Read free-text operational reports, such as the pump. Decide whether to request a catalog item, or escalate a non-catalog or safety-risk need to a human with a write-up. Needs a "report" inject type and an engine path for non-catalog requests that always goes to a human. |
| Cargo Keeper | Read free-text delivery notes ("2 crushed, 1 missing") into receipt lines. When unsure, ask for a human recount, which the engine turns into a hold. |
| Bill Checker | Give the reader a choice of tools: invoice, quote, "not an invoice, route it" or "conflicting sources, flag it". |
| Money Keeper | When cash or runway is tight, choose which approved payments go now and which later, with reasons. Policy still caps amounts and enforces runway. |
| Rule Keeper | Choose the next action among policy-legal moves: partial order, wait, verify or escalate. Write the recommendation. The engine-built options stay. |

**Cost:** about 4-6 hours with tests and a small LLM eval of about 10 seeds.

**Risks:**
- **Latency:** seconds per live call on venue Wi-Fi.
- **A less fixed story:** policy still forces the beat-5 escalation, because the fake quote can't pass and 15 batteries exceed the Rule Keeper's limit.
- **The scorecard:** it measures the rules brains; hundreds of LLM seeds are slow and cost money.

## Decisions (Sat 2026-10-24)

1. **Spectator view first**, agents later: "keep going with the spectator view on Mac". The agent changes in section 5 are not started.
2. **Report before implementing** any LLM-agent change (your instruction).
3. **Pending your OK:** fix the two misleading labels in section 1. This takes minutes and changes no behavior.
4. **Pending your call:** "Five AI agents" (pitch, Devpost) and "LLM agents only propose" (README, Devpost) overstate what runs today. Either make the agents real (section 5) or reword, e.g. "five rule-driven agents; an LLM reads messy documents and drafts the human note; the architecture lets an LLM propose under the same controls".
5. **Sat 04:50, your decision: make the agents real, keep the demo reliable.** Order of work: labels, a Tier 1 spike of a local model, three model layers (local, cloud, rules), one generic LLM brain per role, on-story guards, judge autonomy, hotspot networking, spectator in parallel, an honest LLM eval. Done so far is in STATUS.md ("Real agents").
6. **Sat 05:30, labels fixed** (3bfae8d) and the `report_issue` path added: a free-text event always reaches the commander with the agent's recommendation.
7. **Sat 05:50, proposed, awaiting you:** cloud-first when online, local as the offline fallback, rules as the floor. Reason: the local model on this fanless Air needs 9-17 s on a cold prompt (verify-08), the cloud answered live decisions in 2-8 s. `ARES_PREFER=local` flips it.
