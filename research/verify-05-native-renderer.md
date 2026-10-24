# Verify 05: native iOS VR renderer (Swift + SceneKit + Cardboard SDK 1.36 Metal)

Date: 2026-10-23. Reviewer: adversarial review (Opus), not anchored on the authors' reasoning.
Target: `vr/AresVR/Sources/*` at commit `11c55e6` (flipV = false), iPhone 16 Pro, Cardboard V2, 2 h demo.

How I checked:
- **Source.** I read every file in `vr/AresVR/Sources` and these SDK sources: `rendering/ios/metal_distortion_renderer.mm`, `distortion_mesh.cc`, `lens_distortion.cc`, `head_tracker.cc`, `util/matrix_4x4.cc`, `util/rotation.h`, `qrcode/ios/*`, `screen_params/ios/*`, the Unity plugin, and `hellocardboard-ios`.
- **Headless SceneKit harness on an Apple GPU** (macOS 26.3, M3, same SceneKit framework). It mirrors `draw(in:)`: one `SCNRenderer` and one command buffer, with the camera and projection changed between the two eye renders.
- **Disparity measurement** on the six newest device captures in `.cache/captures/`.

Harness files are in `/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/scnstereo/`:
- `stereo_check.swift`: eye switching, orientation, actions.
- `misc_check.swift`: gamma, near plane, action timing.
- `disparity.swift`: measures disparity in a capture.

The profile decoder is in the parent folder: `/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/decode_profile.py`.

## Summary by severity

| # | Sev | Issue | One-line fix |
|---|-----|-------|--------------|
| C1 | **CRITICAL** | **There is no stereo.** Both eyes render the same stale camera (SceneKit implicit transaction). Proven on the device. | Use two eye cameras and call `SCNTransaction.flush()` before rendering. |
| H1 | HIGH | No recenter. "Forward" is whatever way the phone faced at launch, plus 2 h of yaw drift. | Wire `cardboard.recenter()` to a gesture and to every new wearer. |
| H2 | HIGH | Holding the Cardboard button for 2 s opens the camera QR scanner inside the headset. | Require 2 fingers, or move the scan to a server command. |
| H3 | HIGH (fresh install only) | The V2 URI is passed without a NUL terminator. The SDK reads it with `stringWithUTF8String`, so it can save no params and leave a black screen forever. | Append `0`, and draw a fallback frame when not configured. |
| M1 | MED | Button bounce or a double tap sends the same decision twice. | Debounce taps and hide the cards synchronously. |
| M2 | MED | `isMultipleTouchEnabled = false`: one resting touch blocks every later tap. | Set it to `true`. |
| M3 | MED | Frame hitches: lazy shader compiles (first dust storm, first card fade), panel texture conversion on main, tape decode on main. | Warm up with `prepare`, upload `MTLTexture`s off-thread, decode the tape on a background queue. |
| M4 | MED | Cross-thread data races that can crash rarely: debug panel closure, `Link.status`, `task`, `replayTimer`, capture path. | Snapshot values before dispatch; confine `Link` to one queue. |
| M5 | MED | Thermal over 2 h: MagSafe charging plus 60 fps, with no adaptive quality. | Unplug, cool between judges, and scale quality on `thermalState`. |
| M6 | MED | After the first connect, a later drop never re-enters replay (frozen world). After replay, the status stays "Offline replay" and pings never start. | Fix the `Link` state machine. |
| M7 | MED | Rendering continues behind the QR UI. The phone inserted the other way round shows an upside-down image with swapped eyes. | Pause while presenting; label the viewer. |
| L1-L9 | LOW | Effective near plane 0.1 m, a far-terrain seam, inout pointer escape, eye-texture density, and more (see below). | See each item. |

Confirmed correct (see the last section): `flipV = false`, the matrix chain and IPD sign, yaw/pitch direction, quaternion order, orientation pairing, projection layout, gamma, single action advance, DPI lookup, terrain winding, and the QR orientation.

---

## C1 CRITICAL: both eyes render the same, stale camera (no stereo, +1 frame latency)

**Code.** `VRViewController.swift:116-130` sets `world.cameraNode.simdTransform` and `world.camera.projectionTransform`, then calls `scnRenderer.render(...)`, and then does the same for the second eye. Both happen inside one `draw(in:)`, with no run-loop turn between them.

