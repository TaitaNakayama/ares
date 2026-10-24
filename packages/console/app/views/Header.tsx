import { useState } from "react";
import { api, type AgentMode, type AppState, type Vr } from "../lib";

interface Props { state: AppState; vr: Vr; live: boolean; error: string | null; refresh: () => Promise<void> }

export function Header({ state, vr, live, error, refresh }: Props) {
  const [seed, setSeed] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const run = async (label: string, fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      const r = (await fn()) as { message?: string; seed?: string };
      setMsg(r.message ?? (r.seed ? `${label}: seed ${r.seed}` : label));
    } catch (e) {
      setMsg(`${label} failed: ${(e as Error).message}`);
    } finally {
      setBusy(false);
      void refresh();
    }
  };
  const pol = state.snapshot.policy;
  const mode: AgentMode = state.agents?.mode ?? state.agentMode ?? "auto";
  const safe = mode === "rules";
  const setMode = (m: AgentMode) => run(`Agent mode: ${m}`, () => api("/api/agents/mode", "POST", { mode: m }));
  const ag = state.agents;
  const agentsText = !ag || (!ag.local && !ag.cloud)
    ? "Agents: rules only"
    : `LLM ${[ag.local ? `local ${ag.local}` : "", ag.cloud ? `cloud ${ag.cloud}${ag.cloudOnline ? "" : " (offline)"}` : ""].filter(Boolean).join(" · ")} · fallbacks ${ag.stats.rulesFallbacks}`;
  return (
    <header className="hdr">
      <div className="hdr-row">
        <div className="brand">
          <span className="logo">ARES</span>
          <span className="sub">Autonomous procure-to-pay, Mars base</span>
        </div>
        <div className="facts">
          <Fact k="Seed" v={state.seed} />
          {(state as unknown as { policyCustom?: boolean }).policyCustom
            ? <Fact k="Policy" v="CUSTOM (Policy tab → Restore default)" tone="warn" />
            : <Fact k="Policy" v={`${pol.name} v${pol.version}`} />}
          <Fact k="Sim time" v={vr.time} />
          <Fact k="Speed" v={state.paused ? "paused" : `${state.speed}x${vr.timelapse ? " (time-lapse)" : ""}`} />
          <Fact k="Link" v={live ? "live" : error ? "offline" : "polling"} tone={live ? "ok" : "warn"} />
          {(() => {
            const h = (state as unknown as { headset?: { connected: number; stats: { fps?: number; receivedAt?: string; link?: string } } }).headset;
            const fresh = h?.stats?.receivedAt ? Date.now() - Date.parse(h.stats.receivedAt) < 8000 : false;
            const ok = !!h && h.connected > 0 && fresh;
            return <Fact k="Headset" v={ok ? `${Math.round(h!.stats.fps ?? 0)} fps` : h && h.connected > 0 ? "connected (paused?)" : "not connected"} tone={ok ? "ok" : "warn"} />;
          })()}
        </div>
        <div className={state.integrity.ok ? "integrity ok" : "integrity bad"} title={state.integrity.problems.join("\n")}>
          <b>{state.integrity.ok ? "Ledger verified" : "INTEGRITY FAILURE"}</b>
          <span>{state.integrity.ok ? "(hash chain + balances)" : state.integrity.problems[0]}</span>
        </div>
      </div>
      <div className="hdr-row controls">
        <button className="btn primary" disabled={busy} onClick={() => run("Next beat", () => api("/api/director/next", "POST", {}))}>Next beat</button>
        <button className="btn" disabled={busy} title="Fresh run: beats play on a timer and wait for the commander's choice in the headset" onClick={() => run("Autoplay", () => api("/api/director/autoplay", "POST", {}))}>Autoplay</button>
        <button className="btn" disabled={busy} title="Make the headset's current direction 'forward' (ask the judge to look straight ahead)" onClick={() => run("Recentered", () => api("/api/headset/recenter", "POST", {}))}>Recenter headset</button>
        <button className={(state as unknown as { rogueController?: boolean }).rogueController ? "btn danger" : "btn"} disabled={busy} title="Swap the Rule Keeper's brain for a malicious one (fresh run). The controls must still hold." onClick={() => run("Rogue toggled", () => api("/api/agents/rogue", "POST", { on: !(state as unknown as { rogueController?: boolean }).rogueController }))}>{(state as unknown as { rogueController?: boolean }).rogueController ? "Rogue Rule Keeper: ON" : "Rogue Rule Keeper"}</button>
        <button className={safe ? "btn safe on" : "btn safe"} disabled={busy} title="Safe mode: every agent switches instantly to its deterministic rules brain, mid-run, no reset" onClick={() => setMode(safe ? "auto" : "rules")}>{safe ? "Safe mode: ON (rules)" : "SAFE MODE"}</button>
        <div className="seg" role="group" aria-label="Agent brain mode">
          {(["auto", "local", "cloud", "rules"] as AgentMode[]).map((m) => (
            <button key={m} className={mode === m ? "on" : ""} aria-pressed={mode === m} disabled={busy} onClick={() => { if (mode !== m) void setMode(m); }}>{m}</button>
          ))}
        </div>
        <span className={ag?.local || ag?.cloud ? "agents-fact" : "agents-fact warn"} title={state.llm ?? undefined}>{agentsText}</span>
        <button className="btn" disabled={busy} onClick={() => run(state.paused ? "Resumed" : "Paused", () => api("/api/director/speed", "POST", { speed: state.speed, paused: !state.paused }))}>
          {state.paused ? "Resume" : "Pause"}
        </button>
        <span className="sep" />
        <input className="in seed" placeholder="seed (blank = same)" value={seed} onChange={(e) => setSeed(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void run("Reset", () => api("/api/director/reset", "POST", { seed: seed || undefined })); }} />
        <button className="btn" disabled={busy} onClick={() => run("Reset", () => api("/api/director/reset", "POST", { seed: seed || undefined }))}>Reset</button>
        <button className="btn" disabled={busy} onClick={() => { const s = "seed-" + Math.random().toString(36).slice(2, 8); setSeed(s); void run("Random seed", () => api("/api/director/reset", "POST", { seed: s })); }}>Random seed</button>
        <span className="msg" aria-live="polite">{msg}</span>
      </div>
    </header>
  );
}

function Fact({ k, v, tone }: { k: string; v: string; tone?: string }) {
  return (
    <div className="fact">
      <span className="k">{k}</span>
      <span className={`v ${tone ?? ""}`}>{v}</span>
    </div>
  );
}
