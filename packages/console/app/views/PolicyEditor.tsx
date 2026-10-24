import { useEffect, useRef, useState } from "react";
import { api, type AppState, type Policy } from "../lib";
import { Card } from "./ui";

const clone = <T,>(x: T): T => JSON.parse(JSON.stringify(x)) as T;

export function PolicyEditor({ state, refresh }: { state: AppState; refresh: () => Promise<void> }) {
  const server = state.snapshot.policy;
  const [draft, setDraft] = useState<Policy>(() => clone(server));
  const [raw, setRaw] = useState(() => JSON.stringify(server, null, 2));
  const [rawErr, setRawErr] = useState("");
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const seen = useRef(`${server.name}@${server.version}`);

  // Re-sync the form when the server's policy changes (apply, reset).
  useEffect(() => {
    const key = `${server.name}@${server.version}`;
    if (key !== seen.current) {
      seen.current = key;
      setDraft(clone(server));
      setRaw(JSON.stringify(server, null, 2));
    }
  }, [server]);

  const edit = (fn: (p: Policy) => void) => {
    const p = clone(draft);
    fn(p);
    setDraft(p);
    setRaw(JSON.stringify(p, null, 2));
    setRawErr("");
  };
  const onRaw = (text: string) => {
    setRaw(text);
    try {
      setDraft(JSON.parse(text) as Policy);
      setRawErr("");
    } catch (e) {
      setRawErr((e as Error).message);
    }
  };
  const apply = async () => {
    if (rawErr) return;
    setBusy(true);
    setResult(null);
    const body = { ...clone(draft), version: server.version + 1 };
    try {
      const p = await api<Policy>("/api/policy", "PUT", body);
      setResult({ ok: true, text: `Accepted. Policy "${p.name}" is now version ${p.version}. The next decision uses it.` });
      seen.current = "";
    } catch (e) {
      setResult({ ok: false, text: (e as Error).message });
    } finally {
      setBusy(false);
      void refresh();
    }
  };
  const dirty = JSON.stringify(draft) !== JSON.stringify(server);
  const roles = Object.keys(draft.permissions ?? {});

  return (
    <div className="split">
      <Card title="Policy editor" right={<span className="dim">Live: {server.name} v{server.version}</span>}>
        <div className="form">
          <Group t="Approval limits (dollars)">
            <Dollars label="Controller agent max" v={draft.approval.agentMaxCents} on={(c) => edit((p) => { p.approval.agentMaxCents = c; })} />
            <Dollars label="Commander (local authority) max" v={draft.approval.localAuthorityMaxCents} on={(c) => edit((p) => { p.approval.localAuthorityMaxCents = c; })} />
            <Dollars label="Earth CFO (remote authority) max" v={draft.approval.remoteAuthorityMaxCents} on={(c) => edit((p) => { p.approval.remoteAuthorityMaxCents = c; })} />
          </Group>
          <Group t="Three-way match and anomalies">
            <Num label="Price tolerance (%)" v={draft.match.priceTolerancePct} step={0.5} on={(n) => edit((p) => { p.match.priceTolerancePct = n; })} />
            <Num label="Price anomaly z threshold" v={draft.priceAnomaly.zThreshold} step={0.5} on={(n) => edit((p) => { p.priceAnomaly.zThreshold = n; })} />
            <Num label="Price anomaly ratio threshold" v={draft.priceAnomaly.ratioThreshold} step={0.05} on={(n) => edit((p) => { p.priceAnomaly.ratioThreshold = n; })} />
            <Dollars label="Materiality (dollars)" v={draft.materialityCents} on={(c) => edit((p) => { p.materialityCents = c; })} />
          </Group>
          <Group t="Treasury and vendor bank changes">
            <Num label="Minimum runway (days)" v={draft.treasury.minRunwayDays} step={5} on={(n) => edit((p) => { p.treasury.minRunwayDays = n; })} />
            <label className="field"><span>Bank change action</span>
              <select className="in" value={draft.vendorBankChange.action} onChange={(e) => edit((p) => { p.vendorBankChange.action = e.target.value as "hold_and_verify" | "block"; })}>
                <option value="hold_and_verify">hold_and_verify</option>
                <option value="block">block</option>
              </select>
            </label>
            <Num label="Verification processing (minutes)" v={draft.vendorBankChange.verificationProcessingMs / 60000} step={5} on={(n) => edit((p) => { p.vendorBankChange.verificationProcessingMs = Math.round(n * 60000); })} />
          </Group>
        </div>
        <div className="row-gap apply">
          <button className="btn primary" disabled={busy || !!rawErr} onClick={apply}>Apply as version {server.version + 1}</button>
          <button className="btn" onClick={() => { setDraft(clone(server)); setRaw(JSON.stringify(server, null, 2)); setRawErr(""); setResult(null); }} disabled={!dirty}>Revert</button>
          <button className="btn" disabled={busy} title="Fresh run with the default policy" onClick={async () => { try { await api("/api/policy/default", "POST", {}); setResult({ ok: true, text: "Default policy restored; a fresh run started." }); } catch (e) { setResult({ ok: false, text: (e as Error).message }); } }}>Restore default</button>
          {dirty && <span className="warnt">unsaved changes</span>}
        </div>
        <p className="dim">Changes apply to the next decision and carry over to new runs (Reset) until you restore the default. Segregation-of-duties flags cannot be disabled.</p>
        {result && <pre className={result.ok ? "result ok" : "result bad"}>{result.ok ? "" : "REJECTED BY THE ENGINE: "}{result.text}</pre>}
      </Card>
      <Card title="Raw JSON" right={<span className="dim small">Add "execute_payment" to controller to see the engine refuse.</span>}>
        <div className="row-gap small">
          <span className="dim">Roles:</span>{roles.map((r) => <code key={r}>{r}</code>)}
        </div>
        <textarea className="json-edit" spellCheck={false} value={raw} onChange={(e) => onRaw(e.target.value)} />
        {rawErr && <p className="badt">Invalid JSON: {rawErr}</p>}
      </Card>
    </div>
  );
}

function Group({ t, children }: { t: string; children: React.ReactNode }) {
  return <fieldset><legend>{t}</legend>{children}</fieldset>;
}

function Num({ label, v, on, step }: { label: string; v: number; on: (n: number) => void; step?: number }) {
  return (
    <label className="field"><span>{label}</span>
      <input className="in num" type="number" step={step} value={Number.isFinite(v) ? v : ""} onChange={(e) => on(Number(e.target.value))} />
    </label>
  );
}

function Dollars({ label, v, on }: { label: string; v: number; on: (cents: number) => void }) {
  return (
    <label className="field"><span>{label}</span>
      <span className="money-in"><i>$</i>
        <input className="in num" type="number" step="100" value={Number.isFinite(v) ? v / 100 : ""} onChange={(e) => on(Math.round(Number(e.target.value) * 100))} />
      </span>
    </label>
  );
}
