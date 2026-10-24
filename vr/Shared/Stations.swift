import SceneKit
import QuartzCore
import simd

/// Part 1 of the demo, outside. Owns the outdoor set, the judge's walk between the four stations, the
/// outdoor robots (Cargo at the pad, Engineer at the solar field), the scientist and his close-up,
/// the pressure door, and the switch inside (approach, 0.5 s fade to black, fade back in).
/// `BaseScene` calls into it from `update` / `applyState` / `tap`; everything it draws is hidden while inside.
final class OutdoorDirector {
  enum Part { case outside, inside }

  private(set) var part: Part = .inside
  private(set) var station: String?
  private(set) var science: VRState.Science?
  private var journey = Journey(at: Spots.start)
  let set: OutdoorSet
  let scientist: Scientist
  let closeUp = CloseUpPanel()
  /// Cargo and Engineer, standing at their stations (second copies of the indoor robots).
  private(set) var outdoorRobots: [String: Robot] = [:]
  private let outside: Outside
  private var indoorNodes: [SCNNode] = []
  private var indoorRobots: [String: Robot] = [:]
  private var hiddenBubbles: [Robot] = []
  private var fadeNodes: [SCNNode] = []
  private(set) var fade: Float = 1
  private var fadeTarget: Float = 1
  private var gotState = false
  private var bootAt: TimeInterval = 0
  private var lastNow: TimeInterval = 0
  private var appliedPart: Part?
  /// The Mac spectator takes the head from the headset's stream instead of its own walk.
  var externalHead: (pos: SIMD3<Float>, yaw: Float)?
  /// Entering: glide to the door, fade out, switch.
  private enum Enter { case none, approach(start: TimeInterval, dur: Double), fadeOut(start: TimeInterval), black(until: TimeInterval) }
  private var enter: Enter = .none
  private var latchedInsideUntil: TimeInterval = 0
  private(set) var eye = SIMD3<Float>(0, 1.6, 0)
  private(set) var yaw: Float = 0
  var doorHovered = false

  init(scene: SCNScene, outside: Outside, indoorNodes: [SCNNode], indoorRobots: [String: Robot]) {
    self.outside = outside
    self.indoorNodes = indoorNodes
    self.indoorRobots = indoorRobots
    set = OutdoorSet(outside: outside, scene: scene)
    let sp = Spots.scientist
    scientist = Scientist(at: SIMD3(sp.x, outside.groundY(sp.x, sp.y), sp.y), facing: atan2(Spots.outcrop.x - sp.x, Spots.outcrop.y - sp.y))
    scene.rootNode.addChildNode(scientist.node)
    scene.rootNode.addChildNode(scientist.bubble.node)
    scene.rootNode.addChildNode(closeUp.node)
    for (role, name, p, look) in [("receiver", "Cargo", Spots.cargoKeeper, Spots.crates), ("requester", "Engineer", Spots.engineer, Spots.fieldCenter)] {
      let y = outside.groundY(p.x, p.y) + (role == "receiver" ? 1.3 : 1.45)
      let r = Robot(role: role, name: name, color: Palette.role(role), at: SCNVector3(p.x, y, p.y), faceYaw: atan2(look.x - p.x, look.y - p.y))
      scene.rootNode.addChildNode(r.node)
      scene.rootNode.addChildNode(r.bubble.node)
      outdoorRobots[role] = r
      // Outdoors the judge is 5 to 30 m away: tags and bubbles are 2.5x their indoor size (the robot puts its bubble to the
      // right when it stands at x < 0, so the tail is then on the left).
      if let tag = r.node.childNode(withName: "nametag", recursively: true) {
        let k = SCNFloat(Self.labelScale)
        tag.scale = SCNVector3(k, k, k)
        let lift: SCNFloat = -0.085 * (1 - 1 / k)
        tag.pivot = SCNMatrix4MakeTranslation(0, lift, 0)
      }
      r.bubble.enlarge(Self.bubbleScale, tailLeft: p.x < 0, lift: 1.3) // above the 2.5x nametag, not over it
    }
    closeUp.configure(nil)
    applyPartVisibility(.inside)
    appliedPart = nil
  }

