import SceneKit
import UIKit
import simd

/// The commander's control room: room shell, window onto Jezero, three wall screens,
/// five robots, gaze-selectable decision cards and the reticle.
final class BaseScene {
  let scene = SCNScene()
  let cameraNode = SCNNode()
  let camera = SCNCamera()
  /// Eye height: the world is shifted down so the head sits 1.6 m above the floor.
  let viewOffset: simd_float4x4 = {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(0, -1.6, 0, 1)
    return m
  }()
  var onDecide: ((String, String) -> Void)?

  private let interactiveMask = 1 << 3
  private let reticleHolder = SCNNode()
  private let reticle = SCNNode()
  private let outside: Outside
  private let screens: WallScreens
  private var robots: [String: Robot] = [:]
  private let debug = TextPanel(width: 1.6, height: 0.6, pixelsPerMeter: 600)
  private let cardRoot = SCNNode()
  private var cards: [SCNNode] = []
  private var cardPanels: [TextPanel] = []
  private var cardTargets: [(esc: String, opt: String, label: String, detail: String)] = []
  private var hovered: SCNNode?
  private var taps = 0
  private var lastTapText = "—"
  private var lastStateVersion = -1
  private var now: TimeInterval = 0
  private var latest: VRState?
  private var cardsVisible = false
  /// After a choice, cards stay hidden briefly; if the item is still waiting (e.g. after "wait"), they return with fresh options.
  private var hideUntil: TimeInterval = 0

  init() {
    camera.zNear = 0.05
    camera.zFar = 60_000
    cameraNode.camera = camera
    scene.rootNode.addChildNode(cameraNode)
    Room.build(into: scene.rootNode)
    outside = Outside(scene: scene)
    screens = WallScreens(root: scene.rootNode)
    robots = RobotCrew.build(into: scene.rootNode)
    buildReticle()
    buildCards()
    debug.node.position = Room.ring(180, r: Room.radius - 0.1, y: 1.6)
    debug.node.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    scene.rootNode.addChildNode(debug.node)
  }

  private func buildReticle() {
    let ring = SCNTorus(ringRadius: 0.012, pipeRadius: 0.0025)
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = UIColor.white
    m.readsFromDepthBuffer = false
    m.writesToDepthBuffer = false
    ring.materials = [m]
    reticle.geometry = ring
    reticle.renderingOrder = 10_000
    reticle.eulerAngles.x = .pi / 2
    reticleHolder.addChildNode(reticle)
    scene.rootNode.addChildNode(reticleHolder)
  }

  private func buildCards() {
    // 2 x 2 grid of choices, about 1.9 m in front of the user, at eye level.
    let spots: [(Float, Float)] = [(-0.42, 1.80), (0.42, 1.80), (-0.42, 1.24), (0.42, 1.24)]
    for (i, s) in spots.enumerated() {
      let p = TextPanel(width: 0.8, height: 0.5, pixelsPerMeter: 960)
      let n = p.node
      n.name = "card:\(i)"
      n.categoryBitMask = interactiveMask
      n.position = SCNVector3(s.0, s.1, -1.9)
      n.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      cardRoot.addChildNode(n)
      cards.append(n)
      cardPanels.append(p)
    }
    cardRoot.opacity = 0
    cardRoot.isHidden = true
    scene.rootNode.addChildNode(cardRoot)
  }

  // ---------------------------------------------------------------- per frame

  func update(time: TimeInterval, headView: simd_float4x4, fps: Double, link: Link) {
    now = time
    let (st, ver) = link.snapshot()
    if ver != lastStateVersion {
      lastStateVersion = ver
      latest = st
      applyState(st)
    }
    let worldFromHead = (headView * viewOffset).inverse
    let origin = SIMD3(worldFromHead.columns.3.x, worldFromHead.columns.3.y, worldFromHead.columns.3.z)
    let fwd = -simd_normalize(SIMD3(worldFromHead.columns.2.x, worldFromHead.columns.2.y, worldFromHead.columns.2.z))
    var hitNode: SCNNode?
    var dist: Float = 2.5
    if cardsVisible {
      let hits = scene.rootNode.hitTestWithSegment(from: SCNVector3(origin), to: SCNVector3(origin + fwd * 10), options: [
        SCNHitTestOption.categoryBitMask.rawValue: interactiveMask,
        SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
      ])
      if let h = hits.first {
        hitNode = h.node
        dist = simd_distance(origin, SIMD3(h.worldCoordinates)) - 0.01
      }
    }
    reticleHolder.simdPosition = origin + fwd * dist
    reticleHolder.simdOrientation = simd_quatf(worldFromHead)
    reticleHolder.simdScale = SIMD3(repeating: dist * (hitNode != nil ? 1.7 : 1.0))
    setHover(hitNode)
    let needs = !(latest?.waiting ?? []).isEmpty
    if needs && !cardsVisible && now >= hideUntil { refreshCards(latest) }
    for r in robots.values { r.update(now: time, user: origin, needsCommander: needs) }
    screens.update(latest, now: time, linkText: link.statusText)
    updateDebug(link: link, fps: fps)
  }

