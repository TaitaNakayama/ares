import type { LlmProvider } from "./llm.ts";
import type { ModelRouter } from "./router.ts";

/**
 * Spoken lines (the headset's speech bubbles and the spectator's subtitles). Text rules, everywhere:
 * at most 10 words, no semicolons, at most one number (digits or number words), plain crewmate speech,
 * and every number must be one the engine or the world provided. A line that breaks a rule gets one
 * retry asking for shorter; then the scripted target line is said instead (labelled `rules`).
 */

export const MAX_WORDS = 10;

const NUMBER_WORDS: Record<string, number> = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
  twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90, hundred: 100, thousand: 1000, million: 1e6,
  half: 0.5, double: 2, twice: 2, triple: 3, thrice: 3, dozen: 12,
};

const words = (line: string) => line.trim().split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w));

/** Numbers a line states: digit groups (with $, %, decimals, k/M suffixes) and number words. */
export function numbersIn(line: string): { token: string; value?: number }[] {
  const out: { token: string; value?: number }[] = [];
  for (const m of line.matchAll(/\$?\d[\d,]*(?:\.\d+)?\s?(?:k|K|M|B|%)?/g)) {
    const raw = m[0];
    const n = Number(raw.replace(/[$,%kKMB\s]/g, ""));
    const mult = /k|K/.test(raw) ? 1e3 : /M/.test(raw) ? 1e6 : /B/.test(raw) ? 1e9 : 1;
    out.push({ token: raw.trim(), value: Number.isFinite(n) ? n * mult : undefined });
  }
  for (const w of words(line)) {
    const k = w.toLowerCase().replace(/[^a-z]/g, "");
    if (k in NUMBER_WORDS) out.push({ token: k, value: NUMBER_WORDS[k] });
  }
  return out;
}

/** Rule check for a spoken line. `facts` is the text the line may draw numbers from. */
export function checkSpoken(line: string, facts: string): "ok" | string {
  const t = line.trim();
  if (!t) return "empty";
  const n = words(t).length;
  if (n > MAX_WORDS) return `${n} words (max ${MAX_WORDS})`;
  if (t.includes(";")) return "semicolon";
  if (/\n|```|\*\*|#{1,6}\s|^[-*]\s/.test(t)) return "markdown";
  // Provider notes ("[incomplete: max_output_tokens]"), tags and code never reach a speech bubble.
  if (/[\[\]{}<>_|\\]/.test(t)) return "not speech";
  if (/\b(as an ai|language model|as an assistant|i cannot|i'm sorry)\b/i.test(t)) return "out of character";
  const nums = numbersIn(t);
  if (nums.length > 1) return `${nums.length} numbers (max 1)`;
  // A number must be one the facts give (digits or the same value written out). Multipliers (triple, double, half) are judged by meaning, not checked here.
  const have = new Set<number>(numbersIn(facts).map((x) => x.value).filter((v): v is number => v !== undefined));
  for (const x of nums) {
    if (x.value === undefined || ["half", "double", "twice", "triple", "thrice"].includes(x.token)) continue;
    const ok = [...have].some((v) => Math.abs(v - x.value!) < 0.5 || Math.abs(v - x.value!) / Math.max(1, Math.abs(v)) < 0.06);
    if (!ok) return `number ${x.token} not in the facts`;
  }
  return "ok";
}

export function wordCount(line: string): number {
  return words(line).length;
}

/** How long a line stays up at least: 4 s plus 0.6 s per word (judges read slower than we do). */
export function holdMsFor(line: string): number {
  return 4000 + 600 * wordCount(line);
}

export interface SpeakRequest {
  /** Crew member's name and what they do (the persona). */
  name: string;
  persona: string;
  /** Who it's said to: "the commander", or another crew member's name. */
  to: string;
  /** What the line must say (the scripted beat), in plain words. */
  intent: string;
  /** Facts the line may use (code-written from engine and world state). */
  facts: string;
  /** The scripted target line: said if the model fails (it must itself pass the rules). */
  target: string;
}

export interface Spoken {
  text: string;
  via: "llm" | "rules";
  /** The model's words replayed from the on-disk response cache (an identical request was answered before). */
  cached?: boolean;
  reason?: string;
  ms: number;
}

const sayTool = {
  name: "say",
  description: "Say one short spoken line.",
  parameters: { type: "object", required: ["text"], properties: { text: { type: "string", description: "At most 10 words, no semicolons, at most one number." } } },
};

/** One spoken line from a crew member: the model's words under the text rules, or the target line. */
export async function speak(llm: LlmProvider | ModelRouter | undefined, req: SpeakRequest, opts: { deadlineMs?: number } = {}): Promise<Spoken> {
  const t0 = Date.now();
  const fallback = (reason: string): Spoken => ({ text: req.target, via: "rules", reason, ms: Date.now() - t0 });
  const router = llm as ModelRouter | undefined;
  if (!llm || (router && "mode" in router && router.mode === "rules")) return fallback("rules mode");
  const deadline = t0 + (opts.deadlineMs ?? 6000);
  const system = `You are ${req.name}, one of five robots in the AI crew that runs a base on Mars (${req.persona}). You speak out loud to ${req.to}. Talk like a calm, competent crewmate: short, warm, plain words. HARD RULES: at most 10 words (5 to 8 is best), no semicolons, at most one number, no lists, no markdown. Use only the facts given; never invent a number, a name or a place. Call the say tool once.`;
  let user = `FACTS:\n${req.facts}\n\nSay this, in your own words: ${req.intent}\n(For example: "${req.target}")`;
  for (let attempt = 0; attempt < 2; attempt++) {
    const left = deadline - Date.now();
    if (left < 800) return fallback("deadline");
    try {
      const call = llm.complete({ system, user, tools: [sayTool], maxOutputTokens: 300 });
      const res = await Promise.race([call, new Promise<never>((_, rej) => setTimeout(() => rej(new Error("deadline")), left))]);
      const said = (res.toolCalls.find((c) => c.name === "say")?.args as { text?: string } | undefined)?.text;
      // Only a say call counts: provider notes ("[incomplete: …]") or prose are not a line.
      if (typeof said !== "string") {
        if (attempt === 1) return fallback(`no say call${res.text ? `: ${res.text.slice(0, 60)}` : ""}`);
        continue;
      }
      const line = said.trim().replace(/^["“]|["”]$/g, "");
      const verdict = checkSpoken(line, `${req.facts}\n${req.target}`);
      if (verdict === "ok") return { text: line, via: "llm", ...(res.cached ? { cached: true } : {}), ms: Date.now() - t0 };
      user = `${user}\n\nYour line "${line}" broke a rule (${verdict}). Say it again, shorter: at most 10 words, at most one number, no semicolons.`;
      if (attempt === 1) return fallback(`rule: ${verdict}`);
    } catch (err) {
      return fallback((err as Error).message);
    }
  }
  return fallback("no line");
}
