import { useState } from "react";
import { api, simTime, usd, type AppState, type Escalation, type Vr } from "../lib";
import { Card, RoleChip } from "./ui";

export function Queues({ state, vr, refresh }: { state: AppState; vr: Vr; refresh: () => Promise<void> }) {
  const s = state.snapshot;
  const vname = (id: string) => s.vendors.find((v) => v.id === id)?.name ?? id;
  const escs = [...s.escalations].reverse();
  const pending = s.verifications.filter((v) => v.status === "pending");
  const invs = s.invoices.filter((i) => ["held", "submitted", "received"].includes(i.status)).reverse();
  return (
    <div className="grid2">
      <Card title="Escalations" right={<span className="dim">{escs.filter((e) => e.status === "awaiting_decision").length} awaiting a decision</span>} className="span2">
        {escs.length === 0 && <p className="dim big">No escalations yet.</p>}
        {escs.map((e) => <EscCard key={e.id} e={e} refresh={refresh} />)}
      </Card>
      <Card title="Pending bank verifications">
        {pending.length === 0 && <p className="dim">None pending.</p>}
        {pending.map((v) => {
          const eta = vr.earth.find((x) => x.id === v.id);
          return (
            <div key={v.id} className="qrow">
              <b>{v.id}</b> {vname(v.vendorId)}
              <div className="dim">claimed account ****{v.claimedBank.account.slice(-4)} at {v.claimedBank.bank}</div>
              <div>Request reaches Earth {simTime(v.arrivesAt)}. {eta ? `Reply ETA ${eta.replyEtaText} (in about ${eta.replyInMin} min of sim time).` : "Awaiting reply."}</div>
            </div>
          );
        })}
      </Card>
      <Card title="Held / submitted invoices">
        {invs.length === 0 && <p className="dim">No invoices waiting.</p>}
        {invs.map((i) => {
          const flags = s.flags.filter((f) => f.subject.id === i.id);
          return (
            <div key={i.id} className="qrow">
              <b>{i.vendorInvoiceNo}</b> <span className={`badge ${i.status === "held" ? "hold" : "said"}`}>{i.status.toUpperCase()}</span> <span className="num">{usd(i.total)}</span>
              <div className="dim">{vname(i.vendorId)}, PO {i.poId ?? "none"}, due {simTime(i.dueAt)}</div>
              {flags.map((f, k) => <div key={k} className="flag"><b>{f.code}</b> {f.detail} <span className="num">({usd(f.amountAtRisk)} at risk)</span></div>)}
            </div>
          );
        })}
      </Card>
      <Card title="Vendors" className="span2">
        <table className="tbl">
          <thead><tr><th>Id</th><th>Name</th><th>Status</th><th>Bank on file (masked)</th><th>Note</th></tr></thead>
          <tbody>
            {s.vendors.map((v) => (
              <tr key={v.id}>
                <td>{v.id}</td><td>{v.name}</td>
                <td><span className={`vs ${v.status}`}>{v.status}</span></td>
                <td className="num">{v.bank.bank} ****{v.bank.account.slice(-4)}</td>
                <td className="dim">{v.statusReason ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  );
}

function EscCard({ e, refresh }: { e: Escalation; refresh: () => Promise<void> }) {
  const [res, setRes] = useState("");
  const [busy, setBusy] = useState(false);
  const open = e.status === "awaiting_decision";
  const decide = async (optionId: string, as: "local_authority" | "remote_authority") => {
    setBusy(true);
    try {
      const r = await api<{ verdict: string; summary: string }>("/api/decide", "POST", { escalationId: e.id, optionId, as });
      setRes(`${r.verdict.toUpperCase()}: ${r.summary}`);
    } catch (err) {
      setRes(`Error: ${(err as Error).message}`);
    } finally {
      setBusy(false);
      void refresh();
    }
  };
  return (
    <div className={`esc ${e.status}`}>
      <div className="esc-h">
        <b>{e.id}</b>
        <span className={`badge st-${e.status}`}>{e.status.replace("_", " ").toUpperCase()}</span>
        <span className="dim">to</span><RoleChip role={e.to} />
        <span className="dim">about {e.subject.kind} {e.subject.id}</span>
        {e.decideBy && <span className="deadline">decide by {simTime(e.decideBy)}</span>}
      </div>
      <p className="big">{e.reason}</p>
      {e.message && <div className="note"><span className="dim small">Note drafted for the human:</span><br />{e.message}</div>}
      {e.history && e.history.length > 0 && (
        <div className="row-gap small"><span className="dim">Choices so far:</span>{e.history.map((h, i) => <span key={i} className="hchip">{e.options.find((o) => o.id === h.optionId)?.label ?? h.optionId} ({h.by}, {simTime(h.at)})</span>)}</div>
      )}
      {e.status === "in_transit" && <p className="dim">Message is in transit (delivers {simTime(e.deliverAt)}).</p>}
      {e.decision && <p className="okt">Decided: {e.options.find((o) => o.id === e.decision!.optionId)?.label ?? e.decision.optionId} by {e.decision.by}</p>}
      <div className="opts">
        {e.options.map((o) => (
          <div key={o.id} className={o.recommended ? "opt rec" : "opt"}>
            <div><b>{o.label}</b> {o.recommended && <span className="badge allow">recommended</span>} {!o.withinAuthority && <span className="badge hold">over authority</span>}</div>
            <div className="dim">{o.detail}</div>
            <div className="num">Cost {usd(o.costCents)}</div>
            {open && (
              <div className="row-gap">
                <button className="btn" disabled={busy} onClick={() => decide(o.id, "local_authority")}>Decide as Commander</button>
                <button className="btn" disabled={busy} onClick={() => decide(o.id, "remote_authority")}>Decide as Earth CFO</button>
              </div>
            )}
          </div>
        ))}
      </div>
      {res && <p className="result">{res}</p>}
    </div>
  );
}
