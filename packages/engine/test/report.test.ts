import { describe, expect, it } from "vitest";
import { makeEngine } from "./fixtures.ts";

/**
 * report_issue: something no catalog action covers (a broken pump, an injury) always reaches
 * the human on site as an escalation with the agent's recommendation, whoever reports it.
 */
describe("report_issue", () => {
  it("any agent role can report, and the report goes to the local authority immediately", () => {
    const e = makeEngine();
    for (const actorId of ["req", "rcv", "ap", "tre", "ctl"]) {
      const r = e.submit({ actorId, type: "report_issue", params: { summary: `Water pump broken (${actorId})`, recommendation: "Buy the used pump; verify the supplier first.", urgency: "high" } });
      expect(r.decision.verdict).toBe("allow");
      expect(r.created?.kind).toBe("escalation");
      const esc = e.escalations.get(r.created!.id)!;
      expect(esc.to).toBe("local_authority");
      expect(esc.status).toBe("awaiting_decision");
      expect(esc.subject.kind).toBe("report");
      expect(esc.message).toBe("Buy the used pump; verify the supplier first.");
      expect(esc.options.map((o) => o.id)).toEqual(["approve", "dismiss"]);
    }
    expect(e.reports.size).toBe(5);
  });

  it("the commander's choice is recorded and settles the report; nothing is paid", () => {
    const e = makeEngine();
    const r = e.submit({ actorId: "req", type: "report_issue", params: { summary: "Pump down", recommendation: "Order the new pump.", urgency: "critical" } });
    const esc = e.escalations.get(r.created!.id)!;
    const cash = e.ledger.balance("cash");
    const d = e.submit({ actorId: "loc", type: "decide", params: { escalationId: esc.id, optionId: "approve" } });
    expect(d.decision.verdict).toBe("allow");
    expect(esc.status).toBe("decided");
    expect(esc.decision?.optionId).toBe("approve");
    expect(e.ledger.balance("cash")).toBe(cash);
    // Earth cannot decide what was routed to the site.
    const e2 = makeEngine();
    const r2 = e2.submit({ actorId: "req", type: "report_issue", params: { summary: "Pump down", recommendation: "Order it.", urgency: "normal" } });
    const bad = e2.submit({ actorId: "rem", type: "decide", params: { escalationId: r2.created!.id, optionId: "approve" } });
    expect(bad.decision.verdict).toBe("deny");
  });

  it("a report about a record that doesn't exist is refused; humans don't report, they decide", () => {
    const e = makeEngine();
    const bad = e.submit({ actorId: "req", type: "report_issue", params: { summary: "x", recommendation: "y", urgency: "low", subject: { kind: "invoice", id: "INV-9999" } } });
    expect(bad.decision.verdict).toBe("deny");
    const human = e.submit({ actorId: "loc", type: "report_issue", params: { summary: "x", recommendation: "y", urgency: "low" } });
    expect(human.decision.verdict).toBe("deny");
  });
});
