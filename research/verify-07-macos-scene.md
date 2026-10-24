# verify-07: C-15, headset SceneKit scene on a native macOS AppKit target

Adversarial review, 2026-10-24. Reviewer did not see the team's reasoning; findings come from reading the code, compiling it, and running probes on this Mac.

**Claim (C-15):** "The headset app's SceneKit scene code (iOS, Swift 5 language mode, UIKit-based) can be compiled unchanged-in-behavior for a native macOS AppKit target and render the same scene on this Mac, at a steady frame rate, as one undistorted full-screen view."

## Verdict: HOLDS WITH CAVEATS

- **The literal claim is false at the source level.** The 8 shared files do not compile for macOS as they are: there are 37 errors in 6 of the 8 files.
- **The port is small and mechanical.** About 30 changed lines plus a 35-line platform shim make them compile for both macOS and iOS (checked with `swiftc -typecheck` against both SDKs).
- **With that port, the scene renders correctly on this Mac.** Measured with offscreen `SCNRenderer` on the M3:
  - every asset loads;
  - text is upright;
  - colors of constant-lit surfaces match the headset capture within 1/255;
  - GPU cost at 3840x2486 is p50 3.3-3.6 ms, p99 5.7 ms, max 9.3 ms, with 0 frames over 16 ms in 72 s (4x MSAA: max 11.1 ms).
- **Still unverified:**
  - on-screen presentation pacing on macOS 26.3 (there are third-party reports of a Tahoe pacing bug);
  - the spectator networking path;
  - the threading model if `SCNView` is used.

  Until an on-screen spike passes (Tier 1 check 4), C-15 stays UNVERIFIED.

### Setup correction (matters for performance)

The detected setup says "2880x1864". That is the panel. The display is set to **"looks like 1920x1243"**, so the backing store is **3840x2486 px (9.5 Mpx)**, and WindowServer scales it down to the panel. That is 3.0x the iPhone's combined eye textures (2622x1206). Other display facts:

- The notch's safe-area top inset is 37 pt, so a normal full-screen content area is 3840x2412 px.
- Refresh is 60 Hz. The color profile is "Color LCD" (P3).

Source: `CGDisplayCopyDisplayMode` and `NSScreen` probe, scratch `probes/display.swift`.

### Method

- All work was done on copies in the session scratchpad. No repo file other than this report was touched.
- The probe `.app` pointed at a dead port (`ws://127.0.0.1:9`) and played the bundled tape. It never connected to the live server on :8787.
- Audio was muted.

---

## 1. Compile blockers

Baseline: the 8 shared files typecheck cleanly for iOS (`arm64-apple-ios17.0`, Swift 5): 0 errors, 0 warnings.

For macOS with no changes: `BaseScene.swift:2: error: no such module 'UIKit'`. The same applies to every file that imports UIKit: BaseScene, Outside, Room, Robots, Screens, Panels.

I then swapped `import UIKit` for `import AppKit` and added `typealias UIColor = NSColor`, `UIImage = NSImage`, `UIFont = NSFont` and `UIBezierPath = NSBezierPath`. These errors remained (`-continue-building-after-errors`):

| File:line | Error | Cause |
|---|---|---|
| BaseScene.swift:151 (x2) | `CGFloat - Float`, `+=` mismatch | `caption.node.position.y` is CGFloat on macOS; `capY` is Float |
| Outside.swift:28 | cannot assign Float to CGFloat | `root.eulerAngles.y = ...` |
| Outside.swift:85 | same | `n.eulerAngles.y = yaw * .pi / 180` |
| Outside.swift:124 | cannot return CGFloat as Float | `convertPosition(...).y` |
| Outside.swift:249 | `UIGraphicsImageRenderer` not found | `softDot()` |
| Outside.swift:313 | missing `size:` | `UIImage(cgImage:)`, whose NSImage equivalent is `init(cgImage:size:)` |
| Outside.swift:324 | CGFloat passed as Float | `simd_quatf(angle: root.eulerAngles.y, ...)` |
| Panels.swift:38, :41 | `UIGraphicsImageRendererFormat` / `UIGraphicsImageRenderer` not found | `TextPanel.update` |
| Panels.swift:86 | `NSFont` has no `lineHeight` | `Draw.text` |
| Panels.swift:95 (x2) | NSBezierPath has no `roundedRect:cornerRadius:` | `Draw.fill` |
| Robots.swift:37, 196, 197, 198, 199 | Float assigned to CGFloat | `eulerAngles.y/z`, `position.y` |
| Robots.swift:216 | "unable to type-check in reasonable time" | `SCNVector3(home.x, home.y + 0.035 * sin(...), home.z)` mixes CGFloat and Float |
| Robots.swift:219 | `SIMD3<Float> - SIMD3<CGFloat>` | `user - SIMD3(node.position...)` |
| Robots.swift:223 | `.pi` ambiguous, FloatingPoint comparison | follows from 222 (`target - node.eulerAngles.y`) |
| Robots.swift:254 | CGFloat passed as Float | `atan2(-pos.x, -pos.z)` builds `faceYaw` |
| Room.swift:57, 67, 93, 117 | Float assigned to CGFloat | `eulerAngles.y = -m * .pi / 180` and similar |
| Room.swift:143 | `UIGraphicsImageRenderer` not found | `floorMaterial()` |
| Sound.swift:10-11 (x7) | `AVAudioSession` unavailable in macOS | session setup |

