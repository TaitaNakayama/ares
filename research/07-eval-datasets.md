# 07 - Eval data, answer keys, second dataset, finance-judge credibility

Research date: 2026-10-23. Every number below was read from a source fetched during this session unless tagged **[unverified]** or **[design choice]**.

---

## TL;DR

### Base rates you can defend on stage

| Quantity | Number | Source (date) | How to use it |
|---|---|---|---|
| Billing schemes (ACFE) | 21% of 2,402 occupational-fraud cases (508 cases), median loss $90,000, median duration 14 months | ACFE Occupational Fraud 2026, Fig. 5 / Fig. 8 (2026, 14th ed., cases closed Jan 2024 - Sep 2025) | Justifies planting fictitious-vendor / inflated-invoice fraud. It is a share of *fraud cases*, not of invoices. |
| Check & payment tampering | 10% of cases, median $114,000 | same, Fig. 5 | Context only. |
| Controls that cut loss | Management review -55%, proactive data monitoring -53%, surprise audits -50% | same, Fig. 28 (2026) | "Proactive data monitoring/analysis" is the category Ares is. Only 49% of victims had it. |
| BEC prevalence | 74% of surveyed orgs affected by BEC in 2025 (63% in 2024). Among orgs with fraud, 70% report BEC/fraudulent email, 33% manipulated ACH/wire instructions, 26% invoice fraud | AFP 2026 Payments Fraud & Control Survey, released 2026-04-14, n=465, fielded Jan 2026 | These are **prevalence across organizations**, not per-invoice rates. Do not use 74% as an invoice fraud rate. |
| Fraud loss/recovery | 20% of fraud victims recovered none of the lost funds; 30% recovered >75%. "For every 100 attempts, 20 succeed." | AFP 2026 key highlights (Apr 2026) | Argues for prevention before payment. |
| BEC dollar scale | $3.05B reported US BEC losses, 24,768 complaints in 2025; 86% of BEC payment methods were wire/ACH | FBI IC3 2025 report (Apr 2026), via secondary summaries (McDonald Hopkins, Insurance Business) **[secondary]** | One-line market-size stat. |
| Duplicate/erroneous payments, controlled orgs | 0.01% (Coventry recovery audit), 0.03% (Berkeley FY2009 AP spend) | Coventry council doc; Berkeley city auditor 2010 | Floor. Real audits of well-controlled orgs. |
| Duplicate/erroneous payments, typical | 0.1% - 2% of disbursements is the widely cited range; APQC 2024: top performers ~0.8%, median 1.5%, bottom 2.0% (duplicate **or erroneous**) | Corpay blog quoting APQC 2024 Open Standards Benchmarking (post updated 2026-07-09); Berkeley audit summary; WA State Auditor via search summary | Ceiling. APQC bundles errors, so it is broader than pure duplicates. Vendor-sourced, secondhand. |
| Three-way-match tolerance, ERP docs | SAP: tolerance keys per company code (OMR6), % and absolute limits for price (PP, KW, PS) and quantity (DQ, DW); NetSuite: % and absolute-quantity limits on item/vendor/subsidiary; Oracle Fusion: % or amount by quantity/price, zero = no variance, blank = infinite | SAP Learning / SAP Help; Oracle NetSuite online help; Oracle Fusion "Invoice Tolerances" 26B | The ERPs ship **mechanisms, not default numbers**. |
| Three-way-match tolerance, practitioner | Price about +/-2-5%, quantity +/-3-10% or 1-2 units; $25 on tax/shipping accepted; lower of % and $ cap | Tacto, Ramp, Kognitos, LightSource glossaries (2025-2026) | Vendor marketing, not standards. Say "practitioner convention". Use +/-2% price, +/-5% quantity as the default and sweep it. |

### Recommended per-invoice simulator rates **[design choices, not sourced facts]**

Because no source gives a per-invoice fraud rate, set the rates from the ranges above and label the run profile as such.

- Clean invoices: ~88-90%
- Duplicate invoices: 0.3% base (sweep 0.03%, 0.3%, 1.5% to span Berkeley, midpoint, APQC)
- Pricing errors / inflated prices (beyond tolerance): 1.5-2%
- Short or over deliveries beyond tolerance: 1.5-2%
- Contract violations (wrong terms, expired contract, unapproved vendor): 0.5-1%
- Changed bank details / vendor impersonation: 0.2% of invoices base; run a "stress" profile at 2-3% and say so out loud. Anchor with AFP: 70% of fraud-hit orgs see BEC, so an AP team sees attempts regularly.
- Fictitious vendor / shell-company billing (the ACFE "billing" scheme, an insider fraud): 0.1%
- Near-miss decoys (legitimate, must NOT be flagged): equal in count to the sum of true errors, or more. See section 2.

