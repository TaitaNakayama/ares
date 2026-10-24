import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// One floating helper robot: an original silhouette per role, a dark screen face with two
/// expressive eyes, a glow halo in the role colour, and a speech bubble that faces the user.
final class Robot {
  let role: String
  let name: String
  let color: PlatformColor
  /// The agent colour pulled ~15% toward grey and a warm cast: shells, rings and halo use this so the crew sits in the room's palette.
  let tone: PlatformColor
  let node = SCNNode()
  private let body = SCNNode()
  private let face = SCNNode()
  private let eyeL = SCNNode()
  private let eyeR = SCNNode()
  private let eyeMat = SCNMaterial()
  private let faceMat = SCNMaterial()
  private let haloMat = SCNMaterial()
  private let home: SIMD3<Float>
  private let homeYaw: Float
  private var mood = "calm"
  private var lastSeq = -1
  private var spokeAt: TimeInterval = -100
  private var text = ""
  private var outcome = "said"
  private var nextBlink: TimeInterval = 2
  private let phase: Float
  private let nametag: Nametag
  private var thinking = false
  private var dots: [SCNNode] = []
  private let dotMat = SCNMaterial()
  private var halo: SCNNode!
    private var shells: [SCNMaterial] = []
  private var rimBase: Float = 0.55
  private var nextGlance: TimeInterval = 3
  private var glanceTo: Float = 0
  private var glance: Float = 0
  private var lean: Float = 0
  private var eyeX: Float = 0.05
  private var shadowNode: SCNNode!
  private static let shadowMat = Tex.decalMaterial(Tex.discShadow())
  /// Fresnel rim in the agent colour: one surface shader modifier on the shell, no extra geometry or lights.
  private static let rimShader = """
  #pragma arguments
  float rimK;
  float3 rimColor;
  #pragma body
  float f = pow(1.0 - saturate(dot(normalize(_surface.normal), normalize(_surface.view))), 2.6);
  _surface.emission.rgb += rimColor * (f * rimK);
  """
  /// Reticle is on this robot (set by the scene): the nametag offers "tap to ask".
  var hovered = false
  /// Speech bubble: lives in the scene root (not under the robot) so the robot's yaw does not turn it.
  let bubble = SpeechBubble()
  private var bubbleVisible = false
  private var bubbleTailLeft: Bool?
  private var shownText = ""
  private var tagY: Float = 0.62
  private var bubbleOffset = SIMD3<Float>(0, 0.2, 0)

  init(role: String, name: String, color: PlatformColor, at pos: SCNVector3, faceYaw: Float) {
    self.role = role
    self.name = name
    self.color = color
    tone = Robot.muted(color)
    home = SIMD3<Float>(pos)
    homeYaw = faceYaw
    phase = Float(abs(role.hashValue % 100)) / 100 * 6.28
    nametag = Nametag(name: name, role: role, color: color)
    node.position = pos
    node.simdEulerAngles.y = faceYaw
    node.addChildNode(body)
    buildBody()
    buildFace()
    // Halo ring under the body: cheap glow instead of bloom.
    haloMat.lightingModel = .constant
    haloMat.diffuse.contents = tone.withAlphaComponent(0.55)
    haloMat.blendMode = .add
    haloMat.writesToDepthBuffer = false
    halo = SCNNode(geometry: SCNTorus(ringRadius: 0.2, pipeRadius: 0.009))
    halo.geometry?.materials = [haloMat]
    halo.position = SCNVector3(0, -0.32, 0)
    node.addChildNode(halo)
    nametag.node.position = SCNVector3(0, 0.62, 0)
    node.addChildNode(nametag.node)
    // Drop shadow just under the pad/ring: a soft dark disc that grounds the floating halo against any background.
    shadowNode = SCNNode(geometry: SCNPlane(width: 0.95, height: 0.95))
    shadowNode.geometry?.materials = [Robot.shadowMat]
    shadowNode.eulerAngles.x = -.pi / 2
    shadowNode.opacity = 0.85
    shadowNode.position = SCNVector3(0, -0.40, 0)
    shadowNode.renderingOrder = 41
    node.addChildNode(shadowNode)
    setMood("calm", force: true)
  }

