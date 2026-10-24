import type { ReactNode } from "react";
import { ROLE_COLORS, ROLE_NAMES } from "../lib";

export function RoleChip({ role, name }: { role: string; name?: string }) {
  const c = ROLE_COLORS[role] ?? "var(--muted)";
  return (
    <span className="chip" style={{ color: c, borderColor: c }}>
      <i style={{ background: c }} />
      {name ?? ROLE_NAMES[role] ?? role}
    </span>
  );
}

export function Outcome({ o }: { o: string }) {
  const label: Record<string, string> = { allow: "ALLOWED", hold: "HELD", escalate: "ESCALATED", deny: "REFUSED BY POLICY", said: "SAID" };
  return <span className={`badge ${o}`}>{label[o] ?? o}</span>;
}

export function Card({ title, right, children, className = "" }: { title?: ReactNode; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`card ${className}`}>
      {(title || right) && (
        <div className="card-h">
          <h2>{title}</h2>
          {right}
        </div>
      )}
      {children}
    </section>
  );
}

export function Hash({ h }: { h: string }) {
  return <code className="hash" title={h}>{h.slice(0, 8)}</code>;
}
