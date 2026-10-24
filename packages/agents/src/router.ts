import { CachedProvider, type LlmProvider, type LlmRequest, type LlmResponse } from "./llm.ts";

/**
 * Three model layers, so an agent decision never fully fails:
 *   local  (Ollama on this machine, works offline)  -> default
 *   cloud  (OpenAI, when a key is set and we are online) -> harder, free-form reasoning
 *   rules  (the deterministic brains)               -> last resort on timeout, error or a failed check
 * The router only picks a model and enforces timeouts. When it throws, the calling brain falls
 * back to its rules brain; it never guesses.
 */

export type AgentMode = "auto" | "local" | "cloud" | "rules";

export interface RouteOptions {
  /** Which layer to try first in `auto` mode. Default ARES_PREFER (cloud: measured 2-8 s live; local needs a warm prompt prefix to answer in time). */
  prefer?: "local" | "cloud";
  /** Restrict the call to one layer (used by warm-ups). */
  only?: "local" | "cloud";
  /** Per-call deadline for the local model. Default 12 s (ARES_LOCAL_TIMEOUT_MS). */
  localTimeoutMs?: number;
  /** Per-call deadline for the cloud model. Default 15 s. */
  cloudTimeoutMs?: number;
}

export interface LayerStats {
  calls: number;
  ok: number;
  errors: number;
  timeouts: number;
  msTotal: number;
  lastError?: string;
  lastMs?: number;
}

const stat = (): LayerStats => ({ calls: 0, ok: 0, errors: 0, timeouts: 0, msTotal: 0 });

export class RouterUnavailable extends Error {}

/** Default local deadline. The reviewer's 8 s holds for a warm prompt prefix; a cold ~900-token prompt needs ~7 s just to be read on this Mac. */
export const LOCAL_TIMEOUT_MS = Number(process.env.ARES_LOCAL_TIMEOUT_MS ?? 8_000);
/** Layer tried first in auto mode. */
export const PREFER: "local" | "cloud" = process.env.ARES_PREFER === "local" ? "local" : "cloud";

export class ModelRouter implements LlmProvider {
  mode: AgentMode = "auto";
  readonly name = "router";
  /** The model a caller would get first in the current mode (for labels). */
  get model(): string {
    const first = this.order()[0];
    return first === "local" ? this.local!.model : first === "cloud" ? this.cloud!.model : "rules";
  }
  readonly local?: LlmProvider;
  readonly cloud?: LlmProvider;
  readonly stats = { local: stat(), cloud: stat(), rulesFallbacks: 0 };
  private cloudDownUntil = 0;

  constructor(local?: LlmProvider, cloud?: LlmProvider, cacheDir?: string) {
    this.local = local && cacheDir ? new CachedProvider(local, cacheDir) : local;
    this.cloud = cloud && cacheDir ? new CachedProvider(cloud, cacheDir) : cloud;
  }

  /** What the console shows. */
  status(): { mode: AgentMode; local?: string; cloud?: string; cloudOnline: boolean; stats: ModelRouter["stats"] } {
    return { mode: this.mode, local: this.local?.model, cloud: this.cloud?.model, cloudOnline: !!this.cloud && Date.now() >= this.cloudDownUntil, stats: this.stats };
  }

  /** The layers to try, in order, for this call. Empty means "use the rules". */
  order(opts: RouteOptions = {}): ("local" | "cloud")[] {
    const cloudOk = !!this.cloud && Date.now() >= this.cloudDownUntil;
    switch (this.mode) {
      case "rules":
        return [];
      case "local":
        return this.local && opts.only !== "cloud" ? ["local"] : [];
      case "cloud":
        return cloudOk && opts.only !== "local" ? ["cloud"] : [];
      case "auto": {
        const prefer = opts.prefer ?? PREFER;
        const seq: ("local" | "cloud")[] = prefer === "cloud" ? ["cloud", "local"] : ["local", "cloud"];
        return seq.filter((l) => (l === "local" ? !!this.local : cloudOk)).filter((l) => !opts.only || l === opts.only);
      }
    }
  }

