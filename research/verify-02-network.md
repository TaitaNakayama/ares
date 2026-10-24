# Verify-02: Phone to Mac network path (adversarial)

Checked 2026-10-23 against live sources (GitHub API, Apple DocC JSON, Unity docs/release API, npm, nodejs.org).
Setup under test: iPhone 16 Pro, iOS 26.6.1; Unity 6000.0.85f1 (LTS, released 2026-10-15), IL2CPP arm64, Xcode 26.6; Node v26.10.0 (2026-09-21) + `ws` 8.22.0 (2026-09-26) on a MacBook Air M3 running macOS 26.3, port 8787; React console in Chrome on the same Mac.

## Verdicts at a glance

| # | Claim (short) | Verdict |
|---|---|---|
| 1 | NativeWebSocket 2.0.7 works on Unity 6 IL2CPP iOS over `ws://LAN:8787`; ClientWebSocket is a fallback | **LIKELY HOLDS** for the main path. The fallback is **misleading** because it is the same code. |
| 2 | ATS key (or `insecureHttpOption`) plus `NSLocalNetworkUsageDescription` make cleartext work; prompt on first connect; works after Allow; no multicast entitlement | **DOUBTFUL**. The ATS reasoning is wrong for this stack (harmless), and "works after Allow" is false without a retry. The entitlement part HOLDS. |
| 3 | Phone is the Personal Hotspot, Mac joins it, the app on that phone connects to 172.20.10.x | **LIKELY HOLDS**, but Apple DTS says it is unsupported. There are reports of an iOS 26.4 hotspot regression, so a spike is mandatory. |
| 4 | Venue Wi-Fi without isolation lets the devices connect directly; with isolation there is no workaround except another network | **FALSE** as a whole. The first half mostly holds; the "no workaround" half is false. |
| 5 | Replay a bundled pre-recorded seeded run, one branch per decision option, when the backend is unreachable | **LIKELY HOLDS** if the branches rejoin and failure detection is designed correctly. |
| 6 | `<name>.local` resolution from Unity on iOS works with the same permission and no `NSBonjourServices` | **DOUBTFUL**. The permission part matches Apple docs. The venue-network part is where it breaks. |

---

## Claim 1: NativeWebSocket 2.0.7 on Unity 6 IL2CPP iOS (fallback: ClientWebSocket)

**Verdict: LIKELY HOLDS (main path). The fallback is not independent.**

What holds:
- 2.0.7 exists. It was published 2026-08-07 and the repo is active (2.0.0 to 2.0.7 shipped between March and August 2026, not archived). LICENSE is Apache-2.0.
- On every non-WebGL target, NativeWebSocket is a thin wrapper over `System.Net.WebSockets.ClientWebSocket` (README: "uses built-in `System.Net.WebSockets`").
- Unity's class library builds ClientWebSocket from corefx's fully managed `WebSocketHandle.Managed.cs`. That code calls `Dns.GetHostAddressesAsync`, then `new Socket(...)` and `ConnectAsync` per address, then `NetworkStream`, and adds `SslStream` only for `wss`. On iOS that means BSD sockets through IL2CPP, with no URLSession and no reflection, so stripping is not a known problem.
- The Unity 6000.0.85f1 release notes list no known issues involving WebSocket, sockets or System.Net.

Strongest evidence against (all real, none fatal):
1. **The "fallback" is the same stack.** If ClientWebSocket fails on this device or network, NativeWebSocket fails the same way. A genuinely independent fallback would be one of these:
   - a native plugin on `NWConnection`. It gets the Local Network "waiting" state for free (see claim 2).
   - HTTP polling through `UnityWebRequest`. On iOS this goes through NSURLSession, so ATS and Unity's `insecureHttpOption` then do apply.
