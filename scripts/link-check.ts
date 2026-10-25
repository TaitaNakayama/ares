// Checks the headset link's recovery with the real phone: cuts the headset's socket N times (POST /api/debug/drop-headset,
// as a pulled USB cable or a Wi-Fi blip would) and times how long until its pose stream is back, and whether the Mac
// spectator stayed LIVE (it holds the last pose for up to 4 s).
//   node scripts/link-check.ts [--drops 5] [--gap 8]
const args = process.argv.slice(2);
const opt = (k: string, d: string) => (args.includes(k) ? args[args.indexOf(k) + 1]! : d);
const DROPS = Number(opt("--drops", "5"));
const GAP = Number(opt("--gap", "8"));
const BASE = process.env.ARES_URL ?? "http://localhost:8787";
const get = async (p: string) => (await fetch(`${BASE}${p}`)).json() as Promise<any>;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const live = async () => {
  const p = await get("/api/debug/pose");
  return p.openHeadsetSockets > 0 && p.msSinceRelay !== null && p.msSinceRelay < 400;
};
for (let i = 0; i < 40 && !(await live()); i++) await sleep(500);
if (!(await live())) {
  console.log("no headset streaming its pose: open the app on the phone (unlocked) and try again");
  process.exit(2);
}
const times: number[] = [];
let spectatorDrops = 0;
for (let i = 0; i < DROPS; i++) {
  const before = (await get("/api/debug/pose")).connects;
  await fetch(`${BASE}/api/debug/drop-headset`, { method: "POST" });
  const t0 = Date.now();
  let back = -1;
  let notLive = false;
  while (Date.now() - t0 < 30_000) {
    await sleep(100);
    const [p, st] = await Promise.all([get("/api/debug/pose"), get("/api/spectator/stats")]);
    if (st.mode && st.mode !== "live") notLive = true;
    if (p.connects > before && p.msSinceRelay !== null && p.msSinceRelay < 300) {
      back = Date.now() - t0;
      break;
    }
  }
  if (notLive) spectatorDrops++;
  times.push(back);
  console.log(`drop ${i + 1}: pose back after ${back < 0 ? "30+ s (never)" : `${(back / 1000).toFixed(2)} s`}${notLive ? "  (spectator left LIVE)" : ""}`);
  await sleep(GAP * 1000);
}
const ok = times.filter((t) => t >= 0);
console.log(`reconnects ${ok.length}/${DROPS}; worst ${ok.length ? (Math.max(...ok) / 1000).toFixed(2) : "-"} s; spectator left LIVE ${spectatorDrops}/${DROPS}`);
const pass = ok.length === DROPS && Math.max(...ok) < 3000 && spectatorDrops === 0;
console.log(`  ${pass ? "PASS" : "FAIL"}  every drop recovered in < 3 s and the spectator stayed LIVE`);
process.exit(pass ? 0 : 1);
