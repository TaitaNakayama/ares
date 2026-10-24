# 06 - Backend, agents, ledger, network (Ares)

Researched 2026-10-23. Everything marked **[V]** was verified against a live source today. **[M]** is from model memory or a single forum report and must be spiked before you rely on it. **[L]** was checked locally on this Mac.

## TL;DR decision table

| Area | Choice | Exact version (checked 2026-10-23) | Why | Rejected alternative | Risk | Sources (date) |
|---|---|---|---|---|---|---|
| Ledger | Own minimal double-entry ledger in TypeScript, on `node:sqlite`, append-only, integer minor units, hash-chained rows | `node:sqlite` in Node 26.10.0 [L] (SQLite 3.53.4 [L]) | 0 setup, fully deterministic, a `source_refs` JSON column on every entry, trivial to replay seeds, and a balanced-entries invariant that is property-testable | TigerBeetle, Formance v3, Blnk, Beancount+Fava (details in section 1) | You own the bugs. Mitigation: fast-check invariants and about 150 lines of core code | Node docs v26.12.1 (2026-10); npm registry (2026-10-23) |
| LLM SDK | `@anthropic-ai/sdk` | **1.3.0** [V] (`latest` tag on npm; 1.3.1 also appeared in a later `npm view` call, so run `pnpm add @anthropic-ai/sdk@latest`) | Official, typed, has a tool runner and streaming | Raw `fetch` | The SDK is at 1.x, so older 0.x snippets from your memory may be wrong | registry.npmjs.org (2026-10-23) |
| Models | Sonnet 5.5 for judgment agents, Haiku 5.5 for high-volume routine agents. No Opus in the hot path | `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5` [V] | Cheap, 1M context, 512-token minimum cacheable prefix | Opus 5.5 ($4/$20) and Fable 5.1 ($10/$50): too slow and too costly for hundreds of seeded scenarios | `temperature` is now rejected (see 2.6). Thinking cannot be fully disabled on Opus 5.5 or Sonnet 5.5 | platform.claude.com models overview (2026-10-23) |
| Tool use | `tool_choice: auto` plus `strict: true` plus a per-role tool list plus an explicit `no_action` tool | n/a | Forced `tool_choice` (`any` or `tool`) returns **400** on Opus 5.5, Sonnet 5.5 and Fable 5.1 [V] | Forced tool choice | Model may answer in prose instead of calling a tool. Handle it as `no_action` plus a retry | platform.claude.com define-tools (2026-10-23) |
| WS client (Unity) | `endel/NativeWebSocket` | 2.0.7, released 2026-08-07 [V], Apache-2.0 | Maintained, supports iOS, small | websocket-sharp, Best HTTP, raw `ClientWebSocket` as primary | No Unity 6 + IL2CPP + iOS 26 report found either way. **Spike on the phone first** | GitHub API (2026-10-23) |
| WS server | `ws` | 8.22.0 [V] | Smallest, no framework tax | Socket.IO 4.8.4, `@fastify/websocket` 11.3.4 | Hand-rolled reconnect (fine, the protocol below handles it) | npm (2026-10-23) |
| HTTP framework | Fastify | 5.12.7 [V] | You know Node; schema-first, has a `ws` integration | Hono 4.13.13 | None significant | npm (2026-10-23) |
| Validation | zod | 4.6.7 [V] | One schema gives you tool JSON schema (via `z.toJSONSchema`), WS messages and policy config | Hand-written JSON Schema | None | npm (2026-10-23) |
| Tests | vitest + fast-check | vitest 5.0.5, fast-check 4.10.2 [V] | TS-native, watch mode | node:test | vitest 5 is new, so pin it | npm (2026-10-23) |
| Venue network | Mac-hosted Wi-Fi is NOT available, so use the iPhone hotspot as primary and bundled offline replay as the fallback. Manual IP entry plus QR code. No Bonjour. | n/a | Hotspot avoids client isolation. Direct IP avoids the Bonjour plist and entitlement rabbit hole | Bonjour/mDNS discovery | Local Network prompt behavior is under-documented. Test on the actual phone | see section 4 |

---

## 1. Ledger

### What I could and could not verify

