# verify-04b: adversarial re-review of the engine after c095b37

Date: 2026-10-23. Reviewer: adversarial subagent (Opus). No file under `src/` was changed.

**Scope.** `packages/engine/src` at c095b37, plus the uncommitted working-tree change as of 19:45 that adds `release_vendor` (remote authority only). I also read `packages/agents/src/orchestrator.ts` and the Mars world, because that is where credentials are bound. `packages/server` is still empty.

**Repro suite.** `packages/engine/test/adversarial-review-2.test.ts`, with the same convention as round 1.

- Each finding has an `it("repro: ...")` that asserts what the engine does today, and an `it.fails("invariant: ...")` that asserts the property we want.
- Result: 22 passed, 18 expected-fail. Full suite: 65 passed, 37 expected-fail, 0 failing.
- I flipped every `it.fails` to `it` and checked that each one fails on its invariant assertion, not on setup.

## Verdicts

| Claim | Verdict | Summary |
|---|---|---|
| **C-10 Ledger correctness** | **HOLDS WITH CAVEATS** | All round-1 cash exploits are closed. Every new double-pay path I built (prepay + invoice, voided invoice re-billed, reject-after-pay) is bounded by `payment.po_cap`. Postings require an `allow` decision and an engine-minted token. Entries are frozen, and the ledger head is cross-checked against the audit log. The caveats are books that strand or never reconcile (N1, N4, N5, N13, N2), event-delivery robustness (N12, N17), and in-process tampering of the audit log and theft of the posting secret (N15, N16). None of them moves more cash than the order total. |
| **C-11 Permission enforcement** | **HOLDS WITH CAVEATS** | RBAC, the literal-true SoD flags, credentials under `requireCredentials` (including `decide` sub-actions), and escalation routing while an escalation is open all held under attack. The caveats: a human "wait" decision isn't binding (N6); escalations can carry stale or undecidable options that lock the controller out (N7); `setPolicy` bypasses credentials (N8); the SoD validator misses verification duties (N9); credentials leak into the audit log (N10); live actor objects allow role mutation (N11); the split guard works per vendor only (N14). |

The engine trusts in-process code completely: brains receive `ctx.engine`, worlds receive `engine`, and every state Map is public. N8, N11, N15 and N16 need such code. An LLM tool call cannot reach them through the current orchestrator, which binds credentials and never hands them to brains.

The world acts as the humans: `external` events submit as `cfo` or the commander with the orchestrator's credential. So credentials isolate the brains, not the world.

## Round-1 fixes re-checked

| Round 1 | Status now |
|---|---|
| C1 hold verdicts move money | Fixed. `vendor.active` is a deny for payments; only `allow` executes outside the side-effect list; `postEntry` refuses non-allow. |
| C2 duplicate invoice lines | Fixed. Duplicates are denied, and the match aggregates by SKU. |
| C3 prepay + invoice double pay | Fixed for cash by `payment.po_cap` and the `prepay_settled` hold. The ledger side can still strand (N5). |
| C4 actorId trusted | Fixed when `requireCredentials` is on, which the orchestrator does. It is still opt-in (default off). |
| H1 reject after partial pay | Fixed for `reject_invoice`. A second door is still open: a rejected verification voids an approved invoice (N13). Cash stays capped. |
| H2 listener re-entrancy | Fixed by deferred events. New issues: N12, N17. |
| H3 forgeable token | Fixed (`#private` fields, `authorize(secret)`). Prototype patching still steals the secret in-process (N16). |
| M1 escalation bypass | Fixed while an escalation is open. A decided "wait" reopens the subject to the agent (N6). |
| M2 split orders | Fixed for the same vendor and item. Across vendors it is not (N14). |
| M3 verification vendor mismatch | Fixed. |
| M4 receipt duplicate lines | Fixed. Over-receipt is flagged and not booked. |
| M5 ledger tail tampering | Fixed for the ledger. The audit log is still mutable (N15). |
| M6 SoD toggle | Fixed: the flags are literal true and the role-conflict validator exists. The validator has a gap (N9), and the policy owner is identified by a string, not a credential (N8). |
| M7 prototype keys crash submit | Fixed. Odd inputs (null, Symbol, throwing getters) are denied and never thrown. |
| L1 quote reuse, L2 early answer, L3 shared objects, L4 decide consumed | Fixed. L3 is fixed only for construction and snapshots; see N11. |
| T1 vacuous fuzz | The fuzz now reaches deep states, and its deep-state test passes. |
| N3 (this round) permanent vendor hold | Withdrawn. `release_vendor` was added in the working tree during this review. |

## New findings