Related notes:

- Link.swift compiles on macOS unchanged. Screens.swift needs only its import changed.
- Some lines compile on macOS without changes:
  - lines that build vectors from all-Float values, such as `SCNVector3(s.0, s.1, -1.9)` and `Room.ring`, because the SceneKit overlay has Float, CGFloat and Double initializers;
  - `SCNVector3(origin)` from `SIMD3<Float>`;
  - literal assignments such as `eulerAngles.x = .pi / 2`.
- `SCNMatrix4(_ m: simd_float4x4)` (VRViewController.swift:302-309) assigns Float into SCNMatrix4 fields, which are CGFloat on macOS. It is iOS-only today, but it breaks if it is ever moved into shared code. The SDK already provides `SCNMatrix4(float4x4)`.
- Swift 6 language mode fails immediately (`Sound.shared` not concurrency-safe, Sound.swift:5). The Mac target must keep `SWIFT_VERSION 5.0`. XcodeGen's default is 5.0.

### Build-configuration blockers (XcodeGen 2.46.0, checked by generating a test macOS target)

- **Deployment target.** `project.yml` sets only `deploymentTarget.iOS: "17.0"`. A macOS target gets `MACOSX_DEPLOYMENT_TARGET = 26.5` (the SDK default; `SDKSettings.plist` DefaultDeploymentTarget is 26.5), but this Mac runs **26.3**.
  - A bare command-line binary built for 26.5 still ran (tested).
  - An app bundle carries `LSMinimumSystemVersion` from that setting, so LaunchServices and Xcode's run-destination check will refuse it on 26.3. I did not test this, because it would pop a dialog.
  - Fix: set `deploymentTarget.macOS` explicitly.
- **iOS-only pieces.** The Mac target must exclude `App.swift`, `VRViewController.swift`, `CardboardSession.swift`, the bridging header, `sdk.bundle` and `-lCardboardSDK -lProtobuf-C++`. The Cardboard `.a` files are arm64 iOS-only (LC_BUILD_VERSION platform 2).
- **Presets.** XcodeGen's macOS presets set `ENABLE_APP_SANDBOX = NO` and `ENABLE_HARDENED_RUNTIME = NO`, so outgoing WebSocket traffic needs no entitlement. The application preset sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`; the iOS target overrides that to `""`, and the Mac target must do the same.

### Verified fix set

Scratch copy `port/`; macOS and iOS both typecheck with 0 errors and 0 warnings.

- **Platform shim (one file):**
  - `#if os(macOS)` AppKit typealiases;
  - a `renderImage(size:opaque:_:)` CGContext helper that replaces all 3 `UIGraphicsImageRenderer` uses;
  - `fontLineHeight()` returning `ceil(ascender - descender + leading)` on macOS.
- **All 14 Float/CGFloat sites** switch to the `simd*` accessors (`simdPosition`, `simdEulerAngles`, `simdConvertPosition`, `simdWorldCoordinates`), which are `Float` on both platforms. Robots.swift:254 wraps `atan2` arguments in `Float()`.
- **`UIBezierPath(...).cgPath`** becomes `CGPath(roundedRect:cornerWidth:cornerHeight:transform:)`. Unlike UIBezierPath, CGPath asserts if 2 x radius exceeds the width or height; current callers stay within bounds.
- **`makeSky` and `softDot`** return `CGImage`. SceneKit accepts `[CGImage]` for cube maps and a `CGImage` as `particleImage`.
- **`AVAudioSession`** goes behind `#if os(iOS)`.