**Mechanism.** Changes to SceneKit nodes and cameras made outside an explicit `SCNTransaction` go into an implicit transaction. It is committed when the run loop turns. `SCNRenderer.render` draws the committed (presentation) state, so neither eye render sees the values set just before it.

**Harness evidence** (12 frames per variant, head yawing 0.01 rad per frame, run-loop turn between frames only; `stereo_check.swift`):

| Variant | Left eye correct | Right eye correct |
|---|---|---|
| As written in the app | 3/12 and 6/12 (two runs); 0/6 in the first harness | 4/12 and 1/12; 0/6 |
| As written, `atTime` bumped for eye 2 | 7/12 | 2/12 |
| `SCNTransaction.flush()` after each eye's update | **12/12** | **12/12** |
| Explicit `SCNTransaction.begin/commit` per eye | **12/12** | **12/12** |
| Two camera nodes, one `flush()`, switch `pointOfView` | **12/12** | **12/12** |

In the first harness run, without interleaved reference renders, both eyes were identical in every frame. That is exactly what the device shows.

**Device evidence.** I measured the six newest captures (`.cache/captures/capture-1792813931160.jpg` through `latest.jpg`; `latest.json` reports fps 59.98, thermal 0). The right half equals the left half shifted by exactly the lens separation (0.0639 m = 1157 px at 460 dpi):
- 86 to 132 of the 88 to 137 textured patches in each frame have disparity 0.
- The mean residual is 0 to 6 grey levels, which is JPEG noise.
- `latest.jpg` looks straight at the decision cards (1.9 m) and robots (about 2.5 m) in front of the terrain (kilometres away). Real stereo would give the cards about −22 px of disparity relative to the terrain (0.0639/1.9 rad × about 659 screen px per tan unit). Measured: 0.

**Effect in the headset:**
- The world is flat.
- Both eyes see one eye position from the previous frame, which adds about 16.7 ms of motion-to-photon latency.
- The first harness showed per-frame alternation between stale and fresh cameras. If that happens on the device, depth will flicker during head turns, and vertical head motion will cause vertical-disparity eye strain.
- With the V2 profile on this phone, both frusta are symmetric (50° on each side, decoded below), so the projection mix-up does not shift images today. A scanned asymmetric viewer would also misalign the two eyes horizontally.

**Fix** (verified variant "two cams, flush once"). Set it up once in `BaseScene`/`configureIfNeeded`:
```swift
// BaseScene
let head = SCNNode()                      // add to rootNode instead of cameraNode
let eyes = [SCNNode(), SCNNode()]
// in VRViewController.configureIfNeeded, after cardboard.configure(...):
for i in 0..<2 {
  let c = SCNCamera(); c.projectionTransform = SCNMatrix4(cardboard.projection[i])
  world.eyes[i].camera = c
  world.eyes[i].simdTransform = cardboard.eyeFromHead[i].inverse   // head-from-eye, fixed
  if world.eyes[i].parent == nil { world.head.addChildNode(world.eyes[i]) }
}
// draw(in:)
world.update(time: now, headView: headView, fps: fps, link: link)
world.head.simdTransform = (headView * world.viewOffset).inverse  // world-from-head
SCNTransaction.flush()                     // commit everything set this frame, before rendering
for eye in 0..<2 { scnRenderer.pointOfView = world.eyes[eye]; scnRenderer.render(atTime: now, ...) }
```
The minimal one-line patch is `SCNTransaction.flush()` right after line 119 (verified 12/12). The flush also commits the reticle and robot updates from `world.update`, which currently lag a frame too.

**Verify on device after the fix.** Take a capture facing the cards and run:
```
/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/scnstereo/disparity <capture.jpg> -v
```
Card patches should show d of about −20, and terrain or sky patches about 0.

## H1 HIGH: no recenter, so "forward" drifts and depends on the launch heading

`CardboardSession.recenter()` exists (line 39) but is never called. The Cardboard EKF has no magnetometer. Yaw zero is the device heading when tracking starts, and the gyro drifts it over hours. The window, the cards (at −Z) and the robots are laid out around "forward". A judge who sits facing any other way, or who arrives an hour into the demo, may find the decision cards behind them.