| Option | Setup on macOS arm64 | Determinism for seed replay | Metadata per entry | On screen | Verdict |
|---|---|---|---|---|---|
| **Own TS ledger + SQLite** | `import { DatabaseSync } from 'node:sqlite'`; nothing to install [L] | Total: you control IDs and clock | Any JSON column | You render it however you like | **Pick** |
| **TigerBeetle** (`tigerbeetle-node` 0.17.9, npm modified 2026-07-06 [V]) | Need the server binary, format a data file, run a replica, then the native client. Package `@tigerbeetle/client` does not exist on npm [V] | Cluster assigns timestamps, so replay is not byte-identical unless you ignore timestamps | Only fixed-width `user_data_128/64/32` integer fields. Source refs need a side table anyway | Nothing, no UI | Reject. Overkill: its strengths (throughput, strict consistency) do not matter here |
| **Formance Ledger** (main branch is "v3 Raft cluster") | README says it needs Go 1.27+, Just, Nix with Flakes, and `just run`; I found no release or tag page [V]. Docker route not confirmed | Single Raft group, probably deterministic but you cannot control the clock | Not confirmed on the README (Numscript, idempotency keys, bulk ops are listed) | Has an HTTP API and a console, none verified | Reject: Nix + Go toolchain is 3am risk |
| **Blnk** | Apache-2.0; repo has docker-compose, so likely Postgres and other services. Redis/Typesense not confirmed [V partial] | Server-side clock | `metadata.go` exists, so metadata is supported | API only | Reject: Docker stack on flaky Wi-Fi |
| **Beancount 3.2.3 + Fava 1.30.16** (PyPI, 2026-05-05 and 2026-08-18 [V]; Python >=3.9 / >=3.10, so 3.14.7 here is fine) | `pip install` in a venv; Fava serves on :5000 | A text file is perfectly replayable | Native: key-value metadata on every posting and transaction | Fava is a polished, ready-made ledger/audit UI | Best "looks real" option, but the Python bridge costs time |

### Recommendation

Write the ledger yourself. Design for the audit trail:

- Tables: `journal_entry(id, seq, ts_sim, request_id, receipt_id, invoice_id, rule_id, approver, memo, prev_hash, hash)` and `posting(entry_id, account, amount_minor INTEGER, currency, direction)`. Deferrable invariant: sum(debits) = sum(credits) per entry, checked in code before `INSERT` inside one transaction. Also add `CHECK(amount_minor > 0)`.
- Entries are append-only (no UPDATE/DELETE statements anywhere; corrections are reversing entries). Hash chain gives tamper evidence and a nice demo line.
- Use a simulated clock and sequence-derived IDs (`je_000042`), never `Date.now()` or random UUIDs in the ledger. That is what makes seeded replay byte-identical.
- Money as integer minor units. No floats anywhere in the path.
- **Cheap bonus:** write an exporter that emits a `.beancount` file from the SQLite ledger. Then `bean-check` independently validates balance, and Fava can show it as the "auditor's view" if time remains. This is stretch, not the plan.

Node caveat [L]: the installed Node 26.10.0 exports `DatabaseSync` only. The 26.12.1 docs say `Database` is the new name and `DatabaseSync` is a deprecated alias (DEP0210). Use `DatabaseSync` and it works on both. `node:sqlite` is "Stability 1.2 release candidate", no flag needed [V].

---

## 2. Claude API tool use for the five agents

### 2.1 Package, models, versions [V]
- Package: `@anthropic-ai/sdk`, **1.3.0** via the npm `latest` endpoint (a later `npm view` showed 1.3.1). Apache-2.0, repo `anthropics/anthropic-sdk-typescript`.
- Model IDs confirmed on the models overview page (2026-10-23). The IDs are complete as written, with no date suffix:

| Model | ID | $/MTok in / out | Notes |
|---|---|---|---|
| Fable 5.1 | `claude-fable-5-1` | 10 / 50 | thinking always on |
| Opus 5.5 | `claude-opus-5-5` | 4 / 20 | default effort `medium`, thinking cannot be disabled |
| Sonnet 5.5 | `claude-sonnet-5-5` | 2 / 10 | default effort `high` |
| Haiku 5.5 | `claude-haiku-5-5` | 0.10 / 0.50 (up to 100K prompt) | default effort `medium` |

All have 1M context and 128K max output. Your guess of `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5` is correct.