  static func muted(_ c: PlatformColor) -> PlatformColor {
    let (r, g, b, _) = c.rgba()
    let l = 0.30 * r + 0.59 * g + 0.11 * b
    let k: CGFloat = 0.15
    return PlatformColor(red: (r + (l - r) * k) * 1.0, green: (g + (l - g) * k) * 0.985, blue: (b + (l - b) * k) * 0.94, alpha: 1)
  }

  private func shell() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.shaderModifiers = [.surface: Robot.rimShader]
    setRim(m, color: tone, k: rimBase)
    shells.append(m)
    // Shell lightly tinted toward the role colour so each robot reads at a glance.
    let (r, g, b, _) = tone.rgba()
    m.diffuse.contents = PlatformColor(red: 0.80 + 0.18 * r, green: 0.80 + 0.18 * g, blue: 0.80 + 0.18 * b, alpha: 1)
    m.specular.contents = PlatformColor(white: 0.35, alpha: 1)  // satin: broad, soft highlight
    m.shininess = 0.28
    return m
  }

  private func setRim(_ m: SCNMaterial, color c: PlatformColor, k: Float) {
    let (r, g, b, _) = c.rgba()
    m.setValue(SCNVector3(r, g, b), forKey: "rimColor")
    m.setValue(NSNumber(value: k), forKey: "rimK")
  }

  /// Small brushed-metal part (collar, joint).
  private func metal() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = PlatformColor(white: 0.46, alpha: 1)
    m.specular.contents = PlatformColor(white: 0.9, alpha: 1)
    m.shininess = 0.55
    return m
  }

  private func accent() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = tone
    m.emission.contents = tone.withAlphaComponent(0.25)
    return m
  }

  private func buildBody() {
    let s = shell()
    let a = accent()
    switch role {
    case "requester": // Engineer: rounded cube with an antenna
      let b = SCNNode(geometry: SCNBox(width: 0.36, height: 0.34, length: 0.32, chamferRadius: 0.09))
      b.geometry?.materials = [s]
      body.addChildNode(b)
      let stem = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.16))
      stem.geometry?.materials = [a]
      stem.position = SCNVector3(0.08, 0.25, 0)
      body.addChildNode(stem)
      let dish = SCNNode(geometry: SCNCone(topRadius: 0.06, bottomRadius: 0.01, height: 0.05))
      dish.geometry?.materials = [a]
      dish.position = SCNVector3(0.08, 0.34, 0)
      body.addChildNode(dish)
      let ear = SCNNode(geometry: SCNBox(width: 0.04, height: 0.12, length: 0.14, chamferRadius: 0.02))
      ear.geometry?.materials = [a]
      ear.position = SCNVector3(-0.2, 0, 0)
      body.addChildNode(ear)
    case "receiver": // Cargo: wide capsule with a cargo-bay belt
      let b = SCNNode(geometry: SCNCapsule(capRadius: 0.16, height: 0.52))
      b.geometry?.materials = [s]
      b.eulerAngles.z = .pi / 2
      body.addChildNode(b)
      let belt = SCNNode(geometry: SCNTorus(ringRadius: 0.163, pipeRadius: 0.02))
      belt.geometry?.materials = [a]
      belt.eulerAngles.z = .pi / 2
      body.addChildNode(belt)
      for x in [-0.27, 0.27] as [Float] {
        let pod = SCNNode(geometry: SCNSphere(radius: 0.05))
        pod.geometry?.materials = [a]
        pod.position = SCNVector3(x, 0, 0)
        body.addChildNode(pod)
      }
    case "ap": // Bills: tall slim pill with a scanner visor
      let b = SCNNode(geometry: SCNCapsule(capRadius: 0.13, height: 0.5))
      b.geometry?.materials = [s]
      body.addChildNode(b)
      let band = SCNNode(geometry: SCNTorus(ringRadius: 0.132, pipeRadius: 0.012))
      band.geometry?.materials = [a]
      band.position = SCNVector3(0, -0.12, 0)
      body.addChildNode(band)
    case "treasury": // Money: a coin on edge with a rim
      let b = SCNNode(geometry: SCNCylinder(radius: 0.21, height: 0.09))
      b.geometry?.materials = [s]
      b.eulerAngles.x = .pi / 2
      body.addChildNode(b)
      let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.21, pipeRadius: 0.022))
      rim.geometry?.materials = [a]
      rim.eulerAngles.x = .pi / 2
      body.addChildNode(rim)
    default: // controller, Rules: hexagonal prism with a crown band
      let hex = SCNCylinder(radius: 0.2, height: 0.42)
      hex.radialSegmentCount = 6
      let b = SCNNode(geometry: hex)
      b.geometry?.materials = [s]
      body.addChildNode(b)
      let cap = SCNCylinder(radius: 0.205, height: 0.05)
      cap.radialSegmentCount = 6
      let c = SCNNode(geometry: cap)
      c.geometry?.materials = [a]
      c.position = SCNVector3(0, 0.2, 0)
      body.addChildNode(c)
    }
    // Brushed-metal emitter collar under the shell, where the halo hangs from.
    let low: Float = ["requester": -0.17, "receiver": -0.16, "ap": -0.26, "treasury": -0.21][role] ?? -0.21
    let collar = SCNNode(geometry: SCNCylinder(radius: 0.055, height: 0.035))
    collar.geometry?.materials = [metal()]
    collar.position = SCNVector3(0, low, 0)
    body.addChildNode(collar)
    let joint = SCNNode(geometry: SCNTorus(ringRadius: 0.055, pipeRadius: 0.008))
    joint.geometry?.materials = [metal()]
    joint.position = SCNVector3(0, low - 0.018, 0)
    body.addChildNode(joint)
  }

  private func buildFace() {
    faceMat.lightingModel = .constant
    faceMat.diffuse.contents = PlatformColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
    let plate = SCNPlane(width: 0.24, height: 0.15)
    plate.cornerRadius = 0.05
    plate.materials = [faceMat]
    face.geometry = plate
    let z: Float
    switch role {
    case "receiver": z = 0.165
    case "treasury": z = 0.05
    case "ap": z = 0.135
    case "requester": z = 0.165
    default: z = 0.18
    }
    face.position = SCNVector3(0, role == "ap" ? 0.08 : 0.02, z)
    body.addChildNode(face)
    // Glass: a faint diagonal specular streak over the plate (additive, no light needed).
    let glassMat = SCNMaterial()
    glassMat.lightingModel = .constant
    glassMat.blendMode = .add
    glassMat.writesToDepthBuffer = false
    glassMat.diffuse.contents = PlatformColor(white: 0.16, alpha: 1)
    let streak = SCNNode(geometry: SCNPlane(width: 0.035, height: 0.2))
    streak.geometry?.materials = [glassMat]
    streak.simdEulerAngles.z = -0.5
    streak.position = SCNVector3(-0.07, 0.01, 0.006)
    face.addChildNode(streak)
    eyeMat.lightingModel = .constant
    eyeMat.diffuse.contents = PlatformColor.white
    // One eye shape per robot: round, oval, slit, rounded square, visor.
    let (ew, eh, er, ex): (CGFloat, CGFloat, CGFloat, Float)
    switch role {
    case "requester": (ew, eh, er, ex) = (0.056, 0.056, 0.028, 0.05)     // round
    case "receiver": (ew, eh, er, ex) = (0.040, 0.074, 0.020, 0.05)      // tall oval
    case "ap": (ew, eh, er, ex) = (0.072, 0.022, 0.011, 0.055)           // slit
    case "treasury": (ew, eh, er, ex) = (0.054, 0.054, 0.013, 0.05)      // rounded square
    default: (ew, eh, er, ex) = (0.084, 0.034, 0.016, 0.0415)            // visor: two wide halves that meet
    }
    eyeX = ex
    for (e, x) in [(eyeL, -ex), (eyeR, ex)] {
      let g = SCNPlane(width: ew, height: eh)
      g.cornerRadius = er
      g.materials = [eyeMat]
      e.geometry = g
      e.position = SCNVector3(x, 0, 0.002)
      face.addChildNode(e)
    }
    // Thinking face: three dots that pulse in turn (shown instead of the eyes).
    dotMat.lightingModel = .constant
    dotMat.diffuse.contents = PlatformColor(red: 0.75, green: 0.90, blue: 1.0, alpha: 1)
    for x in [Float(-0.06), 0, 0.06] {
      let d = SCNNode(geometry: SCNSphere(radius: 0.017))
      d.geometry?.materials = [dotMat]
      d.position = SCNVector3(x, -0.005, 0.004)
      d.isHidden = true
      face.addChildNode(d)
      dots.append(d)
    }
  }

  private func setThinking(_ on: Bool) {
    thinking = on
    eyeL.isHidden = on
    eyeR.isHidden = on
    for d in dots { d.isHidden = !on }
    if !on {
      halo.scale = SCNVector3(1, 1, 1)
      setMood(mood, force: true)
    }
  }

  func setMood(_ m: String, force: Bool = false) {
    guard force || m != mood else { return }
    mood = m
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.25
    var eyeColor = PlatformColor.white
    var sy: Float = 1, rotL: Float = 0, rotR: Float = 0, dy: Float = 0
    var faceGlow = PlatformColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
    var halo = tone.withAlphaComponent(0.55)
    var rimC = tone
    switch m {
    case "worried":
      eyeColor = PlatformColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1); sy = 0.85; rotL = -0.35; rotR = 0.35; dy = 0.006
    case "suspicious":
      eyeColor = PlatformColor(red: 1.0, green: 0.30, blue: 0.25, alpha: 1); sy = 0.32; rotL = 0.18; rotR = -0.18
      faceGlow = PlatformColor(red: 0.22, green: 0.02, blue: 0.02, alpha: 1); halo = PlatformColor(red: 1, green: 0.2, blue: 0.15, alpha: 0.8); rimC = PlatformColor(red: 1, green: 0.2, blue: 0.15, alpha: 1)
    case "attentive":
      eyeColor = PlatformColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1); sy = 1.18
    case "happy":
      eyeColor = PlatformColor(red: 0.55, green: 1.0, blue: 0.70, alpha: 1); sy = 0.42; dy = 0.01
    default:
      break
    }
    eyeMat.diffuse.contents = eyeColor
    faceMat.diffuse.contents = faceGlow
    haloMat.diffuse.contents = halo
    for m in shells { setRim(m, color: rimC, k: rimBase) }
    eyeL.scale = SCNVector3(1, sy, 1)
    eyeR.scale = SCNVector3(1, sy, 1)
    eyeL.simdEulerAngles.z = rotL
    eyeR.simdEulerAngles.z = rotR
    eyeL.simdPosition.y = dy
    eyeR.simdPosition.y = dy
    SCNTransaction.commit()
  }

  /// Speaking window: the same 9 s the robot turns to the user for.
  func isSpeaking(now: TimeInterval) -> Bool { now - spokeAt < 9 && !text.isEmpty }
  /// Where the robot hovers, in scene coordinates.
  var worldPosition: SIMD3<Float> { node.simdPosition }

  func hear(text: String, mood: String, outcome: String, seq: Int, now: TimeInterval) {
    guard seq != lastSeq else { return }
    lastSeq = seq
    self.text = text
    self.outcome = outcome
    spokeAt = now
    setMood(outcome == "deny" ? "attentive" : mood)
    haloMat.diffuse.contents = (mood == "suspicious" ? PlatformColor(red: 1, green: 0.2, blue: 0.15, alpha: 1) : tone).withAlphaComponent(0.9)
    body.runAction(.sequence([.moveBy(x: 0, y: 0.06, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.06, z: 0, duration: 0.2)]))
  }

  /// The bubble floats beside the robot, toward the middle of the room so it stays in view,
  /// turned to face the viewer, with its tail pointing back at the robot.
  private func updateBubble(now: TimeInterval, user: SIMD3<Float>, speaking: Bool) {
    if speaking != bubbleVisible {
      bubbleVisible = speaking
      bubble.node.removeAllActions()
      if speaking {
        bubble.node.isHidden = false
        bubble.node.runAction(.fadeIn(duration: 0.2))
      } else {
        bubble.node.runAction(.sequence([.fadeOut(duration: 0.4), .hide()]))
      }
    }
    guard speaking else { return }
    let p = node.simdPosition
    var radial = SIMD3(p.x - user.x, 0, p.z - user.z)
    radial = simd_length(radial) > 0.01 ? simd_normalize(radial) : SIMD3(0, 0, -1)
    let right = SIMD3<Float>(-radial.z, 0, radial.x)
    let bubbleToRight = p.x < 0 // robots on the left put the bubble to their right, and vice versa
    let side: Float = bubbleToRight ? 1 : -1
    let w = Float(SpeechBubble.w)
    let base = p + right * side * (w / 2 + 0.28) - radial * 0.15
    // Keep clear of the wall screens (as seen from the commander): try raising, lowering or pushing outward.
    var best = SIMD3<Float>(0, 0.2, 0), bestArea = Float.infinity
    search: for dx in [Float(0), 0.35, 0.7] {
      for dy in [Float(0.2), 0.5, 0.8, -0.55, -0.85] {
        let off = right * side * dx + SIMD3(0, dy, 0)
        let a = ScreenRects.overlap(center: base + off, w: w, h: Float(SpeechBubble.h), user: user)
        if a < bestArea { bestArea = a; best = SIMD3(dx, dy, 0) }
        if a == 0 { break search }
      }
    }
    let target = right * side * best.x + SIMD3(0, best.y, 0)
    bubbleOffset += (target - bubbleOffset) * 0.12
    let c = base + bubbleOffset
    bubble.node.simdPosition = c
    let toUser = user - c
    bubble.node.simdEulerAngles = SIMD3(0, atan2(toUser.x, toUser.z), 0)
    let tailLeft = bubbleToRight
    if bubbleTailLeft != tailLeft || shownText != text {
      bubbleTailLeft = tailLeft
      shownText = text
      bubble.set(text: text, name: name, color: color, deny: outcome == "deny", tailLeft: tailLeft, key: "\(text)|\(outcome)")
    }
  }

  func update(now: TimeInterval, user: SIMD3<Float>, needsCommander: Bool, bubbleWanted: Bool = true, thinking think: Bool = false) {
    let t = Float(now)
    if think != thinking { setThinking(think) }
    if thinking {
      // Slow pulse of the halo (size and brightness) and a travelling dot on the face.
      let k = 0.5 + 0.5 * sin(t * 2.4)
      halo.scale = SCNVector3(1 + 0.12 * k, 1 + 0.12 * k, 1 + 0.12 * k)
      haloMat.diffuse.contents = PlatformColor(red: 0.55 + 0.4 * CGFloat(k), green: 0.80 + 0.2 * CGFloat(k), blue: 1.0, alpha: 0.35 + 0.65 * CGFloat(k))
      for (i, d) in dots.enumerated() {
        let a = Float(max(0, sin(t * 5 - Float(i) * 0.9)))
        let sc = 0.7 + 0.9 * a
        d.scale = SCNVector3(sc, sc, sc)
      }
    }
    nametag.setSuffix(thinking ? " · thinking…" : hovered ? " · tap to ask" : "")
    node.simdPosition = SIMD3(home.x, home.y + 0.035 * sin(t * 1.3 + phase), home.z)
    // Turn toward the user while speaking or when a decision is waiting; otherwise face the work.
    let speaking = now - spokeAt < 9
    let toUser = user - node.simdPosition
    let yawUser = atan2(toUser.x, toUser.z)
    let target = speaking || needsCommander ? yawUser : homeYaw
    var dyaw = target - node.simdEulerAngles.y
    while dyaw > .pi { dyaw -= 2 * .pi }
    while dyaw < -.pi { dyaw += 2 * .pi }
    node.simdEulerAngles.y += dyaw * 0.08
    updateBubble(now: now, user: user, speaking: speaking && !text.isEmpty && bubbleWanted)
    // Nametag billboard: always faces the viewer, upright (the parent yaw is undone).
    nametag.node.simdEulerAngles.y = yawUser - node.simdEulerAngles.y
    // Keep the tag off the wall screens: try above, higher, then below the robot; fade to 40% if nothing clears.
    var tagTarget: Float = 0.62, tagFade: CGFloat = 1, bestArea = Float.infinity
    let np = node.simdPosition
    for ty in [Float(0.62), 0.8, 1.0, -0.55, -0.75] {
      let a = ScreenRects.overlap(center: np + SIMD3(0, ty, 0), w: 1.12, h: 0.17, user: user)
      if a < bestArea { bestArea = a; tagTarget = ty }
      if a == 0 { break }
    }
    if bestArea > 0 { tagFade = 0.4 }
    tagY += (tagTarget - tagY) * 0.12
    nametag.node.simdPosition = SIMD3(0, tagY, 0)
    nametag.node.opacity += (tagFade - nametag.node.opacity) * 0.15
    if !speaking && spokeAt > 0 && now - spokeAt < 9.2 && mood != "suspicious" { setMood(needsCommander ? "attentive" : "calm") }
    // Lean toward the commander and brighten the rim while speaking; pulse when the action went through.
    let dt = Float(now - spokeAt)
    lean += ((speaking && !text.isEmpty ? 1 : 0) - lean) * 0.06
    body.simdEulerAngles.x = 0.1 * lean
    var pulse: Float = 0
    if outcome == "allow" { pulse = 0.9 * max(0, 1 - dt / 1.5) * (0.5 + 0.5 * sin(dt * 7 - 1.57)) }
    else if outcome == "deny" { pulse = 0.35 * max(0, 1 - dt / 2.8) * (0.5 + 0.5 * sin(dt * 3.2 - 1.57)) }
    let boost = 0.7 * max(0, 1 - dt / 1.2) + 0.25 * lean
    let rim = rimBase + boost + pulse
    for m in shells { m.setValue(NSNumber(value: rim), forKey: "rimK") }
    if !thinking {
      let hs = 1 + 0.25 * pulse
      halo.scale = SCNVector3(hs, hs, hs)
    }
    // Eyes glance: toward the commander (or the speaker's side) when engaged, otherwise drift now and then.
    if now > nextGlance {
      nextGlance = now + Double.random(in: 1.5...4.5)
      glanceTo = Float.random(in: 0...1) < 0.4 ? 0 : Float.random(in: -1...1)
    }
    var gx = glanceTo
    if speaking || needsCommander { gx = max(-1, min(1, sin(yawUser - node.simdEulerAngles.y) * 3)) }
    glance += (gx - glance) * 0.15
    eyeL.simdPosition.x = -eyeX + 0.012 * glance
    eyeR.simdPosition.x = eyeX + 0.012 * glance
    if now > nextBlink {
      nextBlink = now + Double.random(in: 3...7)
      let s = eyeL.scale.y
      let blink = SCNAction.sequence([.customAction(duration: 0.07) { n, _ in n.scale.y = s * 0.1 }, .wait(duration: 0.07), .customAction(duration: 0.01) { n, _ in n.scale.y = s }])
      eyeL.runAction(blink)
      eyeR.runAction(blink)
    }
  }
}