**Fix:**
- Call `cardboard.recenter()` from a deliberate input. For example, make the 2 s hold recenter instead of scanning the QR (see H2), or recenter on the first tap after the headset has been still.
- Recenter in `resume()` after unlock.
- Tell the operator to recenter for each judge while the judge looks straight ahead.
- `HeadTracker::Recenter` calls `sensor_fusion_->Reset()` (`head_tracker.cc:179-181`), so expect pitch and roll to settle again within a few hundred ms.

## H2 HIGH: a 2 s button hold opens the camera scanner inside the headset

`VRViewController.swift:50-52, 70-73`: any single touch held for 2 s calls `CardboardQrCode_scanQrCodeAndSaveDeviceParams()`. That presents a full-screen camera view (`qr_code.mm:35-54`). A judge who holds the Cardboard lever, which is natural when "pressing to choose", ends up staring at a camera feed. Someone must then take the phone out and press Skip.

**Fix:**
- Remove the gesture from the headset path. Trigger the scan from the server (add a `scan_viewer` message next to `capture`).
- Or set `lp.numberOfTouchesRequired = 2` together with `isMultipleTouchEnabled = true` (see M2). The viewer's lever is a single touch.

## H3 HIGH on a fresh install: the default viewer profile URI is not NUL-terminated

`CardboardSession.swift:49-50` passes `Array(cardboardV2URI.utf8)`, which has no terminator, along with its size.

The header promises a sized buffer (`cardboard.h:701-704`). The iOS implementation ignores `size` and calls `[NSString stringWithUTF8String:]` (`qrcode/ios/qr_code.mm:134-135`), which reads until a NUL. The possible outcomes:
- Trailing heap bytes that are not valid UTF-8 make the string `nil`. The URI becomes `https://(null)`, which is invalid, so nothing is saved.
- Valid trailing junk corrupts the base64 `p=` value, so decoding fails or yields a corrupt proto.

Either way `configure()` returns false on every frame. `draw(in:)` then returns before presenting (lines 110-111), and the screen stays black with no message.

It only bites when the app's data container is empty: a first install, or after deleting the app. It worked on the current phone, but the result is luck, not guaranteed.

**Fix:**
- Use `var uri = Array(Self.cardboardV2URI.utf8); uri.append(0)` and pass `Int32(uri.count - 1)`.
- When `!configured`, still clear and present a coloured frame with a "viewer profile missing, hold 2 fingers to scan" panel. That way a failure is never a silent black screen.
- Add `paramsSize` to `vr_stats`.

## M1 MED: double decisions from bounce or repeated taps

`BaseScene.swift:146-161`: after a successful choice, `cardsVisible` stays true until the 0.1 s scale animation's completion block calls `showCards(false)`. Any second touch-down in that window, including the conductive pad bouncing, calls `onDecide` again for the same escalation and sends a second `decide`.

**Fix:**
- Ignore taps within 300 ms of the previous one.
- In `tap()`, add `guard now >= hideUntil`.
- Set `cardsVisible = false` and `setHover(nil)` synchronously before starting the animation.

## M2 MED: single-touch mode can swallow every tap

`VRViewController.swift:47` sets `isMultipleTouchEnabled = false`. While any touch is down, UIKit delivers no other touches to the view. Examples are a judge's finger on the screen edge while inserting the phone, or a viewer pad left resting on the glass. The Cardboard button is then dead until that touch lifts.

**Fix:**
- Set it to `true`.
- In `touchesBegan`, fire once per new touch (`touches.count` new touches, debounced as in M1).
- Override `touchesEnded`/`touchesCancelled` as empty stubs to satisfy UIKit's override contract.

## M3 MED: frame-hitch sources

1. **Lazy pipeline compilation on main.** SceneKit builds Metal pipelines the first time a material variant is drawn:
   - Dust particles first emit only when `tau > 1.2` (`Outside.swift:283`), which is mid-demo during the storm beat.
   - The first card fade needs blended variants (`cardRoot.opacity`).
   - The first image on each `TextPanel` replaces a `UIColor` material, which is a texture variant.

   Each costs about 10 to 100+ ms.

   **Fix:**
   - At launch, call `scnRenderer.prepare([world.scene], completionHandler:)`.
   - Then run 1 to 2 s of warm-up behind a black frame: dust `birthRate` > 0, `cardRoot.opacity = 0.01` and unhidden, every panel drawn once.