| ID | Sev. | Claim | Finding | Repro (describe block in the test file) |
|---|---|---|---|---|
| N1 | Medium | C-10 | `payment.po_cap` uses the bare PO total, while the match approves up to PO price + 2%. An invoice at the tolerance is approved for 1,224.00, but only 1,200.00 can ever be paid; 24.00 sits in AP forever and the invoice never reaches `paid`. | N1 |
| N4 | Medium (pre-existing, missed in round 1) | C-10 | `invoiced` counts the *billed* quantity of approved invoices, not the quantity paid. Bill 10, receive 8: 8 are paid. When the last 2 arrive, a new invoice matches 0, so the vendor is underpaid and 240.00 stays in GRNI. | N4 |
| N6 | Medium | C-11 | When the CFO decides "wait" (or picks a lever), the escalation closes while the requisition stays `escalated` with no open escalation. The controller then orders 6 of the 10 (4,800.00) one step later. The human decision isn't binding. | N6 |
| N7 | Medium | C-11 | Options are built once, at creation. (a) A transient `prepay_settled` hold on `approve_invoice` auto-escalates with the single option "reject". Once the prepayment settles and AP resubmits, the controller is locked out (`escalation.routing`), and the human's only decide option is to reject a valid invoice. (b) A runway escalation on an approved invoice offers only "reject", which policy always refuses (`use a credit note`), so the escalation stays `awaiting_decision` forever. Schedule-payment escalations on a prepaid PO get zero options. | N7 |
| N8 | Medium (in-process) | C-11 | `setPolicy(p, "rem")` needs only the string "rem", even with `requireCredentials`. Repro: raise `agentMaxCents` without a credential, and the controller approves 8,000.00 alone. Combined with N9, the same code can let the controller confirm its own bank changes. | N8 |
| N9 | Medium | C-11 | `INCOMPATIBLE` doesn't cover verification duties. A policy that gives the controller `answer_verification` is accepted. The controller then requests and confirms a fraudster's account as the vendor master. The same gap applies to record_quote/record_invoice + approve_*. | N9 |
| N2 | Low | C-10 | A scheduled payment is snapshotted to the old bank. After a verified bank change it can't be sent or re-issued (it still consumes the remaining amount and the PO cap). For prepayments it keeps the goods' invoice on `prepay_settled` hold. The only escape is a vendor-wide `hold_vendor` plus the CFO's `release_vendor`, which works (tested). There is no targeted cancel. | N2 |
| N5 | Low | C-10 | A prepayment scheduled after its invoice was approved is allowed. Cash is right (paid once; the invoice payment is capped), but 1,200.00 stays in AP and 1,200.00 in prepayments, never reconciled, and the invoice stays `approved`. | N5 |
| N10 | Low | C-11 | The malformed-proposal path audits `{ input, rules }`, and `input` carries the credential. A credential ends up in the hash-chained audit log. `pendingInbound()` also exposes queued inputs, including their credentials. | N10 |
| N11 | Low (in-process) | C-11 | `engine.actors` values are live, and brains get `ctx.self` from that Map. Setting `.role` gives the AP credential the remote authority's permissions. | N11 |
| N12 | Low | C-10 | `flush()` runs in submit's `finally`. A throwing listener (for example, a closed WebSocket broadcast) makes `submit` throw after the payment was sent, skips later listeners, and leaves `payment_sent` undelivered until an unrelated submit. | N12 |
| N13 | Low | C-10 | `answer_verification(confirmed: false)` sets *any* subject invoice to `rejected` + `voidedAsFraud`, even an approved, part-paid one. Its number becomes reusable and its quantity is freed. The PO cap keeps cash at 1,200.00, but AP ends at 1,200.00 owed on goods paid in full. | N13 |
| N14 | Low | C-11 | The split guard is keyed by vendor and item. 6 batteries from Alpha plus 5 from Beta (9,550.00) are approved in one minute by an agent with a 5,000.00 limit. | N14 |
| N15 | Low (in-process) | C-10 | `AuditLog.all()` returns its internal array and records aren't frozen. Popping the tail erases the CFO's bank-change confirmation, and `verifyIntegrity()` is still clean, because only "execution" records are anchored. | N15 |
| N16 | Low (in-process) | C-10 | Patching `Ledger.prototype.authorize` before construction captures the secret during the opening-balance posting. With it, plus the public `audit.append`, a forged entry passes `verifyIntegrity()`. One JS realm cannot defend against in-process code; this documents the limit. | N16 |
| N17 | Low | C-10 | A listener that answers every event with a submit livelocks: the running flush keeps draining forever, with no step limit. Before the change this failed fast with a RangeError. | N17 |

## Suggested fixes (short)

- **N1:** Cap at the sum of approved invoice amounts plus prepayments, or at `po.total × (1 + tolerance)`, so PPV within tolerance stays payable.
- **N4:** Count `payQty` (the quantity actually matched) in `invoiced`, not the billed quantity.
- **N5:** Treat a prepayment scheduled after invoice approval as a deny, or net it in a settlement step that debits AP and credits prepayments.
- **N6:** Keep the subject routed to the human until the human approves or rejects it. Alternatively, have "wait" keep the escalation open and snooze it rather than close it.
- **N7:**
  - Don't escalate transient `prepay_settled` holds.
  - Rebuild options on delivery and supersede escalations whose options are all invalid.
  - Never offer an option whose sub-action fails policy at creation.
- **N8:** `setPolicy` should require the owner's credential when `requireCredentials` is on, or go through `submit` as an action.
- **N9:** Add `answer_verification` to `INCOMPATIBLE` against request_verification, record_*, approve_* and pay. Add record_* against approve_*.
- **N2:** Add a `cancel_payment` action (treasury or controller), audited, that frees the remaining amount and the cap.
- **N10:** Strip `credential` before auditing. Return copies from `pendingInbound()`.
- **N11:** Hand out frozen actor copies, and keep roles in a `#private` map.
- **N12, N17:** Catch listener errors per listener (log them, keep delivering), and add a cascade bound.
- **N13:** A rejected verification should hold or flag an approved invoice and go through a credit note, not reject it.
- **N14:** Aggregate per approver and item across vendors (optionally with a lower cross-vendor multiple).
- **N15:** Freeze audit records, return copies, anchor the audit head externally, and include it in `verifyIntegrity()`.
- **N16:** Accept the limit in CLAIMS.md, or move the ledger into a separate process or worker with a message API.
- **Credentials:** Default `requireCredentials` to true, and use `crypto.randomUUID()` instead of `Math.random()`.
