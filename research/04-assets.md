# 04 - Assets research (Mars base control room, Unity 6 URP, Cardboard VR, iPhone 16 Pro)

Researched 2026-10-23 against live pages (source dates noted inline). Downloaded packs are in
`/Users/TAITA/Projects/ares/data/assets-raw/` (285 MB total). Each pack ships its own license file.

## TL;DR shortlist

| Need | Asset | URL | License (exact) | Format | Notes |
|---|---|---|---|---|---|
| Control room modular kit (walls, round corners, floors, doors, window frames, columns, props, vents) | Quaternius Modular Sci-Fi MegaKit **Standard** (190 of 270+ models; OGA post 2025-04-16) | https://opengameart.org/content/modular-sci-fi-megakit (zip: https://opengameart.org/sites/default/files/modular_scifi_megakitstandard.zip) ; also https://quaternius.itch.io/modular-sci-fi-megakit | CC0 1.0 Universal (License_Standard.txt in zip) | glTF, FBX, FBX (Unity), OBJ | PBR textures (27 MB, trim sheets + emissive); 393 files in glTF folder. Has `Walls` (168 files incl. round corners), `Platforms` (Platform_Window_Wide/Thin, doors), `Columns`, `Props` (Computer, Crates, Vents, Lights, Barrel, Chest). Best-looking room kit. Check texture res (downscale to 1k for mobile). |
| Consoles, screens, chairs, display walls, windows, containers | Kenney Space Station Kit (v1.0, 2024) | https://kenney.nl/assets/space-station-kit | CC0 (License.txt: Creative Commons Zero) | GLB, FBX, OBJ | `computer*`, `display-wall(-wide)`, `table*`, `chair*`, `wall-window*`, `door*`, `container*` (cargo crates), `rocks`. Extremely light (1.1 MB of GLB total). Flat colors via one texture. Good for mobile; stylistically cleaner/cartoony vs Quaternius. |
| Outdoor: rover, lander-ish craft, satellite dish, generators, rocks, craters, pipes, barrels, rocket parts | Kenney Space Kit (CC0, 150 files; page says v1.0 2020, zip License.txt says 2.0) | https://kenney.nl/assets/space-kit | CC0 (zip License.txt: http://creativecommons.org/publicdomain/zero/1.0/) | GLB, FBX, DAE, OBJ, STL | `rover.glb` (13 KB), `craft_miner`, `craft_cargoA/B`, `satelliteDish*`, `machine_generator*`, `machine_wireless`, `crater*`, `rock*`, `barrels`, `pipe_*`, `structure*`, `platform_*`. Ultra low-poly. |
| Landers | Kay Lousberg "Lander A/B" on Poly Pizza (posted 2024-03-19) | https://poly.pizza/m/YPZ2B9ao7L , https://poly.pizza/m/TVASj3JcDO | CC0 ("Public Domain (CC0)" on page; Lander B verified, Lander A assumed same author/pack - verify on page) | FBX, glTF | Not downloaded (Poly Pizza has no direct link). Optional. |
| Alt rovers | Quaternius "Rover", "Round Rover" on Poly Pizza | https://poly.pizza/m/tzOLXetacM , https://poly.pizza/m/ejdkcNgMpr | Per-model; Quaternius models are normally CC0 but search page did not show license - verify per page | glTF/FBX | Optional. Kenney rover is enough. |
| Solar panels, ice drill rig | **No suitable CC0 model found.** Build procedurally / compose from Kenney `structure`, `pipe_*`, `machine_*`, `satelliteDish` | - | - | - | Solar panel = thin cube (dark blue, grid texture/shader) on a pole; trivially procedural. Drill rig = tall lattice tower (Kenney `structure_*` stacked) + cylinder drill + `pipe_*` + `machine_generator`. Only found CC-BY/GPL (OGA "solar panel" by Jummit, CC-BY 4.0 + GPL 3.0, https://opengameart.org/content/solar-panel) and paid/CGTrader items - skip. |
| Real NASA hardware (Perseverance/Ingenuity), optional | NASA 3D Resources | https://github.com/nasa/NASA-3D-Resources , https://nasa3d.arc.nasa.gov/models | "free and without copyright" (README); governed by NASA Media Usage Guidelines (page updated 2026-08-13) | OBJ/STL/GLB varies; Perseverance/Ingenuity GLB reported on NASA Mars page | Not downloaded: I could not confirm an official glTF link (science.nasa.gov resource URL 404'd). Heavy meshes; would need decimation. Credit NASA, no endorsement. Skip unless time. |
| Mars ground PBR | Poly Haven textures: `red_sand`, `terrain_red_01` (Rob Tuytel, 2018), `cracked_red_ground`, `rocky_terrain_02` | https://polyhaven.com/a/terrain_red_01 etc. | CC0 | JPG 1k diff/nor_gl/rough | Downloaded 1k. Tint toward Mars orange in shader. |
| Sky/HDRI | Poly Haven `wasteland_clouds_puresky` (Jarod Guest, Sergej Majboroda, 2023), `sandsloot` | https://polyhaven.com/a/wasteland_clouds_puresky | CC0 | HDR 1k | No Mars HDRI exists on Poly Haven (997 HDRIs searched by name). Use a clear/dusty sky, grade orange/butterscotch, or a custom gradient skybox with fog (cheaper). |
| Metal PBR (consoles/hull) | ambientCG (Metal, PaintedMetal, etc.) | https://ambientcg.com , license https://docs.ambientcg.com/license/ | CC0 1.0 Universal | JPG/PNG zips | Not downloaded (API search returned nothing useful for sci-fi queries; browse by category). Quaternius trim sheets already cover interior; ambientCG optional. |
| UI blips/beeps | Kenney Interface Sounds (100 files, 2020), Kenney Sci-fi Sounds (70 files, 2020) | https://kenney.nl/assets/interface-sounds , https://kenney.nl/assets/sci-fi-sounds | CC0 | OGG/WAV | Downloaded. |
| Mars wind | NASA Perseverance SuperCam wind (sol 4, 2021-02-22) | https://www.nasa.gov/wp-content/uploads/2024/05/scam-mic-sol004-run001.wav (list: https://www.nasa.gov/sounds-from-beyond/) | NASA Media Usage Guidelines (not copyrighted unless noted; credit NASA/JPL-Caltech/LANL/CNES/CNRS/ISAE-Supaero; no endorsement) | WAV | Not downloaded. Very quiet/sparse; better to layer with a synthesized wind loop. |
| Fonts | Inter 4.1, IBM Plex Sans/Mono, JetBrains Mono 2.304, Rajdhani | see Fonts section | SIL OFL 1.1 | TTF | Downloaded with license texts. |

## 1. 3D assets - detail

### Quaternius Modular Sci-Fi MegaKit (primary interior kit)
- OGA page dated 2025-04-16, CC0. Itch page: free tier "Standard" is 46 MB (itch checkout, name-your-price), Pro $9.99 (187 MB), Source $14.99 (899 MB, includes Unity URP project with shaders). The OGA zip (48.6 MB) is the same Standard content and downloads directly - used that.
- Style: clean semi-realistic low-poly, trim-sheet PBR (BaseColor/Normal/ORM/Emissive, color variants). Round corner walls (`*_Corner_Round_*`) and `Platform_Round1`/`Platform_Window_Wide` suit a circular room. Mobile OK: trim sheets share a few materials; keep URP Lit, 1k textures, bake lighting or use 1 light + light probes. The Standard pack lacks consoles/screens apart from `Prop_Computer`, `Prop_AccessPoint` - use Kenney for those.
- Companion: Sci-Fi Essentials Kit (OGA, 2025-04-16, CC0; 37 models incl. animated screens, crates; models zip 87.8 MB + textures 79.1 MB): https://opengameart.org/content/sci-fi-essentials-kit . **Not downloaded** (over scope; contains enemy robots/guns we don't need). Grab crates/screens if wanted.
- Also seen: Quaternius Ultimate Space Kit (CC0, March 2023, 92 animated models, FBX/OBJ/Blend/glTF) https://quaternius.com/packs/ultimatespacekit.html - characters/planets, not useful here.

### Kenney kits
- Both CC0, direct zips (the Kenney page download link works without donating; downloads were truncated by throttling on first try, resume worked).
- Space Station Kit has windows (`wall-window`, `wall-window-frame`, `wall-window-shutters`), `display-wall`, consoles, containers, `skip`. No solar panels. Space Kit has rover/miner craft/dish/generators/rocks/craters but no solar panel or drill.

### Poly Haven / ambientCG
- Poly Haven license page: all assets "CC0 ... effectively Public Domain"; no credit required; site logos/renders/text are not CC0. Credit is optional but listed below.
- ambientCG license page (https://docs.ambientcg.com/license/): CC0 1.0 Universal; credit not required; suggested wording "Created using <asset name> from ambientCG.com, licensed under the Creative Commons CC0 1.0 Universal License."

### NASA
- Guidelines page (https://www.nasa.gov/nasa-brand-center/images-and-media/ , last updated 2026-08-13; older URL https://www.nasa.gov/multimedia/guidelines/index.html): images, audio, video and 3D model files generally not copyrighted in the US; credit NASA as source; do not imply endorsement; NASA insignia/logotype/"meatball"/worm are NOT public domain - do not show them (including on real-rover decals if copied). Third-party items are marked. Special AI clause: do not attribute outputs to NASA ("according to NASA" prohibited), do not combine NASA logos with AI-generated imagery; stating that source material came from NASA is fine. Safe credit: "Mars wind recording: NASA/JPL-Caltech/LANL/CNES/CNRS/ISAE-Supaero. Not endorsed by NASA."
- Poly Pizza models are per-model CC0 or CC-BY; the search listing did not display the license - always open the model page.

### Unity Asset Store "Standard EULA" (https://unity.com/legal/as-terms, updated 2024-12-04)
Allowed in a shipped build: asset must be embedded in a "Licensed Product" with substantial original content, can be distributed/publicly displayed as embedded, no attribution requirement. NOT allowed: redistributing raw asset files (a public GitHub repo containing the asset = violation), AI training. So free Store items are usable in a public demo **build**, but must not be committed to a public repo. Given hackathon repos are often public, **recommendation: avoid Store assets entirely**; CC0 above covers the need.

## 2. Robot bodies (5 robots) - recommendation

Use **procedural primitive-composed bodies** (spheres, capsules, rounded boxes, tori, cones in a prefab, ~3-6 mesh parts each), not a CC0 model:
- Originality guaranteed, zero license risk; distinct silhouettes per role; shared 1-2 materials (URP Lit/Simple Lit + emissive rim) so SRP-batcher friendly; trivially animated (bob, tilt toward user).
- Common language: a floating head-body, no legs, soft bevels, a **flat rounded-rect face screen** inset into a darker bezel, a thin emissive ring/rim in the role color, a small downward glow (hover light, fake with an unlit additive quad). Avoid white egg bodies, pill-shaped single eyes and spherical droids (EVE/WALL-E/BB-8/Baymax territory).

| Role | Body shape | Color | Face/rim detail |
|---|---|---|---|
| Engineer | Hexagonal-prism/chunky rounded box, wider than tall, two small arm pods (capsules) and a top antenna | Amber/orange (#FFA31A) | Squarish screen, blink slow; rim is hazard-stripe segments |
| Cargo Keeper | Barrel-ish cylinder on its side or stacked double capsule, side lugs like crate handles | Teal (#1FB5A8) | Wide short screen, calm half-lidded eyes; lower cargo-clamp torus |
| Bill Checker | Tall thin lozenge (flattened capsule) with a magnifier-lens ring (torus) offset on one side | Blue/cyan (#3D8BFF) | Narrow screen, eyes with "scanning" horizontal pupil sweep |
| Money Keeper | Squat sphere-cut-in-half "coin" (disc, thick cylinder), coin-edge ridges via torus | Gold/green (#E8C14A / #3CC47C) | Round face, bright wide eyes, happy squint on good news |
| Rule Keeper | Upright shield/arch shape (rounded box with chamfered top), a halo ring floating above | Violet/red (#8E5CFF / #E04F5F) | Stern slanted brows via eye squint/angle, steady gaze |

Distinct hues, different silhouette outlines, different ring/accessory placement = readable at Cardboard resolution and distance. Budget: < 2k tris each.
If you ever want a model instead: Quaternius robots in the Sci-Fi Essentials Kit are CC0 but are enemy-style, not recommended.

## 3. Expressive screen faces - recommendation

| Option | Effort | Runtime cost | Verdict |
|---|---|---|---|
| (a) Sprite/texture swap per expression | Need N expressions x art; transitions pop unless cross-faded | Cheapest (1 texture sample) | Fine fallback, poor look-at and blends |
| (b) Procedural SDF eye shader | 2-4 h in HLSL, 1 material per robot (or MaterialPropertyBlock); infinite expression blends, smooth blink/lookat | ~2 rounded-box/ellipse SDFs per pixel on a small quad; negligible on A18 Pro | **Recommended** |
| (c) TextMeshPro glyph eyes | Fast to start | TMP mesh/atlas, awkward blending, little control of squint | Not recommended for eyes (keep TMP for text on screens) |

Recommended: unlit URP shader (HLSL, hand-written; faster to author than Shader Graph for SDF and easier to keep in git), applied to a quad on each face with `[PerRendererData]` params driven from C# (MaterialPropertyBlock keeps SRP batching minimal impact; with 5 robots just use per-robot material instances).

Shader parameters (suggested):
- `_Color` (eye color, HDR for bloom), `_BgColor`, `_Glow` (outer glow falloff)
- `_Openness` 0..1 (vertical eye scale; 0 = closed line)
- `_Blink` 0..1 (multiplies openness; C# drives a random 3-6 s blink coroutine, 120 ms close/open)
- `_Squint` -1..1 (upper-lid cut: +1 happy arch / lower lid raise, -1 sad/angry slant) plus `_Tilt` (lid angle for angry/sad brows)
- `_EyeSize` (xy), `_EyeSpacing`, `_Roundness` (corner radius of rounded box SDF)
- `_PupilOffset` (xy, -1..1; look-at user: compute in C# by transforming head-camera position into robot local space, smooth with SmoothDamp, clamp) - shift eye shapes themselves a few % and optionally a darker pupil disk
- `_Scanline` / `_Pixelate` (optional LCD look: step uv to a 48x32 grid, subtle scanlines)
- Expression presets = ScriptableObject of these floats; lerp between presets in C# (0.15 s). Keep a handful: Neutral, Happy, Curious, Alarm, Sleepy, Thinking.

Sketch (fragment, local face uv in [-1,1]):
```
float sdRoundBox(float2 p, float2 b, float r){ float2 q=abs(p)-b+r; return length(max(q,0))+min(max(q.x,q.y),0)-r; }
float eye(float2 uv, float side){
  float2 p = uv - float2(side*_EyeSpacing, 0) - _PupilOffset*0.12;
  p.y /= max(_Openness*(1-_Blink), 0.02);
  // lid cut: slanted half-plane
  float lid = p.y*1.0 + side*p.x*_Tilt - _Squint*0.5;
  float d = max(sdRoundBox(p, _EyeSize, _Roundness), -lid);
  return smoothstep(0.02, -0.02, d);   // + exp glow term
}
// col = lerp(_BgColor, _Color, saturate(eye(uv,-1)+eye(uv,1)))
```
CC0 face/eye sprite packs: Kenney Emotes Pack (CC0, 480 files, 2018, https://kenney.nl/assets/emotes-pack) is balloon-style emoji, only useful as reference or for fallback; no worthwhile CC0 robot-eye pack was found. Not needed with the shader.

## 4. Fonts (all confirmed SIL OFL 1.1; license texts downloaded)

| Font | Use | Source / version | License note |
|---|---|---|---|
| Inter | Body text, numbers on wall screens | https://github.com/rsms/inter v4.1 (2024-11-16); TTF variable in zip | OFL 1.1, (c) 2016 The Inter Project Authors; Reserved Font Name "Inter" |
| IBM Plex Sans | Alternative body | Google Fonts repo (ofl/ibmplexsans); upstream https://github.com/IBM/plex (Sans 3.5 per Wikipedia; recent releases up to 2026-07) | OFL 1.1, (c) 2017 IBM Corp., Reserved Name "Plex" (IBM rescinded brief Apache dual license in 2018) |
| IBM Plex Mono | Data/terminal readouts | Google Fonts repo; https://github.com/IBM/plex | OFL 1.1 as above |
| JetBrains Mono | Alt mono, very legible at small size | https://github.com/JetBrains/JetBrainsMono v2.304 (2023-01-14) | OFL 1.1, (c) 2020 The JetBrains Mono Project Authors (source code Apache 2.0, irrelevant) |
| Rajdhani | Sci-fi headers (Light-Bold) | https://github.com/google/fonts/tree/main/ofl/rajdhani (added 2014-07-09) | OFL 1.1, (c) 2014 Indian Type Foundry |

Notes: use TMP SDF font assets (Window > TextMeshPro > Font Asset Creator) with SDF 512x512+ atlas, Static/Dynamic as preferred; in VR text needs large size, medium/semibold weights (Inter Medium/SemiBold, Rajdhani SemiBold, Plex Mono Medium) to survive Cardboard lens blur. OFL permits embedding in apps, forbids selling the font alone and using Reserved Font Names for modified versions (don't rename-and-redistribute modified Inter). Include OFL texts in credits/licenses folder.

## 5. Audio

- Kenney Interface Sounds (100 files, v1.0 2020) and Sci-fi Sounds (70 files, v1.0 2020): CC0. Downloaded to `data/assets-raw/audio/`.
- Ambient wind/hum: freesound.org items are per-file (CC0 / CC-BY / CC-BY-NC); filter license=CC0 and double-check each file; not searched in depth. Easiest: synthesize wind (filtered noise with LFO) and a room-tone hum in Unity, zero license risk.
- NASA Perseverance microphone recordings: the Sounds from Beyond page (https://www.nasa.gov/sounds-from-beyond/) defers to the Media Usage Guidelines - NASA-created audio generally not copyrighted; credit lines vary per file (SuperCam clips credit includes LANL/CNES/CNRS/ISAE-Supaero; chassis-mic ones "NASA/JPL-Caltech"). Usable with credit and a no-endorsement line; WAVs (e.g. wind sol 4, dust devil `pia25657.wav`, driving highlights) at nasa.gov/wp-content/uploads/2024/05/. Real Mars wind is faint and the "inside the base" perspective would hear none; use only as a subtle layer when the window is "open" or on a loading/intro. Note the AI clause (no "according to NASA" phrasing).

## License notes / risks
1. CC0 items need no credit but credit anyway (cheap goodwill).
2. Do not commit Unity Asset Store assets to a public repo (Standard EULA). CC0 packs are fine to commit.
3. Quaternius Standard zip license text says it is the free version; keep `License_Standard.txt` with it.
4. Poly Pizza: per-model licenses; I verified only Lander B (CC0, Kay Lousberg). Re-check before use.
5. NASA: no logos/insignia; no endorsement; credit; AI-attribution clause.
6. Kenney Space Kit page says v1.0 (2020) while the downloaded License.txt says 2.0 (created 2020-08-27); content/license identical (CC0).
7. Kenney page counts: Space Kit 150 files, Space Station Kit 90 files (file counts, not models).
8. Not verified: exact triangle counts (did not open meshes); mobile budget advice is heuristic. glTF import in Unity 6 needs the glTFast package (`com.unity.cloud.gltfast`); FBX/OBJ import natively - prefer the "FBX (Unity)" folder in the Quaternius zip, FBX/OBJ for Kenney.

## Downloaded (in /Users/TAITA/Projects/ares/data/assets-raw/, ~285 MB)
- `kenney_space-kit/` (zip + `x/` extracted), `kenney_space-station-kit/`
- `quaternius_modular-scifi-megakit-standard/` (zip + `x/`)
- `polyhaven/`: red_sand, terrain_red_01, cracked_red_ground, rocky_terrain_02 (1k diff/nor_gl/rough JPG); HDRI wasteland_clouds_puresky_1k.hdr, sandsloot_1k.hdr
- `fonts/`: Inter-4.1.zip (+inter/), JetBrainsMono-2.304.zip (+jbm/), Rajdhani x4 TTF + OFL, IBMPlexMono Regular/Medium + OFL, IBMPlexSans variable TTF + OFL
- `audio/`: kenney_interface-sounds, kenney_sci-fi-sounds
- Not downloaded: ambientCG, NASA models/audio, Quaternius Sci-Fi Essentials, Poly Pizza models.

## Credits block (paste into app)

```
Credits and licenses
3D models: Space Kit, Space Station Kit by Kenney (kenney.nl), CC0 1.0.
Modular Sci-Fi MegaKit by Quaternius (quaternius.com), CC0 1.0.
Textures and HDRIs: Poly Haven (polyhaven.com), CC0 - incl. terrain_red_01 by Rob Tuytel;
  wasteland_clouds_puresky by Jarod Guest and Sergej Majboroda.
Sound effects: Interface Sounds and Sci-Fi Sounds by Kenney, CC0 1.0.
[If used] Mars wind recording: NASA/JPL-Caltech/LANL/CNES/CNRS/ISAE-Supaero. Not endorsed by NASA.
Fonts (SIL Open Font License 1.1): Inter (c) The Inter Project Authors; IBM Plex (c) 2017 IBM Corp.;
  JetBrains Mono (c) 2020 The JetBrains Mono Project Authors; Rajdhani (c) 2014 Indian Type Foundry.
Robot designs, characters and scene are original.
```

## Sources (fetched 2026-10-23)
Kenney: https://kenney.nl/assets/space-kit , /space-station-kit , /sci-fi-sounds , /interface-sounds , /emotes-pack ;
Quaternius: https://quaternius.com/packs/ultimatespacekit.html , https://quaternius.itch.io/modular-sci-fi-megakit , https://opengameart.org/content/modular-sci-fi-megakit , https://opengameart.org/content/sci-fi-essentials-kit ;
Poly Haven license https://polyhaven.com/license ; ambientCG https://docs.ambientcg.com/license/ ;
NASA https://www.nasa.gov/nasa-brand-center/images-and-media/ , https://www.nasa.gov/multimedia/guidelines/index.html , https://www.nasa.gov/sounds-from-beyond/ , https://github.com/nasa/NASA-3D-Resources ;
Unity EULA https://unity.com/legal/as-terms ; Poly Pizza https://poly.pizza/m/YPZ2B9ao7L ;
Fonts: https://github.com/rsms/inter , https://github.com/IBM/plex , https://github.com/JetBrains/JetBrainsMono , https://github.com/google/fonts/tree/main/ofl/rajdhani .
