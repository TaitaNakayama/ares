# Verify 03: libraries and terrain (adversarial check)

Checked 2026-10-23 (local; 2026-10-24 02:05 UTC). Machine: MacBook Air M3, macOS 26.3, Node 26.10.0, pnpm 10.34.6, Python 3.14.7.
Method: live registry/API queries plus local spikes. Everything was installed only in the session scratchpad (`.../scratchpad/spike-ts`, `spike-node`, `spike-js`, `venv-rio`). Nothing was installed globally.

## Verdict summary

| # | Claim | Verdict | Main catch |
|---|---|---|---|
| 1 | TS 7.0.2 native `tsc --noEmit` with erasableSyntaxOnly / allowImportingTsExtensions / nodenext | **HOLDS** | TS 7 ships no classic JS compiler API. typescript-eslint 8.72 needs `typescript <6.1.0`. |
| 2 | Node 26.10 runs `.ts` directly, including through pnpm workspace symlinks | **HOLDS** | enum, parameter properties, runtime namespaces, decorators, `.tsx` and anything under `node_modules` are rejected. `--experimental-transform-types` was removed in v26.0.0. |
| 3 | vitest 5.0.5, fast-check 4.10.2, zod 4.6.7, ws 8.22.0, React 19.3.1, Vite 8.3.5, astronomy-engine 2.1.19 | **HOLDS** | astronomy-engine is dormant (last npm release 2023-12-14, last commit 2025-01-27). Light time works. |
| 4 | `openai` SDK latest, tool calling, current models | **HOLDS, with a constraint** | Latest is **7.43.0**. GPT-6-family tool calling needs the **Responses API**. Chat Completions with tools does not work on gpt-6.1-sol, and works on gpt-6-luna only with `reasoning_effort: none`. |
| 5 | CoplayDev/unity-mcp v10.3.0, MIT, Unity 6000.0.x, Claude Code, needs uv | **LIKELY HOLDS** | `uv` is **not installed** on this Mac. There are open macOS session-drop bugs (#1207, #1265, #1454). The README pin (`#v10.0.0`) is stale. |
| 6 | rasterio wheels for py3.14 / macOS arm64 bundle GDAL, so `/vsicurl/` works without a system GDAL | **HOLDS** | Functionally true (tested). On these particular files it is very slow (see 7). |
| 7 | USGS Jezero HiRISE/CTX products are public, range-readable and usable with credit | **HOLDS** | The files are **not COGs**: 1-row strips, no compression, no overviews. Windowed reads are slower than downloading. CTX and HiRISE use **different projections**. |
| 8 | ~190k-tri terrain + 2×4096² ASTC 6x6 + <100k interior, steady 60 fps stereo, iPhone 16 Pro, URP | **LIKELY HOLDS** (GPU budget) / **unproven** (frame pacing) | No public triangle-rate benchmark exists. Cardboard is multi-pass only. Unity XR on iOS ignores `targetFrameRate`, and a related bug was closed Won't Fix. Thermal stability is 67–90%. |

---

## 1. TypeScript 7.0.2 native compiler: HOLDS

**Evidence**
- `npm view typescript` returns `latest = 7.0.2`, Apache-2.0, with `@typescript/typescript-darwin-arm64@7.0.2` (os darwin, cpu arm64) as an optional dependency. npm publish time is 2026-07-08T15:55Z; the GitHub release `v7.0.2` is dated 2026-08-20. Other tags: `beta = 7.1.0-beta` (GitHub v7.1-beta 2026-10-20) and `next = 7.1.0-dev.20261023.1`.
- Spike (`spike-ts`): `tsc --version` printed `Version 7.0.2`. The tsconfig used `module/moduleResolution nodenext`, `erasableSyntaxOnly`, `allowImportingTsExtensions`, `verbatimModuleSyntax`, `noEmit` and `strict`.
  - A clean project with `import { add, type Pt } from "./a.ts"` exits 0 in 0.24 s wall time.
  - With `enum` and a parameter property added, it exits 1 with `TS1294: This syntax is not allowed when 'erasableSyntaxOnly' is enabled` (correct).
  - `tsc --help --all` lists `--erasableSyntaxOnly`, `--allowImportingTsExtensions` and `--rewriteRelativeImportExtensions`.
- The GitHub issue search on microsoft/TypeScript turned up no open issues on `erasableSyntaxOnly` since 2026-06. Two open issues mention `allowImportingTsExtensions` (#64828 language-service go-to-definition; #64028 TS5097 not reported for `require()`/side-effect imports). Neither blocks `--noEmit` checking.

**Counter-evidence and caveats**
- **No classic compiler API.** `require("typescript")` on 7.0.2 exports only `version` and `versionMajorMinor`. The package `exports` map exposes only `./unstable/sync`, `./unstable/async`, `./unstable/ast/*`, and so on. Any tool that imports the TypeScript JS API breaks if it resolves `typescript@7`.
- typescript-eslint 8.72.0 and @typescript-eslint/parser declare the peer `typescript: ">=4.8.4 <6.1.0"`, so they do **not** support TS 7. The same probably applies to ts-morph, vite-plugin-dts, ts-json-schema-generator and others (inferred; not individually checked).
  - Option: keep 7.0.2 for `tsc --noEmit` only and give API-dependent tools a 6.0.3 copy. Watch the bin-name clash, since both packages ship `tsc`.
- `microsoft/typescript-go` is **archived** (last push 2026-08-31). Development is in microsoft/TypeScript. Report bugs there, not in the old Go repo.

**Sources (accessed 2026-10-23)**
- https://registry.npmjs.org/typescript (`npm view`)
- https://api.github.com/repos/microsoft/TypeScript/releases
- https://api.github.com/repos/microsoft/typescript-go
- https://registry.npmjs.org/typescript-eslint

**Spike**: Already run; reproduce with `pnpm add -D typescript@7.0.2 && pnpm exec tsc --noEmit -p .` in the real repo. Then run every dev tool (eslint, vitest `--typecheck` if used, any codegen) and confirm none of them `require("typescript")` and get only `{version}`.

## 2. Node 26.10 runs `.ts` directly: HOLDS

**Evidence**
- `process.features.typescript === "strip"` on v26.10.0. `node --help` lists only `--experimental-strip-types` and `--no-strip-types`.
- Node docs (page for v26.12.1): type stripping is "Stability: 2 - Stable" and enabled by default. History table: stable since v25.2.0/v24.12.0, no warning since v24.3.0, and **"v26.0.0: Removed `--experimental-transform-types` flag."** Running `node --experimental-transform-types` on 26.10.0 gives "bad option".
- pnpm workspace spike (`spike-node`): `@ares/app` depends on `@ares/core` (`workspace:*`, exports `./src/index.ts`, which re-exports `./helper.ts`). pnpm created `packages/app/node_modules/@ares/core -> ../../../core`. `node src/main.ts` printed `len 5 OK strip` and exited 0. Node resolves the symlink to its real path, which is outside `node_modules`, so stripping is allowed.

**Counter-evidence and caveats (all reproduced)**
- `enum`: `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX: TypeScript enum is not supported in strip-only mode`.
- Parameter properties: `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX ... parameter property`.
- Namespaces with runtime code: `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX ... namespace declaration`. Type-only namespaces are allowed per the docs.
- A `.ts` file physically under `node_modules`: `ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`. Under **`node --preserve-symlinks`** the same workspace import fails with this error. It also fails if pnpm is configured to **inject** workspace packages (`inject-workspace-packages` / `dependenciesMeta.injected`, which copies them into `node_modules/.pnpm`), or for any published package that ships `.ts`. That last part is inferred from the same rule.
- Per the docs: decorators, import aliases (`import x = require`), `tsconfig` `paths` and `.tsx` are unsupported. Extensions are mandatory (`./x.ts`). Type-only imports must use `import type` or inline `type`, so set `verbatimModuleSyntax`. `tsconfig.json` is ignored entirely, and there is no type checking.
- There is now **no built-in escape hatch** for enums: the transform flag is gone, so the alternative is `tsx`. `erasableSyntaxOnly` in tsconfig catches these cases at check time.

**Sources (accessed 2026-10-23)**
- https://nodejs.org/api/typescript.html (doc version v26.12.1)
- Local spike output (Node v26.10.0)

**Spike**: Already run. In the real repo, add a CI step: `node --no-warnings packages/<each-entry>.ts` plus `tsc --noEmit` with `erasableSyntaxOnly`. Grep `.npmrc` and `package.json` for `inject`/`preserve-symlinks`.

## 3. JS libraries: HOLDS

| Package | Version (latest?) | License | Published | Notes |
|---|---|---|---|---|
| vitest | 5.0.5 (latest) | MIT | 2026-10-15 | engines `^22.12 \|\| ^24 \|\| >=26`. Peer vite `^6.4 \|\| ^7 \|\| ^8`. |
| fast-check | 4.10.2 (latest) | MIT | 2026-09-19 | |
| zod | 4.6.7 (latest) | MIT | 2026-10-12 | |
| ws | 8.22.0 (latest) | MIT | 2026-09-26 | `openai@7.43.0` peer `ws ^8.21.0` is satisfied. |
| react | 19.3.1 (latest) | MIT | 2026-10-14 | `@vitejs/plugin-react@6.1.2` peer `vite ^8.0.0`. |
| vite | 8.3.5 (latest) | MIT | 2026-10-21 | engines `^20.19 \|\| >=22.12`. |
| astronomy-engine | 2.1.19 (latest) | MIT | **2023-12-14** | Repo not archived, but last commit 2025-01-27, 49 open issues, 1066 stars. |

**Spikes, all run directly as `.ts` under Node 26.10 (`spike-js`)**
- `z.toJSONSchema` exists and emits a 2020-12 schema; `{target: "draft-7"}` also works.
  - Gotcha: `z.number().int()` emits `minimum/maximum` of ±9007199254740991.
  - Gotcha: `.optional()` fields are left out of `required`, which conflicts with OpenAI strict function schemas.
  - `openai/helpers/zod` `zodResponsesFunction` / `zodFunction` accept zod 4 objects. They emit `strict: true`, draft-07, all keys required, and work when optional fields are written as `.nullable()`.
- **astronomy-engine light time works**: `GeoVector(Body.Mars, date, true).Length() * KM_PER_AU / c`.
  - 2026-10-23: 1.50422 AU, **12.51 min** one way.
  - 2027-02-19: 0.67802 AU, 5.64 min.
  - 2025-01-12: 0.64231 AU, 5.34 min. This matches the known 2025-01-12 closest approach (~96 M km).
  - `C_AUDAY` and `CorrectLightTravel` are exported.
- ws: a server/client round trip on an ephemeral port returned `echo:hi`.
- vitest 5.0.5 with a fast-check 4.10.2 property test: 1 passed, 110 ms.

**Counter-evidence**: astronomy-engine has had no release in about 22 months. It is a pure computation library with no deps, so the risk is low. Pin it and vendor a fallback if needed.

**Sources (accessed 2026-10-23)**
- https://registry.npmjs.org/<pkg> (`npm view` for each)
- https://api.github.com/repos/cosinekitty/astronomy

## 4. `openai` npm SDK and current models: HOLDS (with constraint)

**Evidence**
- `openai` **latest = 7.43.0**, Apache-2.0, published 2026-10-22T21:54Z, engines `node >=22`. Peers include `zod ^3.25 || ^4.0` and `ws ^8.21.0`. In the spike, `client.responses.create`, `client.chat.completions.create` and `client.models.list` are all functions, and `openai/version` reports 7.43.0.
- Official models page (https://developers.openai.com/api/docs/models; platform.openai.com/docs/models 301-redirects there):
  - Flagships: `gpt-6-astra` ("start with" recommendation), `gpt-6.1-sol` and `gpt-6-luna`. All support function calling, a 1.05M-token context and 128K output.
  - Realtime models with tool use: `gpt-realtime-2.1`, `gpt-realtime-2.1-mini` and `gpt-realtime-2`.
  - Deprecated: `gpt-realtime-mini`, `gpt-4o-mini-tts`, `gpt-4o-transcribe` and `gpt-4o-mini-transcribe`.
- Changelog (latest entry 2026-10-22):
  - `gpt-6-astra` released 2026-09-03; its tool calling "requires the Responses API".
  - `gpt-6-sol` and `gpt-6-luna` released 2026-09-22; `gpt-6.1-sol` released 2026-09-29.
  - The previous generation is `gpt-5.6-sol/-terra/-luna` (2026-07-09).
  - The Assistants API shut down on 2026-08-26.
- `gpt-6.1-sol` model page: "Use the Responses API for tool calling." "Chat Completions is supported without tool calling." $2 in / $10 out per 1M tokens. Reasoning effort `low` to `max`; `none`/`minimal` are not supported.
- `gpt-6-luna` model page: "Chat Completions supports function calling only with `reasoning_effort` set to `none`." $0.10 in / $0.50 out per 1M tokens. Effort `none` to `max`.

**Counter-evidence**: Any design that uses `chat.completions.create({tools})` with GPT-6 models is wrong. Use `client.responses.create({ model: "gpt-6.1-sol" | "gpt-6-luna", tools: [zodResponsesFunction(...)] })`.
- For tool calling: `gpt-6.1-sol` is the balanced default and `gpt-6-luna` the cheap, high-volume option. Use `gpt-6-astra` only if quality demands it; it allows no custom `temperature`/`top_p`.

**Sources (accessed 2026-10-23)**
- https://developers.openai.com/api/docs/models
- https://developers.openai.com/api/docs/models/gpt-6.1-sol
- https://developers.openai.com/api/docs/models/gpt-6-luna
- https://developers.openai.com/api/docs/changelog
- https://registry.npmjs.org/openai

**Spike** (needs an API key; not run):
1. Make one `responses.create` call with a `light_time` function tool on `gpt-6.1-sol` and on `gpt-6-luna`. Assert the response contains a `function_call` item, then send a `function_call_output` and get the final text.
2. Make one `chat.completions.create` call with tools on `gpt-6.1-sol` and confirm it is rejected.

## 5. CoplayDev/unity-mcp v10.3.0: LIKELY HOLDS

**Evidence**
- Repo is not archived, MIT (LICENSE "Copyright (c) 2025 CoplayDev"), 15,356 stars, 112 open issues, last push 2026-10-19. The default branch is **`beta`**.
- Release `v10.3.0` was published 2026-10-04. Its notes include "fix: Claude Code registrations invisible to CheckStatus" (#1280) and Unity 6 fixes (#1399 for 6000.6, #1423 Unity 6 `.meta` parse).
- At tag v10.3.0, `MCPForUnity/package.json` has `"version": "10.3.0"` and `"unity": "2021.3"` (minimum), so 6000.0.x is allowed.
- README: "Unity **2021.3 LTS → 6.x** · Python **3.10+** (via `uv`) ... Claude Desktop & Code".
- The PyPI server package `mcpforunityserver` 10.3.0 is MIT with `requires_python >=3.10`.
- No open issues mention "6000.0".

**Counter-evidence**
- **`uv`/`uvx` is not installed** on this machine: not on PATH, not in `/opt/homebrew/bin`. Run `brew install uv` first.
- Open macOS bugs relevant to a Claude-Code-driven, often-unfocused editor:
  - #1207: macOS HTTP transport WebSocket drops (close 1005) on reload/test boundaries, giving `no_unity_session`.
  - #1265: session drops after domain-reload churn and re-registers only on editor focus. Reported on macOS 26.2 with Claude Code.
  - #1454: EditMode `run_tests` always fails at 15 s when the editor is unfocused, and the orphaned run keeps the lock.
  - #1397 (Windows, cosmetic): Claude Code shows "Not Configured" while connected.
- The README's install line says `#main` and "pin `#v10.0.0` for this release", which is stale. Pin `...?path=/MCPForUnity#v10.3.0`.

**Sources (accessed 2026-10-23)**
- https://api.github.com/repos/CoplayDev/unity-mcp
- https://github.com/CoplayDev/unity-mcp/releases/tag/v10.3.0
- README and `MCPForUnity/package.json` at v10.3.0
- Issues #1207, #1265, #1397 and #1454
- https://pypi.org/pypi/mcpforunityserver/json

**Spike**
1. `brew install uv`. Create a Unity 6000.0.x project (at least 6000.0.58f2; see 8) and add the package by git URL `#v10.3.0`. Use Window, then MCP for Unity, then Configure Claude Code.
2. `claude mcp list` shows it connected. Ask it to create a cube.
3. Force a script recompile (domain reload) with the editor **in the background**, and confirm the next tool call works.
4. Run `run_tests` EditMode with the editor unfocused. Workaround to test: set Preferences, General, Interaction Mode to "No Throttling".

## 6. rasterio wheels bundle GDAL; `/vsicurl/` works without a system GDAL: HOLDS

**Evidence**
- PyPI `rasterio` latest is 1.5.2 (uploaded 2026-09-30), BSD-3-Clause, `requires_python >=3.12`. Wheels include `rasterio-1.5.2-cp314-cp314-macosx_15_0_arm64.whl` (23.5 MB) and also cp314t, cp315 and cp315t.
- Spike: a fresh venv with Python 3.14.7 arm64 and `pip install --only-binary=:all: rasterio==1.5.2`.
  - It reports `rasterio 1.5.2, gdal 3.12.2`.
  - `.dylibs` contains `libgdal.38.3.12.2`, `libcurl.4`, `libproj.25.9.8.1`, libtiff, libssl, libnghttp2 and others. `proj_data/proj.db` is bundled; `CRS.from_epsg(4326)` and Mars `eqc` transforms work.
  - **No Homebrew GDAL is installed** (`/opt/homebrew/bin/gdalinfo` is absent), yet `/vsicurl/https://asc-pds-services...` opens and windowed reads succeeded on all four products.

**Counter-evidence**: The macOS wheel tag is `macosx_15_0`, so it needs macOS 15 or later (26.3 is fine). The practical limit is the files' layout, not rasterio; see 7.

**Sources (accessed 2026-10-23)**: https://pypi.org/pypi/rasterio/json and the local spike.

## 7. USGS Mars 2020 Jezero products: HOLDS (but they are not cloud-optimized)

**Availability**: anonymous S3 `ListObjectsV2` on `asc-pds-services` with prefix `mosaic/mars2020_trn/`. HEAD gives 200 and `Accept-Ranges: bytes`, and `Range: 0-1023` gives 206. CORS is `Access-Control-Allow-Origin: *` with GET and HEAD allowed. `planetarymaps.usgs.gov/mosaic/...` 302-redirects to the same S3 object.

| Product | Key | Size | Raster |
|---|---|---|---|
| HiRISE 1 m DTM | `HiRISE/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40.tif` | 1.84 GB | 21400×21488 float32, nodata −3.4028e38, `eqc lat_ts=0`, extent ≈21.4×21.5 km |
| HiRISE 25 cm ortho | `HiRISE/JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first.tif` | 7.36 GB | 85600×85952 uint8, nodata 0, `eqc lat_ts=0`. Alternatives: `..._first_dd.tif` (9.82 GB) and `JEZ_hirise_soc_007_orthoMosaic_25cm_Ortho_blend120.tif` (3.41 GB, "Surface Operations") |
| CTX 20 m DEM | `CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXDEM_20m.tif` | 90 MB | 4456×5067 float32, `eqc lat_ts=18.4663`, extent ≈89×101 km |
| CTX 5 m ortho | `CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif` | 360 MB | 17766×20234 uint8, **no nodata set**, `eqc lat_ts=18.4663` |

All four files are Last-Modified 2022-11-10.

**License and credit**
- HiRISE TRN products: FGDC metadata `accconst None`, `useconst None`. The USGS catalog page says "Use Constraints: Please cite authors", publisher USGS Astrogeology, published 2020-07-24.
  - DOIs: 10.5066/P9REJ9JN (DTM) and 10.5066/P9QJDP48 (ortho).
  - Cite Fergason et al. 2020 (LPSC 51) and McEwen et al. 2007.
- USGS policy: "USGS-authored or produced data and information are considered to be in the U.S. Public Domain"; credit "U.S. Geological Survey". The USGS logo is trademarked.
- HiRISE imagery: "public domain", "no copyright restriction"; requested credit "Image: NASA/JPL/University of Arizona".
- CTX DEM and ortho: these are **JPL "Science Investigation" PDS4 products** (`urn:nasa:pds:mars2020_ctx_basemap_2021:data:m20_ctxdem_mosaic`), not USGS-authored, and they cite **Mangold et al. 2021, *Science*, doi:10.1126/science.abl4051**.
  - JPL image policy: usable "for any purpose without prior permission", credit "Courtesy NASA/JPL-Caltech", no implied endorsement, and NASA/JPL logos need written approval.
  - Add MSSS for CTX by convention: "NASA/JPL-Caltech/MSSS". The MSSS policy was not checked.
- Suggested credit block: "HiRISE DTM/orthomosaic: USGS Astrogeology (Fergason et al. 2020), NASA/JPL/University of Arizona. CTX DEM/ortho: NASA/JPL-Caltech/MSSS, Mangold et al. 2021." Use no NASA or USGS logos.

**Counter-evidence (practical)**
1. **They are not COGs.** rasterio reports `tiled False`, `block (1, width)` (one-row strips), `compress None` and `overviews []` for all four files.
   - Measured time for a 512×512 window from mid-raster: CTX DEM 23 s, CTX ortho 15 s, **HiRISE DTM 83 s, HiRISE ortho 144 s**. That is about one HTTP round trip per row.
   - Bulk throughput from this network was about 4.9 MB/s (200 MB in 42.5 s). Downloading the entire 1.84 GB DTM (about 6 min) is faster than one 10000-row windowed read (about 27 min by extrapolation).
   - Any decimated read (out_shape) touches every strip, which is effectively the whole file.
   - **Plan instead**: one-time full download (`curl`, or `aws s3 cp --no-sign-request`), then `gdal_translate -of COG` or `gdalwarp` locally. Budget about 10–12 GB disk and about 30–40 min at this bandwidth.
2. **Projection mismatch.** The HiRISE TRN products use `+proj=eqc +lat_ts=0` and the CTX JPL products use `+proj=eqc +lat_ts=18.4663` (both R=3396190).
   - The same point has x coordinates differing by a factor of 0.9485.
   - A HiRISE "1 m" pixel is only about 0.949 m of ground east-west at Jezero (cos 18.47°).
   - Reproject both to one local frame before blending the near and far meshes, or the seams will be offset by kilometres.
3. The HiRISE DTM footprint is irregular (nodata fill), so verify that the chosen near-mesh centre has valid data out to 5 km in every direction. The CTX extent (about 89×101 km) comfortably covers a 25 km radius.
4. Picking the "25 cm HiRISE orthomosaic" is ambiguous; choose between soc_006 `_first` and soc_007 `blend120` explicitly. A 4096² texture over a 10 km disc is about 2.4 m/texel, so the 25 cm source gets heavily decimated anyway.

**Sources (accessed 2026-10-23)**
- https://asc-pds-services.s3.us-west-2.amazonaws.com/?list-type=2&prefix=mosaic/mars2020_trn/ and the per-file HEAD/range/`.xml` requests
- https://astrogeology.usgs.gov/search/map/Mars/Mars2020/JEZ_hirise_soc_006_DTM_MOLAtopography_DeltaGeoid_1m_Eqc_latTs0_lon0_blend40
- https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits
- https://uahirise.org/media/usage.php
- https://www.jpl.nasa.gov/jpl-image-use-policy/ (v3.2.0)

**Spike**: download the four files. Run `gdalinfo`, then `gdalwarp -t_srs "<local eqc or ortho centred on site>" -r bilinear` and `-of COG`. Sample a 5 km-radius disc for nodata, and confirm the CTX/HiRISE height offset at overlap is under a few metres (both are MOLA-referenced).

## 8. 190k-tri polar terrain + interior at steady 60 fps in Cardboard on iPhone 16 Pro: LIKELY HOLDS (GPU), unproven (pacing)

**No public triangle-throughput or draw-call benchmark exists for A17 Pro or A18 Pro.** I found none in UL, GSMArena, Android Authority, Beebom, Unity docs or the Cardboard issues. The verdict therefore rests on proxies and arithmetic.

**Budget arithmetic**
- Geometry: at most 290k triangles. Cardboard is **multi-pass only** (googlevr/cardboard #142 "Single Pass Support" has been open since 2020), so that becomes about 580k triangles submitted per frame, about 35 M tris/s at 60 Hz. Draw calls are about 2×(a handful), which is trivial.
  - Proxy: Meta's Quest 3 guidance is <1.5 M triangles per frame and <200 draw calls at 72 Hz, with 90 Hz recommended, on XR2 Gen 2 (Adreno 740-class).
  - A18 Pro 3DMark Wild Life Extreme (4K, deferred PBR, SSAO, TAA): 4248 (UL listing via search; the UL page did not render) to 4898 (GSMArena), about 25–29 fps. That is at or above Snapdragon 8 Gen 2-class.
- Pixels: 2622×1206 ≈ 3.16 MP per frame (both eyes share the screen) plus Cardboard's distortion composite. That is about 190 MP/s at 60 Hz. WLE shades about 8.3 MP at 25+ fps with much heavier shaders, so unlit or simple-lit, shadowless terrain should use well under half the GPU.
- Textures: 4096² ASTC 6x6 = 683² blocks × 16 B ≈ 7.5 MB, about 10 MB with mips, so about 20 MB for both. Negligible.

**Counter-evidence and risks to "steady"**
1. **Frame-rate control.** Unity 6 docs: "XR platforms ignore both" `vSyncCount` and `targetFrameRate`, and "the XR SDK controls the frame rate".
   - Unity issue UUM-43316 (XR on iOS drops to 5 fps when `Application.targetFrameRate` is set; repro project "Unity-cardboard-bugs") is **Won't Fix**, affected versions list 6.0.X, and the workaround is private.
   - Cardboard #267 "Add FPS setting to XR Plugin" is open; a commenter reports that Unity's frame-rate setting does not work.
   - Keep **ProMotion off** (the Unity default, giving a native 60 Hz) and never set `targetFrameRate`. Otherwise pacing on the 120 Hz panel is undefined.
2. **Thermals.**
   - 3DMark stability for iPhone 16 Pro Max: 75% WLE and 86% Solar Bay (Android Authority, 2024-09-27), and 90% GPU (GSMArena, 2024-10-01).
   - Beebom's A18 Pro WLE stress runs gave 90.1% and 67.7%; UL Steel Nomad Light shows 71% for the 16 Pro (via search).
   - The non-Max 16 Pro has less thermal mass, and a closed Cardboard viewer traps heat. Design for about 65% sustained GPU, which means a start-of-session GPU time of about 8–10 ms.
3. **Cardboard plugin on Unity 6 / iPhone 16.**
   - `com.google.xr.cardboard` 1.36.0 (2026-10-15) declares `"unity": "6000.0", "unityRelease": "58f2"`, so the 6000.0.x editor must be **at least 6000.0.58f2**.
   - #523 (double-render/dim image on iPhone 16/17, iOS 26) was closed on 2026-08-20 with "use Unity 6 or 6.2"; the maintainer tested on iPhone 16.
   - #442 (MSAA on iPhone 15 Pro Max shows VR and non-VR overlaid) is still open, which is a further reason to keep MSAA off.
   - Tested iOS devices: v1.36 on iPhone 13 mini and iPhone 16, v1.35 on iPhone 15 Pro and iPhone 17. The 16 Pro is not explicitly tested.
4. Minor items:
   - Unity meshes default to 16-bit indices (65,535 vertices); a single 190k-tri mesh (about 95k vertices) needs `IndexFormat.UInt32`, or split it.
   - The polar-grid pole produces sliver and micro triangles with poor 2×2 quad efficiency. Collapse the innermost rings.
   - With MSAA off and no post-AA, expect visible edge shimmer (quality, not performance).

**Sources (accessed 2026-10-23)**
- https://github.com/googlevr/cardboard-xr-plugin (`package.json`, release v1.36.0)
- https://github.com/googlevr/cardboard issues #142, #267, #442, #523
- https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Application-targetFrameRate.html
- https://issuetracker.unity.com/issues/13691/frame-rate-of-the-xr-application-on-ios-devices-is-affected-when-using-applicationtargetframerate
- https://developers.meta.com/horizon/resources/device-optimization-comparison/
- https://www.androidauthority.com/iphone-16-pro-max-benchmarks-3484521/ (2024-09-27)
- https://www.gsmarena.com/apple_iphone_16_pro_max-review-2750p4.php (2024-10-01)
- https://beebom.com/apple-a18-pro-benchmarks/amp/ (via search)
- https://benchmarks.ul.com/hardware/phone/Apple+iPhone+16+Pro+review (via search; the page itself did not render)

**Spike (go/no-go before content work)**
1. Build a scene in Unity at least 6000.0.58f2 with URP, Cardboard 1.36.0, Metal, MSAA off, no shadows, no post, and ProMotion off.
   - Content: two procedural polar log-radial meshes totalling 190k triangles (UInt32 indices), two 4096² ASTC 6x6 textures, and a 100k-triangle interior.
2. Run on the iPhone 16 Pro **inside the viewer** at 80% brightness for 20 min while the head-pose script sweeps the view.
3. Record with the Xcode Metal HUD / Instruments (Game Performance template): GPU time, frame time and `ProcessInfo.thermalState`.
4. Pass: p99 frame time ≤ 16.7 ms, under 1% missed frames over 20 min, start GPU time ≤ 9 ms, and no `.serious` thermal state.
5. Repeat at 2× triangles to measure headroom.