2. **`await ws.Connect()` does not return until the socket closes.** In `src/NativeWebSocket/WebSocket.cs`@2.0.7, `Connect()` awaits `ConnectAsync`, raises `OnOpen`, then `await Receive()`. Any code placed after `await Connect()` runs only after disconnect. This was also noted in issue #49.
3. **There is no connect timeout.** The cancellation token fires only if you call `CancelConnection()`. If SYNs are silently dropped (client isolation, firewall), the connect waits for the XNU connect timer: `TCPTV_KEEP_INIT = 75*TCP_RETRANSHZ`, about 75 s. Unity's managed handle also tries the resolved addresses one after another, with no Happy Eyeballs.
4. **The install path is a trap.** Unity needs the generated `upm-2` branch. Release tags and OpenUPM lack the asmdef (open issue #107, 2026-05-11). Issue #101 reports the same assembly-reference failure on Unity 6 (comments run 2025-11 to 2026-05). `upm-2` is a moving branch, so pin a commit or use the 2.0.7 `.unitypackage` (release asset, 9,975 bytes).
5. **Open stability reports exist**, but none is a confirmed 2.x iOS bug:
   - #49 (2021): IL2CPP crash on resume after about 10 minutes in the background, on 1.x.
   - #89 (2023): freeze when the uplink dies but Wi-Fi stays up, on 1.x. 2.x rewrote the send path and no longer uses `Task.Wait`.
   - #102 (2025-05, Unity 6000.0.35f1): freeze after about 180 minutes of receive-only traffic.
   - PR #105 (2026-01, open): send-queue deadlocks during disconnects.
6. **Minor:** `integrations/Unity/package.json`@2.0.7 says `"license": "MIT"` while LICENSE says Apache-2.0. GitHub reports NOASSERTION. Credit it as Apache-2.0, which is what the LICENSE file says.

Sources:
- https://github.com/endel/NativeWebSocket (releases 2.0.7 2026-08-07, 2.0.5 2026-08-06, 2.0.0 2026-03-11; CHANGELOG 2.0.7 dated 2026-08-06)
- https://github.com/endel/NativeWebSocket/blob/2.0.7/src/NativeWebSocket/WebSocket.cs (Connect/Receive, fetched 2026-10-23)
- Issues: https://github.com/endel/NativeWebSocket/issues/107 (2026-05-11), /101 (2025-03-24, comments to 2026-05-07), /102 (2025-05-21), /105 (2026-01-25), /89 (2023-09-20), /49 (2021-07-20)
- https://github.com/Unity-Technologies/mono/blob/unity-main/mcs/class/System/common.sources and `external/corefx-bugfix/src/System.Net.WebSockets.Client/src/System/Net/WebSockets/WebSocketHandle.Managed.cs` (unity-main, repo pushed 2026-10-23)
- Unity 6000.0.85f1 release notes (released 2026-10-15): https://storage.googleapis.com/live-platform-resources-prd/templates/assets/6000_0_85f1_c02551297b/6000_0_85f1_c02551297b.md
- XNU `bsd/netinet/tcp_timer.h` (`TCPTV_KEEP_INIT` 75 s): https://github.com/apple-oss-distributions/xnu (tag xnu-12377.x, latest commit 2025-10-16)

Spike 1A (Unity build, about 45 min):
1. Install with `https://github.com/endel/NativeWebSocket.git#c612a4fef60f2ae57614b73202d2d261ba56aa3e` (`upm-2` at 2.0.7) or the 2.0.7 `.unitypackage`.
2. Use IL2CPP, arm64, Managed Stripping Level **High** (worst case), and a **non-Development** build. Development builds' player connection can fire the Local Network alert by itself at launch.
3. Add this script. It enforces its own timeout and retries:
```csharp
using System.Threading.Tasks; using NativeWebSocket; using UnityEngine;
public class NetSpike : MonoBehaviour {
  public string url = "ws://172.20.10.13:8787"; WebSocket ws;
  async void Start() {
    Screen.sleepTimeout = SleepTimeout.NeverSleep;
    for (int i = 1; i <= 8; i++) { int a = i;
      ws = new WebSocket(url); var opened = new TaskCompletionSource<bool>();
      ws.OnOpen  += () => { Debug.Log($"OPEN a={a} t={Time.realtimeSinceStartup:F2}"); opened.TrySetResult(true); };
      ws.OnError += e  => { Debug.Log($"ERR a={a} {e}"); opened.TrySetResult(false); };
      ws.OnClose += c  => { Debug.Log($"CLOSE {c}"); opened.TrySetResult(false); };
      ws.OnMessage += b => Debug.Log("MSG " + System.Text.Encoding.UTF8.GetString(b));
      _ = ws.Connect();                                   // resolves only on close
      if (await Task.WhenAny(opened.Task, Task.Delay(3000)) == opened.Task && opened.Task.Result) {
        for (int k = 0; k < 100; k++) await ws.SendText($"ping {k} {Time.realtimeSinceStartup}"); return; }
      ws.CancelConnection(); await Task.Delay(1000 * a);  // own timeout + backoff
    }
    Debug.Log("GIVE UP -> replay");
  }
}
```
4. Run this server on the Mac:
```js
import { WebSocketServer } from 'ws';
const wss = new WebSocketServer({ port: 8787 });            // no host => all interfaces
wss.on('connection', (ws, req) => { console.log('conn', req.socket.remoteAddress);
  ws.on('message', m => ws.send(`echo:${m}`));
  const t = setInterval(() => ws.send(JSON.stringify({ hb: Date.now() })), 5000);
  ws.on('close', () => clearInterval(t)); });
```
5. Pass criteria:
   - `OPEN` appears.
   - 100 echoes come back.
   - Heartbeats keep arriving for 30 minutes with the screen on.
   - Locking the phone for 2 minutes and unlocking does not crash the app. A reconnect is expected.

---

## Claim 2: ATS, the Local Network prompt, and the multicast entitlement

**Verdict: DOUBTFUL.** Taken one part at a time:

- **ATS: irrelevant to this stack (the claim's mechanism is wrong).** Apple: ATS "requires that all HTTP connections made with the URL Loading System ... use HTTPS", and "ATS doesn't apply to calls your app makes to lower-level networking interfaces like the Network framework or CFNetwork". Unity's ClientWebSocket is managed code over BSD sockets (claim 1), so `NSAllowsLocalNetworking` neither helps nor hurts `ws://` here. Setting it is harmless. Apple's page says it covers "unqualified domains, `.local` domains, and IP addresses", and that since iOS 17 ATS no longer allows raw IP addresses by default. That matters only if you add `UnityWebRequest` or NSURLSession calls to the Mac.
- **`PlayerSettings.insecureHttpOption` is not equivalent to the ATS key.** Unity documents it as "Options for allowing plain text HTTP connections for **UnityWebRequest**". It "affects only URLs that use the `http` scheme", and only `localhost`/`127.0.0.1` are exempt. It does nothing for ClientWebSocket. Set it to `AlwaysAllowed` only if a UnityWebRequest HTTP fallback is added.
- **`NSLocalNetworkUsageDescription`: required, holds.** Outgoing TCP to a local-network address needs Local Network access. The check lives "deep in the networking stack ... BSD Sockets ... and any APIs implemented on top". Unity 6.0's iOS Player Settings have no field for this key, so add it in a `PostProcessBuild` step with `PlistDocument`.
- **"Prompt on first connection, then it works once the user taps Allow": FALSE as stated.** TN3179: "If the system presents a local network alert in response to one of your local network operations, it **may deny the operation immediately, before the user has responded** ... If you can't use one of these preferred APIs [Network framework / URLSession waitsForConnectivity], add appropriate retry logic." BSD sockets do not wait. NativeWebSocket raises `OnError` then `OnClose(Abnormal)` and never retries. On a fresh install, the first connection will probably fail. If the code falls back to replay on the first failure (claim 5), the first demo launch goes straight to replay. Further caveats from TN3179:
  - If the app is in the background while the state is undetermined, the operation is denied without an alert.
  - Simulators do not implement this privacy check at all.
  - Resetting the decision requires deleting the app (or Reset Location & Privacy).
  - If someone taps "Don't Allow" during testing, every connection fails silently until the app's switch under Settings > Privacy & Security > Local Network is turned back on.
- **No multicast entitlement: HOLDS.** TN3179 and the entitlement page say it is needed to "send or receive IP multicast or broadcast" and for arbitrary Bonjour types. Unicast TCP does not need it. Keep it that way: no UDP broadcast discovery, which would also need an Apple approval request.

Sources:
- TN3179 Understanding local network privacy, revised 2026-10-06 (prior revisions 2026-02-17, 2025-07-18): https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- NSAllowsLocalNetworking (undated, fetched 2026-10-23): https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
- NSAppTransportSecurity: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity ; Preventing Insecure Network Connections: https://developer.apple.com/documentation/security/preventing-insecure-network-connections (both fetched 2026-10-23)
- NSLocalNetworkUsageDescription / NSBonjourServices / multicast entitlement: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription , .../nsbonjourservices , https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast (fetched 2026-10-23)
- Unity InsecureHttpOption (UnityWebRequest only): https://docs.unity.com/en-us/engine/6000.7/script-reference/unityeditor/insecurehttpoption (fetched 2026-10-23); 6000.0 page https://docs.unity3d.com/6000.0/Documentation/ScriptReference/PlayerSettings-insecureHttpOption.html (built 2026-10-22)
- Unity 6.0 iOS Player settings (no local-network field): https://docs.unity3d.com/6000.0/Documentation/Manual/class-PlayerSettingsiOS.html (built 2026-10-22)
- iOS & iPadOS 26 to 26.6 release notes show no Local Network privacy changes: https://developer.apple.com/documentation/ios-ipados-release-notes (fetched 2026-10-23)

Spike 2 (15 min, uses the Spike 1A build):
1. Delete the app. Install from Xcode and launch.
2. Write down whether attempt 1 logs `ERR` while the alert is up, and the exact error string. Tap Allow and confirm a later attempt logs `OPEN`.
3. Turn the app's Local Network switch off in Settings. Confirm the connection fails and the app shows "Local Network is off".
4. Turn it back on and confirm a reconnect.
5. Delete and reinstall, tap Don't Allow, and confirm the app shows the Settings hint instead of silently replaying.
6. Run `plutil -p <xcodeproj>/Info.plist | grep -E 'NSLocalNetwork|NSAppTransport'`. Optionally, remove the ATS keys and confirm that `ws://` still works, which proves ATS is irrelevant here.

Post-process for the usage key:
```csharp
[UnityEditor.Callbacks.PostProcessBuild] static void P(UnityEditor.BuildTarget t, string path) {
  if (t != UnityEditor.BuildTarget.iOS) return; var f = System.IO.Path.Combine(path, "Info.plist");
  var d = new UnityEditor.iOS.Xcode.PlistDocument(); d.ReadFromFile(f);
  d.root.SetString("NSLocalNetworkUsageDescription", "Connects to the mission console on this network."); d.WriteToFile(f); }
```

---

## Claim 3: The app on the hotspot iPhone connects to the Mac on 172.20.10.x

**Verdict: LIKELY HOLDS. It is not supported by Apple and must be spiked on this exact phone and OS.**

Evidence for:
- Apple DTS (Quinn) has said apps on the hotspot device can reach hotspot clients: "That works right now". This is a 2017 forum post, so it is supporting evidence only.
- The Mac received a 172.20.10.x DHCP lease, so the link layer works.

Strongest evidence against:
1. **Not guaranteed by Apple.** Same Quinn post: "Personal Hotspot does not guarantee connectivity between apps running on the hotspot device and apps running on the hotspot network ... one could easily imagine it being blocked in the future." It also says Personal Hotspot "was designed *solely* as a way to connect the client devices to the Internet".
2. **iOS 26.4 hotspot regression.** Press reports from April 2026 say Wi-Fi hotspot clients get a 172.20.10.x lease, but "all IPv4 TCP connections fail immediately with 'Network is unreachable'" (iPhone 17 family; worked on 26.3). Apple's iOS 26 update notes (26.4.1 to 26.7.1) never mention a hotspot fix. It is unknown whether this hits an iPhone 16 Pro on 26.6.1, or traffic from the phone to the client.
3. **Apple's own caveats.**
   - "When you're not using the hotspot, your devices automatically disconnect to save battery life". Keep a 5 s heartbeat running.
   - The hotspot requires the carrier plan to allow it.
   - The hotspot shares cellular only. Apple: "You can't connect your iPhone to a Wi-Fi network, and then share that network". All of the Mac's own internet traffic (LLM APIs, for example) will go over cellular.
4. **Local Network privacy still applies.** The hotspot bridge is a broadcast-capable interface, and TN3179 defines a local network by that property. This is an inference; Apple does not document the hotspot case. Claim 2's retry logic is needed here too.
5. **The address is not stable.** DHCP may hand out a different 172.20.10.2 to .14 lease on rejoin, so .13 is not guaranteed. Put the host in an in-app text field.

Sources:
- Apple Developer Forums thread 79141, Quinn "The Eskimo!" (Apple DTS), June 2017: https://developer.apple.com/forums/thread/79141
- MobileSyrup, 2026-04-06: https://mobilesyrup.com/2026/04/06/iphone-17-experience-hotspot-issues-after-update/ (cites the MacRumors thread https://forums.macrumors.com/threads/hotspot-issues-after-26-4.2479908/ , which is forum evidence only)
- Apple "About iOS 26 Updates", published 2026-09-28 (26.6.1 = security fixes; 26.6.2, 26.7 and 26.7.1 also exist; no hotspot notes): https://support.apple.com/en-us/123075
- Apple iPhone User Guide (iOS 26), Share your internet connection (USB/Wi-Fi/Bluetooth, auto-disconnect, cellular only), fetched 2026-10-23: https://support.apple.com/guide/iphone/share-your-internet-connection-iph45447ca6/26.0/ios/26.0

Spike 3 (20 min, do it **before** the event):
1. Turn the hotspot on with Maximize Compatibility off (5 GHz). Join from the Mac over Wi-Fi. Run `ipconfig getifaddr en0` (check the interface with `networksetup -listallhardwareports`), then `ping -c3 172.20.10.1`.
2. **Safari control test.** TN3179 says Safari traffic is exempt from Local Network privacy, so this separates network problems from permission problems. On the Mac, run `python3 -m http.server 8000` in a folder containing `t.html`:
   `<script>const w=new WebSocket('ws://'+location.hostname+':8787');w.onopen=()=>document.body.textContent='OPEN';w.onerror=()=>document.body.textContent='ERROR';w.onmessage=e=>document.body.textContent=e.data</script>`
   On the iPhone, open `http://172.20.10.x:8000/t.html`. If Safari shows OPEN and the app fails, the problem is the permission or the app. If Safari fails too, the problem is the route, the firewall or the server binding.
3. Run the Spike 1A app against `ws://172.20.10.x:8787`. Leave it 15 minutes with heartbeats, then 15 minutes idle with the server heartbeat only, and confirm the Mac stays joined.
4. Repeat over a **USB cable**: Mac Wi-Fi off, cable in, Trust; then `ifconfig | grep 172.20.10`. USB avoids the congested 2.4/5 GHz air entirely.
5. Do **not** update iOS or Xcode before the event. The iOS 26.4 regression shows hotspot behavior changes between point releases.

---

## Claim 4: Venue Wi-Fi works directly; with client isolation there is no workaround

**Verdict: FALSE.** The first half is LIKELY HOLDS with caveats; the second half is false.

First half, caveats:
- "No isolation" does not mean "same L2 segment". Meraki's NAT mode "isolates clients" and is always on. Bridge-mode isolation also blocks wireless clients from reaching wired hosts on the same VLAN: "will only be able to communicate with the default gateway".
- A Mac-side block looks exactly like isolation:
  - the macOS Application Firewall, either "Block all incoming connections" or a denied `node` binary;
  - Node bound to `localhost` instead of all interfaces. `ws` binds all interfaces when `host` is omitted.
- Isolation drops SYNs silently, so an untimed connect hangs about 75 s (claim 1).

Second half, workarounds that need no different venue network:
1. **iPhone hotspot over USB or Wi-Fi** (claim 3). It is technically "a different network", but it is one you bring yourself.
2. **Tailscale** on the phone and the Mac. When direct paths fail, DERP relays "blindly forward already-encrypted traffic" through the internet. Per TN3179, traffic over a VPN interface is not "local network", so it also sidesteps the Local Network prompt. It costs uplink: 0.4 MB/s is plenty for JSON events, but latency rises.
3. **Cloudflare quick tunnel**: `cloudflared tunnel --url http://localhost:8787` gives a `wss://<random>.trycloudflare.com` address with no account. Cloudflare proxies WebSockets. There is "no uptime guarantee", a 200 concurrent-request cap, and the hostname changes on every run, so the app must accept a full URL including the `wss` scheme. Unity's ClientWebSocket TLS handles TLS 1.2. One forum report (6000.6) says Mono hardcodes TLS 1.2 for ClientWebSocket; Cloudflare accepts 1.2.
4. **USB without the hotspot**: reverse the direction. The phone listens, and the Mac connects through usbmux (`iproxy 8787 8787` from libusbmuxd 2.1.1, maintained). TN3179 says accepting incoming TCP needs no Local Network access. This costs a server inside Unity, so treat it as a last resort.

Sources:
- Meraki Wireless Client Isolation (undated, © 2026): https://documentation.meraki.com/MR/Firewall_and_Traffic_Shaping/Wireless_Client_Isolation ; NAT mode: https://documentation.meraki.com/MR/Client_Addressing_and_Bridging/NAT_Mode_with_Meraki_DHCP
- Tailscale DERP servers (last validated 2026-01-21): https://tailscale.com/kb/1232/derp-servers
- Cloudflare Quick Tunnels (last updated 2026-09-30): https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/ ; WebSockets: https://developers.cloudflare.com/network/websockets
- TN3179 (VPN/cellular not local; accepting TCP needs no access), revised 2026-10-06 (URL above)
- macOS firewall settings (fetched 2026-10-23): https://support.apple.com/guide/mac-help/change-firewall-settings-on-mac-mh11783/mac
- ws server options (`host`/`port`): https://github.com/websockets/ws/blob/master/doc/ws.md ; ws 8.22.0 release 2026-09-26
- libusbmuxd (iproxy), repo pushed 2025-09-07: https://github.com/libimobiledevice/libusbmuxd

Spike 4 (5 min on arrival, plus one at home beforehand):
1. On the Mac:
   - `lsof -nP -iTCP:8787 -sTCP:LISTEN`. Expect `*:8787`.
   - `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`, then `--getblockall`, then `--listapps`. `node` must be allowed.
2. Run the Safari `t.html` test from Spike 3 against the venue IP. OPEN means no isolation. If the page hangs, isolation is likely.
3. Rehearse fallbacks at home:
   - `tailscale status`, then `tailscale ping <phone>`. It shows "via DERP(...)" when relayed.
   - `cloudflared tunnel --url http://localhost:8787`, then point the app at the printed `wss://` URL.
4. Simulate silent isolation on the Mac with `echo "block drop in quick proto tcp from any to any port 8787" | sudo pfctl -ef -` (restore with `sudo pfctl -f /etc/pf.conf && sudo pfctl -d`). Confirm the app gives up in about 3 s per attempt, not 75 s.

---

## Claim 5: Bundled replay of a seeded run when the backend is unreachable

**Verdict: LIKELY HOLDS, with conditions.** Nothing platform-side blocks it. Unity reads `StreamingAssets` with regular file APIs on most platforms (Android and Web excepted); a `TextAsset` also works.

Strongest evidence against (design traps):
1. **"One branch per decision option" grows combinatorially.** With N decisions of k options, a full tree is k^N runs. It only scales if each option's segment rejoins a canonical trunk, or if only the first decision branches. State this explicitly in the log format: `{decisionId, option, events[], rejoinAt}`.
2. **The trigger can fire wrongly.**
   - The first connect on a fresh install may be denied while the Local Network alert is showing (claim 2).
   - A dropped SYN hangs about 75 s (claim 1).
   - A "Don't Allow" looks identical to "unreachable".
   Rules:
   - Never fall back on attempt 1.
   - Use an own 3 s timeout with 3 to 5 attempts.
   - Treat `OnOpen` plus an app-level `hello`/`ack` as "healthy".
   - Show a visible "Offline replay" banner so judges are not misled.
3. **Mid-run failover.** If the backend dies at event 140, replay has to resume from a matching sequence number, or restart cleanly.
4. **Schema drift.** A log recorded on Saturday morning breaks if the event schema changes on Saturday night. Regenerate the log as a build step, and feed replay through the *same* `OnMessage` parser as live.

Sources:
- Unity StreamingAssets (6000.0, built 2026-10-22): https://docs.unity3d.com/6000.0/Documentation/Manual/StreamingAssets.html
- TN3179 (immediate denial, retry advice), revised 2026-10-06; XNU `TCPTV_KEEP_INIT` (URLs above)

Spike 5 (20 min):
1. Turn on Airplane mode and launch. Replay should start within about 10 s, with the banner.
2. At each decision, choose every option in turn. Diff the rendered event sequence against the live recording. Only the timestamps should differ.
3. Kill `node` mid-run and confirm the app either resumes in replay at the same sequence number or restarts cleanly.
4. Fresh install with the backend up: the app must **not** enter replay while the Local Network alert is on screen.
5. Run the pfctl drop test from Spike 4.

---

## Claim 6: Resolving `<name>.local` from Unity on iOS

**Verdict: DOUBTFUL.** It is fine as a convenience but must not be the primary addressing scheme.

Evidence for:
- TN3179, "DNS operations": "Resolving a local DNS name | yes [requires local network access]". The check "applies to ... dnssd, `<net_db.h>`, and any APIs that use them", so the same Local Network permission covers it.
- `NSBonjourServices` is documented for "registering or browsing for specific Bonjour services". Plain hostname resolution is listed as a DNS operation, separate from the Bonjour-service rows. The docs therefore support "no `NSBonjourServices` needed", though Apple never states that sentence outright.

Strongest evidence against:
1. **mDNS needs working multicast between the phone and the Mac.** Meraki says NAT-mode isolation "will prevent Bonjour, layer 2 discovery protocols, and multicasting protocols from working". Bridge isolation blocks client-to-client broadcast and unicast unless Bonjour forwarding is configured. Congested venue Wi-Fi also loses multicast frames.
2. **The resolver path is undocumented.** Unity's ClientWebSocket calls `Dns.GetHostAddressesAsync`. That IL2CPP forwards it to `getaddrinfo` (and thus mDNSResponder) is an inference; Unity documents nothing about `.local`. On top of that, the managed connect walks the address list one entry at a time, so a stale or unreachable entry adds delay.
3. **The name is not stable.** macOS renames itself `name-2.local` on a conflict. Apple also warns that unicast DNS names ending in `.local` can fail on iOS. The note is archived (2023-08-07).
4. **It adds no value where it would matter.** On isolated venue Wi-Fi it fails along with the direct connection. On the hotspot, the IP is already known.

Sources:
- TN3179, revised 2026-10-06 (URL above)
- NSBonjourServices (fetched 2026-10-23, URL above)
- Meraki NAT mode / Client Isolation (URLs above)
- Apple Support 101297, `.local` names, published 2023-08-07 (archived): https://support.apple.com/en-us/101297

Spike 6 (10 min):
1. On the Mac, run `scutil --get LocalHostName`.
2. In the app, time `System.Net.Dns.GetHostAddresses("<name>.local")`. Log every address and family, then connect to each.
3. Run this on home Wi-Fi, on the hotspot and on venue Wi-Fi. Compare with Safari opening `http://<name>.local:8000/t.html`.
4. Pass criteria: under 1 s and a successful connect on all three networks. Otherwise ship only the IP field.

---

## Risks outside the claims

- **Chrome console.** Connect to `ws://localhost:8787`, not the LAN IP. Loopback is outside both macOS Local Network privacy and Chrome's Local Network Access rollout (blog 2025-06-09: https://developer.chrome.com/blog/local-network-access). Under macOS 15+ privacy, Chrome would need its own permission to reach a LAN IP. Node started from Terminal is auto-allowed, and accepting connections needs no permission (TN3179).
- **OS drift.** iOS 26.6.1 is not current: 26.6.2, 26.7 and 26.7.1 exist (Apple 123075). Node 26.12.1 is out (2026-10-21). Freeze all versions until after the demo.
- **Keep the app in the foreground.** Set `Screen.sleepTimeout = NeverSleep`. Backgrounding kills the socket, and 1.x had a resume crash (#49).

## Suggested connection ladder for demo day

1. iPhone hotspot over USB cable, IP typed into the app.
2. iPhone hotspot over Wi-Fi.
3. Venue Wi-Fi, direct.
4. Tailscale (DERP) or a `cloudflared` quick tunnel using `wss://`.
5. Bundled replay with a visible banner.

Make the app accept a full URL (`ws://` or `wss://`), remember it in PlayerPrefs, and show the connection state on screen.