### 2.2 Request format
Standard Messages API: `tools: [{ name, description, input_schema, strict?, cache_control? }]`; the response contains `tool_use` blocks `{type, id, name, input}`; you reply in a single user message with `tool_result` blocks `{type:'tool_result', tool_use_id, content, is_error?}`. Tool name regex is `^[a-zA-Z0-9_-]{1,128}$` [V]. Descriptions are the biggest quality lever per Anthropic; `input_examples` are optional and schema-validated [V].

### 2.3 `tool_choice`
- Options are `auto`, `any`, `tool`, `none` [V].
- **On Opus 5.5, Sonnet 5.5 and Fable 5.1, `any` and `tool` return a 400** [V]. Use `auto` plus `strict: true` plus a prompt instruction ("respond only by calling exactly one tool"). Changing `tool_choice` between calls also invalidates the cached messages portion [V].
- Haiku 5.5 is not in the restricted list on the page I read, so forced tool use probably works there, but the same page says a forced call skips thinking. I did not test it. Do not build on it.
- Strict tool use: set `strict: true` on the tool, with `additionalProperties: false` and `required` listed [M, from the skill reference; the strict-tool-use page itself was not fetched]. This guarantees the input validates against your schema, but you still run zod server-side.

### 2.4 Thinking and sampling (things that will bite)
- Opus 5.5: `thinking: {type:'disabled'}` returns 400 at every effort level. Sonnet 5.5: `disabled` is a 400; use `{type:'between_tools'}` (effort `high` or below) or just set `output_config: {effort:'low'}`. [V from models page; detail from the skill reference [M]]
- **`temperature`, `top_p` and `top_k`: per the skill reference, a Messages request that sends any of them returns 400 on every model from 2026-10-21 [M, not confirmed on docs.]** I did not fetch the API-version migration page. Check once with a real call, and do not rely on `temperature: 0` for determinism. This is why the response cache below matters.
- Extended-thinking `budget_tokens` is rejected on these models [V].

### 2.5 Prompt caching [V]
- Minimum cacheable prefix is 512 tokens on Opus 5.5, Sonnet 5.5, Haiku 5.5. Default TTL 5 minutes; `ttl: '1h'` costs 2x to write.
- Cache read: 0.05x on Opus/Sonnet 5.5 ($0.10/MTok on Sonnet 5.5), 0.1x on Haiku 5.5. 5-minute write is 1.25x.
- Order is tools, then system, then messages. Put per-role tools + role prompt + policy summary first, mark the last stable block with `cache_control: {type:'ephemeral'}`, and keep timestamps and scenario data after it. Verify `usage.cache_read_input_tokens > 0`.
- Cached reads do not count toward ITPM.

### 2.6 Latency, cost, rate limits
- **Latency: I have no measured numbers.** The docs only rank latency (Haiku fastest, Sonnet fast, Opus moderate, Fable slower). Measure p50/p95 in your first spike with `effort: 'low'`. Budget on the order of 1 to 5 s per Sonnet call until measured [M].
- Cost estimate [calc, not measured]: a call with 3K input (cached 2K) and 300 output tokens on Sonnet 5.5 is about $0.0003 + $0.003 = about $0.004. Hundreds of scenarios with ~10 calls each is on the order of $10 to $40 uncached; Haiku 5.5 is ~20x cheaper. Use batch (50% off) for the eval harness if latency does not matter.
- Rate limits [V, platform.claude.com/docs/en/api/rate-limits, 2026-10-23]. The page now uses tiers named Start/Build/Scale (not Tier 1-4):
  - Start: 1,000 RPM; Sonnet 5.5, Opus 5.5 and Haiku 5.5 each 2M ITPM / 400K OTPM; Fable 5.x 500K ITPM / 100K OTPM. Monthly spend cap $500.
  - **New organizations may begin in an "Evaluation" tier with limits below these**, rising automatically with usage history. So a brand-new key may be tighter than the table; check `platform.claude.com/usage/limits` before the event.
  - 429 from sharp usage ramps ("acceleration limits") is possible: ramp the eval harness gradually, honor `retry-after`. The spend-cap 429 has no `retry-after` and retries will not help.
  - Data retention: Fable 5.1 requires 30-day retention [M, skill ref]; irrelevant if you stay on Sonnet/Haiku.
- Refusals: the models can return `stop_reason: 'refusal'` with HTTP 200 [M, skill ref]. Treat as `no_action` and escalate. A tool parameter that asks for the model's "reasoning" can trigger a `reasoning_extraction` refusal [V]; name the field `rationale_short` or `evidence` and keep it brief.

