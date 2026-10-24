#!/usr/bin/env python3
"""Build a polar (log-radial) terrain mesh around a viewpoint from HiRISE+CTX DEM GeoTIFFs -> OBJ.

Why polar: the vertex density falls off with distance (like LOD), only the visible azimuth sector is
meshed, and triangle count is a direct knob (n_r * n_az * 2).

Usage:
  pip install numpy rasterio
  python build_polar_mesh.py --hirise data/raw/hirise_dtm_5km_1m.tif --ctx data/raw/M20_JezeroCrater_CTXDEM_20m.tif \
      --lat 18.4446 --lon 77.4509 --az-center 300 --az-span 150 --out-prefix data/mesh/jezero

Outputs <prefix>_near.obj (r_min..r_split) and <prefix>_far.obj (r_split..r_max), local metres, origin at
the eye footprint (ground point), +Y up. OBJ is right-handed; Unity's OBJ importer negates X, so we write
X = -East so Unity ends up with +X = East, +Z = North (left-handed). UVs are planar east/north rectangles
so a single orthophoto crop maps without distortion (u=(E-E0)/W, v=(N-N0)/W).
"""
import argparse, math, os
import numpy as np
import rasterio

R_MARS = 3396190.0  # IAU sphere used by the USGS products


def load(path):
    ds = rasterio.open(path)
    a = ds.read(1).astype("float64")
    nod = ds.nodata
    if nod is not None:
        a[a == nod] = np.nan
    a[a < -1e6] = np.nan
    return ds, a


def make_sampler(ds, arr):
    """Return f(lat_deg, lon_deg)->height (bilinear, NaN outside), handling any Equirectangular ts."""
    wkt = ds.crs.to_wkt()
    ts = 0.0
    if "standard_parallel_1" in wkt:
        ts = float(wkt.split('"standard_parallel_1",')[1].split("]")[0])
    cts = math.cos(math.radians(ts))
    t = ds.transform
    H, W = arr.shape

    def f(lat, lon):
        x = R_MARS * np.radians(lon) * cts
        y = R_MARS * np.radians(lat)
        col = (x - t.c) / t.a - 0.5
        row = (y - t.f) / t.e - 0.5
        r0 = np.floor(row).astype(int); c0 = np.floor(col).astype(int)
        fr = row - r0; fc = col - c0
        ok = (r0 >= 0) & (c0 >= 0) & (r0 < H - 1) & (c0 < W - 1)
        r0c = np.clip(r0, 0, H - 2); c0c = np.clip(c0, 0, W - 2)
        v = (arr[r0c, c0c] * (1 - fr) * (1 - fc) + arr[r0c, c0c + 1] * (1 - fr) * fc +
             arr[r0c + 1, c0c] * fr * (1 - fc) + arr[r0c + 1, c0c + 1] * fr * fc)
        v[~ok] = np.nan
        return v
    return f


def write_obj(path, E, N, Z, uvE0, uvN0, uvW, tri_idx, grid_shape):
    n_r, n_a = grid_shape
    with open(path, "w") as fh:
        fh.write("# polar terrain mesh, local metres. X=-East (Unity importer flips), Y=up, Z=North\n")
        for e, n, z in zip(E.ravel(), N.ravel(), Z.ravel()):
            fh.write(f"v {-e:.2f} {z:.2f} {n:.2f}\n")
        for e, n in zip(E.ravel(), N.ravel()):
            fh.write(f"vt {(e - uvE0) / uvW:.5f} {(n - uvN0) / uvW:.5f}\n")
        for a, b, c in tri_idx:
            fh.write(f"f {a+1}/{a+1} {b+1}/{b+1} {c+1}/{c+1}\n")