## 2. Runtime divergences

These were found by running the port in a real `.app` bundle (flat `Contents/Resources`) on this Mac.

### Checked and fine (no divergence)

- **Bundle lookups.** `url(forResource:"near", withExtension:"obj", subdirectory:"terrain")` returns nil on macOS too, and the flat fallback (Outside.swift:51, :57) finds `Contents/Resources/near.obj`.
  - Props (Outside.swift:105) and sounds (Sound.swift:13) have no subdirectory fallback. They work only while resources stay flat, as XcodeGen groups copy them today.
  - If anyone switches to a folder reference (`type: folder`), all props and sounds silently disappear.
  - The 42 flattened files have no name collisions.
- **ModelIO OBJ/MTL.** Terrain loads (near 87,906 triangles, far 67,952), as do all props: 109 geometry nodes, plus the rocket, panels and drill.
  - `Unable to find mtl file near.mtl / far.mtl` is logged. The terrain OBJs reference MTL files that aren't bundled; this is harmless because the material is replaced, and iOS behaves the same.
- **Color handling (offscreen into `bgra8Unorm_srgb`).** Constant-lit surfaces match the headset capture `docs/evidence/offline-replay.jpg`:
  - card background (15,18,27) on iOS vs (15,18,26) on Mac;
  - caption bar (9,10,15) vs (8,10,15).

  Linear-space rendering and sRGB texture decoding behave the same on both platforms.
- **Cube-map sky and particles.** The sky gradient renders through the window and storm dust streaks render. Face order and orientation go through the same SceneKit code. I did not separately verify the sun-disc direction.
- **Text drawing from the background queue (`ares.panels`)** with a thread-local `NSGraphicsContext` ran for 3 x 72 s with no crash.
- **NSColor(red:green:blue:alpha:)** is sRGB on macOS, so `getRed` works on it (probe).

### Divergences and traps

1. **Text orientation trap (verified).** The `renderImage` helper must do both of the following:
   - flip the CTM (`translateBy(0, h)`, `scaleBy(1, -1)`);
   - install `NSGraphicsContext(cgContext:flipped: true)`.

   The two obvious partial ports fail (probe `probes/text.swift`):
   - flip the CTM but use `flipped: false`: text is upside down;
   - no CTM flip with `flipped: false`: text is upright, but every `ctx.fill` and `stroke` lands mirrored vertically. Bars, borders and the sparkline (Screens.swift:54, :61-71; BaseScene.swift:185, :251-253) move to the bottom.
2. **`getRed` crash (verified).** `NSColor(white:alpha:).getRed(...)` raises `NSInvalidArgumentException` ("not valid for the NSColor Generic Gray Gamma 2.2 Profile colorspace"), which terminates the app.
   - Robots.swift:58 calls `color.getRed` on `Palette.role(role)`.
   - That function's `default:` returns `Palette.text = UIColor(white:)` (Panels.swift:53, :72).
   - It is safe today only because all 5 robot roles map to RGB colors. A new role, or a renamed one, crashes the Mac app and not the iPhone.
   - Fix: `color.usingColorSpace(.sRGB)!.getRed`.
3. **MTKView default pixel format (verified).** MTKView on macOS defaults to `colorPixelFormat = .bgra8Unorm`, not `_srgb`. Its `colorspace` defaults to sRGB.
   - Rendering the scene into `bgra8Unorm` makes it far too dark: panel background (13,15,20) becomes (1,1,2), and the wall (179,151,120) becomes (116,80,49).
   - The driver must set `.bgra8Unorm_srgb`, as VRViewController.swift:57 does.
   - If a raw `CAMetalLayer` is used instead, its `colorspace` defaults to nil ("not color-matched", Apple docs), so sRGB values would be shown as P3 on this panel and look oversaturated. Set it to sRGB.
   - SCNView's own layer is `bgra8Unorm_srgb` + sRGB (probe), so SCNView is fine on this point.