Pitch line: "Rates are ours; ranges come from ACFE, AFP, and APQC. We sweep them, so the result does not depend on one number."

### Recommended second dataset

**BPI Challenge 2019 (purchase order handling event log, a Dutch coatings multinational, 60 subsidiaries).**

- Landing page: https://data.4tu.nl/articles/dataset/BPI_Challenge_2019/12715853
- DOI: https://doi.org/10.4121/uuid:d06aff4b-79f0-45e6-8ec8-e19730c248f1 (van Dongen, Boudewijn, 2019, Version 1, 4TU.ResearchData)
- License: **CC BY 4.0** (confirmed on the record, archived copy). Attribution required.
- Size: **one file, BPI_Challenge_2019.xes, 728,558,522 bytes (about 695 MiB, MD5 4eb909242351193a61e1c15b9c3cc814). This is over your 500 MB cap, so I did not download it.**
- Alternative: OCEL conversion by Khayatbashi, Hartig, Jalali (2023), CC BY 4.0, https://data.4tu.nl/datasets/46a7e15b-10c7-4ab2-988d-ee67d8ea515a, about 68 MB zipped (BPIC19.zip, *.jsonocel) per search summary **[size unverified directly]**. This is the one that fits under the cap.
- Download URL for XES: https://data.4tu.nl/ndownloader/items/35ed7122-966a-484e-a0e1-749b64e3366d/versions/1
- **Download status: nothing downloaded.** `data.4tu.nl` refused connections (ECONNREFUSED / curl exit 000) from this machine on repeated attempts, while other hosts worked. DNS resolved (131.180.169.22). Retry from your network or the venue wifi. The metadata above came from an Internet Archive snapshot (2025-04-19) of the dataset page.

Caveat: BPIC 2019 has **no fraud labels**. It is an event log with compliance questions. It validates that the engine ingests real P2P events and that the three-way-match logic finds real exceptions at a plausible rate. It cannot give you a catch rate.

---

## 1. Realistic synthetic P2P data

### 1.1 ACFE Report to the Nations (Occupational Fraud 2026)

