# Spike 17 (claim C-17): ground-level Jezero with near-field detail, stereo, 60 fps

Status: **INCOMPLETE. Only the baseline configurations were measured on the phone; the rock, storm and room-hidden configurations were not.** The phone's link to the server stopped connecting partway through (see "What went wrong"). Nothing below is presented as measured unless it says so.

## Setup (code is flagged, normal demo unchanged)
- Branch `worktree-agent-aad2ce280b41e9c8e`. Enable with `ARES_GROUND=1 scripts/build-ios.sh` (bakes `"ground": true` into the gitignored ares.json), or launch args `--ground`, `-ground YES`. Extra args: `--ground-window <s>` (default 70), `--ground-hold <config index>`.
- `vr/AresVR/Sources/GroundSpike.swift` (iOS only). Shared-code edits are two lines: `BaseScene.viewOffset` is now `var`, `BaseScene.outside` is no longer private.
- Judge: 40 m from the habitat on terrain azimuth 305 (the middle of the terrain wedge), head 1.6 m above the near-mesh ground (ground 0.37 m, head y = 1.97), facing out (-Z, the delta, props and drill in view). One config turns the judge to face the habitat. Room, screens and robots stay loaded; real terrain, Mars24 sun and sky unchanged.
- Detail: 512 px tileable procedural noise (mean 0.86) in the near terrain's `multiply` channel, 1 tile per ~1.2 m, mipmapped, anisotropy 8, diffuse intensity raised by 1/0.86 to hold brightness. Mip filtering is the distance fade (no shader modifier; one extra texture sample per terrain pixel).
- Rocks: 400 flat-shaded 80-triangle pebbles (6 variants, sizes 4-90 cm, median ~12 cm), within 1.5-25 m, resting on the near mesh via hit test. Batched = merged with `flattenedClone` into 16 chunks (8 azimuth sectors x base/extra, so chunks cull when the head turns), 1 material. Loose = 400 separate nodes sharing 6 geometries.
- Config cycle (70 s each, first 10 s of each discarded; avg/min fps and frames >20 ms / >33 ms reported in `vr_stats` as `cfgResults`): r0 plain, r0 detail, r150 plain, r150 detail, r400 plain, r400 detail, r400 detail loose, r400 detail no-room, r400 detail storm (tau 4.6), r400 detail storm no-room, r400 detail facing habitat.

## Measured
| Config | fps avg (60 s) | min | thermal | frames >20 ms |
|---|---|---|---|---|
| r0, plain, judge outside, room loaded | 59.9-60.0 | 59.9 (1 s samples) | nominal (0) | not captured |
| r0 + detail texture | 60.0 (first ~14 s only) | 60.0 | nominal | not captured |
| everything else (150/400 rocks, loose, no-room, storm, face-habitat) | NOT MEASURED | | | |

Captures taken (and viewed) for r0 plain: facing out, and turned 180 degrees via the capture override. I deleted those two files while restarting runs, so there are no evidence images in `docs/evidence/polish/spike-ground-*`; this is a gap.

## What the captures showed (r0 plain)
- Facing out: smooth, brownish, low-contrast ground to a believable horizon with the hangar/rocket/drill silhouettes; sky and haze right. The ground within about 10 m of the feet is a featureless smooth slope: no grit, no rocks. It is believable as distance terrain, not as ground you stand on. This is the case for the detail texture and rocks.
- Turned toward the habitat: rover, dish, solar field, hangar read well at 20-40 m; the sun disc is correct. The ground ends at a flat horizon line.

## Terrain data near the feet (from the OBJ, measured)
- Near mesh vertex spacing is about 0.55 m within 10 m of the origin and about 1 m around the 40 m judge position (~0.9 m2 per vertex, 3087 vertices within 30 m); about 1.5 m average spacing out to 100 m. This is the HiRISE 1 m DEM: terrain relief below ~1 m does not exist. Rocks resting on it will interpenetrate or float by up to a few cm over a 1 m cell; hide with burial (I sink each rock 2% of its size) or snap-to-triangle placement.
- Height range within 30 m of the judge: 0.1 to 3.65 m (gentle), so no steps, but also no micro-relief.
- The albedo texture (4096 px over ~5.2 km) is ~1.3 m per texel: blurry flat colour at the feet; detail texture or a decal layer is mandatory.
- **Coverage (reviewer finding, confirmed from the OBJ):** the near and far meshes cover only azimuth ~210-390 degrees (a wedge) with a hole at r < 4 m. Turning around from a ground-level viewpoint shows the wedge edge and no ground behind. The full build must either keep the judge looking into the wedge, or add CTX fill for the rest of the circle.
- Room: its walls are one-sided, so the habitat is invisible from outside (only the floor disc shows); a visible exterior needs an exterior shell.

## What went wrong / what could not be measured
- I waited ~20 minutes for the unlock with a loop that silently failed (missing DEVELOPER_DIR in the background shell), so that wait was wasted; the app launched at 07:10 once I used the right environment.
- Runs 1 and 2 were cut off when other sessions installed/launched their own AresVR build on the same phone (same bundle id) at 07:11 and 07:22. Run 3 ran only the baseline window. After 07:41 my build launches and prints its `[ground]` init lines (judge placed, 400 rocks built) but never reaches the server (`[link] trying 10.20.50.20`, no established connection on :8787), so no further stats or captures came back.
- Not measured at all: any rock count, loose vs batched, storm (tau 4.6) at ground level, room hidden, thermal over 5+ minutes, frame-time distribution beyond the 1-second fps samples, draw-call counts (SceneKit's SCNRenderer exposes none here; Xcode GPU frame capture needed). Re-run: `ARES_GROUND=1 scripts/build-ios.sh` with the phone unlocked and no other session using it; read `cfgResults` from `/api/vr/stats` after ~12 minutes.

## Budget (analysis only, not measured)
- Rocks batched: 400 x 80 tris = 32k triangles per eye and about 16 draws (fewer when sectors are culled); the terrain near mesh is 88k triangles per eye already, and the baseline at ~60 fps with that mesh plus the room is measured. Loose rocks would add ~400 draws per eye (SceneKit has no GPU instancing): the reviewer's concern is right, so ship batched. Detail texture adds one texture fetch per terrain pixel, minor.
- The storm particle emitter (up to ~8000 particles, alpha, large overdraw at ground level) is the unmeasured risk and the most likely thing to break 60 fps; hiding the indoor scene is the cheapest mitigation.

## Verdict
**UNVERIFIED (claim stays UNVERIFIED in CLAIMS.md).** Measured: ground-level stereo on the real terrain with the room loaded holds 60 fps at rest, cool, with 0 rocks. Not measured: the pass criterion (150+ rocks plus detail texture), the storm, thermal. Do not mark PASS. Fallback if it fails on re-run: batched rocks only, 150 or fewer within 15 m, detail on, indoor scene hidden, storm particles reduced while outside.