### 2.7 Design pattern: least-privilege tools plus server checks

```
role -> allowedTools (static map)         // Requester: create_request; Receiver: record_receipt;
                                          // AP: submit_match_result; Treasury: propose_payment;
                                          // Controller: approve/block/escalate
every agent also gets: no_action(reason), ask_clarification(...)   // never need free text
```

1. **Layer 1 (schema/tool surface):** each agent's API call includes only its role's tools, with `tool_choice: auto`, `strict: true`. The model cannot even see `execute_payment`.
2. **Layer 2 (server):** the orchestrator takes `(agentId, toolName, input)`, then (a) checks `toolName in ROLE_TOOLS[agentId]`, (b) `zod.parse(input)`, (c) runs the policy engine (limits, SoD: requester != approver != payer, three-way-match tolerance, bank-change hold, materiality, runway), (d) only then calls the ledger. LLM output is never executed directly. Violations are logged as `rejected_proposal` events (great demo material and eval signal).
3. **Layer 3 (ledger):** invariants that cannot be bypassed, such as balanced entries and no payment without an approved match id.
4. Do not give the LLM any tool that performs statistics. Price anomaly z-scores/MAD are computed in code and passed in as facts.
5. Treat all tool results and document text (invoices) as untrusted data; they can contain injected instructions, which is a realistic AP attack to demo.

### 2.8 Offline proposer and replay cache
- `Proposer` interface: `propose(agentId, observation, ctx) -> Proposal[]`. Implementations: `ClaudeProposer`, `RuleProposer` (deterministic, seeded), `CachedProposer`.
- Cache key: `sha256(model + promptVersion + agentId + canonicalJSON(observation) + seed + eventIndex)`; store the raw `tool_use` blocks as JSONL in `data/llm-cache/`. Modes: `live` (call + write), `replay` (read only; miss = hard fail), `offline` (miss = fall back to `RuleProposer`). The default for demos is `replay`.
- Record one golden run per demo scenario before the event ends, commit the cache. Because `temperature` can't be pinned, treat the cache as the only source of reproducibility.
- Auto-fallback: no `ANTHROPIC_API_KEY`, a 5xx, or a timeout over ~8 s leads to `RuleProposer` and a visible "offline proposer" badge in the UI, so judges are not misled.

---

## 3. Real-time link to Unity (iOS)

