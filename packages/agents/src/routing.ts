import type { ModelRouter } from "./router.ts";

/**
 * Which crew member a free-text report goes to (an engine role, or a crew actor id when the world has one:
 * `life` for air, water and crew health, `science` for the lab and samples). Keyword routing is the
 * deterministic default; `llmRoute` asks the model with one tiny tool and falls back to the keywords.
 */
export function keywordRoute(text: string, crew = false): string {
  const t = text.toLowerCase();
  if (crew && /\b(injur|hurt|fractur|medic|medicine|pain|sick|health|oxygen|o2|air |water|pump|recycler|breath)/.test(t)) return "life";
  if (crew && /\b(lab|sample|specimen|microscope|freezer|experiment|core|rock)/.test(t)) return "science";
  if (/\b(supplier|vendor|bankrupt|insolven|bank account|invoice|quote|fraud|price)/.test(t)) return "controller";
  if (/\b(deliver|arriv|crate|manifest|pallet|cargo|count|damaged|missing)/.test(t)) return "receiver";
  if (/\b(cash|budget|payment|pay |runway|afford)/.test(t)) return "treasury";
  return "requester";
}

const ROLES = ["requester", "receiver", "ap", "treasury", "controller"];
const CREW_TARGETS = ["life", "science"];

export function llmRoute(router: ModelRouter, timeoutMs = 6_000, crew = false): (text: string) => Promise<string> {
  const targets = crew ? [...ROLES, ...CREW_TARGETS] : ROLES;
  return async (text) => {
    try {
      const res = await router.complete(
        {
          system: `Route an incoming report to the one crew member whose job it is. requester = Engineer: power, solar panels, the ice drill, machines, anything to buy. ${crew ? "life = Life: oxygen, water, the water pump and recycler, crew health and injuries. science = Science: the lab, samples, research. " : ""}receiver = Supply (receiving): deliveries, counts, damaged or missing goods. ap = Supply (bills): invoices and documents. treasury = Supply (payments): cash, payments, budget. controller = Rules: a supplier's own status or conduct (bankruptcy, fraud, changed bank details), approvals. Call route exactly once.`,
          user: text.slice(0, 1500),
          tools: [{ name: "route", description: "Pick the crew member.", parameters: { type: "object", required: ["role"], properties: { role: { type: "string", enum: targets } } } }],
          maxOutputTokens: 60,
        },
        { localTimeoutMs: timeoutMs, cloudTimeoutMs: timeoutMs },
      );
      const role = (res.toolCalls.find((c) => c.name === "route")?.args as { role?: string } | undefined)?.role;
      if (role && targets.includes(role)) return role;
    } catch {
      // keyword fallback below
    }
    return keywordRoute(text, crew);
  };
}
