import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// One crew robot (engineer, life, science, supply, rules): an original silhouette per agent, a dark screen face with two
/// expressive eyes, a rim glow in the agent colour and a nametag (icon + one word). It is a puppet: `Crew` decides where it
/// floats, what it looks at, whether it speaks, and `update` makes it move like a creature (bob, job motion, glances).
final class Robot {
  /// Crew id: engineer | life | science | supply | rules.
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
  private let phase: Float
  private let nametag: Nametag
  private var dots: [SCNNode] = []
  private let dotMat = SCNMaterial()
  private var halo: SCNNode!
  private var shells: [SCNMaterial] = []
  private var rimBase: Float = 0.55
  private var shadowNode: SCNNode!
  private var cueHalo: SCNNode?
  private var arm: SCNNode?
  private var bit: SCNNode?
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

  // ---- puppet inputs (set by Crew every frame)
  /// Reticle is on this robot: the nametag offers "tap to ask".
  var hovered = false
  /// What it is doing: plants | panel | crates | bench | console | rock | lander | judge | idle.
  var task = "idle"
  /// World point to look at; nil = face the work (`homeYaw`).
  var lookPoint: SIMD3<Float>?
  var homeYaw: Float = 0
  /// Where it floats (the robot glides there).
  var target: SIMD3<Float>
  /// Glides at most this fast (m/s).
  var maxSpeed: Float = 1.6
  var speaking = false
  var cueOn = false
  var thinking = false
  /// Nametag size multiplier (outdoors the judge is metres away).
  var tagScale: Float = 1
  /// Science only: the grinding arm is out.
  var armOut = false
  var mood = "calm"
  /// 0...1, fades in and out when the robot changes place.
  var alpha: Float = 1 { didSet { if alpha != oldValue { applyAlpha() } } }

  // ---- state
  private(set) var pos: SIMD3<Float>
  private var yaw: Float
  private var shownMood = ""
  private var wasThinking = false
  private var nextBlink: TimeInterval = 2
  private var nextGlance: TimeInterval = 3
  private var glanceTo: Float = 0
  private var glance: Float = 0
  private var lean: Float = 0
  private var eyeX: Float = 0.05
  private var tagY: Float = 0.62
  private var lastNow: TimeInterval = 0
  private var speakingSince: TimeInterval = 0
  private var wasSpeaking = false
  private var pitch: Float = 0
  /// Legacy (unused by the crew): kept so old call sites compile.
  let bubble = SpeechBubble()

  init(role legacyRole: String, name: String, color: PlatformColor, at start: SCNVector3, faceYaw: Float) {
    let id = CrewIDs.id(forRole: legacyRole)
    role = id
    self.name = name
    self.color = color
    tone = Robot.muted(color)
    pos = SIMD3<Float>(start)
    target = pos
    yaw = faceYaw
    homeYaw = faceYaw
    phase = Float(abs(id.hashValue % 100)) / 100 * 6.28
    nametag = Nametag(name: name, role: id, color: color)
    node.position = start
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
    applyMood("calm", force: true)
  }

  convenience init(id: String, at start: SIMD3<Float>) {
    self.init(role: id, name: CrewIDs.name(id), color: CrewIDs.color(id), at: SCNVector3(start), faceYaw: 0)
  }

  static func muted(_ c: PlatformColor) -> PlatformColor {
    let (r, g, b, _) = c.rgba()
    let l = 0.30 * r + 0.59 * g + 0.11 * b
    let k: CGFloat = 0.15
    return PlatformColor(red: (r + (l - r) * k) * 1.0, green: (g + (l - g) * k) * 0.985, blue: (b + (l - b) * k) * 0.94, alpha: 1)
  }

  // ---------------------------------------------------------------- build