4. **SCNView defaults differ from iOS (probe).**
   - `antialiasingMode` is 4x MSAA by default (Apple docs say "In macOS, the default mode is multisampling4X"; on iOS it is none), so edges look smoother than in the headset.
   - `isPlaying = false`, `rendersContinuously = false`, `preferredFramesPerSecond = 0`.
   - With an SCNView, set `rendersContinuously = true` and `isPlaying = true`. Otherwise it renders only on change, and actions such as fades, drill spin, beacon and blink depend on scene time advancing.
   - The verified `SCNRenderer.render(atTime:)` path (mirroring VRViewController) advanced actions correctly: the cards faded in.
5. **Threading if driven from `SCNSceneRendererDelegate` (verified thread).**
   - `renderer(_:updateAtTime:)` runs on `com.apple.scenekit.renderingQueue.SCNView0x...` with `isMainThread=false`, at 60 Hz (121 callbacks in 2 s).
   - Every frame on iOS today runs on the main thread (`MTKView.draw`, VRViewController.swift:156-182). Calling `BaseScene.update` from the render queue creates these unsynchronized races:
     - `TextPanel.lastKey/generation`: written by the caller at Panels.swift:32-35, read on main at Panels.swift:43.
     - `Outside.skyBusy/lastSkyKey`: written in Outside.swift:349-351 and on main at :358-359.
     - `BaseScene.tap()` (main; mouse or keyboard on Mac) against `update()` (render queue): both read and write `now`, `hovered`, `cardsVisible`, `hideUntil` and `cardTargets`. `refreshCards` reassigns the `cardTargets` array at BaseScene.swift:241 while `tap()` indexes it at :211 and :216. A concurrent Swift array read during reassignment can crash.
     - `Link` callbacks dispatched to main (`onDecide`, `onRecenter`, `onCaptureRequest`) touch the same state.
     - `Sound.play` from the render queue: AVAudioPlayer is not documented as thread-safe.
   - Pre-existing on iOS as well: `Link.statusText` (Link.swift:308-315) reads `status`, an enum with a String payload, without the lock. Meanwhile `handle()` writes it from the URLSession delegate queue (Link.swift:206-208). `everConnected` (Link.swift:202) and `isReplay` (Link.swift:203, reading `replayTimer`) are also touched off-main.
   - **Recommendation:** use MTKView + `SCNRenderer.render(atTime:)` on the main thread, exactly as iOS does. This is the path I measured. Do not use the SCNView delegate.
6. **It is not a mirror; it is a second client with local state.** The server already has a `spectator` role (packages/server/src/main.ts:101, :120-121, :149, :550-575; uncommitted and still changing, so line numbers are as of 2026-10-24 04:2x). Against that:
   - **Do not reuse `Link.loadCandidates()`.** Every `ares.json` candidate is a LAN address (10.20.50.20, 169.254.49.67, `.local`, 172.20.10.x).
     - A socket from this Mac to its own LAN IP arrives with a non-loopback `remoteAddress`, so `?client=spectator` is refused with close code 4401 (main.ts:550-552).
     - With `client=vr&t=<token>` it is accepted as a **headset**: it becomes `activeHeadset` (main.ts:560-561). The real headset's `vr_pose` is then dropped (main.ts:574), the console shows "headset connected" with the phone off, and decisions are attributed to "headset".
     - The spectator must use `ws://127.0.0.1:8787/?client=spectator` and no token.
   - **`force_replay` is not sent to spectators.** It is in `VR_TYPES` but not `SPECTATOR_TYPES` (main.ts:120-121). When the console forces the headset into tape replay, the Mac keeps showing live state.
   - **Link's 12 s auto-replay** (Link.swift:98-101) would make the Mac play the tape whenever the server is unreachable, independently of what the headset is doing.
   - **Hover is local.** Hover and reticle come from a hit-test at the local head origin (BaseScene.swift:126-144). The relayed pose carries only the quaternion `q` (main.ts:149), not the Cardboard neck-model translation, so hover can differ near card edges. Drive hover from the relayed `gaze` index instead.
   - **Local timing differs.** Tap feedback, the 1.5 s `hideUntil` after a choice (BaseScene.swift:218) and caption fade timing are all local; `vr_choice` is not handled by `Link.handle` (it falls through to `default`).
   - **Robots won't move in sync.** Robot bob phase and blink timing derive from `role.hashValue` (Robots.swift:35), which Swift seeds randomly per process, and from a per-process clock. Robots will not bob or blink in sync with the headset.
   - **Pose rate.** Poses arrive at "30+ times a second" (main.ts:133) with network jitter, against a 60 Hz render. Without interpolation (slerp or exponential smoothing) the big screen will judder even at a steady 60 fps.
   - **Double audio.** Sound plays on the Mac too (blips, alerts, storm rumble), offset in time from the phone.
   - **Debug panel text.** It shows "Two-finger hold 2 s (out of the viewer) scans your viewer QR" (BaseScene.swift:293) and the Mac's own fps.
