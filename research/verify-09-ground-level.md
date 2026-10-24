# Verify 09: C-17, ground-level terrain at 60 fps

2026-10-24. Opus adversarial reviewer, not shown the team's reasoning. Read the code, data and C-14 log; no device run.

## Verdict: HOLDS WITH CAVEATS

Render cost is plausible; heat, draw calls and coverage are unproven. Triangles and fill rate aren't the problem.

## 1. Risks

1. **The terrain only covers the window view.** It spans azimuth 223-387° (164°) with a hole at r < 4 m, so there is no ground behind the base. The HiRISE square ends about 1.4 km east of the origin, so a full circle needs CTX fill or a new crop. The room's one-sided walls make the base invisible from outside.
2. **Heat (UNVERIFIED here).**
   - C-14 ran on MagSafe in open air, never in the viewer on battery, and was "fair" from 85 s.
   - The log froze at uptime 1091 s: the last 8 of 41 samples are repeats, and each sample covers 1 s in 30.
   - Apple, for `serious`: "Reduce the target framerate from 60 FPS to 30 FPS" (ThermalState docs, fetched 2026-10-24). A hot iPhone gets "lower frame rates" and "the display dims" (Apple Support 118431, 2026-05-14).
   - A18 Pro sustained-GPU stability is reported at 55-74% (Tom's Guide, UL 3DMark; seen only as snippets, unverified).
3. **Draw calls.** Apple: each geometry and material costs a draw command (`flattenedClone` docs). Forum users report that SceneKit on Metal batches nodes that share one geometry (4.36K draws to 8, Jul 2016; Jul 2024). Apple hasn't confirmed this, and SceneKit is in maintenance mode (WWDC25). Trap: `loadProp` returns a fresh `flattenedClone()` on every call, so 400 rocks placed with it add about 800 draws per frame on the main thread.
4. **The storm outdoors.** The dust emitter holds about 8,000 alpha particles at tau 4.6. Outside, it surrounds the judge: heavy overdraw.
5. **The near field.**
   - The ground will read as a smooth sheet: 2 m mesh rings, 2 m/px height, and a synthetic 1 m/px albedo. There are no height steps.
   - Rocks will shimmer: with no MSAA or anisotropy, a 10 cm rock at 20 m covers about 3 eye pixels.
   - The detail shader is cheap but needs `prepare`, or its first draw hitches.
6. **Minor.** The distortion pass is already within today's 60 fps. 120 Hz isn't enabled, so a 60 Hz cap gains nothing. The albedos are uncompressed in memory, not ASTC.

## 2. What the spike must measure

- **Scene:** the one that ships: real standpoint, rocks built the shipping way, room loaded, bubbles updating, storm at peak.
- **Per frame:** main-thread CPU time, GPU time (`gpuEndTime - gpuStartTime`) and presented-frame intervals. Report p99, max and frames over 20 ms per minute, not average fps.
- **Draw calls per eye**, from a GPU frame capture.
- **Thermal state and battery over time.** Phone in the viewer, unplugged, fixed brightness, starting warm. Two 10-minute sessions back to back.
- **Worst poses:** a scripted 360° turn, looking at the feet, looking at the base.
- **Pass bar:** at the start, GPU ≤ 9 ms and CPU ≤ 10 ms, which leaves room for a 40% throttle. Never `serious`. At most 1 dropped frame per minute.

## 3. Cheapest mitigations, in order

1. Bake the rocks into 2-4 static meshes with one material.
2. Hide the room, screens and indoor robots when outside, and the rocks when inside. Prepare both states.
3. A 512-1024² detail texture with `maxAnisotropy` 4, or the `multiply` slot with `.repeat` (no shader).
4. Eye buffers at 0.85 scale (28% fewer pixels), then 0.75. Set `framebufferOnly = true`.
5. Cap the dust outdoors.
6. At `serious`: eye scale 0.75, no rocks beyond 12 m, no dust.
7. ASTC albedos. Add LOD only if a 360° rebuild grows the mesh.

## 4. Fallbacks

- **Raised deck.** A pad platform or airlock ramp, 1.5-2 m up, with the habitat behind. Rocks start at 8 m (about 50), and the wall hides the missing half.
- **Baked sky plus a ground patch.** At 50 m the stereo disparity is under one eye pixel. Beyond that, a cube map baked from the real terrain looks the same. Keep a 30-50 m real patch underfoot and bake 2-3 tau versions.
- **Rover cab or airlock window** framing the existing wedge, or **the habitat window only** (today's proven scene).
