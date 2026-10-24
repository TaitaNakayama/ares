# verify-04: adversarial review of the engine (claims C-10, C-11)

Date: 2026-10-23. Reviewer: adversarial subagent (Opus). Scope: `packages/engine/src/*` as of 19:03 (engine.ts 19:00, ledger.ts and audit.ts 19:03). No file under `src/` was changed.

Threat model: an attacker controls everything an LLM agent sends (action type, params, actorId, order and timing). Separately marked are findings that need in-process code access (a listener, a console module, a world plugin).

Repro suite: `packages/engine/test/adversarial-review.test.ts`. Run it with `npx vitest run packages/engine/test/adversarial-review.test.ts`.

- Each finding has an `it("repro: ...")` that asserts what the engine does today, and an `it.fails("invariant: ...")` that asserts the claimed property.
- Current result: 29 passed, 21 expected-fail.
- I flipped every `it.fails` to `it` and checked that each one fails on its invariant assertion, not on setup.
- When you fix a bug, both of its tests flip. Delete the repro and turn `it.fails` into `it`.

## Verdicts

| Claim | Verdict | Why |
|---|---|---|
| **1. Ledger correctness** | **BROKEN** | The arithmetic holds: every entry balances, the totals are zero, and in-place edits are detected. The payment conditions do not hold. Money leaves cash under a `hold` decision (C1). The three-way match can be inflated (C2). A PO or an invoice can be paid twice (C3, H1). "Only an allow verdict reaches the executor" is false (C1 for LLM input; H3 in process). Tamper-evidence misses truncation and tail rewrites (M5). |
| **2. Permission enforcement** | **BROKEN** (escalation clause); RBAC and SoD **HOLD WITH CAVEATS** | Per actorId, RBAC is checked before anything else and sub-actions are re-checked. SoD holds while its flags are on, even with widened permissions. The escalation clause fails: an escalated subject can be decided by the other human, or by the target before delivery (M1). The controller can also resolve its own escalation by splitting the order (M2). The whole claim also assumes the caller authenticates actorId, which the engine does not do (C4). |

Claim 1's payment conditions, checked one by one:

| Condition | Status |
|---|---|
| Invoice approved after a three-way match, or prepaid PO approved | BROKEN: the match over-counts duplicate lines (C2); the prepay and invoice paths are not netted (C3); a rejected invoice's quantity is freed (H1) |
| Amount at most the approved amount | Holds per payment. BROKEN per PO (C3, H1) |
| Payee bank equals the verified master | HOLDS. Payment uses `vendor.bank` at schedule and re-checks it at execute. Caveats: M3, C4, L2 |
| Vendor is active | BROKEN (C1) |
| Payer did not approve | HOLDS while `sod.approverCannotPay` is on. It is a policy toggle (M6) |

## Findings by severity

| ID | Severity | Claim | Finding | Needs in-process access? |
|---|---|---|---|---|
| C1 | Critical | 1 | A `hold` verdict on `schedule_payment` and `execute_payment` still schedules and sends the payment, so a vendor on hold gets paid | no |
| C2 | Critical | 1 | Duplicate SKU lines on one invoice multiply the matched payable | no |
| C3 | Critical | 1 | Prepaid PO paid twice (prepayment + invoice), in either order | no |
| C4 | Critical (integration precondition) | 1, 2 | `submit` trusts the caller's `actorId`, so one caller plays every role, including the remote authority that "verifies" a bank change | no (if the agent layer forwards actorId) |
| H1 | High | 1 | Rejecting a partly paid invoice frees its quantity and its invoice number, so it is paid again | no |
| H2 | High | 1 | Re-entrancy: a listener that calls `submit` during the `decision` event double-executes a payment | listener |
| H3 | High | 1 | The ledger token is forgeable: `Ledger.registerAuthorization` is public and unchecked | yes |
| M1 | Medium | 2 | Escalation routing is advisory: the other human, or the target before delivery, approves directly | no |
| M2 | Medium | 2 | The agent's approval limit is per approval: split orders, and the controller resolves its own escalation | no |
| M3 | Medium | 2 | `request_verification` does not tie the vendor to the subject document, so one vendor's change overwrites another vendor's master | no |
| M4 | Medium | 1 | Duplicate SKU lines on a receipt inflate inventory and GRNI | no |
| M5 | Medium | 1 | Hash chain: truncation and tail rewrites pass `verify()`; cached balances are never recomputed | yes |
| M6 | Medium | 2 | SoD is a policy toggle; `setPolicy` accepts any editor id; `engine.policy` is a public mutable field | console/API |
| M7 | Medium | 2 | Action types that are `Object.prototype` keys make `submit` throw, and nothing is audited | no |
| L1 | Low | 2 | A quote recorded for one requisition approves another | no |
| L2 | Low | 2 | A verification answer is accepted after one-way latency, before a reply could physically return | no |
| L3 | Low | 2 | Actor records and `snapshot()` alias live engine state | yes |
| L4 | Low | 2 | `decide` with an `escalate` or `hold` verdict still consumes the escalation | no |
| T1 | High (process) | 1, 2 | The fuzz evidence for C-10/C-11 is vacuous: the walk never creates a PO, so it never sends a payment. Its own deep-state test fails at HEAD | n/a |

