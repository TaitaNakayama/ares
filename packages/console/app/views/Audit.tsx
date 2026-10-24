import { Fragment, useMemo, useState } from "react";
import { simTime, type AppState } from "../lib";
import { Card, Hash } from "./ui";

export function AuditView({ state }: { state: AppState }) {
  const [kind, setKind] = useState("all");
  const [q, setQ] = useState("");
  const [open, setOpen] = useState<number | null>(null);
  const kinds = useMemo(() => [...new Set(state.audit.map((a) => a.kind))].sort(), [state.audit]);
  const rows = state.audit.filter((a) => (kind === "all" || a.kind === kind) && (!q || a.summary.toLowerCase().includes(q.toLowerCase()))).slice().reverse();
  return (
    <Card title="Audit trail" right={<span className="dim">{rows.length} of {state.audit.length} shown (latest 400). Each record's hash covers the previous one.</span>}>
      <div className="filters">
        <label>Kind
          <select className="in" value={kind} onChange={(e) => setKind(e.target.value)}>
            <option value="all">all</option>
            {kinds.map((k) => <option key={k}>{k}</option>)}
          </select>
        </label>
        <label>Search
          <input className="in" value={q} onChange={(e) => setQ(e.target.value)} placeholder="summary text" />
        </label>
      </div>
      <table className="tbl audit">
        <thead><tr><th>Seq</th><th>Sim time</th><th>Kind</th><th>Actor</th><th>Summary</th><th>Prev</th><th>Hash</th></tr></thead>
        <tbody>
          {rows.map((a) => (
            <Fragment key={a.seq}>
              <tr className="clickable" onClick={() => setOpen(open === a.seq ? null : a.seq)}>
                <td className="num">{a.seq}</td>
                <td className="nowrap">{simTime(a.at)}</td>
                <td><span className={`kindtag k-${a.kind}`}>{a.kind}</span></td>
                <td>{a.actorId}</td>
                <td>{a.summary}</td>
                <td><Hash h={a.prevHash} /></td>
                <td><Hash h={a.hash} /></td>
              </tr>
              {open === a.seq && (
                <tr><td colSpan={7}><pre className="json">{JSON.stringify(a.data, null, 2)}</pre></td></tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </Card>
  );
}
