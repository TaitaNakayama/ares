import * as Astronomy from "astronomy-engine";

/**
 * Mars24 sunclock (Allison & McEwen 2000, NASA GISS
 * https://www.giss.nasa.gov/tools/mars24/help/algorithm.html), ported from
 * research/code/mars_sun.py which was checked against the GISS worked example.
 */

/** TT - UTC in seconds (37 leap seconds + 32.184). */
const TT_MINUS_UTC = 37 + 32.184;
export const SOL_MS = 88_775_244;

const PERT: [number, number, number][] = [
  [0.0071, 2.2353, 49.409],
  [0.0057, 2.7543, 168.173],
  [0.0039, 1.1177, 191.837],
  [0.0037, 15.7866, 21.736],
  [0.0021, 2.1354, 15.704],
  [0.002, 2.4694, 95.528],
  [0.0018, 32.8493, 49.095],
];
const rad = (d: number) => (d * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;
const mod = (a: number, n: number) => ((a % n) + n) % n;

export function jdTT(unixMs: number): number {
  return 2440587.5 + unixMs / 86_400_000 + TT_MINUS_UTC / 86400;
}

export interface SunState {
  /** Areocentric solar longitude (season), degrees. */
  ls: number;
  /** Local true solar time, hours. */
  ltst: number;
  /** Solar elevation and azimuth (clockwise from north), degrees. */
  elevation: number;
  azimuth: number;
  /** Mars Sol Date. */
  msd: number;
}

export function marsSun(unixMs: number, latDeg: number, lonEastDeg: number): SunState {
  const jd = jdTT(unixMs);
  const dt = jd - 2451545.0;
  const M = 19.3871 + 0.52402073 * dt;
  const aFms = 270.3871 + 0.524038496 * dt;
  const pbs = PERT.reduce((s, [A, tau, ph]) => s + A * Math.cos(rad((0.985626 * dt) / tau + ph)), 0);
  const nuM =
    (10.691 + 3.0e-7 * dt) * Math.sin(rad(M)) + 0.623 * Math.sin(rad(2 * M)) + 0.05 * Math.sin(rad(3 * M)) + 0.005 * Math.sin(rad(4 * M)) + 0.0005 * Math.sin(rad(5 * M)) + pbs;
  const ls = mod(aFms + nuM, 360);
  const eot = 2.861 * Math.sin(rad(2 * ls)) - 0.071 * Math.sin(rad(4 * ls)) + 0.002 * Math.sin(rad(6 * ls)) - nuM;
  const msd = (jd - 2451549.5) / 1.0274912517 + 44796.0 - 0.0009626;
  const mst = mod(24 * msd, 24);
  const lamW = mod(-lonEastDeg, 360);
  const lmst = mod(mst - lamW / 15, 24);
  const ltst = mod(lmst + eot / 15, 24);
  const dec = deg(Math.asin(0.42565 * Math.sin(rad(ls)))) + 0.25 * Math.sin(rad(ls));
  const lamS = 15 * mst + eot + 180;
  const H = rad(lamW - lamS);
  const phi = rad(latDeg);
  const de = rad(dec);
  const cosZ = Math.sin(de) * Math.sin(phi) + Math.cos(de) * Math.cos(phi) * Math.cos(H);
  const elevation = 90 - deg(Math.acos(Math.max(-1, Math.min(1, cosZ))));
  const azimuth = mod(deg(Math.atan2(Math.sin(H), Math.cos(phi) * Math.tan(de) - Math.sin(phi) * Math.cos(H))), 360);
  return { ls, ltst, elevation, azimuth, msd };
}

/** One-way light time Earth <-> Mars at a date, from the real ephemeris. */
export function lightTimeMs(unixMs: number): number {
  const v = Astronomy.GeoVector(Astronomy.Body.Mars, new Date(unixMs), false);
  const au = Math.hypot(v.x, v.y, v.z);
  // Whole milliseconds: simulated timestamps are integers everywhere.
  return Math.round(au * 499.004784 * 1000);
}

export function earthMarsDistanceAu(unixMs: number): number {
  const v = Astronomy.GeoVector(Astronomy.Body.Mars, new Date(unixMs), false);
  return Math.hypot(v.x, v.y, v.z);
}

export function fmtLtst(h: number): string {
  const hh = Math.floor(h);
  const mm = Math.floor((h - hh) * 60);
  return `${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}`;
}
