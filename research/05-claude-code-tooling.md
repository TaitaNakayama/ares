# 05 - Claude Code tooling for Unity (research, as of 2026-10-23)

Method: GitHub pages/search API fetched 2026-10-23; Unity docs/blog; web search. Items marked **[unverified]** come from my background knowledge, not a source fetched today. Verify them with the 5-minute smoke test at the bottom before relying on them.

## TL;DR

**Chosen MCP server: CoplayDev/unity-mcp ("MCP for Unity")**. 15.4k stars, MIT, v10.3.0 released 2026-10-04 (monthly cadence: 10.0.2 07-13, 10.1.0 07-13, 10.1.2 08-02, 10.2.0 09-01, 10.3.0 10-04), repo pushed 2026-10-19, ~52 open issues, 50 tool entrypoints (scenes, GameObjects, scripts, assets, tests, profiling, builds), Unity 2021.3 to 6.x.

Install (one-time, once the Unity project exists):
```bash
brew install uv                       # server is Python 3.10+, run through uv/uvx
# Unity: Window > Package Manager > + > Add package from git URL:
#   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#v10.3.0     (pin the tag, not #main)
# Or add to unity/AresVR/Packages/manifest.json (no GUI needed):
#   "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#v10.3.0"
# Then in Unity: Window > MCP for Unity > (Transport: HTTP, default http://localhost:8080) > Start Server
#   and "Configure All Detected Clients" (writes the Claude Code entry), OR register manually:
claude mcp add --transport http UnityMCP http://localhost:8080/mcp
# Manual server launch if the button fails (documented on glama mirror of Server README):
uvx --from mcpforunityserver mcp-for-unity --transport http --http-url http://localhost:8080
```
The `claude mcp add` line is **my inference** from the documented JSON (`{"mcpServers":{"UnityMCP":{"url":"http://localhost:8080/mcp"}}}`); the README only documents the GUI auto-configure. Use `claude mcp add --scope project ...` to write `.mcp.json` into the repo.

**Headless build workflow** (editor CLOSED):
```bash
UNITY=/Applications/Unity/Hub/Editor/<6000.x.y>/Unity.app/Contents/MacOS/Unity
"$UNITY" -batchmode -nographics -quit -projectPath "$PWD/unity/AresVR" \
  -buildTarget iOS -executeMethod Ares.Editor.Builder.BuildIOS -logFile - 2>&1 | tee build/unity-build.log
# then xcodebuild the generated Xcode project and `xcrun devicectl device install app` (see Q3)
```
Rule: editor open -> use MCP; editor closed -> batchmode. Never both on the same project.

**Fallback if Coplay breaks:** CoderGamester/mcp-unity (smallest, simplest, Node-based, Unity 6+ only, 5 open issues) - or skip MCP entirely and drive everything via `-executeMethod` scripts + Editor.log (Q2/Q4). Do NOT pick Unity's official MCP: it needs a paid/trial Unity AI subscription on Personal (ambiguous, see below).

---

## Q1. Unity MCP servers compared

