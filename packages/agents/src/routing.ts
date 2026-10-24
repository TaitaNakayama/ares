import type { AgentRole } from "@ares/engine";
import type { ModelRouter } from "./router.ts";

/**
 * Which agent a free-text report goes to. Keyword routing is the deterministic default;
 * `llmRoute` asks the model with one tiny tool and falls back to the keywords.
 */
export function keywordRoute(text: string): AgentRole {
  const t = text.toLowerCase();
  if (/\b(supplier|vendor|bankrupt|insolven|bank account|invoice|quote|fraud|price)/.test(t)) return "controller";
  if (/\b(deliver|arriv|crate|manifest|pallet|cargo|count|damaged|missing)/.test(t)) return "receiver";
  if (/\b(cash|budget|payment|pay |runway|afford)/.test(t)) return "treasury";
  return "requester";
}

const ROLES: AgentRole[] = ["requester", "receiver", "ap", "treasury", "controller"];

export function llmRoute(router: ModelRouter, timeoutMs = 6_000): (text: string) => Promise<AgentRole> {
  return async (text) => {
    try {
      const res = await router.complete(
        {
          system: "Route an incoming report to the one agent whose job it is. requester = Engineer: base operations, broken or failing equipment, water, power, crew needs, anything to buy (even when suppliers or prices are mentioned). receiver = Cargo: deliveries, counts, damaged or missing goods. ap = Bills: invoices and documents. treasury = Money: cash, payments, budget. controller = Rules: a supplier's own status or conduct (bankruptcy, fraud, changed bank details), approvals. Call route exactly once.",
          user: text.slice(0, 1500),
          tools: [{ name: "route", description: "Pick the agent.", parameters: { type: "object", required: ["role"], properties: { role: { type: "string", enum: ROLES } } } }],
          maxOutputTokens: 40,
        },
        { localTimeoutMs: timeoutMs, cloudTimeoutMs: timeoutMs },
      );
      const role = (res.toolCalls.find((c) => c.name === "route")?.args as { role?: string } | undefined)?.role;
      if (role && (ROLES as string[]).includes(role)) return role as AgentRole;
    } catch {
      // keyword fallback below
    }
    return keywordRoute(text);
  };
}
