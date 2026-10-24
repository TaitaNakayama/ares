import Foundation
import simd

/// Live state pushed by the server (`vr_state`). Optional everywhere: the app must survive partial data.
struct VRState: Decodable {
  struct Power: Decodable { var socPct: Double?; var solarKWhPerSol: Double?; var loadKWhPerSol: Double?; var solsLeft: Double?; var drillOn: Bool? }
  struct Payment: Decodable { var id: String; var vendor: String?; var amountText: String? }
  struct Money: Decodable { var cashText: String?; var runwayDays: Int?; var committedText: String?; var savedText: String?; var payments: [Payment]? }
  struct Option: Decodable { var id: String; var label: String; var detail: String?; var proposedBy: String? }
  struct Waiting: Decodable { var id: String; var reason: String?; var decideByText: String?; var options: [Option] }
  struct Earth: Decodable { var id: String; var vendor: String?; var replyEtaText: String?; var replyInMin: Int? }
  struct Robot: Decodable { var name: String?; var text: String?; var short: String?; var mood: String?; var outcome: String?; var seq: Int? }
  struct Sun: Decodable { var elevation: Double?; var azimuth: Double? }
  /// The real Perseverance reference the scientist shows (all optional; the app has bundled defaults).
  struct Science: Decodable { var scientist: String?; var instrument: String?; var sol: Double?; var target: String?; var credit: String?; var image: String?; var source: String?; var caption: String? }
  /// Two-part demo: `part` outside/inside, `station` pad/science/solar/door (absent in old tapes = inside).
  struct SceneInfo: Decodable { var part: String?; var station: String?; var science: Science? }
  var seed: String?
  var policyVersion: Int?
  var beat: Int?
  /// Where the demo story is, 1-7 (absent in tapes recorded before it existed).
  var storyBeat: Int?
  var storyBeats: Int?
  var timelapse: Bool?
  var time: String?
  var tau: Double?
  var sun: Sun?
  var lightTimeMin: Double?
  var power: Power?
  var money: Money?
  var waiting: [Waiting]?
  var earth: [Earth]?
  var robots: [String: Robot]?
  /// Roles whose LLM brain is deciding right now (absent in old tapes).
  var thinking: [String]?
  var agentMode: String?
  var scene: SceneInfo?
}

/// WebSocket link to the Mac. Tries every baked server URL until one answers,
/// reconnects forever, and retries the first connection (iOS may deny it while
/// showing the Local Network prompt).
final class Link: NSObject, @unchecked Sendable {
  enum Status: Equatable { case connecting(String), connected(String), offline, replay }
  private(set) var status: Status = .connecting("")
  private(set) var state: VRState?
  private(set) var stateVersion = 0
  private(set) var lastDecision: String?
  /// Debug: capture with an optional forced head direction (yaw/pitch in degrees).
  var onCaptureRequest: ((Double?, Double?) -> Void)?
  var onRecenter: (() -> Void)?
  var onScanViewer: (() -> Void)?
  /// Recording mode for the demo video: (on, fps, director camera).
  var onRecord: ((Bool, Int, Bool) -> Void)?
  /// Every parsed message, on the network queue (the spectator view's own message types).
  var onMessage: ((String, [String: Any]) -> Void)?
  /// Same, but called before `onMessage` for high-rate messages the receiver handles itself.
  var onRawMessage: ((String, [String: Any]) -> Void)?
  private let uploadQueue = DispatchQueue(label: "ares.upload")
  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var candidates: [String] = []
  private var index = 0
  private var current: URL?
  private let lock = NSLock()
  private var everConnected = false
  // Thinking roles: the server's set (vr_state / push) plus asks made here that the server has not confirmed yet.
  private var serverThinking = Set<String>()
  private var localThinking: [String: Date] = [:]
  /// Debug: play the tape while staying connected (so captures still work).
  private var forcedReplay = false
  // Offline replay (bundled tape recorded from the live server).
  private struct Frame { let t: Double; let state: VRState }
  private var tapePrefix: [Frame] = []
  private var tapeBranches: [String: [Frame]] = [:]
  private var replayStart = Date()
  private var branch: [Frame]?
  private var branchStart = Date()
  private var replayTimer: Timer?

