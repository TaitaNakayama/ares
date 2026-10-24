# 03 - Mars terrain + sky for the Jezero control-room VR app

Researched 2026-10-23. Everything marked VERIFIED was fetched or computed today in this session; items marked HEURISTIC are my own design values (tunable), not published numbers.

## TL;DR

**Important correction to the brief:** the ~1.8 GB file is the **HiRISE DTM (1 m)**, not the 25 cm orthomosaic. The 25 cm orthomosaics are 3.4 GB and 7.3 GB. You never need to download them whole: all GeoTIFFs below support HTTP range requests and the windowed-read crops in this report pull only ~55 MB (DTM) and ~150 MB (ortho).

| Role | Product | URL | Size | Grid |
|---|---|---|---|---|
| Near terrain height | HiRISE DTM mosaic, Mars 2020 TRN, 1 m, float32 (m above Mars geoid, MOLA) | https://planetarymaps.usgs.gov/mosaic/mars2020_trn/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif (302 redirect to S3; direct S3 form below) | 1,839,545,409 B | 21400x21488, Equirectangular ts=0, R=3396190 m, covers lat 18.307..18.669, lon 77.223..77.584 |
| Near texture | HiRISE ortho 25 cm, uint8 grayscale, "first" mosaic (same grid as the DTM, 4x finer) | https://planetarymaps.usgs.gov/mosaic/mars2020_trn/HiRISE/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif | 7,358,523,457 B (striped, uncompressed) | 85600x85952 |
| Near texture (alt) | HiRISE ortho 25 cm "blend120", tiled+LZW (cheaper windowed reads) but a different version (007) and CRS: Orthographic at 18.4663N 77.4298E | https://planetarymaps.usgs.gov/mosaic/mars2020_trn/HiRISE/JEZ_hirise_soc_007_orthoMosaic_25cm_Ortho_blend120.tif | 3,408,854,746 B | 81064x85936 |
| Far height | CTX DEM 20 m, Mars 2020 Science Investigation (whole crater + surroundings), float32 | https://planetarymaps.usgs.gov/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXDEM_20m.tif | 90,345,300 B (DOWNLOADED) | 4456x5067, Equirectangular ts=18.4663, lat 17.58..19.29, lon 77.00..78.58 |
| Far texture | CTX ortho 5 m, uint8 grayscale, matched to that DEM | https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif | 359,599,280 B | 17766x20234, ts=18.4663 |

Direct S3 hosts (use these for scripted downloads; the planetarymaps.usgs.gov 302 sometimes reset the connection during my GETs while HEAD was fine): replace the host with `https://asc-pds-services.s3.us-west-2.amazonaws.com` and keep the path `/mosaic/mars2020_trn/...`.

**Viewpoint:** Octavia E. Butler Landing, **18.4446 N, 77.4509 E** (planetocentric), DEM ground height **-2570 m** (HiRISE) / -2568 m (CTX). Look direction **azimuth ~305 deg (WNW)**: the delta scarp is ~2.1-2.2 km away at az 300-315, rising ~90 m (2.4 deg above the eye), with the western crater rim behind it at ~10-12 km (3-4 deg elevation, 600-900 m above the eye). Computed from the DEMs today.

**Crop:** HiRISE DTM 5 km x 5 km at 1 m (r < 2.5 km), CTX DEM out to 25 km (CTX coverage ends at lon 77.00 E, i.e. ~27 km west of the site, so r_max = 25 km). Textures: near 3 km ortho at 0.5 m (downsample to 4096^2 for the game, ~0.73 m/px), far CTX ortho at ~12 m/px in a 4096^2.

**Pipeline:** `rasterio`/GDAL windowed read over HTTP -> local azimuthal-equidistant metres -> `build_polar_mesh.py` (log-radial polar grid, only the visible azimuth sector) -> two OBJ files (near/far, ~187k tris total for a 150 deg sector, before culling) + two ortho textures -> Unity (ASTC 6x6).