| | **CoplayDev/unity-mcp** (pick) | IvanMurzak/Unity-MCP | CoderGamester/mcp-unity | Unity official MCP (AI Assistant pkg) |
|---|---|---|---|---|
| URL | github.com/CoplayDev/unity-mcp | github.com/IvanMurzak/Unity-MCP | github.com/CoderGamester/mcp-unity | docs.unity3d.com/Packages/com.unity.ai.assistant@2.0/manual/unity-mcp-get-started.html |
| Stars | 15.4k | 4.5k | ~2.0k | n/a (closed source pkg) |
| Last push / release | pushed 2026-10-19; v10.3.0 2026-10-04 | pushed 2026-10-24 (very active); no GitHub releases listed, installer linked | pushed 2026-10-11; README says v1.5.0; no releases listed | announced 2026-05-11 (open beta) |
| Open issues | 52 | 46 | 5 | n/a |
| License | MIT | Apache-2.0 | MIT | proprietary |
| Unity | 2021.3 LTS to 6.x | not stated on page (Editor + Runtime) | Unity 6+ | Unity 6 (6000.0)+ |
| Install | UPM git URL (or OpenUPM `com.coplaydev.unity-mcp`) + Python 3.10+ server via `uv` (auto-launched from Unity window) | `.unitypackage` / OpenUPM `com.ivanmurzak.unity.mcp` / `npm i -g unity-mcp-cli`; requires `unity-mcp-cli login` (browser OAuth device flow); **project path must not contain spaces** | UPM git URL + Node 18+; server in package `Server~/build/index.js`; WebSocket port 8090 | `com.unity.ai.assistant` package; relay binary auto-installed at `~/.unity/relay/relay_mac_arm64.app/Contents/MacOS/relay_mac_arm64 --mcp` |
| Tools | 50 entrypoints in 10 groups: scenes, GameObjects, components, scripts (Roslyn validation), assets/prefabs/materials, console read, run_tests, profiling, builds, VFX/animation/UI optional groups, batch. Full catalog: coplaydev.github.io/unity-mcp/reference/tools (404'd on direct fetch today; names per README summary, not itemised by me) | 70+: assets, prefabs, materials, shaders, packages, scene/hierarchy/components, screenshots, console logs, editor state, reflection method calls, Roslyn script execute, test runner; extension pkgs (Terrain, ProBuilder, Cinemachine, InputSystem, etc.) | ~35: `execute_menu_item`, `recompile_scripts`, `run_tests`, `batch_execute`, `get_console_logs`, gameobject CRUD/transform, `update_component`, `create_prefab`, scene CRUD, material CRUD, `get/set_play_mode_status`. No build tool, no screenshot | `Unity_ManageScene`, `Unity_ManageGameObject`, `Unity_ReadConsole`, more (not itemised in docs); custom C# tools supported |
| Claude Code | Works; GUI "Configure All Detected Clients"; manual `claude mcp add --transport http UnityMCP http://localhost:8080/mcp` (inferred) | Documented: `npx unity-mcp-cli setup-skills claude-code ./Proj` or `claude mcp add ai-game-developer <path-to-Library/mcp-server/.../gamedev-mcp-server> port=<p> client-transport=stdio` | Works; Server Window button writes `~/.claude.json` or project `.mcp.json` | Works with Claude Code (named by Unity); JSON config with relay path above; first connection needs approval in Project Settings > AI > Unity MCP |
| Notable bugs / risks (open issues, Oct 2026) | #1299 closing one Unity instance halts shared HTTP server; #1265 macOS background editor only re-registers on focus; #1454 EditMode run_tests auto-fails at 15s if Editor unfocused; #1394 domain reload mid-test false failure (Windows); #1397 Claude Code shows "Not Configured" though connected; #1482 default tool list ~16.7k prompt tokens; #1411 agent blocked by "Reload scene" popup | not triaged in depth; login/OAuth dependency and space-free path are friction | too small to judge; fewer features | beta, "may change, be limited or discontinued". **Personal-tier access unclear**: one pricing page version lists 1 MCP connection on Personal but requires the $10/mo AI subscription (1,000 credits; 14-day trial); another lists MCP as free. Unity forum thread complains of paywall. |

Sources: github.com repo pages and GitHub search API (2026-10-23); Coplay README on `beta` (release list dated through 2026-10-04); Coplay issues page (updated 2026-10-23); Unity blog "Unity AI Open Beta: How to get started with MCP" (2026-05-11); Unity docs AI Assistant 2.0; Unity pricing page + forum thread "MCP Versus Built in Assistant"; glama.ai mirror of Coplay Server README (HTTP/uvx commands). Others seen but not evaluated: hatayama/unity-cli-loop (583 stars), AnkleBreaker-Studio/unity-mcp-server (526), youngwoocho02/unity-cli (316; a plain CLI, interesting for no-MCP flows), FunplayAI/funplay-unity-mcp (267).

**Why Coplay:** by far the largest community (15k stars => bugs get found and fixed), monthly releases, MIT, has a **build tool and test runner** and screenshots, supports Unity 6, no account/login, no paywall. Its weak spots (domain-reload races, unfocused-editor throttling on macOS) are manageable: keep Unity foregrounded or on a second Space, and prefer batchmode for tests/builds.

Mitigations for token cost (#1482): enable only needed tool groups (guides/tool-groups on its wiki) - core + scene + script + test + build; leave vfx/animation/ui off.

## Q2. Headless Unity from the CLI

Editor binary on macOS: `/Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/MacOS/Unity`. Unity 6.0 LTS standard support ends Oct 2026; **6.3 LTS** is the "latest LTS" (support to Dec 2027) per unity.com release pages. Cardboard XR Plugin v1.36.0 (2026-10-14) explicitly notes Unity 6 / 6.2 support and iOS 26.4/26.5 testing; 6.3 not explicitly stated - pin 6.3 LTS but test the Cardboard build early. [Release notes: github.com/googlevr/cardboard-xr-plugin/releases]

What works in batchmode (all **[unverified today, standard Unity behaviour]** unless noted):
- **Build:** `-batchmode -nographics -quit -projectPath P -buildTarget iOS -executeMethod Ares.Editor.Builder.BuildIOS -logFile -`. The static method calls `BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=..., locationPathName="Builds/iOS", target=BuildTarget.iOS, options=BuildOptions.None})` and calls `EditorApplication.Exit(report.summary.result==BuildResult.Succeeded?0:1)`. iOS output is an **Xcode project**; you still run `xcodebuild` (signing: set `PlayerSettings.iOS.appleDeveloperTeamID` + automatic signing from the script).
- **Tests:** `-runTests -testPlatform EditMode -testResults results.xml` (add `-batchmode`; **omit `-quit`** with `-runTests`). PlayMode works the same with `-testPlatform PlayMode`, slower. Exit code non-zero on failures.
- **Create scenes/prefabs/materials by script:** an Editor-only class under `Assets/Editor/` using `EditorSceneManager.NewScene`, `PrefabUtility.SaveAsPrefabAsset`, `AssetDatabase.CreateAsset`, then `EditorSceneManager.SaveScene`. Run via `-executeMethod`. This is the most deterministic way for Claude Code to build scenes (reviewable in git, no MCP flakiness). Tip: keep scene-building logic in `Assets/Editor/SceneBuilders/*.cs`, one idempotent method per scene.
- **Packages:** edit `Packages/manifest.json` directly (git URLs, scoped registries incl. OpenUPM); next editor/batchmode launch resolves them. Delete `Packages/packages-lock.json` entries only if resolution gets stuck. First launch after edit takes minutes; include `-quit` and watch for compile errors in the log.
- **Gotchas:**
  1. Batchmode refuses/hangs if the project is open in the editor ("Multiple Unity instances cannot open the same project" - lock file `Temp/UnityLockfile`). Close the editor first (`osascript -e 'quit app "Unity"'`), or work on a copy.
  2. Compile errors anywhere in `Assets/` abort `-executeMethod` ("Scripts have compiler errors"); script log goes to `-logFile`. Use `-logFile -` to stream to stdout or a path in the repo's `build/`.
  3. First import of a fresh project (Library/ absent) can take 5-20 min; keep Library/ between runs.
  4. `-nographics` is fine for builds/tests but breaks anything needing a GPU (lightmap bake, some screenshots). Omit it for those.
  5. **Licence:** batchmode needs an activated licence on the machine (next section).
  6. Always pass an explicit `-buildTarget iOS` once, so the first import is not done for macOS and then re-imported.

**Recommended mixed workflow**
1. Day-0 (manual, ~15 min): you create the empty project (Unity Hub, 6.3 LTS, URP template), sign in. Claude Code then edits `manifest.json` (Cardboard, Coplay, XR, URP).
2. Exploration/layout phase: editor open, Coplay MCP on; Claude creates GameObjects, tweaks, reads console, takes screenshots.
3. Anything repeatable (scenes, prefabs, materials, project settings, build) gets captured as an `Assets/Editor/*.cs` method, so it is reproducible by batchmode and you are not dependent on MCP.
4. Build/test phase: quit the editor, `scripts/unity-build.sh`, `scripts/unity-test.sh`; then `xcodebuild` + `devicectl`.
5. Never leave the editor open when a script spawns batchmode; make the script check `pgrep -f "Unity.app/Contents/MacOS/Unity"` and fail early.

## Q3. Extra tools

**Unity licence (Personal).** Unity 6.3 manual (docs.unity3d.com/Manual/ManualActivationHub.html and ManualActivationCmdMac.html): manual `.alf/.ulf` activation is **not supported for Personal**; Personal is activated by signing in to **Unity Hub** (a one-time GUI step; the licence then lives in `/Library/Application Support/Unity/` and is shared by batchmode launches on the same Mac). The `-serial -username -password` command-line route is Pro/Plus/Enterprise only. So: sign in via Hub once, then batchmode works headless **while the Hub licence stays valid** (it re-validates online periodically; if you stay signed out of Hub, batchmode may fail with "no valid licence"). Do this on Day 0.

**Blender / GDAL MCPs:** Not needed for a 38 h build. Terrain/DEM prep can be done in a Node/Python script (the repo's `/data` pipeline), outputting a heightmap PNG/RAW or glTF mesh that Unity imports. Use GDAL CLI (`brew install gdal`: `gdal_translate`, `gdalwarp`) directly via Bash instead of an MCP; Claude Code handles CLIs well. blender-mcp (not evaluated today) adds a second GUI app and failure surface; skip unless you must hand-fix a mesh, and then prefer `blender -b -P script.py`.

**iOS install/launch/logs (iOS 26 / Xcode 26):**
- `ios-deploy` is effectively dead for iOS 17+ physical devices (no debugserver path; React Native community issue proposes replacing it with devicectl). Use `xcrun devicectl`.
- Commands:
  ```bash
  xcrun devicectl list devices
  xcrun devicectl device install app --device <UDID-or-name> Builds/ios/build/Release-iphoneos/AresVR.app
  xcrun devicectl device process launch --device <id> --terminate-existing --console <bundle.id>   # --console streams stdout/stderr until app exits (added in Xcode 16, per Apple DTS forum reply)
  ```
  I found no iOS 26-specific change to devicectl; the `--console` stdout path has had flakiness reports (Apple forums thread 756393), so treat it as best effort. Apple's `devicectl` requires Xcode 15+ and iOS 17+.
- `idevicesyslog` (brew `libimobiledevice`) still works for many devices **[unverified on iOS 26]**; fallback is Console.app / `log stream` for the device. Unity `Debug.Log` output on device reaches the system log under the app's process; to make logs trivially greppable, also POST important events to the Node server (the repo already has one). That is more reliable than any CLI log path at 3am.
- Device must be paired, trusted, in Developer Mode, and (for wireless) on the same network; Xcode must have registered the device once.
- Cardboard on iOS: plugin v1.34.0+ needs iOS 15+; camera permission string required (`NSCameraUsageDescription`) for QR viewer-profile scan - skip by hard-coding a viewer profile or you will hit a dialog.

## Q4. Repo structure for Claude Code

```
ares/
  CLAUDE.md                  # root: map of repo, the 6 commands you run most, rules
  .mcp.json                  # project-scoped MCP (Coplay), checked in
  unity/AresVR/              # Unity project (path has no spaces)
    CLAUDE.md                # Unity-specific: asmdef layout, "no logic in MonoBehaviours", batchmode commands, how to read Editor.log
    Assets/{Scripts,Editor,Scenes,Prefabs,Materials,Terrain}
    Packages/manifest.json   # committed (and packages-lock.json)
    ProjectSettings/         # committed
  engine/                    # world-agnostic TS core (pure functions, vitest)
  worlds/mars/               # world definition/data (JSON/TS)
  server/                    # Node backend
  console/                   # React laptop console
  eval/                      # evals
  data/                      # raw+derived data; large files git-ignored, fetched by script
  scripts/                   # unity-build.sh, unity-test.sh, ios-install.sh, unity-log.sh, fetch-data.sh
  research/
```
Per-directory CLAUDE.md files keep context small (Claude loads nested ones on demand). Put shared TS types in `engine/` and generate C# DTOs (or hand-mirror a tiny protocol file) so Unity and server agree; keep the protocol in one `protocol/` dir with a JSON schema if time allows.

**.gitignore (Unity part):**
```
unity/AresVR/[Ll]ibrary/
unity/AresVR/[Tt]emp/
unity/AresVR/[Oo]bj/
unity/AresVR/[Bb]uild/
unity/AresVR/[Bb]uilds/
unity/AresVR/[Ll]ogs/
unity/AresVR/[Uu]ser[Ss]ettings/
unity/AresVR/MemoryCaptures/
unity/AresVR/*.csproj
unity/AresVR/*.sln
unity/AresVR/.vs/ 
*.pidb.meta
*.pdb.meta
.DS_Store
node_modules/
data/raw/
data/cache/
```
**Commit `.meta` files** (never ignore them) and `ProjectSettings/`, `Packages/manifest.json`, `packages-lock.json`. Set `Edit > Project Settings > Editor > Asset Serialization = Force Text` and `Version Control = Visible Meta Files` (default in Unity 6; verify in ProjectSettings/EditorSettings.asset) so scenes/prefabs are diffable YAML. Add `.gitattributes` `*.unity merge=unityyamlmerge` only if you collaborate; solo, skip.

**Large binaries:** For a 38 h solo project, keep terrain source rasters **out of git** (git-ignored `data/raw`, fetched/generated by `scripts/fetch-data.sh`) and commit only the small derived assets Unity needs (<~50 MB total; heightmaps at moderate res). Git LFS adds setup + quota + a failure mode on push; use it only if you must commit >100 MB of binaries, with `git lfs track "*.png" "*.exr" "*.tif" "*.fbx"` limited to `unity/AresVR/Assets/Terrain/**` **[unverified: LFS free quota on GitHub is 1 GB storage/1 GB bandwidth per month]**.

**Keeping compile errors visible to Claude:**
- Editor log: `~/Library/Logs/Unity/Editor.log` (current session; `Editor-prev.log` is the previous one). Batchmode: wherever `-logFile` points; prefer `-logFile build/unity.log`.
- `scripts/unity-log.sh`: `grep -E "error CS[0-9]+|Exception|Build succeeded|Build failed" ~/Library/Logs/Unity/Editor.log | tail -50`. Claude can run this after each edit.
- Via MCP: Coplay's read-console tool (watch #1434: transport log lines pollute results) and script validation (Roslyn) before writing C#.
- Best check with editor closed: a cheap batchmode compile: `Unity -batchmode -nographics -quit -projectPath ... -logFile - ` (no executeMethod) exits non-zero on compile errors. Wrap as `scripts/unity-compile-check.sh`.
- Add `-warnaserror`-style discipline: tell Claude in unity/CLAUDE.md to always run the compile check after editing `.cs` files, and to keep logic in asmdef-separated, test-covered classes.

## What would make this fail at 3am?

1. **Editor open + batchmode launched** -> build hangs or exits ("project already open"). Mitigate: wrapper scripts that `pgrep` first and refuse.
2. **Personal licence lapsed / Hub signed out** -> batchmode prints "no valid licence" and does nothing; you cannot fix it headlessly (manual activation is unsupported for Personal). Sign in to Hub before sleeping; don't update Hub overnight.
3. **Coplay MCP drops after domain reload / editor unfocused on macOS** (#1265, #1454, #1394). Claude's tool calls time out. Mitigate: keep editor frontmost (disable display sleep: `caffeinate -d`), reconnect with `/mcp`, and have batchmode scripts as the fallback path.
4. **Coplay Python server (uv) not found / port 8080 clash** with your own Node server. Run the TS server on a different port (e.g. 3000/8787); verify `uv --version` in the same PATH Unity sees (Unity launched from Hub does not inherit zsh PATH - use the full path or set it in the MCP window).
5. **Modal popups** in the editor ("Reload scene", "Import TMP essentials", API updater) block the agent (#1411). Mitigate: accept dialogs once manually; avoid external modifications of open scenes; save scenes before external edits.
6. **Compile error in a script blocks every `-executeMethod`** and MCP tools alike; Claude must run the compile check after each C# change.
7. **Unity 6.3 vs Cardboard plugin**: plugin explicitly lists Unity 6 / 6.2; 6.3 is untested by me. Mitigate: build a trivial Cardboard scene to a device in the first 3 hours; fall back to 6.2 or 6.0 LTS if broken.
8. **iOS signing**: provisioning/Developer Mode/trust/pairing errors only appear at install; xcodebuild without a configured team ID fails. Do one manual Xcode build to a device early and note the team ID.
9. **devicectl `--console` unreliable**; no usable debugserver. Send logs over HTTP to your server as the primary channel.
10. **Library/ deletion or first-import time** (5-20 min) mid-session; never `git clean -fdx` the Unity dir. Keep Library/ on disk.
11. **Token cost of Coplay tool list** (~16.7k tokens, #1482) eats context; enable minimal tool groups.
12. **Pricing ambiguity on Unity official MCP** - avoid; if you try it, expect a paywall surprise.
13. **Large terrain files** accidentally committed (no LFS) -> push fails/slow; ignore `data/raw` from the start.
14. **Version drift**: do not track `#main`; pin Coplay to `#v10.3.0` and Cardboard to a tag (e.g. `#v1.36.0`) in manifest.json. Coplay README says to branch from `beta`, so `main` may lag or move abruptly.

### 5-minute smoke test (do first)
1. Hub sign-in; create project; add Coplay + Cardboard in manifest.json. 2. Open editor; confirm `claude mcp list` shows UnityMCP connected; ask Claude to create a cube and read the console. 3. Quit editor; run the batchmode compile check and a stub `BuildIOS` to confirm exit codes and logs. 4. `xcrun devicectl list devices` shows the iPhone.