### Client library
| Option | Evidence | Verdict |
|---|---|---|
| **endel/NativeWebSocket** | Latest release 2.0.7 on 2026-08-07; repo pushed that same day; 1,735 stars; 57 open issues (API count) [V]. README says iOS supported and Unity 2019.1+; 2.x dispatches callbacks through `SynchronizationContext` (no `DispatchMessageQueue()` call needed in Unity) [V]. Open issues seen are about freezes after long idle or network loss (#102, #89, #82), none labelled iOS/IL2CPP by title [V]; issue #107 (UPM compat, 2026-05-11). Install via UPM git URL `https://github.com/endel/NativeWebSocket.git#upm-2` [V] | **Primary** |
| `System.Net.WebSockets.ClientWebSocket` | A search found a library (RxWebSocket) that wraps it and lists IL2CPP on iOS as working [secondhand, date unknown]. I found no Unity 6 evidence. Do not import the .NET Core `System.Net.WebSockets.dll`; use the one in Unity's own profile [V, Unity tracker note] | **Fallback** if NativeWebSocket misbehaves. About 80 lines to wrap |
| websocket-sharp (sta) | Repo pushed 2026-10-11, 6,080 stars, 559 open issues, no release published [V]. This is the code NativeWebSocket's native path builds on in some forks. I found no direct IL2CPP/iOS evidence either way | Not as a direct dependency |
| Best HTTP | Paid; not evaluated | Reject |

Honest status: **I found no source confirming any of these on Unity 6 + IL2CPP + iOS 26.** The IL2CPP risk is mostly code stripping and AOT. In Player Settings use Managed Stripping Level Low (or add `link.xml`) and test a **Release IL2CPP build on the phone in the first 3 hours.** Spike script: connect, send ping, receive 1,000 messages, background the app, resume, and verify it reconnects.

### Server library
`ws` 8.22.0 on a Fastify 5.12.7 HTTP server (shared port via `server.on('upgrade')` or `@fastify/websocket` 11.3.4). Socket.IO adds its own protocol, which Unity needs an extra client for; reject it. Hono's WS support is thinner on Node. Node 26 also has a global `WebSocket` client [L], handy for headless test clients.

### Message schema (snapshot + incremental, sequenced)
All messages are JSON, validated with zod, with `v: 1`.

```
Server -> client
 { t:'hello',    v:1, serverId, runId, seq: 1042 }                       // after connect
 { t:'snapshot', runId, seq: 1042, state: {...full derived state...} }
 { t:'event',    runId, seq: 1043, simTime, kind:'ledger.posted'|'request.created'|'escalation.opened'|
                  'proposal.rejected'|..., payload:{...}, refs:{requestId,receiptId,invoiceId,ruleId,approver} }
 { t:'ack',      clientMsgId, ok, error? }
 { t:'pong' }
Client -> server
 { t:'hello',    clientId, device:'unity-ios'|'react', lastSeq: 1040 }   // resume
 { t:'cmd',      clientMsgId, type:'approve'|'reject'|'inject_scenario'|..., payload }
 { t:'ping' }
```
- Single global monotonically increasing `seq` assigned only by the server's event log (the same log that feeds the ledger and audit trail).
- On connect with `lastSeq`: if the gap is small (say <= 500 events) and still in the in-memory ring buffer, replay events `lastSeq+1..`; else send a `snapshot` then live events. If the client sees a gap in `seq`, it sends `resync` and gets a snapshot. If `runId` changes, the client discards local state.
- Idempotent commands via `clientMsgId` (the two clients may both click Approve; the second gets a `stale`/`already_decided` ack).
- Heartbeat: client ping every 5 s, server closes if no frame in 15 s; client reconnects with 0.5 s to 5 s capped backoff. Unity's side must do this itself; do not trust TCP to notice a dead Wi-Fi.
- Keep Unity's JSON parsing simple: `JsonUtility` does not handle polymorphic payloads; use Newtonsoft (`com.unity.nuget.newtonsoft-json`) or flatten the payload to a fixed shape per `kind`. Put the schema as one `.ts` file and generate C# DTOs by hand.

---

## 4. Venue network

### What I verified vs. not
- **ATS and cleartext `ws://`:** Apple forum threads say that since iOS 10, ATS does not apply to connections made to IP address literals; `NSAllowsLocalNetworking` covers unqualified/`.local` hostnames [V via forum threads, 2016-era, not re-tested for WebSocket on iOS 26]. Unity's `UnityWebRequest` honors ATS settings but Unity may add an `NSAllowsArbitraryLoads` default depending on the "Allow downloads over HTTP" Player Setting. For the safe path: set that Player Setting to "Always allowed" for the hackathon build (or add `NSAppTransportSecurity > NSAllowsLocalNetworking = YES`) and use an IP literal in the URL. Test on the device.
- **Local Network privacy:** I could not retrieve the body of Apple's TN3179 (the fetch returned only the title), so the following is **[M] from memory**, consistent with the forum snippets I did see: iOS 14+ shows the prompt when an app connects to a local-network address or uses Bonjour/multicast; the prompt text comes from `NSLocalNetworkUsageDescription`; Bonjour browsing additionally requires `NSBonjourServices`; Apple states there is no public API to check or request this permission. A plain `ws://192.168.x.x` direct connect is expected to trigger the prompt and needs only the usage description, not `NSBonjourServices`.
  - A developer reported (single forum post, iOS 26.5.2) that direct IP connections still worked after tapping Don't Allow [M, unconfirmed]. Do not depend on that. Tell the app to retry the connection with backoff, and show "Allow Local Network in Settings" guidance on failure.
  - Add the `NSLocalNetworkUsageDescription` key to the Xcode project's Info.plist via a Unity post-build script (`PlistDocument`); Unity does not add it. Without it the prompt may appear with a blank or generic reason, as reported on iOS 18 [V forum].
  - The prompt is attached to the app. If the demo phone already has the app installed with "Don't Allow", reset it by deleting and reinstalling, or toggle Settings > Privacy & Security > Local Network [M].
- **Discovery:** Use manual IP entry plus a QR code that encodes `ws://IP:PORT/?token=...`. The Mac console can show this QR. Scan with the in-app camera, or just type it (store last-used IP). Skip Bonjour: it needs `NSBonjourServices`, a native plugin in Unity (Unity has no built-in mDNS browse), and mDNS is commonly blocked on conference Wi-Fi.
- **Hackathon Wi-Fi client isolation:** common on large events; I have no source for Cal Hacks' venue specifically. Assume it is on. Symptoms: the Mac and phone both have Internet but `ping` between them fails.
- **iPhone Personal Hotspot as the network:**
  - Mac joined to the phone's hotspot gets 172.20.10.x (a /28; the phone is the gateway at 172.20.10.1). **This Mac was on `172.20.10.13` at the time of this research [L].**
  - Open question: can the *same phone's own app* open a TCP connection to a Mac on its own hotspot (i.e. hairpin to a tethered client)? Search results did not answer this directly. It is the single most important thing to test, because if it works, the hotspot is your venue-proof network. Test: from the iPhone Safari (no Local Network prompt needed for Safari testing, but the page load itself counts) open `http://172.20.10.x:PORT/health` while the Mac serves on `0.0.0.0`. If Safari works, the app will too (modulo the permission prompt).
  - If the phone is also the VR viewer, the phone's cellular data is what is used for Claude API calls (the Mac proxies over the hotspot); keep the data plan in mind.
  - The Mac firewall is **disabled** [L] right now, so incoming connections are not blocked. If you enable it, Node needs an allow rule, or you get a silent failure.
  - Server must bind to `0.0.0.0` (not `localhost`), and print every IPv4 address plus QR at start-up.
- **USB networking:** iPhone-to-Mac USB with Internet Sharing needs the Mac to share *to* the iPhone, which is the reverse direction of what is useful; one walkthrough [V, Medium] uses the Mac's "iPhone USB" interface address for the phone to reach the Mac. I could not verify this on iOS 26 and it needs System Settings changes. Treat it as plan C, to try only if the hotspot fails.
- **Fully offline mode (plan D, build it first):** bundle `StreamingAssets/run-<seed>.jsonl` (snapshot + ordered events with `simTime`) in the Unity app, and add a `ReplaySource` that implements the same `IEventSource` interface as the WebSocket client. Same state reducer, same rendering. The React console loads the same file. A visible "REPLAY (offline)" badge keeps this honest, and judges can still see everything on the phone. Because the ledger is deterministic, the bundled log is identical to what a live run would give.

---

## 5. Stack recommendation

| Layer | Pick | Notes |
|---|---|---|
| Runtime | Node 26.10.0 [L], pnpm | TypeScript 7.0.2 is the npm `latest` today [V], but most tooling and `@types/node` (26.6.5 [V]) still assume the JS compiler API. Safe choice: TS `~5.x`/`6.x` if any plugin complains. I did not test TS 7 with vitest |
| Run TS | `tsx` 4.23.15 [V] (or Node's native type stripping) | Native stripping is faster to set up, but enums and path aliases need care; use `tsx` |
| HTTP/WS | Fastify 5.12.7 + `ws` 8.22.0 | Fastify serves the REST/snapshot endpoint and the static React build |
| Validation | zod 4.6.7 | `z.toJSONSchema()` feeds the Anthropic `input_schema` (check that its output passes `strict` rules: no `$ref`, `additionalProperties:false`) |
| SQLite | `node:sqlite` `DatabaseSync` | No native build; sync API is fine for a single-writer ledger. Fallback: `better-sqlite3` 13.0.3 [V] if you hit an RC bug |
| Tests | vitest 5.0.5 | `node:test` is a legitimate fallback |
| Property tests | fast-check 4.10.2 | Properties below |

Properties to write first (these are your credibility with judges):
1. For any generated sequence of proposals, applying them through the engine never produces an unbalanced entry (sum debits = sum credits, per entry and per currency).
2. Trial balance = 0 after any sequence.
3. For every ledger entry, `request_id` and `rule_id` and `approver` are non-null, and any payment entry has a matching approved invoice and receipt (no action without policy).
4. SoD: no entry where requester = approver = payer.
5. Replaying the event log into a fresh DB gives a byte-identical hash chain (determinism).
6. Any proposal outside a role's tool list is rejected with no state change.
7. Bank-detail change always yields `hold` and never `pay`, regardless of amount.

---

## What would make this fail at the venue at 3am?

1. **Client isolation on the venue Wi-Fi.** Both devices have Internet but cannot see each other. Fix: iPhone hotspot with the Mac joined. Pre-test the hairpin (phone app to Mac on its own hotspot) tonight, not Saturday 3am.
2. **Hotspot flakiness.** iOS drops the hotspot after idle or when the Mac sleeps, and the IP can change. Fix: disable Mac sleep (`caffeinate -dimsu`), re-print the QR on every server start, and keep a manual IP field with last-used memory.
3. **Local Network permission denied or never prompted.** The app silently cannot connect. Fix: show an in-app diagnostic screen ("Connecting to 172.20.10.13:8787... Local Network access: check Settings"), and keep the offline replay one tap away.
4. **ATS blocks cleartext `ws://`.** Verify the built IPA (not the editor) connects over `ws://IP`. Fix: Player Setting for HTTP downloads, plus `NSAllowsLocalNetworking`.
5. **IL2CPP stripping or AOT surprises** in the WebSocket or JSON library only show up in Release builds. Fix: do a Release IL2CPP device build on day one, and test after every package change.
6. **Anthropic API unreachable or rate-limited** (venue Wi-Fi, new-org Evaluation tier limits, spend cap, acceleration 429s). Fix: `replay` mode default for demos, `RuleProposer` fallback with a visible badge, and run the eval harness the night before and not during judging.
7. **`temperature` rejected** after 2026-10-21 (if the skill note is right): a 400 from every call. Fix: never send sampling params. Test one real call at the beginning.
8. **Forced `tool_choice` 400** if you copy older examples. Use `auto` and `strict`.
9. **Model produces prose instead of a tool call** or a refusal: treated as `no_action`, retry once, then escalate. Never block the demo on LLM behavior.
10. **Cache invalidation by accident** (a timestamp in the system prompt) tripling cost/latency. Check `cache_read_input_tokens`.
11. **Mac firewall** enabled by an OS update. It is disabled now [L], and any block is silent. Add a `/health` check shown on the console.
12. **Seed drift:** any use of `Date.now()`, `Math.random()`, or object-key ordering in the ledger breaks replay and the bundled offline log. Add property test 5 to CI.
13. **Node `node:sqlite` is a release candidate** and the local Node (26.10.0) differs from the docs (26.12.1): the `Database` class does not exist locally yet. Use `DatabaseSync`; pin the Node version and do not `brew upgrade` during the event.
14. **Unity phone thermals/battery** in the VR viewer: keep the phone cool and the app at a stable frame rate, and bring a charger.
15. **Battery of the Mac on stage:** sleep, Wi-Fi power saving, and Do Not Disturb can interrupt the hotspot link. Plug in.

## Source list (all fetched 2026-10-23 unless noted)
- npm registry: `@anthropic-ai/sdk`, `ws`, `fastify`, `hono`, `zod`, `vitest`, `fast-check`, `better-sqlite3`, `tigerbeetle-node`, `socket.io`, `@fastify/websocket`, `tsx`, `typescript`, `@types/node` (registry modified dates shown in the table above).
- https://platform.claude.com/docs/en/models/overview (model IDs, prices, retirement dates, default effort)
- https://platform.claude.com/docs/en/api/rate-limits (Start/Build/Scale tiers, Evaluation tier note)
- https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools (`tool_choice` restrictions)
- https://platform.claude.com/docs/en/build-with-claude/prompt-caching (512-token minimum, multipliers; only the first 100K characters of the page read)
- https://nodejs.org/docs/latest/api/sqlite.html (v26.12.1 docs; stability 1.2)
- https://github.com/endel/NativeWebSocket and the GitHub API (release 2.0.7, 2026-08-07), https://github.com/sta/websocket-sharp (pushed 2026-10-11)
- https://github.com/formancehq/ledger, https://github.com/blnkfinance/blnk, https://github.com/beancount/fava, PyPI JSON for beancount and fava
- Apple forum threads on ATS and IP literals (https://developer.apple.com/forums/thread/70520, /thread/66417, 2016-era) and on Local Network privacy (https://developer.apple.com/forums/thread/826268, /thread/776771, /thread/761927)
- The Anthropic API reference bundled with the Claude Code `claude-api` skill (cached 2026-10-06), used for strict tool use, the temperature removal, refusals and fallbacks. **These items are marked [M] because I did not confirm them on the live docs.**
- Not retrieved: Apple TN3179 body (fetch failed), the tigerbeetle-node README, the Anthropic `strict-tool-use` and `refusals` pages.
