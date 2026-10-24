import { Fragment } from "react";
import { simTime, usd, type AppState, type Decision, type Proposal, type Trace, type TraceSource } from "../lib";
import { Card, Hash, Outcome, RoleChip } from "./ui";

export function TracePanel({ trace, state, onPick }: { trace: Trace; state: AppState; onPick: (id: string) => void }) {
  const { entry: e } = trace;
  const prev = state.snapshot.ledger.find((x) => x.seq === e.seq - 1);
  const next = state.snapshot.ledger.find((x) => x.seq === e.seq + 1);
  return (
    <div className="trace">
      <Card title={`Trace of ${e.id}`} right={<span className="dim">{simTime(e.at)}</span>}>
        <p className="big memo">{e.memo}</p>
        <table className="tbl lines-tbl">
          <thead><tr><th>Account</th><th className="r">Debit</th><th className="r">Credit</th></tr></thead>
          <tbody>
            {e.lines.map((l, i) => (
              <tr key={i}><td>{l.account}{l.vendorId ? ` (${l.vendorId})` : ""}</td><td className="num r">{l.debit ? usd(l.debit) : ""}</td><td className="num r">{l.credit ? usd(l.credit) : ""}</td></tr>
            ))}
          </tbody>
        </table>
        <div className="row-gap">
          <span className="dim">Posted by</span>
          {trace.actor ? <RoleChip role={trace.actor.role} name={trace.actor.displayName} /> : <b>{e.actorId}</b>}
          <span className="dim">Approvers</span>
          {trace.approvers.length === 0 && <span>none required</span>}
          {trace.approvers.map((a, i) => (a ? <RoleChip key={i} role={a.role} name={a.displayName} /> : <span key={i}>{e.approvers[i]}</span>))}
        </div>
      </Card>

      <Card title="1. Who proposed it" right={trace.proposal ? <SourceBadge s={trace.proposal.source} /> : undefined}>
        {trace.proposal ? <ProposalView p={trace.proposal} /> : <p className="dim">System entry (no agent proposal), e.g. opening balance.</p>}
      </Card>

      <Card title="2. How the rules decided" right={trace.decision ? <Outcome o={trace.decision.verdict} /> : undefined}>
        {trace.decision ? <DecisionView d={trace.decision} labels={state.ruleLabels} /> : <p className="dim">No decision record.</p>}
      </Card>

      <Card title={`3. Source records and documents (${trace.sources.length})`}>
        {trace.sources.map((s, i) => <SourceView key={i} s={s} />)}
      </Card>

      <Card title="4. Hash chain">
        <div className="chain">
          <ChainBox label={prev ? prev.id : "genesis"} h={prev?.hash ?? "genesis"} onClick={prev ? () => onPick(prev.id) : undefined} />
          <span className="arrow">prevHash {"->"}</span>
          <ChainBox label={e.id} h={e.hash} cur />
          {next && (<><span className="arrow">{"->"}</span><ChainBox label={next.id} h={next.hash} onClick={() => onPick(next.id)} /></>)}
        </div>
        <dl className="kv">
          <dt>prevHash</dt><dd><code>{e.prevHash}</code></dd>
          <dt>hash</dt><dd><code>{e.hash}</code></dd>
          <dt>rules checked</dt><dd>{e.rules.length}</dd>
        </dl>
        <p className="dim small">hash = SHA-256 of this entry (including prevHash). Changing any earlier entry breaks every hash after it.</p>
      </Card>
    </div>
  );
}

function ChainBox({ label, h, cur, onClick }: { label: string; h: string; cur?: boolean; onClick?: () => void }) {
  return (
    <button className={cur ? "cbox cur" : "cbox"} onClick={onClick} disabled={!onClick}>
      <b>{label}</b>
      <Hash h={h} />
    </button>
  );
}

function SourceBadge({ s }: { s?: string }) {
  const src = s ?? "rules";
  return <span className={`badge src ${src}`}>source: {src}</span>;
}

