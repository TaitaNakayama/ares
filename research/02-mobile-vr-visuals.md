# 02 - Mobile VR visuals: Unity 6 + URP + Cardboard XR on iPhone 16 Pro

Researched 2026-10-23. Confidence tags: [V] = verified in a source I fetched this session (date given); [J] = my engineering judgment/estimate, NOT sourced, validate on device; [U] = could not verify, test it.

## TL;DR settings table

| Setting | Value | Why | Source + date |
|---|---|---|---|
| Unity / plugin | Unity 6000.0.58f2+ (6000.0 LTS), Cardboard XR Plugin 1.36.0 (2026-10-14; adds iPhone 18 Pro/17e res data; 1.34+ needs iOS 15+) | Plugin README demands 6000.0.58f2 or later. Quickstart says 6000.0.23f1+. Use the newer. | github.com/googlevr/cardboard-xr-plugin README + releases, fetched 2026-10-23 [V] |
| Graphics API | Metal (only option on iOS) | n/a | [V] |
| Stereo rendering mode | Leave at whatever Cardboard loader offers; assume MULTI-PASS. Do not rely on Single Pass Instanced | I found no doc or release note saying the Cardboard loader supports SPI. Unity says SPI falls back to multi-pass when unsupported, and its supported-platform list does not name Cardboard. | Unity 6000.0 stereo-rendering manual, 2026-10 [V for Unity side; U for Cardboard] |
| Render path | Forward (not Forward+, not Deferred) | Deferred = GMEM loads on tile GPUs | Unity 6.3 "Optimize for untethered XR devices in URP", 2026-10-23 [V] |
| MSAA | 4x (drop to 2x if GPU-bound). Unity recommends 2x as balance. | Tile GPUs resolve MSAA on-chip, cheap. Wall-screen text edges and window frames shimmer without it. | same Unity page [V]; 4x choice [J] |
| HDR | OFF | Less bandwidth. Unity recommends off for XR. | same Unity page [V] |
| Render scale (URP asset) | 1.0 start; try 0.8-0.85 if GPU > 12 ms. Set once at startup; do not change per frame. | Changing it reallocates the eye texture. Cardboard also draws a distortion mesh, so eye buffer is already ~ screen size. | Unity resolution-scaling page, 6.3 docs, 2026-10-23 [V]; numbers [J] |
| Depth priming | Disabled | XR doubles depth pre-pass cost | Unity page [V] |
| Opaque Texture / Depth Texture | OFF | Extra copies = GMEM loads. NOTE: Cardboard issue #518 (Dec 2025, plugin 1.31 + Unity 6000.2, Android) had black screen on a world-space Canvas gaze with Depth Texture off + MSAA on. Not iOS, but test early. | Unity page [V]; github.com/googlevr/cardboard/issues/518 [V, Android] |
| SSAO | OFF | Multiple full-screen passes | Unity page [V] |
| Post-processing | OFF on 6000.0. No bloom. (If you move to 6.3+, on-tile post-processing exists, but I would not risk it with Cardboard.) | Multi-pass PP breaks tile flow; the final blit alone costs a GMEM load | Unity page [V] |
| Glow | Emissive materials + additive halo quads/sprites (billboard, no depth write) | Cheap, no extra render target | [J]. Not found as a sourced recipe |
| Shadows | Main light: realtime shadows OFF. Bake. If you need one, 1 cascade, 1024 map, ~15 m distance, soft shadows off | Each shadow cascade re-renders geometry; stereo + MSAA make it worse | [J] |
| Lighting | Baked lightmaps for room (static), Light Probe Group for the 5 robots, 1 realtime directional max, additional lights: 0-2 per-pixel | Static room geometry is ideal for baking | [J] |
| SRP Batcher | ON (default) and keep one or few shaders (URP Lit/Unlit/SimpleLit) | Makes SetPass cheaper, not fewer draws. Can be a wash on some mobile. Xcode capture may show far more draws than Unity | Unity discussions thread "SRP Batching not occurring on iOS Metal frame capture" [V, undated forum] |
| GPU instancing | ON for robots/props that share mesh+material; static batching for room | Cuts draw calls | unity.com mobile optimization tips [V] |
| Texture compression | ASTC. 6x6 for albedo, 8x8 for lightmaps/skybox/smooth gradients, 4x4 for normal maps and font/icon atlases and the reticle. Max texture 2048 (1024 for props) | ASTC is native on A-series | [J]; ASTC is standard on A8+ |
| Frame rate | Target 60 fps. Let the Cardboard SDK own it. Don't fight it. | Unity: "XR platforms ignore Application.targetFrameRate and vSyncCount; the XR SDK controls the frame rate". Cardboard docs give no frame rate. | Unity 6000.0 Application.targetFrameRate doc, fetched 2026-10-23 [V]; Cardboard quickstart updated 2025-10-09 [V] |
| ProMotion / 120 Hz | Don't go for it. Do not add CADisableMinimumFrameDurationOnPhone. Keep it 60 Hz | Half the heat, half the budget; without the plist key iPhone caps at 60 Hz | search summary of Unity docs/forums [V-ish] |
| Fog | URP Lighting window fog (Exponential Squared), color matched to the dust sky, plus a few transparent cards | Per-pixel math is trivial | [J] |
| Text | TMP SDF, Bold sans-serif, cap height >= 1.5 deg, 1.8 deg for key text | See section 3 | Frontiers VR review, Meta typography [V] |
| Thermal | Cap at 60, render scale <= 1, brightness ~50-60%, poll thermal state, drop render scale at Fair, rotate phones | See section 6 | Apple thermal docs, Unity AP Apple provider [V] |

