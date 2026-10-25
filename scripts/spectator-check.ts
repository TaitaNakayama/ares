// Checks the Mac spectator against a live show with a stand-in headset (scripts/fake-headset.ts) sweeping its head:
// the view stays LIVE, the camera follows the head, the decision card leaves after the choice, subtitles don't linger.
//   node scripts/spectator-check.ts [--choice drill] [--secs 230] [--pattern sweep] [--json out.json]
// Needs the server on :8787 (or ARES_URL) and the spectator running (scripts/build-spectator.sh --director).
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => (args.includes(k) ? args[args.indexOf(k) + 1]! : d);
const CHOICE = opt("--choice", "drill");
const SECS = Number(opt("--secs", "230"));
const PATTERN = opt("--pattern", "sweep");
const OUT = opt("--json", "");
/** --real: the phone is the headset (no stand-in); the camera is still compared with the pose it streams. */
const REAL = args.includes("--real");
/** --observe: don't start anything; watch a show someone else runs (a judge in the headset). */
const OBSERVE = args.includes("--observe");
const BASE = process.env.ARES_URL ?? "http://localhost:8787";

const get = async (p: string) => (await fetch(`${BASE}${p}`)).json() as Promise<any>;
const post = async (p: string, body: unknown) => (await fetch(`${BASE}${p}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })).json();
const angle = (a: number) => ((((a + 180) % 360) + 360) % 360) - 180;

await fetch(`${BASE}/api/debug/pose`, { method: "DELETE" });
const head = REAL ? undefined : spawn(process.execPath, [new URL("./fake-headset.ts", import.meta.url).pathname, "--secs", String(SECS + 10), "--pattern", PATTERN], { stdio: "ignore", env: { ...process.env, ARES_URL: BASE } });
await new Promise((r) => setTimeout(r, 1500));
if (!OBSERVE) await post("/api/show/autoplay", { choice: CHOICE });
const t0 = Date.now();

type Sample = { t: number; act: string; mode: string; yawErr: number | null; pitchErr: number | null; flips: number; poseAge: number; subtitle: string; card: boolean; speaking: string | null; chosen: boolean; title: string | null; seenTitle: string; bubbleMaxStep: number; bubbleJumps: number; tagSwitches: Record<string, number>; longFrames: number };
const samples: Sample[] = [];
let lastStatsAt = "";
while ((Date.now() - t0) / 1000 < SECS) {
  await new Promise((r) => setTimeout(r, 250));
  const [st, log] = await Promise.all([get("/api/spectator/stats"), get("/api/show/log")]);
  if (st.receivedAt === lastStatsAt) continue; // the spectator reports every 0.5 s
  lastStatsAt = st.receivedAt;
  const d = st.diag ?? {};
  const live = st.mode === "live";
  const sp = log.show?.speaking;
  samples.push({
    t: (Date.now() - t0) / 1000,
    act: log.act,
    mode: st.mode,
    yawErr: live && d.cam && d.pose ? angle(d.cam[0] - d.pose[0]) : null,
    pitchErr: live && d.cam && d.pose ? d.cam[1] - d.pose[1] : null,
    flips: d.modeFlips ?? 0,
    poseAge: d.maxPoseAgeMs ?? 0,
    subtitle: (st.subtitles ?? [])[0] ?? "",
    card: !!st.card,
    speaking: sp?.text ?? null,
    chosen: !!log.show?.decision?.chosen,
    title: log.show?.scene?.title?.style ?? null,
    seenTitle: d.title ?? "",
    bubbleMaxStep: d.bubbleMaxStep ?? 0,
    bubbleJumps: d.bubbleJumps ?? 0,
    tagSwitches: d.tagSwitches ?? {},
    longFrames: d.longFrames ?? 0,
  });
  if (log.act === "explore" && (Date.now() - t0) / 1000 > 60 && samples.filter((s) => s.act === "explore").length > 30) break;
}
head?.kill();

const live = samples.filter((s) => s.mode === "live");
const errs = live.map((s) => Math.abs(s.yawErr ?? 0)).sort((a, b) => a - b);
const pct = (xs: number[], p: number) => (xs.length ? xs[Math.min(xs.length - 1, Math.floor(p * xs.length))]! : NaN);
// The card shows the choice for 3.5 s and must be gone by 4.5 s.
const chosenAt = samples.find((s) => s.chosen)?.t;
const cardLate = chosenAt === undefined ? [] : samples.filter((s) => s.t > chosenAt + 4.5 && s.card);
// A subtitle must match the line being spoken (or be gone within ~2 s of the server's line ending).
const stale = samples.filter((s, i) => s.subtitle && s.speaking && s.subtitle !== s.speaking && samples[i - 1]?.speaking === s.speaking);
// Judged on what the spectator itself saw at that moment (its own title), not the server's newer state.
const underTitle = samples.filter((s) => (s.seenTitle === "window" || s.seenTitle === "end") && s.subtitle);
const jumps = samples.reduce((n, s) => n + s.bubbleJumps, 0);
const tagMoves = samples.reduce((n, s) => n + Object.values(s.tagSwitches).reduce((a, b) => a + b, 0), 0);
// Flicker: the same robot's tag changing height twice within 4 s.
const tagTimes = new Map<string, number[]>();
for (const s of samples) for (const [id, n] of Object.entries(s.tagSwitches)) for (let k = 0; k < n; k++) tagTimes.set(id, [...(tagTimes.get(id) ?? []), s.t]);
const flicker = [...tagTimes].flatMap(([id, ts]) => ts.slice(1).filter((t, i) => t - ts[i]! < 4).map((t) => `${id}@${t.toFixed(1)}s`));
const checks: Record<string, boolean> = {
  "LIVE the whole show (≥98% of samples)": live.length >= 0.98 * samples.length,
  "no LIVE drop-outs (mode flips 0)": samples.every((s) => s.flips === 0),
  "pose never older than 300 ms": samples.every((s) => s.poseAge < 300),
  "camera follows the head (p95 yaw error ≤ 6°)": pct(errs, 0.95) <= 6,
  "decision card gone ≤ 4.5 s after the choice": chosenAt !== undefined && cardLate.length === 0,
  "subtitle always the current line": stale.length === 0,
  "no subtitle under a window/end card": underTitle.length === 0,
  "bubbles never hop within a line (0 frames > 8 cm)": jumps === 0,
  "no nametag flicker (same robot twice within 4 s)": flicker.length === 0,
};
console.log(`${samples.length} samples over ${(samples.at(-1)?.t ?? 0).toFixed(0)} s; LIVE ${live.length}; yaw error p50 ${pct(errs, 0.5).toFixed(1)}°, p95 ${pct(errs, 0.95).toFixed(1)}°, max ${(errs.at(-1) ?? NaN).toFixed(1)}°`);
const byAct = new Map<string, number[]>();
for (const s of live) byAct.set(s.act, [...(byAct.get(s.act) ?? []), Math.abs(s.yawErr ?? 0)]);
for (const [a, xs] of byAct) console.log(`  ${a.padEnd(11)} p95 yaw error ${pct(xs.sort((x, y) => x - y), 0.95).toFixed(1)}° (${xs.length} samples)`);
if (cardLate.length) console.log(`  card still up at ${cardLate.map((s) => s.t.toFixed(1)).slice(0, 5).join(", ")} s (chosen at ${chosenAt?.toFixed(1)} s)`);
if (stale.length) console.log(`  stale subtitles: ${stale.slice(0, 3).map((s) => `"${s.subtitle}" while "${s.speaking}"`).join(" | ")}`);
const nonLive = samples.filter((s) => s.mode !== "live");
if (nonLive.length) console.log(`  not LIVE at ${nonLive.slice(0, 8).map((s) => `${s.t.toFixed(1)}s(${s.mode})`).join(" ")}`);
console.log(`  long frames while a bubble was up (> 33 ms): ${samples.reduce((n, s) => n + s.longFrames, 0)}`);
console.log(`  bubble hops ${jumps}, largest bubble step ${Math.max(0, ...samples.map((s) => s.bubbleMaxStep)).toFixed(3)} m; nametag height changes ${tagMoves} (${[...tagTimes].map(([id, ts]) => `${id} ${ts.length}`).join(", ")})${flicker.length ? `; flicker ${flicker.join(" ")}` : ""}`);
console.log("pose relay:", JSON.stringify(await get("/api/debug/pose")));
for (const [k, v] of Object.entries(checks)) console.log(`  ${v ? "PASS" : "FAIL"}  ${k}`);
if (OUT) writeFileSync(OUT, JSON.stringify({ checks, samples }, null, 1));
process.exit(Object.values(checks).every(Boolean) ? 0 : 1);
