# Jezero terrain assets

Engine-neutral OBJ + JPG/PNG terrain for the Mars base control room at Octavia E. Butler Landing
(18.4446 N, 77.4509 E planetocentric, ground -2570 m MOLA), looking out toward azimuth 305 (WNW).

## Commands

```bash
cd terrain
/opt/homebrew/bin/python3.14 -m venv .venv
.venv/bin/pip install -r requirements.txt          # rasterio wheels bundle GDAL
.venv/bin/python build.py                          # SceneKit / right-handed (default), ~40 s
.venv/bin/python build.py --handedness left        # Unity
```

Inputs are read from `../data/raw/` (git-ignored): `hirise_dtm_5km_1m.tif` (made by
`research/code/crop_rasterio.py`), `M20_JezeroCrater_CTXDEM_20m.tif`, and
`M20_JezeroCrater_CTXortho_mosaic_5m.tif` (360 MB; build.py downloads it if missing, the whole-file
download took about 30 s versus minutes for range reads). Other flags: `--az`, `--span`, `--margin`,
`--near-rmax`, `--far-rmin/--far-rmax`, `--near-budget/--far-budget`, `--tex-size`, `--height-size`,
`--no-curvature`. The run asserts: no NaN/inf, UVs in 0..1, triangle counts within budget, and a
max elevation angle of 0.5-10 degrees; it prints the angle.

## Outputs (`out/`)

| File | Content |
|---|---|
| `near.obj/.mtl`, `near_albedo.jpg`, `near_height.png` | HiRISE 1 m, r 4-2350 m. 87,906 tris, 44,388 verts |
| `far.obj/.mtl`, `far_albedo.jpg`, `far_height.png` | CTX 20 m, r 2150-25000 m. 67,952 tris, 34,375 verts |
| `terrain.json` | origin, CRS, extents, counts, height ranges, sector, UV squares, sources, credit |
| `preview.png` | software render from eye 2 m, az 305, 90 deg horizontal FOV (degree ticks at left) |
| `topdown.png` | hillshades with sector, seam radii and viewpoint |

Total about 33 MB. OBJ is small enough that no binary variant was written.

## Coordinate frame

Local metres, origin = viewpoint ground point, **+X east, +Y up, +Z north**, heights relative to the
viewpoint ground (0 at the eye-ground; the eye is 2 m up). No vertical exaggeration. Both DEMs are
reprojected to an azimuthal-equidistant CRS (`+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190`),
which removes the 5% E-W stretch of the lat_ts=0 HiRISE grid.

* **SceneKit** is right-handed Y-up: use the default (`--handedness right`).
* **Unity** is left-handed: `--handedness left` writes Z negated (+Z = south) and reverses winding so
  faces still point up. Verify on first import (see caveats): the scarp must appear left of the
  view axis ahead of you when facing az 305, with the rim straight ahead-left.

Planetary curvature `r^2/(2R)` (15 m at 10 km, 92 m at 25 km) is subtracted so the world can be flat
(`--no-curvature` disables; recorded in `terrain.json`).

## Mesh design

Polar grids over azimuth 305 +- 80 plus a 2 deg angular skirt each side (223-387 deg). Near: radial
step 2 m from 4 m to 200 m, then +4%/ring; angular segment count is solved to fill the budget
(~2 m spacing at 200 m). Far: +2%/ring from 2150 m. Heights are sampled from mip pyramids selected by
local vertex spacing (trilinear), so coarse rings are filtered, not aliased. Seam: the near heights
blend to the (offset-corrected) CTX over the last 150 m, so both meshes agree at 2350 m, and the far
mesh is pushed down up to 3 m inside the 2150-2350 m overlap so it hides under the near mesh.
No vertical skirt is generated. Budgets: near <= 90k, far <= 70k tris.

UVs are planar: `u=(E-(cE-s/2))/s`, `v=(N-(cN-s/2))/s` over the square given per mesh in `terrain.json`
(`uv_square`), v=0 at the south (bottom) image edge. Near square about 4.1 km (1.0 m/px), far about
43 km (10.6 m/px). Height PNGs (2048^2) cover the same squares; decode
`h = min + uint16/65535 * (max-min)` with min/max from `terrain.json` (heights are post-curvature).

## Albedo and palette

* **Far**: CTX 5 m ortho reprojected to the far square (area-average), percentile-stretched, contrast
  compressed (x0.7 about mid-gray) to soften the baked topographic shading, then tinted.
* **Near**: HiRISE ortho not used (25 cm files are 3.4-7.4 GB, striped or in another CRS/version;
  a 5 km window is too slow). Synthesized: low-passed (6 px) CTX tone as real large-scale albedo, plus
  DTM slope darkening, curvature (DoG) and multi-scale noise and gravel speckle. No sun shading baked.
* **Tint**: `rgb = dark + (light - dark) * g`, g in 0.05..0.95, dark = (0.30, 0.17, 0.11), light =
  (0.80, 0.57, 0.39) (sRGB, 0..1). Heuristic; tune against Perseverance Mastcam-Z frames.

## Sources

HiRISE DTM 1 m (006 mosaic, Equirectangular ts=0), CTX DEM 20 m, CTX ortho 5 m, all USGS Astrogeology
Mars 2020 TRN products (URLs in `terrain.json`; DOI https://doi.org/10.5066/P906QQT8).
Credit: *Terrain: NASA/JPL-Caltech/UArizona (HiRISE), MSSS (CTX); USGS Astrogeology Mars 2020 TRN products.*

## Known caveats

* The HiRISE crop is 5000 map-m wide, which is only about 4.74 km E-W on the ground (ts=0 grid), so the
  near mesh stops at 2350 m instead of 2500 m; the far mesh takes over from 2150 m. About 12% of the
  5.2 km working grid lies outside the crop and is filled from CTX (never inside the meshes).
* CTX sits +1.39 m above HiRISE near the site; that offset is removed from CTX. Both DEMs are
  affine-aligned only roughly (a few metres); sub-3 m seams are expected.
* HiRISE far-west "Crater Rim" strip has y-parallax artefacts (outside our sector).
* CTX ortho coverage ends near lon 77.00 E (about 25 km west); texels beyond are flat fill. Do not look east
  (az 90-120): the sector excludes it, and the rim is absent there anyway.
* The CTX ortho contains baked sun shading (mostly low-contrast at 10 m/px); light it in the engine at
  reduced strength or accept double shading on the far field.
* The near albedo is synthetic: do not expect real rocks/ripples to line up with the DTM detail.
* Orthos are grayscale; colour is only a tint, not measured Mars colour.
* Range reads of the big HiRISE files are slow (15-144 s per 512^2 window; verify-03 claim 7); whole-file
  downloads are faster. HiRISE (ts=0) and CTX (ts=18.4663) projections differ; both are handled by reprojection.
* Engine import: SceneKit/ModelIO and Unity both treat OBJ v=0 as the bottom edge; if the texture looks
  flipped vertically, flip V on import. Unity's own OBJ importer has been reported to mirror X; if Unity
  shows a mirrored scene with `--handedness left`, build with `right` and set Scale X = -1 instead.
  Use `.mtl` or assign textures manually; enable mipmaps and aniso on the near texture.
* Elevation angles: delta scarp about 2.6 deg (98 m at 2.15 km), rim about 4.2-4.3 deg (az 308, 10.6 km,
  ~790 m) from a 2 m eye, consistent with the research estimates (2.4 and 3-4 deg).
