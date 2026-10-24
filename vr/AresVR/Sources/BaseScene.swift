import SceneKit
import UIKit
import simd

/// The commander's control room. Spike version: room shell, a status wall screen,
/// gaze-selectable decision cards and the reticle. Later milestones add the window,
/// terrain, sky, robots and the three wall screens.
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
  private let reticle = SCNNode()
  private let status = TextPanel(width: 2.4, height: 1.35)
  private var cards: [SCNNode] = []
  private var cardPanels: [TextPanel] = []
  private var cardTargets: [(esc: String, opt: String, label: String, detail: String)] = []
  private var hovered: SCNNode?
  private var hoverStart: TimeInterval = 0
  private var taps = 0
  private var lastTapText = "—"
  private var lastStateVersion = -1
  private var now: TimeInterval = 0
  private var latest: VRState?

  init() {
    camera.zNear = 0.05
    camera.zFar = 60_000
    cameraNode.camera = camera
    scene.rootNode.addChildNode(cameraNode)
    scene.background.contents = UIColor(red: 0.62, green: 0.45, blue: 0.32, alpha: 1)
    buildRoom()
    buildReticle()
    status.node.position = SCNVector3(0, 2.1, -3.2)
    scene.rootNode.addChildNode(status.node)
    buildCards(count: 3)
  }

  private func buildRoom() {
    // Floor
    let floor = SCNNode(geometry: SCNCylinder(radius: 4.2, height: 0.05))
    floor.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1)
    floor.position = SCNVector3(0, -0.025, 0)
    scene.rootNode.addChildNode(floor)
    // Curved wall (inside faces), with a gap facing -Z for the future window.
    let wall = SCNTube(innerRadius: 4.0, outerRadius: 4.15, height: 3.2)
    wall.radialSegmentCount = 96
    let wm = SCNMaterial()
    wm.diffuse.contents = UIColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1)
    wm.isDoubleSided = true
    wall.materials = [wm]
    let wallNode = SCNNode(geometry: wall)
    wallNode.position = SCNVector3(0, 1.6, 0)
    scene.rootNode.addChildNode(wallNode)
    // Ceiling ring light
    let ceil = SCNNode(geometry: SCNCylinder(radius: 4.15, height: 0.05))
    ceil.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.75, alpha: 1)
    ceil.position = SCNVector3(0, 3.2, 0)
    scene.rootNode.addChildNode(ceil)
    // Orientation markers so stereo depth and tracking are easy to judge.
    for i in 0..<8 {
      let a = Float(i) / 8 * 2 * .pi
      let post = SCNNode(geometry: SCNBox(width: 0.15, height: 0.9, length: 0.15, chamferRadius: 0.03))
      post.geometry?.firstMaterial?.diffuse.contents = i == 0 ? Palette.amber : UIColor(white: 0.5, alpha: 1)
      post.position = SCNVector3(3.4 * sin(a), 0.45, -3.4 * cos(a))
      scene.rootNode.addChildNode(post)
    }
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 450
    scene.rootNode.addChildNode(ambient)
    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.intensity = 700
    key.eulerAngles = SCNVector3(-0.9, 0.4, 0)
    scene.rootNode.addChildNode(key)
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
    let holder = SCNNode()
    holder.addChildNode(reticle)
    holder.name = "reticleHolder"
    scene.rootNode.addChildNode(holder)
  }

  private func buildCards(count: Int) {
    for i in 0..<count {
      let p = TextPanel(width: 0.9, height: 0.62)
      let n = p.node
      n.name = "card:\(i)"
      n.categoryBitMask = interactiveMask
      let x = Float(i - (count - 1) / 2) * 1.0 - (count % 2 == 0 ? 0.5 : 0)
      n.position = SCNVector3(x, 1.25, -2.0)
      // Angle the outer cards toward the user.
      n.look(at: SCNVector3(0, 1.4, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      scene.rootNode.addChildNode(n)
      cards.append(n)
      cardPanels.append(p)
    }
  }

  // ---------------------------------------------------------------- per frame

  func update(time: TimeInterval, headView: simd_float4x4, fps: Double, link: Link) {
    now = time
    let (st, ver) = link.snapshot()
    if ver != lastStateVersion {
      lastStateVersion = ver
      latest = st
      refreshCards(st)
    }
    let worldFromHead = (headView * viewOffset).inverse
    let origin = SIMD3(worldFromHead.columns.3.x, worldFromHead.columns.3.y, worldFromHead.columns.3.z)
    let fwd = -simd_normalize(SIMD3(worldFromHead.columns.2.x, worldFromHead.columns.2.y, worldFromHead.columns.2.z))
    let hits = scene.rootNode.hitTestWithSegment(from: SCNVector3(origin), to: SCNVector3(origin + fwd * 40), options: [
      SCNHitTestOption.categoryBitMask.rawValue: interactiveMask,
      SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
      SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
    ])
    let hit = hits.first
    let dist: Float = hit.map { simd_distance(origin, SIMD3($0.worldCoordinates)) - 0.01 } ?? 2.5
    if let holder = scene.rootNode.childNode(withName: "reticleHolder", recursively: false) {
      holder.simdPosition = origin + fwd * dist
      holder.simdOrientation = simd_quatf(worldFromHead)
      let s: Float = dist * (hit != nil ? 1.6 : 1.0)
      holder.simdScale = SIMD3(repeating: s)
    }
    setHover(hit?.node)
    updateStatus(link: link, fps: fps)
  }

  private func setHover(_ node: SCNNode?) {
    guard node !== hovered else { return }
    if let h = hovered { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; h.scale = SCNVector3(1, 1, 1); SCNTransaction.commit() }
    hovered = node
    hoverStart = now
    if let n = node { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; n.scale = SCNVector3(1.08, 1.08, 1.08); SCNTransaction.commit() }
    refreshCards(latest)
  }

  /// The Cardboard button.
  func tap() {
    taps += 1
    guard let h = hovered, let name = h.name, name.hasPrefix("card:"), let i = Int(name.dropFirst(5)) else {
      lastTapText = "tap (not looking at a card)"
      return
    }
    if i < cardTargets.count, !cardTargets[i].esc.isEmpty {
      let t = cardTargets[i]
      lastTapText = "chose: \(t.label)"
      onDecide?(t.esc, t.opt)
    } else {
      lastTapText = "tapped test card \(i + 1)"
    }
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.08
    h.scale = SCNVector3(0.95, 0.95, 0.95)
    SCNTransaction.completionBlock = { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; h.scale = SCNVector3(1.08, 1.08, 1.08); SCNTransaction.commit() }
    SCNTransaction.commit()
  }

  private func refreshCards(_ st: VRState?) {
    let waiting = st?.waiting?.first
    let opts = Array((waiting?.options ?? []).prefix(cards.count))
    cardTargets = (0..<cards.count).map { i in
      if i < opts.count, let w = waiting { return (w.id, opts[i].id, opts[i].label, opts[i].detail ?? "") }
      return ("", "", "Test card \(i + 1)", "Look at me, then press the viewer button.")
    }
    for (i, p) in cardPanels.enumerated() {
      let t = cardTargets[i]
      let isHover = hovered === cards[i]
      let live = !t.esc.isEmpty
      p.update(key: "\(t.label)|\(t.detail)|\(isHover)|\(live)") { ctx, size in
        Draw.fill(ctx, CGRect(origin: .zero, size: size), isHover ? UIColor(red: 0.16, green: 0.14, blue: 0.08, alpha: 1) : Palette.panel)
        ctx.setStrokeColor((isHover ? Palette.amber : UIColor(white: 1, alpha: 0.25)).cgColor)
        ctx.setLineWidth(isHover ? 14 : 4)
        ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 7))
        _ = Draw.text(t.label, at: CGPoint(x: 36, y: 34), size: 46, weight: .bold, color: isHover ? Palette.amber : Palette.text, width: size.width - 72, maxLines: 2)
        _ = Draw.text(t.detail, at: CGPoint(x: 36, y: 170), size: 30, weight: .medium, color: Palette.dim, width: size.width - 72, maxLines: 5)
        if isHover { _ = Draw.text("Press the button to choose", at: CGPoint(x: 36, y: size.height - 64), size: 28, weight: .bold, color: Palette.amber) }
      }
    }
  }

  private func updateStatus(link: Link, fps: Double) {
    let st = latest
    let fpsBucket = Int(fps.rounded())
    let key = "\(link.statusText)|\(fpsBucket)|\(taps)|\(lastTapText)|\(st?.time ?? "")|\(st?.tau ?? 0)"
    status.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("ARES · SPIKE A", at: CGPoint(x: 60, y: 50), size: 64, weight: .heavy, color: Palette.amber)
      _ = Draw.text(link.statusText, at: CGPoint(x: 60, y: 160), size: 52, weight: .bold, color: link.statusText.hasPrefix("Live") ? Palette.green : Palette.red)
      _ = Draw.text("\(fpsBucket) fps · taps \(taps)", at: CGPoint(x: 60, y: 250), size: 52, weight: .bold)
      _ = Draw.text(lastTapText, at: CGPoint(x: 60, y: 340), size: 44, weight: .semibold, color: Palette.cyan, width: size.width - 120)
      if let t = st?.time { _ = Draw.text("Base time \(t)  ·  dust tau \(String(format: "%.1f", st?.tau ?? 0))", at: CGPoint(x: 60, y: 430), size: 42, weight: .semibold, color: Palette.dim) }
      _ = Draw.text("Hold the screen 2 s (out of the viewer) to scan your viewer's QR", at: CGPoint(x: 60, y: size.height - 90), size: 32, weight: .medium, color: Palette.dim, width: size.width - 120)
    }
  }
}