function ProposalView({ p }: { p: Proposal }) {
  return (
    <>
      <dl className="kv">
        <dt>Agent</dt><dd><RoleChip role={p.role} /></dd>
        <dt>Action</dt><dd><code>{p.action.type}</code></dd>
        <dt>Rationale</dt><dd>{p.rationale ?? "-"}</dd>
        <dt>Parameters</dt><dd><code className="wrap">{JSON.stringify(p.action.params)}</code></dd>
      </dl>
    </>
  );
}

function DecisionView({ d, labels }: { d: Decision; labels: Record<string, string> }) {
  const failed = d.rules.filter((r) => !r.ok).length;
  return (
    <>
      <p className="big">{d.summary}</p>
      <p className="dim">{d.rules.length} rules checked, {failed} failed.</p>
      <ul className="rules">
        {d.rules.map((r, i) => (
          <li key={i} className={r.ok ? "pass" : `fail ${r.effect}`}>
            <span className="mark">{r.ok ? "PASS" : "FAIL"}</span>
            <div>
              <b>{labels[r.rule] ?? r.rule}</b>
              <div className="dim small"><code>{r.rule}</code>{r.ok ? "" : ` (effect: ${r.effect})`}</div>
              <div className="detail">{r.detail}</div>
            </div>
          </li>
        ))}
      </ul>
    </>
  );
}

const MONEY = /(cents|amount|total|price|cash|payable|variance)/i;
const TIME = /(^at$|At$|validUntil|validTo|validFrom|orderBy|deliverAt|decideBy)/;
const SKIP = new Set(["docText", "lines", "bank", "claimedBank", "context", "approvedBy"]);

function fmtVal(k: string, v: unknown): string {
  if (typeof v === "number") {
    if (TIME.test(k)) return simTime(v);
    if (MONEY.test(k)) return usd(v);
    return String(v);
  }
  if (Array.isArray(v)) return v.join(", ");
  if (v && typeof v === "object") return JSON.stringify(v);
  return String(v);
}

function Bank({ b }: { b: unknown }) {
  const x = b as { holder: string; bank: string; account: string } | undefined;
  if (!x) return null;
  return <>{`${x.holder}, ${x.bank}, acct ****${String(x.account).slice(-4)}`}</>;
}

function SourceView({ s }: { s: TraceSource }) {
  const rec = s.record as Record<string, unknown> | undefined;
  const lines = rec?.lines as { sku: string; qty?: number; qtyReceived?: number; qtyRejected?: number; unitPrice?: number }[] | undefined;
  return (
    <div className="src">
      <div className="src-h">
        <span className="kind">{s.ref.kind}</span> <b>{s.ref.id}</b>
        {s.proposal && <span className="dim"> created by proposal {s.proposal.id} ({s.proposal.source ?? "rules"}), decision {s.decision?.verdict}</span>}
      </div>
      {rec ? (
        <dl className="kv">
          {Object.entries(rec).filter(([k, v]) => !SKIP.has(k) && v !== undefined && v !== null && k !== "id").map(([k, v]) => (
            <Fragment key={k}><dt>{k}</dt><dd className={MONEY.test(k) && typeof v === "number" ? "num" : ""}>{fmtVal(k, v)}</dd></Fragment>
          ))}
          {lines && (<><dt>lines</dt><dd>{lines.map((l, i) => <div key={i} className="num">{l.qty ?? l.qtyReceived} x {l.sku}{l.unitPrice !== undefined ? ` @ ${usd(l.unitPrice)}` : ""}{l.qtyRejected ? ` (${l.qtyRejected} rejected)` : ""}</div>)}</dd></>)}
          {Boolean(rec.bank || rec.claimedBank) && (<><dt>bank</dt><dd><Bank b={rec.bank ?? rec.claimedBank} /></dd></>)}
        </dl>
      ) : <p className="dim small">No record held for this reference.</p>}
      {s.document && (
        <div className="doc">
          <div className="doc-h">Original document {s.document.id} ({s.document.kind}) from {s.document.from}</div>
          <pre>{s.document.text}</pre>
        </div>
      )}
    </div>
  );
}