  /// `candidates`: server URLs to try in turn; nil = the addresses baked into ares.json (the headset).
  init(candidates: [String]? = nil) {
    super.init()
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 4
    cfg.waitsForConnectivity = false
    session = URLSession(configuration: cfg)
    self.candidates = candidates ?? Self.loadCandidates()
  }

  /// Per-machine token from scripts/build-ios.sh; the server refuses headsets without it.
  static let token: String = {
    guard let url = Bundle.main.url(forResource: "ares", withExtension: "json"), let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
    return obj["token"] as? String ?? ""
  }()

  static func loadCandidates() -> [String] {
    var list: [String] = ["ws://172.20.10.2:8787/?client=vr"]
    if let url = Bundle.main.url(forResource: "ares", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let l = obj["servers"] as? [String], !l.isEmpty {
      list = l
    }
    // Append the token unless the URL already has a `t` query item ("client=vr" also contains "t=").
    guard !token.isEmpty else { return list }
    return list.map { s in
      let hasToken = URLComponents(string: s)?.queryItems?.contains { $0.name == "t" } ?? false
      return hasToken ? s : s + (s.contains("?") ? "&" : "?") + "t=" + token
    }
  }

  func start() {
    connectNext()
    // No server after 12 s: play the bundled tape, keep trying the network in the background.
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
      guard let self, !self.everConnected else { return }
      self.enterReplay()
    }
  }

  var isReplay: Bool { replayTimer != nil }

  /// A live connection to the server (whether or not the recording is playing on top).
  var isConnectedToServer: Bool {
    lock.lock()
    defer { lock.unlock() }
    if case .connected = status { return true }
    return forcedReplay && everConnected && task != nil
  }

  /// Play the recording instead of the live state (main thread). No-op when already in that mode.
  func setReplay(_ on: Bool) {
    guard on != forcedReplay || on != isReplay else { return }
    forcedReplay = on
    if on { exitReplay(); enterReplay() } else { exitReplay() }
  }

