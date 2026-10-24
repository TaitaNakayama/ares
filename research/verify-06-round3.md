# verify-06: adversarial review, round 3

Date: 2026-10-23. Reviewer: adversarial subagent (Opus). No file under `src/` was changed. The live server on :8787 was not touched; everything below ran in-process (vitest, or node scripts that build the same `MarsWorld` + `Orchestrator` the server's `Session` builds).

**Threat model.** An attacker controls anything an LLM agent or an external document can say, including free text pasted by a stranger, and can reach the server's HTTP/WebSocket API on the LAN.

**Repro suite.** `packages/engine/test/adversarial-review-3.test.ts`, round 1-2 convention (`it("repro: ...")` shows today's behaviour, `it.fails("invariant: ...")` states the property we want).
- Result: 6 passed, 9 expected-fail.
- Full suite: 70 passed, 48 expected-fail, 0 failing. `pnpm typecheck` is clean.
- I flipped every `it.fails` to `it`; all nine fail on their invariant assertion, not in setup.

Server, world and agent findings are in prose with repro steps; the in-process evidence is summarised per finding.

## Verdicts

| Claim | Engine in isolation | System as deployed (server + simulated world) |
|---|---|---|
| **C-10** money never moves except as approved and matched, to the verified account | **HOLDS WITH CAVEATS.** Payments run only on `allow`, always use the vendor master bank, are capped per PO, and post through the one-shot token. Caveat: the PO cap is `po.total × (1 + priceTolerancePct)`, and `priceTolerancePct` is unbounded and editable (E1). | **BROKEN.** (1) Any LAN/browser caller edits the policy and lifts the price ceiling (S1+E1); a 50x invoice on received goods then pays out (verified: $31.6M on a $669k PO). (2) The simulated Earth CFO confirms bank changes it should refuse, so "the verified account" is moved without a real verification and the next genuine bill is paid to the attacker (W1, verified: $632k to an attacker routing number). |
| **C-11** no actor acts outside its role; escalations are decided only by their target | **HOLDS WITH CAVEATS.** Held: approve/reject routing while an escalation is open, decide authority + delivery, credentials on `decide` sub-actions, RBAC-first evaluation. Caveats E2, E3, E4, E5, E7, E9. | **BROKEN.** The server attaches the bound CFO/commander credential for *any* HTTP/WS caller, and `/api/decide {as:"remote_authority"}` lets anyone decide as the Earth CFO (S1). |

## Findings by severity

### HIGH

**S1 — the control API has no authentication; policy edits and human decisions are open to any caller.** `packages/server/src/main.ts`.
- `/api/policy` PUT, `/api/decide` (honours `as:"remote_authority"`), `/api/inject`, `/api/director/*`, `/api/eval`, WebSocket `decide` all trust the caller. `Orchestrator.setPolicy`/`submitHuman` attach the CFO's or commander's credential for whoever calls (orchestrator.ts:148-167). So `requireCredentials:true` isolates the brains, not the network.
- Responses carry `access-control-allow-origin: *` and `readJson` parses any body, so a web page merely *visited* on any device on the venue Wi-Fi / phone hotspot can drive every route (not only a deliberate LAN client).
- Repro: `curl -XPUT :8787/api/policy -d '<policy with priceTolerancePct:1e6, agentMaxCents huge, minRunwayDays:0>'` then `POST /api/inject {kind:"invoice", poId, qty:received, unitPrice:50x}`. In-process equivalent (`scratchpad policy.ts`): after `orch.setPolicy(hostilePolicy)` a 34-unit invoice at 50x the PO price on delivered goods is matched, approved and paid; cash out **$31,613,829** on a **$669,469** PO, `verifyIntegrity().ok === true`.
- Fix: bind the human/console channel to a shared secret or local-only socket; never honour `as` from the body; drop wildcard CORS for mutating routes; gate `/api/inject` and `/api/director/*` behind the same secret.

**W1 — the simulated Earth CFO confirms bank changes it should refuse (account-number-only oracle).** `packages/world-mars/src/world.ts:466` with `bankTruth` keyed on `v.bank.account` in the constructor/`catalog.ts`.
- The world's call-back truth table is keyed only by *account number*. A document that reuses a vendor's real account number but a new routing/bank name hashes to "legit", so the CFO auto-answers `confirmed`, and `answer_verification` rewrites the master to the attacker's routing (`engine.ts:1296`). The engine is correct — it faithfully pays "the verified master"; the oracle that verifies is fooled.
- Repro (`scratchpad oracle.ts`, this is exactly `POST /api/inject {kind:"text"}`): paste `Remit to: Mallory, Swiftline Digital Bank, routing 987654321, account <real account #>`. The account number is public (every quote doc prints it; `GET /api/state` exposes it). Verification auto-confirms; master becomes routing 987654321; beat-1's genuine filter invoice then pays **$632,276.58 to routing 987654321**.
- Also (`honest.ts`): a paste that prints only the account number (no routing/bank) makes the deterministic parser fill `bank:"Unknown bank", routing:"000000000"`; the CFO still confirms it and the master is corrupted.
- Fix: key `bankTruth` on the full `bankKey` (bank|routing|account), and in a real deployment require a human CFO plus a hard check that the whole account tuple matches a pre-registered contact, not a single field.

### MEDIUM

**E1 — `priceTolerancePct` is unbounded, and `payment.po_cap` scales with it, so a policy edit erases every price ceiling.** `policy.ts` schema (`z.number().nonnegative()`), `engine.ts:854`. The per-PO cap becomes `po.total × (1 + tol)`; with `tol` huge there is no ceiling. Combined with S1 this is the money-mover. Test: `R3-E1`. Fix: cap `priceTolerancePct` in the schema (e.g. ≤ 25) and/or keep an absolute hard ceiling (small multiple of `po.total`) independent of policy.

**S2 — a hostile policy persists across resets and poisons every future session.** `main.ts:20,41,336`. `policyOverride` is stored on a successful PUT and the next `Session` is built with it; `/api/director/reset` does not clear it (only `/api/policy/default` does). So one PUT survives the reset the presenter does between rehearsals. Beyond the price ceiling (E1), the world *sizes beat-2's decision from the policy*: with `localAuthorityMaxCents:0`, `buildOptions` offers the commander a `buy` for qty `floor(limit/price)=0`, which is dropped — the headline "Buy 15 now" option disappears and the climactic decision is un-makeable. Verified in `policy.ts`. Fix: clear `policyOverride` on `reset()`, or persist it only behind S1's auth and surface it loudly in the console.

**S3 — a non-numeric or huge `speed` bricks the clock and crashes the process.** `POST /api/director/speed {speed:"x"}` → `session.speed = Number("x") = NaN` (main.ts:423) → `tick()` sets `simNow = NaN` → `engine.advanceTo(NaN)` leaves `engine.now = NaN`. `Session.tick` swallows the throw, but `scheduleVrState`'s bare `setTimeout` calls `world.telemetry(NaN)` → `astronomy-engine` throws *outside any try/catch* → uncaught exception ends the Node process. Huge `speed` (e.g. 1e15) drives `now` to a nonsense future with the same telemetry crash. After NaN, no time-gated rule ever passes again (quotes "expired", escalations never deliver). Verified `scratchpad speed.ts`. Fix: `Number.isFinite` guards on `speed`/`paused`; wrap the `vrState`/telemetry timer body in try/catch.

**E2 — the SoD validator still lets a non-human role answer bank verifications.** `INCOMPATIBLE` pairs `request_verification` with `answer_verification`, but AP never needs `request_verification` (its `submit_invoice` hold auto-creates the verification), and nothing confines `answer_verification` to a human role. Granting AP `answer_verification` is accepted; AP then confirms the bank change its own invoice triggered, rewriting the master. Test `R3-E2`. Fix: restrict `answer_verification` to `remote_authority` in `evaluate` (not just via `INCOMPATIBLE`), and add `answer_verification` as incompatible with `record_*`/`submit_invoice`/`approve_*`.

**E4 — an agent removes the human's options while the escalation is open.** `reject_quote` has no `escalationRoutingRule` (engine.ts:569-573). While a requisition is escalated to the CFO, the controller rejects the only clean quote; the CFO's `buy-<quote>` option is then refused (`quote is rejected`). The human's decision is sabotaged by the agent. Test `R3-E4`. Fix: add `escalationRoutingRule` to `reject_quote` (and any action that mutates a subject carrying an open escalation's options).

**E5 — the requester cancels an escalated requisition; its escalation is stranded forever.** `cancel_requisition` allows status `escalated` (engine.ts:504) and has no routing check. After cancel, the CFO's `buy` option fails (`request is cancelled`) and `reject` fails (`request is cancelled`), so the escalation sits `awaiting_decision` with no working option and is never superseded (cancel doesn't call `supersedeEscalations`). Test `R3-E5`. Fix: supersede open escalations on cancel, or deny cancel while escalated.

