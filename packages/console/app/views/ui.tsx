import type { ReactNode } from "react";
import { crewOf, ROLE_COLORS, ROLE_NAMES, ROLE_TITLES } from "../lib";

/** Crew chip. `actorId` (preferred) or `role` picks the crew member; `showRole` adds Supply's sub-role (Receiving / Bills / Payments). */
export function RoleChip({ role, actorId, name, showRole }: { role: string; actorId?: string; name?: string; showRole?: boolean }) {
  const crew = crewOf(actorId, role);
  const c = crew?.color ?? ROLE_COLORS[role] ?? "var(--muted)";
  let label: string;
  if (crew) {
    label = crew.sub && showRole ? `${crew.name} · ${crew.sub}` : crew.name;
  } else {
    label = (name ?? ROLE_NAMES[role] ?? role) + (showRole && ROLE_TITLES[role] ? ` · ${ROLE_TITLES[role]}` : "");
  }
  return (
    <span className="chip" style={{ color: c, borderColor: c }}>
      <i style={{ background: c }} />
      {label}
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