  private func applyState(_ st: VRState?) {
    guard let st else { return }
    outside.apply(tau: st.tau ?? 0.6, sunAzimuth: st.sun?.azimuth ?? 120, sunElevation: st.sun?.elevation ?? 45)
    outside.setDrill(on: st.power?.drillOn ?? true)
    for (role, r) in st.robots ?? [:] {
      guard let robot = robots[role], let seq = r.seq else { continue }
      robot.hear(text: r.short ?? r.text ?? "", mood: r.mood ?? "calm", outcome: r.outcome ?? "said", seq: seq, now: now)
    }
    refreshCards(st)
  }

  private func setHover(_ node: SCNNode?) {
    guard node !== hovered else { return }
    if let h = hovered { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; h.scale = SCNVector3(1, 1, 1); SCNTransaction.commit() }
    hovered = node
    if let n = node { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; n.scale = SCNVector3(1.07, 1.07, 1.07); SCNTransaction.commit() }
    refreshCards(latest)
  }

  /// The Cardboard button.
  func tap() {
    taps += 1
    guard cardsVisible, let h = hovered, let name = h.name, name.hasPrefix("card:"), let i = Int(name.dropFirst(5)), i < cardTargets.count, !cardTargets[i].esc.isEmpty else {
      lastTapText = "tap"
      return
    }
    let t = cardTargets[i]
    lastTapText = "chose: \(t.label)"
    hideUntil = now + 1.5
    onDecide?(t.esc, t.opt)
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.1
    h.scale = SCNVector3(0.94, 0.94, 0.94)
    SCNTransaction.completionBlock = { [weak self] in self?.showCards(false) }
    SCNTransaction.commit()
  }

  private func showCards(_ on: Bool) {
    guard on != cardsVisible else { return }
    cardsVisible = on
    if on {
      cardRoot.isHidden = false
      cardRoot.runAction(.fadeIn(duration: 0.4))
    } else {
      cardRoot.runAction(.sequence([.fadeOut(duration: 0.3), .hide()]))
      setHover(nil)
    }
  }

  private func refreshCards(_ st: VRState?) {
    let waiting = st?.waiting?.first
    let opts = Array((waiting?.options ?? []).prefix(cards.count))
    showCards(waiting != nil && !opts.isEmpty && now >= hideUntil)
    cardTargets = (0..<cards.count).map { i in
      if i < opts.count, let w = waiting { return (w.id, opts[i].id, opts[i].label, Self.firstSentence(opts[i].detail ?? "")) }
      return ("", "", "", "")
    }
    for (i, p) in cardPanels.enumerated() {
      let t = cardTargets[i]
      cards[i].isHidden = t.esc.isEmpty
      let isHover = hovered === cards[i]
      p.update(key: "\(t.label)|\(t.detail)|\(isHover)") { ctx, size in
        Draw.fill(ctx, CGRect(origin: .zero, size: size), isHover ? UIColor(red: 0.17, green: 0.13, blue: 0.06, alpha: 1) : UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1))
        ctx.setStrokeColor((isHover ? Palette.amber : UIColor(white: 1, alpha: 0.3)).cgColor)
        ctx.setLineWidth(isHover ? 16 : 5)
        ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
        _ = Draw.text(t.label, at: CGPoint(x: 40, y: 34), size: 66, weight: .heavy, color: isHover ? Palette.amber : Palette.text, width: size.width - 80, maxLines: 2)
        _ = Draw.text(t.detail, at: CGPoint(x: 40, y: 210), size: 44, weight: .semibold, color: Palette.dim, width: size.width - 80, maxLines: 3)
        if isHover { _ = Draw.text("Press the button to choose", at: CGPoint(x: 40, y: size.height - 76), size: 42, weight: .heavy, color: Palette.amber) }
      }
    }
  }

  static func firstSentence(_ s: String) -> String {
    if let r = s.range(of: ". ") { return String(s[..<r.lowerBound]) + "." }
    return s
  }

  private func updateDebug(link: Link, fps: Double) {
    let key = "\(link.statusText)|\(Int(fps.rounded()))|\(taps)|\(lastTapText)|\(latest?.seed ?? "")"
    debug.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("ARES · \(link.statusText)", at: CGPoint(x: 30, y: 24), size: 44, weight: .bold, color: link.statusText.hasPrefix("Live") ? Palette.green : Palette.red, width: size.width - 60)
      _ = Draw.text("\(Int(fps.rounded())) fps · taps \(self.taps) · \(self.lastTapText)", at: CGPoint(x: 30, y: 110), size: 40, weight: .semibold, width: size.width - 60)
      _ = Draw.text("Seed \(self.latest?.seed ?? "-") · policy v\(self.latest?.policyVersion ?? 0)", at: CGPoint(x: 30, y: 190), size: 36, weight: .medium, color: Palette.dim)
      _ = Draw.text("Hold the screen 2 s (out of the viewer) to scan your viewer QR", at: CGPoint(x: 30, y: 270), size: 30, weight: .medium, color: Palette.dim, width: size.width - 60)
    }
  }
}