  private func shell() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.shaderModifiers = [.surface: Robot.rimShader]
    setRim(m, color: tone, k: rimBase)
    shells.append(m)
    // Shell lightly tinted toward the agent colour so each robot reads at a glance.
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
    case "engineer": // rounded cube with an antenna and a tool-ear
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
    case "supply": // wide capsule with a cargo-bay belt and pods
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
    case "life": // droplet: round body, pointed top, a leaf-green accent ring
      let b = SCNNode(geometry: SCNSphere(radius: 0.19))
      b.geometry?.materials = [s]
      b.position = SCNVector3(0, -0.04, 0)
      body.addChildNode(b)
      let tip = SCNNode(geometry: SCNCone(topRadius: 0.0, bottomRadius: 0.135, height: 0.26))
      tip.geometry?.materials = [s]
      tip.position = SCNVector3(0, 0.2, 0)
      body.addChildNode(tip)
      let band = SCNNode(geometry: SCNTorus(ringRadius: 0.19, pipeRadius: 0.012))
      band.geometry?.materials = [a]
      band.position = SCNVector3(0, -0.12, 0)
      body.addChildNode(band)
    case "science": // squat dome with a tilted eyepiece and a folding sampling arm
      let b = SCNNode(geometry: SCNCylinder(radius: 0.2, height: 0.26))
      b.geometry?.materials = [s]
      body.addChildNode(b)
      let dome = SCNNode(geometry: SCNSphere(radius: 0.2))
      dome.geometry?.materials = [s]
      dome.scale = SCNVector3(1, 0.5, 1)
      dome.position = SCNVector3(0, 0.13, 0)
      body.addChildNode(dome)
      let tube = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.22))
      tube.geometry?.materials = [a]
      tube.position = SCNVector3(-0.04, 0.3, 0.02)
      tube.eulerAngles.z = 0.35
      body.addChildNode(tube)
      let lens = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.03))
      lens.geometry?.materials = [a]
      lens.position = SCNVector3(-0.085, 0.41, 0.02)
      lens.eulerAngles.z = 0.35
      body.addChildNode(lens)
      let band = SCNNode(geometry: SCNTorus(ringRadius: 0.203, pipeRadius: 0.014))
      band.geometry?.materials = [a]
      band.position = SCNVector3(0, -0.1, 0)
      body.addChildNode(band)
      // The arm: folded against the right flank; Crew swings it out when grinding.
      let sh = SCNNode()
      sh.position = SCNVector3(0.22, -0.02, 0.04)
      let upper = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 0.42))
      upper.geometry?.materials = [metal()]
      upper.position = SCNVector3(0, -0.21, 0)
      sh.addChildNode(upper)
      let joint = SCNNode(geometry: SCNSphere(radius: 0.04))
      joint.geometry?.materials = [a]
      sh.addChildNode(joint)
      let head = SCNNode(geometry: SCNBox(width: 0.07, height: 0.05, length: 0.07, chamferRadius: 0.012))
      head.geometry?.materials = [a]
      head.position = SCNVector3(0, -0.43, 0)
      sh.addChildNode(head)
      let b2 = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 0.014))
      b2.geometry?.materials = [metal()]
      b2.position = SCNVector3(0, -0.47, 0)
      sh.addChildNode(b2)
      body.addChildNode(sh)
      arm = sh
      bit = b2
    default: // rules: hexagonal prism with a crown band
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
    let low: Float = ["engineer": -0.17, "supply": -0.16, "life": -0.25, "science": -0.13][role] ?? -0.21
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
    case "supply": z = 0.165
    case "life": z = 0.205
    case "science": z = 0.205
    case "engineer": z = 0.165
    default: z = 0.18
    }
    face.position = SCNVector3(0, role == "life" ? 0.0 : 0.02, z)
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
    // One eye shape per robot: round, tall oval, soft oval, rounded square, visor.
    let (ew, eh, er, ex): (CGFloat, CGFloat, CGFloat, Float)
    switch role {
    case "engineer": (ew, eh, er, ex) = (0.056, 0.056, 0.028, 0.05)
    case "supply": (ew, eh, er, ex) = (0.040, 0.074, 0.020, 0.05)
    case "life": (ew, eh, er, ex) = (0.064, 0.046, 0.023, 0.05)
    case "science": (ew, eh, er, ex) = (0.054, 0.054, 0.013, 0.05)
    default: (ew, eh, er, ex) = (0.084, 0.034, 0.016, 0.0415)
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

  // ---------------------------------------------------------------- state

  private func setThinking(_ on: Bool) {
    wasThinking = on
    eyeL.isHidden = on
    eyeR.isHidden = on
    for d in dots { d.isHidden = !on }
    if !on {
      halo.scale = SCNVector3(1, 1, 1)
      applyMood(shownMood, force: true)
    }
  }

  /// calm | attentive | worried | suspicious (alarmed: red, eyes narrowed) | happy.
  private func applyMood(_ m: String, force: Bool = false) {
    guard force || m != shownMood else { return }
    shownMood = m
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.25
    var eyeColor = PlatformColor.white
    var sy: Float = 1, rotL: Float = 0, rotR: Float = 0, dy: Float = 0
    var faceGlow = PlatformColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1)
    var haloC = tone.withAlphaComponent(0.55)
    var rimC = tone
    switch m {
    case "worried":
      eyeColor = PlatformColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1); sy = 0.85; rotL = -0.35; rotR = 0.35; dy = 0.006
    case "suspicious":
      eyeColor = PlatformColor(red: 1.0, green: 0.30, blue: 0.25, alpha: 1); sy = 0.32; rotL = 0.18; rotR = -0.18
      faceGlow = PlatformColor(red: 0.22, green: 0.02, blue: 0.02, alpha: 1); haloC = PlatformColor(red: 1, green: 0.2, blue: 0.15, alpha: 0.8); rimC = PlatformColor(red: 1, green: 0.2, blue: 0.15, alpha: 1)
    case "attentive":
      eyeColor = PlatformColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1); sy = 1.18
    case "happy":
      eyeColor = PlatformColor(red: 0.55, green: 1.0, blue: 0.70, alpha: 1); sy = 0.42; dy = 0.01
    default:
      break
    }
    eyeMat.diffuse.contents = eyeColor
    faceMat.diffuse.contents = faceGlow
    haloMat.diffuse.contents = haloC
    for m in shells { setRim(m, color: rimC, k: rimBase) }
    eyeL.scale = SCNVector3(1, sy, 1)
    eyeR.scale = SCNVector3(1, sy, 1)
    eyeL.simdEulerAngles.z = rotL
    eyeR.simdEulerAngles.z = rotR
    eyeL.simdPosition.y = dy
    eyeR.simdPosition.y = dy
    SCNTransaction.commit()
  }

  private func applyAlpha() {
    node.isHidden = alpha <= 0.01
    node.opacity = CGFloat(min(1, alpha))
  }

  /// Where the robot hovers now (render position), for the gaze test and the bubble.
  var worldPosition: SIMD3<Float> { node.simdPosition }
  /// Above the shell: the nametag.
  var tagPosition: SIMD3<Float> { node.simdPosition + SIMD3(0, tagY * tagScale, 0) }
  /// True while it can be seen and gazed at.
  var isVisible: Bool { alpha > 0.5 && !node.isHidden }

  /// Teleport (only while invisible).
  func snap(to p: SIMD3<Float>) { pos = p; target = p; node.simdPosition = p }

  // ---------------------------------------------------------------- per frame

  func update(now: TimeInterval, user: SIMD3<Float>) {
    let dt = Float(min(0.1, max(0.001, now - lastNow)))
    lastNow = now
    guard !node.isHidden else { return }
    let t = Float(now)
    if thinking != wasThinking { setThinking(thinking) }
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
    nametag.setActive(speaking)
    applyMood(mood)
    if speaking && !wasSpeaking { speakingSince = now }
    wasSpeaking = speaking

    // Glide toward the target (exponential approach, speed-capped).
    let d = target - pos
    let dist = simd_length(d)
    if dist > 0.001 {
      let step = min(dist, max(dist * (1 - exp(-dt * 2.2)), 0), maxSpeed * dt)
      pos += d / dist * step
    }
    // Job motion: gentle, task-shaped.
    var off = SIMD3<Float>(0, 0.035 * sin(t * 1.3 + phase), 0)
    var jobYaw: Float = 0, jobPitch: Float = 0
    let r = SIMD3<Float>(cos(homeYaw), 0, -sin(homeYaw))
    if !speaking {
      switch task {
      case "plants": off += r * (0.10 * sin(t * 0.5 + phase)); jobYaw = 0.12 * sin(t * 0.5 + phase); jobPitch = 0.16 + 0.05 * sin(t * 0.9)
      case "panel": off += r * (0.16 * sin(t * 0.4 + phase)); jobPitch = 0.07 * sin(t * 1.4)
      case "crates": off += r * (0.28 * sin(t * 0.33 + phase)); jobYaw = 0.35 * sin(t * 0.33 + phase + 1.2)
      case "bench": jobPitch = 0.10 + 0.05 * sin(t * 1.1); jobYaw = 0.1 * sin(t * 0.4)
      case "console": jobYaw = 0.30 * sin(t * 0.42 + phase)
      case "rock": jobPitch = 0.25
      case "lander": jobYaw = 0.45 * sin(t * 0.5 + phase)
      default: break
      }
    }
    // Arm: out and grinding, or folded.
    if let arm {
      let want: Float = armOut ? -1.0 : 0
      var cur = arm.simdEulerAngles.x
      cur += (want - cur) * (1 - exp(-dt * 3))
      arm.simdEulerAngles.x = cur
      if armOut {
        arm.simdEulerAngles.x += 0.05 * sin(t * 9)
        bit?.simdEulerAngles.y += dt * 24
        off += SIMD3(0.004 * sin(t * 47), 0.004 * sin(t * 53), 0)
      }
    }
    // Facing: toward what it looks at, else its work.
    var wantYaw = homeYaw + jobYaw
    var wantPitch = jobPitch
    if let lp = lookPoint {
      let v = lp - pos
      let h = hypot(v.x, v.z)
      if h > 0.05 {
        wantYaw = atan2(v.x, v.z)
        wantPitch = -max(-0.45, min(0.45, atan2(v.y, h))) * 0.7
      }
    }
    var dyaw = wantYaw - yaw
    while dyaw > .pi { dyaw -= 2 * .pi }
    while dyaw < -.pi { dyaw += 2 * .pi }
    yaw += dyaw * (1 - exp(-dt * (speaking ? 6 : 3.6)))
    node.simdEulerAngles.y = yaw
    node.simdPosition = pos + off
    pitch += (wantPitch - pitch) * (1 - exp(-dt * 5))
    lean += ((speaking ? 1 : 0) - lean) * (1 - exp(-dt * 4))
    body.simdEulerAngles.x = pitch + 0.08 * lean
    // Nametag billboard: always faces the viewer, upright (the parent yaw is undone).
    let toUser = user - node.simdPosition
    let yawUser = atan2(toUser.x, toUser.z)
    nametag.node.simdEulerAngles.y = yawUser - yaw
    var tagTarget: Float = 0.62, tagFade: CGFloat = 1, bestArea = Float.infinity
    let np = node.simdPosition
    for ty in [Float(0.62), 0.8, 1.0, -0.55, -0.75] {
      let a = ScreenRects.overlap(center: np + SIMD3(0, ty * tagScale, 0), w: 1.12 * tagScale, h: 0.17 * tagScale, user: user)
      if a < bestArea { bestArea = a; tagTarget = ty }
      if a == 0 { break }
    }
    if bestArea > 0 { tagFade = 0.4 }
    tagY += (tagTarget - tagY) * 0.12
    nametag.node.simdPosition = SIMD3(0, tagY * tagScale, 0)
    let pulseTag: Float = speaking ? 1 + 0.07 * sin(Float(now - speakingSince) * 7) : 1
    let ts = tagScale * pulseTag
    nametag.node.simdScale = SIMD3(repeating: ts)
    nametag.node.opacity += (tagFade - nametag.node.opacity) * 0.15

    // Rim: bright while speaking (with a decaying burst at the start), plus the cue halo.
    let since = Float(now - speakingSince)
    let burst = speaking ? 0.7 * max(0, 1 - since / 1.2) : 0
    let rimK = rimBase + burst + 0.35 * lean + (cueOn ? 0.5 + 0.4 * sin(t * 4.5) : 0)
    for m in shells { m.setValue(NSNumber(value: rimK), forKey: "rimK") }
    if !thinking {
      let hs = 1 + (speaking ? 0.12 + 0.08 * sin(since * 6) : 0) + (cueOn ? 0.15 * (0.5 + 0.5 * sin(t * 4.5)) : 0)
      halo.scale = SCNVector3(hs, hs, hs)
    }
    updateCueHalo(t: t, yawUser: yawUser)

    // Eyes glance: toward the target when engaged, otherwise drift now and then.
    if now > nextGlance {
      nextGlance = now + Double.random(in: 1.5...4.5)
      glanceTo = Float.random(in: 0...1) < 0.4 ? 0 : Float.random(in: -1...1)
    }
    var gx = glanceTo
    if let lp = lookPoint {
      let v = lp - pos
      var rel = atan2(v.x, v.z) - yaw
      while rel > .pi { rel -= 2 * .pi }
      while rel < -.pi { rel += 2 * .pi }
      gx = max(-1, min(1, sin(rel) * 3))
    }
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

  /// A big pulsing glow behind the robot: the one obvious thing to look at.
  private func updateCueHalo(t: Float, yawUser: Float) {
    if cueOn && cueHalo == nil {
      let n = SCNNode(geometry: SCNPlane(width: 1.5, height: 1.5))
      n.geometry?.materials = [Tex.glowMaterial(tone, strength: 1)]
      n.renderingOrder = 60
      n.position = SCNVector3(0, 0, -0.1)
      node.addChildNode(n)
      cueHalo = n
    }
    guard let h = cueHalo else { return }
    h.isHidden = !cueOn
    guard cueOn else { return }
    let k = 0.5 + 0.5 * sin(t * 4.5)
    let s = tagScale > 1.5 ? tagScale * 0.9 : 1
    h.simdScale = SIMD3(repeating: (1.0 + 0.3 * k) * s)
    h.opacity = CGFloat(0.55 + 0.45 * k)
    h.simdEulerAngles.y = yawUser - node.simdEulerAngles.y
  }

}

/// Names and colours of the legacy agents, kept for the decision cards ("proposed by Rules") and old tapes.
enum RobotCrew {
  /// The colour of the agent with this display name (the crew names, and the pre-rename names for old tapes); nil for an unknown name.
  static func color(forAgent name: String) -> PlatformColor? {
    let legacy = ["cargo keeper": "supply", "bill checker": "supply", "money keeper": "supply", "rule keeper": "rules",
                  "cargo": "supply", "bills": "supply", "money": "supply"]
    if let r = legacy[name.lowercased()] { return CrewIDs.color(r) }
    return CrewIDs.all.first { CrewIDs.name($0).caseInsensitiveCompare(name) == .orderedSame }.map { CrewIDs.color($0) }
  }

  /// Compatibility for the spectator overlay: the crew ids with their names (angle/radius/height are the inside anchors).
  static var layout: [(role: String, name: String, deg: Float, r: Float, y: Float)] {
    CrewIDs.all.map { id in
      let m = CrewMarks.inside(id)
      return (id, CrewIDs.name(id), m.deg, m.r, m.y)
    }
  }
}
