import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// The commander's control room: room shell, window onto Jezero, three wall screens,
/// five robots, gaze-selectable decision cards and the reticle.
final class BaseScene {
  let scene = SCNScene()
  /// Head pose node; each eye is a fixed child (head-from-eye), with its own projection.
  let head = SCNNode()
  let eyes = [SCNNode(), SCNNode()]
  /// Mono 16:9 camera for the demo video (only rendered while recording).
  let videoCam = SCNNode()
  /// Eye height: the world is shifted down so the head sits 1.6 m above the floor.
  var viewOffset: simd_float4x4 = {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(0, -1.6, 0, 1)
    return m
  }()
  var onDecide: ((String, String) -> Void)?
  /// The Cardboard button with the reticle on a robot (and no card): ask that robot to explain itself.
  var onAsk: ((String) -> Void)?
  /// Roles whose agent is thinking; set from the link every frame.
  private var thinkingRoles = Set<String>()
  private var lastDecisionHeard: String?
  private var decisionPrimed = false
  private var hoveredRobot: String?
  private var lastAsk: [String: TimeInterval] = [:]
  /// The spectator view draws its own gaze dot.
  var showsReticle = true { didSet { reticleHolder.isHidden = !showsReticle } }
  /// The decision card under the reticle (0-3), if any: streamed to the spectator view.
  var gazedCard: Int? {
    guard cardsVisible, let n = hovered?.name, n.hasPrefix("card:") else { return nil }
    return Int(n.dropFirst(5))
  }
  var cardsShown: Bool { cardsVisible }

  /// Part 1 (outside): the outdoor set, the walk, the scientist, the door. See Stations.swift.
  private(set) var director: OutdoorDirector!
  /// False while a debug spike owns `viewOffset` (GroundSpike).
  var drivesView = true
  /// "scientist" or "door" while the reticle is on it (outside).
  private var hoveredSpecial: String?
  /// Called when the judge presses the door (the headset sends `vr_enter`).
  var onEnter: (() -> Void)?
  private let interactiveMask = 1 << 3
  private let reticleHolder = SCNNode()
  private let reticle = SCNNode()
  let outside: Outside
  private let screens: WallScreens
  private var robots: [String: Robot] = [:]
  private let debug = TextPanel(width: 1.6, height: 0.6, pixelsPerMeter: 600)
  /// Head-locked arrow toward a speaking robot that is outside the view. The spectator camera is wider than the head pose, so it turns this off.
  var showsSpeakerArrow = true
  private let arrow = OffscreenArrow()
  private var arrowRole = ""
  private var captionSeq = -1
  private var captionAt: TimeInterval = -100
  private var captionRole: String?
  private var lastSaved = ""
  private var savedChangedAt: TimeInterval = -100
  private let cardRoot = SCNNode()
  private var cards: [SCNNode] = []
  private var cardPanels: [TextPanel] = []
  private var cardTargets: [(esc: String, opt: String, label: String, detail: String, by: String)] = []
  private var hovered: SCNNode?
  private var taps = 0
  private var lastTapText = "—"
  private var lastStateVersion = -1
  private var now: TimeInterval = 0
  private var latest: VRState?
  private var cardsVisible = false
  private var lastHeadView = matrix_identity_float4x4
  /// After a choice, cards stay hidden briefly; if the item is still waiting (e.g. after "wait"), they return with fresh options.
  private var hideUntil: TimeInterval = 0

