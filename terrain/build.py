#!/usr/bin/env python3
"""Jezero Crater terrain assets (near.obj / far.obj + textures) for the Ares VR control room.

One command:   .venv/bin/python build.py [--handedness right|left]

Frame: local metres, origin = viewpoint ground point, +X east, +Y up, +Z north
(right-handed, SceneKit).  --handedness left flips Z (Unity) and reverses winding.
Heights are relative to the viewpoint ground, true scale (no vertical exaggeration).
"""
import argparse
import json
import math
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.crs import CRS
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

R_MARS = 3396190.0          # IAU sphere used by the USGS products
LAT, LON = 18.4446, 77.4509  # Octavia E. Butler Landing, planetocentric
AEQD = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT} +lon_0={LON} +R={R_MARS} +units=m +no_defs")
S3 = "https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn"
URL_HIRISE_DTM = S3 + "/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif"
URL_CTX_DEM = S3 + "/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXDEM_20m.tif"
URL_CTX_ORTHO = S3 + "/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif"
CREDIT = ("Terrain: NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX); "
          "USGS Astrogeology Mars 2020 TRN products.")
# Linear gray -> colour map (sRGB 0..1). Documented in README.
PALETTE_DARK = np.array([0.30, 0.17, 0.11], np.float32)
PALETTE_LIGHT = np.array([0.80, 0.57, 0.39], np.float32)


def log(*a):
    print(f"[{time.time() - T0:6.1f}s]", *a, flush=True)


T0 = time.time()


# --------------------------------------------------------------------------- data
def ensure(path, url):
    path = Path(path)
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    log(f"downloading {url} -> {path}")
    tmp = path.with_suffix(".part")
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    tmp.rename(path)
    return path


def warp_local(path, x0, y1, res, w, h, resampling, dtype="float32", fill=np.nan):
    """Reproject a raster band into the local aeqd grid (upper-left x0,y1; square pixels `res`)."""
    dst = np.full((h, w), fill, dtype)
    with rasterio.open(path) as ds:
        reproject(rasterio.band(ds, 1), dst, dst_transform=from_origin(x0, y1, res, res),
                  dst_crs=AEQD, resampling=resampling, src_nodata=ds.nodata,
                  dst_nodata=fill, num_threads=4)
    return dst


def bilerp(a, u, v):
    h, w = a.shape
    u = np.clip(u, 0, w - 1.0001)
    v = np.clip(v, 0, h - 1.0001)
    i = u.astype(np.int64)
    j = v.astype(np.int64)
    fu = (u - i).astype(np.float32)
    fv = (v - j).astype(np.float32)
    top = a[j, i] * (1 - fu) + a[j, i + 1] * fu
    bot = a[j + 1, i] * (1 - fu) + a[j + 1, i + 1] * fu
    return top * (1 - fv) + bot * fv


class Pyramid:
    """Square grid centred on the origin, half-extent `half`, with box-filtered mips.
    sample(E, N, L) interpolates between mip levels (L = log2(wanted spacing / base res))."""

    def __init__(self, base, res, nlev=7):
        self.half = base.shape[0] * res / 2
        self.res = res
        self.lv = [base.astype(np.float32)]
        for _ in range(nlev - 1):
            a = self.lv[-1]
            h, w = (a.shape[0] // 2) * 2, (a.shape[1] // 2) * 2
            a = a[:h, :w]
            self.lv.append(((a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2]) / 4))

    def _bil(self, k, E, N):
        r = self.res * 2 ** k
        return bilerp(self.lv[k], (E + self.half) / r - 0.5, (self.half - N) / r - 0.5)

    def sample(self, E, N, L=0.0):
        E = np.asarray(E, np.float32)
        N = np.asarray(N, np.float32)
        L = np.clip(np.broadcast_to(np.asarray(L, np.float32), E.shape), 0, len(self.lv) - 1.001)
        lo = np.floor(L).astype(int)
        f = L - lo
        out = np.zeros(E.shape, np.float32)
        for k in np.unique(lo):
            m = lo == k
            out[m] = (1 - f[m]) * self._bil(k, E[m], N[m]) + f[m] * self._bil(k + 1, E[m], N[m])
        return out


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


