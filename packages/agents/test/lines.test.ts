import { describe, expect, it } from "vitest";
import { checkSpoken, holdMsFor, numbersIn, speak, type LlmProvider } from "../src/index.ts";

/** The spoken-line rules: at most 10 words, no semicolons, at most one number, numbers from the facts. */
describe("spoken lines", () => {
  const facts = "Water reserve 9 days. Earth round trip 25 minutes. Delivered 34 of 36, 2 missing.";
  it("accepts the script's target lines", () => {
    for (const l of ["Welcome, Commander. The crew has the base.", "Two crates missing. I won't pay for those.", "I've asked Earth to check. That takes 25 minutes.", "Air is safe. Water lasts nine more days.", "This quote is triple the normal price.", "We can't wait, Commander. What do we give up?"]) {
      expect(checkSpoken(l, facts), l).toBe("ok");
    }
  });
  it("rejects long lines, semicolons, two numbers and invented numbers", () => {
    expect(checkSpoken("The storm is coming and we really need to get you inside right now", facts)).toMatch(/words/);
    expect(checkSpoken("Payment blocked; Earth is checking.", facts)).toBe("semicolon");
    expect(checkSpoken("34 arrived, 2 missing.", facts)).toMatch(/2 numbers/);
    expect(checkSpoken("Water lasts 12 more days.", facts)).toMatch(/not in the facts/);
  });
  it("never lets a provider note or markup into a bubble", () => {
    expect(checkSpoken("[incomplete: max_output_tokens]", facts)).toBe("not speech");
    expect(checkSpoken("Ask <rules> about quote_7", facts)).toBe("not speech");
    expect(checkSpoken("Storm's passing. We made it, Commander.", facts)).toBe("ok");
  });
  it("counts number words and digits", () => {
    expect(numbersIn("nine days and 25 minutes").length).toBe(2);
    expect(holdMsFor("Dust storm incoming.")).toBe(4000 + 3 * 600);
  });
  it("speak: a rule-breaking answer gets one shorter retry, then the target line", async () => {
    const answers = ["The batteries we found on Earth cost three times the usual amount; scam", "Too long again, this line is still far too long for the rule"];
    const llm: LlmProvider = { name: "fake", model: "f", async complete() { return { text: "", toolCalls: [{ name: "say", args: { text: answers.shift() } }], cached: false, model: "f" }; } };
    const out = await speak(llm, { name: "Supply", persona: "cargo", to: "Rules", intent: "the quote is triple", facts, target: "This quote is triple the normal price." });
    expect(out.via).toBe("rules");
    expect(out.text).toBe("This quote is triple the normal price.");
    const good: LlmProvider = { name: "fake", model: "f", async complete() { return { text: "", toolCalls: [{ name: "say", args: { text: "Triple the usual price. Something's off." } }], cached: false, model: "f" }; } };
    const ok = await speak(good, { name: "Supply", persona: "cargo", to: "Rules", intent: "the quote is triple", facts, target: "This quote is triple the normal price." });
    expect(ok.via).toBe("llm");
  });
});