**W2 — one pasted fraud invoice locks the trusted vendor for the whole demo.** A paste naming the alternative battery supplier with a new bank is held and the controller `hold_vendor`s it. In **demo mode** there is no release (`world.ts:487` fires `release_vendor` only when `mode==="eval"`). When beat 2 runs, the commander's "Buy 15 from `<alt>`" option is gone and `vendor.active` denies any purchase from it. Verified `scratchpad lockout.ts`: with the paste the vendor is `hold` and the decide is denied; without it the buy is `allow`. Fix: give the demo a release path (CFO `release_vendor` after a call-back), and/or don't let an unverified paste flip a vendor to hold without human review.

**E9 — a document's own `dueAt` picks which human gets the escalation.** `createEscalation` sets `decideBy = inv.dueAt` and routes to `local_authority` when the CFO can't answer in time (engine.ts:1381-1386). The LLM/parser sets `dueAt` from the document, so an attacker's past-due date forces the decision to the on-site authority (lower limit, less context) instead of the CFO. Test `R3-E9`. Fix: derive `decideBy` from trusted state (the requisition's `orderBy`, bounded), not from a document field an attacker controls.

**S4 (DoS, medium) — the invoice parser has quadratic regexes and runs inside the single tick loop.** `parseInvoiceText` (`llm.ts:179,186`): `(\d+)\s*(?:x|…)\s*[^@\n]*@…` and the `remit to` bank-name pattern are O(n²) on crafted input. A 200 kB paste to `/api/inject {kind:"text"}` blocks `parseInvoiceText` ~9 s (100 kB ~2.2 s, scaling with size); 40 kB regex-only ~0.35 s. The parse happens on the server's one event loop (`drain` → brains), so it freezes telemetry, VR state and every client. Verified `scratchpad redos.ts`. Fix: cap pasted text length (e.g. 8 kB), anchor/bound the regexes, and/or run the reader off the tick.

