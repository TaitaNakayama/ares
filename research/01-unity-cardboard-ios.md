# 01 - Unity + Google Cardboard XR Plugin on iOS (iPhone 16 Pro, Xcode 26.6)

Researched 2026-10-23. All GitHub data pulled live via `gh api` on that date. Items marked (UNVERIFIED) come from my own knowledge, not a fetched source.

## TL;DR

- **Plugin is alive and maintained.** `googlevr/cardboard-xr-plugin` latest = **v1.36.0** (released 2026-10-15). Not archived. Cadence is about every 2-3 months (1.33 Mar, 1.34 May/Jun, 1.35 Aug, 1.36 Oct). The plugin repo has 1 open issue; Google asks for issues to be filed on `googlevr/cardboard` (110 open, mostly old).
- **Pick: Unity `6000.0.85f1`, changeset `ee7790f1426a`** (Unity 6.0 LTS, released 2026-10-15), with iOS Build Support, Apple Silicon editor.
  - Plugin `package.json` says `"unity": "6000.0"`, `"unityRelease": "58f2"`. README says "Unity 6000.0.58f2 or later".
  - 6000.0.68f1+ has Apple UIScene lifecycle support (Apple hard requirement for the SDK after iOS 26). Plugin 1.34+ also supports TN3187/UIScene.
  - A Google maintainer said (2026-07-30) compatibility "extends up to Unity 6000.0.62 and 6000.2.13". 85f1 is newer than that statement. This is the main residual version risk. Pin fallback is `6000.0.68f1` (first UIScene build) if 85f1 misbehaves.