class Terrain:
    def __init__(self, args):
        self.a = args
        raw = Path(args.raw)
        hirise = ensure(raw / "hirise_dtm_5km_1m.tif", URL_HIRISE_DTM) if (raw / "hirise_dtm_5km_1m.tif").exists() else None
        if hirise is None:
            sys.exit("hirise_dtm_5km_1m.tif missing in data/raw (see research/code/crop_rasterio.py)")
        self.ctx_dem = ensure(raw / "M20_JezeroCrater_CTXDEM_20m.tif", URL_CTX_DEM)
        self.hirise = hirise
        self.ctx_ortho = raw / "M20_JezeroCrater_CTXortho_mosaic_5m.tif"
        # --- reproject DEMs to the local aeqd grid (true metres)
        nh, fh = 5184, 2688   # multiples of 32 so mips tile exactly
        log("warping CTX DEM -> local aeqd (20 m)")
        far = warp_local(self.ctx_dem, -fh * 10, fh * 10, 20.0, fh, fh, Resampling.bilinear)
        log("warping HiRISE DTM -> local aeqd (1 m)")
        near = warp_local(self.hirise, -nh / 2, nh / 2, 1.0, nh, nh, Resampling.bilinear)
        far_pyr0 = Pyramid(np.nan_to_num(far, nan=float(np.nanmedian(far))), 20.0, 2)
        # fill HiRISE gaps (outside the crop) with CTX
        yy, xx = np.mgrid[0:nh, 0:nh]
        Eg, Ng = xx - nh / 2 + 0.5, nh / 2 - yy - 0.5
        ctx_at_near = far_pyr0.sample(Eg, Ng, 0)
        both = np.isfinite(near) & (np.hypot(Eg, Ng) < 2000)
        offset = float(np.median(ctx_at_near[both] - near[both]))
        log(f"CTX - HiRISE median offset within 2 km: {offset:+.2f} m (removed from CTX)")
        valid_frac = float(np.isfinite(near).mean())
        near = np.where(np.isfinite(near), near, ctx_at_near - offset)
        # ground height at the viewpoint (HiRISE) = zero of the local frame
        z0 = float(bilerp(near, np.array([nh / 2 - 0.5]), np.array([nh / 2 - 0.5]))[0])
        self.z0, self.offset, self.hirise_valid_frac = z0, offset, valid_frac
        self.near_pyr = Pyramid(near - z0, 1.0, 7)
        far = np.where(np.isfinite(far), far, np.nan)
        far_fill = np.nan_to_num(far, nan=float(np.nanmedian(far)))
        self.far_valid_frac = float(np.isfinite(far).mean())
        self.far_pyr = Pyramid(far_fill - offset - z0, 20.0, 7)
        log(f"viewpoint ground = {z0:.2f} m (MOLA geoid datum); HiRISE valid {valid_frac:.3f}")

    def curv(self, r):
        return (r * r) / (2 * R_MARS) if not self.a.no_curvature else 0.0

    def h_far(self, E, N, L=0.0):
        r = np.hypot(E, N)
        h = self.far_pyr.sample(E, N, L)
        a = self.a
        bias = 3.0 * (1 - smoothstep((r - a.far_rmin) / max(a.near_rmax - a.far_rmin, 1)))  # tuck under near mesh
        return h - bias - self.curv(r)

    def h_near(self, E, N, L=0.0):
        r = np.hypot(E, N)
        a = self.a
        hi = self.near_pyr.sample(E, N, L)
        ctx = self.far_pyr.sample(E, N, np.maximum(L - 4.3, 0))
        s = smoothstep((r - (a.near_rmax - a.blend)) / a.blend)   # converge to CTX at the seam
        return (1 - s) * hi + s * ctx - self.curv(r)


# --------------------------------------------------------------------------- mesh
def radial_samples(rmin, rmax, dr0, r_dense, growth):
    """dr0 spacing up to r_dense, then geometric growth landing exactly on rmax."""
    r_dense = min(r_dense, rmax)
    if r_dense <= rmin:
        inner = np.array([rmin])
    else:
        inner = np.linspace(rmin, r_dense, max(int(round((r_dense - rmin) / dr0)), 1) + 1)
    if r_dense >= rmax:
        return inner
    r_dense = inner[-1]
    n_out = int(math.ceil(math.log(rmax / r_dense) / math.log(1 + growth)))
    outer = r_dense * (rmax / r_dense) ** (np.arange(1, n_out + 1) / n_out)
    return np.concatenate([inner, outer])