2. **Panel swap is still costly on main.** `Panels.swift:42-45` assigns a `UIImage`. SceneKit converts it to an `MTLTexture` and builds mipmaps (`mipFilter = .linear`) during the next `render` on the main thread. Panel sizes run from 768x480 up to 1344x768.

   The debug panel's key includes `Int(fps.rounded())` (`BaseScene.swift:205`), so it redraws about once a second as fps wobbles between 59 and 60. That is a periodic upload in the headset.

   **Fix:**
   - Drop fps from the key, or quantise it to 5.
   - Build the `MTLTexture` on the panel queue with `MTKTextureLoader.newTexture(cgImage:options:[.SRGB: true, .generateMipmaps: true])` and assign the texture as `contents`.
   - Set `fmt.preferredRange = .standard`. With `.automatic` on a P3 display, `UIGraphicsImageRenderer` may produce 16-bit float (64 bpp) images, doubling upload size. Check with `img.cgImage?.bitsPerComponent`.
3. **Tape decode on main.** `Link.loadTape()` decodes the 1.3 MB `tape.json` with `JSONSerialization` plus one `JSONDecoder` call per frame. It runs on main from the 12 s `asyncAfter` (`Link.swift:78-111`), giving one visible stall when replay starts. Decode it on a background queue at launch.
4. **Replay bumps the version needlessly.** `replayTick` increments `stateVersion` at 10 Hz even when the frame is unchanged (`Link.swift:113-125`), so `applyState` and `Outside.apply` run 10 times a second. It is cheap but pointless. Bump only when the frame index changes.

## M4 MED: data races that can rarely crash over 2 h

- **Debug panel closure.** `BaseScene.updateDebug` (lines 206-212) runs on `ares.panels` and reads `self.taps`, `self.lastTapText`, `self.latest` (a struct containing Strings, arrays and dictionaries) and `link.statusText`. The main thread writes these; in replay that happens every 100 ms.

  A concurrent read of refcounted Swift values during an assignment can be a use-after-free. The other panels already capture values first. Do the same here: build the strings on main and capture them.
- **`Link.status`.** It is written under `lock` from the URLSession delegate queue but read without the lock in `handle` (line 182), `statusText` (line 252) and the 4 s timeout (line 143).
- **Other `Link` fields.** `task`, `current`, `index`, `replayTimer` (read by `isReplay` on the network queue, line 181) and `everConnected` are touched from both main and the delegate queue.

  **Fix:** create the session with `delegateQueue: .main`. JSON decode is the only heavy part; do it on a private queue and post the result. This makes `Link` single-threaded.
- **Capture path.** `sendCapture` runs on Metal's completion thread (`VRViewController.swift:146`). It reads the drawable's texture after `present`, so it can be torn or reused, allocates 12.6 MB, and touches `link.current` and `fps`. It is debug-only; hop to a private queue and snapshot the values.

## M5 MED: thermal over 2 hours

An earlier "serious" thermal state was recorded while the phone sat on a MagSafe charger. Charging plus 2 × 1311x1206 eye passes, a full-resolution distortion pass and 60 fps for 2 h is the worst case. When iOS throttles at serious or critical, frames drop and the image judders. The app has no response to this.

**Fix:**
- No MagSafe during the demo. Use a cable at low draw or nothing, take the case off, and cool the phone between judges.
- Observe `ProcessInfo.thermalStateDidChangeNotification`. At `.serious`, render eyes at 0.8 scale (re-make `eyeColor`/`eyeDepth`) and set dust `birthRate = 0`.
- Add GPU time (`cmd.gpuEndTime - gpuStartTime`) to `vr_stats` so the laptop sees throttling before the judge does.

## M6 MED: `Link` state machine gaps

- **No return to replay.** Replay is entered only once, 12 s after start, if nothing ever connected (`Link.swift:78-81`). If venue Wi-Fi drops after the first connection, the world freezes on the last state, showing "Offline · retrying", for the rest of the session.

  **Fix:** in `lost()`, schedule `enterReplay()` after about 8 s if still not connected.
- **Status stuck on replay.** While replay is active, `setStatus(.connecting)` is refused (line 248), so `status` stays `.replay`. When the server reappears, `handle` checks `if case .connecting = status` (line 182). That is false, so the status never becomes `.connected` and `keepAlive` never starts. The panels then say "Offline replay" while the app is live, and dead links are found only by receive errors.

  **Fix:** on the first message from the current `task`, always set `.connected` and start `keepAlive`.