  static let labelScale: CGFloat = 2.5
  /// Speech bubbles outdoors: 1.3x the old 2.5x, plus a bigger header (see `SpeechBubble.enlarge`).
  static let bubbleScale: CGFloat = 3.2

  var isOutside: Bool { part == .outside }
  /// The glide is in progress (or the door sequence is running).
  var isWalking: Bool { journey.moving }
  var isEntering: Bool { if case .none = enter { return false }; return true }
  /// The door can be pressed: the story is at the door and the judge is within reach of it.
  var doorArmed: Bool {
    guard isOutside, station == "door", !isEntering else { return false }
    return simd_distance(SIMD2(eye.x, eye.z), Spots.door.pos) < 3.5
  }

  /// A full-view black quad that fades the picture; one per camera that needs it.
  func attachFade(to parent: SCNNode) {
    let q = SCNNode(geometry: SCNPlane(width: 6, height: 6))
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = PlatformColor.black
    m.readsFromDepthBuffer = false
    m.writesToDepthBuffer = false
    q.geometry?.materials = [m]
    q.position = SCNVector3(0, 0, -0.25)
    q.renderingOrder = 30_000
    q.opacity = CGFloat(fade)
    q.isHidden = fade <= 0.001
    parent.addChildNode(q)
    fadeNodes.append(q)
  }

  // ---------------------------------------------------------------- state from the server

  func apply(_ st: VRState, now: TimeInterval) {
    science = st.scene?.science
    closeUp.configure(science)
    scientist.setName(science?.scientist)
    let wantPart: Part = (st.scene?.part ?? "inside") == "outside" ? .outside : .inside
    let wantStation = st.scene?.station
    if !gotState {
      gotState = true
      station = wantStation
      setPart(wantPart, now: now, snap: true)
      fadeTarget = 0
      return
    }
    if wantPart != part {
      if wantPart == .outside && now < latchedInsideUntil { return } // the server has not caught up with the door tap yet
      if wantPart == .inside {
        beginEnter(now: now)
      } else {
        station = wantStation
        setPart(.outside, now: now, snap: true) // a reset: back to the start
        fadeTarget = 0
        fade = 1
      }
      return
    }
    if part == .outside && wantStation != station {
      station = wantStation
      if !isEntering { journey.go(to: Spots.spot(station) ?? Spots.start, now: now) }
    }
  }

  /// First frame with no server in sight (offline): the old room.
  private func bootIfNoState(now: TimeInterval) {
    if bootAt == 0 { bootAt = now }
    if !gotState && now - bootAt > 4 {
      gotState = true
      setPart(.inside, now: now, snap: true)
      fadeTarget = 0
    }
  }

  private func setPart(_ p: Part, now: TimeInterval, snap: Bool) {
    part = p
    enter = .none
    if p == .outside {
      let s = Spots.spot(station) ?? Spots.start
      journey = Journey(at: s)
      journey.go(to: s, now: now, snap: true)
    } else {
      closeUp.close()
      journey = Journey(at: Spots.start)
    }
    applyPartVisibility(p)
  }

  // ---------------------------------------------------------------- entering the base

  /// The door tap (or the server saying the story is inside): glide the last metres, fade, switch.
  func beginEnter(now: TimeInterval, local: Bool = false) {
    guard part == .outside, !isEntering else { return }
    if local { latchedInsideUntil = now + 6 }
    closeUp.close()
    let d = simd_distance(SIMD2(eye.x, eye.z), Spots.doorStep.pos)
    if d < 14 {
      journey.go(to: Spots.doorStep, now: now, speed: 1.4)
      enter = .approach(start: now, dur: Double(d / 1.4 + 0.25))
    } else {
      fadeTarget = 1
      enter = .fadeOut(start: now)
    }
  }

  // ---------------------------------------------------------------- per frame