7. **Font metrics: close, not identical (verified).**
   - On macOS, `ceil(ascender - descender + leading)` equals or exceeds the laid-out line height at 44-72 pt, so the `h = lineHeight * maxLines` budget (Panels.swift:86) fits and no lines drop.
   - Wrapping still differs. The headset capture truncates the card title to "Buy 15 now from / Ridgeline Power Syste...", while the Mac renders "Ridgeline Power Systems" in full on two lines.
   - Expect similar but not pixel-identical panels.
8. **`UIGraphicsImageRenderer` defaults differ from a plain CGContext.**
   - On iOS, `Room.floorMaterial()` (Room.swift:143) and `softDot()` (Outside.swift:249) use the default format: screen scale 3 (a 1536x1536 floor texture) and automatic, likely extended, range.
   - A scale-1 CGContext port gives 512x512.
   - Keep `UIGraphicsImageRenderer` behind `#if os(iOS)` so the verified iOS build stays token-identical.
9. **Visibility, App Nap, notch.**
   - SCNView made **0** delegate callbacks in 2.5 s while its window was not visible (off-screen window probe).
   - macOS 26 has a reported bug with Metal views in non-visible windows (see section 4).
   - If the presenter covers the full-screen view with the console, expect it to stop, and possibly to stutter on return.
   - App Nap can throttle Link's `asyncAfter` keepalive and the replay `Timer` while the app is hidden.
   - Full screen on this notched panel renders below a 37 pt top inset unless the app opts out.

## 3. Performance risks

Measured with offscreen `SCNRenderer` into private textures, waiting on each command buffer, paced at 60 Hz, using the bundled tape (clear sky, then storm at tau up to 4.6, then the 4 cards), with a yaw sweep of ±45°:

| Run | GPU ms p50 / p95 / p99 / max | Frames > 16 ms | CPU encode p50 / p95 |
|---|---|---|---|
| 3840x2486, no MSAA, 72 s | 3.34 / 4.03 / 5.44 / 9.32 | 0 / 4289 | 1.95 / 2.82 ms |
| 3840x2486, no MSAA, with autorelease pool, 72 s | 3.62 / 4.79 / 5.71 / 8.62 | 0 / 4289 | 1.88 / 2.75 ms |
| 3840x2486, 4x MSAA (memoryless), 22 s | 4.13 / 6.45 / 8.60 / 11.09 | 0 / 1289 | 0.74 / 2.20 ms |

Thermal state stayed 0 (nominal) throughout. 2880x1864 is a subset of this load and was not run separately.

GPU headroom is about 4x. The real risks are elsewhere:

- **One-off 150 ms main-thread hitch when the first state arrives (verified cause).**
  - `Sound.shared` is created lazily inside `applyState` (BaseScene.swift:164, `Sound.shared.setStorm`). Its init (15 AVAudioPlayers plus rumble, Sound.swift:9-25) took **149.4 ms**.
  - Prewarming `Sound.shared` at launch removed the spike: max encode fell from 158.8 ms to 5.4 ms.
  - The same code path exists on iOS, so the headset probably has the same hitch when it connects or starts replay.
- **First-frame pipeline compile:** 70 ms (169 ms with MSAA) on frame 0, even after `prepare(_:completionHandler: nil)`, which is asynchronous. This happens once, at launch.
- **Autorelease pools.** Without a per-frame `autoreleasepool`, footprint grew from 190 MB to 891 MB in 70 s. With a pool it held at about 540 MB.
  - MTKView's main-thread draw is drained by the run loop.
  - A custom loop or a `CVDisplayLink` thread must wrap each frame itself.