def build_grid(rs, az0, az1, budget, hfun, res_base, flipz):
    """Polar grid over [az0,az1] deg. Naz chosen to fit the triangle budget."""
    nr = len(rs) - 1
    naz = max(int(budget // (2 * nr)), 8)
    azs = np.linspace(az0, az1, naz + 1)
    ar = np.radians(azs)
    RR, AA = np.meshgrid(rs, ar, indexing="ij")
    E, N = RR * np.sin(AA), RR * np.cos(AA)
    dr = np.gradient(rs)[:, None] * np.ones_like(RR)
    dth = RR * (ar[1] - ar[0])
    L = np.log2(np.maximum(np.maximum(dr, dth), 1e-3) / res_base)
    H = hfun(E.ravel(), N.ravel(), L.ravel()).reshape(E.shape)
    # triangles; wind so normals face +Y in the right-handed frame
    idx = np.arange((nr + 1) * (naz + 1)).reshape(nr + 1, naz + 1)
    a, b, c, d = idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]
    t1 = np.stack([a, b, c], -1).reshape(-1, 3)
    t2 = np.stack([a, c, d], -1).reshape(-1, 3)
    tris = np.concatenate([t1, t2])
    V = np.stack([E.ravel(), H.ravel(), N.ravel()], 1).astype(np.float64)
    n = np.cross(V[tris[:, 1]] - V[tris[:, 0]], V[tris[:, 2]] - V[tris[:, 0]])
    if np.median(n[:, 1]) < 0:
        tris = tris[:, ::-1].copy()
    return V, tris, (nr, naz)


def vertex_normals(V, tris):
    fn = np.cross(V[tris[:, 1]] - V[tris[:, 0]], V[tris[:, 2]] - V[tris[:, 0]])
    vn = np.zeros_like(V)
    for k in range(3):
        np.add.at(vn, tris[:, k], fn)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)


def tex_bbox(V, pad_frac=0.01):
    e0, e1 = V[:, 0].min(), V[:, 0].max()
    n0, n1 = V[:, 2].min(), V[:, 2].max()
    W = max(e1 - e0, n1 - n0) * (1 + 2 * pad_frac)
    return (e0 + e1) / 2, (n0 + n1) / 2, W   # centre E, centre N, side