**Sun:** Mars24 implemented and validated against the NASA GISS worked example in `research/code/mars_sun.py` (pure stdlib, C#-portable in ~60 lines).

**Sky:** one `tau` drives direct-sun transmittance `exp(-tau/sin(elev))`, ambient/sky luminance, sky gradient colors, sun-halo size/strength and fog density `beta = tau / 11.5 km`. Details in section 5.

## Credit line to show on screen

Suggested (the USGS pages say "Please cite authors"; the pages state no license beyond that and a no-warranty/no-endorsement disclaimer; USGS works are generally US-government public domain, but I did not find an explicit license statement on these pages):

> Terrain: NASA/JPL-Caltech/UArizona (HiRISE, CTX), USGS Astrogeology Science Center - Mars 2020 TRN DTM/orthomosaics (Fergason et al., 2020; Calef, 2021). Sun model: Mars24, NASA GISS (Allison and McEwen, 2000).

Do not imply NASA/USGS endorsement (their disclaimer: "Any use of trade, firm, or product names is for descriptive purposes only and does not imply endorsement by the U.S. Government"). HiRISE credit convention is "NASA/JPL-Caltech/UArizona"; CTX is MSSS/NASA/JPL. DOI of the TRN products: https://doi.org/10.5066/P906QQT8.

## Evidence table

| Claim | URL | Date |
|---|---|---|
| Collection of Jezero products; HiRISE DTM/ortho, CTX DEM, CTX ortho exist with these pages | https://astrogeology.usgs.gov/search/map/mars-2020-jezero-crater-landing-site-products | fetched 2026-10-23 (items dated 2020-07-24, 2021-10-14, 2025-02-28) |
| HiRISE DTM file URL, 1 m, "Please cite authors", affine alignment to CTX, caution on the far-west "Crater Rim" strip (y-parallax) | https://astrogeology.usgs.gov/search/map/mars_2020_terrain_relative_navigation_hirise_dtm_mosaic | fetched 2026-10-23 (published 2020) |
| HiRISE DTM size 1,839,545,409 B, Last-Modified 2022-11-10; ISIS label: 21400x21488, lat 18.3068..18.6693, lon 77.2229..77.5840, 1 m, Equirectangular ts=0, radius 3396190 | https://astrogeology.usgs.gov/ckan/dataset/381ba037-d8a9-4cea-86be-374e4951afe3/resource/bd39aeaf-231d-4732-b333-7636bce607ff/download/jez_hirise_soc_006_dtm_molatopography_deltageoid_1m_eqc_latts0_lon0_blend40.lbl | curl/HEAD 2026-10-23 |
| HiRISE ortho 25 cm file URLs and sizes (7.36 GB "first", 3.41 GB "blend120") | https://astrogeology.usgs.gov/search/map/mars_2020_terrain_relative_navigation_hirise_orthorectified_image_mosaic | HEAD 2026-10-23 (files modified 2022-11-10) |
| CTX DEM 20 m (90 MB) and CTX ortho 5 m (360 MB) URLs; DEM metadata (lat/lon bounds, ts=18.4663, 20 m) | https://astrogeology.usgs.gov/search/map/mars_2020_science_investigation_ctx_dem_mosaic ; XML https://astrogeology.usgs.gov/ckan/dataset/f8ef46b8-d512-4c46-b825-fe9633c38e1c/resource/5691ea08-1db4-4018-a341-e415e716add7/download/m20_jezerocrater_ctxdem_20m.xml | page dated 2021-10-14; fetched 2026-10-23 |
| Newer MSR HiRISE mosaic (v003, 2024-08; 1 m DTM + 0.25 m ortho "First_NoBlend"; mosaics zip 5.47 GB, individual images zip 13.6 GB); too big, not needed | https://astrogeology.usgs.gov/search/map/mars-sample-return-terrain-relative-navigation-hirise-dtm-mosaic | page 2025-02-28; zip Last-Modified 2025-02-04 |
| All of the above GeoTIFFs answer HTTP 200 with `Accept-Ranges: bytes` on the S3 host; windowed `/vsicurl/` reads worked via rasterio (GDAL 3.12.2) | (see URLs above) | 2026-10-23 |
| Butler Landing position ~18.44 N 77.45 E; Ingenuity helipad 18.44486 N 77.45102 E | https://en.wikipedia.org/wiki/Octavia_E._Butler_Landing ; https://en.wikipedia.org/wiki/Mars_2020 | search 2026-10-23 (secondary source; rounded) |
| Delta scarps ~2.2 km NW of landing, ~60 m (NASA) high; rim hills 5-7 km (NASA text, loosely) | https://science.nasa.gov/blog/studying-the-jezero-delta-from-a-distance/ | search 2026-10-23 |
| My DEM profile: scarp max +94 m at 2.2 km, az 315; rim 3-4 deg at 10-12 km W/WSW | computed from the downloaded CTX DEM and HiRISE crop | 2026-10-23 |
| Mars24 algorithm formulas A-1..D-6, worked examples | https://www.giss.nasa.gov/tools/mars24/help/algorithm.html | page updated 2025-01-07 |
| `marstime` (Python) Mars24 implementation, Modified BSD | https://pypi.org/project/marstime/ ; docs https://marstime.readthedocs.io/en/latest/marstime.html | search 2026-10-23 |
| `@xfanta/mars-time` TypeScript port of marstime, Modified BSD | https://unpkg.com/@xfanta/mars-time@1.0.3/README.md | search 2026-10-23 |
| Original Mars24 (Java, Schmunk/Allison): no code license found, credits list only third-party libs | https://www.giss.nasa.gov/tools/mars24/help/credits.html | search 2026-10-23 |
| Sky: dust preferentially absorbs blue, scatters rest -> butterscotch; Mie forward scatter puts blue halo around the sun at sunset; Curiosity first colour sunset sol 956 (April 2015, PIA19400) | https://www.webexhibits.org/causesofcolor/14C.html ; https://spacedaily.com/t-sunsets-on-mars-glow-blue-rather-than-red-because-the-fine-dust-suspended-in-its-thin-air-scatters-sunlight-so-that-the-blue-gathers-into-a-halo-around-the-setting-sun-while-the-rest-of-the-sky-stay/ | search 2026-10-23 (popular sources; the PIA19400 NASA page itself I could not fetch) |
| Blue halo about 5 deg wide in PIA19400 (a GitHub issue, unreviewed, weak evidence) | https://github.com/celestiary/web/issues/188 | search 2026-10-23 |
| Curiosity record of tau (440/880 nm) over 5+ Mars years via solar imaging | https://arxiv.org/pdf/2309.07378 | search 2026-10-23 |
| 2018 global storm: Curiosity tau above 8; Opportunity ~11 before going silent; sky darkening until sun vanished | https://www.jpl.nasa.gov/news/martian-dust-storm-grows-global-curiosity-captures-photos-of-thickening-haze/ | NASA release 2018-06-20 |
| Typical background tau ~0.9 at Gusev/Meridiani early mission; dust scale height 11.56 +/- 0.62 km; Spirit tau 3.6 -> 3.3 in 2007 storm | https://experts.arizona.edu/en/publications/atmospheric-imaging-results-from-the-mars-exploration-rovers-spir/ (Lemmon et al., Science 306, 2004) ; https://ntrs.nasa.gov/api/citations/20110000777/downloads/20110000777.pdf | search 2026-10-23 |
| Perseverance: regional storm sol 1244 gave hazier crater views, team uses Mastcam-Z "tau" sky pointing | https://science.nasa.gov/blog/persevering-through-the-storm/ | 2024-09-05 |
| Mastcam-Z visible aerosol optical depth record (Lemmon) | https://data.mendeley.com/datasets/gktjp9jptb | search 2026-10-23 |

## 1. Data products: details

Full detail is in the TL;DR table. Extra facts:
- HiRISE DTM is stored **striped, uncompressed float32** (one row = 85.6 KB). A 5000 x 5000 window = 5000 range requests; it took about one minute. nodata = -3.4028e38.
- The HiRISE ortho "first" (006) shares the DTM grid (same corners 4577366/1106618 m), so DTM and texture align exactly. The "blend120" (007) is a *different version* in a *different CRS* (Orthographic centred 18.4663 N, 77.4298 E, 0.25 m, tiled 256x256 + LZW, much faster windowed reads). Mixing 007 ortho with the 006 DTM can misregister by metres. Prefer 006 "first" for exact alignment unless reads are too slow.
- **Gotcha:** the HiRISE products use Equirectangular with latitude of true scale **0**, so "1 m/px" is 1 m in north-south but only cos(18.4 deg) = 0.948 m east-west on the ground. CTX products use ts = 18.4663 (true scale at the site). Reproject to a local metric CRS before meshing (the commands do this; the mesh script uses lat/lon sampling so it is already correct).
- HiRISE vs CTX height difference near the site: median -2.07 m (computed), i.e. same datum to within a couple of metres; the mesh script removes it.
- Orthos are **grayscale only** (no colour mosaic exists at these scales). Colour must come from a tint in the shader (see section 3).
- HiRISE quality caveat from the USGS page: the far-west "Crater Rim" strip has y-parallax artifacts, outside the landing ellipse (not near our viewpoint).

## 2. Crop + pipeline

### Is the rim visible? (VERIFIED by computation)
Mars radius 3389.5 km (3396.19 km IAU sphere gives <0.2% difference).
- Horizon distance for eye height h: d = sqrt(2 R h + h^2). h = 1.7 m -> 3.39 km; h = 2 m -> 3.68 km.
- Curvature drop at distance d is d^2/(2R): 5 km: 3.7 m; 10 km: 14.8 m; 20 km: 59 m; 22 km: 71 m; 25 km: 92 m; 30 km: 133 m.
- So the geometric horizon (3.4-3.7 km) is *closer* than the delta scarp (2.2 km is inside it, the rest of the floor beyond it is hidden only by the 90 m scarp itself), but anything taller than the drop is visible. A 600 m rim at 22 km rises 600 - 71 = ~530 m above the horizon line = **1.4 deg above the eye level**. Easily visible, as a low ridge.
- Using the actual CTX DEM from the viewpoint (eye +1.7 m, curvature-corrected): max elevation angle per azimuth: N 1.9 deg (rim at 17.6 km, 616 m above eye), S 2.2 deg (22 km, 905 m), SW 3.4-3.5 deg (12-15 km, ~750-930 m), W 4.0 deg (10.6 km, 762 m), NW 3.2 deg, NNW 2.1 deg. **East and ESE (az 90-120) show no rim** (max angle -0.25 deg): the east side of the site opens onto the crater outlet/low plains. Do not look east.
- Consequence: in Unity you can use a flat world with the curvature subtracted from vertex heights (done in the script), no need for a planetary-curvature shader.

### Where to stand
18.4446 N, 77.4509 E. Projected metres in the HiRISE grid (Equirectangular ts=0): x = 4590878.67, y = 1093298.09.

### Commands (GDAL; rasterio equivalents were what I ran, see below)
GDAL CLI was **not run**: `brew install gdal` was already queued by another process in this machine (it was still fetching `unity-hub` first) and I did not want to fight it for the brew lock. I validated the same operations through `rasterio 1.5.2` (bundles GDAL 3.12.2) in a venv. The GDAL commands below use standard flags and should work verbatim on 3.13.x; re-run `gdalinfo` first.

```bash
export S3=https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn
export D=/Users/TAITA/Projects/ares/data/raw
# inspect without downloading
gdalinfo /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif | head -40

# 1) near DTM: 5 km square at 1 m (projwin = ulx uly lrx lry, in source metres)
gdal_translate -projwin 4588378 1095798 4593378 1090798 -of GTiff -co COMPRESS=DEFLATE \
  /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif $D/hirise_dtm_5km_1m.tif

# 2) near ortho: 3 km square, downsampled 25 cm -> 50 cm (average)
gdal_translate -projwin 4589378 1094798 4592378 1091798 -tr 0.5 0.5 -r average -co COMPRESS=DEFLATE \
  /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif $D/hirise_ortho_3km_0p5m.tif

# 3) reproject to a local metric CRS (azimuthal equidistant, origin = eye) so E/N are true metres
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -2000 -2000 2000 2000 -tr 1 1 -r bilinear -dstnodata -9999 \
  $D/hirise_dtm_5km_1m.tif $D/dtm_local_4km_1m.tif
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -1500 -1500 1500 1500 -tr 0.75 0.75 -r cubic $D/hirise_ortho_3km_0p5m.tif $D/ortho_local_3km_0p75m.tif   # 4000 px

# 4) far field: CTX ortho 5 m, 50 km square, to 12.2 m (4096 px), local CRS
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -25000 -25000 25000 25000 -ts 4096 4096 -r average \
  /vsicurl/$S3/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif $D/ctx_ortho_local_50km.tif   # ~360 MB read

# 5) to 8-bit PNG for Unity import (stretch 2-98 percent; the HiRISE ortho is 0=nodata, 1..255)
gdal_translate -of PNG -scale_1 20 235 1 255 -ot Byte $D/ortho_local_3km_0p75m.tif $D/ortho_near_4k.png
```

**Rasterio equivalents actually executed (worked, 2026-10-23):** `crop.py` (windowed read of DTM 5 km -> `data/raw/hirise_dtm_5km_1m.tif`, 55 MB, shape 5000x5000, range -2640..-2441 m; ortho 3 km at 0.5 m queued, see the "3am" section for status) and an `rasterio.warp.reproject` of the DTM into the `+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190` CRS (4000x4000, no NaNs, centre height -2569.90 m). Scripts are in the scratchpad `crop.py`; the commands above are the GDAL form.

If you want 16-bit RAW for a Unity Terrain (not recommended, see sec. 3):
```bash
gdalinfo -stats $D/dtm_local_4km_1m.tif | grep -E 'MINIMUM|MAXIMUM'   # use these in -scale
gdal_translate -ot UInt16 -scale -2640 -2440 0 65535 -outsize 2049 2049 -r bilinear -of ENVI $D/dtm_local_4km_1m.tif terrain.raw
# Unity: Terrain settings -> Import Raw: Depth 16 bit, Width/Height 2049, Byte order = Windows (little-endian). Terrain Size X=Z=4000 m, Y=200 m (the scale range).
```
(Unity's valid heightmap resolutions are 2^n+1: 513, 1025, 2049, 4097.)

### Recommended crops
| Layer | Extent | Source res | Game res | Notes |
|---|---|---|---|---|
| Near mesh/texture | r < 1.5 km (3 km square) | HiRISE 1 m DTM, 25 cm ortho | mesh angular/radial grid ~2-8 m near, texture 4096^2 = 0.73 m/px | rocks/regolith detail comes from a tiling detail normal map, not geometry |
| Mid | 1.5-2.5 km | HiRISE DTM | in "far" mesh, blended | script feathers HiRISE->CTX over 200 m at 2.4 km |
| Far mesh | 1.5-25 km | CTX 20 m DEM | log-radial, 30-250 m spacing | CTX coverage ends at lon 77.00 E (west) |
| Far texture | 50 km square | CTX ortho 5 m | 4096^2 = 12.2 m/px | tint + fog hides softness |
| Beyond 25 km | - | - | not needed; fog/haze + sky gradient | rim is at 10-22 km |

## 3. Unity side

**Recommendation: decimated static mesh, not Unity Terrain.** Reasons (engineering judgement, not benchmarked): Terrain runs a quadtree LOD + per-patch draw + splat/blend shaders that are costly in stereo on a phone; our view is a fixed point (no free roaming), so a baked mesh with exactly the density we want is cheaper and fully controllable; URP's Terrain Lit shader is heavier than a simple Lit/Unlit mesh with one texture. Use Terrain only if you need runtime sculpting or trees/details painting (we don't).

**Budget:** my proposal is **<= 200k triangles for the whole sector mesh** (the script's defaults give 187k for a 150 deg sector, which the room window will cut by at least half through frustum culling), plus solar panels/drill/room (target the whole scene <= 300k tris, <= 100 draw calls in stereo, single directional light, no realtime shadow cascades beyond 1 cascade near the room). iPhone 16 Pro can handle more, but Cardboard stereo (2 renders, at least 60 fps, thermals over a multi-minute demo) is where mobile VR falls over. These numbers are not from a cited source: measure with Xcode GPU frame capture early.

**Why a polar log-radial grid:** quad density automatically falls with distance (near 2-8 m, far ~100-250 m); only the azimuth sector you can see is meshed; triangle count = n_r * n_az * 2 is one knob. Defaults: near ring 15 m-1.5 km, 260 x 240; far ring 1.5-25 km, 160 x 200.

**Mesh script (tested):** `/Users/TAITA/Projects/ares/research/code/build_polar_mesh.py`
```bash
python3 -m venv .venv && .venv/bin/pip install numpy rasterio
.venv/bin/python research/code/build_polar_mesh.py \
  --hirise data/raw/hirise_dtm_5km_1m.tif --ctx data/raw/M20_JezeroCrater_CTXDEM_20m.tif \
  --lat 18.4446 --lon 77.4509 --az-center 305 --az-span 150 --r-split 1500 --r-max 25000 \
  --out-prefix data/mesh/jezero
```
Ran today: HiRISE-CTX median offset -2.07 m removed; near mesh 62,400 verts / 123,802 tris; far 32,000 verts / 63,282 tris; total 187,084 tris; OBJ files 7.0 MB + 3.7 MB. The script: samples both DEMs bilinearly by lat/lon (handles ts=0 vs ts=18.4663), blends HiRISE into CTX, **subtracts planetary curvature** d^2/(2*3389.5 km) so the world can be flat, zeroes heights at the eye's ground point (eye at y = 1.7 m above 0), writes planar east/north UVs (u=(E-E0)/W, v=(N-N0)/W where W = 2*r_split for near, 2*r_max for far), and checks triangle winding gives +Y normals. Unity's OBJ importer negates X, so the file stores X=-East: after import Unity +X = East, +Z = North. **Check the first import visually** (wrong handedness shows as a mirrored delta and inside-out faces). If it is mirrored, flip Scale X = -1 on the parent or drop the `-e` negation. UV/texture alignment: the near ortho covers E,N in [-1500,1500] (square) and the far one [-25000,25000], matching the script's uvW (3000 and 50000). Note the sector mesh covers only part of the square, so the texture is partly unused; that is fine.

glTF alternative: glTFast package in Unity can import GLB, but adds a dependency and loading code; OBJ needs none. Another low-dependency route: write a `.bin` of float32 heights and build the `Mesh` in a Unity C# `Start()` (UInt32 indices, `mesh.indexFormat = IndexFormat.UInt32` is required above 65k verts; the OBJ importer does this automatically).

**Textures:** HiRISE ortho is grayscale. Import as single channel or RGB and drive colour in the shader: `albedo = gray^1.1 * lerp(float3(0.42,0.24,0.15), float3(0.78,0.55,0.38), gray)` (HEURISTIC: Mars regolith is red-brown with dark basaltic floor; tune against Perseverance Mastcam-Z frames). Sizes: near 4096^2 ASTC 6x6 = 4096*4096/36*16 B = 7.5 MB (8x8 = 4 MB); far 4096^2 ASTC 8x8 = 4 MB; total < 12 MB. 2048^2 fallback if memory/thermals suffer. Enable mipmaps, aniso 4 on the near texture (floor viewed at grazing angles). Add a 1024^2 tiling regolith detail normal map (CC0 gravel) faded in within ~50 m to fake rocks. The only truly 3-D rocks should be a handful of hero props near the base.

**Vertical exaggeration:** none, scale = 1.0 on all axes. The real Jezero floor is nearly flat; the relief comes from the 90 m delta scarp 2.2 km away and the 3-4 deg rim. In a cardboard stereo app the horizon and parallax are tiny at those distances anyway (stereo depth cues vanish beyond ~30-100 m), so the sky and haze carry the sense of depth. If it looks too flat for the demo, do **not** scale heights: raise the camera (the room floor is a few metres above the regolith), or pick az 305 where the scarp is.

## 4. Sun position: Mars24 (Allison and McEwen 2000)

Source: https://www.giss.nasa.gov/tools/mars24/help/algorithm.html (page updated 2025-01-07). Steps (angles in degrees):
1. JD_UT = 2440587.5 + unix_ms/86400000. JD_TT = JD_UT + (TT-UTC)/86400, TT-UTC = 37 s (TAI-UTC) + 32.184 s = 69.184 s since 2017-01-01 (assumes no leap second since; error of one second is irrelevant here). dt = JD_TT - 2451545.0.
2. Mean anomaly M = 19.3871 + 0.52402073 dt. Fictitious mean sun alpha_FMS = 270.3871 + 0.524038496 dt.
3. Perturbers PBS = sum_{i=1..7} A_i cos(0.985626 dt / tau_i + phi_i): (A, tau, phi) = (0.0071, 2.2353, 49.409), (0.0057, 2.7543, 168.173), (0.0039, 1.1177, 191.837), (0.0037, 15.7866, 21.736), (0.0021, 2.1354, 15.704), (0.0020, 2.4694, 95.528), (0.0018, 32.8493, 49.095).
4. Equation of centre (nu - M) = (10.691 + 3.0e-7 dt) sin M + 0.623 sin 2M + 0.050 sin 3M + 0.005 sin 4M + 0.0005 sin 5M + PBS. Solar longitude Ls = alpha_FMS + (nu - M).
5. Equation of time EOT = 2.861 sin 2Ls - 0.071 sin 4Ls + 0.002 sin 6Ls - (nu - M) (degrees; /15 for hours).
6. Mars Mean Time at 0 deg: MST = mod24(24 * ((JD_TT - 2451549.5)/1.0274912517 + 44796.0 - 0.0009626)). Local mean solar time LMST = MST - Lambda_W/15 (Lambda_W = degrees WEST = 360 - east longitude). LTST = LMST + EOT/15.
7. Declination dec = asin(0.42565 sin Ls) + 0.25 sin Ls (degrees). Subsolar longitude (W) = 15 MST + EOT + 180.
8. Hour angle H = Lambda_W - subsolar_W. Zenith cos Z = sin(dec) sin(lat) + cos(dec) cos(lat) cos H; elevation = 90 - Z. Azimuth = atan2(sin H, cos(lat) tan(dec) - sin(lat) cos H), compass degrees clockwise from north (verified: ~99 deg = east in the morning, ~268 deg = west in the evening at Jezero).
9. Heliocentric distance R_M = 1.52367934 * (1.00436 - 0.09309 cos M - 0.004336 cos 2M - 0.00031 cos 3M - 0.00003 cos 4M) AU. Use it for solar irradiance: S = 1361 / R_M^2 W/m^2 (about 717 at perihelion down to 493 W/m^2 at aphelion, ~590 mean; keep consistent with the power model).

Sol length: 24 h 39 m 35.244 s = 88775.244 s (= 1.0274912517 days, the constant above). Sun apparent diameter from Mars is about 21 arcmin = 0.35 deg (from memory, not verified here).

**Implementation (validated):** `/Users/TAITA/Projects/ares/research/code/mars_sun.py` (stdlib only). Check against the NASA example (2000-01-06 00:00 UTC, 0 E): dt = 4.50074 (matches), Ls = 277.18759 (page: 277.18758), MST = 23.9942 h = 23:59:39 (matches). Sample output at Jezero (18.4446, 77.4509) today: Ls = 11.6 (northern spring, dust-storm season is Ls ~180-330), local noon elevation ~73 deg, sunset at LTST ~18.4 h. For the demo drive time by a "Mars clock" (LTST) and Ls directly (set `jd_tt` or bypass: pick Ls and LTST, compute dec from Ls, H from LTST).

Open-source references (to cross-check or port):
- `marstime` (Python), Christopher Lee, Modified BSD, https://pypi.org/project/marstime/ (functions solar_elevation, solar_azimuth, ...).
- `@xfanta/mars-time` (TypeScript), Modified BSD, port of marstime.
- No C# implementation found; the 60-line Python port above translates directly (use `System.Math`, `DateTimeOffset.ToUnixTimeMilliseconds`).
- Mars24 original: Java, no code license found; the algorithm itself is published (Allison and McEwen 2000, Planet. Space Sci. 48, 215-235; Allison 1997 GRL 24, 1967). Reimplementing the published formulas is fine; cite both.

## 5. Sky model

### What is physically known
- The Martian daytime sky is butterscotch/tan: airborne dust (radius ~1.5 um, Lemmon 2004) absorbs blue and scatters the rest; Rayleigh from CO2 would be blue but is overwhelmed.
- Near sunrise/sunset the sky around the sun turns blue: dust scatters strongly forward and blue is scattered slightly more forward than red, so a blue aureole (order 5 deg per the PIA19400 analysis, weak source) surrounds the sun while the rest of the sky stays tan/orange. Curiosity's first colour sunset: sol 956, PIA19400.
- Higher dust optical depth tau: direct sun dims as exp(-tau/sin elev) (Beer-Lambert; tau is by definition the exponent), more light becomes diffuse, shadows soften, the sky gets darker overall, redder/browner and more uniform, the sun disk fades; in the 2018 storm Curiosity saw tau above 8 and Opportunity ~11 (sun invisible). Background tau at Gusev/Meridiani ~0.9 early in the missions; Perseverance regional storm sol 1244 gave visibly hazier crater views (NASA 2024-09-05).
- Dust is well mixed to a scale height of ~11.6 km (Lemmon 2004), so near-surface horizontal extinction is about beta = tau / H = tau / 11.5 km.

I could not find published numbers for the diffuse-to-direct ratio versus tau in a fetched source; the curve below is a standard two-stream style approximation and marked HEURISTIC.

### Proposed cheap implementation: parameters as functions of (tau, sun elevation e)
Let s = clamp(sin e, 0.02, 1), tau in [0.2, 8] (clamp; 0.5 = clear, 1.0 = typical, 3 = regional storm, 6+ = global storm).

| Quantity | Formula (HEURISTIC, tune by eye against Perseverance/Curiosity frames) |
|---|---|
| Direct sun transmittance | T_dir = exp(-tau / (s + 0.05)) (cap airmass at ~20) |
| Sun light intensity | I_sun = I_0 * T_dir, I_0 from the irradiance in step 9, then exposure-mapped; at tau 0.5 noon: 0.75*I_0; tau 3: 0.05*I_0; tau 6: 0.002*I_0 |
| Diffuse/sky luminance (ambient + sky shader brightness) | L_sky = k * (1 - T_dir^0.6) * (0.35 + 0.65*s^0.5) * exp(-0.12*max(tau-2, 0)) (rises with tau up to ~2-3 as light is scattered into the sky, then falls as total light is absorbed) |
| Shadow strength (URP shadow intensity / soft shadow) | = T_dir / (T_dir + L_sky*0.8): ~0.8 at tau 0.5, ~0.35 at tau 3, ~0.05 at tau 6 (set directional light `shadowStrength`, or fade the shadow distance) |
| Zenith colour (linear RGB, day) | lerp( (0.55,0.38,0.26) @tau0.5 , (0.30,0.20,0.14) @tau3 , (0.16,0.10,0.07) @tau7 ) * L_sky |
| Horizon colour | lerp( (0.85,0.65,0.45) @tau0.5 , (0.55,0.38,0.26) @tau3 , (0.22,0.14,0.09) @tau7 ) * L_sky; horizon is brighter than zenith; the zenith-horizon contrast factor (1 - 0.8*tau/(tau+3)) goes toward flat as tau rises |
| Sun disk | base colour (1.0,0.93,0.82); multiply per channel by exp(-tau_c/(s+0.05)) with tau_R = 0.8 tau, tau_G = 1.0 tau, tau_B = 1.3 tau (dust extinguishes blue more, so the low sun goes orange-red; ratios HEURISTIC); angular radius 0.17 deg |
| Blue halo about 5 deg wide in PIA19400 (a GitHub issue, unreviewed, weak evidence) | https://github.com/celestiary/web/issues/188 | search 2026-10-23 |
| Curiosity record of tau (440/880 nm) over 5+ Mars years via solar imaging | https://arxiv.org/pdf/2309.07378 | search 2026-10-23 |
| 2018 global storm: Curiosity tau above 8; Opportunity ~11 before going silent; sky darkening until sun vanished | https://www.jpl.nasa.gov/news/martian-dust-storm-grows-global-curiosity-captures-photos-of-thickening-haze/ | NASA release 2018-06-20 |
| Typical background tau ~0.9 at Gusev/Meridiani early mission; dust scale height 11.56 +/- 0.62 km; Spirit tau 3.6 -> 3.3 in 2007 storm | https://experts.arizona.edu/en/publications/atmospheric-imaging-results-from-the-mars-exploration-rovers-spir/ (Lemmon et al., Science 306, 2004) ; https://ntrs.nasa.gov/api/citations/20110000777/downloads/20110000777.pdf | search 2026-10-23 |
| Perseverance: regional storm sol 1244 gave hazier crater views, team uses Mastcam-Z "tau" sky pointing | https://science.nasa.gov/blog/persevering-through-the-storm/ | 2024-09-05 |
| Mastcam-Z visible aerosol optical depth record (Lemmon) | https://data.mendeley.com/datasets/gktjp9jptb | search 2026-10-23 |

## 1. Data products: details

Full detail is in the TL;DR table. Extra facts:
- HiRISE DTM is stored **striped, uncompressed float32** (one row = 85.6 KB). A 5000 x 5000 window = 5000 range requests; it took about one minute. nodata = -3.4028e38.
- The HiRISE ortho "first" (006) shares the DTM grid (same corners 4577366/1106618 m), so DTM and texture align exactly. The "blend120" (007) is a *different version* in a *different CRS* (Orthographic centred 18.4663 N, 77.4298 E, 0.25 m, tiled 256x256 + LZW, much faster windowed reads). Mixing 007 ortho with the 006 DTM can misregister by metres. Prefer 006 "first" for exact alignment unless reads are too slow.
- **Gotcha:** the HiRISE products use Equirectangular with latitude of true scale **0**, so "1 m/px" is 1 m in north-south but only cos(18.4 deg) = 0.948 m east-west on the ground. CTX products use ts = 18.4663 (true scale at the site). Reproject to a local metric CRS before meshing (the commands do this; the mesh script uses lat/lon sampling so it is already correct).
- HiRISE vs CTX height difference near the site: median -2.07 m (computed), i.e. same datum to within a couple of metres; the mesh script removes it.
- Orthos are **grayscale only** (no colour mosaic exists at these scales). Colour must come from a tint in the shader (see section 3).
- HiRISE quality caveat from the USGS page: the far-west "Crater Rim" strip has y-parallax artifacts, outside the landing ellipse (not near our viewpoint).

## 2. Crop + pipeline

### Is the rim visible? (VERIFIED by computation)
Mars radius 3389.5 km (3396.19 km IAU sphere gives <0.2% difference).
- Horizon distance for eye height h: d = sqrt(2 R h + h^2). h = 1.7 m -> 3.39 km; h = 2 m -> 3.68 km.
- Curvature drop at distance d is d^2/(2R): 5 km: 3.7 m; 10 km: 14.8 m; 20 km: 59 m; 22 km: 71 m; 25 km: 92 m; 30 km: 133 m.
- So the geometric horizon (3.4-3.7 km) is *closer* than the delta scarp (2.2 km is inside it, the rest of the floor beyond it is hidden only by the 90 m scarp itself), but anything taller than the drop is visible. A 600 m rim at 22 km rises 600 - 71 = ~530 m above the horizon line = **1.4 deg above the eye level**. Easily visible, as a low ridge.
- Using the actual CTX DEM from the viewpoint (eye +1.7 m, curvature-corrected): max elevation angle per azimuth: N 1.9 deg (rim at 17.6 km, 616 m above eye), S 2.2 deg (22 km, 905 m), SW 3.4-3.5 deg (12-15 km, ~750-930 m), W 4.0 deg (10.6 km, 762 m), NW 3.2 deg, NNW 2.1 deg. **East and ESE (az 90-120) show no rim** (max angle -0.25 deg): the east side of the site opens onto the crater outlet/low plains. Do not look east.
- Consequence: in Unity you can use a flat world with the curvature subtracted from vertex heights (done in the script), no need for a planetary-curvature shader.

### Where to stand
18.4446 N, 77.4509 E. Projected metres in the HiRISE grid (Equirectangular ts=0): x = 4590878.67, y = 1093298.09.

### Commands (GDAL; rasterio equivalents were what I ran, see below)
GDAL CLI was **not run**: `brew install gdal` was already queued by another process in this machine (it was still fetching `unity-hub` first) and I did not want to fight it for the brew lock. I validated the same operations through `rasterio 1.5.2` (bundles GDAL 3.12.2) in a venv. The GDAL commands below use standard flags and should work verbatim on 3.13.x; re-run `gdalinfo` first.

```bash
export S3=https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn
export D=/Users/TAITA/Projects/ares/data/raw
# inspect without downloading
gdalinfo /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif | head -40

# 1) near DTM: 5 km square at 1 m (projwin = ulx uly lrx lry, in source metres)
gdal_translate -projwin 4588378 1095798 4593378 1090798 -of GTiff -co COMPRESS=DEFLATE \
  /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif $D/hirise_dtm_5km_1m.tif

# 2) near ortho: 3 km square, downsampled 25 cm -> 50 cm (average)
gdal_translate -projwin 4589378 1094798 4592378 1091798 -tr 0.5 0.5 -r average -co COMPRESS=DEFLATE \
  /vsicurl/$S3/HiRISE/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif $D/hirise_ortho_3km_0p5m.tif

# 3) reproject to a local metric CRS (azimuthal equidistant, origin = eye) so E/N are true metres
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -2000 -2000 2000 2000 -tr 1 1 -r bilinear -dstnodata -9999 \
  $D/hirise_dtm_5km_1m.tif $D/dtm_local_4km_1m.tif
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -1500 -1500 1500 1500 -tr 0.75 0.75 -r cubic $D/hirise_ortho_3km_0p5m.tif $D/ortho_local_3km_0p75m.tif   # 4000 px

# 4) far field: CTX ortho 5 m, 50 km square, to 12.2 m (4096 px), local CRS
gdalwarp -t_srs "+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190 +units=m +no_defs" \
  -te -25000 -25000 25000 25000 -ts 4096 4096 -r average \
  /vsicurl/$S3/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif $D/ctx_ortho_local_50km.tif   # ~360 MB read

# 5) to 8-bit PNG for Unity import (stretch 2-98 percent; the HiRISE ortho is 0=nodata, 1..255)
gdal_translate -of PNG -scale_1 20 235 1 255 -ot Byte $D/ortho_local_3km_0p75m.tif $D/ortho_near_4k.png
```

**Rasterio equivalents actually executed (worked, 2026-10-23):** `crop.py` (windowed read of DTM 5 km -> `data/raw/hirise_dtm_5km_1m.tif`, 55 MB, shape 5000x5000, range -2640..-2441 m; ortho 3 km at 0.5 m queued, see the "3am" section for status) and an `rasterio.warp.reproject` of the DTM into the `+proj=aeqd +lat_0=18.4446 +lon_0=77.4509 +R=3396190` CRS (4000x4000, no NaNs, centre height -2569.90 m). Scripts are in the scratchpad `crop.py`; the commands above are the GDAL form.

If you want 16-bit RAW for a Unity Terrain (not recommended, see sec. 3):
```bash
gdalinfo -stats $D/dtm_local_4km_1m.tif | grep -E 'MINIMUM|MAXIMUM'   # use these in -scale
gdal_translate -ot UInt16 -scale -2640 -2440 0 65535 -outsize 2049 2049 -r bilinear -of ENVI $D/dtm_local_4km_1m.tif terrain.raw
# Unity: Terrain settings -> Import Raw: Depth 16 bit, Width/Height 2049, Byte order = Windows (little-endian). Terrain Size X=Z=4000 m, Y=200 m (the scale range).
```
(Unity's valid heightmap resolutions are 2^n+1: 513, 1025, 2049, 4097.)

### Recommended crops
| Layer | Extent | Source res | Game res | Notes |
|---|---|---|---|---|
| Near mesh/texture | r < 1.5 km (3 km square) | HiRISE 1 m DTM, 25 cm ortho | mesh angular/radial grid ~2-8 m near, texture 4096^2 = 0.73 m/px | rocks/regolith detail comes from a tiling detail normal map, not geometry |
| Mid | 1.5-2.5 km | HiRISE DTM | in "far" mesh, blended | script feathers HiRISE->CTX over 200 m at 2.4 km |
| Far mesh | 1.5-25 km | CTX 20 m DEM | log-radial, 30-250 m spacing | CTX coverage ends at lon 77.00 E (west) |
| Far texture | 50 km square | CTX ortho 5 m | 4096^2 = 12.2 m/px | tint + fog hides softness |
| Beyond 25 km | - | - | not needed; fog/haze + sky gradient | rim is at 10-22 km |

## 3. Unity side

**Recommendation: decimated static mesh, not Unity Terrain.** Reasons (engineering judgement, not benchmarked): Terrain runs a quadtree LOD + per-patch draw + splat/blend shaders that are costly in stereo on a phone; our view is a fixed point (no free roaming), so a baked mesh with exactly the density we want is cheaper and fully controllable; URP's Terrain Lit shader is heavier than a simple Lit/Unlit mesh with one texture. Use Terrain only if you need runtime sculpting or trees/details painting (we don't).

**Budget:** my proposal is **<= 200k triangles for the whole sector mesh** (the script's defaults give 187k for a 150 deg sector, which the room window will cut by at least half through frustum culling), plus solar panels/drill/room (target the whole scene <= 300k tris, <= 100 draw calls in stereo, single directional light, no realtime shadow cascades beyond 1 cascade near the room). iPhone 16 Pro can handle more, but Cardboard stereo (2 renders, at least 60 fps, thermals over a multi-minute demo) is where mobile VR falls over. These numbers are not from a cited source: measure with Xcode GPU frame capture early.

**Why a polar log-radial grid:** quad density automatically falls with distance (near 2-8 m, far ~100-250 m); only the azimuth sector you can see is meshed; triangle count = n_r * n_az * 2 is one knob. Defaults: near ring 15 m-1.5 km, 260 x 240; far ring 1.5-25 km, 160 x 200.

**Mesh script (tested):** `/Users/TAITA/Projects/ares/research/code/build_polar_mesh.py`
```bash
python3 -m venv .venv && .venv/bin/pip install numpy rasterio
.venv/bin/python research/code/build_polar_mesh.py \
  --hirise data/raw/hirise_dtm_5km_1m.tif --ctx data/raw/M20_JezeroCrater_CTXDEM_20m.tif \
  --lat 18.4446 --lon 77.4509 --az-center 305 --az-span 150 --r-split 1500 --r-max 25000 \
  --out-prefix data/mesh/jezero
```
Ran today: HiRISE-CTX median offset -2.07 m removed; near mesh 62,400 verts / 123,802 tris; far 32,000 verts / 63,282 tris; total 187,084 tris; OBJ files 7.0 MB + 3.7 MB. The script: samples both DEMs bilinearly by lat/lon (handles ts=0 vs ts=18.4663), blends HiRISE into CTX, **subtracts planetary curvature** d^2/(2*3389.5 km) so the world can be flat, zeroes heights at the eye's ground point (eye at y = 1.7 m above 0), writes planar east/north UVs (u=(E-E0)/W, v=(N-N0)/W where W = 2*r_split for near, 2*r_max for far), and checks triangle winding gives +Y normals. Unity's OBJ importer negates X, so the file stores X=-East: after import Unity +X = East, +Z = North. **Check the first import visually** (wrong handedness shows as a mirrored delta and inside-out faces). If it is mirrored, flip Scale X = -1 on the parent or drop the `-e` negation. UV/texture alignment: the near ortho covers E,N in [-1500,1500] (square) and the far one [-25000,25000], matching the script's uvW (3000 and 50000). Note the sector mesh covers only part of the square, so the texture is partly unused; that is fine.

glTF alternative: glTFast package in Unity can import GLB, but adds a dependency and loading code; OBJ needs none. Another low-dependency route: write a `.bin` of float32 heights and build the `Mesh` in a Unity C# `Start()` (UInt32 indices, `mesh.indexFormat = IndexFormat.UInt32` is required above 65k verts; the OBJ importer does this automatically).

**Textures:** HiRISE ortho is grayscale. Import as single channel or RGB and drive colour in the shader: `albedo = gray^1.1 * lerp(float3(0.42,0.24,0.15), float3(0.78,0.55,0.38), gray)` (HEURISTIC: Mars regolith is red-brown with dark basaltic floor; tune against Perseverance Mastcam-Z frames). Sizes: near 4096^2 ASTC 6x6 = 4096*4096/36*16 B = 7.5 MB (8x8 = 4 MB); far 4096^2 ASTC 8x8 = 4 MB; total < 12 MB. 2048^2 fallback if memory/thermals suffer. Enable mipmaps, aniso 4 on the near texture (floor viewed at grazing angles). Add a 1024^2 tiling regolith detail normal map (CC0 gravel) faded in within ~50 m to fake rocks. The only truly 3-D rocks should be a handful of hero props near the base.

**Vertical exaggeration:** none, scale = 1.0 on all axes. The real Jezero floor is nearly flat; the relief comes from the 90 m delta scarp 2.2 km away and the 3-4 deg rim. In a cardboard stereo app the horizon and parallax are tiny at those distances anyway (stereo depth cues vanish beyond ~30-100 m), so the sky and haze carry the sense of depth. If it looks too flat for the demo, do **not** scale heights: raise the camera (the room floor is a few metres above the regolith), or pick az 305 where the scarp is.

## 4. Sun position: Mars24 (Allison and McEwen 2000)

Source: https://www.giss.nasa.gov/tools/mars24/help/algorithm.html (page updated 2025-01-07). Steps (angles in degrees):
1. JD_UT = 2440587.5 + unix_ms/86400000. JD_TT = JD_UT + (TT-UTC)/86400, TT-UTC = 37 s (TAI-UTC) + 32.184 s = 69.184 s since 2017-01-01 (assumes no leap second since; error of one second is irrelevant here). dt = JD_TT - 2451545.0.
2. Mean anomaly M = 19.3871 + 0.52402073 dt. Fictitious mean sun alpha_FMS = 270.3871 + 0.524038496 dt.
3. Perturbers PBS = sum_{i=1..7} A_i cos(0.985626 dt / tau_i + phi_i): (A, tau, phi) = (0.0071, 2.2353, 49.409), (0.0057, 2.7543, 168.173), (0.0039, 1.1177, 191.837), (0.0037, 15.7866, 21.736), (0.0021, 2.1354, 15.704), (0.0020, 2.4694, 95.528), (0.0018, 32.8493, 49.095).
4. Equation of centre (nu - M) = (10.691 + 3.0e-7 dt) sin M + 0.623 sin 2M + 0.050 sin 3M + 0.005 sin 4M + 0.0005 sin 5M + PBS. Solar longitude Ls = alpha_FMS + (nu - M).
5. Equation of time EOT = 2.861 sin 2Ls - 0.071 sin 4Ls + 0.002 sin 6Ls - (nu - M) (degrees; /15 for hours).
6. Mars Mean Time at 0 deg: MST = mod24(24 * ((JD_TT - 2451549.5)/1.0274912517 + 44796.0 - 0.0009626)). Local mean solar time LMST = MST - Lambda_W/15 (Lambda_W = degrees WEST = 360 - east longitude). LTST = LMST + EOT/15.
7. Declination dec = asin(0.42565 sin Ls) + 0.25 sin Ls (degrees). Subsolar longitude (W) = 15 MST + EOT + 180.
8. Hour angle H = Lambda_W - subsolar_W. Zenith cos Z = sin(dec) sin(lat) + cos(dec) cos(lat) cos H; elevation = 90 - Z. Azimuth = atan2(sin H, cos(lat) tan(dec) - sin(lat) cos H), compass degrees clockwise from north (verified: ~99 deg = east in the morning, ~268 deg = west in the evening at Jezero).
9. Heliocentric distance R_M = 1.52367934 * (1.00436 - 0.09309 cos M - 0.004336 cos 2M - 0.00031 cos 3M - 0.00003 cos 4M) AU. Use it for solar irradiance: S = 1361 / R_M^2 W/m^2 (about 717 at perihelion down to 493 W/m^2 at aphelion, ~590 mean; keep consistent with the power model).

Sol length: 24 h 39 m 35.244 s = 88775.244 s (= 1.0274912517 days, the constant above). Sun apparent diameter from Mars is about 21 arcmin = 0.35 deg (from memory, not verified here).

**Implementation (validated):** `/Users/TAITA/Projects/ares/research/code/mars_sun.py` (stdlib only). Check against the NASA example (2000-01-06 00:00 UTC, 0 E): dt = 4.50074 (matches), Ls = 277.18759 (page: 277.18758), MST = 23.9942 h = 23:59:39 (matches). Sample output at Jezero (18.4446, 77.4509) today: Ls = 11.6 (northern spring, dust-storm season is Ls ~180-330), local noon elevation ~73 deg, sunset at LTST ~18.4 h. For the demo drive time by a "Mars clock" (LTST) and Ls directly (set `jd_tt` or bypass: pick Ls and LTST, compute dec from Ls, H from LTST).

Open-source references (to cross-check or port):
- `marstime` (Python), Christopher Lee, Modified BSD, https://pypi.org/project/marstime/ (functions solar_elevation, solar_azimuth, ...).
- `@xfanta/mars-time` (TypeScript), Modified BSD, port of marstime.
- No C# implementation found; the 60-line Python port above translates directly (use `System.Math`, `DateTimeOffset.ToUnixTimeMilliseconds`).
- Mars24 original: Java, no code license found; the algorithm itself is published (Allison and McEwen 2000, Planet. Space Sci. 48, 215-235; Allison 1997 GRL 24, 1967). Reimplementing the published formulas is fine; cite both.

## 5. Sky model

### What is physically known
- The Martian daytime sky is butterscotch/tan: airborne dust (radius ~1.5 um, Lemmon 2004) absorbs blue and scatters the rest; Rayleigh from CO2 would be blue but is overwhelmed.
- Near sunrise/sunset the sky around the sun turns blue: dust scatters strongly forward and blue is scattered slightly more forward than red, so a blue aureole (order 5 deg per the PIA19400 analysis, weak source) surrounds the sun while the rest of the sky stays tan/orange. Curiosity's first colour sunset: sol 956, PIA19400.
- Higher dust optical depth tau: direct sun dims as exp(-tau/sin elev) (Beer-Lambert; tau is by definition the exponent), more light becomes diffuse, shadows soften, the sky gets darker overall, redder/browner and more uniform, the sun disk fades; in the 2018 storm Curiosity saw tau above 8 and Opportunity ~11 (sun invisible). Background tau at Gusev/Meridiani ~0.9 early in the missions; Perseverance regional storm sol 1244 gave visibly hazier crater views (NASA 2024-09-05).
- Dust is well mixed to a scale height of ~11.6 km (Lemmon 2004), so near-surface horizontal extinction is about beta = tau / H = tau / 11.5 km.

I could not find published numbers for the diffuse-to-direct ratio versus tau in a fetched source; the curve below is a standard two-stream style approximation and marked HEURISTIC.

### Proposed cheap implementation: parameters as functions of (tau, sun elevation e)
Let s = clamp(sin e, 0.02, 1), tau in [0.2, 8] (clamp; 0.5 = clear, 1.0 = typical, 3 = regional storm, 6+ = global storm).

| Quantity | Formula (HEURISTIC, tune by eye against Perseverance/Curiosity frames) |
|---|---|
| Direct sun transmittance | T_dir = exp(-tau / (s + 0.05)) (cap airmass at ~20) |
| Sun light intensity | I_sun = I_0 * T_dir, I_0 from the irradiance in step 9, then exposure-mapped; at tau 0.5 noon: 0.75*I_0; tau 3: 0.05*I_0; tau 6: 0.002*I_0 |
| Diffuse/sky luminance (ambient + sky shader brightness) | L_sky = k * (1 - T_dir^0.6) * (0.35 + 0.65*s^0.5) * exp(-0.12*max(tau-2, 0)) (rises with tau up to ~2-3 as light is scattered into the sky, then falls as total light is absorbed) |
| Shadow strength (URP shadow intensity / soft shadow) | = T_dir / (T_dir + L_sky*0.8): ~0.8 at tau 0.5, ~0.35 at tau 3, ~0.05 at tau 6 (set directional light `shadowStrength`, or fade the shadow distance) |
| Zenith colour (linear RGB, day) | lerp( (0.55,0.38,0.26) @tau0.5 , (0.30,0.20,0.14) @tau3 , (0.16,0.10,0.07) @tau7 ) * L_sky |
| Horizon colour | lerp( (0.85,0.65,0.45) @tau0.5 , (0.55,0.38,0.26) @tau3 , (0.22,0.14,0.09) @tau7 ) * L_sky; horizon is brighter than zenith; the zenith-horizon contrast factor (1 - 0.8*tau/(tau+3)) goes toward flat as tau rises |
| Sun disk | colour (1.0,0.93,0.82) when high; as elevation falls multiply by T_dir per channel using tau_R=1.0*tau, tau_G = 0.9*tau, tau_B = 0.75*tau? NO - on Mars the blue extinction is *larger* (dust absorbs blue), so use tau_R = 0.8 tau, tau_G = 1.0 tau, tau_B = 1.3 tau so the low sun goes orange-red; disk angular radius 0.17 deg (sky shader smoothstep) |
| Blue halo (aureole) | colour (0.35,0.50,0.85); strength = smoothstep(25, 0, e_deg) * exp(-0.35*tau), i.e. only when the sun is low (below ~20 deg) and fades in storms; angular width = 5 deg + 4 deg*tau (broadens and dims as tau rises); Gaussian in angle (see shader) |
| Sun-direction brightening | day-side warm aureole: `exp(-angle/20deg) * 0.4 * L_sky` in orange (1.0,0.7,0.45) |
| Night / below horizon (e < -6 deg) | fade to ~0.02 and a faint dark blue-grey; skip stars unless wanted |
| Fog (URP: RenderSettings fog, Exp2 or custom) | beta = tau/11500 per metre; physical visibility ~ 3.9/beta = 90 km at tau 0.5, 15 km at tau 3, 7.5 km at tau 6. Use `density = 2.5*beta` for legibility (HEURISTIC, since the terrain ends at 25 km); fog colour = the horizon colour above, sampled in the camera direction |
| Ambient | `RenderSettings.ambientMode = Trilight`, sky = zenith colour, equator = horizon colour, ground = 0.5 * regolith albedo * (L_sky + 0.2*T_dir*s) |

This keeps everything driven by one scalar `tau` that your solar power model also reads: `P = P0 * (T_dir*s + diffuse_factor*L_sky)`.

### Shader sketch (URP skybox, Unlit HLSL, ~25 ALU)
Properties set from a C# `SkyController` every frame: `_Zenith`, `_Horizon`, `_SunDir`, `_SunColor`, `_HaloColor`, `_HaloWidth`, `_HaloStrength`, `_Tau`, `_Lum`.
```hlsl
float3 v = normalize(i.dir);
float h = saturate(v.y);                              // 0 horizon, 1 zenith
float3 sky = lerp(_Horizon.rgb, _Zenith.rgb, pow(h, 0.45));
float ang = acos(clamp(dot(v, _SunDir), -1, 1));      // radians
float halo = exp(-(ang*ang) / (2*_HaloWidth*_HaloWidth));   // gaussian
sky += _HaloColor.rgb * halo * _HaloStrength;
sky += float3(1,0.7,0.45) * exp(-ang*3.0) * 0.25 * _Lum;     // warm aureole
float disk = smoothstep(0.0035, 0.0030, ang);         // radius 0.17 deg ~ 0.003 rad
sky += _SunColor.rgb * disk * 40;                     // HDR; bloom needs HDR on
// below horizon: darken so a distant mesh edge never shows a hole
sky *= lerp(0.6, 1.0, smoothstep(-0.1, 0.05, v.y));
return float4(sky * _Lum, 1);
```
Hook the light: `RenderSettings.sun` directional light colour = `_SunColor`, intensity = I_sun; URP "Sky" ambient set via Trilight. Drive fog colour from the same horizon colour so the far mesh dissolves into the sky seamlessly (this is the main thing that sells the rim).

## 6. What would make this fail at 3am?

1. **Handedness/mirroring of the terrain in Unity** (delta appears on the east instead of west, faces inside-out). Check in the first 10 minutes; fix with Scale X = -1 or the `-e` flag.
2. **Texture/mesh misalignment** (UV extents, near ortho vs mesh): the UV rectangle is [-1500, 1500] (near) and [-25000, 25000] (far) in east/north metres centred on the eye; the ortho crop must use exactly those `-te` values and must be in the aeqd CRS, not the raw equirect (which stretches E-W by 5%).
3. **Ortho crop is 7.3 GB striped with 12000-row reads over HTTP**; it was slow and, if the network drops, stalls. Fallback: use the tiled/LZW `blend120` (007) ortho (different CRS, orthographic at 18.4663/77.4298, so use gdalwarp not projwin; accept small misregistration), or the CTX ortho for everything (5 m/px, softer but fine at 1.7 m eye height if you add the detail normal map). Status of my ortho crop: see the result line at the bottom of this file.
4. **GDAL not installed** (brew was busy with `unity-hub` + `gdal` queued by another process). Fallback that already works: rasterio wheel in a venv (`pip install rasterio numpy`, GDAL 3.12.2 bundled, Python 3.14 wheel available), and the mesh script only needs rasterio+numpy.
5. **Download hosts:** the planetarymaps.usgs.gov URLs 302 to S3 and one GET reset the connection; use the direct S3 URLs and `curl -C -` (resume). Contention from parallel brew downloads dropped throughput to ~1 KB/s at one point.
6. **Datum offset:** HiRISE vs CTX differ by ~2 m near the site (handled); at the far west the CTX DEM runs out at lon 77.00 E (~27 km), so r_max 25 km; larger values give NaNs/flat fill.
7. **Terrain is boring-flat**: the floor is within a ~30 m height range in the first 1.5 km (computed -5..37 m). The view works because of the scarp (2.4 deg) and rim (3-4 deg), and only if you look WNW (az 285-330). Eastward there is no rim. Design the window orientation first.
8. **Floating-point precision in Unity** for origin-at-eye local coordinates: fine (<25 km). Do not use projected metres (4.59e6) as world coordinates (float32 jitter).
9. **Dust fog density** under Unity's fog with 25 km far plane: set camera far clip to >= 30 km and use a reverse-Z friendly near plane >= 0.1 m; keep terrain meshes in a layer with no shadows; otherwise z-fighting/precision flicker at distance in stereo.
10. **Mobile cost surprises**: HDR + bloom for the sun disk, SSAO, soft shadows, and MSAA 4x in stereo can blow the frame budget before triangle count does. Start with MSAA 2x, no post except a cheap bloom (or fake the sun with a billboard), one shadow cascade.
11. **tau-to-look tuning is subjective** (my curves are HEURISTIC). Budget an hour to compare against Perseverance Mastcam-Z/NavCam frames (https://mars.nasa.gov/mars2020/multimedia/raw-images/) at known tau (Mastcam-Z tau record: https://data.mendeley.com/datasets/gktjp9jptb) and tweak `lerp` endpoints; the hazard is spending the night on this instead of the room.
12. **Credit line missing** on a screen: put it in the splash/end card.
13. **Mars24 leap-second constant** (37 s) assumes no leap seconds after 2017; harmless (1 s = 0.0001 deg of solar motion).

## Files
- `/Users/TAITA/Projects/ares/research/code/mars_sun.py` - Mars24 solar elevation/azimuth (validated vs GISS example).
- `/Users/TAITA/Projects/ares/research/code/build_polar_mesh.py` - DEM -> polar OBJ meshes (tested).
- `/Users/TAITA/Projects/ares/data/raw/M20_JezeroCrater_CTXDEM_20m.tif` (90 MB), `hirise_dtm_5km_1m.tif` (55 MB), `hirise_ortho_3km_0p5m.tif` (if the crop finished).

## Status at time of writing
- Downloaded/created: CTX DEM (90 MB), HiRISE DTM 5 km crop (55 MB). The 3 km HiRISE ortho crop (`crop_rasterio.py`, second call) was still running in the background (striped 7.3 GB source, ~12000 row reads); if `data/raw/hirise_ortho_3km_0p5m.tif` is absent, re-run `research/code/crop_rasterio.py` or use the tiled blend120 ortho / CTX ortho fallback in section 6.3. The CTX ortho (360 MB) was not downloaded.
- Not run: GDAL CLI commands (no GDAL installed yet); rasterio equivalents were run instead. Not built/tested in Unity.
