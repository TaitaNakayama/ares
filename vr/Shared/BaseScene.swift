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
  /// A press on a show marker that the server acts on (`vr_tap`): "enter" in the opening panorama.
  var onTapTarget: ((String) -> Void)?
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
    if decisionCards.isActive { return decisionCards.gazedIndex }
    guard cardsVisible, let n = hovered?.name, n.hasPrefix("card:") else { return nil }
    return Int(n.dropFirst(5))
  }
  var cardsShown: Bool { cardsVisible || decisionCards.isActive }

  /// Part 1 (outside): the outdoor set, the walk, the scientist, the door. See Stations.swift.
  private(set) var director: OutdoorDirector!
  /// The show: title / window / end cards, the crisis in the world, the decision card's gaze. See Show.swift.
  private(set) var show: ShowDirector!
  /// The three-option decision card (Act 3). The legacy 4-card grid below stays for states without `decision` (old tapes).
  private let decisionCards = DecisionCards()
  /// Gaze rested 0.6 s on an option (its id), or left the card (nil): the headset sends `vr_gaze_option`.
  var onGazeOption: ((String?) -> Void)? { didSet { decisionCards.onGaze = onGazeOption } }
  /// False while a debug spike owns `viewOffset` (GroundSpike).
  var drivesView = true
  /// "scientist" or "door" while the reticle is on it (outside).
  private var hoveredSpecial: String?
  /// Called when the judge presses the door (the headset sends `vr_enter`).
  var onEnter: (() -> Void)?
  /// Free roam: the judge pressed a station pill.
  var onStation: ((String) -> Void)?
  private let interactiveMask = 1 << 3
  private let reticleHolder = SCNNode()
  private let reticle = SCNNode()
  let outside: Outside
  private let screens: WallScreens
  private var robots: [String: Robot] = [:]
  /// The five crew robots, their one speech bubble and the outdoor props (Crew.swift).
  private(set) var crew: Crew!
  private let debug = TextPanel(width: 1.6, height: 0.6, pixelsPerMeter: 600)
  /// Head-locked arrow toward a speaking robot that is outside the view. The spectator camera is wider than the head pose, so it turns this off.
  var showsSpeakerArrow = true
  /// False on the Mac spectator: its 2D card shows the options, so the 3D cards would show through it twice.
  var showsDecisionCards = true
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
    crew = Crew(root: scene.rootNode, outside: outside, scene: scene)
    robots = crew.bots
    buildReticle()
    buildCards()
    arrow.node.renderingOrder = 9_000
    scene.rootNode.addChildNode(arrow.node)
    debug.node.position = Room.ring(180, r: Room.radius - 0.1, y: 1.6)
    debug.node.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    scene.rootNode.addChildNode(debug.node)
    director = OutdoorDirector(scene: scene, outside: outside, indoorNodes: indoor + [debug.node, cardRoot], indoorRobots: [:])
    show = ShowDirector(scene: scene, outside: outside)
    scene.rootNode.addChildNode(decisionCards.root)
    adoptCrew()
  }

  /// The crew owns its robots in both sets: drop the director's two legacy outdoor robots and wire the crew to it.
  private func adoptCrew() {
    for r in director.outdoorRobots.values { r.node.removeFromParentNode(); r.bubble.node.removeFromParentNode() }
    crew.director = director
    crew.openCloseUp = { [unowned self] in self.openCloseUpAtHead() }
  }

  /// A full-view black quad on this camera node for the fade to black (the headset passes `head`, the Mac its camera).
  func attachFade(to camera: SCNNode) { director.attachFade(to: camera); show.attach(to: camera) }

  /// The robots the judge can see and gaze at: the two at their outdoor stations, or the five indoors.
  private var liveRobots: [Robot] { crew.liveBots }

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
    stepTau(now: time)
    show.update(now: time)
    crew.labelsHidden = show.labelsHidden
    if drivesView { viewOffset = director.viewOffset }
    lastHeadView = headView
    let worldFromHead = (headView * viewOffset).inverse
    let origin = SIMD3(worldFromHead.columns.3.x, worldFromHead.columns.3.y, worldFromHead.columns.3.z)
    let fwd = -simd_normalize(SIMD3(worldFromHead.columns.2.x, worldFromHead.columns.2.y, worldFromHead.columns.2.z))
    if !director.isOutside { decisionCards.update(now: time, eye: origin, fwd: fwd) }
    crew.decisionFrame = decisionCards.isActive ? decisionCards.placedYaw.map { ($0, decisionCards.placedEyeY) } : nil
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
        for (c, rad) in [(r.worldPosition, Float(0.34) * r.tagScale), (r.tagPosition, Float(0.2) * r.tagScale)] {
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
      director.markers.update(eye: origin, visible: director.markersVisible, current: director.station)
      if let m = director.markers.hit(origin: origin, fwd: fwd), m.d < (special?.d ?? .infinity) { special = ("marker:" + m.id, m.d) }
      if let s = special, let rh = robotHit, rh.d < s.d { special = nil }
      if special != nil { robotHit = nil }
    }
    hoveredSpecial = special?.id
    director.markers.setHover(special.flatMap { $0.id.hasPrefix("marker:") ? String($0.id.dropFirst(7)) : nil }, current: director.station)
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
    if decisionCards.isHit { dist = min(dist, 1.9) }
    reticleHolder.simdPosition = origin + fwd * dist
    reticleHolder.simdScale = SIMD3(repeating: dist * (hitNode != nil || robotHit != nil || special != nil || decisionCards.isHit ? 1.7 : 1.0))
    setHover(hitNode)
    let needs = (!(latest?.waiting ?? []).isEmpty || decisionCards.isActive) && !director.isOutside
    if (needs && !cardsVisible && now >= hideUntil) || (director.isOutside && cardsVisible) { refreshCards(latest) }
    let nowThinking = link.thinkingRoles
    if !nowThinking.subtracting(thinkingRoles).isEmpty { Sound.shared.thinkingStarted() }
    thinkingRoles = nowThinking
    if link.lastDecision != lastDecisionHeard {
      if decisionPrimed { Sound.shared.decided() }
      lastDecisionHeard = link.lastDecision
    }
    decisionPrimed = true
    crew.update(now: time, eye: origin, fwd: fwd, link: link, hovered: inStory ? nil : hoveredRobot, needsCommander: needs) // "tap to ask" is Act 4
    updateArrow(worldFromHead: worldFromHead)
    screens.update(latest, now: time, linkText: link.publicStatusText)
    updateDebug(link: link, fps: fps)
  }

  /// Head-locked arrow at the edge of the view toward the newest speaker, only while that robot is out of view.
  private func updateArrow(worldFromHead: simd_float4x4) {
    guard showsSpeakerArrow, let robot = crew.speakerBot(now: now) else { arrow.node.isHidden = true; return }
    let role = robot.role
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

  private var tauTarget = 0.6, tauApplied = 0.6, tauSun: (Double, Double) = (120, 45)
  private var tauShown: Double?
  private var lastTauStep: TimeInterval = 0

  /// Per frame: ease the shown dust toward the server's (up to 1 tau per second, i.e. the full storm in about 4 s).
  private func stepTau(now: TimeInterval) {
    let dt = min(0.1, max(0, now - lastTauStep))
    lastTauStep = now
    guard let shown = tauShown, shown != tauTarget else { return }
    let step = 1.0 * dt
    let next = abs(tauTarget - shown) <= step ? tauTarget : shown + (tauTarget > shown ? step : -step)
    tauShown = next
    if abs(next - tauApplied) >= 0.08 || next == tauTarget {
      tauApplied = next
      outside.apply(tau: next, sunAzimuth: tauSun.0, sunElevation: tauSun.1)
    }
  }

  private func applyState(_ st: VRState?) {
    guard let st else { return }
    if let saved = st.money?.savedText, saved != lastSaved {
      if !lastSaved.isEmpty { savedChangedAt = now; Sound.shared.play("saved", volume: 0.8) }
      lastSaved = saved
    }
    director.apply(st, now: now)
    let tauNow = ShowDirector.effectiveTau(st)
    // The dust rises over about 4 s instead of jumping (the storm wall grows over the rim as the Engineer warns).
    tauSun = (st.sun?.azimuth ?? 120, st.sun?.elevation ?? 45)
    tauTarget = tauNow
    if tauShown == nil { tauShown = tauNow; tauApplied = tauNow; outside.apply(tau: tauNow, sunAzimuth: tauSun.0, sunElevation: tauSun.1) }
    else { outside.apply(tau: tauApplied, sunAzimuth: tauSun.0, sunElevation: tauSun.1) }
    outside.show(Consequence.active(in: st))
    show.apply(st, now: now) // after the legacy consequences: the show contract's `world` has the last word
    Sound.shared.setStorm(tau: tauNow)
    crew.apply(st, now: now)
    decisionCards.apply(st.decision, crew: st.crew, now: now)
    if !showsDecisionCards { decisionCards.root.isHidden = true }
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

  /// The show's story acts: everything before Act 4 (`explore`); an old server without the show counts as Act 4.
  var inStory: Bool {
    guard let act = latest?.scene?.act else { return false }
    return act != "explore"
  }

  /// The Cardboard button.
  private var lastTap: TimeInterval = -10

  func tap() {
    // Debounce: the conductive lever can bounce, and a choice must be sent once.
    guard now - lastTap > 0.35 else { return }
    lastTap = now
    taps += 1
    // During the story (Acts 1-3) a press does nothing except on the door marker and the decision card; asking the crew,
    // the close-up and the reality check are Act 4.
    if latest?.scene?.act == "real" {
      // The opening: the press on "Tap to enter the simulation" starts the story (the server flips the panorama off).
      Sound.shared.play("select", volume: 0.9)
      onTapTarget?("enter")
      lastTapText = "enter the simulation"
      return
    }
    if inStory {
      // The one crew press in the story: Science's close-up (the real WATSON rock image) while Science glows.
      if latest?.scene?.cue == "science", let used = crew.handleTap(robot: hoveredRobot, now: now) { lastTapText = used; Sound.shared.play("select", volume: 0.7); return }
      if director.closeUp.isOpen, let used = tapOutside() { lastTapText = used; return } // page 2, then closed
      if let (esc, opt) = decisionCards.tap(now: now) {
        lastTapText = "chose: \(opt)"
        onDecide?(esc, opt)
        return
      }
      if let used = tapOutside(doorOnly: true) { lastTapText = used; return }
      lastTapText = "tap (story)"
      return
    }
    if let used = crew.handleTap(robot: hoveredRobot, now: now) { lastTapText = used; Sound.shared.play("select", volume: 0.7); return }
    if RealityCheck.shared.wantOn { RealityCheck.shared.set(false); lastTapText = "reality check off"; return } // any tap brings you back
    if let (esc, opt) = decisionCards.tap(now: now) {
      lastTapText = "chose: \(opt)"
      onDecide?(esc, opt)
      return
    }
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
  private func tapOutside(doorOnly: Bool = false) -> String? {
    guard director.isOutside else { return nil }
    if doorOnly {
      guard hoveredSpecial == "door" else { return nil }
      Sound.shared.play("select", volume: 0.9)
      director.beginEnter(now: now, local: true)
      onEnter?()
      return "entering"
    }
    if director.closeUp.isOpen {
      // Stereo page -> WATSON page -> closed.
      let turned = director.closeUp.advance()
      Sound.shared.play("select", volume: 0.5)
      return turned ? "close-up page 2" : "closed close-up"
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
      if let id = hoveredSpecial, id.hasPrefix("marker:") {
        let station = String(id.dropFirst(7))
        Sound.shared.play("select", volume: 0.7)
        if station == "rover" && director.station == "rover" { RealityCheck.toggle(); return "reality check" }
        director.goTo(station: station, now: now)
        onStation?(station)
        return "go: " + station
      }
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
    let waiting = (director.isOutside || st?.decision?.options?.isEmpty == false) ? nil : st?.waiting?.first
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

  /// World position of the centre console screen (the QUOTE card shows there), for the director camera.
  var quoteScreenPosition: SIMD3<Float> { screens.waiting.node.simdPosition }

  /// Where the director camera should look (yaw right-positive, pitch up-positive, degrees).
  func directorTarget(now: TimeInterval) -> (Float, Float) {
    if cardsVisible { return (0, -4) }
    // Money just saved: show it on the MONEY screen.
    if now - savedChangedAt > 2.5 && now - savedChangedAt < 8 { return (60, 2) }
    if let t = crew.directorLook(now: now) { return t }
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
    let status = link.publicStatusText, f = Int(fps.rounded()), tapCount = taps, tapText = lastTapText
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
