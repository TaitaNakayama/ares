import { useCallback, useEffect, useRef, useState } from "react";
import { api, type AppState, type Narration, type Vr } from "./lib";

export function useAres() {
  const [state, setState] = useState<AppState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [live, setLive] = useState(false);
  const [vr, setVr] = useState<Vr | null>(null);
  const [extra, setExtra] = useState<Narration[]>([]);
  const [thinking, setThinking] = useState<string[]>([]);
  const timer = useRef<number | undefined>(undefined);

  const refresh = useCallback(async () => {
    try {
      const s = await api<AppState>("/api/state");
      setState(s);
      setVr(s.vr);
      setThinking(s.thinking ?? []);
      setExtra([]);
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  const refreshSoon = useCallback(() => {
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void refresh(), 250);
  }, [refresh]);

  useEffect(() => {
    void refresh();
    const id = window.setInterval(() => void refresh(), 1500);
    return () => window.clearInterval(id);
  }, [refresh]);

  useEffect(() => {
    let ws: WebSocket | undefined;
    let closed = false;
    let retry: number | undefined;
    const connect = () => {
      const proto = location.protocol === "https:" ? "wss" : "ws";
      const url = location.port === "5173" ? `${proto}://${location.host}/ws` : `${proto}://${location.host}/`;
      ws = new WebSocket(url);
      ws.onopen = () => setLive(true);
      ws.onclose = () => {
        setLive(false);
        if (!closed) retry = window.setTimeout(connect, 1500);
      };
      ws.onmessage = (ev) => {
        let m: { type: string; narration?: Narration; state?: Vr; role?: string; on?: boolean };
        try { m = JSON.parse(String(ev.data)); } catch { return; }
        if (m.type === "narration" && m.narration) {
          const n = m.narration;
          setExtra((x) => (x.some((y) => y.seq === n.seq) ? x : [...x, n]));
        } else if (m.type === "vr_state" && m.state) setVr(m.state);
        else if (m.type === "thinking" && m.role) {
          const role = m.role;
          setThinking((t) => (m.on ? (t.includes(role) ? t : [...t, role]) : t.filter((r) => r !== role)));
        } else if (m.type === "agent_mode") { setThinking([]); refreshSoon(); }
        else if (m.type === "engine") refreshSoon();
        else if (m.type === "reset") { setExtra([]); void refresh(); }
        else if (m.type === "hello") refreshSoon();
      };
    };
    connect();
    return () => { closed = true; window.clearTimeout(retry); ws?.close(); };
  }, [refresh, refreshSoon]);

  const narration = state ? mergeNarration(state.narration, extra) : [];
  return { state, vr, narration, thinking, error, live, refresh };
}

function mergeNarration(base: Narration[], extra: Narration[]): Narration[] {
  const seen = new Set(base.map((n) => n.seq));
  return [...base, ...extra.filter((n) => !seen.has(n.seq))];
}
