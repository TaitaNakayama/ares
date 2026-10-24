# Verify-01: adversarial check of the Unity + Cardboard plan (iPhone 16 Pro, Xcode 26.6)

Checked 2026-10-23 (PDT). I used live sources only: GitHub API (`gh api`), the Unity release API, the Unity issue-tracker API, official docs, Apple's Xcode support page, Unity pkg metadata read over HTTP range requests, and read-only commands on this Mac. I installed nothing and changed no settings. A forum thread is cited only next to stronger evidence and is marked "(forum)".

## Machine state observed during the check (differs from the brief)

- `xcodebuild -version`: Xcode 26.6 (17F113). The only iOS SDK is 26.5. Apple's support page confirms Xcode 26.6 ships the iOS 26.5 SDK and can debug on iOS 15 and later, so the 26.6.1 phone is fine.
- Signing is ready. Keychain has 1 valid "Apple Development" identity. Xcode prefs list team 6M6DG3Y544 and account entries. The wildcard profile "iOS Team Provisioning Profile: *" (6M6DG3Y544.*) contains this phone's UDID (00008140-000A3D401E3B001C) and expires 2027-04-15. `xcodebuild -checkFirstLaunchStatus` returns 0.
- **Metal Toolchain component: "uninstalled"** (`xcodebuild -showComponent MetalToolchain`).
- `devicectl list devices`: the phone is "paired", Developer Mode enabled, iOS 26.6.1 (23G83), but **tunnelState "unavailable"**. It was not reachable over the network at check time.
- **Unity is already partly installed by another process.** Unity Hub 3.22.4 was installed at 19:25 and is running, not signed in, with its licensing client up. `/Applications/Unity/Hub/Editor/6000.0.85f1/Unity.app` (8.7 GB) appeared at 19:26 and `PlaybackEngines/` was still empty at 19:35. `~/Library/Unity/licenses/` is empty and `/Library/Application Support/Unity` does not exist. I did not touch any of this.

## Verdicts

| # | Claim (short) | Verdict |
|---|---|---|
| 1 | 6000.0.85f1 + plugin v1.36.0 + URP gives correct stereo, distortion and head tracking on the 16 Pro / iOS 26.6.1 | **LIKELY HOLDS** (not proven for this exact combination) |
| 2 | `resolutions.csv` v1.36.0 includes iPhone17,1, so the viewport is sized correctly | **HOLDS** (with a safe-area caveat) |
| 3 | Batchmode export, `xcodebuild -allowProvisioningUpdates`, `devicectl` install/launch over the network, no Xcode GUI | **LIKELY HOLDS** |
| 4 | Personal license needs a Hub GUI sign-in; then batchmode works, including with a pkg-extracted editor | **LIKELY HOLDS**, but two details are wrong |
| 5 | V2 button is a touch `Began`; `Api.IsTriggerPressed` detects it; reticle raycast gives gaze plus tap | **LIKELY HOLDS**, with a documented reliability gap |
| 6 | QR flow works on iOS 26; the profile persists; **without a scan a default Cardboard V2 profile is used** | **FALSE as stated.** The default is **Cardboard V1**. The scan and persistence parts LIKELY HOLD |
| 7 | The listed settings are all that is required; nothing hidden breaks the build on Xcode 26.6 | **DOUBTFUL** (the list is incomplete; `targetFrameRate` may be ignored) |

---

## Claim 1: stereo, distortion and head tracking on 16 Pro / iOS 26.6.1. LIKELY HOLDS