  async complete(req: LlmRequest, opts: RouteOptions = {}): Promise<LlmResponse & { layer: "local" | "cloud"; ms: number }> {
    const layers = this.order(opts);
    if (!layers.length) throw new RouterUnavailable(`no model layer available (mode ${this.mode})`);
    let lastErr: Error | undefined;
    for (const layer of layers) {
      const provider = layer === "local" ? this.local! : this.cloud!;
      const timeoutMs = layer === "local" ? (opts.localTimeoutMs ?? LOCAL_TIMEOUT_MS) : (opts.cloudTimeoutMs ?? 15_000);
      const s = this.stats[layer];
      const t0 = performance.now();
      s.calls++;
      try {
        const res = await withTimeout(provider.complete(req), timeoutMs, `${layer} model timed out after ${timeoutMs} ms`);
        const ms = performance.now() - t0;
        s.ok++;
        s.msTotal += ms;
        s.lastMs = ms;
        return { ...res, layer, ms };
      } catch (err) {
        const e = err as Error;
        lastErr = e;
        s.errors++;
        s.lastError = e.message;
        s.lastMs = performance.now() - t0;
        if (/timed out/.test(e.message)) s.timeouts++;
        // A network failure on the cloud layer means we are probably offline: stop asking for a minute.
        if (layer === "cloud" && /fetch failed|ENOTFOUND|ECONNRESET|EAI_AGAIN|network/i.test(e.message)) this.cloudDownUntil = Date.now() + 60_000;
      }
    }
    throw lastErr ?? new RouterUnavailable("no model answered");
  }
}

function withTimeout<T>(p: Promise<T>, ms: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(message)), ms);
    p.then((v) => { clearTimeout(t); resolve(v); }, (e) => { clearTimeout(t); reject(e); });
  });
}

// ---------------------------------------------------------------- Ollama (local)

/** Small models sometimes return a nested array/object as a JSON string; parse those. */
function repairArgs(args: unknown): unknown {
  if (typeof args === "string") {
    try { return repairArgs(JSON.parse(args)); } catch { return {}; }
  }
  if (!args || typeof args !== "object" || Array.isArray(args)) return args;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(args as Record<string, unknown>)) {
    if (typeof v === "string" && /^\s*[[{]/.test(v)) {
      try { out[k] = JSON.parse(v); continue; } catch { /* keep the string */ }
    }
    out[k] = v;
  }
  return out;
}

/** Ollama's native /api/chat with tools. Thinking is off; the context window is capped to keep memory and latency predictable. */
export class OllamaProvider implements LlmProvider {
  readonly name = "ollama";
  readonly model: string;
  readonly host: string;
  private readonly timeoutMs: number;

  constructor(model = process.env.ARES_LOCAL_MODEL ?? "qwen3.5:9b", host = process.env.OLLAMA_HOST ?? "http://127.0.0.1:11434", timeoutMs = 60_000) {
    this.model = model;
    this.host = host.replace(/\/$/, "");
    this.timeoutMs = timeoutMs;
  }

  /** Is the server up and is the model pulled? */
  async available(): Promise<{ up: boolean; hasModel: boolean; version?: string }> {
    try {
      const v = (await (await fetch(`${this.host}/api/version`, { signal: AbortSignal.timeout(1500) })).json()) as { version?: string };
      const tags = (await (await fetch(`${this.host}/api/tags`, { signal: AbortSignal.timeout(1500) })).json()) as { models?: { name: string }[] };
      const hasModel = (tags.models ?? []).some((m) => m.name === this.model || m.name === `${this.model}:latest`);
      return { up: true, hasModel, version: v.version };
    } catch {
      return { up: false, hasModel: false };
    }
  }

  /** Load the model into memory so the first real decision isn't a cold start (6-20 s). */
  async prewarm(keepAlive = "60m"): Promise<void> {
    await fetch(`${this.host}/api/chat`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ model: this.model, messages: [], keep_alive: keepAlive }), signal: AbortSignal.timeout(60_000) });
  }

  async complete(req: LlmRequest): Promise<LlmResponse> {
    const body = {
      model: this.model,
      stream: false,
      think: false,
      keep_alive: "60m",
      options: { num_ctx: 4096, num_predict: req.maxOutputTokens ?? 400, temperature: 0.3 },
      messages: [{ role: "system", content: req.system }, { role: "user", content: req.user }],
      tools: (req.tools ?? []).map((t) => ({ type: "function", function: { name: t.name, description: t.description, parameters: t.parameters } })),
    };
    const r = await fetch(`${this.host}/api/chat`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(this.timeoutMs) });
    const j = (await r.json()) as { error?: string; message?: { content?: string; tool_calls?: { function: { name: string; arguments: unknown } }[] }; prompt_eval_count?: number; prompt_eval_duration?: number; eval_count?: number; eval_duration?: number };
    if (!r.ok || j.error) throw new Error(`Ollama ${r.status}: ${j.error ?? "error"}`);
    const toolCalls = (j.message?.tool_calls ?? []).map((c) => ({ name: c.function.name, args: repairArgs(c.function.arguments) }));
    const usage = { promptTokens: j.prompt_eval_count ?? 0, promptMs: (j.prompt_eval_duration ?? 0) / 1e6, evalTokens: j.eval_count ?? 0, evalMs: (j.eval_duration ?? 0) / 1e6 };
    return { text: j.message?.content ?? "", toolCalls, cached: false, model: this.model, usage };
  }
}