## Details

### C1 Critical: money moves under a `hold` verdict

- **Root cause.** `submit` stops only on `deny` (engine.ts:346). `vendorActiveRule` fails with effect `hold` for a vendor on hold (engine.ts:793). The executor for `schedule_payment` checks only `escalate` (engine.ts:1042). The executor for `execute_payment` checks neither (engine.ts:1069). If the vendor is on hold and runway is short, `hold` outranks `escalate`, so the runway escalation is skipped as well.
- **Repro.**
  1. Run the normal cycle up to an approved invoice (1,200.00).
  2. `ctl hold_vendor V-A "suspected fraud: stop all payments"`. This is allowed and cancels any scheduled payments.
  3. `tre schedule_payment` returns verdict `hold` with `executed: true`, and a payment is created.
  4. `tre execute_payment` returns verdict `hold` with `executed: true`. Cash drops by 1,200.00, and the journal entry's decision verdict is `hold`.
- **Impact.** The controller's emergency stop does not stop payments. There is also no action that releases a hold, so a held vendor can only ever be paid through this bug.
- **Fix.**
  - Run `execute` only on `allow`, except for an explicit allow-list of actions that implement hold/escalate side effects (submit_invoice, approve_*, confirm_funds, schedule_payment's escalate branch).
  - Make `vendor.active` a `deny` rule for both payment actions.
  - Add a ledger-side assertion that the decision for every post is `allow`.

### C2 Critical: duplicate invoice lines inflate the three-way match

- **Root cause.** `computeMatch` computes `receivable` per invoice line from the receipts and the other invoices. It never subtracts what earlier lines of the same invoice consumed (engine.ts:573). `record_invoice` accepts repeated SKUs.
- **Repro.**
  1. PO for 10 FLT at 120.00, receipt for 10.
  2. AP records an invoice with lines `[{FLT,10,120.00},{FLT,10,120.00}]`. The payable comes out as 2,400.00.
  3. Submit, approve and pay all pass. 2,400.00 leaves cash for 1,200.00 of goods. GRNI, a liability account, ends at +1,200.00 (a debit balance), and `verify()` stays clean.
  4. With three lines, the payment is 3x.
- **Impact.** A vendor document defeats the core control. It stays under the agent's limit up to 5,000.00 per invoice.
- **Fix.**
  - Aggregate invoice lines by SKU before matching, or carry a running `consumed` per SKU inside the loop.
  - Reject invoices with repeated SKUs.
  - Add an invariant: payable is at most the PO-priced accepted value minus what was already approved for the PO.

### C3 Critical: a prepaid PO is paid twice

- **Root cause.**
  - `schedule_payment(poId)` takes `remaining = po.total - paidOrScheduled({poId})` (engine.ts:707). `paidOrScheduled` counts only payments with no `invoiceId` (engine.ts:1395).
  - The invoice side nets only prepayments that were already *sent* (`prepaidBalance`, engine.ts:1380). Scheduled ones are ignored.
- **Repro A.**
  1. Prepay quote, PO for 1,200.00.
  2. Treasury schedules the prepayment at order time.
  3. Goods arrive. The invoice is submitted and approved at 1,200.00, since the prepayment is not sent yet.
  4. Treasury sends the prepayment, then schedules and sends the invoice payment. 2,400.00 is paid on a 1,200.00 PO.
- **Repro B.** Pay the invoice in full first, then `schedule_payment {poId, 1,200.00}`. It is allowed and sent.
- **Fix.**
  - Track one "paid against PO" figure: prepayments plus payments on that PO's invoices, scheduled or sent.
  - Cap both paths by `po.total`.
  - Have the match net scheduled prepayments, or deny an invoice payment while a prepayment on the PO is still scheduled.

### C4 Critical (integration precondition): actorId is not authenticated

- **Root cause.** `submit(input)` looks up `input.actorId` and applies that actor's role (engine.ts:313). The engine has no notion of a caller.
- **Repro.** One caller runs the whole sequence, choosing the actorId on each call:
  1. As `rcv`: records the receipt.
  2. As `ap`: records an invoice with the fraudster's bank. It is held and a verification is sent.
  3. Advances the clock to `arrivesAt`.
  4. As `rem`: answers the verification `confirmed`. The vendor master becomes the fraudster's account.
  5. As `ap`: resubmits. As `ctl`: approves. As `tre`: schedules and executes.
  6. The payment goes to `bankAFake`.
- **Impact.** In the threat model as stated, RBAC and SoD constrain only ids, not the attacker. This is not an engine bug by itself. It is the precondition every other guarantee rests on.
- **Fix.**
  - In the agents/server layer, bind actorId to the agent's session or socket. Never read it from a tool argument.
  - Accept `decide` and `answer_verification` only from an authenticated human channel.
  - Optionally, have the engine mint an opaque per-actor capability at construction and require it in `submit`.

### H1 High: rejecting a partly paid invoice enables a second payment

- **Root cause.**
  - `reject_invoice` is allowed on an `approved` invoice, even after a payment was sent (engine.ts:454).
  - Rejected invoices drop out of the `invoiced` quantity (engine.ts:555), the duplicate-number check and the duplicate-amount check (engine.ts:523).
  - The AP credit is never reversed (engine.ts:1010).
- **Repro.**
  1. Invoice "A-1001" is approved for 1,200.00 and 600.00 of it is paid.
  2. `ctl reject_invoice` is allowed.
  3. AP records "A-1001" again. It matches 1,200.00, is approved and is paid.
  4. 1,800.00 is paid for 1,200.00 of goods, and the AP subledger still shows 600.00 owed.
- **Fix.**
  - Deny `reject_invoice` once any payment is scheduled or sent; use a credit-note/reversal flow instead.
  - Keep rejected invoice numbers in the duplicate-number check.
  - Cap payments per PO by the received value.

### H2 High (latent): re-entrancy between evaluate and execute

- **Root cause.** `submit` evaluates, emits `decision` synchronously (engine.ts:372), then executes. A listener that calls `submit` for the same payment sees status `scheduled`, gets `allow`, and executes it. The outer `execute` then runs on the stale check.
- **Repro.** Subscribe a listener that, on the first `decision` event for an allowed `execute_payment`, submits the same `execute_payment`. Result: two "Payment PAY-0001" postings, and 2,400.00 out of cash for a 1,200.00 payment.
- **Relevance.** `World.onEngineEvent(e, engine)` receives the engine, and an event-driven agent loop is the natural design.
- **Fix.**
  - Add a re-entrancy guard in `submit`: queue nested calls, except `decide`'s own sub-actions.
  - Emit events only after `execute`.
  - Re-check the precondition (for example, `pay.status === "scheduled"`) inside the executor.

### H3 High (in-process): the posting token is forgeable

- **Root cause.**
  - `PostingAuthorization`'s constructor is private only in TypeScript.
  - `Ledger.registerAuthorization(auth)` is public and adds any object to the live set without the secret (ledger.ts:78).
- **Repro.**
  ```ts
  const t = Object.create(PostingAuthorization.prototype);
  Object.defineProperty(t, "decisionId", { value: "X" });
  e.ledger.registerAuthorization(t);
  e.ledger.post({ /* ..., */ decisionId: "X" }, e.now, t);
  ```
  10,000.00 leaves cash with no proposal and no decision, and `verify()` is clean.
- **Impact.** This contradicts the CLAUDE.md rule "Only an `allow` verdict mints the one-shot ledger token".
- **Fix.**
  - Mint inside the ledger with a `#private` method gated on the secret, and drop the public `registerAuthorization`.
  - Use `#` fields for `entries`, `balances` and `live`.
  - Return frozen copies from `all()` and in `ledger_posted` events.

### M1 Medium: escalations can be bypassed by direct approval

- **Root cause.**
  - Both human roles hold `approve_requisition` and `approve_invoice` directly (policy.ts:87).
  - `approveRequisitionRules` accepts a requisition in status `escalated` (engine.ts:629) with no check on the open escalation's target or delivery.
- **Repro.**
  1. A requisition for 10 BAT at 800.00 escalates to `remote_authority` (status `in_transit`).
  2. Before `deliverAt`, `rem approve_requisition` is allowed. Alternatively, `loc approve_requisition` (within its 15,000.00 limit) is allowed.
  3. The escalation becomes `superseded`.
- **Fix.** While an escalation is open for a subject, deny direct approvals unless `role === esc.to && esc.status === "awaiting_decision"`. Alternatively, remove the direct approve permissions from human roles and route everything through `decide`.

### M2 Medium: limits are per approval

- **Root cause.** `limitRule` checks a single amount (engine.ts:764).
- **Repro.**
  1. 10 BAT (8,000.00) escalates.
  2. The controller approves the same escalated requisition with `qty: 6` (4,800.00), and it is allowed.
  3. A new requisition for 4 is also allowed.
  4. 8,000.00 goes to one vendor for one item, approved by an agent whose limit is 5,000.00. The human never decides.
- **Fix.**
  - Aggregate an approver's commitments per vendor and item over a window.
  - While a subject is escalated, deny `approve_*` to anyone but the target.

### M3 Medium: verification vendor not tied to its subject

- **Root cause.** `request_verification` takes `vendorId` and `subject` independently (engine.ts:467). It compares the subject's bank with the master of the vendor given in the params.
- **Repro.**
  1. Alpha's quote carries a new account.
  2. `ctl request_verification {vendorId: "V-B", subject: <Alpha's quote>}` is allowed.
  3. The CFO confirms the document's change, and Beta's master becomes Alpha's new account. Beta's next payment goes there.
- **Fix.** Require `vendorOf(subject) === params.vendorId`.

### M4 Medium: duplicate receipt lines inflate inventory and GRNI

- **Root cause.** In the receipt executor, `already` is read before the receipt is stored (engine.ts:836). Each duplicate line therefore gets the full cap.
- **Repro.** A receipt with lines `[{FLT,10},{FLT,10}]` on a 10-unit PO books 2,400.00 of inventory against a 1,200.00 order.
- **Scope.** The match caps payable at the PO quantity, so this alone doesn't move cash. The books are wrong, though, and receipts above the PO quantity are also accepted without a flag.
- **Fix.** Accumulate per SKU inside the loop, reject repeated SKUs, and flag over-receipt.

### M5 Medium (in-process): tamper-evidence gaps

- **Root cause.** `verify()` (ledger.ts:138) checks per-entry balance, the hash chain and the cached trial-balance sum. It has no anchor for the head of the chain, and it never recomputes per-account balances from the entries.
- **Repro.**
  - Popping the last entry passes `verify()`, while cash no longer matches the entries.
  - Rewriting the last entry and recomputing its hash also passes `verify()`.
  - Editing a middle entry is detected, with or without re-hashing it (covered by the HOLDS test).
- **Fix.**
  - Recompute balances from the entries in `verify()` and compare them with the cache.
  - Checkpoint `{seq, headHash}` externally, or cross-check against the audit log, which already records each entry hash.
  - Freeze the entries.

### M6 Medium: SoD can be switched off

- **Root cause.** `setPolicy(input, actorId)` (engine.ts:294) accepts any schema-valid policy from any editor string. `engine.policy` is also a public mutable field (engine.ts:165), and assigning it skips validation and audit.
- **Repro.** Set all `sod` flags to false and give the controller `execute_payment`. The controller approves an invoice and releases its own payment.
- **Fix.**
  - Make the SoD flags non-disableable, or require a two-person policy change.
  - Validate that no role holds both an approve permission and a pay permission.
  - Make `policy` private and authorize `setPolicy`.

### M7 Medium: prototype-key action types crash `submit`

- **Root cause.** `parseAction` tests `type in ACTION_SCHEMAS` (actions.ts:100), which is true for inherited keys.
- **Repro.** `submit({type: "toString" | "constructor" | "__proto__" | "hasOwnProperty" | "valueOf"})` throws `TypeError`. No proposal or decision is audited.
- **Fix.** Use `Object.hasOwn`, and wrap `submit` in a try/catch that audits the failure.

### L1–L4 Low

- **L1. Quote reused across requisitions.** `approveRequisitionRules` (engine.ts:623) never checks `q.requisitionId === req.id`.
- **L2. Early verification answer.** `answer_verification` needs only `now >= arrivesAt` (engine.ts:485). The engine's own `expectedVerificationReply` is a latency plus the processing time later. Require at least `sentAt + 2*latency`.
- **L3. Shared mutable objects.**
  - Actors are stored by reference (engine.ts:206), so mutating the caller's array changes RBAC.
  - `snapshot()` (engine.ts:1528) returns live vendor objects, so editing a snapshot rewrites the verified master bank.
  - Events carry live objects too.
  - A listener that mutates `proposal.action.params` on the `proposal` event changes what is evaluated and executed, while the audit keeps the original.
- **L4. `decide` consumes escalations on non-allow verdicts.** `decide` runs with an `escalate` or `hold` verdict (engine.ts:1087): it marks the escalation `decided`, and the sub-action escalates again. No money moves, but the decision record says "decided" while nothing was done.

### T1 High (process): the fuzz evidence is vacuous

- Across 20 seeds × 400 steps there are 440 `approve_requisition` decisions, all `deny`. Every one of 310 `execute_payment` decisions is also `deny`.
- The random walk blocks vendors, rejects quotes and cancels requests long before any PO exists. So the property test's payment invariants (5–7) never run.
- The existing "walk reaches deep states" test fails at HEAD (`sent = 0`).
- CLAIMS.md C-10/C-11 cite this fuzz as **PASS**. That evidence should be withdrawn.
- **Fix.**
  - Bias the walk: rare reject/block actions, plus a happy-path prefix.
  - Assert coverage inside the property.
  - Add targeted generators for the attacks above: duplicate lines, hold-then-pay, prepay plus invoice, reject-then-rebill, listener re-entry.

## What held (tests in the `HOLDS:` blocks)

- **Ledger arithmetic.** Every entry balances and the trial balance sums to zero. Negative, fractional, unsafe (≥ 2^53), NaN, Infinity and string amounts or quantities are refused by zod; `.int()` rejects unsafe integers in zod 4.6.7. PPV credits balance.
- **In-place tampering of a middle entry** is detected, with or without re-hashing it.
- **No double payment through repetition.** A second `schedule_payment` beyond the approved amount, a second `execute_payment`, and a second invoice for already-approved goods are all denied.
- **Bank changes are held.** An invoice with new bank details is held and can't be approved or scheduled. Verification answers before arrival, or from the wrong role, are denied. The payment bank is always the master copy.
- **Caller-held objects are copied.** zod returns fresh objects, and the vendor config is copied at construction, so mutating params or the config afterwards changes nothing.
- **RBAC per actorId.** RBAC is checked first, and denied proposals leave all state untouched; `evaluate` is pure. `decide` re-checks each sub-action under the human's role and current limit. Wrong-authority, undelivered, unknown-option and repeated decisions are denied.
- **SoD with widened permissions and flags on.** Approver ≠ payer, submitter ≠ approver, requester ≠ receiver, and requester ≠ approver all hold, including a human requester deciding its own escalation.
- **Roles outside controller and the two humans have a 0 approval limit.** Granting the treasurer `approve_invoice` only escalates.

## Other observations (not claim violations)

- There is no action that releases a vendor hold. Hold is effectively a permanent block, which makes C1 the only way to pay a held vendor.
- The treasurer both schedules and releases payments (no maker-checker on release).
- `dup.same_amount` and the contract check key on `issuedAt`, which the attacker supplies. An issue date more than 90 days away, or outside the contract window, skips them. The three-way match is the real backstop, and C2 and H1 show where it fails.
- `confirm_funds` estimates with `marketPrice`, which is 0 for an item with no price history, so funds are always confirmed for it. `approve_requisition` re-checks runway.