**Strongest evidence against**
- Google's own compatibility statement stops below 85f1. In googlevr/cardboard#696 (2026-07-30) the maintainer wrote "Our current compatibility extends up to Unity 6000.0.62 and 6000.2.13". No later statement covers 6000.0.85f1, and the v1.36.0 release notes name no Unity version.
- The iPhone 16 Pro is not in Google's tested lists. v1.34.0 (2026-05-28) tested iPhone 16 on iOS 26.3. v1.35.0 (2026-08-31) tested iPhone 15 Pro and iPhone 17 on iOS 26.5. v1.36.0 (2026-10-15) tested iPhone 13 mini on iOS 26.4.1 and iPhone 16 on iOS 26.5. Nothing was tested on iOS 26.6.x.
- googlevr/cardboard#523 (opened 2026-01-19, closed 2026-08-20): on iPhone 16/17 with iOS 26 the reporter saw double rendering. Upgrading to Unity 6000.0.65f1 removed that, but the image was then "significantly dimmer". The screenshots are 2622x1206, which is the 16 Pro's resolution. The maintainer could not reproduce the dimming with the sample on iPhone 16 and Air, and closed the issue without a root cause.
- googlevr/cardboard#442 is still open (2023-11-06, last update 2024-11-14). With MSAA on in URP, VR and non-VR views draw at the same time on an iPhone 15 Pro Max. The plan's MSAA-off setting addresses this, but it must be off in the URP asset the iOS quality level actually uses.
- Unity 6.0 LTS support is ending. unity.com/releases/unity-6-releases (checked 2026-10-23) says "Unity 6.0 LTS is supported through October 2026". 85f1 (2026-10-15) may be the last 6.0 patch, so a future Xcode or iOS break will not be fixed on this line for Personal users.
- Rendering uses `Screen.safeArea` by design (googlevr/cardboard#235, open, maintainer reply 2021-04-28, last comment 2025-11-25). The SDK builds the lens distortion from the **viewport** size (`cardboard_display_api.cc` at v1.36.0 calls `CardboardLensDistortion_create(..., viewport_width, viewport_height)`). My inference: in landscape the safe area loses the home-indicator strip (about 21 pt, about 3.5 mm at 460 ppi), so the lens centre sits a few mm above where the full-screen geometry would put it. This is a small comfort and alignment error, not a failure.
- A fresh Universal 3D camera has no head tracking. The sample scene's camera uses the Input System `TrackedPoseDriver` (guid c2fadf23…) bound to `<XRHMD>/centerEyePosition` and `<XRHMD>/centerEyeRotation` (HelloCardboard.unity at v1.36.0). Without that component the template camera will not track.

**Evidence for**
- Plugin `package.json` at v1.36.0: `"unity": "6000.0", "unityRelease": "58f2"`. README: "Unity 6000.0.58f2 or later".
- The 6000.0.85f1 release notes (2026-10-15) contain no iOS, Xcode, Metal or IL2CPP regressions. XR Management moves to 4.6.1. Its changelog (4.6.1 dated 2026-07-17; 4.6.0 dated 2026-03-26) only widens `XRLoaderHelper` methods from protected to public. The Cardboard `XRLoader` only calls them, so nothing breaks.
- Google's maintainer reproduces with the URP "Universal 3D" template (#696, 2026-10-01). Built-in RP was the failing case there.
- The prebuilt `Runtime/iOS/GfxPluginCardboard.a` (66.9 MB, not Git LFS, so no git-lfs needed) is arm64 only, with `minos 12.0` and `sdk 26.2` (`otool -l`). No simulator slice, so device builds only.
- Unity 6000.0 system requirements: iOS 13+, Xcode 15+, Metal. Page built 2026-10-22.

**Spike must check:** run the stock HelloCardboard scene first. Check two-eye render, distortion, no double image and no dimming, and compare brightness with a non-VR frame. Check head tracking on the camera that has `TrackedPoseDriver`. Check which URP asset the iOS quality level uses and that MSAA is off in it. Look for `[CardboardApi]` lines in the device console.

## Claim 2: `resolutions.csv` includes iPhone17,1. HOLDS

- `Runtime/iOS/sdk.bundle/resolutions.csv` at plugin tag v1.36.0 (commit 7fb2c0e, released 2026-10-15) has line 56: `iPhone17.1,iPhone 16 Pro,460.0f`. 460 ppi matches the 16 Pro panel.
- Matching works as claimed. `sdk/screen_params/ios/screen_params.mm` at v1.36.0 reads `uname().machine`, replaces `,` with `.`, and looks the result up in the CSV. On a miss it logs "Couldn't find screen params for model" and falls back to `kDefaultDpi = 326`.
- **Caveats:** the DPI is applied to the pixel size Unity passes in, which is the safe area. Anything that changes the render size breaks the physical scale: `Screen.SetResolution` (googlevr/cardboard#225, open), a non-native resolution scaling mode, and possibly iOS Display Zoom (my inference, unverified). Keep native resolution.
- **Spike:** confirm the device log has no "Couldn't find screen params" line, and that `sdk.bundle/resolutions.csv` is inside the built `.app`. Its absence was the cause of the black-screen bug fixed in 1.30.1 (#502).

## Claim 3: headless build, sign and install. LIKELY HOLDS

**Evidence for**
- Unity 6000.0 script reference pages exist for `PlayerSettings.iOS.appleEnableAutomaticSigning` ("Set this property to true for Xcode to attempt to automatically sign your app based on your appleDeveloperTeamID") and `appleDeveloperTeamID` (HTTP 200, checked 2026-10-23).
- `xcodebuild -help` (local Xcode 26.6): `-allowProvisioningUpdates` "Requires a developer account to have been added in Xcode's Accounts settings or an App Store Connect authentication key". An account is present.
- The device does not need registering: its UDID is already in the wildcard profile. Otherwise `-allowProvisioningDeviceRegistration` would also be needed.
- `devicectl` 518.33 is present, with `device install app` and `device process launch --terminate-existing --console`.
- Burst for iOS cross-compiles under Unity 2022.3+, and Xcode is only needed to build the generated project (Burst docs, building-projects). The CommandLineTools `xcode-select` setting only matters to `xcodebuild`, which takes `DEVELOPER_DIR`.
- Xcode 26 linker failures (`dylibToOrdinal`, `-ld64`) came from the ARKit plug-in, not Unity core (Unity staff, 2025-10-31; Unity issue UUM-111730 does not reproduce on 6000.0.54f1). The Cardboard post-processor (`Editor/BuildPostProcessor.cs` v1.36.0) adds no linker flags. It only deletes three `.meta` files and sets `ENABLE_BITCODE = NO`.

**Strongest evidence against / risks**
- The phone was **not reachable over the network** at check time (tunnelState "unavailable"). Network CoreDevice needs the same subnet and mDNS. Venue Wi-Fi with client isolation will break it. Keep a USB cable.
- `devicectl ... process launch` needs the phone unlocked. In a viewer it may auto-lock before launch.
- **Metal Toolchain is not installed.** If the exported Xcode project contains any `.metal` file, Xcode 26 fails with "missing Metal Toolchain" (Apple forum threads, 2025). I found no Unity report of this, so it is probably not triggered, but it is unverified.
- Hidden GUI steps that can block a headless run: a first-time keychain "codesign wants to access key" prompt, and the Xcode account token needing refresh (re-sign-in).
- Unity `-quit` can exit 0 even when a build fails unless the method calls `EditorApplication.Exit(1)` on failure. Check `BuildReport` and the log.

**Spike must check:** a full cold run of export, `xcodebuild` (pass `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE` on the command line so UnityFramework is covered), install and launch, from a plain Terminal and from the agent shell, with the phone on Wi-Fi only. Run `find <export> -name '*.metal'` and watch for a hung `codesign`.

## Claim 4: licensing. LIKELY HOLDS, two details wrong

**Evidence for**
- Unity 6000.0 manual, "Manage your license through the command line" (last updated about 20 days before 2026-10-23): "The following procedures don't apply to Unity Personal. To activate a license for Unity Personal, log in to the Unity Hub."
- The license is per user, not per install. ActivationFAQ (6000.6, checked 2026-10-23) puts a named-user license at `~/Library/Unity/licenses/UnityEntitlementLicense.xml`. Unity licensing-server requirements: Editor 2019.4+ includes the Unity Licensing Client. The 85f1 pkg contains `Unity.app/Contents/Frameworks/UnityLicensingClient.app` (from its PackageInfo). So an editor not installed by Hub can still license itself once the user is activated.
- Batchmode with Personal works outside sandboxes: GameCI activation docs (checked 2026-10-23), and a third-party GitHub issue, smokim38/rts-game#82 (2026-10-23), where batchmode exited 0 outside the sandbox.

**What is wrong or risky**
- "Must be Hub GUI" is no longer strictly true. The Unity CLI bundled with Hub 3.22.4 (`unity` 1.0.0-beta.13, local `--help`, 2026-10-23) has `unity license activate --personal --accept-eula`. Sign-in is `unity auth login`, which opens a browser. A browser sign-in is still required, but not the Hub window. This is a beta tool and conflicts with the manual. Untested.
- The manual pkg path is not a plain extraction. From the pkg metadata, read 2026-10-23 from the official URLs:
  - The editor pkg is `relocatable="false"`, `auth="root"`, install-location `/Applications` with payload `./Unity/Unity.app`, and its `preinstall` deletes `/Applications/Unity/{Documentation,PlaybackEngines,Unity.app}`.
  - The **iOS Support pkg** installs to `/Applications/Unity/PlaybackEngines`, and its `preinstall` **fails unless `/Applications/Unity/Unity.app` is exactly 6000.0.85f1**. So `installer -pkg` cannot target `Hub/Editor/6000.0.85f1/`. You must extract its Payload (root `iOSSupport/`) into `.../6000.0.85f1/PlaybackEngines/iOSSupport` yourself.
  - The editor `postinstall` also creates `/Library/Application Support/Unity` with world-writable permissions. That folder is absent now. Named-user licenses live in `~/Library`, so this probably does not matter, but it is untested.
- Unity CLI reference (last updated about 2026-10-20): "You can only add modules to Editors that the Hub or CLI installed." The Hub cannot add iOS support to a hand-extracted editor. Register it with `unity editors add <path>` and check with `unity editors verify 6000.0.85f1`.
- Sandbox risk: in rts-game#82 (third-party, Windows/Codex, 2026-10-23), Unity 6000.3.23f1 batchmode inside an agent sandbox failed with "Error 10 verifying Licensing Client signature", "com.unity.editor.headless" entitlement not found, and "No valid Unity Editor license found". The Hub's client listens on named pipe `Unity-LicenseClient-TAITA`. A sandboxed Claude Code shell may not reach it.

**Spike must check:** sign in, activate Personal, then run batchmode from both a normal Terminal and the agent's (sandboxed) shell. grep the log for `License`/`entitlement`. Run a second time with the Hub closed.

## Claim 5: button, trigger and gaze. LIKELY HOLDS, with a reliability gap

- **The code does what is claimed** (`Runtime/Api.cs` v1.36.0). `IsTriggerPressed` returns true only when `XRLoader._isStarted` is set, `Touchscreen.current.touches[0].phase == Began`, and the touch is not inside the close (top-left) or gear (top-right) rect. `CardboardReticlePointer.Update` runs `Physics.Raycast(transform.position, transform.forward, ...)`, sends `OnPointerEnter/Exit` messages, and sends `OnPointerClick` when `IsTriggerPressed` is true and the hit is on the interaction layer.
- **Strongest evidence against:**
  - Unity's Input System docs, `touch-polling.md` (InputSystem repo, develop branch, pushed 2026-10-12): "Don't use `Touchscreen` for polling. If you read out touch state from `Touchscreen` directly inside of the `Update` or `FixedUpdate` methods, your application misses changes in touch state." The plugin does exactly that.
  - `Touchscreen.cs` in the same repo: "We do *NOT* make a effort here to prevent us from losing short-lived touches." A tap that begins and ends within one update is invisible to `IsTriggerPressed`.
  - Open googlevr/cardboard#457 (2024-03-16, open): "[iOS] IsTriggerPressed does not work periodically". The maintainer could not reproduce it.
  - Unity ISXB-990 (last updated 2026-01-14): on iOS, touches near a screen edge start with "Ended" instead of "Began". Unity also marked ISXB-862 a duplicate. Google added "Defer system gestures on edges" to the quickstart because of edge-touch problems (#475, closed 2025-05-28).
- Gaze caveat: the raycast has no layer mask. Any collider blocks it, and UI needs colliders.
- **Spike must check:** 50 button presses while gazing at a target. Count hits and double fires, and log `touch.phase`. If the miss rate is not zero, add an `InputAction` on `<Touchscreen>/primaryTouch/press` (actions see every state change) or use `EnhancedTouch`, and keep the plugin's gear and close rects.

## Claim 6: QR flow and default profile. FALSE as stated

- **Default without a scan is Cardboard V1, not V2.** Evidence:
  - `sdk/unity/xr_unity_plugin/cardboard_display_api.cc` at v1.36.0: "Loads Cardboard V1 device parameters when no device parameters are available" → `CardboardQrCode_getCardboardV1DeviceParams`.
  - The scanner's Skip button also saves V1 (`qr_scan_view_controller.mm`: "If no parameter are saved yet, saves Cardboard V1 params by default").
  - The V1 bytes encode "Google, Inc." / "Cardboard v1" (`cardboard_v1.cc`).
  - To get a V2 profile without the camera, call `Api.SaveDeviceParams("https://google.com/cardboard/cfg?p=…")`, using the example in Api.cs ("Cardboard I/O 2015"), **then call `Api.ReloadDeviceParams()` yourself**. `saveDeviceParams` in `qr_code.mm` never increments the changed counter, so `HasNewDeviceParams()` stays false after it. This may explain the unresolved #486.
- **Persistence holds.** `device_params_helper.mm` stores the params in `NSUserDefaults` under `com.google.cardboard.sdk.DeviceParamsAndTime`. They survive relaunches and in-place reinstalls, but not app deletion or a bundle-id change.
- **Scan flow and its risks:**
  - The scan flow is in the code: camera permission request, the denied-permission dialog added in v1.34.0, AVFoundation QR, http rewritten to https.
  - A QR code holding a **short link** needs network: a HEAD request that follows redirects to `google.com/cardboard/cfg`.
  - Google's goo.gl notice (2024-07-18, updated 2025-08-01): links that "showed no activity in late 2024" stop working after 2025-08-25, and all others keep working. A third-party "V2" viewer with a dead goo.gl code will fail with "Invalid QR Code".
  - The scanner is presented through the deprecated `UIApplication.keyWindow`. Unity 6000.0.68f1+ uses the UIScene lifecycle (Unity staff thread, 2026-02-16, updated to 2026-10-06). Google claims TN3187 support since v1.34.0, but nothing has been tested on 85f1.
- **Spike must check:** decode the viewer's QR with the Camera app and test whether the URL resolves. Scan on first launch from `Start()`. Kill and relaunch the app and confirm there is no rescan. Test the `SaveDeviceParams` + `ReloadDeviceParams` fallback offline.

## Claim 7: required settings and hidden requirements. DOUBTFUL

- **Missing from the list (runtime-critical, from the Google quickstart, last updated 2025-10-09):**
  - Tick **Cardboard XR Plugin** under XR Plug-in Management, iOS tab.
  - **Camera Usage Description.**
  - **Defer system gestures on edges: Top, Left, Right.**
  - Also add a **TrackedPoseDriver** on the camera (see claim 1), and keep URP, not Built-in (#696).
- `Application.targetFrameRate = 60`. Unity's 6000.0 docs say "XR platforms ignore both" `vSyncCount` and `targetFrameRate`, and "the XR SDK controls the frame rate". The same page says mobile defaults to 30 fps when `targetFrameRate` is -1. A Google maintainer suggested `targetFrameRate` for Cardboard in #267 (2021), and a user said it did not work (Android). Whether it does anything under Cardboard on iOS is unknown.
- Minimum iOS 15.0 is correct (v1.34.0 breaking change; Xcode 26.6 supports deployment targets iOS 15–26.5). "Both" input handling works, but Google recommends New (#501).
- Build-breaker candidates on Xcode 26.6: only the uninstalled Metal Toolchain (see claim 3), which is unconfirmed. No other Xcode-26 failure applies to a Unity-core plus Cardboard project in what I found.
- **Spike must check:** measure the real frame rate on device with and without `targetFrameRate`, for example with an on-screen FPS counter or Xcode's FPS gauge.

---

## Sources (URL, date)

| Source | Date |
|---|---|
| github.com/googlevr/cardboard-xr-plugin: releases, tree and files at tag v1.36.0 (package.json, Api.cs, CardboardReticlePointer.cs, Widget.cs, XRLoader.cs, BuildPostProcessor.cs, resolutions.csv, sample scene) | v1.36.0 released 2026-10-15; queried 2026-10-23 |
| github.com/googlevr/cardboard at tag v1.36.0: screen_params.mm, qr_code.mm, device_params_helper.mm, nsurl_session_data_handler.mm, qr_scan_view_controller.mm, cardboard_v1.cc, cardboard_display_api.cc | 2026-10-15 |
| SDK release notes v1.34.0 / v1.35.0 / v1.36.0 (github.com/googlevr/cardboard/releases) | 2026-05-28 / 2026-08-31 / 2026-10-15 |
| Issues googlevr/cardboard #696, #523, #442, #235, #457, #486, #475, #717, #267 | dates given inline; queried 2026-10-23 |
| Unity release API: services.api.unity.com/unity/editor/release/v1/releases?version=6000.0.85f1 | 85f1 released 2026-10-15; queried 2026-10-23 |
| 6000.0.85f1 release notes (storage.googleapis.com/…/6000_0_85f1_c02551297b.md) | 2026-10-15 |
| unity.com/releases/unity-6-releases ("6.0 LTS supported through October 2026") | checked 2026-10-23 |
| unity.com/blog/unity-6-3-lts-is-now-available | 2025-12-04 |
| Unity pkg metadata (PackageInfo, pre/postinstall) from download.unity3d.com/download_unity/ee7790f1426a/… (editor arm64 pkg and iOS Support pkg) | read 2026-10-23 |
| docs.unity.com/en-us/engine/6000.0/…/managing-your-unity-license | updated about 2026-10-03 |
| docs.unity3d.com/Manual/ActivationFAQ.html (6000.6) | checked 2026-10-23 |
| docs.unity.com/en-us/licensing-server/requirements | checked 2026-10-23 |
| docs.unity.com/en-us/hub/hub-cli-reference (deprecated from 3.18.0; default arch x86_64) | updated about Aug 2026 |
| docs.unity.com/en-us/unity-cli/unity-cli-reference, plus local `unity` 1.0.0-beta.13 `--help` | about 2026-10-20 / 2026-10-23 |
| formulae.brew.sh/api/cask/unity-hub.json (3.22.4) | generated 2026-10-24 UTC |
| docs.unity3d.com/6000.0/Documentation/ScriptReference/Application-targetFrameRate.html | checked 2026-10-23 |
| docs.unity3d.com/6000.0/Documentation/Manual/system-requirements.html | built 2026-10-22 |
| docs.unity3d.com/Packages/com.unity.xr.management@4.6/changelog | 4.6.1 dated 2026-07-17 |
| docs.unity3d.com/Packages/com.unity.burst@1.8/manual/building-projects.html | checked 2026-10-23 |
| Input System repo: Documentation~/touch-polling.md and Runtime/Devices/Touchscreen.cs (Unity-Technologies/InputSystem, develop) | pushed 2026-10-12 |
| Unity issue tracker API: ISXB-990 (id 4937), ISXB-862 (id 9469); UUM-111730 (id 16795) | 2026-01-14; 2025-12-09 |
| developers.google.com/cardboard/develop/unity/quickstart | last updated 2025-10-09 |
| developers.googleblog.com/en/google-url-shortener-links-will-no-longer-be-available/ | 2024-07-18, updated 2025-08-01 |
| developer.apple.com/support/xcode/ (Xcode 26.6 → iOS 26.5 SDK; Xcode 27 needs macOS 26.6+) | checked 2026-10-23 |
| Unity Discussions: UIScene info thread (staff), 1709065 | 2026-02-16 to 2026-10-06 |
| Unity Discussions: dylibToOrdinal thread, 1684912 (forum, staff replies) | 2025-09-24 to 2025-12-08 |
| game.ci/docs/github/activation | checked 2026-10-23 |
| github.com/smokim38/rts-game/issues/82 (third party, Windows sandbox) | 2026-10-23 |

## One-pass spike checklist (in order)
1. Hub sign-in, then activate Personal. Run batchmode from Terminal and from the agent shell, and confirm the license (claim 4).
2. Make sure iOS Support sits at `6000.0.85f1/PlaybackEngines/iOSSupport` and that `unity editors verify` passes (claim 4).
3. Universal 3D project, plugin `#v1.36.0`, stock HelloCardboard scene, Cardboard loader on, camera usage string, edge-gesture deferral, MSAA off in the iOS URP asset (claims 1 and 7).
4. Export, run `find -name '*.metal'`, `xcodebuild`, then install and launch with `devicectl` over Wi-Fi and over USB (claim 3).
5. On device: check the log for no "Couldn't find screen params", check stereo, brightness and tracking, and measure FPS with and without `targetFrameRate` (claims 1, 2, 7).
6. 50 button presses: count misses and double fires (claim 5).
7. Test the QR URL, scan, relaunch, then the offline `SaveDeviceParams` + `ReloadDeviceParams` fallback (claim 6).