  init() {
    for e in eyes {
      let c = SCNCamera()
      c.zNear = 0.05
      c.zFar = 60_000
      e.camera = c
      head.addChildNode(e)
    }
    let vc = SCNCamera()
    vc.zNear = 0.05
    vc.zFar = 60_000
    vc.fieldOfView = 62
    vc.projectionDirection = .vertical
    videoCam.camera = vc
    head.addChildNode(videoCam)
    scene.rootNode.addChildNode(head)
    var indoor: [SCNNode] = []
    let rootNode = scene.rootNode
    func added(_ build: () -> Void) {
      let before = Set(rootNode.childNodes.map { ObjectIdentifier($0) })
      build()
      indoor += rootNode.childNodes.filter { !before.contains(ObjectIdentifier($0)) }
    }
    added { Room.build(into: rootNode) }
    outside = Outside(scene: scene)
    var wallScreens: WallScreens!
    added { wallScreens = WallScreens(root: rootNode) }
    screens = wallScreens
    robots = RobotCrew.build(into: scene.rootNode)
    buildReticle()
    buildCards()
    arrow.node.renderingOrder = 9_000
    scene.rootNode.addChildNode(arrow.node)
    debug.node.position = Room.ring(180, r: Room.radius - 0.1, y: 1.6)
    debug.node.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    scene.rootNode.addChildNode(debug.node)
    director = OutdoorDirector(scene: scene, outside: outside, indoorNodes: indoor + [debug.node, cardRoot], indoorRobots: robots)
  }

  /// A full-view black quad on this camera node for the fade to black (the headset passes `head`, the Mac its camera).
  func attachFade(to camera: SCNNode) { director.attachFade(to: camera) }

  /// The robots the judge can see and gaze at: the two at their outdoor stations, or the five indoors.
  private var liveRobots: [Robot] { director.isOutside ? Array(director.outdoorRobots.values) : Array(robots.values) }

  private func buildReticle() {
    let ring = SCNTorus(ringRadius: 0.012, pipeRadius: 0.0025)
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = PlatformColor.white
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
    director.update(now: time)
    if drivesView { viewOffset = director.viewOffset }
    lastHeadView = headView
    let worldFromHead = (headView * viewOffset).inverse
    let origin = SIMD3(worldFromHead.columns.3.x, worldFromHead.columns.3.y, worldFromHead.columns.3.z)
    let fwd = -simd_normalize(SIMD3(worldFromHead.columns.2.x, worldFromHead.columns.2.y, worldFromHead.columns.2.z))
    var hitNode: SCNNode?
    var dist: Float = 2.5
    if cardsVisible && !director.isOutside {
      let hits = scene.rootNode.hitTestWithSegment(from: SCNVector3(origin), to: SCNVector3(origin + fwd * 10), options: [
        SCNHitTestOption.categoryBitMask.rawValue: interactiveMask,
        SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
      ])
      if let h = hits.first {
        hitNode = h.node
        dist = simd_distance(origin, SIMD3(h.worldCoordinates)) - 0.01
      }
    }
    // Robots (body or nametag): a simple ray test; cards take priority.
    var robotHit: (role: String, d: Float)?
    if hitNode == nil {
      for r in liveRobots {
        for (c, rad) in [(r.worldPosition, Float(0.34)), (r.worldPosition + SIMD3(0, 0.62, 0), Float(0.2))] {
          let t = simd_dot(c - origin, fwd)
          guard t > 0.3, simd_length(c - (origin + fwd * t)) < rad else { continue }
          if t < (robotHit?.d ?? .infinity) { robotHit = (r.role, t) }
        }
      }
    }
    // The scientist and the pressure door (outside): whichever the reticle reaches first.
    var special: (id: String, d: Float)?
    if hitNode == nil && director.isOutside {
      if let d = director.scientistHit(origin: origin, fwd: fwd) { special = ("scientist", d) }
      if let d = director.doorHit(origin: origin, fwd: fwd), d < (special?.d ?? .infinity) { special = ("door", d) }
      if let s = special, let rh = robotHit, rh.d < s.d { special = nil }
      if special != nil { robotHit = nil }
    }
    hoveredSpecial = special?.id
    director.doorHovered = special?.id == "door"
    director.scientist.hovered = special?.id == "scientist" && !director.closeUp.isOpen
    hoveredRobot = robotHit?.role
    if let rh = robotHit { dist = max(0.5, rh.d - 0.4) }
    if let s = special { dist = max(0.5, s.d - 0.4) }
    if director.closeUp.isOpen {
      // The close-up: looking away for 3 s closes it.
      if director.closeUp.tick(now: time, eye: origin, forward: fwd) { Sound.shared.play("hover", volume: 0.3) }
    }
    reticleHolder.simdPosition = origin + fwd * dist
    reticleHolder.simdOrientation = simd_quatf(worldFromHead)
    reticleHolder.simdScale = SIMD3(repeating: dist * (hitNode != nil || robotHit != nil || special != nil ? 1.7 : 1.0))
    setHover(hitNode)
    let needs = !(latest?.waiting ?? []).isEmpty && !director.isOutside
    if (needs && !cardsVisible && now >= hideUntil) || (director.isOutside && cardsVisible) { refreshCards(latest) }
    // One bubble at a time: the newest speaker's.
    let speaker = now - captionAt < 9 ? captionRole : nil
    let nowThinking = link.thinkingRoles
    if !nowThinking.subtracting(thinkingRoles).isEmpty { Sound.shared.thinkingStarted() }
    thinkingRoles = nowThinking
    if link.lastDecision != lastDecisionHeard {
      if decisionPrimed { Sound.shared.decided() }
      lastDecisionHeard = link.lastDecision
    }
    decisionPrimed = true
    for r in liveRobots {
      r.hovered = r.role == hoveredRobot
      r.update(now: time, user: origin, needsCommander: needs, bubbleWanted: r.role == speaker, thinking: thinkingRoles.contains(r.role))
    }
    if director.isOutside { director.scientist.update(now: time, user: origin, bubbleWanted: speaker == "scientist") }
    updateArrow(worldFromHead: worldFromHead)
    screens.update(latest, now: time, linkText: link.statusText)
    updateDebug(link: link, fps: fps)
  }

