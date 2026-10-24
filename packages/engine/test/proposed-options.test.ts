import { describe, expect, it } from "vitest";
import { bankAFake, bankB, makeEngine, requisitionWithQuotes, T0 } from "./fixtures.ts";

/**
 * Decision options can come from the escalating agent, not only from the engine's fixed list.
 * Each proposed option's action is dry-run through policy as the deciding human; illegal ones vanish.
 */
describe("agent-proposed escalation options", () => {
  function setup() {
    const e = makeEngine();
    // Order-by in 10 minutes: Earth can't answer in time, so the site commander decides.
    const { reqId, quoteIds } = requisitionWithQuotes(
      e,
      "FLT",
      10,
      [
        { vendorId: "V-A", unitPrice: 12_000, qtyAvailable: 100, bank: bankB }, // bank differs from master: flagged
        { vendorId: "V-A", unitPrice: 12_500, qtyAvailable: 4, bank: { ...bankAFake, holder: "x" } },
      ],
      T0 + 10 * 60_000,
    );
    return { e, reqId, flagged: quoteIds[0]!, other: quoteIds[1]! };
  }

  it("keeps options that pass policy for the commander, drops the rest, and the choice executes", () => {
    const { e, reqId, flagged } = setup();
    const res = e.submit({
      actorId: "ctl",
      type: "escalate",
      params: {
        subject: { kind: "requisition", id: reqId },
        reason: "Bank details on the quote differ from the master.",
        options: [
          { label: "Reject this request for now", action: { type: "reject_requisition", params: { requisitionId: reqId, reason: "wait for a clean quote" } } },
          { label: "Buy from the flagged quote anyway", action: { type: "approve_requisition", params: { requisitionId: reqId, quoteId: flagged } } },
          { label: "Ask Earth for guidance by voice", detail: "No system action; the commander calls Earth." },
          { label: "Something impossible", action: { type: "release_vendor", params: { vendorId: "V-A", reason: "x" } } },
        ],
      },
    });
    expect(res.decision.verdict).toBe("allow");
    const esc = e.escalations.get(res.created!.id)!;
    expect(esc.to).toBe("local_authority");
    const agent = esc.options.filter((o) => o.proposedBy === "ctl");
    expect(agent.map((o) => o.label)).toEqual(["Reject this request for now", "Ask Earth for guidance by voice"]);
    expect(esc.options.some((o) => o.id === "reject")).toBe(true); // the standard options stay
    expect(esc.options.every((o) => o.withinAuthority)).toBe(true);
    // The flagged-quote option never reached the human.
    expect(esc.options.some((o) => o.actions.some((a) => (a.params as { quoteId?: string }).quoteId === flagged))).toBe(false);

    const d = e.submit({ actorId: "loc", type: "decide", params: { escalationId: esc.id, optionId: agent[0]!.id } });
    expect(d.decision.verdict).toBe("allow");
    expect(e.requisitions.get(reqId)!.status).toBe("rejected");
    expect(esc.status).toBe("decided");
  });

  it("a proposed option that duplicates a standard one is not listed twice, and more than three are cut", () => {
    const { e, reqId } = setup();
    const res = e.submit({
      actorId: "ctl",
      type: "escalate",
      params: {
        subject: { kind: "requisition", id: reqId },
        reason: "r",
        options: [
          { label: "Reject", action: { type: "reject_requisition", params: { requisitionId: reqId, reason: "rejected by authority" } } },
          { label: "A" }, { label: "B" }, { label: "C" },
        ],
      },
    });
    const esc = e.escalations.get(res.created!.id)!;
    expect(esc.options.filter((o) => o.actions.some((a) => a.type === "reject_requisition"))).toHaveLength(1);
    expect(esc.options.filter((o) => o.proposedBy).map((o) => o.label)).toEqual(["A", "B"]);
  });
});
