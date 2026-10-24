import { useEffect, useState } from "react";
import { api, usd, type AppState, type Scorecard } from "../lib";
import { Card } from "./ui";

const pct = (x: number) => `${(x * 100).toFixed(1)}%`;
const TYPE_NAMES: Record<string, string> = {
  duplicate_invoice: "Duplicate invoice", bank_fraud_invoice: "Bank fraud (invoice)", bank_fraud_quote: "Bank fraud (quote)",
  inflated_quote: "Inflated quote", inflated_invoice: "Inflated invoice", short_delivery: "Short delivery", over_contract_quote: "Over-contract quote",
};

export function ScorecardView({ state }: { state: AppState }) {
  const [from, setFrom] = useState("5000");
  const [count, setCount] = useState("50");
  const [cycles, setCycles] = useState("30");
  const [usePolicy, setUsePolicy] = useState(false);
  const [running, setRunning] = useState(false);
  const [sc, setSc] = useState<Scorecard | null>(null);
  const [err, setErr] = useState("");
  const run = async () => {
    setRunning(true); setErr("");
    try {
      setSc(await api<Scorecard>("/api/eval", "POST", { from: Number(from), count: Math.min(500, Number(count)), cycles: Number(cycles), usePolicy }));
    } catch (e) { setErr((e as Error).message); } finally { setRunning(false); }
  };
  // ?eval=N in the URL starts a run of N seeds on load (handy for demos and screenshots).
  useEffect(() => {
    const n = new URLSearchParams(location.search).get("eval");
    if (n) { setCount(n); void (async () => { setRunning(true); try { setSc(await api<Scorecard>("/api/eval", "POST", { from: 5000, count: Number(n), cycles: 30, usePolicy: true })); } catch (e) { setErr((e as Error).message); } finally { setRunning(false); } })(); }
  }, []);
  const pol = state.snapshot.policy;
  return (
    <div className="col">
      <Card title="Evaluation scorecard">
        <p className="big">Scoring uses a world answer key that the engine never sees: the simulator plants errors and fraud, and we count what actually got through to the ledger and bank.</p>
        <div className="row-gap evalform">
          <label className="field"><span>From seed</span><input className="in num" type="number" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
          <label className="field"><span>Count (max 500)</span><input className="in num" type="number" max={500} value={count} onChange={(e) => setCount(e.target.value)} /></label>
          <label className="field"><span>Cycles</span><input className="in num" type="number" value={cycles} onChange={(e) => setCycles(e.target.value)} /></label>
          <label className="check"><input type="checkbox" checked={usePolicy} onChange={(e) => setUsePolicy(e.target.checked)} /> Use current policy ({pol.name} v{pol.version})</label>
          <button className="btn primary" disabled={running} onClick={run}>{running ? "Running..." : "Run evaluation"}</button>
          {running && <span className="spinner" role="status" aria-label="running" />}
        </div>
        {running && <p className="dim">Simulating {count} independent worlds. This can take a while for large counts.</p>}
        {err && <p className="result bad">{err}</p>}
      </Card>
      {sc && (
        <>
          <Card title={`Results: ${sc.seeds.count} seeds from ${sc.seeds.from}, ${sc.cyclesPerSeed} cycles each`} right={<span className="dim">{sc.policy.name} v{sc.policy.version}, {(sc.ms / 1000).toFixed(1)} s</span>}>
            <div className="tiles">
              <Stat k="Overall recall" v={pct(sc.overallRecall)} tone="good" s="planted errors caught" />
              <Stat k="False-alarm rate" v={pct(sc.falseAlarmRate)} s={`of ${sc.cleanInvoices} clean invoices not paid in full`} />
              <Stat k="Held then paid" v={pct(sc.frictionRate)} s="clean invoices delayed, then paid" />
              <Stat k="Money saved" v={usd(sc.savedCents)} tone="good" s="stopped before leaving" />
              <Stat k="Overpaid" v={usd(sc.overpaidCents)} tone={sc.overpaidCents ? "bad" : "good"} s="paid beyond what was due" />
              <Stat k="Wrongly blocked" v={usd(sc.wronglyBlockedCents)} s="legit invoices not paid" />
              <Stat k="Payments to fraud accounts" v={String(sc.fraudPaymentsSent)} tone={sc.fraudPaymentsSent ? "bad" : "good"} s="must be 0" />
              <Stat k="Escalations / cycle" v={sc.escalationRate.toFixed(2)} s="human attention needed" />
              <Stat k="Integrity failures" v={String(sc.integrityFailures)} tone={sc.integrityFailures ? "bad" : "good"} s="runs with a broken ledger" />
              <Stat k="Proposals" v={sc.proposals.toLocaleString()} s={`${sc.deniedProposals.toLocaleString()} denied by policy`} />
              <Stat k="Runtime" v={`${(sc.ms / 1000).toFixed(1)} s`} s={sc.medianDaysToPay === null ? "" : `median ${sc.medianDaysToPay.toFixed(2)} days to pay`} />
            </div>
          </Card>
          <Card title="Recall by error type">
            <table className="tbl">
              <thead><tr><th>Error type</th><th className="r">Planted</th><th className="r">Caught</th><th className="r">Recall</th><th></th></tr></thead>
              <tbody>
                {sc.perError.map((p) => (
                  <tr key={p.type}>
                    <td>{TYPE_NAMES[p.type] ?? p.type}</td><td className="num r">{p.planted}</td><td className="num r">{p.caught}</td><td className="num r">{pct(p.recall)}</td>
                    <td className="barcell"><div className="bar"><i style={{ width: `${p.recall * 100}%` }} className={p.recall < 0.9 ? "low" : ""} /></div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </>
      )}
    </div>
  );
}

function Stat({ k, v, s, tone = "" }: { k: string; v: string; s: string; tone?: string }) {
  return <div className={`tile ${tone}`}><span className="k">{k}</span><span className="v num">{v}</span><span className="s">{s}</span></div>;
}
