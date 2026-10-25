import { useEffect, useState } from "react";
import { api, ROLE_NAMES, simTime, usd, type AppState, type JournalEntry, type Trace } from "../lib";
import { Card, Hash, RoleChip } from "./ui";
import { TracePanel } from "./Trace";

export function LedgerView({ state }: { state: AppState }) {
  const [sel, setSel] = useState<string | null>(() => new URLSearchParams(location.search).get("entry"));
  const entries = [...state.snapshot.ledger].reverse();
  const actors = new Map(state.snapshot.actors?.map((a) => [a.id, a]) ?? []);
  const names = new Map([...actors].map(([id, a]) => [id, a.displayName] as [string, string]));
  return (
    <div className="split">
      <div className="col">
        <Card title="Trial balance" right={<span className={state.integrity.ok ? "okt" : "badt"}>{state.integrity.ok ? "balanced, chain intact" : "PROBLEM"}</span>}>
          <table className="tbl">
            <tbody>
              {state.snapshot.trialBalance.map((t) => (
                <tr key={t.account}>
                  <td>{t.name}</td>
                  <td className="num r">{usd(t.balance)}</td>
                </tr>
              ))}
              <tr className="total">
                <td>Sum (must be $0.00)</td>
                <td className="num r">{usd(state.snapshot.trialBalance.reduce((s, t) => s + t.balance, 0))}</td>
              </tr>
            </tbody>
          </table>
          <p className="dim small">Debit-positive. Liabilities and equity show as negative.</p>
        </Card>
        <Card title="Journal" right={<span className="dim">{entries.length} entries. Click one to trace it to its sources.</span>}>
          <div className="entries">
            {entries.map((e) => (
              <Entry key={e.id} e={e} actor={actors.get(e.actorId)?.displayName ?? e.actorId} role={actors.get(e.actorId)?.role} names={names} selected={sel === e.id} onClick={() => setSel(e.id)} />
            ))}
          </div>
        </Card>
      </div>
      <div className="col trace-col">
        {sel ? <TraceLoader id={sel} state={state} onPick={setSel} /> : <Card title="Trace"><p className="dim big">Select a journal entry to see the proposal, every rule that was checked, the source records and documents, approvers and the hash chain behind it.</p></Card>}
      </div>
    </div>
  );
}

function Entry({ e, actor, role, names, selected, onClick }: { e: JournalEntry; actor: string; role?: string; names: Map<string, string>; selected: boolean; onClick: () => void }) {
  return (
    <button className={selected ? "entry on" : "entry"} onClick={onClick}>
      <div className="entry-h">
        <b>{e.id}</b>
        <span className="memo">{e.memo}</span>
        <Hash h={e.hash} />
      </div>
      <div className="lines">
        {e.lines.map((l, i) => (
          <div key={i} className="pl">
            <span className={l.debit ? "acct dr" : "acct cr"}>{l.credit ? "    " : ""}{l.account}</span>
            <span className="num dr-amt">{l.debit ? usd(l.debit) : ""}</span>
            <span className="num cr-amt">{l.credit ? usd(l.credit) : ""}</span>
          </div>
        ))}
      </div>
      <div className="entry-f">
        <span>{simTime(e.at)}</span>
        {role ? <RoleChip role={role} actorId={e.actorId} name={actor} /> : <span>{actor}</span>}
        {e.approvers.length > 0 && <span className="dim">approved by {e.approvers.map((a) => names.get(a) ?? ROLE_NAMES[a] ?? a).join(", ")}</span>}
      </div>
    </button>
  );
}

function TraceLoader({ id, state, onPick }: { id: string; state: AppState; onPick: (id: string) => void }) {
  const [t, setT] = useState<Trace | null>(null);
  const [err, setErr] = useState("");
  useEffect(() => {
    let dead = false;
    setT(null);
    setErr("");
    api<Trace>(`/api/trace/${encodeURIComponent(id)}`).then((x) => { if (!dead) setT(x); }).catch((e: Error) => { if (!dead) setErr(e.message); });
    return () => { dead = true; };
  }, [id]);
  if (err) return <Card title="Trace"><p className="badt">{err}</p></Card>;
  if (!t) return <Card title="Trace"><p className="dim">Loading {id}...</p></Card>;
  return <TracePanel trace={t} state={state} onPick={onPick} />;
}
