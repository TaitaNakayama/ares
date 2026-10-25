// A stand-in headset for testing the Mac spectator's LIVE camera without the phone: connects as the
// authenticated headset and streams `vr_pose` at 30 Hz with a known head motion.
//   node scripts/fake-headset.ts [--secs 60] [--pattern sweep|still|look] [--yaw 0] [--pitch 0]
//   sweep: the head turns left and right (±50°, 10 s period) with a small nod; still: holds --yaw/--pitch.
// Prints the yaw it sent each second so a check can compare it with the spectator's camera (GET /api/spectator/stats).
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => (args.includes(k) ? args[args.indexOf(k) + 1]! : d);
const SECS = Number(opt("--secs", "60"));
const PATTERN = opt("--pattern", "sweep");
const YAW0 = Number(opt("--yaw", "0"));
const PITCH0 = Number(opt("--pitch", "0"));
const BASE = process.env.ARES_URL ?? "http://localhost:8787";
const token = readFileSync(new URL("../.cache/headset-token", import.meta.url), "utf8").trim();
const url = `${BASE.replace(/^http/, "ws")}/?client=vr&t=${encodeURIComponent(token)}`;

/** World-from-head rotation for a head turned `yaw` degrees right and `pitch` degrees up (CameraMath.orientation). */
function quat(yawDeg: number, pitchDeg: number): [number, number, number, number] {
  const y = (-yawDeg * Math.PI) / 180 / 2;
  const p = (pitchDeg * Math.PI) / 180 / 2;
  // q = qy * qx
  const qy = [0, Math.sin(y), 0, Math.cos(y)];
  const qx = [Math.sin(p), 0, 0, Math.cos(p)];
  const [x1, y1, z1, w1] = qy as [number, number, number, number];
  const [x2, y2, z2, w2] = qx as [number, number, number, number];
  return [w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2];
}

export function headAt(t: number): { yaw: number; pitch: number } {
  if (PATTERN === "still") return { yaw: YAW0, pitch: PITCH0 };
  if (PATTERN === "look") return { yaw: YAW0 + 25 * Math.sign(Math.sin((2 * Math.PI * t) / 12)), pitch: PITCH0 };
  return { yaw: YAW0 + 50 * Math.sin((2 * Math.PI * t) / 10), pitch: PITCH0 + 8 * Math.sin((2 * Math.PI * t) / 7) };
}

const ws = new WebSocket(url);
const t0 = Date.now();
let sent = 0;
ws.addEventListener("open", () => {
  console.log(`fake headset connected (${PATTERN}, ${SECS} s)`);
  const timer = setInterval(() => {
    const t = (Date.now() - t0) / 1000;
    if (t > SECS) {
      clearInterval(timer);
      ws.close();
      return;
    }
    const h = headAt(t);
    const [x, y, z, w] = quat(h.yaw, h.pitch);
    ws.send(JSON.stringify({ type: "vr_pose", q: [x, y, z, w], gaze: -1, cards: false, fov: 95 }));
    sent++;
    if (sent % 30 === 0) console.log(`${t.toFixed(1)}s yaw ${h.yaw.toFixed(1)} pitch ${h.pitch.toFixed(1)}`);
  }, 1000 / 30);
});
ws.addEventListener("close", () => {
  console.log(`closed after ${sent} poses`);
  process.exit(0);
});
ws.addEventListener("error", (e) => {
  console.error("fake headset error", (e as ErrorEvent).message ?? e);
  process.exit(1);
});