def build(f_h, f_c, lat0, lon0, az_c, az_span, r0, r1, n_r, n_az, eye_ground, hirise_cutoff, curvature=True):
    az = np.radians(np.linspace(az_c - az_span / 2, az_c + az_span / 2, n_az))
    r = r0 * (r1 / r0) ** (np.linspace(0, 1, n_r))
    A, Rr = np.meshgrid(az, r)             # (n_r, n_az)
    E = Rr * np.sin(A); N = Rr * np.cos(A)
    lat = lat0 + np.degrees(N / R_MARS)
    lon = lon0 + np.degrees(E / (R_MARS * math.cos(math.radians(lat0))))
    zc = f_c(lat, lon)
    zh = f_h(lat, lon) if f_h is not None else np.full_like(zc, np.nan)
    # HiRISE inside hirise_cutoff, feather into CTX over 200 m; remove DC offset between products
    both = ~np.isnan(zh) & ~np.isnan(zc)
    off = np.nanmedian((zh - zc)[both & (Rr < hirise_cutoff)]) if both.any() else 0.0
    w = np.clip((hirise_cutoff - Rr) / 200.0, 0, 1) * (~np.isnan(zh))
    Z = np.where(np.isnan(zh), zc, w * (zh - off) + (1 - w) * zc)
    if curvature:
        # Elevations are relative to a sphere already; Unity world is flat, so subtract planetary curvature drop
        Z = Z - Rr ** 2 / (2 * 3389500.0)
    Z = Z - eye_ground
    print(f"HiRISE-CTX median offset {off:.2f} m; NaNs left {int(np.isnan(Z).sum())}")
    Z = np.where(np.isnan(Z), np.nanmin(Z), Z)
    return E, N, Z, Rr


def grid_tris(n_r, n_a, base=0):
    idx = np.arange(n_r * n_a).reshape(n_r, n_a) + base
    a = idx[:-1, :-1].ravel(); b = idx[:-1, 1:].ravel(); c = idx[1:, :-1].ravel(); d = idx[1:, 1:].ravel()
    # winding chosen so geometric normal points +Y in OBJ space (verified in main)
    return np.concatenate([np.stack([a, c, b], 1), np.stack([b, c, d], 1)])


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--hirise"); p.add_argument("--ctx", required=True)
    p.add_argument("--lat", type=float, default=18.4446); p.add_argument("--lon", type=float, default=77.4509)
    p.add_argument("--az-center", type=float, default=300); p.add_argument("--az-span", type=float, default=150)
    p.add_argument("--r-min", type=float, default=15); p.add_argument("--r-split", type=float, default=1500)
    p.add_argument("--r-max", type=float, default=25000)
    p.add_argument("--nr-near", type=int, default=260); p.add_argument("--naz-near", type=int, default=240)
    p.add_argument("--nr-far", type=int, default=160); p.add_argument("--naz-far", type=int, default=200)
    p.add_argument("--eye", type=float, default=1.7)
    p.add_argument("--out-prefix", default="jezero")
    a = p.parse_args()
    os.makedirs(os.path.dirname(a.out_prefix) or ".", exist_ok=True)
    dc, ac = load(a.ctx); fc = make_sampler(dc, ac)
    fh = None
    if a.hirise:
        dh, ah = load(a.hirise); fh = make_sampler(dh, ah)
    ground = float(fc(np.array([a.lat]), np.array([a.lon]))[0])
    if fh is not None:
        g2 = float(fh(np.array([a.lat]), np.array([a.lon]))[0])
        if not math.isnan(g2): ground = g2
    print("ground height at viewpoint", ground)
    total = 0
    for name, r0, r1, nr, na, uvW in (("near", a.r_min, a.r_split, a.nr_near, a.naz_near, 2 * a.r_split),
                                      ("far", a.r_split, a.r_max, a.nr_far, a.naz_far, 2 * a.r_max)):
        E, N, Z, Rr = build(fh, fc, a.lat, a.lon, a.az_center, a.az_span, r0, r1, nr, na, ground,
                            hirise_cutoff=2400 if fh is not None else 0)
        tris = grid_tris(nr, na)
        # winding check: normal of first triangle must have +Y in OBJ space (X=-E)
        i, j, k = tris[len(tris) // 3]
        P = np.stack([-E.ravel(), Z.ravel(), N.ravel()], 1)
        nrm = np.cross(P[j] - P[i], P[k] - P[i])
        if nrm[1] < 0:
            tris = tris[:, ::-1]
        write_obj(f"{a.out_prefix}_{name}.obj", E, N, Z, -uvW / 2, -uvW / 2, uvW, tris, (nr, na))
        print(name, "verts", E.size, "tris", len(tris), "z range %.0f..%.0f" % (Z.min(), Z.max()))
        total += len(tris)
    print("TOTAL tris (whole sector, before frustum culling):", total)