- **Orphan tasks.** `handle` does not check that the message came from the current `task`. A race between the 4 s timeout's `cancel()` + `connectNext()` and the cancelled task's failure callback can leave an un-cancelled orphan task that also feeds state.

  **Fix:** pass `t` into `handle` and drop messages when `t !== task`.

## M7 MED: QR UI, orientation and operator issues

- **Rendering behind the QR UI.** The MTKView keeps rendering behind the full-screen QR scanner while the camera runs, which wastes heat. Google's sample pauses rendering while its dialogs are up (`HelloCardboardViewController.mm:191-195`). In `draw(in:)`, return early when `presentedViewController != nil`.
- **Phone orientation in the viewer.** Only `landscapeRight` is supported, matching Google. A phone inserted rotated 180° shows the world upside down with the eyes swapped. Mark the viewer: Dynamic Island / camera on the **left**, USB-C on the right.
- **Operator checklist:**
  - Enable a Focus (Do Not Disturb) mode so notification banners do not appear in the headset.
  - Accept the Local Network and camera prompts before the first judge.
  - Expect the Dynamic Island and home indicator to intrude slightly at the outer edges of the eye views. This cannot be avoided.

## LOW

- **L1. Near plane and depth precision.** SceneKit applies the custom GL-style `projectionTransform` as-is in Metal's [0,1] clip space.
  - Verified with probes at 0.06, 0.08 and 0.095 m: all clipped. At 0.105 m: visible.
  - So the effective near plane is 2n ≈ 0.1 m. That is harmless for this scene.
  - With zNear 0.05 and zFar 60 km, depth resolution is about 6e-7·d² m, roughly 3 m at 2.2 km.
  - The far terrain (radius 2150 to 25000 m) and near terrain (radius 4 to 2350 m) overlap in a 200 m ring, so a faint seam shimmer near the horizon is possible.
  - **Fix:** zFar 30 km (the far mesh ends at 25 km), and lower the far mesh about 2 m inside r < 2350 in the generator.
- **L2. Inout pointer escapes.** `CGContext(data: &px, …)` in `Outside.makeSky` and `CGContext(data: &bytes, …)` in `sendCapture` let an inout-to-pointer conversion escape the call, and the compiler warns about it. It works in practice but is UB. Use `data: nil` and write through `ctx.data`.
- **L3. Eye texture density.** Each eye texture is 1311 px wide over 2·tan(50°), about 550 px per tan unit, against about 659 screen px per tan unit at the lens centre. That is 83% density, so text is slightly soft. If GPU headroom allows after C1 and M5, try an eye width of about 1600.
- **L4. Pose prediction.** The 50 ms prediction is Google's "without vsync" default. After C1 removes the extra frame, it may overshoot a little (slight swimming on fast turns). Optionally tune to about 35 to 40 ms by eye.
- **L5. `framebufferOnly = false`.** It is needed only for debug captures and costs drawable bandwidth. Leave it if captures matter; otherwise set it to `true` for the demo build.
- **L6. Blink overwrites mood.** A robot blink captures `s = eyeL.scale.y` and restores it afterwards (`Robots.swift:252-255`). A mood change during a blink is therefore overwritten until the next mood change. Cosmetic.
- **L7. Misleading comment.** The comment at `VRViewController.swift:25` ("Cardboard's UVs assume bottom-left origin") now argues for the wrong setting. Replace it with the reasoning in the next section and remove the `flipV` toggle.
- **L8. Terrain header disagrees with the generator.** The bundled OBJ header says "+X east, +Y up, +Z south (LEFT-handed, Unity)". `research/code/build_polar_mesh.py` writes X = −East, Z = North. Winding is correct for SceneKit: all 67,952 far and 87,906 near faces are CCW from above and agree with their `vn`. But confirm in the headset that azimuth 305°, straight ahead, shows the delta. If X were really −East, the drill and panels (placed by `ground(az:)`) would sit mirrored relative to the terrain.
- **L9. Memory warnings are not handled.** The estimated footprint is about 300 to 400 MB (two 4096² albedos with mipmaps, about 180 MB GPU), well under the 16 Pro's limit. Acceptable.

---

## Confirmed correct, with evidence