- **Not measured: on-screen presentation.** This covers the WindowServer downscale from 3840x2486 to 2880x1864, drawable acquisition and vsync pacing. This is exactly where the macOS 26 reports below sit.
- **Not measured: a long soak** on this fanless Air with the node server, the browser console and the LLM adapter running, nor running on battery or in Low Power Mode.
- **Neutral:**
  - texture memory (two 4096² terrain JPEGs, about 85 MB each with mips);
  - transparency (cards and caption with `renderingOrder`, additive halos, alpha dust);
  - lighting (one directional light, no shadows, one ambient, one omni).

  None of these showed up in GPU time.

## 4. Platform status

| Date | Source | Finding |
|---|---|---|
| June 2025 | WWDC25 session 288, "Bring your SceneKit project to RealityKit" (https://developer.apple.com/videos/play/wwdc2025/288/) | SceneKit is **soft-deprecated** and in maintenance mode (critical fixes only). RealityKit is recommended. |
| Aug 2025, Apr 2026 | Apple Developer Forums thread 795520, DTS Engineer answers (https://developer.apple.com/forums/thread/795520) | "Soft deprecation", "Apps will continue to work", "Maintenance mode", "No date for hard deprecation". Removal would come only after a hard deprecation "with ample warning". The April 2026 answer repeats the same terms. |
| fetched 2026-10-24 | Apple docs, SCNView / SCNSceneRendererDelegate / antialiasingMode (https://developer.apple.com/documentation/scenekit/scnview) | Availability metadata reads "macOS: 10.8.0 - 26.0.0", which is the documentation-level deprecation marker. |
| 2026-10-24 (local) | MacOSX26.5.sdk on this Mac | SceneKit.framework ships (tbd current-version 608.255). No class-level `API_DEPRECATED` in the headers (only legacy method-level ones from 10.10-10.13). The Swift interface has 0 `deprecated`. The shared code compiles with **0 warnings** for macOS 26.0 and iOS 17 targets. |
| 2025-12-21 | Psychtoolbox forum, M. Kleiner, post #32 (https://psychtoolbox.discourse.group/t/timing-performance-issues-on-macos-26-tahoe/5767/32) | On macOS 26 on Apple Silicon, vsync-timed presentation is capped at **half the refresh rate** (about 30 fps on 60 Hz). No workaround was known at the time. PTB 3.0.22.2 notes list 26.0-26.2 as affected and the status of 26.3+ as unknown. |
| thread active to 2026-04-17 | Psychtoolbox, "Quick fix for Mac Tahoe timing issues" (https://psychtoolbox.discourse.group/t/quick-fix-for-mac-tahoe-timing-issues/5804) | User workaround on the macOS 26.5 beta: switching display resolution or refresh rate cleared the halved frame rate until reboot. On a MacBook Air M4 it occurred at the default 1710x1107 and cleared at 1920x1243. |
| 2026-03-31 | VDMX6 1.2.11 release notes (https://discourse.vidvox.net/t/vdmx6-1-2-11/8931) | A macOS 26 bug affects Metal views in windows that are not visible (stutter when overlapped). The vendor expects Apple's fix in macOS 27. |

Confidence:

- **High:** SceneKit is present and usable in the macOS 26.5 SDK with no compiler warnings (checked directly), and its status is soft deprecation without warnings (Apple sources).
- **Low to medium:** that there is **no SceneKit-specific macOS 26 regression**. Searches found none, but absence of evidence after a shallow search is weak.
- **Medium:** the two general macOS 26 Metal presentation issues are real (third-party, but specific and recent). It is **unknown** whether they reproduce on 26.3 (25D125) with this display mode. Only the on-screen spike can settle that.

## 5. Required mitigations (before C-15 can be accepted)

1. **Port the shared files with platform gates.** Make the platform shim the only file with `#if os(macOS)`. Keep `UIGraphicsImageRenderer`, `UIFont.lineHeight` and `UIBezierPath` on iOS so the verified iOS build is unchanged, then re-run the iOS on-device check. On macOS:
   - a flipped CTM **plus** `NSGraphicsContext(cgContext:, flipped: true)`;
   - `ceil(ascender - descender + leading)`;
   - `CGPath(roundedRect:)`;
   - `CGImage` returns;
   - `AVAudioSession` behind `#if os(iOS)`.
2. **Replace the 14 Float/CGFloat sites with `simd*` accessors** (listed in section 1). They are Float on both platforms, so iOS behavior is unchanged.
3. **Robots.swift:58:** convert to sRGB before `getRed`.
4. **Driver:** MTKView + `SCNRenderer.render(atTime:viewport:commandBuffer:passDescriptor:)` on the main thread, mirroring VRViewController.swift:156-200.
   - Set `colorPixelFormat = .bgra8Unorm_srgb` and keep `colorspace` sRGB.
   - Use one mono camera (`world.videoCam` or a dedicated camera with the right aspect).
   - Wrap each frame in `autoreleasepool`.
   - Prewarm `Sound.shared` (or mute or skip it on the Mac).
   - If SCNView is used instead, run all BaseScene and Link mutations on its render queue or under one lock, and set `isPlaying`, `rendersContinuously` and `antialiasingMode` explicitly.
5. **XcodeGen Mac target:**
   - explicit `deploymentTarget: macOS` at or below 26.3;
   - exclude the 3 iOS-only files, the bridging header and the Cardboard libraries;
   - `SWIFT_VERSION 5.0` and `SWIFT_STRICT_CONCURRENCY minimal`;
   - `ASSETCATALOG_COMPILER_APPICON_NAME: ""`;
   - resources copied flat (never `type: folder`).
6. **Spectator networking:**
   - a dedicated URL `ws://127.0.0.1:8787/?client=spectator`, with no `ares.json` candidates and no token;
   - no auto-replay, or replay that mirrors the headset (the server must then also send `force_replay` to spectators);
   - parse `vr_pose` and interpolate it to the display rate;
   - drive hover from `gaze`;
   - handle `vr_choice` to hide the cards;
   - never send `decide`.
7. **Presentation hygiene:**
   - `ProcessInfo.beginActivity([.userInitiated, .latencyCritical, .idleDisplaySleepDisabled])`;
   - keep the window visible and never covered (run the console on another display or as a small overlay);
   - decide whether to render under the notch or within the 3840x2412 safe area.
8. **On-screen spike on this Mac (Tier 1 check 4):**
   - run full screen for at least 10 minutes, logging `CAMetalDrawable.addPresentedHandler` and `presentedTime` intervals, not just GPU time;
   - pass condition: at least 99% of intervals within 16.7 ± 2 ms and no run of halved rate;
   - repeat after a reboot (the Tahoe workaround reportedly does not survive one), and on battery;
   - log thermal state alongside.

## 6. Fallback

- **A (preferred fallback): Mac Catalyst target.**
  - The 8 **unchanged** shared files typecheck for `arm64-apple-ios17.0-macabi` with **0 errors and 0 warnings**. UIKit, `UIGraphicsImageRenderer`, `UIFont.lineHeight`, `AVAudioSession` and iOS SceneKit Float vector types are all available there. Only typecheck was run, not link or run.
  - It needs its own target that excludes the Cardboard files and libraries (they have no Catalyst slice). The driver is a copy of VRViewController's mono path.
  - The same presentation risks (section 4) apply, and so do mitigations 4 and 6-8.
- **B: the existing recording pipeline.** `link.onRecord` and `/api/record/frame` already stream the headset's mono `videoCam` at 1280x720 JPEG (VRViewController.swift:202-233). The console can show it full screen.
  - Frames come from the real headset, so it is a true mirror.
  - Cost: lower frame rate (12 fps default, bounded by about 0.5 MB/s venue Wi-Fi or the hotspot), and extra GPU load on the phone.
- **C: last resort.** Wired QuickTime mirroring of the phone shows the distorted stereo frame, which is not a clean full-screen view, but it is zero-risk.

---

Scratch evidence (not committed), under `/private/tmp/claude-502/-Users-TAITA-Projects-ares/68cb0f5f-9dae-4466-a672-556fa0e064e5/scratchpad/`:

- `unchanged/` and `port/`: the sources;
- `scene/main.swift` and `scene/AresProbe.app`: the probe;
- `scene/run-3840.log` and `scene/run-pool.log`: run logs;
- `scene/out-*/`: screenshots;
- `probes/{display,color,text,scnthread,sample}.swift`: small probes.