- **Second choice: `6000.3.27f1` (changeset `672d562a42a7`, LTS, 2026-10-20).** Google said 6000.3 was unsupported (2026-07-30), then on 2026-10-01 said they had it working on 6000.3.25f1 (Vulkan/GLES3 on Android, with URP). An iOS user ran 6000.3.19f1 + plugin 1.34.0 + Metal on iPhone 17e. VR rendered, only the viewport size was wrong, which was a resolutions.csv gap fixed in 1.36.0.
- **Plugin version: v1.36.0.** It contains `iPhone17,1` (iPhone 16 Pro) at 460 ppi in `resolutions.csv`.
- **Install URL:** `https://github.com/googlevr/cardboard-xr-plugin.git#v1.36.0` (pin the tag, do not track main).
- **Hub:** brew cask `unity-hub` is now **3.22.4**, not 3.22.3 (formulae.brew.sh, checked 2026-10-23). The Hub CLI is deprecated since 3.18.0 but still documented.
- **Template:** use "Universal 3D" (URP). Google's maintainer reproduces with URP. Built-in RP was the failing case in issue #696 (Android, Unity 6.3).
- **Red flags:**
  1. Unity says nothing about Xcode 26.6 specifically. I found no Unity doc confirming 26.6, only general "Xcode 26 works with Unity 6" statements.
  2. Personal license cannot be activated headless. One GUI Hub sign-in is required.
  3. Default `Application.targetFrameRate = -1` means 30 fps on mobile. Set it explicitly.
  4. MSAA on in URP caused double render on iPhone 15 Pro Max (open issue #442). Keep MSAA off.
  5. Hub CLI `install` defaults to the x86_64 editor on macOS. Pass `-a arm64`.

## Evidence table

| Claim | Source URL | Source date | What it says |
|---|---|---|---|
| Plugin latest v1.36.0, not archived | https://github.com/googlevr/cardboard-xr-plugin (API `repos/googlevr/cardboard-xr-plugin`, `/releases`) | 2026-10-15 (release); queried 2026-10-23 | `archived:false`, pushed 2026-10-15, releases 1.36.0 (10-15), 1.35.0 (08-31), 1.34.0 (06-12), 1.33.0 (03-11), 1.32.0 (2025-12-19) |
| SDK latest v1.36.0 | https://github.com/googlevr/cardboard/releases/tag/v1.36.0 | 2026-10-15 | "Added resolution information for iPhone 17e, iPhone 18 Pro, 18 Pro Max". Tested iOS: iPhone 13 mini (iOS 26.4.1), iPhone 16 (iOS 26.5). Known issues: None |
| Recent iOS device coverage | releases 1.33-1.35 notes | 2026-03 to 2026-08 | Tested iPhone 14 (26.3), iPhone 17 Air (26.1), iPhone 15 Pro (26.5), iPhone 17 (26.5), iPhone 16 (26.3), iPhone XS Max (18.7) |
| Min Unity version | https://raw.githubusercontent.com/googlevr/cardboard-xr-plugin/v1.36.0/package.json and README | tag v1.36.0 (2026-10-07 commit) | `unity: 6000.0`, `unityRelease: 58f2`. Deps: inputsystem 1.7.0, xr.management 3.2.9, xr.legacyinputhelpers 2.1.4 |
| Docs say Unity 6000.0.23f1+ | https://developers.google.com/cardboard/develop/unity/quickstart | "Last updated 2025-10-09" | Stale versus README (58f2). Quickstart: Landscape Left/Right, camera usage string, min iOS "12.0" (stale, since 1.34 needs iOS 15), defer system gestures Top/Left/Right, enable Cardboard XR Plugin in XR Plug-in Management. Silent on Metal, input system, MSAA, URP, frame rate on iOS |
| iOS min raised to 15.0; camera-denied dialog; UIScene support | https://github.com/googlevr/cardboard/releases/tag/v1.34.0 | 2026-05-28 | Breaking: min iOS 15.0. Added TN3187 UIScene support. Fixed #527 camera permission handling |
| Unity compat statement | https://github.com/googlevr/cardboard/issues/696 (comment) | 2026-07-30 | "we do not support Unity 6000.3 or 6000.5. Our current compatibility extends up to Unity 6000.0.62 and 6000.2.13" |
| Google later got 6000.3 working | same issue | 2026-09-24 and 2026-10-01 | "tested using Vulkan and OpenGL3 with Unity 6000.3.25f1 and everything is working". The reporter's failure was Built-in RP; maintainer uses URP "Universal 3D" |
| 2021/2022 dropped | https://github.com/googlevr/cardboard/issues/506 | 2025-10-16 | "won't be able to offer support for the other versions starting from cardboard v1.31". Also #523: iPhone 16/17 double render/dim on old Unity, maintainer says use Unity 6 (2026-01-26) |
| iPhone 16/17 rendering works on Unity 6 | https://github.com/googlevr/cardboard/issues/523 | 2026-01-26 | Maintainer tested iPhone 16 and Air with sample: "works as intended. There's no dimming" |
| Black screen on iPhone 13/16 Pro Max (Unity 6000.2.5f1, plugin 1.30.0) | https://github.com/googlevr/cardboard/issues/502 | 2025-09-16 to 09-25 | Cause: `resolutions.csv` missing from bundle. "Fixed in v1.30.1" |
| iOS needs resolutions.csv entry per model | https://github.com/googlevr/cardboard/issues/717 | 2026-08-25 to 10-15 | iPhone 17e on Unity 6000.3.19f1/1.34.0 rendered tiny viewports. Fix = add model to `resolutions.csv`. "Fixed in v1.36.0" |
| 16 Pro is in the table | https://raw.githubusercontent.com/googlevr/cardboard/master/sdk/qrcode/ios/sdk.bundle/resolutions.csv | 2026-10-23 | `iPhone17.1,iPhone 16 Pro,460.0f` (written with a dot, matches model id iPhone17,1). Also 17.2, 17.3, 17.4, 17.5, 18.x, 19.x |
| iPhone 18 Pro window too small (open) | https://github.com/googlevr/cardboard/issues/723 | 2026-10-15 | Fixed on master/1.36.0. Irrelevant to the 16 Pro |
| MSAA double-render on iPhone 15 Pro Max, open | https://github.com/googlevr/cardboard/issues/442 | 2023-11 to 2024-11 | URP with MSAA 4x shows non-VR camera on top. Workaround: MSAA off in the URP asset before build (runtime disable does not work) |
| Mono render in Unity 2023.2 | https://github.com/googlevr/cardboard/issues/452 | 2024-02 | Unity bug, pre-Unity 6 |
| Camera not rotating unless XR initialised first | https://github.com/googlevr/cardboard/issues/506 (comment) | 2025-10-31 | TrackedPoseDriver only works if XR initialised before it. Fix = check "Initialize XR on Startup" |
| IPD/ghost dot on iPhone 17 (open, no repro) | https://github.com/googlevr/cardboard/issues/524 | 2026-02-17 to 02-26 | Single user report. Maintainer asked for a screenshot, no follow-up |
| `SaveDeviceParams` no effect on iPhone 16 (open, no repro) | https://github.com/googlevr/cardboard/issues/486 | 2024-12-12 | Unity 6000.0.28f1, plugin 1.27.0. Stale |
| Neck model bug (translation of head pose), open | https://github.com/googlevr/cardboard/issues/714 | 2026-08-17 | Affects the translation part of `getPose`. Rotation fine. Minor for our use |
| Latency/pose prediction/frame pacing request, open | https://github.com/googlevr/cardboard/issues/694 | 2026-07-18 | No fix. Expect stock Cardboard latency |
| iOS HelloCardboard Xcode build C++20 error | https://github.com/googlevr/cardboard/issues/720 | 2026-09-07 | Native sample only (`starts_with` with C++17). Not the Unity package, which ships a prebuilt `GfxPluginCardboard.a` |
| Plugin API uses new Input System Touchscreen | https://github.com/googlevr/cardboard-xr-plugin/blob/v1.36.0/Runtime/Api.cs | tag 2026-10-07 | `GetFirstTouchIfExists()` uses `Touchscreen.current.touches[0]`. Trigger = phase `Began` and not inside close/gear rects |
| Issue #501: plugin requires new Input System | https://github.com/googlevr/cardboard/issues/501 | 2025-09-15 | "we suggest to stick with the new input system" |
| UIScene requirement and Unity versions | https://discussions.unity.com/t/info-apple-update-your-editor-to-receive-uiscene-lifecycle-support/1709065 | 2026-02-16, updated to 2026-10-06 | Apple: in the release after iOS 26 apps built with the latest SDK must use UIScene or won't launch. Unity 6.0 LTS needs 6000.0.68f1+ (2026-02-18), 6.3 LTS needs 6000.3.8f1+ (2026-02-11). Existing shipped apps unaffected |
| Xcode 26 linker assertion (`dylibToOrdinal`) | https://discussions.unity.com/t/xcode-26-0-1-unity-6-0-ar-project-fails-with-linker-assertion-dylibtoordinal/1684912 and https://issuetracker.unity.com/issues/7602/ | 2025-09 to 2025-12 | Caused by the legacy `-ld64` flag added by the ARKit plug-in, not by Unity core. Workaround: strip `-ld64` in a post-build. Cardboard does not use ARKit, so likely not hit, but see risks |
| Xcode 26 + Unity 6 fine per Unity staff | https://discussions.unity.com/t/visionos-not-building-at-xcode-stage-clean-project-setup-recommendation/1703281 | 2025-12 | Staff: Xcode 26 works with Unity 6 builds, used internally |
| 6000.0.85f1 / 6000.3.27f1 changesets and dates | `https://services.api.unity.com/unity/editor/release/v1/releases?version=6000.0&architecture=ARM64&platform=MAC_OS` | 2026-10-23 | 6000.0.85f1 (2026-10-15) `ee7790f1426a`, 0.84f1 `78ab6fc243d5`, 0.83f1 `dacc44548933`. 6000.3.27f1 (2026-10-20) `672d562a42a7`, 3.26f1 `de8167e7440c`, 3.25f1 `e1dba0a9aba4` |
| 6000.0.85f1 release notes | https://storage.googleapis.com/live-platform-resources-prd/templates/assets/6000_0_85f1_c02551297b/6000_0_85f1_c02551297b.md | 2026-10-15 | No iOS/Xcode entries. XR Management package goes 4.5.4 to 4.6.1. Known issue UUM-156125 (hang after repeated LoadSceneAsync) only matters if you switch scenes a lot. Don't |
| Hub CLI deprecated, syntax | https://docs.unity.com/en-us/hub/hub-cli-reference | page checked 2026-10-23 (undated) | Deprecated from Hub 3.18.0. `install -v -c -m --cm -a`. macOS default arch is x86_64, use `-a arm64`. iOS module id `ios` |
| Unity CLI (new) | https://docs.unity.com/en-us/unity-cli/unity-cli-reference | 2026-10-23 (undated) | `unity install 6000.0.85f1 -c ee7790f1426a -m ios -a arm64`; `unity auth login` is browser-based; service-account env vars `UNITY_SERVICE_ACCOUNT_ID/SECRET` for headless auth (entitlement to Personal not stated) |
| Personal license cannot be activated by CLI | https://docs.unity3d.com/6000.3/Documentation/Manual/ManualActivationCmdWin.html | 2026-10-23 | "It doesn't support Unity Pro assigned seats, Unity Personal, or floating license subscriptions." "To activate a license for Unity Personal, log in to the Unity Hub." |
| Default mobile frame rate 30 fps; ProMotion opt-in | https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/application/targetframerate | 2026-10-23 | vSync 0 and targetFrameRate -1 renders at fixed 30 fps. ProMotion off by default, 60 Hz native. Use `Screen.currentResolution.refreshRateRatio` |
| HTTP to LAN needs setting | https://docs.unity3d.com/cn/6000.0/ScriptReference/InsecureHttpOption.html | 2026-10-23 | `PlayerSettings.insecureHttpOption = AlwaysAllowed` for `http://` (localhost exempt) |
| Sample startup pattern | https://github.com/googlevr/cardboard-xr-plugin/blob/v1.36.0/Samples~/hellocardboard-unity/Scripts/CardboardStartup.cs | tag 2026-10-07 | `Screen.sleepTimeout = NeverSleep; Screen.brightness = 1;` scan QR if `!HasDeviceParams()`, per-frame gear/close/hold handling, `HasNewDeviceParams()` then `ReloadDeviceParams()`, `UpdateScreenParams()` |

## Answers by question

### 1. Repo state
- Plugin and SDK both release in lockstep; v1.36.0 on 2026-10-14/15. Last 8 plugin commits are one per release (version bumps from a Google-internal sync). No community PRs landing, but Google staff (`victorveleze`, `jballoffet`, `Voldivh`) respond within days to weeks.
- Open issues matching your concerns: none that describe iPhone 16 Pro + Unity 6 + Metal being broken. Open ones that could touch you are #442 (MSAA), #524 (iPhone 17 IPD, unreproduced), #486 (SaveDeviceParams on iPhone 16, unreproduced, stale), #714 (neck model translation), #694 (latency). Nothing about Xcode 26 build failures in the Unity package. The Xcode failures (#720, #658, #587) concern the native iOS sample and were fixed.
- Closed iOS problems worth knowing: #502/#500 (black screen or crash from missing `resolutions.csv`, fixed 1.30.1), #523 (iPhone 16/17 double render, was a Unity 2021/2022 problem).
- Not found: no issue with "IL2CPP" failure specific to iOS, "URP" failure on iOS, or "QR scanning" failure on iOS in 2026.

### 2. Unity version and settings
- Recommended: **6000.0.85f1 (ee7790f1426a)**. Reasoning: plugin's declared target line is 6000.0; UIScene support in editor since .68; Google's QA matrix names 6000.0.x first.
- Why not 6000.3: Google explicitly said unsupported in July, partial confirmation in Sept/Oct, and it is Android-only evidence. It is a reasonable plan B if 6000.0.85f1 fails (one iOS user ran 6000.3.19f1 with 1.34.0 and only hit the resolution-table gap).
- Why not 6000.2.x: Supported stream ended (latest 6000.2.15f1, 2025-12-03).
- Settings (all from sources above unless marked):
  - Template: Universal 3D (URP).
  - Graphics API: Metal only (the only option on iOS in Unity 6; the Google docs are silent for iOS).
  - Default orientation: **Landscape Left** (Google docs say Left or Right). Also untick auto-rotation to portrait variants.
  - XR Plug-in Management: iOS tab, tick **Cardboard XR Plugin**. Tick **Initialize XR on Startup** (issue #506 comment: TrackedPoseDriver needs XR initialised first). The sample uses the `CardboardStartup` object; the plugin XR loader starts at launch.
  - Active Input Handling: **Input System Package (New)** (plugin code uses `Touchscreen.current`; maintainers recommend new). "Both" is probably fine (UNVERIFIED).
  - URP asset: **MSAA = Disabled** (issue #442), Depth Texture off unless needed, HDR off, Post-processing off, Render Scale 1.0. Also set the Quality level used on iOS to the same asset.
  - Camera Usage Description: required string (copy from Google docs).
  - Target minimum iOS: **15.0** (plugin 1.34 minimum); Unity 6 minimum is likely higher or equal anyway.
  - Defer system gestures: Top, Left, Right edges; hide home indicator (`PlayerSettings.iOS.hideHomeButton = true`).
  - Scripting backend IL2CPP, arm64.
  - Frame rate: add `Application.targetFrameRate = 60; QualitySettings.vSyncCount = 0;` in your startup script (default -1 gives 30 fps).
  - Add the "Interactive" layer and set Reticle Interaction Layer Mask on `CardboardReticlePointer` (Google quickstart).
  - Do not use the Built-in RP.

### 3. iOS pipeline (concrete)
Hub install (Hub CLI path; pass `-a arm64`). Note this is a one-time cost of about 5 GB editor pkg (6000.0.85f1 Mac arm64 installer = 4.98 GB, iOS module 371 MB).

```bash
brew install --cask unity-hub          # 3.22.4 now
HUB="/Applications/Unity Hub.app/Contents/MacOS/Unity Hub"
"$HUB" -- --headless install -v 6000.0.85f1 -c ee7790f1426a -m ios -a arm64
# add module later if needed:
"$HUB" -- --headless install-modules -v 6000.0.85f1 -m ios
"$HUB" -- --headless editors -i
# new CLI alternative (installed by Hub automatically):
# unity install 6000.0.85f1 -c ee7790f1426a -m ios -a arm64
```

License (cannot be headless for Personal): open Unity Hub once, sign in (browser flow), accept Personal license. After that `-batchmode` builds use the Hub's licensing client. Verify with a batchmode run and look for "Successfully activated" or licensing errors in the log. Sign in to Xcode (Settings > Accounts) with the paid Apple ID once so `-allowProvisioningUpdates` works.

Create project: Hub GUI > New project > Universal 3D (6000.0.85f1). Then in the editor, once: Package Manager > Add from git URL `https://github.com/googlevr/cardboard-xr-plugin.git#v1.36.0`; import the "Hello Cardboard" sample; enable XR loader (iOS tab); set the settings above. Commit the project so XR settings are serialized (`Assets/XR/`, `ProjectSettings/`).

Editor build script (`Assets/Editor/BuildIOS.cs`):

```csharp
using UnityEditor;
using UnityEditor.Build.Reporting;
public static class BuildIOS {
  public static void Build() {
    PlayerSettings.SetApplicationIdentifier(UnityEditor.Build.NamedBuildTarget.iOS, "com.taita.ares");
    PlayerSettings.iOS.appleEnableAutomaticSigning = true;
    PlayerSettings.iOS.appleDeveloperTeamID = "6M6DG3Y544";
    PlayerSettings.iOS.targetOSVersionString = "15.0";
    PlayerSettings.iOS.cameraUsageDescription =
      "Cardboard SDK requires camera permission to read the QR code (required to get the encoded device parameters).";
    PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
    PlayerSettings.insecureHttpOption = InsecureHttpOption.AlwaysAllowed; // only if http:// to a LAN server
    var opts = new BuildPlayerOptions {
      scenes = new[] { "Assets/Scenes/Main.unity" },
      locationPathName = "Build/ios",
      target = BuildTarget.iOS,
      options = BuildOptions.Development   // drop for final
    };
    var r = BuildPipeline.BuildPlayer(opts);
    if (r.summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
  }
}
```

(API names `appleEnableAutomaticSigning`, `appleDeveloperTeamID` confirmed in Unity docs; the rest are standard PlayerSettings, UNVERIFIED against 6000.0.85f1 in this session. `SetApplicationIdentifier(NamedBuildTarget,...)` is the Unity 6 form.)

Add a `[PostProcessBuild]` that writes `NSLocalNetworkUsageDescription` (and `NSBonjourServices` only if using Bonjour) with `PlistDocument` if the app talks to a LAN server. This is Apple behavior, not Unity-documented in the sources I fetched (UNVERIFIED), but the iOS local-network prompt is triggered by private-IP connections on iOS 14+.

Headless build:

```bash
UNITY="/Applications/Unity/Hub/Editor/6000.0.85f1/Unity.app/Contents/MacOS/Unity"
"$UNITY" -batchmode -nographics -quit -projectPath "$PWD" -buildTarget iOS \
  -executeMethod BuildIOS.Build -logFile Build/unity.log
```

(Do not use `-nographics` if shaders need compiling and it errors; remove the flag in that case.)

Xcode build and install:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Build/ios/Unity-iPhone.xcodeproj -scheme Unity-iPhone \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath Build/dd -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=6M6DG3Y544 CODE_SIGN_STYLE=Automatic build
DEV=B177F8D9-2156-5A6C-8882-05087D03426A    # Taita's iPhone 16 Pro (verified via devicectl list)
APP=$(ls -d Build/dd/Build/Products/Release-iphoneos/*.app)
xcrun devicectl device install app --device $DEV "$APP"
xcrun devicectl device process launch --device $DEV --terminate-existing --console <bundle-id>
```

`devicectl` subcommands and flags `--terminate-existing`, `--console` confirmed locally via `--help`. The phone must be unlocked for launch. Wildcard profile is fine with automatic signing; a unique bundle id like `com.taita.ares` matches `*`.

If the generated project fails to link with the `dylibToOrdinal` assertion, add a post-build step removing `-ld64` from `OTHER_LDFLAGS` on UnityFramework (documented workaround); unlikely for Cardboard since it does not use ARKit.

Info.plist keys: `NSCameraUsageDescription` (set via player setting above, required for QR scan). `NSLocalNetworkUsageDescription` only for LAN. Nothing else needed. Cardboard reads gyro through CoreMotion (no usage key required).

### 4. Cardboard input and QR flow
- V2 button: the capacitive button produces a screen touch. `Api.IsTriggerPressed` = first touch in phase `Began` and not inside the close or gear widget rect. Touch uses the new Input System `Touchscreen`. Only works while the XR loader is started (`XRLoader._isStarted`).
- `Api.IsCloseButtonPressed` / `IsGearButtonPressed` = `Began` inside `Widget.CloseButtonRect` / `GearButtonRect` (widgets drawn between eyes). Gear sample action = `Api.ScanDeviceParams()`; close = `Application.Quit()` in sample. Recenter = hold trigger 3 s (`IsTriggerHeldPressed`, `MinTriggerHeldPressedTime`).
- Since only a single tap and gaze are allowed, build on `IsTriggerPressed`. For gaze dwell, use your own timer on the reticle raycast (the sample only has `Physics.Raycast(transform.position, transform.forward, ...)` on a layer mask, and click via `IsTriggerPressed`).
- Gaze pattern: `CardboardReticlePointer` on the camera, raycast forward, `ReticleInteractionLayerMask`, calls `OnPointerEnter/Exit/Click`-style events on hit objects (via ExecuteEvents). Copy the sample `ObjectController` for hover/click logic.
- QR flow: `if (!Api.HasDeviceParams()) Api.ScanDeviceParams();` at start; each frame `if (Api.HasNewDeviceParams()) Api.ReloadDeviceParams();` and `Api.UpdateScreenParams();`. Params are persisted by the native SDK; `HasDeviceParams()` reads saved params, so scanning is once per install (reinstall may or may not wipe it, UNVERIFIED). Offline: `Api.SaveDeviceParams("https://google.com/cardboard/cfg?p=...")` stores a profile from a URI without the camera (useful 3am fallback; the V2 default URI is in the Api.cs doc comment). Issue #486 claims SaveDeviceParams had no effect on iPhone 16 in 2024 (unreproduced), so test it.
- First launch triggers the iOS camera permission prompt; if denied, v1.34+ shows a dialog with an "open Settings" button.

### 5. iPhone 16 Pro gotchas
- ProMotion: off by default in Unity (60 Hz). Leave off. Set `Application.targetFrameRate = 60`.
- Dynamic Island / safe area: plugin renders into `Screen.safeArea` (issue #235). In landscape this shrinks the render area slightly; Google says it's by design and patchable (replace `Screen.safeArea` with full rect) but that edits the package (copy to `Packages/` embedded). Keep stock unless viewport looks off. `resolutions.csv` has your device at 460 ppi.
- Auto-lock/dimming: sample sets `Screen.sleepTimeout = NeverSleep` and `Screen.brightness = 1`. Issue #511 (closed) says forced brightness stuck after exiting VR mode. Restore brightness if you leave VR.
- Thermal: no source found. Expect throttling after sustained load; keep MSAA off, simple shaders, 60 fps cap. Device in a plastic viewer is trapped heat (UNVERIFIED).
- Works on iOS 26: Google tested iPhone 16 (26.3, 26.5), iPhone 15 Pro (26.5), iPhone 13 mini (26.4.1). No iPhone 16 Pro tested explicitly. Issue #523 (iPhone 16/17 iOS 26) was resolved by Unity 6.

### 6. Fallbacks (if plugin is broken)
Ranked by expected time-to-working for a solo dev who is new to Unity:
1. **(a) Switch Unity version** (6000.0.68f1, then 6000.3.27f1; plugin v1.36.0 or v1.34.0): 1-2 h each including a rebuild cycle (Unity import ~10-15 min first time). Cheapest, try first.
2. **(d) Native iOS with Cardboard C SDK** (Metal/SceneKit): HelloCardboard iOS sample builds from Xcode directly (`googlevr/cardboard`, note #720: set C++ dialect to C++20 or use the fixed release). If the Unity wrapper is the problem but the SDK works, this is a reliable base. 4-8 h to get your scene content onto it; high if the app needs rich assets or networking code in Swift. Ties to Google's tested sample path (their release tests use HelloCardboard).
3. **(b) DIY stereo in Unity**: two cameras + CoreMotion/`Input.gyro` (or `AttitudeSensor` in Input System) head tracking + barrel distortion shader with V2 lens params. 6-10 h for acceptable result, easily 12+ for good comfort (distortion coefficients, per-eye viewport, IPD). Quality risk: latency and drift. No other dependencies.
4. **(c) Other XR plugins**: no practical alternative for iOS Cardboard in Unity; the old Google VR SDK for Unity is deprecated and not Unity 6 compatible. Not recommended. (UNVERIFIED survey, I did not research alternatives deeply.)

## Open issues / risks (summary)
- Version mismatch: Google's stated tested ceiling for 6000.0 was .62 (2026-07-30); we recommend .85.
- Unity 6000.0.85f1 bumps `com.unity.xr.management` to 4.6.1 (plugin pins min 3.2.9); possible but unreported incompatibility.
- No Unity statement on Xcode 26.6. Prior Xcode 26.x problems were ARKit-linked.
- MSAA bug (#442) is open; Dynamic Island safe-area shrink by design; no latency improvements (#694).
- UIScene: plugin 1.34+ handles it, but the interaction with Unity's UIScene glue in 6000.0.68+ is untested by me.
- Google docs lag the code (quickstart updated 2025-10-09 still says min iOS 12 and Unity 6000.0.23f1).
- Unity Personal: requires sign-in via Hub; revenue eligibility not checked.

## What would make this fail on an iPhone 16 Pro at a hackathon at 3am?
1. **Unity licence not activated** (Personal requires Hub GUI sign-in, expired token, offline venue Wi-Fi). Activate and do a test batchmode build well before 3am.
2. **Hub CLI installs x86_64 editor** (default arch) which then runs under Rosetta, builds slowly or fails. Use `-a arm64`.
3. **Signing**: Xcode not signed in, so `-allowProvisioningUpdates` fails; phone locked at `devicectl launch`; Developer Mode toggled off after iOS update; stale trust. Keep the Xcode GUI as a fallback.
4. **Black screen or tiny viewport** if `resolutions.csv` lacks the model or the build misses the bundle (old failure #502). With 1.36.0 `iPhone17.1` is present. Check Xcode console for "[CardboardApi]" and `sdk.bundle` in the .app.
5. **Camera permission denied** at first QR scan, so no profile and warped lens. Use `Api.SaveDeviceParams` with the V2 default URI as a baked-in fallback.
6. **Stereo double render or mono** if MSAA is enabled in URP or Initialize XR on Startup is off (#442, #506). Keep MSAA off.
7. **Head tracking dead** if XR initialised after the TrackedPoseDriver (#506 comment). Use the sample's setup.
8. **30 fps nausea** because `targetFrameRate` is -1 by default on mobile. Set to 60.
9. **Input**: no touch events if Active Input Handling is the old Input Manager only. Use New.
10. **Thermal throttling** in a plastic viewer plus brightness 1.0, frame drops at the end of the demo.
11. **Local-network prompt/ATS** blocks LAN HTTP calls (need `insecureHttpOption` and `NSLocalNetworkUsageDescription`; user must tap Allow once on the phone, which is hard to do inside the viewer).
12. **Xcode 26.6 linker/strip surprise** (e.g. `dylibToOrdinal` assertion) that costs an hour; the workaround is stripping `-ld64`, or fall back to 6000.0.68f1/6000.3.27f1.
13. **Disk and time**: 5 GB editor download plus first project import on conference Wi-Fi. Install Unity before the event if possible.