- **`flipV = false` (top_v 1, bottom_v 0) is right. Keep it.**
  - The mesh's v = 0 is the bottom of the eye's FOV (`distortion_mesh.cc:44-49`; vertices at NDC y = −1, Metal bottom).
  - The Metal vertex shader flips v for Metal (`metal_distortion_renderer.mm:80`: `1.0 - tex_coords.y`).
  - The fragment shader samples `start + tc·(end − start)`, with start = (left_u, bottom_v) and end = (right_u, top_v) (lines 89, 216-221).
  - With top_v 1 and bottom_v 0, the top of the FOV samples Metal row 0. The harness shows row 0 of a SceneKit offscreen texture is the image top (red-above / green-below check).
  - Google's GL sample (`HelloCardboardRenderer.mm:150-151`) and the Unity plugin, which covers Metal (`unity/xr_unity_plugin/cardboard_display_api.cc:341-342`), both use top_v 1 and bottom_v 0.
  - Your `flipV = true` capture showing a vertical, water-reflection flip is the predicted result.
- **View chain.** `eyeFromHead · T(pos)·R(q) · T(0, −1.6, 0)` with `camera.simdTransform = eyeView.inverse` is identical to `HelloCardboardRenderer.mm:195-204, 240-249` (floor −1.7 there). SceneKit's camera looks down −Z with +Y up, like the GL convention. Yaw and pitch are not mirrored.
- **Quaternion order.** The SDK's quaternion is (x, y, z, w) (`util/rotation.h`: "vector part in the first 3 elements"), which matches `simd_quatf(ix:iy:iz:r:)`. The pose is world-to-head, as the sample uses it.
- **Orientation pairing.** `kLandscapeLeft` maps to `UIDeviceOrientationLandscapeLeft` (`cardboard.h:47-51`), which is `UIInterfaceOrientationLandscapeRight`. Google's sample uses exactly this pair (`HelloCardboardViewController.mm:92-95` returns `MaskLandscapeRight`, and the renderer passes `kLandscapeLeft`).
- **IPD sign.** The left eye is `T(+ipd/2)` (`lens_distortion.cc:44-47`), so the left camera sits at −ipd/2. Eye indices 0/1 map to kLeft/kRight, and textures are passed in that order.
- **Projection.** It is a GL frustum stored column-major (`matrix_4x4.cc`: `m[col][row]`). `CardboardSession.matrix` and `SCNMatrix4(_:)` map it memory-identically. SceneKit honours asymmetric frusta once they are committed (harness).
- **Viewer profile.** The V2 URI decodes to s2l 0.0364, IPD 0.0639, k = [0.2416, 0.3013], BOTTOM alignment, tray 0.035, FOV 50/50/50/50. On the 16 Pro the raw angles are 62.9 / 50.1 / 50.2 / 54.3°, so all clamp to 50°, giving symmetric frusta for both eyes.
- **Gamma.** Correct end to end. A 50% sRGB constant material is written as byte 127 into `bgra8Unorm_srgb`. The distortion pipeline is built with the drawable's format, and filtering happens in linear space.
- **Actions advance once per frame.** Two renders per frame at the same `atTime`: `moveBy` 10 m/10 s gave 2.80 m after 3.0 s, so no double advance. Implicit `SCNTransaction` animations use system time.
- **Screen size.** `resolutions.csv` maps iPhone17.1 to 460 dpi, and `sdk.bundle` ships in `Release-iphoneos/AresVR.app`, giving 0.1448 × 0.0666 m.
- **QR scanner orientation.** The scanner returns `UIInterfaceOrientationMaskAll` (`qr_scan_view_controller.mm:282-284`), which intersects with the plist's landscapeRight. There is no orientation crash. The completion fires after the params are saved.
- **Lifecycle.** The pause/resume order matches Google's sample, and `isIdleTimerDisabled` is set at launch and on every activation.

## Reproduce

All paths are in `/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/scnstereo/`:
```bash
swiftc -O -swift-version 5 stereo_check.swift -o stereo_check && MTL_DEBUG_LAYER=1 ./stereo_check
swiftc -O -swift-version 5 misc_check.swift -o misc_check && MTL_DEBUG_LAYER=1 ./misc_check
swiftc -O disparity.swift -o disparity && ./disparity /Users/TAITA/Projects/ares/.cache/captures/latest.jpg -v
```
Caveat: the harness runs macOS SceneKit on an M3. The device captures independently confirm C1 on iOS 26 / A18 Pro.