  private func enterReplay() {
    guard replayTimer == nil, loadTape() else { return }
    replayStart = Date()
    branch = nil
    replayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.replayTick() }
  }

  private func exitReplay() {
    replayTimer?.invalidate()
    replayTimer = nil
  }

  private func loadTape() -> Bool {
    if !tapePrefix.isEmpty { return true }
    guard let url = Bundle.main.url(forResource: "tape", withExtension: "json"), let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    func frames(_ any: Any?) -> [Frame] {
      (any as? [[String: Any]] ?? []).compactMap { f in
        guard let t = f["t"] as? Double, let st = f["state"], let d = try? JSONSerialization.data(withJSONObject: st), let v = try? JSONDecoder().decode(VRState.self, from: d) else { return nil }
        return Frame(t: t / 1000, state: v)
      }
    }
    tapePrefix = frames(obj["prefix"])
    for (k, v) in obj["branches"] as? [String: Any] ?? [:] { tapeBranches[k] = frames(v) }
    return !tapePrefix.isEmpty
  }

  private func replayTick() {
    let frames: [Frame]
    let t: Double
    if let b = branch { frames = b; t = Date().timeIntervalSince(branchStart) } else { frames = tapePrefix; t = Date().timeIntervalSince(replayStart) }
    // Hold the last frame; after a finished branch, restart the story after 40 s.
    if branch != nil, t > (frames.last?.t ?? 0) + 40 { branch = nil; replayStart = Date(); return }
    guard let f = frames.last(where: { $0.t <= t }) ?? frames.first else { return }
    lock.lock()
    state = f.state
    stateVersion += 1
    status = .replay
    lock.unlock()
  }


  private func connectNext() {
    guard !candidates.isEmpty else { return }
    let s = candidates[index % candidates.count]
    index += 1
    guard let url = URL(string: s) else { return connectNext() }
    setStatus(.connecting(url.host ?? s))
    NSLog("[link] trying %@", url.host ?? s)
    let t = session.webSocketTask(with: url)
    t.maximumMessageSize = 8 * 1024 * 1024
    task = t
    current = url
    t.resume()
    // Connected = the server's first message arrived (it sends "hello" immediately).
    receive(t)
    // A blocked connection can hang; give up on this candidate after a few seconds.
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      guard let self, self.task === t, case .connecting = self.status else { return }
      t.cancel()
      self.connectNext()
    }
  }

  private func keepAlive(_ t: URLSessionWebSocketTask) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      guard let self, self.task === t else { return }
      t.sendPing { err in
        if err != nil { self.lost(t) } else { self.keepAlive(t) }
      }
    }
  }

  private func lost(_ t: URLSessionWebSocketTask) {
    guard task === t else { return }
    t.cancel()
    setStatus(.offline)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.connectNext() }
  }

  private func receive(_ t: URLSessionWebSocketTask) {
    t.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .failure(let err):
        NSLog("[link] %@ failed: %@", self.current?.host ?? "?", err.localizedDescription)
        self.lost(t)
      case .success(let msg):
        if case .string(let s) = msg { self.handle(s) }
        if case .data(let d) = msg, let s = String(data: d, encoding: .utf8) { self.handle(s) }
        self.receive(t)
      }
    }
  }

  private func handle(_ s: String) {
    everConnected = true
    if isReplay && !forcedReplay { DispatchQueue.main.async { self.exitReplay() } }
    let wasConnecting: Bool = { if case .connected = status { return false }; return true }()
    if wasConnecting, let t = task {
      lock.lock()
      status = .connected(current?.host ?? "")
      lock.unlock()
      keepAlive(t)
    }
    guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { return }
    onRawMessage?(type, obj)
    if type != "vr_pose" { onMessage?(type, obj) }
    switch type {
    case "force_replay":
      let on = obj["on"] as? Bool ?? true
      DispatchQueue.main.async {
        self.forcedReplay = on
        if on { self.exitReplay(); self.enterReplay() } else { self.exitReplay() }
      }
    case "vr_state", "hello":
      if forcedReplay { break }
      let key = type == "hello" ? "vr" : "state"
      if let st = obj[key], let d = try? JSONSerialization.data(withJSONObject: st), let v = try? JSONDecoder().decode(VRState.self, from: d) {
        lock.lock()
        state = v
        stateVersion += 1
        serverThinking = Set(v.thinking ?? [])
        lock.unlock()
      }
    case "scene":
      // The server's push on enter: flip the part without waiting for the next vr_state.
      if forcedReplay { break }
      lock.lock()
      if var st = state, let part = obj["part"] as? String {
        var sc = st.scene ?? VRState.SceneInfo()
        sc.part = part
        st.scene = sc
        state = st
        stateVersion += 1
      }
      lock.unlock()
    case "thinking":
      if let role = obj["role"] as? String {
        let on = obj["on"] as? Bool ?? false
        lock.lock()
        if on { serverThinking.insert(role) } else { serverThinking.remove(role); localThinking[role] = nil }
        lock.unlock()
      }
    case "decided":
      lastDecision = obj["summary"] as? String
    case "recenter":
      DispatchQueue.main.async { self.onRecenter?() }
    case "scan_viewer":
      DispatchQueue.main.async { self.onScanViewer?() }
    case "record":
      let on = obj["on"] as? Bool ?? false
      let fps = obj["fps"] as? Int ?? 12
      let director = obj["director"] as? Bool ?? true
      DispatchQueue.main.async { self.onRecord?(on, fps, director) }
    case "capture":
      let yaw = obj["yaw"] as? Double
      let pitch = obj["pitch"] as? Double
      DispatchQueue.main.async { self.onCaptureRequest?(yaw, pitch) }
    default:
      break
    }
  }

  /// Roles that are thinking now: the server's list plus local asks (shown for up to 12 s until the server says otherwise).
  var thinkingRoles: Set<String> {
    lock.lock()
    defer { lock.unlock() }
    let now = Date()
    localThinking = localThinking.filter { $0.value > now }
    return serverThinking.union(localThinking.keys)
  }

  /// Ask one agent to explain itself live (`vr_ask`). Shows the thinking state at once; the answer comes back as a narration.
  func ask(role: String) {
    guard !isReplay else { return }
    lock.lock()
    localThinking[role] = Date().addingTimeInterval(12)
    lock.unlock()
    let msg = ["type": "vr_ask", "role": role]
    guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
    task?.send(.string(s)) { _ in }
  }

  func snapshot() -> (VRState?, Int) {
    lock.lock()
    defer { lock.unlock() }
    return (state, stateVersion)
  }

  /// Debug telemetry so the Mac can see how the headset is doing.
  func sendStats(_ stats: [String: Any]) {
    var msg = stats
    msg["type"] = "vr_stats"
    msg["link"] = statusText
    guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
    task?.send(.string(s)) { _ in }
  }

  /// The judge's head orientation for the Mac's spectator view (`vr_pose`): world-from-head rotation,
  /// the decision card under the reticle, whether cards are up, the eye's horizontal field of view.
  /// `pos` is the head position in the scene (the walk outside), `yaw` the scene yaw applied to the head
  /// (so the spectator camera is `Rot(yaw) * q` at `pos`), `closeUp` whether the science close-up is open.
  func sendPose(_ q: simd_quatf, gaze: Int?, cards: Bool, fovX: Float, pos: SIMD3<Float> = SIMD3(0, 1.6, 0), yaw: Float = 0, closeUp: Bool = false) {
    guard case .connected = status, let t = task else { return }
    let v = q.vector
    let s = String(format: "{\"type\":\"vr_pose\",\"q\":[%.5f,%.5f,%.5f,%.5f],\"p\":[%.3f,%.3f,%.3f],\"wy\":%.4f,\"cu\":%@,\"gaze\":%ld,\"cards\":%@,\"fov\":%.1f}", v.x, v.y, v.z, v.w, pos.x, pos.y, pos.z, yaw, closeUp ? "true" : "false", gaze ?? -1, cards ? "true" : "false", fovX)
    t.send(.string(s)) { _ in }
  }

  /// The judge tapped the pressure door: the server takes the story inside (`vr_enter`).
  func enter() {
    guard !isReplay else { return }
    let msg = ["type": "vr_enter"]
    guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
    task?.send(.string(s)) { _ in }
  }

  func decide(escalationId: String, optionId: String) {
    if isReplay {
      if let b = tapeBranches[optionId] ?? tapeBranches.first(where: { $0.key.hasPrefix(String(optionId.prefix(4))) })?.value {
        branch = b
        branchStart = Date()
      }
      return
    }
    let msg = ["type": "decide", "escalationId": escalationId, "optionId": optionId]
    guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
    task?.send(.string(s)) { _ in }
  }

  /// Recording: post one video frame (JPEG) to the server.
  func uploadFrame(_ jpg: Data) {
    guard let ws = current, var comps = URLComponents(url: ws, resolvingAgainstBaseURL: false) else { return }
    comps.scheme = ws.scheme == "wss" ? "https" : "http"
    comps.path = "/api/record/frame"
    comps.query = "t=\(Self.token)"
    guard let url = comps.url else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("image/jpeg", forHTTPHeaderField: "content-type")
    session.uploadTask(with: req, from: jpg).resume()
  }

  /// Debug: post a JPEG of the current frame to the server.
  func uploadCapture(_ jpg: Data, info: [String: Any]) {
    guard let ws = current, var comps = URLComponents(url: ws, resolvingAgainstBaseURL: false) else { return }
    comps.scheme = ws.scheme == "wss" ? "https" : "http"
    comps.path = "/api/capture"
    comps.query = (info.map { "\($0.key)=\($0.value)" } + ["t=\(Self.token)"]).joined(separator: "&")
    guard let url = comps.url else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("image/jpeg", forHTTPHeaderField: "content-type")
    session.uploadTask(with: req, from: jpg).resume()
  }

  private func setStatus(_ s: Status) {
    lock.lock()
    if replayTimer == nil || s != .offline { if !(replayTimer != nil && { if case .connecting = s { return true } else { return false } }()) { status = s } }
    lock.unlock()
  }

  var statusText: String {
    switch status {
    case .connecting(let h): return "Connecting \(h)…"
    case .connected(let h): return "Live · \(h)"
    case .offline: return "Offline · retrying"
    case .replay: return "Offline replay (recorded run)"
    }
  }
}