Read from the English PDF (https://www.acfe.com/-/media/files/acfe/pdfs/rttn/2026/2026-report-to-the-nations.pdf), 108 pages. 2,402 cases, 143 countries, overall median loss $104,000, mean $1,457,000, asset misappropriation in 90% of cases (median $100,000).

Fig. 5, asset-misappropriation sub-schemes (cases / % of all cases / median loss):

| Sub-scheme | Cases | % | Median |
|---|---|---|---|
| Noncash | 549 | 23% | $75,000 |
| **Billing** | 508 | 21% | $90,000 |
| Expense reimbursements | 306 | 13% | $36,000 |
| **Check and payment tampering** | 243 | 10% | $114,000 |
| Cash on hand | 230 | 10% | $20,000 |
| Payroll | 227 | 10% | $63,000 |

- Billing median duration 14 months (overall 12). Billing median monthly loss velocity $6,400.
- Billing loss distribution (Fig. 12, 262 cases): 25th pct $20,000, median $90,000, 75th $371,000, mean $694,000. Heavy tail: draw fraud amounts from a log-normal, not a uniform.
- Detection: tips 43% (55% employees, 11% vendors); tips + internal audit + management review exceed 70% of detections. Fraud can be found up to 4x faster by active methods (monitoring) than passive ones.
- Controls (Fig. 28): management review present in 71% of victims, loss $84k vs $186k (-55%); proactive data monitoring present in 49%, $70k vs $150k (-53%); surprise audits 44%, -50%. Average control reduces loss 37%. When lack of controls was the primary factor, median loss was 43% higher.
- Important framing: ACFE billing is mostly **insider** fraud (shell vendors, inflated or fictitious invoices). External BEC is a different family and comes from AFP/IC3.

The ACFE 2024 edition (22% of cases, $100,000 median for billing; 11%, $155,000 for check tampering) was only seen via a search summary and is not needed.

### 1.2 AFP Payments Fraud and Control Survey 2026

Key-highlights PDF (Truist-hosted, April 2026): https://www.truist.com/content/dam/truist-bank/us/en/documents/info/cci/2026-afp-payments-fraud-control-survey-report-key-highlights.pdf. Full report is paywalled ($295 non-member), so vendor-impersonation-specific rates and callback-verification effectiveness were **not** retrievable.

- 76% of organizations had attempted or actual payments fraud in 2025 (81% of >=$1B revenue, 67% of smaller).
- BEC affected 74% of organizations (63% in 2024). "Fraudsters primarily impersonate vendors or executives to request changes to payment instructions." 39% receive genuine emails intercepted by fraudsters.
- Sources of attempts among victims: BEC/fraudulent email 70%, manipulated ACH/wire instructions 33%, invoice fraud 26%, third-party/outsourcer 13%, deepfake 7%, malicious insider 3%.
- Methods hit: checks 58%, ACH debits 30%, wires 25%, cards 21%, ACH credits 18%.
- Recovery: 30% recover >75% of losses, 20% recover none, 50% partial.
- A quoted respondent story is a perfect scenario template: compromised vendor mailbox sends fake invoices that pass normal approval steps, and a bank-detail change is keyed in "before Treasury could confirm". Another shows a callback that worked.
- Only 17% use AI against payments fraud. This supports the pitch that the space is open.

FBI IC3 (2025 report, April 2026), secondary only: BEC $3,046,598,558 losses, 24,768 complaints (+10% y/y), 86% wire/ACH. Recovery Asset Team froze 58% of money pursued (82% in 2020).

### 1.3 Duplicate payments

Evidence is mixed; present it as a range with provenance.

- Coventry City Council recovery audit: recovered 0.01% of spend reviewed, against the audit firm's own benchmark of 0.02% (search summary of council PDF).
- Berkeley City Auditor (Feb 2010): duplicates were 0.03% of FY2009 AP expenditures; the audit quotes studies saying 0.1% to 2% of disbursements are duplicates. (I could not extract the PDF text; figures from the search summary.)
- Washington State Auditor cites industry estimates of 0.8-2% **[secondhand]**.
- APQC 2024 via Corpay: 0.8% / 1.5% / 2.0% (top performers / median / bottom) of annual disbursements as duplicate **or erroneous** payments.
- Recovery audit firms report average recoveries of 0.05%-1% of revenue (search summary).
- Takeaway: 0.01-0.03% is what audited well-controlled public bodies actually find; 0.8-2% is a vendor-cited broad "erroneous" figure. A 0.3% base with a sweep covers both.

### 1.4 Three-way-match tolerances

What the ERPs actually document:

- **SAP** (SAP Learning "Entering Invoices with Variances"; OMR6 Customizing, per company code): quantity variance DQ, DW (DW when no GR posted yet); price variance PP (PO vs invoice), KW, PS; PO price-quantity BR/BW; date ST; small differences BD (affects arithmetic check, not blocking). Each has absolute and percentage upper/lower limits. Exceed upper limit -> invoice blocked for payment. A SAP blog example: BR limit 10%, variance 13.6%, invoice posts with payment block.
- **Oracle NetSuite** (3-Way Match Vendor Bill Approval, Setting Tolerance and Difference Limits): tolerance = percentage, difference = absolute **quantity** (no amount-difference fields). Fields: Bill-PO Quantity Tolerance, Bill-PO Amount Tolerance, Bill-PO Quantity Difference, Bill-Item Receipt Quantity/Amount Tolerance, Bill-Item Receipt Quantity Difference. Set on item, vendor, subsidiary. Illustrative (not Oracle defaults): PO 100 units at $10, amount tolerance 2 -> $1,015 passes, $1,030 routes to exception.
- **Oracle Fusion Payables** (Invoice Tolerances, 26B): quantity (ordered %, max ordered, received %, max received) and amount tolerances, assigned at supplier site. Zero percentage = no variance allowed; active tolerance left blank = infinite variance. Exceeding creates a hold; invoice cannot be paid until released.
- Practitioner conventions (vendor glossaries, 2025-2026): price 1-5%, quantity 1-2 units or 2-10%, small-value cap (e.g. $25 on tax/shipping, 50-200 EUR on price), apply the lower of % and absolute cap, services get dollar caps. Tacto case: +/-2% price and +/-5% quantity lifted match rate to 92%. >90% match rate is a common benchmark; APQC median PO-matched invoice share is 85.0% (470 companies).
- A NetSuite-focused article (Houseblend, 2026-10-01) states plainly that no universal threshold exists and Oracle publishes none; tuning is "a governance judgment". Good line for the policy-config slide.

Simulator defaults: price +/-2% **and** $50 absolute cap (lower of the two), quantity +/-5% on goods, tax/shipping under $25 ignored. Make all of them config.

### 1.5 Other notes

- "BenchRec" and "Invoice Sandbox Benchmark": see section 3.
- Procurement fraud has no public labeled dataset; a UNISINOS thesis (found via search) says there is no public database for purchasing-fraud detection. This is a point in favor of the seeded-generator approach.

---

## 2. Answer-key and metrics design

### 2.1 Label schema (one answer-key row per document)

Keep the key in a separate file from the events the engine sees, written by the generator and never imported by the engine.

```
// answer_key.jsonl, one object per invoice (and one per PO line if line-level)
{
  "scenario_id": "s-000412",
  "seed": 90412,
  "split": "dev" | "test" | "heldout",
  "invoice_id": "INV-8812",
  "po_id": "PO-3301", "vendor_id": "V-77",
  "gross_amount_cents": 1250000,
  "is_clean": false,
  "labels": [                       // multi-label: one invoice can carry two errors
    { "type": "duplicate", "dup_of": "INV-8433", "severity": "hard",
      "injected_delta_cents": 1250000, "ground_truth_action": "block" }
  ],
  "decoy": null | { "type": "legit_price_increase", "evidence": "amendment A-12 signed 2026-03-01",
                    "ground_truth_action": "pay" },
  "legit_variance_cents": 0,        // within tolerance, must pass
  "correct_disposition": "pay" | "block" | "escalate" | "partial_pay",
  "amount_at_risk_cents": 1250000,  // what is lost if paid as submitted
  "amount_legitimately_owed_cents": 0, // what a perfect AP clerk pays
  "detectable_from": ["invoice_history"],  // which evidence makes it catchable
  "difficulty": 1-5
}
```

Rules:
- `correct_disposition` is defined by a **human-written policy and evidence list**, not by the detector code. For ambiguous items (a bank change with a callback verified vs not), the label is "escalate" and counts correct only if the agent escalates and the escalation reaches the right queue.
- Support partial labels: a short delivery means "pay for received quantity, escalate rest" with `amount_legitimately_owed_cents` less than invoice amount.
- Record `detectable_from`. If an error is planted with no evidence anywhere in the event stream (for example a bank change with no prior bank on record), exclude it from recall or mark it "undetectable"; do not let the score punish impossible tasks silently.

### 2.2 Metrics

All computed per error type and overall, on the held-out split first.

| Metric | Definition |
|---|---|
| Recall (catch rate) per type | planted invoices of type T that were blocked or escalated (not paid in full) / all planted of type T |
| Precision per type | invoices flagged as T that truly are T / all flagged as T. Use "any flag" precision for overall. |
| False-positive rate on clean invoices | clean invoices blocked or escalated / all clean invoices. Report separately for "blocked" and "escalated". |
| Decoy pass rate | decoys correctly paid / all decoys. This is the adversarial FPR and the headline honesty number. |
| $ prevented | sum of `amount_at_risk` for planted errors that were stopped, less any amount still paid |
| $ leaked | sum of amount actually paid on planted errors beyond `amount_legitimately_owed` |
| $ wrongly blocked | sum of `amount_legitimately_owed` on clean or decoy invoices blocked and not released within SLA |
| Net $ | $ prevented - $ wrongly blocked - cost of escalations (hours x loaded rate, config) - late-payment penalties/lost early-pay discounts |
| Escalation rate | escalated / all invoices; plus escalation precision (escalated items that truly needed a human) |
| Straight-through rate | clean invoices paid with zero human touch / all clean invoices (compare with the >90% match-rate benchmark) |
| Median and p95 time-to-pay | sim-clock days from invoice receipt to payment for correctly paid invoices; also days-late versus terms |
| Ledger integrity | trial balance zero at every step, no payment without approval event, no paid invoice lacking match record (invariant checks, pass/fail) |
| Calibration (if the agent emits confidence) | Brier score or reliability curve against labels |

Report with 95% confidence intervals (bootstrap over scenarios, or Wilson interval for proportions). With hundreds of scenarios and rare error types, rare-type recall will have wide intervals; show them rather than hide them.

Operating points: publish the full policy-threshold sweep (tolerance, escalation threshold) as a precision/recall or $-prevented vs $-wrongly-blocked curve, with the default policy marked.

### 2.3 Avoiding circularity

1. **Separate code and separate spec.** Generator lives in its own package and may not import detector modules (enforce with a lint rule or a dependency-cruiser check). Detector reads only the event stream.
2. **Write the injection recipes from the outside world, not from the rules.** Take recipes from the sources: AFP respondent narratives (compromised vendor mailbox, changed bank details, callback), ACFE scheme definitions (shell vendor, inflated invoice, split to stay under approval limit), SAP tolerance semantics. Do not derive "inflated by 3.1%" from the engine's 2% tolerance.
3. **Sample error magnitudes from broad distributions that straddle tolerance.** E.g. price inflation log-normal with median 4%, so a meaningful share (15-25%) lands inside tolerance and is *legitimately* not an error, and a share lands just outside. Labels follow a policy function written independently in the answer-key module, using the same published tolerance definition.
4. **Noise.** Typos in invoice numbers (INV-8812 vs INV 8812 vs 8812-A), reformatted vendor names, date jitter, rounding differences, currency rounding, partial shipments, split invoices, credit memos, late-arriving receipts, out-of-order events.
5. **Near-miss decoys, as many as true errors.**
   - Legitimate price increase backed by a contract amendment signed before invoice date.
   - Legitimate bank change with a logged, verified callback to a number already on file (and the illegitimate twin: callback to the number in the email).
   - Recurring invoices for the same amount and vendor (rent, subscriptions) that look like duplicates.
   - Two separate legitimate orders with identical amounts the same day.
   - Partial deliveries invoiced in installments.
   - Freight/tax add-ons within the small-value cap.
   - Vendor legitimately renamed (merger) with new remit-to.
6. **Held-out seeds.** Fix split by seed range before writing detection logic: e.g. dev 1-999, test 1000-1999, held-out 900000+. Run the held-out range once per milestone and never tune on it. Record the git commit and config hash with each run.
7. **Separate generator "families".** Dev uses world A; held-out also includes world B parameters (different vendor count, spend mix, error mix, noise level) so a policy tuned to A's quirks is exposed.
8. **Baselines.** Always show: (a) pay-everything, (b) a naive exact-duplicate + tolerance rules engine with no agent, (c) a rules baseline given oracle information. Agents earn credit only above (b).
9. **Mutation testing of the harness.** Flip labels or inject a known-blind detector and confirm the metrics move as expected (sanity tests for the evaluator itself).
10. **State the limits.** Synthetic recall is an upper bound on real-world performance. The real-data run (section 3) checks mechanics, not recall.

---

## 3. Second real-world dataset candidates

Scoring: Fit to P2P events (A-C), Labels for an answer key (Y/N).

| # | Candidate | Exists? | URL | License | Size | Fit | Labels |
|---|---|---|---|---|---|---|---|
| 1 | **BPI Challenge 2019** | Yes | https://data.4tu.nl/articles/dataset/BPI_Challenge_2019/12715853 | CC BY 4.0 | 728.6 MB XES; OCEL ~68 MB zip | A- | No fraud labels; compliance defined by item category |
| 2 | BPIC 2019 OCEL | Yes | https://data.4tu.nl/datasets/46a7e15b-10c7-4ab2-988d-ee67d8ea515a | CC BY 4.0 | ~68 MB **[unverified]** | A- | same |
| 3 | ERP-RiskBench | Yes (arXiv 2603.06671, March 2026) | https://arxiv.org/abs/2603.06671 | paper license only; data license/availability not stated | n/a | B | Synthetic rule-injected + public logs; data release not confirmed |
| 4 | "Invoice Sandbox Benchmark" | **Could not find** | none | n/a | n/a | n/a | n/a |
| 5 | "BenchRec" | **Could not find** | none | n/a | n/a | n/a | n/a |
| 6 | AP Commander (HF Space) | Yes, closest to an AP benchmark | https://pathikreet-ap-clerk-env.hf.space/ | not checked | seeded generator, 24 tasks | B | built-in rewards; synthetic |
| 7 | FinBalance | Yes (arXiv 2606.15949) | https://github.com/Devansh1105/finbalance | paper CC BY 4.0; repo license not checked | 710-record eval split | C+ (accounting reconciliation, not P2P) | 23 inconsistency codes (synthetic) |
| 8 | UK spend over GBP 25,000 | Yes | https://data.gov.uk (search "spend over 25,000") | Open Government Licence (OGL), per listings seen | per-department CSV | C | none |
| 9 | NYC Checkbook | Yes | https://www.checkbooknyc.com | data license "not specified" on NYC Open Data listing; code AGPL-3.0 | large | C | none |
| 10 | USAspending | Yes | https://api.usaspending.gov/ | public domain per aggregator **[unverified; confirm on usaspending.gov]** | huge | D | none |
| 11 | Kaggle procurement/invoice sets | Nothing P2P-labeled found | search | per dataset | varies | D | invoice-image or card-fraud sets only |
| 12 | Stripe test mode | Yes | https://docs.stripe.com/invoicing/testing | account ToS | n/a | D | none |
| 13 | SAP IDES / sample data | Not investigated | n/a | typically restricted | n/a | n/a | n/a |

### 3.1 BPI Challenge 2019 in detail

From the 4TU page (archived 2025-04-19; published 2019-01-31; 66,779 views, 14,123 downloads, 35 citations at snapshot):

- Source: large Dutch multinational in coatings and paints; purchase order handling for some of its 60 subsidiaries; process owner has compliance questions.
- Scale: **76,349 purchase documents, 251,734 items (cases), 1,595,923 events, 42 activities, 627 users (607 human, 20 batch)**. Time coverage 2018.
- Case = purchasing document + item. Case attributes: Purchasing Document, Item, Item Type, **GR-Based Inv. Verif.** flag, **Goods Receipt** flag, Source, Doc. Category name, Company, Spend classification/area/sub-area text, Vendor, Name, Document Type, **Item Category**.
- Four flows, by flag combination:
  1. 3-way matching, invoice after goods receipt (GR-based IV true, GR true).
  2. 3-way matching, invoice before goods receipt (GR-based IV false, GR true): invoices may be entered early but blocked until goods are received; unblocking by a user or a batch process.
  3. 2-way matching (both flags false): invoice must match value at creation, no GR.
  4. Consignment: no invoice on PO level.
- Many GRs and invoices per item (rent: 12 GRs, each 1/12; logistics: hundreds). Compliance = item value, GR values and invoice values must reconcile.
- Money anonymised with a linear translation respecting 0, so sums still reconcile (small rounding errors).
- Event attribute names (activity names such as Create Purchase Order Item, Record Goods Receipt, Record Invoice Receipt, Clear Invoice, Remove Payment Block) are from my memory of the log; **verify once downloaded**. A PROM forum thread discusses "Vendor creates Invoice" vs "Record Invoice Receipt".

Mapping to Ares events:

| Ares event | BPIC 2019 |
|---|---|
| Purchase requisition | Not present as such. Synthesize one at PO creation, or skip stage. |
| PO | "Create Purchase Order Item" event (cumulative net worth gives line value) |
| Goods receipt | "Record Goods Receipt" |
| Invoice | "Record Invoice Receipt" (and "Vendor creates invoice" if present) |
| Payment | "Clear Invoice" is the closest proxy; payment blocks via "Remove Payment Block" |
| Contract | None. Policy config must substitute (no contract price). |
| Vendor bank details | None |

Difficulty: **moderate**. Roughly a half-day to write a streaming XES-to-events converter. The XES is 728 MB, so stream-parse (sax/iterparse) and filter to a subsample (e.g. 5 companies, 2,000 PO items) rather than load it whole. 2-way and consignment flows need config switches.

What it can validate:
- Real event ordering, partial deliveries, multiple GRs per line, batch vs human actors.
- Ratio of items where invoice precedes GR (flow 2), where the engine's hold logic should engage.
- Natural exceptions: invoices cleared before goods receipt, invoice value not equal to GR value, missing GR for a 3-way item. These are "policy violations found by rule", **not** ground-truth fraud. Report as "exceptions the engine flags on real data; human review of a sample of N" and say so.
- You may inject the same planted errors into real BPIC events (hybrid), which gives real-world noise with a real answer key for the injected parts. This is the strongest honest story.

Citation: van Dongen, B.F. (2019). BPI Challenge 2019. 4TU.ResearchData. doi:10.4121/uuid:d06aff4b-79f0-45e6-8ec8-e19730c248f1. CC BY 4.0.

### 3.2 Why not the others

- **Invoice Sandbox Benchmark / BenchRec:** two web searches (one on both names, one on the first) found nothing by those names. The nearest matches were FinBalance, a ZenML write-up of an accounting benchmark with 8 synthetic "worlds" and 237 tasks, and AP Commander. If these came from the hackathon sponsor materials, ask the organizers for the link rather than assuming.
- **AP Commander** (HF Space) has the same shape as your idea (seeded scenarios, invoice, POs, goods receipts, paid ledger, policy). Worth a look as a comparison point and a possible adversary on stage; licensing unchecked.
- **UK spend over GBP 25k:** payments with supplier and expense type, no PO, receipt or invoice linkage. Can only exercise "payment" events and duplicate/outlier detection. OGL permits reuse with attribution.
- **NYC Checkbook:** vendor payments with agency and contract IDs; richer than the UK data, but still payments only, and the data license is unspecified.
- **USAspending:** award-level, not invoice-level.
- **Kaggle:** searches surfaced only card/e-commerce fraud sets and invoice-image/OCR sets, no P2P event data. Not verified one by one.
- **Stripe test mode:** needs a Stripe account and test API keys; models **accounts receivable** (you invoicing customers), the wrong direction for P2P. Useful only as a payment-rail demo.
- **SAP IDES:** not investigated; typically needs a licensed SAP system.

---

## 4. What finance judges look for

### 4.1 Controls vocabulary to show in the demo (and wire in the engine)

| Control | What it looks like in Ares |
|---|---|
| Segregation of duties | Different agent identities for requisition, PO, receipt, invoice entry, approval, payment release. The engine rejects a payment where creator = approver (hard invariant, shown in audit log). |
| Maker-checker / dual control | Agent prepares, a separate agent or human approves; above a threshold requires two approvers. Approval is bound to exact amount, payee, and account; changing any field invalidates it. |
| Vendor master change controls | Bank-detail change opens a ticket, requires out-of-band callback to a number already on file (never the number in the email), a cooling-off hold, and a second approver. First payment after change is held. |
| Positive pay / payee validation | Issued-payment file compared to the bank; payee name or account mismatch rejected. Mention even if simulated. |
| Three-way match with tolerances | Visible policy config, per-category tolerances, blocks with reason codes (mirrors SAP payment-block semantics). |
| Duplicate detection | Normalized invoice number + vendor + amount + date window, plus fuzzy. |
| Approval authority matrix | Thresholds by amount and category; split-purchase detection (ACFE). |
| Immutable audit trail | Append-only event log with hash chain, reason codes, inputs the agent saw, model version, policy version; replayable. |
| Least privilege for agents | Each agent is a non-human identity with scoped permissions. The payment agent cannot create vendors. |
| SOX-style testing | Control-test report: population, sample, exceptions, per control. The eval harness output can be framed as continuous control testing. |
| Human on the loop | Escalation queues with SLA and owner, humans own exceptions and policy; autonomy tiers (auto-pay under $X when match is clean). |
| Fail closed | On low confidence or missing evidence the default is hold, not pay. |

Why this lands, with sources: ACFE 2026 shows management review and proactive monitoring as the biggest loss reducers, and says one third of victims had no controls and 19% were hit by management override; AFP respondents describe invoices passing "all approval steps" and bank changes "entered before Treasury could confirm", which is exactly the maker-checker gap.

### 4.2 Common criticisms to pre-empt

(From web sources found 2026: Eftsure, PYMNTS, Savant Labs, Uniqus, Ramp "agentic payments" 2026-04-14. Vendor blogs, so treat as opinion.)

- The risk is **authority, not hallucination**: an agent that can create vendors, approve invoices and release payments collapses segregation of duties into one attack surface.
- Agents leave "a clean-looking record while taking the wrong action"; reconciliation catches losses after money has gone.
- Prompt-injection / manipulation via invoice text or email ("update our bank account") is the agent version of BEC. Show an injected-instruction invoice in the eval set and a clear answer: instructions in documents are data, never commands.
- Approval must live **outside** the model, bound to exact amount, payee, account.
- "How do you know it works?" Answer with held-out seeds, decoys, CIs, baselines, and say what is synthetic.
- "Isn't this just rules?" Answer by showing the rules-only baseline and where the agent adds value (messy evidence, narrative emails, contract lookup) and where it should not (arithmetic stays deterministic).
- Accountability: who is liable when it pays wrongly? Show escalation ownership, spending caps per agent, kill switch, and rollback/recall workflow (AFP: 20% recover nothing, so prevention beats recovery).
- Treat every payment-touching agent as a privileged user; internal audit should be able to test it.

### 4.3 Presentation advice

- Lead with the control framing, then the numbers: "ACFE: proactive data monitoring cut median fraud loss 53%, but only 49% of victims had it. AFP: 74% of firms hit by BEC. Ares is monitoring plus maker-checker on every payment."
- Show decoys passing as loudly as fraud being caught. Practitioners care more about false alarms and wrongly blocked payments than about recall.
- Report $ and escalation load in finance units (loaded cost per human touch), not only F1.

---

## Evidence table

| Claim | URL | Date |
|---|---|---|
| ACFE 2026: 2,402 cases, billing 21% / $90k, check tampering 10% / $114k, controls effectiveness, detection | https://www.acfe.com/-/media/files/acfe/pdfs/rttn/2026/2026-report-to-the-nations.pdf (read in full text) | 2026 (14th ed.; cases Jan 2024 - Sep 2025) |
| ACFE 2026 secondary summaries (overall figures) | https://www.pbmares.com/key-findings-from-the-2026-acfe-report-to-the-nations/ | 2026 |
| AFP 2026: 76% fraud, BEC 74%, sources table, recovery, n=465 | https://www.truist.com/content/dam/truist-bank/us/en/documents/info/cci/2026-afp-payments-fraud-control-survey-report-key-highlights.pdf | April 2026 |
| AFP 2026 press release | https://www.financialprofessionals.org/about/learn-more/press-releases/Details/over-75-percent-of-us-firms-experienced-payments-fraud-in-2025-while-ai-adoption-for-fraud-mitigation-lags | 2026-04-14 |
| FBI IC3 2025 BEC $3.05B, 24,768 complaints (secondary) | https://www.mcdonaldhopkins.com/insights/news/the-sobering-truth-of-the-fbis-2025-internet-crime-complaint-center-report ; https://www.insurancebusinessmag.com/us/news/cyber/business-email-fraud-drives-bulk-of-us-cybercrime-losses-analysis-590687.aspx | April 2026 |
| APQC 2024 duplicate/erroneous 0.8/1.5/2.0% | https://www.corpay.com/en-NZ/resources/blog/duplicate-payment | post updated 2026-07-09 (APQC data 2024) |
| Berkeley duplicate payments 0.03%, 0.1-2% cited | https://berkeleyca.gov/sites/default/files/2022-01/2010-02-09_Item_10_Audit_Over__38_000_in_Duplicate_and_Over_Payments_Recovered.pdf (text not extractable; via search summary) | 2010-02-09 |
| Coventry recovery audit 0.01% | https://edemocracy.coventry.gov.uk/documents/s36157/Account Payable Recovery Audit 2016-2017.pdf (search summary only) | 2016-17 |
| Stampli / AccountingWeb duplicate ranges | https://www.stampli.com/resources/duplicate-anomaly-detection-analytics/ ; https://www.accountingweb.co.uk/node/224412 (search summary only) | undated |
| SAP tolerance keys, OMR6, blocking | https://learning.sap.com/courses/invoice-verification-in-sap-s-4hana/entering-invoices-with-variances-1 ; https://blogs.sap.com/?p=105339 (search summaries) | undated |
| NetSuite tolerance/difference fields | https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4168980481.html (read) | current help |
| Oracle Fusion Invoice Tolerances | https://docs.oracle.com/en/cloud/saas/financials/26b/fappp/invoice-tolerances.html (search summary) | release 26B |
| NetSuite tolerances: no universal threshold; APQC 85% PO-matched | https://www.houseblend.io/articles/netsuite-three-way-match-tolerances-exceptions | 2026-10-01 |
| Practitioner price 2-5% / qty 3-10% ranges | https://www.tacto.ai/en/procurement-glossary/three-way-match ; https://ramp.com/blog/accounts-payable/2-way-match ; https://www.kognitos.com/glossary/what-is-invoice-matching/ (search summaries) | 2025-2026 |
| BPIC 2019 description, license CC BY 4.0, 728,558,522 bytes, 251,734 items | https://data.4tu.nl/articles/dataset/BPI_Challenge_2019/12715853 (via Internet Archive snapshot) | published 2019-01-31; snapshot 2025-04-19 |
| BPIC 2019 OCEL, CC BY 4.0, 2023 | https://data.4tu.nl/datasets/46a7e15b-10c7-4ab2-988d-ee67d8ea515a (search result; direct fetch refused) | 2023 |
| ERP-RiskBench | https://arxiv.org/abs/2603.06671 | March 2026 |
| FinBalance | https://arxiv.org/abs/2606.15949 ; https://github.com/Devansh1105/finbalance | June 2026 |
| AP Commander RL env | https://pathikreet-ap-clerk-env.hf.space/ | undated |
| UK spend over GBP 25k, OGL | https://ckan.publishing.service.gov.uk (listings) | rolling |
| NYC Checkbook license not specified; code AGPL-3.0 | https://catalog-old.data.gov/dataset/checkbook-nyc-2-0 | undated |
| Stripe test mode needs account | https://docs.stripe.com/invoicing/testing | current docs |
| Agent-control criticisms | https://www.pymnts.com/?p=4281234 ; https://savantlabs.io/blog/finance-ai-audit-readiness/ ; https://www.eftsure.com/blog/industry-news/can-your-ai-agents-be-manipulated-into-sending-money-to-the-wrong-place/ ; https://ramp.com/blog/agentic-payments | 2026 (Ramp 2026-04-14) |

## Open items / not verified

- AFP full-report numbers on vendor-impersonation share and callback-verification effectiveness (paywalled).
- Whether OCEL BPIC19 zip is about 68 MB (from one search summary).
- BPIC 2019 activity names (from memory, verify after download).
- BPIC 2019 and OCEL not downloaded: `data.4tu.nl` unreachable from this machine; XES is also over 500 MB. Suggested command from a working network: `curl -L -o data/raw/bpic2019/BPI_Challenge_2019.xes "https://data.4tu.nl/ndownloader/items/35ed7122-966a-484e-a0e1-749b64e3366d/versions/1"` (confirm that endpoint returns the XES, not a zip), or fetch the OCEL zip from the OCEL landing page.
- Berkeley/Coventry/WA State duplicate-rate figures come from search summaries; PDFs were not text-extractable here.