def write_obj(path, name, V, tris, uv, flipz):
    """V is right-handed (x=E,y=up,z=N). flipz -> left-handed for Unity."""
    V = V.copy()
    vn = vertex_normals(V, tris)
    T = tris
    if flipz:
        V[:, 2] *= -1
        vn[:, 2] *= -1
        T = tris[:, ::-1]
    n = len(V)
    with open(path, "w") as f:
        f.write(f"# {name}: local metres, origin = viewpoint ground, +X east, +Y up, "
                f"{'+Z south (LEFT-handed, Unity)' if flipz else '+Z north (right-handed)'}\n")
        f.write(f"# {CREDIT}\nmtllib {name}.mtl\no {name}\nusemtl {name}\n")
        f.write("".join(f"v {x:.3f} {y:.3f} {z:.3f}\n" for x, y, z in V))
        f.write("".join(f"vt {u:.6f} {v:.6f}\n" for u, v in uv))
        f.write("".join(f"vn {x:.4f} {y:.4f} {z:.4f}\n" for x, y, z in vn))
        f.write("".join(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n" for a, b, c in (T + 1)))
    Path(str(path).replace(".obj", ".mtl")).write_text(
        f"newmtl {name}\nKa 1 1 1\nKd 1 1 1\nKs 0 0 0\nillum 1\nmap_Kd {name}_albedo.jpg\n")


# --------------------------------------------------------------------------- imagery
def tint(gray):
    g = np.clip(gray, 0, 1)[..., None]
    rgb = PALETTE_DARK + (PALETTE_LIGHT - PALETTE_DARK) * g
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def blur(a, sigma):
    if sigma > 5:  # blur at reduced resolution
        f = 4
        h, w = a.shape
        small = np.asarray(Image.fromarray(a).resize((w // f, h // f), Image.BILINEAR))
        small = blur(small, sigma / f)
        return np.asarray(Image.fromarray(small).resize((w, h), Image.BICUBIC))
    r = int(3 * sigma) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(np.float32)
    k /= k.sum()
    p = np.pad(a, ((0, 0), (r, r)), mode="reflect")
    t = sum(k[i] * p[:, i:i + a.shape[1]] for i in range(2 * r + 1))
    p = np.pad(t, ((r, r), (0, 0)), mode="reflect")
    return sum(k[i] * p[i:i + a.shape[0]] for i in range(2 * r + 1)).astype(np.float32)


def fractal_noise(n, rng, scales=(4, 8, 16, 32, 64, 128), decay=0.7):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for s in scales:
        m = max(n // s, 2)
        g = rng.standard_normal((m, m)).astype(np.float32)
        out += amp * np.asarray(Image.fromarray(g).resize((n, n), Image.BICUBIC))
        tot += amp * amp
        amp *= decay
    return out / math.sqrt(tot)


def pstretch(a, lo=2, hi=98):
    p0, p1 = np.percentile(a, [lo, hi])
    return np.clip((a - p0) / max(p1 - p0, 1e-6), 0, 1)


def ortho_gray(terrain, cx, cy, W, n, blur_sigma=0.0):
    img = warp_local(terrain.ctx_ortho, cx - W / 2, cy + W / 2, W / n, n, n,
                     Resampling.average if W / n > 5 else Resampling.bilinear, "float32", -1.0)
    bad = img < 1
    if bad.any():
        img[bad] = np.median(img[~bad])
    return img


def near_albedo(terrain, bbox, n, rng):
    cx, cy, W = bbox
    res = W / n
    xs = cx - W / 2 + (np.arange(n) + 0.5) * res
    ys = cy + W / 2 - (np.arange(n) + 0.5) * res
    E, N = np.meshgrid(xs, ys)
    H = terrain.h_near(E.ravel(), N.ravel(), math.log2(max(res, 1.0))).reshape(n, n)
    log("near albedo: CTX ortho base tone")
    base = ortho_gray(terrain, cx, cy, W, n)
    base = pstretch(blur(base, 6.0), 2, 98)            # drop baked sun shading: keep only low-frequency albedo
    base = 0.5 + 0.55 * (base - 0.5)
    gy, gx = np.gradient(blur(H, 1.0), res)
    slope = np.clip(np.hypot(gx, gy) / 0.5, 0, 1)
    dog = blur(H, 1.5) - blur(H, 9.0)
    curv = np.clip(dog / (3 * dog.std() + 1e-6), -1, 1)
    nf, nm = fractal_noise(n, rng, (2, 4, 8)), fractal_noise(n, rng, (16, 32, 64, 128))
    speck = fractal_noise(n, rng, (1, 2))
    gravel = np.clip((speck - 1.6) / 1.5, 0, 1) - np.clip((-speck - 1.6) / 1.5, 0, 1)
    tone = (base + 0.10 * curv - 0.14 * slope + 0.06 * nf + 0.06 * nm
            + 0.20 * gravel * (0.35 + slope))
    tone = 0.05 + 0.9 * pstretch(tone, 1, 99)
    return tint(tone)


def far_albedo(terrain, bbox, n):
    cx, cy, W = bbox
    g = ortho_gray(terrain, cx, cy, W, n)
    g = pstretch(g, 2, 98)
    g = 0.5 + 0.7 * (g - 0.5)    # compress contrast: partially de-emphasise baked topographic shading
    return tint(0.05 + 0.9 * np.clip(g, 0, 1))


def height_png(fun, bbox, n, res_base, path):
    cx, cy, W = bbox
    res = W / n
    xs = cx - W / 2 + (np.arange(n) + 0.5) * res
    ys = cy + W / 2 - (np.arange(n) + 0.5) * res
    E, N = np.meshgrid(xs, ys)
    H = fun(E.ravel(), N.ravel(), math.log2(max(res / res_base, 1.0))).reshape(n, n)
    lo, hi = float(H.min()), float(H.max())
    u16 = np.round((H - lo) / (hi - lo) * 65535).astype(np.uint16)
    Image.fromarray(u16).save(path)
    return lo, hi


# --------------------------------------------------------------------------- previews
def hillshade(z, res, az=315, alt=40):
    gy, gx = np.gradient(z, res)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    A, h = math.radians(az), math.radians(alt)
    return np.clip(math.sin(h) * np.cos(slope) + math.cos(h) * np.sin(slope) * np.cos(A - aspect), 0, 1)


def topdown(terrain, args, out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axs = plt.subplots(1, 2, figsize=(16, 8.4))
    for ax, (pyr, ext, title, rin, rout) in zip(axs, [
            (terrain.far_pyr, 27000, "CTX 20 m, +-27 km (far mesh sector)", args.far_rmin, args.far_rmax),
            (terrain.near_pyr, 2592, "HiRISE 1 m, +-2.6 km (near mesh sector)", 4, args.near_rmax)]):
        z = pyr.lv[0]
        hs = hillshade(z, pyr.res)
        half = pyr.half
        ax.imshow(hs, extent=[-half, half, -half, half], cmap="gray", vmin=0.15, vmax=1)
        az = np.radians(np.linspace(args.az - args.span - args.margin, args.az + args.span + args.margin, 200))
        for r, c in ((rin, "#ffcc00"), (rout, "#00e5ff")):
            ax.plot(r * np.sin(az), r * np.cos(az), color=c, lw=1.4)
        for a in (args.az - args.span - args.margin, args.az + args.span + args.margin):
            ax.plot([rin * math.sin(math.radians(a)), rout * math.sin(math.radians(a))],
                    [rin * math.cos(math.radians(a)), rout * math.cos(math.radians(a))], color="#00e5ff", lw=1.2)
        ax.plot([0, rout * 1.15 * math.sin(math.radians(args.az))], [0, rout * 1.15 * math.cos(math.radians(args.az))],
                "--", color="#ff4040", lw=1, label=f"az {args.az:g} deg")
        ax.plot(0, 0, "*", color="#ff4040", ms=16, mec="white", label="viewpoint")
        ax.set_xlim(-half, half)
        ax.set_ylim(-half, half)
        ax.set_title(title)
        ax.set_xlabel("East (m)")
        ax.set_ylabel("North (m)")
        ax.legend(loc="lower right")
    fig.suptitle("Jezero terrain: hillshade, sector, viewpoint (yellow = inner radius, cyan = outer radius)")
    fig.tight_layout()
    fig.savefig(out, dpi=90)
    plt.close(fig)


def preview(meshes, args, out, eye_h=2.0, W=1600, Hh=640, ss=2):
    az = math.radians(args.az)
    fwd = np.array([math.sin(az), 0, math.cos(az)])
    right = np.array([math.cos(az), 0, -math.sin(az)])
    eye = np.array([0, eye_h, 0.0])
    F = (W * ss) / 2.0               # 90 deg horizontal FOV
    cx, cy = W * ss / 2, Hh * ss * 0.62
    img = Image.new("RGB", (W * ss, Hh * ss))
    d = ImageDraw.Draw(img)
    # sky gradient (butterscotch)
    top, hor = np.array([150, 112, 86]), np.array([222, 176, 132])
    for y in range(Hh * ss):
        t = np.clip((cy - y) / cy, 0, 1)
        d.line([(0, y), (W * ss, y)], fill=tuple(int(v) for v in hor + (top - hor) * t ** 0.6)
               if y < cy else tuple(int(v) for v in hor))
    sun = np.array([math.sin(math.radians(250)) * 0.8, 0.6, math.cos(math.radians(250)) * 0.8])
    sun /= np.linalg.norm(sun)
    items = []
    for V, tris, uv, tex in meshes:
        P = V - eye
        zc, xc, yc = P @ fwd, P @ right, P[:, 1]
        px = cx + F * xc / np.maximum(zc, 1e-3)
        py = cy - F * yc / np.maximum(zc, 1e-3)
        vn = vertex_normals(V, tris)
        t = tris
        ok = (zc[t] > 0.5).all(1)
        t = t[ok]
        cen = zc[t].mean(1)
        uvc = uv[t].mean(1)
        ty = ((1 - uvc[:, 1]) * (tex.shape[0] - 1)).astype(int).clip(0, tex.shape[0] - 1)
        tx = (uvc[:, 0] * (tex.shape[1] - 1)).astype(int).clip(0, tex.shape[1] - 1)
        col = tex[ty, tx].astype(np.float32) / 255
        lam = np.clip(vn[t].mean(1) @ sun, 0.0, 1)[:, None]
        col = col * (0.35 + 0.85 * lam)
        dist = np.hypot(V[t][:, :, 0].mean(1), V[t][:, :, 2].mean(1))
        fog = (1 - np.exp(-dist / 28000.0))[:, None] * 0.55
        col = col * (1 - fog) + (hor / 255)[None] * fog
        items.append((t, cen, col, px, py))
    recs = []
    for k, (t, cen, col, px, py) in enumerate(items):
        recs.append((cen, np.full(len(t), k), np.arange(len(t))))
    cen = np.concatenate([r[0] for r in recs])
    mk = np.concatenate([r[1] for r in recs])
    ti = np.concatenate([r[2] for r in recs])
    order = np.argsort(-cen)
    for o in order:
        t, _, col, px, py = items[mk[o]]
        tri = t[ti[o]]
        c = tuple(int(v * 255) for v in col[ti[o]].clip(0, 1))
        d.polygon([(px[i], py[i]) for i in tri], fill=c)
    img = img.resize((W, Hh), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    # elevation-angle ticks (relative to eye level)
    cy1, F1 = cy / ss, F / ss
    for deg in (0, 1, 2, 3, 4, 5, 6):
        y = cy1 - F1 * math.tan(math.radians(deg))
        d.line([(0, y), (28 if deg else W, y)], fill=(255, 255, 255) if deg else (255, 255, 255, 90), width=1)
        d.text((32, y - 6), f"{deg} deg", fill=(255, 255, 255))
    for a in range(-40, 41, 10):
        x = W / 2 + F1 * math.tan(math.radians(a))
        d.line([(x, Hh - 14), (x, Hh)], fill=(255, 255, 255))
        d.text((x - 14, Hh - 28), f"{(args.az + a) % 360:g}", fill=(255, 255, 255))
    img.save(out)


# --------------------------------------------------------------------------- main
def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--raw", default=str(ROOT / "data" / "raw"))
    p.add_argument("--out", default=str(HERE / "out"))
    p.add_argument("--handedness", choices=["left", "right"], default="right",
                   help="right = SceneKit (+Z north); left = Unity (Z flipped, +Z south, winding reversed)")
    p.add_argument("--az", type=float, default=305.0, help="view azimuth, compass degrees")
    p.add_argument("--span", type=float, default=80.0, help="half-width of the visible sector (deg)")
    p.add_argument("--margin", type=float, default=2.0, help="extra angular skirt each side (deg)")
    p.add_argument("--near-rmin", type=float, default=4.0)
    p.add_argument("--near-rmax", type=float, default=2350.0, help="HiRISE crop limits this to ~2.37 km E-W")
    p.add_argument("--near-dr", type=float, default=2.0, help="near radial spacing (m) out to --near-dense")
    p.add_argument("--near-dense", type=float, default=200.0)
    p.add_argument("--near-growth", type=float, default=0.04)
    p.add_argument("--blend", type=float, default=150.0, help="width of near->CTX height blend at the seam (m)")
    p.add_argument("--far-rmin", type=float, default=2150.0)
    p.add_argument("--far-rmax", type=float, default=25000.0)
    p.add_argument("--far-growth", type=float, default=0.02)
    p.add_argument("--near-budget", type=int, default=88000)
    p.add_argument("--far-budget", type=int, default=68000)
    p.add_argument("--tri-limit-near", type=int, default=90000)
    p.add_argument("--tri-limit-far", type=int, default=70000)
    p.add_argument("--tex-size", type=int, default=4096)
    p.add_argument("--height-size", type=int, default=2048)
    p.add_argument("--eye-height", type=float, default=2.0)
    p.add_argument("--no-curvature", action="store_true", help="do not subtract d^2/2R planetary curvature")
    p.add_argument("--seed", type=int, default=2020)
    args = p.parse_args()
    flipz = args.handedness == "left"
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    ensure(Path(args.raw) / "M20_JezeroCrater_CTXortho_mosaic_5m.tif", URL_CTX_ORTHO)
    T = Terrain(args)
    rng = np.random.default_rng(args.seed)
    az0, az1 = args.az - args.span - args.margin, args.az + args.span + args.margin

    log("near mesh")
    rs_n = radial_samples(args.near_rmin, args.near_rmax, args.near_dr, args.near_dense, args.near_growth)
    Vn, Tn, (nrn, nazn) = build_grid(rs_n, az0, az1, args.near_budget, T.h_near, 1.0, flipz)
    log("far mesh")
    rs_f = radial_samples(args.far_rmin, args.far_rmax, 1.0, args.far_rmin, args.far_growth)
    Vf, Tf, (nrf, nazf) = build_grid(rs_f, az0, az1, args.far_budget, T.h_far, 20.0, flipz)

    bb_n, bb_f = tex_bbox(Vn), tex_bbox(Vf)
    meshes = {}
    for name, V, Tr, bb in (("near", Vn, Mesh_tris(Tn), bb_n), ("far", Vf, Mesh_tris(Tf), bb_f)):
        uv = np.stack([(V[:, 0] - (bb[0] - bb[2] / 2)) / bb[2], (V[:, 2] - (bb[1] - bb[2] / 2)) / bb[2]], 1)
        meshes[name] = (V, Tr, uv, bb)

    # ---- sanity: no NaNs, budgets
    for name, (V, Tr, uv, bb) in meshes.items():
        assert np.isfinite(V).all() and np.isfinite(uv).all(), f"NaN/inf in {name}"
        assert uv.min() >= 0 and uv.max() <= 1, f"{name} UV outside 0..1"
    assert len(Tn) <= args.tri_limit_near, f"near {len(Tn)} tris over budget"
    assert len(Tf) <= args.tri_limit_far, f"far {len(Tf)} tris over budget"

    # ---- textures
    log("far albedo")
    far_tex = far_albedo(T, bb_f, args.tex_size)
    log("near albedo (synthetic detail on CTX tone)")
    near_tex = near_albedo(T, bb_n, args.tex_size, rng)
    Image.fromarray(near_tex).save(out / "near_albedo.jpg", quality=90, subsampling=0, optimize=True)
    Image.fromarray(far_tex).save(out / "far_albedo.jpg", quality=90, subsampling=0, optimize=True)
    log("height PNGs")
    nlo, nhi = height_png(T.h_near, bb_n, args.height_size, 1.0, out / "near_height.png")
    flo, fhi = height_png(T.h_far, bb_f, args.height_size, 20.0, out / "far_height.png")
    assert all(np.isfinite([nlo, nhi, flo, fhi]))

    # ---- OBJ
    log("writing OBJ")
    for name, (V, Tr, uv, bb) in meshes.items():
        write_obj(out / f"{name}.obj", name, V, Tr, uv, flipz)

    # ---- elevation angle check (mesh vertices, eye at y = eye_height)
    allV = np.concatenate([Vn, Vf])
    r = np.hypot(allV[:, 0], allV[:, 2])
    azv = (np.degrees(np.arctan2(allV[:, 0], allV[:, 2])) + 360) % 360
    m = (np.abs(((azv - args.az + 180) % 360) - 180) <= 10) & (r > 100)
    ang = np.degrees(np.arctan2(allV[m, 1] - args.eye_height, r[m]))
    k = int(np.argmax(ang))
    rk, hk, ak = r[m][k], allV[m, 1][k], azv[m][k]
    # dense ray check against the height functions (not limited by vertex spacing)
    best = (-90, 0, 0, 0)
    for a in np.arange(args.az - 10, args.az + 10.01, 0.5):
        rr = np.linspace(100, args.far_rmax, 4000)
        E, N = rr * math.sin(math.radians(a)), rr * math.cos(math.radians(a))
        h = np.where(rr < args.near_rmax - args.blend, T.h_near(E, N, 0), T.h_far(E, N, 2))
        e = np.degrees(np.arctan2(h - args.eye_height, rr))
        j = int(np.argmax(e))
        if e[j] > best[0]:
            best = (float(e[j]), a, float(rr[j]), float(h[j]))
    log(f"MAX ELEVATION ANGLE az {args.az - 10:g}..{args.az + 10:g}: {best[0]:.2f} deg "
        f"(dense rays; az {best[1]:.1f}, r {best[2]/1000:.2f} km, h {best[3]:.0f} m) | "
        f"mesh vertices: {ang[k]:.2f} deg (az {ak:.1f}, r {rk/1000:.2f} km, h {hk:.0f} m)")
    # separate scarp (r < 4 km) and rim (r > 6 km)
    for lab, lo, hi in (("delta scarp 1.5-4 km", 1500, 4000), ("rim 6-25 km", 6000, 25000)):
        mm = m & (r > lo) & (r < hi)
        if mm.any():
            aa = np.degrees(np.arctan2(allV[mm, 1] - args.eye_height, r[mm]))
            q = int(np.argmax(aa))
            log(f"   {lab}: {aa[q]:.2f} deg at r {r[mm][q]/1000:.2f} km, h {allV[mm, 1][q]:.0f} m")
    assert 0.5 < best[0] < 10, "max elevation angle outside expected few-degree range"

    # ---- previews (right-handed geometry always)
    log("preview.png")
    preview([(Vf, Tf, meshes["far"][2], far_tex), (Vn, Tn, meshes["near"][2], near_tex)], args,
            out / "preview.png", args.eye_height)
    log("topdown.png")
    topdown(T, args, out / "topdown.png")

    # ---- terrain.json
    def mesh_info(name, V, Tr, bb, hmm, rs, nr, naz, tex_px):
        return {"file": f"{name}.obj", "albedo": f"{name}_albedo.jpg", "height_png": f"{name}_height.png",
                "vertices": int(len(V)), "triangles": int(len(Tr)), "grid_rings": nr, "grid_azimuth_segments": naz,
                "r_min_m": float(rs[0]), "r_max_m": float(rs[-1]),
                "height_min_m": float(V[:, 1].min()), "height_max_m": float(V[:, 1].max()),
                "uv_square": {"center_east_m": bb[0], "center_north_m": bb[1], "side_m": bb[2],
                              "note": "u=(E-(cE-side/2))/side, v=(N-(cN-side/2))/side, v=0 is the BOTTOM (south) image edge"},
                "albedo_px": tex_px, "albedo_m_per_px": bb[2] / tex_px,
                "height_png_px": args.height_size,
                "height_png_decode": {"min_m": hmm[0], "max_m": hmm[1], "formula": "h = min + (uint16/65535)*(max-min)"}}
    info = {
        "origin": {"lat_planetocentric_deg": LAT, "lon_east_deg": LON, "ground_elevation_m_mola": T.z0,
                   "note": "local height 0 = this ground point; eye is eye_height above it"},
        "eye_height_m": args.eye_height,
        "crs": {"proj4": AEQD.to_proj4(), "description": "azimuthal equidistant, centred on the origin, sphere R=3396190 m"},
        "frame": {"x": "east", "y": "up", "z": "north (right) / south (left)", "handedness": args.handedness,
                  "units": "metres", "vertical_exaggeration": 1.0,
                  "curvature_removed": not args.no_curvature,
                  "curvature_formula": "h -= r^2/(2*3396190 m)" if not args.no_curvature else None},
        "sector": {"view_azimuth_deg": args.az, "half_span_deg": args.span, "skirt_deg": args.margin,
                   "azimuth_range_deg": [az0, az1], "azimuth_convention": "compass, clockwise from north"},
        "extents": {"near_radius_m": [float(rs_n[0]), float(rs_n[-1])], "far_radius_m": [float(rs_f[0]), float(rs_f[-1])],
                    "near_far_overlap_m": [args.far_rmin, args.near_rmax]},
        "near": mesh_info("near", Vn, Tn, bb_n, (nlo, nhi), rs_n, nrn, nazn, args.tex_size),
        "far": mesh_info("far", Vf, Tf, bb_f, (flo, fhi), rs_f, nrf, nazf, args.tex_size),
        "triangles_total": int(len(Tn) + len(Tf)),
        "max_elevation_angle_deg": {"az_range": [args.az - 10, args.az + 10], "dense_rays": best[0],
                                    "at_az_deg": best[1], "at_r_m": best[2], "mesh_vertices": float(ang[k])},
        "calibration": {"ctx_minus_hirise_median_m": T.offset, "hirise_valid_fraction_of_grid": T.hirise_valid_frac},
        "albedo": {"far": "CTX 5 m orthomosaic (reprojected, contrast-compressed, tinted)",
                   "near": "synthetic: low-passed CTX ortho tone + DTM slope/curvature + noise (no HiRISE ortho used)",
                   "palette_dark_srgb": PALETTE_DARK.tolist(), "palette_light_srgb": PALETTE_LIGHT.tolist(),
                   "palette_rule": "rgb = dark + (light-dark)*gray, gray in 0.05..0.95"},
        "sources": [
            {"role": "near height", "name": "HiRISE DTM 1 m (Mars 2020 TRN)", "url": URL_HIRISE_DTM,
             "used": "5 km window pre-cropped to data/raw/hirise_dtm_5km_1m.tif"},
            {"role": "far height", "name": "CTX DEM 20 m (Mars 2020 Science Investigation)", "url": URL_CTX_DEM},
            {"role": "far albedo", "name": "CTX orthomosaic 5 m", "url": URL_CTX_ORTHO},
            {"role": "doi", "url": "https://doi.org/10.5066/P906QQT8"}],
        "credit": CREDIT,
    }
    (out / "terrain.json").write_text(json.dumps(info, indent=2))
    log(f"triangles: near {len(Tn)}, far {len(Tf)}; vertices: near {len(Vn)}, far {len(Vf)}")
    log("done")


def Mesh_tris(t):
    return t


if __name__ == "__main__":
    main()
