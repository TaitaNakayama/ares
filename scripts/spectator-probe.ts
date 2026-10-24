// Checks the spectator relay rules against the running server (node scripts/spectator-probe.ts):
// only the token-authenticated headset's pose reaches spectators; nothing on the Mac can steer it.
import { readFileSync } from "node:fs";

const BASE = "ws://127.0.0.1:8787/";
const token = readFileSync(new URL("../.cache/headset-token", import.meta.url), "utf8").trim();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function open(query: string): Promise<{ ws: WebSocket; got: Record<string, unknown>[] }> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(BASE + query);
    const got: Record<string, unknown>[] = [];
    ws.onmessage = (ev) => got.push(JSON.parse(String(ev.data)));
    ws.onopen = () => resolve({ ws, got });
    ws.onerror = () => reject(new Error(`cannot open ${query}`));
  });
}

const poses = (got: Record<string, unknown>[], tag: string) => got.filter((m) => m.type === "vr_pose" && m.tag === tag).length;
let failures = 0;
function check(name: string, ok: boolean): void {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`);
  if (!ok) failures++;
}

const spec = await open("?client=spectator");
const spec2 = await open("?client=spectator");
await sleep(300);
const hello = spec.got.find((m) => m.type === "hello");
check("spectator gets hello with vr state and headset status", !!hello?.vr && typeof hello?.headset === "boolean");
check("spectator is not sent the engine firehose", !spec.got.some((m) => m.type === "engine" || m.type === "telemetry"));

const fake = await open("?client=vr");
fake.ws.send(JSON.stringify({ type: "vr_pose", tag: "untokened", q: [0, 0, 0, 1] }));
const head = await open(`?client=vr&t=${token}`);
await sleep(200);
check("headset connect is announced", spec.got.some((m) => m.type === "headset" && m.connected === true));
head.ws.send(JSON.stringify({ type: "vr_pose", tag: "headset", q: [0, 0.38268, 0, 0.92388], gaze: 1 }));
head.ws.send(JSON.stringify({ type: "vr_pose", tag: "bad", q: [0, 0, 1] }));
head.ws.send(JSON.stringify({ type: "vr_pose", tag: "bad", q: [0, 0, 5, 1] }));
fake.ws.send(JSON.stringify({ type: "vr_pose", tag: "untokened", q: [0, 0, 0, 1] }));
spec.ws.send(JSON.stringify({ type: "vr_pose", tag: "spectator", q: [0, 0, 0, 1] }));
spec.ws.send(JSON.stringify({ type: "decide", escalationId: "ESC-0001", optionId: "wait" }));
await sleep(400);
check("authenticated headset pose reaches spectators", poses(spec.got, "headset") === 1 && poses(spec2.got, "headset") === 1);
check("malformed pose is dropped", poses(spec.got, "bad") === 0);
check("a loopback 'vr' socket without the token cannot steer the view", poses(spec.got, "untokened") === 0 && poses(spec2.got, "untokened") === 0);
check("a spectator cannot steer the view", poses(spec2.got, "spectator") === 0);
check("a spectator cannot decide", !spec.got.some((m) => m.type === "decided" || m.type === "error"));
check("the console does not receive head poses", poses(fake.got, "headset") === 0);

head.ws.close();
await sleep(300);
const last = spec.got.filter((m) => m.type === "headset").at(-1);
console.log(`after the probe headset left: headset connected = ${String(last?.connected)} (true only if the real headset is online)`);
for (const c of [spec, spec2, fake]) c.ws.close();
await sleep(100);
console.log(failures ? `${failures} FAILED` : "all passed");
process.exit(failures ? 1 : 0);
