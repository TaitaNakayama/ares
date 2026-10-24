import { useState } from "react";
import { api, usd, type AppState } from "../lib";
import { Card } from "./ui";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type F = Record<string, any>;
type Result = { ok: boolean; text: string } | null;

export function Inject({ state, refresh, goLive }: { state: AppState; refresh: () => Promise<void>; goLive: () => void }) {
  const s = state.snapshot;
  const [res, setRes] = useState<Result>(null);
  const post = async (body: Record<string, unknown>) => {
    try {
      const r = await api<{ message: string }>("/api/inject", "POST", body);
      setRes({ ok: true, text: r.message });
    } catch (e) {
      setRes({ ok: false, text: (e as Error).message });
    }
    void refresh();
  };
  const dollars = (v: string) => (v === "" ? undefined : Math.round(Number(v) * 100));
  const num = (v: string) => (v === "" ? undefined : Number(v));
  const openPos = s.pos;
  const openReq = s.requisitions.filter((r) => r.status === "open" || r.status === "escalated").at(-1);

  return (
    <div className="grid2">
      <Card title="Invent an event" className="span2">
        <p className="big">Anything you inject goes through the same rules as real events. Watch the <button className="link" onClick={goLive}>Live feed</button> for the reaction, then trace what happened in the Ledger and Audit trail.</p>
        {res && <p className={res.ok ? "result ok" : "result bad"}>{res.ok ? "Injected: " : "Error: "}{res.text}. {res.ok && "Now watch the Live feed."}</p>}
      </Card>

      <Form title="Invoice" onSubmit={(f) => post({ kind: "invoice", vendorId: f.vendor || undefined, poId: f.po || undefined, qty: num(f.qty), unitPrice: dollars(f.price), bank: f.bank, invoiceNo: f.no || undefined })}
        init={{ vendor: "", po: openPos.at(-1)?.id ?? "", qty: "", price: "", bank: "master", no: "" }}>
        {(f, set) => (<>
          <Sel label="Vendor" v={f.vendor} on={(v) => set("vendor", v)} opts={[["", "(PO's vendor)"], ...s.vendors.map((v) => [v.id, `${v.name} (${v.status})`] as [string, string])]} />
          <Sel label="Purchase order" v={f.po} on={(v) => set("po", v)} opts={[["", "(latest PO)"], ...openPos.map((p) => [p.id, `${p.id} ${usd(p.total)} ${p.status}`] as [string, string])]} />
          <In label="Quantity (blank = PO qty)" v={f.qty} on={(v) => set("qty", v)} type="number" />
          <In label="Unit price, dollars (blank = PO price)" v={f.price} on={(v) => set("price", v)} type="number" />
          <Sel label="Bank details" v={f.bank} on={(v) => set("bank", v)} opts={[["master", "Matches vendor master"], ["new", "NEW account (fraud test)"]]} />
          <In label="Invoice no (optional)" v={f.no} on={(v) => set("no", v)} />
        </>)}
      </Form>

      <Form title="Quote" note={openReq ? `For open request ${openReq.id}: ${openReq.qty} x ${openReq.sku}` : "Needs an open purchase request."} onSubmit={(f) => post({ kind: "quote", vendorId: f.vendor || undefined, unitPrice: dollars(f.price), qty: num(f.qty), bank: f.bank })}
        init={{ vendor: "", price: "", qty: "", bank: "master" }}>
        {(f, set) => (<>
          <Sel label="Vendor" v={f.vendor} on={(v) => set("vendor", v)} opts={[["", "(first vendor)"], ...s.vendors.map((v) => [v.id, v.name] as [string, string])]} />
          <In label="Unit price, dollars (blank = market)" v={f.price} on={(v) => set("price", v)} type="number" />
          <In label="Quantity available" v={f.qty} on={(v) => set("qty", v)} type="number" />
          <Sel label="Bank details" v={f.bank} on={(v) => set("bank", v)} opts={[["master", "Matches vendor master"], ["new", "NEW account"]]} />
        </>)}
      </Form>

      <Form title="Need (new purchase request)" onSubmit={(f) => post({ kind: "need", sku: f.sku, qty: num(f.qty), reason: f.reason || undefined })}
        init={{ sku: s.items[0]?.sku ?? "WTR-CART", qty: "10", reason: "" }}>
        {(f, set) => (<>
          <Sel label="Item" v={f.sku} on={(v) => set("sku", v)} opts={s.items.map((i) => [i.sku, `${i.sku} ${i.name}`] as [string, string])} />
          <In label="Quantity" v={f.qty} on={(v) => set("qty", v)} type="number" />
          <In label="Reason" v={f.reason} on={(v) => set("reason", v)} />
        </>)}
      </Form>

      <Form title="Delivery" onSubmit={(f) => post({ kind: "delivery", poId: f.po || undefined, qtyReceived: num(f.rec), qtyRejected: num(f.rej) })}
        init={{ po: "", rec: "", rej: "" }}>
        {(f, set) => (<>
          <Sel label="Purchase order" v={f.po} on={(v) => set("po", v)} opts={[["", "(latest open PO)"], ...openPos.map((p) => [p.id, `${p.id} ${p.status}`] as [string, string])]} />
          <In label="Received (blank = full)" v={f.rec} on={(v) => set("rec", v)} type="number" />
          <In label="Rejected" v={f.rej} on={(v) => set("rej", v)} type="number" />
        </>)}
      </Form>

      <Form title="Dust storm" onSubmit={(f) => post({ kind: "storm", tau: num(f.tau) })} init={{ tau: "4.6" }}>
        {(f, set) => <In label="Optical depth tau (clear 0.6, storm 4+)" v={f.tau} on={(v) => set("tau", v)} type="number" />}
      </Form>
    </div>
  );
}

function Form({ title, note, init, onSubmit, children }: {
  title: string; note?: string; init: Record<string, string>;
  onSubmit: (f: F) => void;
  children: (f: F, set: (k: string, v: string) => void) => React.ReactNode;
}) {
  const [f, setF] = useState<F>(init);
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));
  return (
    <Card title={title}>
      {note && <p className="dim">{note}</p>}
      <form className="form" onSubmit={(e) => { e.preventDefault(); onSubmit(f); }}>
        {children(f, set)}
        <button className="btn primary" type="submit">Inject {title.toLowerCase()}</button>
      </form>
    </Card>
  );
}

function In({ label, v, on, type }: { label: string; v: string; on: (v: string) => void; type?: string }) {
  return <label className="field"><span>{label}</span><input className="in" type={type ?? "text"} step="any" value={v} onChange={(e) => on(e.target.value)} /></label>;
}

function Sel({ label, v, on, opts }: { label: string; v: string; on: (v: string) => void; opts: [string, string][] }) {
  return <label className="field"><span>{label}</span><select className="in" value={v} onChange={(e) => on(e.target.value)}>{opts.map(([k, t]) => <option key={k} value={k}>{t}</option>)}</select></label>;
}
