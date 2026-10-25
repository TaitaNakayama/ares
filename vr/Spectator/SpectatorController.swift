import AppKit
import SceneKit
import simd

/// The Mac's spectator view: the headset's scene, one undistorted camera that follows the judge's
/// head (lightly smoothed, slightly wider), plus overlays for the table. Read-only: it never sends
/// a decision or a pose. Without a headset it shows the recorded run under a drifting camera.
final class SpectatorController: NSViewController, SCNSceneRendererDelegate {
  private let world = BaseScene()
  private let cam = SCNNode()
  private var scnView: SpectatorSCNView!
  private let overlay = OverlayView(frame: .zero)
  private var link: Link!
  private let pose = HeadPose()
  private let subtitles = SubtitleQueue()
  private var timer: Timer?
  private let start = CACurrentMediaTime()
  private var lastTick = CACurrentMediaTime()
  private var chosen: (label: String, at: TimeInterval)?
  private var mode: BadgeView.Mode = .replay
  private var lastReplay: Bool?

  // Camera state shared with SceneKit's render thread.
  private let camLock = NSLock()
  private var camMode: BadgeView.Mode = .replay
  private var camFovX: Float = 110
  private var smoother = OrientationSmoother()
  private var renderedQ = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
  // Where the judge stands (the walk outside): the headset's stream when live, else this scene's own walk.
  private var targetPos = SIMD3<Float>(0, 1.6, 0)
  private var targetYaw: Float = 0
  private var shownPos = SIMD3<Float>(0, 1.6, 0)
  private var shownYaw: Float = 0
  private var lastRender: TimeInterval = 0
  private var frames = 0
  private var fpsWindowStart = CACurrentMediaTime()
  private var fps: Double = 0

  #if DEBUG
  // Debug fallback only: a mouse-driven camera while no headset is connected. Compiled out of the demo build.
  private var mouseYaw: Float = 0
  private var closeUpShown = false
  private var realityShown = false
  private var mousePitch: Float = 0
  /// Captures (debug builds only): ARES_LOOK="yaw,pitch" (degrees, relative to the walk's own facing) and ARES_POS="x,z,yawRad"
  /// (a fixed head position and scene yaw outside) aim the camera without a headset.
  private let debugLook: (Float, Float)? = {
    guard let v = ProcessInfo.processInfo.environment["ARES_LOOK"] else { return nil }
    let p = v.split(separator: ",").compactMap { Float($0) }
    return p.count == 2 ? (p[0], p[1]) : nil
  }()
  private let debugPos: (SIMD3<Float>, Float)? = {
    guard let v = ProcessInfo.processInfo.environment["ARES_POS"] else { return nil }
    let p = v.split(separator: ",").compactMap { Float($0) }
    return p.count == 3 ? (SIMD3(p[0], 1.6, p[1]), p[2]) : nil
  }()
  #endif

  static let server = "ws://127.0.0.1:8787/?client=spectator"
  static let statsURL = URL(string: "http://127.0.0.1:8787/api/spectator/stats")!
  static let frameURL = URL(string: "http://127.0.0.1:8787/api/spectator/frame")!

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.black.cgColor
    let v = SpectatorSCNView(frame: root.bounds, options: nil)
    v.autoresizingMask = [.width, .height]
    v.scene = world.scene
    v.pointOfView = cam
    v.rendersContinuously = true
    v.isPlaying = true
    v.preferredFramesPerSecond = 60
    v.antialiasingMode = .multisampling4X
    v.isJitteringEnabled = false
    v.backgroundColor = .black
    v.delegate = self
    scnView = v
    overlay.frame = root.bounds
    overlay.autoresizingMask = [.width, .height]
    root.addSubview(v)
    root.addSubview(overlay)
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    world.showsReticle = false // the overlay draws the judge's gaze instead
    world.showsSpeakerArrow = false // the spectator camera is wider than the head pose; an edge arrow would point the wrong way
    Sound.shared.muted = true // the headset makes the sounds; no echo from the Mac
    let c = SCNCamera()
    c.zNear = 0.05
    c.zFar = 60_000
    c.projectionDirection = .horizontal
    c.fieldOfView = CGFloat(camFovX)
    cam.camera = c
    cam.simdPosition = SIMD3(0, 1.6, 0)
    world.scene.rootNode.addChildNode(cam)
    world.attachFade(to: cam)
    var all: [Any] = []
    world.scene.rootNode.enumerateHierarchy { n, _ in all.append(n) }
    scnView.prepare(all, completionHandler: nil)

