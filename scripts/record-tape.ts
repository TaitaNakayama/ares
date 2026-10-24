// Records offline replay tapes from the live server, one run per decision option.
// The headset plays these if it cannot reach any server (C-08 offline fallback).
//   node scripts/record-tape.ts [baseUrl]
import { writeFileSync, mkdirSync } from "node:fs";

const BASE = process.argv[2] ?? "http://localhost:8787";
const post = (p: string, body: unknown = {}) => fetch(BASE + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => r.json());
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Frame = { t: number; state: unknown };
async function record(choice: string): Promise<{ frames: Frame[]; decideAt: number; optionId: string }> {
  await post("/api/director/reset", {});
  await sleep(500);
  const ws = new WebSocket(BASE.replace(/^http/, "ws") + "/?client=vr");
  const frames: Frame[] = [];
  const t0 = Date.now();
  let latest: any;
  ws.addEventListener("message", (ev) => {
    const m = JSON.parse(String(ev.data));
    const st = m.type === "vr_state" ? m.state : m.type === "hello" ? m.vr : undefined;
    if (st) {
      latest = st;
      frames.push({ t: Date.now() - t0, state: st });
    }
  });
  await new Promise((r) => ws.addEventListener("open", r));
  await sleep(4000);
  // Part 1 outside: pad (beat 1), science, solar (beat 2 + storm warning), door, then inside.
  await post("/api/director/next"); // pad
  // Beat 1 with model-backed agents takes several decisions at a few seconds each: wait for the payments, up to 90 s.
  for (let i = 0; i < 180 && !((latest?.money?.payments?.length ?? 0) >= 2 && !(latest?.thinking?.length)); i++) await sleep(500);
  await sleep(3000);
  await post("/api/director/next"); // science
  await sleep(10000);
  await post("/api/director/next"); // solar + storm
  await sleep(8000);
  await post("/api/director/next"); // door
  await sleep(6000);
  await post("/api/director/enter");
  for (let i = 0; i < 400 && !(latest?.waiting?.length); i++) await sleep(500);
  if (!latest?.waiting?.length) throw new Error(`no escalation appeared (${frames.length} frames, beat ${latest?.beat})`);
  console.log(`  ${choice}: escalation after ${Math.round((Date.now() - t0) / 1000)} s`);
  await sleep(4000); // time to read the options
  const w = latest.waiting[0];
  const opt = w.options.find((o: any) => o.id.startsWith(choice)) ?? w.options[0];
  const decideAt = Date.now() - t0;
  ws.send(JSON.stringify({ type: "decide", escalationId: w.id, optionId: opt.id }));
  await sleep(26000);
  ws.close();
  return { frames, decideAt, optionId: opt.id };
}

const tape: { recordedAt: string; seed?: string; prefix: Frame[]; branches: Record<string, Frame[]> } = { recordedAt: new Date().toISOString(), prefix: [], branches: {} };
for (const choice of ["buy", "lever", "wait", "reject"]) {
  const r = await record(choice);
  const before = r.frames.filter((f) => f.t < r.decideAt);
  const after = r.frames.filter((f) => f.t >= r.decideAt).map((f) => ({ t: f.t - r.decideAt, state: f.state }));
  if (!tape.prefix.length) tape.prefix = before;
  tape.branches[r.optionId] = after;
  tape.seed = (r.frames[0]?.state as any)?.seed;
  console.log(`recorded ${choice}: prefix ${before.length} frames, branch ${after.length} frames (${r.optionId})`);
}
// Thin frames: keep at most ~4 per second, the app interpolates nothing so this is plenty.
const thin = (fs: Frame[]) => fs.filter((f, i) => i === 0 || i === fs.length - 1 || f.t - (fs[i - 1]?.t ?? 0) > 200);
tape.prefix = thin(tape.prefix);
for (const k of Object.keys(tape.branches)) tape.branches[k] = thin(tape.branches[k]!);
mkdirSync("vr/AresVR/Resources", { recursive: true });
writeFileSync("vr/AresVR/Resources/tape.json", JSON.stringify(tape));
console.log("wrote vr/AresVR/Resources/tape.json", Math.round(JSON.stringify(tape).length / 1024), "KB");