enum RobotCrew {
  /// The colour of the agent with this display name (e.g. "Rules"; the pre-rename names still resolve for old tapes); nil for an unknown name.
  static func color(forAgent name: String) -> PlatformColor? {
    let legacy = ["cargo keeper": "receiver", "bill checker": "ap", "money keeper": "treasury", "rule keeper": "controller"]
    if let r = legacy[name.lowercased()] { return Palette.role(r) }
    return layout.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { Palette.role($0.role) }
  }

  /// Angle (deg, 0 = straight ahead), distance and height for each role.
  static let layout: [(role: String, name: String, deg: Float, r: Float, y: Float)] = [
    ("requester", "Engineer", -48, 2.45, 1.38),
    ("receiver", "Cargo", -27, 2.75, 1.02),
    ("controller", "Rules", 16, 2.45, 2.12),
    ("ap", "Bills", 31, 2.75, 1.10),
    ("treasury", "Money", 50, 2.45, 1.38),
  ]

  static func build(into root: SCNNode) -> [String: Robot] {
    var out: [String: Robot] = [:]
    for l in layout {
      let pos = Room.ring(l.deg, r: l.r, y: l.y)
      // Face slightly outward toward the window/screens when idle.
      // Idle: turned ~40 degrees toward its work; it turns to the user when it speaks.
      let yaw = atan2(Float(-pos.x), Float(-pos.z)) + (l.deg == 0 ? 0 : (l.deg > 0 ? 0.7 : -0.7))
      let r = Robot(role: l.role, name: l.name, color: Palette.role(l.role), at: pos, faceYaw: yaw)
      root.addChildNode(r.node)
      root.addChildNode(r.bubble.node)
      out[l.role] = r
    }
    return out
  }
}