  /// Head-locked arrow at the edge of the view toward the newest speaker, only while that robot is out of view.
  private func updateArrow(worldFromHead: simd_float4x4) {
    guard showsSpeakerArrow, let role = captionRole, now - captionAt < 9, let robot = (director.isOutside ? director.outdoorRobots[role] : robots[role]), robot.isSpeaking(now: now) else { arrow.node.isHidden = true; return }
    let wp = robot.worldPosition
    let local4 = (worldFromHead.inverse) * SIMD4(wp.x, wp.y + 0.1, wp.z, 1)
    guard let place = OffscreenArrow.place(local: SIMD3(local4.x, local4.y, local4.z)) else { arrow.node.isHidden = true; return }
    if arrowRole != role { arrowRole = role; arrow.setColor(robot.color, key: role) }
    let t = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(place.pos.x, place.pos.y, place.pos.z, 1)))
    let c = cos(place.angle), s = sin(place.angle)
    let r = simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    arrow.node.simdWorldTransform = worldFromHead * t * r
    arrow.node.isHidden = false
  }

  private func applyState(_ st: VRState?) {
    guard let st else { return }
    if let saved = st.money?.savedText, saved != lastSaved {
      if !lastSaved.isEmpty { savedChangedAt = now; Sound.shared.play("saved", volume: 0.8) }
      lastSaved = saved
    }
    director.apply(st, now: now)
    outside.apply(tau: st.tau ?? 0.6, sunAzimuth: st.sun?.azimuth ?? 120, sunElevation: st.sun?.elevation ?? 45)
    outside.show(Consequence.active(in: st))
    Sound.shared.setStorm(tau: st.tau ?? 0.6)
    var newest: (role: String, r: VRState.Robot)?
    for (role, r) in st.robots ?? [:] {
      guard let seq = r.seq else { continue }
      if role == "scientist" {
        director.scientist.hear(text: r.short ?? r.text ?? "", seq: seq, now: now)
        if seq > (newest?.r.seq ?? -1) { newest = (role, r) }
        continue
      }
      guard let robot = robots[role] else { continue }
      robot.hear(text: r.short ?? r.text ?? "", mood: r.mood ?? "calm", outcome: r.outcome ?? "said", seq: seq, now: now)
      director.outdoorRobots[role]?.hear(text: r.text ?? r.short ?? "", /* outdoors: the full line, never the server's clipped `short` */ mood: r.mood ?? "calm", outcome: r.outcome ?? "said", seq: seq, now: now)
      if seq > (newest?.r.seq ?? -1) { newest = (role, r) }
    }
    if let n = newest, let seq = n.r.seq, seq != captionSeq { showCaption(role: n.role, r: n.r, seq: seq) }
    refreshCards(st)
  }

  private func showCaption(role: String, r: VRState.Robot, seq: Int) {
    captionSeq = seq
    captionAt = now
    captionRole = role
    // The speech bubble beside the speaker (Robot) shows the text; this only keeps the sound cue.
    let deny = r.outcome == "deny"
    if deny || r.mood == "suspicious" { Sound.shared.play("alert", volume: 0.6) } else if r.outcome == "decided" { Sound.shared.decided() } else { Sound.shared.speak(role: role) }
  }

  private func setHover(_ node: SCNNode?) {
    guard node !== hovered else { return }
    if let h = hovered { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; h.scale = SCNVector3(1, 1, 1); SCNTransaction.commit() }
    hovered = node
    if let n = node { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.12; n.scale = SCNVector3(1.07, 1.07, 1.07); SCNTransaction.commit(); Sound.shared.play("hover", volume: 0.5) }
    refreshCards(latest)
  }

  /// The Cardboard button.
  private var lastTap: TimeInterval = -10

  func tap() {
    // Debounce: the conductive lever can bounce, and a choice must be sent once.
    guard now - lastTap > 0.35 else { return }
    lastTap = now
    taps += 1
    if let used = tapOutside() { lastTapText = used; return }
    guard cardsVisible, let h = hovered, let name = h.name, name.hasPrefix("card:"), let i = Int(name.dropFirst(5)), i < cardTargets.count, !cardTargets[i].esc.isEmpty else {
      if let role = hoveredRobot, now - (lastAsk[role] ?? -100) > 3 {
        lastAsk[role] = now
        lastTapText = "asked: \(role)"
        NSLog("[ask] %@", role)
        Sound.shared.play("select", volume: 0.6)
        onAsk?(role)
      } else {
        lastTapText = "tap"
      }
      return
    }
    guard now >= hideUntil else { return }
    let t = cardTargets[i]
    lastTapText = "chose: \(t.label)"
    hideUntil = now + 1.5
    Sound.shared.play("select", volume: 0.9)
    onDecide?(t.esc, t.opt)
    showCards(false)
  }

  /// Button presses that belong to part 1: closing the close-up, the scientist (no vr_ask), the pressure door.
  private func tapOutside() -> String? {
    guard director.isOutside else { return nil }
    if director.closeUp.isOpen {
      director.closeUp.close()
      Sound.shared.play("select", volume: 0.5)
      return "closed close-up"
    }
    switch hoveredSpecial {
    case "scientist":
      openCloseUpAtHead()
      return "close-up"
    case "door":
      Sound.shared.play("select", volume: 0.9)
      director.beginEnter(now: now, local: true)
      onEnter?()
      return "entering"
    default:
      return nil
    }
  }

  /// Opens the science close-up in front of the current head pose (the button, the spectator's mirror, a debug click).
  func openCloseUpAtHead() {
    let wf = (lastHeadView * viewOffset).inverse
    let fwd = -simd_normalize(SIMD3(wf.columns.2.x, wf.columns.2.y, wf.columns.2.z))
    director.openCloseUp(eye: SIMD3(wf.columns.3.x, wf.columns.3.y, wf.columns.3.z), forward: fwd, now: now)
  }

  /// The spectator mirrors the headset's close-up.
  func setCloseUpMirror(_ open: Bool) {
    if open && !director.closeUp.isOpen && director.isOutside { openCloseUpAtHead() }
    if !open && director.closeUp.isOpen { director.closeUp.close() }
  }

  private func showCards(_ on: Bool) {
    guard on != cardsVisible else { return }
    cardsVisible = on
    if on {
      cardRoot.isHidden = false
      cardRoot.runAction(.fadeIn(duration: 0.4))
      Sound.shared.play("saved", volume: 0.5)
    } else {
      cardRoot.runAction(.sequence([.fadeOut(duration: 0.3), .hide()]))
      setHover(nil)
    }
  }

  private func refreshCards(_ st: VRState?) {
    let waiting = director.isOutside ? nil : st?.waiting?.first
    let opts = Array((waiting?.options ?? []).prefix(cards.count))
    showCards(waiting != nil && !opts.isEmpty && now >= hideUntil)
    cardTargets = (0..<cards.count).map { i in
      if i < opts.count, let w = waiting { return (w.id, opts[i].id, opts[i].label, Self.firstSentence(opts[i].detail ?? ""), opts[i].proposedBy ?? "") }
      return ("", "", "", "", "")
    }
    for (i, p) in cardPanels.enumerated() {
      let t = cardTargets[i]
      cards[i].isHidden = t.esc.isEmpty
      let isHover = hovered === cards[i]
      p.update(key: "\(t.label)|\(t.detail)|\(t.by)|\(isHover)") { ctx, size in
        Draw.fill(ctx, CGRect(origin: .zero, size: size), isHover ? PlatformColor(red: 0.17, green: 0.13, blue: 0.06, alpha: 1) : PlatformColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1))
        ctx.setStrokeColor((isHover ? Palette.amber : PlatformColor(white: 1, alpha: 0.3)).cgColor)
        ctx.setLineWidth(isHover ? 16 : 5)
        ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
        _ = Draw.text(t.label, at: CGPoint(x: 40, y: 30), size: 58, weight: .heavy, color: isHover ? Palette.amber : Palette.text, width: size.width - 80, maxLines: 2)
        if !t.by.isEmpty {
          _ = Draw.text("proposed by \(t.by)", at: CGPoint(x: 40, y: 168), size: 35, weight: .bold, color: RobotCrew.color(forAgent: t.by) ?? Palette.violet, width: size.width - 80)
        }
        _ = Draw.text(t.detail, at: CGPoint(x: 40, y: 210), size: 44, weight: .semibold, color: Palette.dim, width: size.width - 80, maxLines: 3)
        if isHover { _ = Draw.text("Press the button to choose", at: CGPoint(x: 40, y: size.height - 76), size: 42, weight: .heavy, color: Palette.amber) }
      }
    }
  }

  /// Where the director camera should look (yaw right-positive, pitch up-positive, degrees).
  func directorTarget(now: TimeInterval) -> (Float, Float) {
    if cardsVisible { return (0, -4) }
    // Money just saved: show it on the MONEY screen.
    if now - savedChangedAt > 2.5 && now - savedChangedAt < 8 { return (60, 2) }
    if now - captionAt < 5, let role = captionRole {
      switch role {
      case "requester": return (-42, 0)
      case "receiver": return (-22, -10)
      case "ap": return (24, -8)
      case "treasury": return (46, 0)
      case "controller": return (12, 6)
      default: return (0, 0)
      }
    }
    return (0, 3)
  }

  static func firstSentence(_ s: String) -> String {
    if let r = s.range(of: ". ") { return String(s[..<r.lowerBound]) + "." }
    return s
  }

  private func updateDebug(link: Link, fps: Double) {
    let status = link.statusText, f = Int(fps.rounded()), tapCount = taps, tapText = lastTapText
    let seed = latest?.seed ?? "-", pv = latest?.policyVersion ?? 0
    let key = "\(status)|\(f)|\(tapCount)|\(tapText)|\(seed)"
    debug.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("ARES · \(status)", at: CGPoint(x: 30, y: 24), size: 44, weight: .bold, color: status.hasPrefix("Live") ? Palette.green : Palette.red, width: size.width - 60)
      _ = Draw.text("\(f) fps · taps \(tapCount) · \(tapText)", at: CGPoint(x: 30, y: 110), size: 40, weight: .semibold, width: size.width - 60)
      _ = Draw.text("Seed \(seed) · policy v\(pv)", at: CGPoint(x: 30, y: 190), size: 36, weight: .medium, color: Palette.dim)
      _ = Draw.text("Two-finger hold 2 s (out of the viewer) scans your viewer QR", at: CGPoint(x: 30, y: 270), size: 30, weight: .medium, color: Palette.dim, width: size.width - 60)
    }
  }
}