### LOW

**E3 — `release_vendor` can be granted to the controller.** `INCOMPATIBLE` doesn't stop one role holding both `hold_vendor` and `release_vendor`, so a policy that adds `release_vendor` to the controller is accepted; the controller could then lift a hold placed after a confirmed fraud with no second party. Test `R3-E3`. Fix: keep `release_vendor` incompatible with `hold_vendor`/`block_vendor`, and confine it to a human role.

**E6 — "wait" (and levers) can be chosen without bound.** Non-final decisions no longer close the escalation (the round-2 N6 fix), but nothing rate-limits them: 50 consecutive `wait` decisions are all `allow`, each emitting `escalation_decided` + appending audit history. Not a money or authority break, but it lets a decision channel spam the audit log and the event stream. Test `R3-E6`. Fix: refuse a repeat of the same non-final option when no new fact (no new verification answer/receipt) has arrived since the last one.

**E7 — a remote decision lands a light-time early.** `answer_verification` got a `sentAt + 2×latency` gate in round 2 (L2), but `decide` has none, so a decision "from Earth" takes effect the instant the escalation is delivered — one one-way light time before a reply could physically return. Via S1 any caller submits it as the CFO immediately. Test `R3-E7`. Fix: gate a remote `decide` by the same round-trip as `answer_verification`.

**E8 (liveness) — a late receipt strands a submitted invoice.** Bill 10, receive 8, submit 960.00; the remaining 2 arrive; `approve_invoice` now denies on `match.amount_within_payable` (payable rose to 1,200.00) and `submit_invoice` refuses a `submitted` invoice, so the invoice is stuck with no action to re-match it. Cash is safe; the book stalls. Test `R3-E8`. Fix: allow re-submission of a `submitted` invoice whose match changed, or re-open to `received` when the payable moves.

**W3 — the "money saved" headline is attacker-settable.** A paste of `999999999 × air filters @ $9,999,999` with no PO raises the `no_po` flag with `amountAtRisk = inv.total`, adding ~$9.99 quadrillion (an unsafe integer) to `prevented` → the VR wall `money.savedText` and `telemetry.preventedTotal`. Ledger integrity stays `ok`; this is a credibility/trust-screen issue, not a cash move. Verified `scratchpad saved.ts`. Fix: bound `amountAtRisk` (e.g. to fair value or the PO/market estimate), and clamp the saved total for display.

**S5 (DoS, low) — `/api/eval` caps `count` at 500 but leaves `cycles` and `from` uncapped.** `runEval` is synchronous on the event loop; `count × cycles` orchestrator runs block all clients. `count` is capped but `cycles` is the stronger lever (1 run × 600 cycles ≈ 0.7 s with no timer ticks); large `cycles` also hits the orchestrator's `maxSteps` and throws. Verified `scratchpad evaltime*.ts`. Fix: cap `cycles` too and/or run eval off-thread.

## What held up under attack

- **Static file serving is safe.** `normalize(join(CONSOLE_DIR, pathname))` + `startsWith(CONSOLE_DIR)` contains `../`, `..\\`, `//` and URL-encoded `%2e%2e` (the URL `pathname` decodes before join, and the result still resolves inside `dist`). No traversal past `CONSOLE_DIR` found (`scratchpad static.mjs`).
- **`/api/record/*` + ffmpeg and `/api/capture`** write only to fixed `.cache`/`docs` dirs with server-generated filenames (`f_%05d.jpg`, `capture-<ts>.jpg`); ffmpeg args are fixed. No path or argument injection from the caller.
- **Engine core (rounds 1-2 fixes).** Payments execute only on `allow`, always to `vendor.bank`, capped per PO; the one-shot token and the audit/ledger cross-check still hold; `requireCredentials` blocks the brains from impersonating roles; approve/reject routing while an escalation is open holds (round-2 N6 is fixed for `approve_*`/`reject_*`). The round-3 escalation findings are all either policy-config gaps (E2, E3), u/actions the routing rule forgot (E4, E5), or latency/liveness (E7, E8, E9) — none lets the brains move cash on their own.

## Bottom line
C-10 and C-11 hold for the engine in isolation (with the E-caveats), but **not for the system as it will be demoed**: the unauthenticated control API (S1) and the account-number-only verification oracle (W1) each independently break both claims, and S2/S3/W2 can brick or hijack the live demo from the venue network. S1 and W1 are the two to fix before judging.
