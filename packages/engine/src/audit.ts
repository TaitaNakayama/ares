import type { Time } from "./types.ts";
import { canonicalJson, sha256 } from "./util.ts";

export type AuditKind =
  | "document"
  | "proposal"
  | "decision"
  | "execution"
  | "escalation"
  | "verification"
  | "message"
  | "policy"
  | "lever";

export interface AuditRecord {
  seq: number;
  at: Time;
  kind: AuditKind;
  actorId: string;
  /** Short plain-language summary for the console and VR screens. */
  summary: string;
  data: unknown;
  prevHash: string;
  hash: string;
}

/** Append-only, hash-chained log of everything that happened and why. */
export class AuditLog {
  private readonly records: AuditRecord[] = [];

  append(at: Time, kind: AuditKind, actorId: string, summary: string, data: unknown): AuditRecord {
    const prevHash = this.records.at(-1)?.hash ?? "genesis";
    // Snapshot the data: callers keep mutating their records, and the hash must stay valid.
    const body = { seq: this.records.length + 1, at, kind, actorId, summary, data: structuredClone(data), prevHash };
    const rec: AuditRecord = { ...body, hash: sha256(canonicalJson(body)) };
    this.records.push(rec);
    return rec;
  }

  all(): readonly AuditRecord[] {
    return this.records;
  }

  since(seq: number): readonly AuditRecord[] {
    return this.records.slice(seq);
  }

  verify(): { ok: boolean; problems: string[] } {
    const problems: string[] = [];
    let prev = "genesis";
    for (const r of this.records) {
      if (r.prevHash !== prev) problems.push(`audit #${r.seq} breaks the chain`);
      const { hash, ...body } = r;
      if (sha256(canonicalJson(body)) !== hash) problems.push(`audit #${r.seq} tampered`);
      prev = r.hash;
    }
    return { ok: problems.length === 0, problems };
  }
}