## 1. URP / stereo specifics

- **Plugin status** (releases page, fetched 2026-10-23): v1.36.0 2026-10-14, v1.35.0 2026-08-31, v1.34.0 2026-05-28 (iOS min 15, new camera permission dialog), v1.31.0 2025-11-04 (Unity 6.2, 2025 iPhones), v1.30.0 2025-08-26 (Unity 6 support; quickstart config for an iOS button-touch problem, issue #475). iPhone 16 Pro data pre-dates these, so viewer params for your phone should exist. If the screen is wrong, the QR/profile scan is what sets distortion; the plugin keeps a table of phone screen sizes (v1.32 corrected one iPhone entry, #507), so check the Cardboard viewer QR scan result on your phone first.
- **URP + Cardboard on iOS:** No official statement either way. The Google quickstart (updated 2025-10-09) never mentions URP. Known URP black-screen issues: Linear color space + URP + GLES3 (#199, #339, Android, 2020-21); #518 (Dec 2025, Android, URP, canvas gaze). No iOS+URP+Unity 6 black-screen issue turned up in my search, but search coverage of GitHub is weak. Plan: build a minimal URP scene to the phone in the first 2 hours, before building the real scene. Fallback: Built-in pipeline (the Cardboard path most users have used).
- **Linear vs Gamma:** Linear is the right choice on Metal. Old URP black screens were GLES3 only. If you see black, switch to Gamma as the quick test [J].
- **Single pass instanced:** UNVERIFIED for Cardboard. Legacy Unity docs (2019.2) listed "Stereo Instanced Rendering" for the old built-in Google VR iOS Metal path, but the new XR Plug-in loader is different. Unity's current docs say SPI falls back to multi-pass if unsupported. Practical implication: budget as if multi-pass (everything drawn twice: 2x draw calls and 2x vertex work). Check Project Settings > XR Plug-in Management > Cardboard for a Render Mode dropdown; if present, try Single Pass Instanced and verify in Xcode GPU capture. Custom shaders must then include the XR macros (UNITY_VERTEX_INPUT_INSTANCE_ID etc.); URP built-ins do.
- **Geometry shaders:** avoid. No grabpass/Opaque Texture.
- **MSAA + render scale:** At 60 Hz on A18 Pro, the budget is 16.6 ms. On A-series, MSAA 4x is usually fine for simple scenes [J]. Unity's own page says 2x as balance [V].
- **Skip render scale > 1.0.** The distortion mesh already supersamples the center a bit.
- **Anti-aliasing for thin lines** on the wall screens: author UI as large shapes; MSAA does the rest.

## 2. Fog, dust storm, particles

- **Global fog:** URP Lighting > Environment > Fog, Exponential Squared, density ~0.01-0.04 outdoors. Fog only affects the view through the window, because the interior is under 8 m. If interior should stay clear, set the interior materials to a fog-less unlit shader [J], or accept some haze as the "dust ingress" effect.
- **Sky darkening:** Animate the skybox/gradient tint and light intensity over 20-30 s, not abruptly. Brightness jumps of the whole frame are uncomfortable (see 5).
- **Layered transparent cards** for "volumetric" dust (cheap): 6-10 large quads outside the window at 20-120 m, texture 512 px soft noise (ASTC 8x8, alpha), additive or alpha-blended, slowly scrolling UVs (very slow: < 0.02 UV/s), unlit. Avoid sorting artifacts by keeping them in distinct depth bands and ZWrite off.
- **Height fog shader:** a single Shader Graph unlit transparent that reads world-space Y: alpha = saturate((fogTop - worldY) * k). Put it on a few large planes or the terrain skirt. [J]
- **Particles (budget):** [J] total < 300 live particles in view, soft particles OFF (needs depth texture), no per-particle lighting, particle texture 128-256 px, max 2-3 stacked layers at any pixel. Large dust sprites are the overdraw hazard: a full-screen sprite is 2 eyes x full screen fill. Prefer fewer, bigger, lower-alpha particles over many small. Disable particle collision/trails/sub-emitters.
- **Overdraw:** Count layers: window glass (1) + fog cards (2-3) + particle dust (1-2) + wall-screen glow quads (1). Target <= 4 transparent layers at any pixel. Check with the Scene view Overdraw mode and Xcode GPU frame capture.
- **Do NOT** put glass in front of the camera (helmet visor effect) with a refraction/grab shader.
- **Window:** make it unlit/emissive plane rather than a real reflective glass; if it must be glass, 1 alpha quad with a faint tint.

## 3. Text legibility at Cardboard resolution

Numbers I could source (all [V], fetched 2026-10-23):
- Meta typography: min 14 px font for legibility, 18 px+ comfortable; Bold/Medium over Light/Thin.
- Frontiers in VR review (2023, frvir.2023.1243387) citing Solum 2019: 21-23 dmm (1.2-1.3 deg) comfortable, 14-16 dmm (0.8-0.92 deg) minimum; Dingler et al. 2018: 1.8 deg for comfortable reading; Google I/O '17 reference: 1.375 deg.
- Dingler et al.: 41 dmm +/- 14 dmm; white on black, sans-serif (Arial) preferred.
- "10 Rules of Using Fonts in VR" (cur.at mirror): a phone Cardboard at 90 deg FOV with 1080 px gives ~12 px per degree; 16 px phone font ~ 0.55 deg => unreadable. Rule: >= 16 physical pixels tall letter.
- Text rotated >= 60 deg needs much bigger size (Buttner 2020).
- World-locked text re-rendered each frame has lower effective resolution than nominal (Frontiers review): oversample.

Estimate for this phone [J]: panel 2622x1206 => ~1311x1206 per eye; with Cardboard V2 lens FOV ~ 90-100 deg horizontal in the eye viewport, about 13-15 pixels/degree at the center, less at edges. So:
- Minimum cap height 1.3 deg ~ 18 px. Body text target >= 1.5 deg (~21 px). Headlines/decisions 2.2-3 deg.
- Formula: cap height (m) = distance (m) x tan(angle). At 2.5 m: 1.5 deg = 6.5 cm; 1.8 deg = 7.9 cm. At 3 m: 1.8 deg = 9.4 cm. A wall screen of 3 m x 1.7 m at 2.5 m distance (~62 deg wide) fits only ~ 20 chars/line at 1.8 deg per cap height... Rule of thumb: 1.5 deg cap height => ~ 40 chars per line is 62 deg wide? No: char width ~ 0.6 x height, so 40 chars = 36 deg x ... compute per design, but the key constraint is: **max ~6-8 short lines per wall screen**, no paragraphs.
- Put the 3 screens within +/-35 deg of the forward direction; text > 40 deg off-axis is hard to read through the Cardboard lens edge blur.
- Keep text planes facing the user (face the room center; room is round so curved panels are natural). Keep the viewing angle off the normal < 30 deg.
- Place important content at 2-3 m depth (Cardboard comfortable focus ~ 2 m optical distance; Quest guidance is also about 1-2 m+). [J]

TMP settings [V from Unity docs, 3.2 manual, fetched 2026-10-23, and J]:
- Render mode SDFAA for dynamic fonts, SDF for static baked atlases; Sampling point size 64 with padding 6 (1:10), atlas 1024x1024 or 2048x2048 max (mobile cap), Optimum packing; Gradient Scale = padding + 1 (set automatically).
- Pre-bake a static atlas of ASCII (and any special glyphs) so no runtime atlas generation hiccup occurs mid-demo. Avoid dynamic fonts for the main screens.
- Use the Mobile/Distance Field shader (cheaper, no bevel) rather than full TMP/Distance Field if you do not need the extras.
- Bold sans-serif (e.g. Roboto Medium/Bold, Inter SemiBold, Orbitron-like fonts are risky for legibility: avoid wide techno fonts for body). Avoid Light/Thin weights.
- Contrast: white or pale amber on near-black (#05080C) panel at >= 90% panel opacity; avoid pure white large blocks (glare) -> use ~#E6EEF5. Avoid colored text on a colored dust-tinted background; keep panels opaque so the dust storm doesn't wash them.
- Disable text animation that moves letters (shimmer); fade in is fine. Avoid scanline overlays/flicker textures on text.
- Canvas: World Space canvas, scale such that 1 unit = 1 m; e.g. canvas 1920x1080 reference at scale 0.0015 => 2.88 x 1.62 m. Canvas Dynamic Pixels per unit ~ 1-2; no Pixel Perfect. One Canvas per screen, static canvases separate from animated elements (rebuild cost). No Canvas "Screen Space - Overlay": it does not work in Cardboard stereo.
- Mipmaps: if using text on a texture, enable mip + aniso 2-4; TMP atlas is SDF, so with Mipmaps off bilinear is fine.

## 4. Gaze reticle and selection

- Cardboard SDK Unity sample (HelloCardboard) ships a `CardboardReticlePointer` on the camera, with a layer mask ("Interactive") and the Cardboard trigger event; the quickstart explains wiring. [V, quickstart updated 2025-10-09]. The older GvrReticlePointer docs are archived at 2019 [V]. The reticle is a child of the camera and grows when over an interactable.
- **Input on iPhone Cardboard V2:** the viewer's button is a capacitive/lever that taps the screen; the Cardboard plugin reports it as a tap/click via the Input System (quickstart requires the new Input System package for Android; for iOS use the same). iOS quickstart config for a button-touch issue exists (#475, v1.30) [V]. TEST EARLY: iOS "defer system gestures on edges" must be on [V] or the tap area triggers the system gestures.
- **Gaze + tap (recommended) vs dwell:** For first-time users, gaze to highlight, then click is the only reliable pattern, because the viewer's button is the physical affordance and nobody has to wait. Dwell is harder to explain and creates accidental activation, but dwell with a "ring fill" can be added as a fallback ONLY if the button is not detected [J]. Do not use both for the same target.
- **Reticle:** small dot (0.4-0.6 deg) at 2-3 m always rendered on top (use an unlit shader, ZTest Always, renderQueue 4000), fixed distance from camera or placed at the hit point; ring expands to ~1.2 deg over a target; color change (white -> amber/cyan) plus ring fill plus a small tick sound on hover. Never hide the reticle while the user is deciding.
- **Hover feedback:** 3 cues together: scale 1.0 -> 1.08, brighten/outline, 20 ms haptic-less audio tick. Press feedback: flash + short sound + haptic (Handheld.Vibrate is crude on iOS; skip).
- **Button sizes [J, derived from the legibility numbers above]:** target >= 6 deg x 3 deg (e.g. 0.3 m x 0.15 m at 3 m is 5.7 x 2.9 deg), 2-3 deg gap between targets, to survive head jitter ~1 deg. Text on buttons >= 2 deg cap height.
- **Three decision options, instantly legible:**
  1. Three large cards side by side at the same height, 2.5-3 m, centered on the forward direction, 12-15 deg apart edge to edge? No: spread over ~35-40 deg total so all three are visible without turning the head much.
  2. Each card: a big numeral/icon (1, 2, 3 or distinct icons), a 2-5 word title, one line of consequence. Same layout for all three.
  3. A prompt strip above: "Look at an option, then press the button" with a small animated icon of the reticle + button. Show for first 5 s or until first hover, then fade.
  4. Nothing else interactive in view during the decision. Dim the rest by ~30%.
  5. On hover, the card lifts toward the user; on click, confirm with a visible state change and ~1 s transition. Add a "look here" pulse on the middle card after 6-8 s of no interaction. No confirm dialog; make the choices reversible or low-stakes.
  6. Start each session by checking calibration: "Look at the dot and press the button" 1 step tutorial; this teaches the grammar and verifies the tap works on that phone.
- Make sure reticle ray length and UI colliders handle double-eye use: use one gaze ray from the head pose, not from each eye.

## 5. Comfort

All [J] unless noted; Meta guidance verified [V]: consistent frame rate is crucial; reduce optic flow with solid/less detailed textures and peripheral occlusion; flashing patterns pose a photosensitivity risk (Meta developer docs, fetched 2026-10-23).
- **Camera is only moved by the head.** No bob, no shake, no animated FOV, no forced rotation, no cutscene camera. Dust-storm "rumble" must be audio + object vibration (e.g. cups, screens jitter slightly), never the camera. If you want a rumble, shake world objects at < 0.5 cm amplitude.
- **Stable horizon:** the room floor and window sill provide a fixed frame. The terrain outside must be static. Storm particles drift at < 1 m/s apparent, in a consistent direction; no fast skybox rotation. A rotating skybox is the classic vection trigger. Use a static skybox, animate only the cloud/dust overlays slowly (< 1 deg/s).
- **Frame drops are the biggest comfort risk.** If the GPU frame time exceeds budget, the Cardboard SDK's reprojection is not like Quest's ASW; you get judder. Keep headroom: target 11-12 ms GPU of 16.6.
- **Brightness flicker:** no strobing screens, no lightning, no emergency red flashes faster than 1 Hz. Ramp lighting changes over >= 2 s. Screen content on walls: no rolling scanlines at high contrast.
- **Elevated risk:** Robots flying toward the face: keep >= 1 m from the head; slow, predictable paths; no rapid approach.
- **Session length:** 2-5 min per judge is short, but first-time users in Cardboard are the most vulnerable. Offer a "tap to re-center" and start in a bright, stable moment before the storm.
- **Orientation:** lock to Landscape Left/Right (quickstart) [V]. Recenter on start so that the screens are in front.
- **IPD/Lens:** judges' glasses won't fit in V2; viewer scan QR sets lens distortion. Pre-scan on all test phones.

## 6. Thermal and battery over 2 hours

- Evidence [V]: Tom's Guide 3DMark Wild Life Extreme Stress Test (20 min): iPhone 16 Pro Max stability 54.7% (run 1), 67.7% (run 2); iPhone 17 Pro Max 65.2/68.4%. (Pro Max, not Pro; the 16 Pro is probably similar or slightly worse because it's smaller.) iGeeksBlog claims 3DMark dropped from 4,898 to 3,870 after 90 minutes on a 16 Pro; low reliability. Takeaway: an A18 Pro running flat out for 20 min loses 30-45% of GPU speed. A light scene at 60 fps will not run flat out, which is the whole point.
- **Keep GPU under ~60% load:** cap 60 fps (SDK-owned), render scale <= 1.0, MSAA 2-4x, no post-processing. Measure GPU time; goal 8-11 ms.
- **Unity API:** Application.targetFrameRate is ignored in XR [V]; so cap via the SDK default. You cannot lower to 30 without visible judder; don't.
- **Thermal state:** Apple ProcessInfo.thermalState: Nominal / Fair / Serious / Critical [V]. Apple guidance: at Fair take proactive measures, Serious reduce work, Critical immediate action [V, archived Apple power-efficiency guide]. Unity: the AR Foundation sample `ThermalStateForIOS` polls the state via a native plugin [V]; Unity Adaptive Performance Apple provider (`com.unity.adaptiveperformance.apple`, docs v6.0 / Unity 6.5) wraps the same API and also exposes "performance mode"; docs don't say how states map to warning levels [V]. Unity says on iOS to disable "Adjust iOS FPS based on thermal state" when AP is on [V]. Simplest for a hackathon: write a 15-line iOS native plugin returning `NSProcessInfo.processInfo.thermalState` (Unity 2022+ may also expose `Application`-level info; I could not confirm a built-in C# API, so don't count on one). On Fair: set `UniversalRenderPipelineAsset.renderScale = 0.85`; on Serious: 0.7, disable particles, drop MSAA to 2x. Avoid changing it mid-session when a user is wearing it if possible (reallocation hitch): change it between sessions, or use XRSettings.renderViewportScale, which is hint-based and cheap [V, but runtime may ignore for Cardboard: U].
- **Operational:**
  - Two phones of the same model, swap every 20-30 min; let each cool 10+ min with case off, out of the sun and off the charger.
  - Take the phone out of any case; Cardboard viewers trap heat against the screen. Tape a heat-sink-ish gap? No; simply use viewers with open sides/ventilation.
  - Do not charge while running (charging adds heat; wireless charging much worse). Start each session >= 80% battery and swap before 30%. Brightness: manual 50-60% (OLED, dark scene, saves heat and battery); disable Auto-Brightness and True Tone; turn on Low Power Mode? NO: LPM caps to 60/30 fps and may change CPU clocks; test with it off, use Airplane + Wi-Fi off + Do Not Disturb + Guided Access (also blocks accidental home swipe and notifications).
  - Disable Auto-Lock (Unity: Screen.sleepTimeout = SleepTimeout.NeverSleep).
  - Room temperature matters more than anything.
- **Measuring:** Xcode Instruments (Metal System Trace, GPU Counters, Energy Log, Thermal State track in the "Activity Monitor/Thermal State" instrument) on a wired device; Xcode GPU Frame Capture to see actual draw calls, overdraw and bandwidth. Unity Profiler over network: Development Build + Autoconnect Profiler, same Wi-Fi (or USB via iproxy); Frame Timing Stats must be enabled in Player Settings > Other > Rendering for release builds [V Unity AP Apple docs]. Profiling itself heats the phone and Wi-Fi profiling is laggy; record 3 min, stop. Run one 30 min soak with the thermal-state logger writing to a file (Application.persistentDataPath) and a frame-time log; plot after.

## 7. Per-frame budget (iPhone 16 Pro, stereo, 60 fps) [J, no vendor numbers]

Apple publishes no triangle budget. These are conservative engineering numbers assuming multi-pass stereo (everything counts twice):

| Item | Target | Hard ceiling | Notes |
|---|---|---|---|
| Frame time (CPU & GPU each) | < 11 ms | 16.6 ms | Headroom for thermals |
| Visible triangles (per eye) | 150-250k | 400k | x2 stereo. Bigger risk is vertex-heavy skinned meshes |
| Draw calls (per eye, i.e. scene) | < 150 | 250 | Unity says a rule of thumb < 200 for mobile 60 fps (studio blog, via search; not official) [V as rule of thumb] |
| SetPass calls | < 40 | 80 | Few materials/shaders; SRP Batcher helps |
| Materials | < 25 | 40 | Atlas the room |
| Texture memory | < 300 MB | 600 MB | iPhone 16 Pro has 8 GB, but jetsam kills at ~ 3 GB for a foreground app; stay low. ASTC 6x6/8x8 |
| Render textures | 1 (eye) + 0 | - | no reflection probes realtime, no mirrors |
| Transparent layers at any pixel | <= 4 | 6 | window glass, fog card, dust particles, glow |
| Particles alive | < 300 | 600 | Large particles cost fill, not count |
| Realtime lights | 1 dir + 0-2 | 4 | Per-pixel additional lights are costly in forward |
| Skinned meshes | 5 robots, < 5k tris each | - | Robots probably do not need skeletal animation; use simple transforms |
| Screen faces on robots | RenderTexture 256x256 shared or atlased animated flipbook | - | Avoid 5 live cameras/RTs |
| Wall screens | Static canvases, update text only on events | - | Canvas rebuild is CPU spike |
| GC | Zero allocs per frame | - | GC spike = judder |

Terrain: a baked mesh of Jezero at < 30k tris with LOD/impostor ring, mostly beyond fog distance; use a single albedo (2048, ASTC 8x8) + fog to hide far plane. Far clip plane 150-300 m. Near clip 0.1.

## What would make this fail on an iPhone at a hackathon at 3am?

1. **Black screen / nothing renders** with URP + Cardboard on a given Unity 6 point release (see #518, #199/#339). Mitigation: test a hello scene on the phone in the first hour; keep a Built-in RP fallback branch; check Gamma vs Linear; pin the plugin version and Unity version and never upgrade late.
2. **Single Pass Instanced assumed, then absent**; scene is 2x more expensive than planned. Always budget for multi-pass.
3. **Wrong distortion / double images**: viewer QR not scanned, or phone profile missing (the plugin hardcodes screen sizes per iPhone model). Verify the 16 Pro on a real viewer; the Cardboard Settings/QR scan screen must work (iOS camera permission string, v1.34 permission dialog).
4. **The viewer button does not register on iOS** (issue #417 settings buttons; #475 button touch config). Have a fallback input: tap on the screen edge will not work inside a viewer, so test the physical lever on each viewer; keep dwell as emergency fallback behind a build flag.
5. **System gestures / edge swipes** interrupt the app: "Defer system gestures" not set; Control Center pops up. Use Guided Access.
6. **Thermal throttling by judge #6**: the phone is hot, fps drops to ~45, judges feel sick. Two-phone rotation, 60 fps cap, light scene, thermal logger and render-scale fallback.
7. **Overdraw from dust particles + fog cards + glow quads** doubles the GPU load in stereo. Count layers; cut particle size.
8. **Text unreadable** because text was sized in pixels not degrees; or thin font; or screens too far off-axis. Test with a judge-like person who has never seen the scene, at arm's length from the viewer, at 3 am, not with your adapted eyes.
9. **Runtime shader compile hitch** the first time the dust storm starts (Metal shader variants). Prewarm with a ShaderVariantCollection or run the storm VFX once offscreen during loading; first-use hitches get noticed.
10. **Dynamic TMP atlas generation hitch** mid-demo. Use static atlases.
11. **Build / signing**: provisioning profile expires or free developer account limit (7 days, 3 apps); camera usage string missing (App Review/launch crash), iOS min version 15 for plugin 1.34+. Build and install a *release-like* build at hour 20, not hour 37.
12. **Memory kill (jetsam)** from big uncompressed textures or lightmaps (forgot ASTC; Unity default may be uncompressed for lightmap/RGBA). Check Xcode memory gauge < 1 GB.
13. **Brightness/Auto-lock**: auto-lock turns the screen off in the viewer, or auto-brightness ramps mid-demo. Disable.
14. **Late changes** (lighting bake, shaders) unvalidated on device. Freeze content at T-6h; only fix bugs.
15. **Wi-Fi profiling/Xcode tethering** left on, draining the battery or causing hitches. Ship a non-development build for the final demo.

## Sources (fetched/search-verified 2026-10-23 unless noted)
- Unity 6.3 docs: Optimize for untethered XR devices in URP: docs.unity.com/en-us/engine/6000.3/manual/xr/graphics/untethered-device-optimization.md
- Unity 6.3 docs: Resolution control in XR projects: docs.unity.com/en-us/engine/6000.3/manual/xr/graphics/resolution-scaling.md
- Unity 6000.0 docs: Application.targetFrameRate: docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/application/targetframerate
- Unity 6000.0 docs: Introduction to stereo rendering: docs.unity.com/en-us/engine/6000.0/manual/xr/graphics/stereo-rendering/single-pass-stereo-rendering.md
- Google Cardboard Unity quickstart (updated 2025-10-09): developers.google.com/cardboard/develop/unity/quickstart
- googlevr/cardboard-xr-plugin README + releases (v1.36.0 2026-10-14): github.com/googlevr/cardboard-xr-plugin
- googlevr/cardboard issues #518, #199, #339, #300, #417, #696: github.com/googlevr/cardboard/issues
- Unity Adaptive Performance Apple provider: docs.unity3d.com/Packages/com.unity.adaptiveperformance.apple@6.0/manual/index.html; AP 5.1 user guide (2025)
- Apple ProcessInfo.ThermalState docs and archived power efficiency guide; Unity ARFoundation ThermalStateForIOS sample; oceanviewgames.co.uk thermal blog
- Meta typography (developers.meta.com/vr/design/styles_typography/); Frontiers in Virtual Reality 2023 (10.3389/frvir.2023.1243387); Dingler et al. 2018; Buttner et al. 2020 (arXiv 2004.01545); "10 Rules of Using Fonts in VR"
- Unity TMP manual 3.2 Font Assets Creator
- Meta Horizon docs: locomotion comfort usability, os-missed-frames, best practices
- Tom's Guide iPhone 17 Pro Max endurance test (includes 16 Pro Max numbers); iGeeksBlog (low reliability)
- Arm blog: post-processing effects on mobile; Unity forum on SRP Batcher on iOS Metal
