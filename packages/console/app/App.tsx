import { useState } from "react";
import { useAres } from "./useAres";
import { Header } from "./views/Header";
import { Live } from "./views/Live";
import { LedgerView } from "./views/Ledger";
import { AuditView } from "./views/Audit";
import { Queues } from "./views/Queues";
import { PolicyEditor } from "./views/PolicyEditor";
import { Inject } from "./views/Inject";
import { ScorecardView } from "./views/Scorecard";

const TABS = ["Live feed", "Ledger", "Audit trail", "Queues", "Policy", "Inject", "Scorecard"] as const;
type Tab = (typeof TABS)[number];

export function App() {
  const { state, vr, narration, error, live, refresh } = useAres();
  const fromHash = TABS.find((t) => t.toLowerCase().replace(/ /g, "-") === location.hash.slice(1));
  const [tab, setTabRaw] = useState<Tab>(fromHash ?? "Live feed");
  const setTab = (t: Tab) => { setTabRaw(t); history.replaceState(null, "", "#" + t.toLowerCase().replace(/ /g, "-")); };

  if (!state || !vr) {
    return <div className="boot">{error ? `Cannot reach the Ares server: ${error}` : "Connecting to Ares..."}</div>;
  }
  const waiting = state.snapshot.escalations.filter((e) => e.status === "awaiting_decision").length;

  return (
    <div className="app">
      <Header state={state} vr={vr} live={live} error={error} refresh={refresh} />
      <nav className="tabs" role="tablist">
        {TABS.map((t) => (
          <button key={t} role="tab" aria-selected={tab === t} className={tab === t ? "tab on" : "tab"} onClick={() => setTab(t)}>
            {t}
            {t === "Queues" && waiting > 0 && <span className="count">{waiting}</span>}
          </button>
        ))}
      </nav>
      <main className="main">
        {tab === "Live feed" && <Live state={state} vr={vr} narration={narration} />}
        {tab === "Ledger" && <LedgerView state={state} />}
        {tab === "Audit trail" && <AuditView state={state} />}
        {tab === "Queues" && <Queues state={state} vr={vr} refresh={refresh} />}
        {tab === "Policy" && <PolicyEditor state={state} refresh={refresh} />}
        {tab === "Inject" && <Inject state={state} refresh={refresh} goLive={() => setTab("Live feed")} />}
        {tab === "Scorecard" && <ScorecardView state={state} />}
      </main>
      <footer className="foot">
        SIMULATED: the Mars base, suppliers, prices, budget, invoices and people are invented for this demo. The ledger, hash chains, rules and decisions are real.
      </footer>
    </div>
  );
}