    #if DEBUG
    if let l = debugLook { mouseYaw = l.0; mousePitch = l.1 }
    #endif
    link = Link(candidates: [Self.server])
    link.onMessage = { [weak self] type, m in DispatchQueue.main.async { self?.handle(type, m) } }
    // Pose frames skip the main queue: the render thread reads them directly.
    link.onRawMessage = { [weak self] type, m in if type == "vr_pose" { self?.pose.receive(m) } }
    link.start()
    #if DEBUG
    scnView.onDrag = { [weak self] dx, dy in self?.mouseDrag(dx: dx, dy: dy) }
    scnView.onClick = { [weak self] in
      guard let self else { return }
      if self.world.director.closeUp.isOpen { self.world.setCloseUpMirror(false) } else { self.world.openCloseUpAtHead() }
    }
    scnView.onKey = { c in if c == "r" { RealityCheck.toggle() } } // debug: reality check
    #endif
    RealityCheck.shared.install(world: world)
    RealityCheck.shared.onTextureReady = { [weak self] n in self?.scnView.prepare([n], completionHandler: nil) }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(timer!, forMode: .common)
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.postStats() }
  }

  // MARK: messages from the server

  private func handle(_ type: String, _ m: [String: Any]) {
    switch type {
    case "hello":
      if let h = m["headset"] as? Bool { pose.setConnected(h) }
    case "headset":
      pose.setConnected(m["connected"] as? Bool ?? false)
    case "narration":
      guard mode != .replay, let n = m["narration"] as? [String: Any] else { return }
      pushLine(n)
    case "vr_choice":
      if let label = m["label"] as? String { chosen = (label, CACurrentMediaTime()) }
    case "reset":
      subtitles.clear()
      chosen = nil
    case "spectator_capture":
      capture()
    default:
      break
    }
  }

  private func pushLine(_ n: [String: Any]) {
    guard let seq = n["seq"] as? Int, let role = n["role"] as? String else { return }
    let full = n["text"] as? String ?? ""
    let short = n["short"] as? String
    let text = full.count > 160 ? (short ?? String(full.prefix(157)) + "…") : full
    guard !text.isEmpty else { return }
    subtitles.push(Subtitle(seq: seq, role: role, name: n["name"] as? String ?? role, text: text, refused: (n["outcome"] as? String) == "deny"))
  }

  // MARK: per frame (main thread)

  private func tick() {
    let now = CACurrentMediaTime()
    lastTick = now
    let live = pose.isLive(now: now)
    #if DEBUG
    let newMode: BadgeView.Mode = live ? .live : .mouse
    let replay = !live && !link.isConnectedToServer
    #else
    let newMode: BadgeView.Mode = live ? .live : .replay
    let replay = !live
    #endif
    if newMode != mode || replay != lastReplay {
      // Switching between the live run and the recording: old lines belong to the other story.
      if replay != lastReplay { subtitles.clear(); chosen = nil }
      mode = newMode
      lastReplay = replay
      link.setReplay(replay)
    }
    let sample = pose.latest()
    camLock.lock()
    camMode = mode
    if let f = sample.fovX { camFovX = min(120, max(70, f + 10)) }
    let shownQ = renderedQ
    let fovX = camFovX
    let fps = self.fps
    camLock.unlock()

    // The judge's raw head pose drives the scene (hover, robots looking at them), as in the headset.
    // Live, the head position and yaw come from the headset's stream; otherwise from this scene's own walk.
    let headQ: simd_quatf = mode == .live ? sample.q : shownQ
    if mode == .live, let p = sample.p { world.director.externalHead = (p, sample.yaw ?? 0) } else { world.director.externalHead = nil }
    #if DEBUG
    if let d = debugPos, mode != .live { world.director.externalHead = d }
    #endif
    world.update(time: now - start, headView: simd_float4x4(headQ).inverse, fps: fps, link: link)
    if mode == .live { world.setCloseUpMirror(sample.closeUp) }
    // Reality check: the headset's `rc` flag (mono mirror); the sphere and caption follow the spectator camera's own position.
    if mode == .live { RealityCheck.shared.set(sample.reality) }
    RealityCheck.shared.update(now: now - start, eye: cam.simdPosition, forward: cam.simdWorldFront)
    #if DEBUG
    // Captures: `--reality` toggles the reality check once outside and the walk is over.
    if CommandLine.arguments.contains("--reality"), world.director.isOutside, !world.director.isWalking, now - start > 3, !realityShown, RealityCheck.shared.isAllowed {
      realityShown = true
      RealityCheck.toggle()
    }
    // Captures: `--closeup` opens the science close-up once the story is at the science site and the walk is over.
    if CommandLine.arguments.contains("--closeup"), world.director.station == "science", !world.director.isWalking, !world.director.closeUp.isOpen, now - start > 2, !closeUpShown {
      closeUpShown = true
      world.openCloseUpAtHead()
    }
    #endif
    camLock.lock()
    targetPos = world.director.eye
    targetYaw = world.director.yaw
    camLock.unlock()

    let (st, _) = link.snapshot()
    // In the recording there's no narration stream: take each robot's newest line from the state.
    if mode == .replay || !link.isConnectedToServer {
      for (role, r) in st?.robots ?? [:] {
        guard let seq = r.seq else { continue }
        pushLine(["seq": seq, "role": role, "name": r.name ?? role, "text": r.text ?? r.short ?? "", "short": r.short as Any, "outcome": r.outcome ?? "said"])
      }
    }
    overlay.thinking.roles = RobotCrew.layout.map(\.role).filter { link.thinkingRoles.contains($0) }
    if subtitles.tick(now: now) { overlay.subtitles.items = subtitles.visible }

    let waiting = st?.waiting?.first
    let opts = (waiting?.options ?? []).prefix(4).map { DecisionCardView.Option(id: $0.id, label: $0.label, detail: $0.detail ?? "", proposedBy: $0.proposedBy) }
    let gazed = mode == .live ? sample.gaze : nil
    if overlay.card.update(waitingReason: waiting?.reason, options: Array(opts), gazed: gazed, chosen: chosen, now: now) { overlay.needsLayout = true }

    overlay.badges.mode = mode
    if let b = st?.storyBeat { overlay.badges.beat = (b, st?.storyBeats ?? 7) } else { overlay.badges.beat = nil }
    #if DEBUG
    overlay.badges.debugText = String(format: "%.0f fps · %@ · fov %.0f°", fps, link.statusText, fovX)
    #endif

    // Gaze dot: the judge's actual (unsmoothed) direction, projected into the smoothed camera.
    if mode == .live {
      let fwd = sample.q.act(SIMD3<Float>(0, 0, -1))
      overlay.placeDot(project(direction: fwd, cameraQ: shownQ, fovX: fovX))
    } else {
      overlay.placeDot(nil)
    }
  }

  /// Screen point (overlay coordinates, top-left origin) of a view direction from the camera position.
  private func project(direction d: SIMD3<Float>, cameraQ: simd_quatf, fovX: Float) -> CGPoint? {
    let v = cameraQ.inverse.act(d)
    guard v.z < -0.05 else { return nil }
    let size = overlay.bounds.size
    guard size.width > 0, size.height > 0 else { return nil }
    let tx = tan(fovX * .pi / 360)
    let ty = tx * Float(size.height / size.width)
    let nx = (v.x / -v.z) / tx
    let ny = (v.y / -v.z) / ty
    return CGPoint(x: CGFloat((nx + 1) / 2) * size.width, y: CGFloat((1 - ny) / 2) * size.height)
  }

  // MARK: camera (SceneKit render thread)

  func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    let now = CACurrentMediaTime()
    camLock.lock()
    let dt = lastRender == 0 ? 1.0 / 60 : min(0.1, now - lastRender)
    lastRender = now
    let target: simd_quatf
    let tau: Double
    switch camMode {
    case .live:
      target = pose.latest().q
      tau = 0.10
    case .mouse:
      #if DEBUG
      target = CameraMath.orientation(yaw: mouseYaw, pitch: mousePitch)
      #else
      target = CameraMath.drift(at: now - start)
      #endif
      tau = 0.06
    case .replay:
      target = CameraMath.drift(at: now - start)
      tau = 1.2
    }
    let q = smoother.step(toward: target, dt: dt, timeConstant: tau)
    renderedQ = q
    // Position and scene yaw follow the same way, lightly smoothed.
    let a = Float(1 - exp(-dt / (camMode == .replay ? 0.25 : 0.10)))
    shownPos += (targetPos - shownPos) * a
    var dy = targetYaw - shownYaw
    while dy > .pi { dy -= 2 * .pi }
    while dy < -.pi { dy += 2 * .pi }
    shownYaw += dy * a
    let pos = shownPos, yawNow = shownYaw
    let fov = camFovX
    frames += 1
    if now - fpsWindowStart >= 1 {
      fps = Double(frames) / (now - fpsWindowStart)
      frames = 0
      fpsWindowStart = now
    }
    camLock.unlock()
    cam.simdPosition = pos
    cam.simdOrientation = simd_quatf(angle: yawNow, axis: SIMD3(0, 1, 0)) * q
    if abs(Float(cam.camera?.fieldOfView ?? 0) - fov) > 0.1 { cam.camera?.fieldOfView = CGFloat(fov) }
  }

  #if DEBUG
  private func mouseDrag(dx: CGFloat, dy: CGFloat) {
    // The headset always wins: mouse input is ignored the moment it is live.
    guard !pose.isLive() else { return }
    camLock.lock()
    mouseYaw += Float(dx) * 0.2
    mousePitch = max(-80, min(80, mousePitch - Float(dy) * 0.2))
    camLock.unlock()
  }
  #endif

  // MARK: verification without screen recording

  private func postStats() {
    camLock.lock()
    let f = fps, fov = camFovX
    camLock.unlock()
    let body: [String: Any] = ["fps": f, "mode": "\(mode)", "fovX": fov, "link": link.statusText, "size": [Int(view.bounds.width), Int(view.bounds.height)], "subtitles": subtitles.visible.map(\.text), "card": overlay.card.isUp]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    var req = URLRequest(url: Self.statsURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    URLSession.shared.uploadTask(with: req, from: data).resume()
  }

  /// What the table sees (3D + overlays) as a JPEG, posted to the server.
  private func capture() {
    let size = view.bounds.size
    // An offscreen render of the same scene and camera: works even when the window is covered.
    let r = SCNRenderer(device: scnView.device, options: nil)
    r.scene = world.scene
    r.pointOfView = cam
    let scale = view.window?.backingScaleFactor ?? 2
    let scene3d = r.snapshot(atTime: CACurrentMediaTime() - start, with: CGSize(width: size.width * scale, height: size.height * scale), antialiasingMode: .multisampling4X)
    upload(jpeg(scene3d), part: "3d")
    guard let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { return }
    overlay.cacheDisplay(in: overlay.bounds, to: rep)
    guard let base = scene3d.cgImage(forProposedRect: nil, context: nil, hints: nil), let top = rep.cgImage,
          let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
    ctx.draw(base, in: full)
    ctx.draw(top, in: full)
    guard let out = ctx.makeImage() else { return }
    upload(NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.8]), part: nil)
  }

  private func jpeg(_ img: NSImage) -> Data? {
    guard let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return nil }
    return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
  }

  private func upload(_ jpg: Data?, part: String?) {
    guard let jpg else { return }
    var comps = URLComponents(url: Self.frameURL, resolvingAgainstBaseURL: false)!
    if let part { comps.queryItems = [URLQueryItem(name: "part", value: part)] }
    var req = URLRequest(url: comps.url!)
    req.httpMethod = "POST"
    req.setValue("image/jpeg", forHTTPHeaderField: "content-type")
    URLSession.shared.uploadTask(with: req, from: jpg).resume()
  }
}

/// The 3D view. In debug builds only, dragging rotates the camera (when no headset is connected).
final class SpectatorSCNView: SCNView {
  #if DEBUG
  var onDrag: ((CGFloat, CGFloat) -> Void)?
  var onClick: (() -> Void)?
  override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX, event.deltaY) }
  override func mouseDown(with event: NSEvent) { onClick?() }
  var onKey: ((String) -> Void)?
  override func keyDown(with event: NSEvent) { if let c = event.charactersIgnoringModifiers { onKey?(c) } }
  #endif
  override var acceptsFirstResponder: Bool { true }
}