  /// Advances the walk, the door sequence and the fade; returns nothing, read `viewOffset` afterwards.
  func update(now: TimeInterval) {
    let dt = Float(min(0.1, max(0, now - lastNow)))
    lastNow = now
    bootIfNoState(now: now)
    switch enter {
    case .approach(let start, let dur):
      if now - start >= dur { fadeTarget = 1; enter = .fadeOut(start: now) }
    case .fadeOut(let start):
      if fade >= 0.999 && now - start >= 0.45 { enter = .black(until: now + 0.15) }
    case .black(let until):
      if now >= until {
        setPart(.inside, now: now, snap: true)
        fade = 1
        fadeTarget = 0
        enter = .none
      }
    case .none: break
    }
    // The fade: 0.5 s to black, 0.7 s back.
    let rate: Float = fadeTarget > fade ? 2.0 : 1.4
    if fade < fadeTarget { fade = min(fadeTarget, fade + rate * dt) } else if fade > fadeTarget { fade = max(fadeTarget, fade - rate * dt) }
    for n in fadeNodes {
      n.opacity = CGFloat(fade)
      n.isHidden = fade <= 0.001
    }
    // The head.
    if let ext = externalHead {
      eye = ext.pos
      yaw = ext.yaw
    } else if part == .outside {
      journey.step(now: now)
      let p = journey.pos
      eye = SIMD3(p.x, outside.groundY(p.x, p.y) + 1.6, p.y)
      yaw = journey.yaw
    } else {
      eye = SIMD3(0, 1.6, 0)
      yaw = 0
    }
    if part == .outside {
      set.updateRocks(eye: eye)
      set.setDoor(armed: doorArmed, hovered: doorHovered && doorArmed)
      outside.followJudge(eye)
    }
  }

  /// Head position and yaw as a matrix for `BaseScene.viewOffset` (worldFromHead = inverse(headView * viewOffset)).
  var viewOffset: simd_float4x4 {
    var t = matrix_identity_float4x4
    t.columns.3 = SIMD4(-eye.x, -eye.y, -eye.z, 1)
    return simd_float4x4(simd_quatf(angle: -yaw, axis: SIMD3(0, 1, 0))) * t
  }

  // ---------------------------------------------------------------- what is visible where

  private func applyPartVisibility(_ p: Part) {
    guard p != appliedPart else { return }
    appliedPart = p
    let out = p == .outside
    for n in indoorNodes { n.isHidden = out }
    for r in indoorRobots.values {
      r.node.isHidden = out
      if out {
        if !r.bubble.node.isHidden { hiddenBubbles.append(r) }
        r.bubble.node.isHidden = true
      }
    }
    if !out {
      for r in hiddenBubbles { r.bubble.node.isHidden = false }
      hiddenBubbles = []
    }
    for r in outdoorRobots.values { r.node.isHidden = !out; if !out { r.bubble.node.isHidden = true } }
    scientist.node.isHidden = !out
    if !out { scientist.bubble.node.isHidden = true }
    set.outdoorOnly.isHidden = !out
    set.habitat.isHidden = !out
    outside.setOutdoor(out)
    Sound.shared.setOutside(out)
  }

  // ---------------------------------------------------------------- gaze targets

  /// Distance along the ray (origin, fwd) to the scientist (body or nametag), if it is under the reticle.
  func scientistHit(origin: SIMD3<Float>, fwd: SIMD3<Float>) -> Float? {
    guard isOutside else { return nil }
    var best: Float?
    for (c, rad) in [(scientist.worldPosition, Float(0.75)), (scientist.tagPosition, Float(0.38))] {
      let t = simd_dot(c - origin, fwd)
      guard t > 0.3, t < 14, simd_length(c - (origin + fwd * t)) < rad else { continue }
      if t < (best ?? .infinity) { best = t }
    }
    return best
  }

  /// Distance to the pressure door when the ray hits its face (a 1.9 x 2.7 m plate, a little generous).
  func doorHit(origin: SIMD3<Float>, fwd: SIMD3<Float>) -> Float? {
    guard doorArmed, fwd.z > 0.05 else { return nil }
    let gy = outside.groundY(0, Spots.doorFaceZ)
    let t = (Spots.doorFaceZ - origin.z) / fwd.z
    guard t > 0.3, t < 12 else { return nil }
    let p = origin + fwd * t
    guard abs(p.x) < 1.3, p.y > gy - 0.2, p.y < gy + 3.3 else { return nil }
    return t
  }

  func openCloseUp(eye: SIMD3<Float>, forward: SIMD3<Float>, now: TimeInterval) {
    closeUp.open(eye: eye, forward: forward, now: now)
    Sound.shared.play("select", volume: 0.6)
  }
}
