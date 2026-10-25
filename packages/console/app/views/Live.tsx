import { useEffect, useRef } from "react";
import { usd, type AppState, type Narration, type Vr } from "../lib";
import { Card, Outcome, RoleChip } from "./ui";

export function Live({ state, vr, narration, thinking }: { state: AppState; vr: Vr; narration: Narration[]; thinking: string[] }) {
  const ref = useRef<HTMLDivElement>(null);
  const last = narration.at(-1)?.seq;
  useEffect(() => { ref.current?.scrollTo({ top: ref.current.scrollHeight }); }, [last, thinking.length]);
  const waiting = vr.waiting.length > 0;
  const solsLeft = vr.power.solsLeft;
  return (
    <div className="live">
      <Card title="Mars base wall screen" className="wall">
        <div className="tiles">
          <Tile k="Power" v={`${Math.round(vr.power.socPct)}%`} s={`battery, solar ${Math.round(vr.power.solarKWhPerSol)} / load ${Math.round(vr.power.loadKWhPerSol)} kWh per sol`} tone={vr.power.socPct < 30 ? "bad" : vr.power.socPct < 60 ? "warn" : ""} />
          <Tile k="Sols left" v={solsLeft === null ? "stable" : solsLeft.toFixed(1)} s={solsLeft === null ? "power not running down" : "at current load"} tone={solsLeft !== null && solsLeft < 5 ? "bad" : ""} />
          <Tile k="Dust (tau)" v={vr.tau.toFixed(1)} s={vr.tau > 3 ? "dust storm" : "clear sky"} tone={vr.tau > 3 ? "warn" : ""} />
          <Tile k="Cash" v={usd(vr.money.cash)} s="on hand" />
          <Tile k="Runway" v={`${vr.money.runwayDays} days`} s={`committed ${vr.money.committedText}`} />
          <Tile k="Money saved" v={vr.money.savedText} s="payments stopped by controls" tone="good" />
          <Tile k="Commander" v={waiting ? "Waiting for commander" : "No decision pending"} s={waiting ? `${vr.waiting.length} escalation(s) need you (see Queues)` : `${state.snapshot.escalations.length} escalations so far`} tone={waiting ? "warn" : ""} wide />
        </div>
      </Card>
      <Card title="What the robots are saying" right={<span className="dim">{narration.length} messages</span>} className="feed-card">
        <div className="feed" ref={ref}>
          {narration.length === 0 && <p className="dim">Nothing yet. Press "Start show".</p>}
          {narration.map((n) => (
            <article key={n.seq} className={`msg-row ${n.outcome}`}>
              <div className="who">
                <RoleChip role={n.role} actorId={n.actorId} name={n.name} showRole />
                {n.voice && <span className="said-aloud" title="Said aloud in the headset" aria-label="said aloud"><Speaker /></span>}
                {n.voice && n.via && <span className={`badge src ${n.via}`}>{n.via}</span>}
                <span className="mood">{n.mood}</span>
                <Outcome o={n.outcome} />
              </div>
              <p>{n.text}</p>
              <time>#{n.seq}</time>
            </article>
          ))}
          {thinking.map((role) => (
            <article key={`think-${role}`} className="msg-row thinking">
              <div className="who">
                <RoleChip role={role} showRole />
                <span className="think"><i className="pulse" />thinking…</span>
              </div>
            </article>
          ))}
        </div>
      </Card>
    </div>
  );
}

function Tile({ k, v, s, tone = "", wide }: { k: string; v: string; s: string; tone?: string; wide?: boolean }) {
  return (
    <div className={`tile ${tone} ${wide ? "wide" : ""}`}>
      <span className="k">{k}</span>
      <span className="v num">{v}</span>
      <span className="s">{s}</span>
    </div>
  );
}

function Speaker() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M11 5 6 9H2v6h4l5 4z" /><path d="M15.5 8.5a5 5 0 0 1 0 7" /><path d="M19 5a10 10 0 0 1 0 14" />
    </svg>
  );
}
