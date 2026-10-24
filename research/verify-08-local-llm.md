# verify-08: C-16 local LLM (adversarial review)

Reviewed 2026-10-24, 05:20 PT. Machine: **Mac15,13 = fanless MacBook Air 15" M3**, 24 GB, on battery. Ollama 0.40.10 serves qwen3.5:9b on its **MLX runner (nvfp4, speculative decoding)**.

**Verdict: FAILS as evidenced today**; it can become HOLDS WITH CAVEATS if the section 5 checks pass. Rules keep the demo alive.

## 1. Evidence
- **Biggest hole: "valid" was checked with zod, not with the policy.** Every treasury call sent both `invoiceId` and an invented `poId` ("V-kepler", "PO-1"): 24/24 in the 3-model run and 15/15 in the 15-rep run. engine.ts:841 denies that ("give exactly one of invoiceId or poId"), yet the judge scored those calls "good". **Real treasury acceptance for qwen3.5 is 0/21.** It also breached the reserve in 2 of 15 runs.
- **The medians are cache hits.** The reps resend an identical prompt, so the server reuses it (`matched=1078 left=5`). Only first calls look like production: qwen3.5 took 12.5, 16.8 and 8.8 s; llama3.1 took 5.9, 8.2 and 5.2 s.
- **The real n is tiny.** At temperature 0.3 the outputs repeat. The controller gave 1 distinct output in 15 runs, so the runs cover 4 situations, not 84 samples.
- **Untested:** randomized state, agent interleaving, `Engine.submit`, render load. Any `escalate` counts as good.

## 2. Memory
- The model holds 8.3 GiB and grows to **9.4 GiB held (9.9 GiB peak)** as prefixes cache. The Metal budget is 17.8 GiB. It should fit, **but** swap already shows 1.76 GB used and the compressor about 5.9 GB, with Chrome, ffmpeg and Claude open. Close them.
- Two runners were loaded at once earlier: set `OLLAMA_MAX_LOADED_MODELS=1`. The flash-attention/KV env vars live only in the launching shell.

## 3. Latency under load
- **Requests are served one at a time.** The MLX runner ignores `OLLAMA_NUM_PARALLEL` (ollama#17280, 2026-07-21; the fix, PR #17317, was still unmerged on 2026-08-14).
- **My two new-state probes** (pessimistic: 60-call run, ffmpeg at 280% CPU, battery) took **17.8 s and 16.5 s wall**: about 8 s queued, 6.8 s reading 867 prompt tokens, 3.2 s generating 55. Prompt reading (mostly tool schemas) dominates a cache miss; the second probe reused 467 cached prefix tokens.
- **Heat.** Max Tech's sustained tests (Wccftech, Gigazine, March 2024): M3 Air GPU fell to ~7 W vs 16 W in the Pro, ~25% lower score. C-14 soaked the phone, not this Mac. Spectator fps during inference (GPU at 93%) is unmeasured; SceneKit/MLX GPU sharing is unverified.

## 4. think:false, versions, cold start
- **think:false holds single-turn.** Thinking defaults to **true** (`ollama show`); every call here returned no thinking text. A path that drops `think` (e.g. `/v1`) turns it back on.
- **One fresh conversation per decision:** multi-turn tool replies risk the `</think>` renderer bug (ollama#14493, reported still open).
- **Keep the model loaded.** The spike's `keep_alive "10m"` will unload it between judges, costing a 7-17 s cold start. Use `-1`, plus one warm-up call per agent prompt at boot.

## 5. Thresholds and checks
- One LLM call in flight at a time. Other agents use rules immediately.
- Deadlines: 8 s wall for an action, 15 s for the free-text report. On a miss, fall back to rules.
- `num_predict` 160. Put the stable prefix first and the state last.
- Breaker: 2 timeouts or denials in the last 4 calls switches to rules for 60 s.
- Keep the JSON-string repair (llama: 7 of 24).

The three cheapest checks:
1. Replay the saved outputs through `Engine.submit` (no GPU needed), then fix the invented `poId`.
2. 20 calls with randomized state across 5 agents, spectator full screen, on battery. Measure p95 wall time and fps.
3. A 10-minute autoplay soak. Measure fallbacks, fps, `pmset -g therm` and swap growth.

## 6. Fallbacks, ranked
1. **(c) Narrow local.** The LLM runs one or two showcase agents (for example the free-text report) and rules run the rest. Nothing queues.
2. **(a) Cloud when online.** C-13 is BLOCKED: there is no key, and a key costs money. Time it on the hotspot.
3. **(b) Rules only.** The floor, wired in regardless.

A replayed tape must be labeled REPLAY.

Sources: github.com/ollama/ollama #17280 #17317 #14493; popularai.org/p/ollama-num-parallel-mac-mlx (2026-08-17); wccftech.com/m3-macbook-air-severely-throttles-under-load.
