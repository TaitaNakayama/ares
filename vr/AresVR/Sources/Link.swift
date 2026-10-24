import Foundation

/// Live state pushed by the server (`vr_state`). Optional everywhere: the app must survive partial data.
struct VRState: Decodable {
  struct Power: Decodable { var socPct: Double?; var solarKWhPerSol: Double?; var loadKWhPerSol: Double?; var solsLeft: Double?; var drillOn: Bool? }
  struct Payment: Decodable { var id: String; var vendor: String?; var amountText: String? }
  struct Money: Decodable { var cashText: String?; var runwayDays: Int?; var committedText: String?; var savedText: String?; var payments: [Payment]? }
  struct Option: Decodable { var id: String; var label: String; var detail: String? }
  struct Waiting: Decodable { var id: String; var reason: String?; var decideByText: String?; var options: [Option] }
  struct Earth: Decodable { var id: String; var vendor: String?; var replyEtaText: String?; var replyInMin: Int? }
  struct Robot: Decodable { var name: String?; var text: String?; var mood: String?; var outcome: String?; var seq: Int? }
  struct Sun: Decodable { var elevation: Double?; var azimuth: Double? }
  var seed: String?
  var policyVersion: Int?
  var beat: Int?
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
}

/// WebSocket link to the Mac. Tries every baked server URL until one answers,
/// reconnects forever, and retries the first connection (iOS may deny it while
/// showing the Local Network prompt).
final class Link: NSObject, @unchecked Sendable {
  enum Status: Equatable { case connecting(String), connected(String), offline }
  private(set) var status: Status = .connecting("")
  private(set) var state: VRState?
  private(set) var stateVersion = 0
  private(set) var lastDecision: String?
  var onCaptureRequest: (() -> Void)?
  private weak var world: BaseScene?
  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var candidates: [String] = []
  private var index = 0
  private var current: URL?
  private let lock = NSLock()

  init(world: BaseScene) {
    self.world = world
    super.init()
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 4
    cfg.waitsForConnectivity = false
    session = URLSession(configuration: cfg)
    candidates = Self.loadCandidates()
  }

  static func loadCandidates() -> [String] {
    if let url = Bundle.main.url(forResource: "Resources/ares", withExtension: "json") ?? Bundle.main.url(forResource: "ares", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let list = obj["servers"] as? [String], !list.isEmpty {
      return list
    }
    return ["ws://172.20.10.2:8787/?client=vr"]
  }

  func start() { connectNext() }

  private func connectNext() {
    guard !candidates.isEmpty else { return }
    let s = candidates[index % candidates.count]
    index += 1
    guard let url = URL(string: s) else { return connectNext() }
    setStatus(.connecting(url.host ?? s))
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
      case .failure:
        self.lost(t)
      case .success(let msg):
        if case .string(let s) = msg { self.handle(s) }
        if case .data(let d) = msg, let s = String(data: d, encoding: .utf8) { self.handle(s) }
        self.receive(t)
      }
    }
  }

  private func handle(_ s: String) {
    if case .connecting = status, let t = task {
      setStatus(.connected(current?.host ?? ""))
      keepAlive(t)
    }
    guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = obj["type"] as? String else { return }
    switch type {
    case "vr_state", "hello":
      let key = type == "hello" ? "vr" : "state"
      if let st = obj[key], let d = try? JSONSerialization.data(withJSONObject: st), let v = try? JSONDecoder().decode(VRState.self, from: d) {
        lock.lock()
        state = v
        stateVersion += 1
        lock.unlock()
      }
    case "decided":
      lastDecision = obj["summary"] as? String
    case "capture":
      DispatchQueue.main.async { self.onCaptureRequest?() }
    default:
      break
    }
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

  func decide(escalationId: String, optionId: String) {
    let msg = ["type": "decide", "escalationId": escalationId, "optionId": optionId]
    guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
    task?.send(.string(s)) { _ in }
  }

  /// Debug: post a JPEG of the current frame to the server.
  func uploadCapture(_ jpg: Data, info: [String: Any]) {
    guard let ws = current, var comps = URLComponents(url: ws, resolvingAgainstBaseURL: false) else { return }
    comps.scheme = ws.scheme == "wss" ? "https" : "http"
    comps.path = "/api/capture"
    comps.query = info.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    guard let url = comps.url else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("image/jpeg", forHTTPHeaderField: "content-type")
    session.uploadTask(with: req, from: jpg).resume()
  }

  private func setStatus(_ s: Status) {
    lock.lock()
    status = s
    lock.unlock()
  }

  var statusText: String {
    switch status {
    case .connecting(let h): return "Connecting \(h)…"
    case .connected(let h): return "Live · \(h)"
    case .offline: return "Offline · retrying"
    }
  }
}
