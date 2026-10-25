import { useState } from "react";
import { api, usd, type AppState } from "../lib";
import { Card } from "./ui";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type F = Record<string, any>;
type Result = { ok: boolean; text: string } | null;

export function Inject({ state, refresh, goLive }: { state: AppState; refresh: () => Promise<void>; goLive: () => void }) {
  const s = state.snapshot;
  const [res, setRes] = useState<Result>(null);
  const post = async (body: Record<string, unknown>): Promise<boolean> => {
    try {
      const r = await api<{ message: string }>("/api/inject", "POST", body);
      setRes({ ok: true, text: r.message });
      void refresh();
      return true;
    } catch (e) {
      setRes({ ok: false, text: (e as Error).message });
      void refresh();
      return false;
    }
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

      <Report post={post} goLive={goLive} />

      <PasteDoc state={state} post={post} goLive={goLive} />

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

function PasteDoc({ state, post, goLive }: { state: AppState; post: (b: Record<string, unknown>) => Promise<boolean>; goLive: () => void }) {
  const s = state.snapshot;
  const po = s.pos.at(-1);
  const vendor = s.vendors.find((v) => v.id === po?.vendorId) ?? s.vendors[0];
  const line = po?.lines[0];
  const item = s.items.find((i) => i.sku === line?.sku);
  const example = `Hi team,\n\nPlease find our invoice no. XYZ-77812 attached. Ref ${po?.id ?? "PO-0001"}.\n\n${line?.qty ?? 36} x ${item?.name ?? "air filters"} @ ${usd(line?.unitPrice ?? 1935000)}\n\nNote our NEW banking details: Remit to: ${vendor?.name ?? "Vendor"}, Coastal Credit Union, routing 321456789, account 4455667788\n\nThanks,\n${vendor?.name ?? "Vendor"} accounts receivable`;
  const [text, setText] = useState<string | null>(null);
  const value = text ?? example;
  return (
    <Card title="Paste a document" className="span2">
      <p className="big">Bills reads it (LLM if configured, otherwise a deterministic parser); the controls decide.</p>
      <textarea className="json-edit paste" value={value} onChange={(e) => setText(e.target.value)} spellCheck={false} />
      <div className="row-gap apply">
        <button className="btn primary" disabled={!value.trim()} onClick={async () => { const ok = await post({ kind: "text", text: value }); if (ok) goLive(); }}>Send to Bills</button>
        <button className="btn" onClick={() => setText(null)}>Reset example</button>
      </div>
    </Card>
  );
}

function Report({ post, goLive }: { post: (b: Record<string, unknown>) => Promise<boolean>; goLive: () => void }) {
  const [text, setText] = useState("");
  const [from, setFrom] = useState("Judge");
  const send = async (body: Record<string, unknown>) => { const ok = await post(body); if (ok) goLive(); };
  return (
    <Card title="Report" className="span2">
      <p className="big">Any event. The crew decides (the preset buttons show who usually answers); anything no catalog action covers reaches the commander.</p>
      <textarea className="json-edit" style={{ minHeight: 90 }} placeholder="e.g. The greenhouse irrigation line has a leak and we are losing water." value={text} onChange={(e) => setText(e.target.value)} />
      <div className="row-gap apply">
        <label className="field"><span>From</span><input className="in" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <button className="btn primary" disabled={!text.trim()} onClick={() => void send({ kind: "report", text, from: from.trim() || "Judge" })}>Send to the agents</button>
      </div>
      <div className="row-gap preset-row">
        <button className="btn" onClick={() => void send({ kind: "report", preset: "pump" })}>Broken water pump → Life</button>
        <button className="btn" onClick={() => void send({ kind: "report", preset: "injury" })}>Crew injury → Life</button>
        <button className="btn" onClick={() => void send({ kind: "report", preset: "bankruptcy" })}>Supplier bankruptcy → Rules</button>
      </div>
    </Card>
  );
}
