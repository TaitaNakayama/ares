import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// The five crew agents: ids, names, colours, icons.
enum CrewIDs {
  static let all = ["engineer", "life", "science", "supply", "rules"]
  static func name(_ id: String) -> String {
    switch id {
    case "engineer": return "Engineer"
    case "life": return "Life"
    case "science": return "Science"
    case "supply": return "Supply"
    default: return "Rules"
    }
  }
  static func color(_ id: String) -> PlatformColor {
    switch id {
    case "engineer": return PlatformColor(red: 0x4D / 255.0, green: 0xA3 / 255.0, blue: 0xFF / 255.0, alpha: 1)
    case "life": return PlatformColor(red: 0xF2 / 255.0, green: 0xF4 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
    case "science": return PlatformColor(red: 0x3B / 255.0, green: 0xD1 / 255.0, blue: 0x6F / 255.0, alpha: 1)
    case "supply": return PlatformColor(red: 0xFF / 255.0, green: 0x9A / 255.0, blue: 0x3C / 255.0, alpha: 1)
    default: return PlatformColor(red: 0xA9 / 255.0, green: 0x7B / 255.0, blue: 0xFF / 255.0, alpha: 1)
    }
  }
  /// A crew id for either a crew id or a pre-redesign role (old tapes): requester -> engineer, receiver/ap/treasury -> supply, controller -> rules.
  static func id(forRole r: String) -> String {
    if all.contains(r) { return r }
    switch r {
    case "requester": return "engineer"
    case "receiver", "ap", "treasury": return "supply"
    case "controller": return "rules"
    case "scientist": return "science"
    default: return "rules"
    }
  }
  /// The pre-redesign role whose chime pitch each crew member keeps.
  static func legacyRole(_ id: String) -> String {
    switch id {
    case "engineer": return "requester"
    case "life": return "ap"
    case "science": return "treasury"
    case "supply": return "receiver"
    default: return "controller"
    }
  }
}

/// Where the crew stands. Inside: anchors around the commander's seat (yaw 0 = the window, positive = right).
/// Outside: computed from the existing anchors (`Spots`: the judge's start, the cargo lander and its crates), never hardcoded.
enum CrewMarks {
  struct Inside { let deg: Float; let r: Float; let y: Float; let task: String }
  static func inside(_ id: String) -> Inside {
    switch id {
    case "engineer": return Inside(deg: -40, r: 2.25, y: 1.45, task: "panel")      // the power panel
    case "life": return Inside(deg: -110, r: 2.1, y: 1.25, task: "plants")         // hydroponics + the oxygen machine
    case "science": return Inside(deg: 110, r: 2.1, y: 1.3, task: "bench")         // the lab bench
    case "supply": return Inside(deg: 40, r: 2.25, y: 1.15, task: "crates")        // the crates
    default: return Inside(deg: 0, r: 2.6, y: 1.95, task: "console")                // the main console, up above the decision card
    }
  }
  /// Rules before the question: close, left and above the card.
  static let approach = Inside(deg: -14, r: 1.7, y: 2.1, task: "judge")

  struct Mark { var pos: SIMD3<Float>; var task: String; var look: SIMD3<Float>? }

  /// Forward and right (x, z) of a scene yaw (Journey convention: head -Z turned by `yaw` about +Y).
  static func basis(yaw: Float) -> (f: SIMD3<Float>, r: SIMD3<Float>) {
    (SIMD3(-sin(yaw), 0, -cos(yaw)), SIMD3(cos(yaw), 0, -sin(yaw)))
  }

  /// The rock Science grinds: ahead and to the right of where the judge starts.
  static func rock(ground: (Float, Float) -> Float) -> SIMD3<Float> {
    let s = Spots.start
    let b = basis(yaw: s.yaw)
    let p = SIMD3(s.pos.x, 0, s.pos.y) + b.f * 3.7 + b.r * 2.2
    return SIMD3(p.x, ground(p.x, p.z), p.z)
  }

  /// The cargo crates Supply scans, and where it floats beside them (on the judge's side).
  static func crates(ground: (Float, Float) -> Float) -> (crates: SIMD3<Float>, bot: SIMD3<Float>) {
    let c = Spots.crates, s = Spots.start.pos
    let toJudge = simd_normalize(s - c)
    let gy = ground(c.x, c.y)
    let bx = c.x + toJudge.x * 2.8, bz = c.y + toJudge.y * 2.8
    return (SIMD3(c.x, gy + 0.9, c.y), SIMD3(bx, ground(bx, bz) + 1.5, bz))
  }

  /// All outside marks. `eye`/`yaw`: the judge now (the Engineer keeps beside them).
  static func outside(_ id: String, eye: SIMD3<Float>, yaw: Float, ground: (Float, Float) -> Float) -> Mark {
    let b = basis(yaw: yaw)
    switch id {
    case "science":
      let rk = rock(ground: ground)
      return Mark(pos: rk, task: "rock", look: SIMD3(rk.x, rk.y + 0.4, rk.z))
    case "supply":
      let c = crates(ground: ground)
      return Mark(pos: c.bot, task: "lander", look: c.crates)
    default: // engineer (and anyone sent outside without a post): beside the judge, head height
      let slot: Float = id == "engineer" ? 1 : (id == "life" ? -1 : 0.4)
      let p = eye + b.f * 2.0 + b.r * (-1.5 * slot)
      return Mark(pos: SIMD3(p.x, eye.y + 0.05, p.z), task: "judge", look: nil)
    }
  }
}

/// One line on screen: the speaker, who it talks to, the text and how long it must stay.
private struct Line {
  let seq: Int
  let speaker: String
  let to: String
  let text: String
  let hold: Double
  var shownAt: TimeInterval = 0
}

/// The crew in the scene: five robots, one speech bubble, the outdoor props (Science's rock and dust, Supply's scan and hologram),
/// placement by `crew[id].place`/`task`, who looks at whom, the cue glow and taps. Driven by `BaseScene`.
final class Crew {
  let bots: [String: Robot]
  weak var director: OutdoorDirector?
  /// Opens the stereo close-up in front of the head (set by BaseScene).
  var openCloseUp: (() -> Void)?
  private weak var link: Link?
  private let root: SCNNode
  private let outside: Outside
  private let scene: SCNScene

  // contract state
  private var state: [String: VRState.Crew] = [:]
  private var cue: String?
  private var act: String?
  private var sawContract = false
  private var lastSeq = -1
  private var primed = false

  // lines
  private var current: Line?
  private var queue: [Line] = []
  let bubble = SpeechBubble()
  private var bubbleShownKey = ""
  private var bubbleOffset = SIMD3<Float>(0, 0.2, 0)

  // per frame
  private var lastNow: TimeInterval = 0
  private var lastPart: String?
  private var holdUntil: [String: TimeInterval] = [:]
  private var wasVisible: [String: Bool] = [:]
  private var arrived: [String: Bool] = [:]
  private var autoCloseAt: TimeInterval = .infinity
  private var lastCloseUpOpen = false
  private var lastReality = false
  private var rimCache: SIMD3<Float>?

  // outside props
  private let props = SCNNode()
  private let rock = SCNNode()
  private var dust: [(node: SCNNode, born: TimeInterval, vel: SIMD3<Float>)] = []
  private var nextPuff: TimeInterval = 0
  private let beamHolder = SCNNode()
  private let beamCone = SCNCone(topRadius: 0, bottomRadius: 0.4, height: 1)
  private var beamLen: Float = 1
  private let holo = SpritePanel(width: 0.95, height: 0.55, pixelsPerMeter: 600)
  private var sparkNode = SCNNode()

  init(root: SCNNode, outside: Outside, scene: SCNScene) {
    self.root = root
    self.outside = outside
    self.scene = scene
    var out: [String: Robot] = [:]
    for id in CrewIDs.all {
      let m = CrewMarks.inside(id)
      let p = Room.ring(m.deg, r: m.r, y: m.y)
      let r = Robot(id: id, at: SIMD3(Float(p.x), Float(p.y), Float(p.z)))
      root.addChildNode(r.node)
      out[id] = r
    }
    bots = out
    bubble.node.renderingOrder = 90
    root.addChildNode(bubble.node)
    buildProps()
    root.addChildNode(props)
    props.isHidden = true
  }

  // ---------------------------------------------------------------- outdoor props

  private func buildProps() {
    // The rock: a few squashed spheres of dark regolith-brown stone.
    let stone = SCNMaterial()
    stone.lightingModel = .blinn
    stone.diffuse.contents = PlatformColor(red: 0.62, green: 0.50, blue: 0.40, alpha: 1)
    stone.emission.contents = PlatformColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)
    stone.specular.contents = PlatformColor(white: 0.08, alpha: 1)
    for (x, y, z, sx, sy, sz) in [(Float(0), Float(0.28), Float(0), Float(0.62), Float(0.34), Float(0.5)), (0.4, 0.14, 0.12, 0.3, 0.17, 0.26), (-0.36, 0.12, -0.1, 0.26, 0.15, 0.24), (0.05, 0.16, -0.38, 0.28, 0.17, 0.22)] {
      let s = SCNSphere(radius: 1)
      s.segmentCount = 14
      s.materials = [stone]
      let n = SCNNode(geometry: s)
      n.position = SCNVector3(x, y, z)
      n.scale = SCNVector3(sx, sy, sz)
      rock.addChildNode(n)
    }
    props.addChildNode(rock)
    // Dust puffs (pool of 12 soft sprites, alpha blended, shared material).
    let dm = SCNMaterial()
    dm.lightingModel = .constant
    dm.diffuse.contents = Tex.glow(PlatformColor(red: 0.78, green: 0.58, blue: 0.40, alpha: 1))
    dm.writesToDepthBuffer = false
    dm.isDoubleSided = true
    for _ in 0..<12 {
      let n = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.34))
      n.geometry?.materials = [dm]
      n.renderingOrder = 62
      n.opacity = 0
      n.isHidden = true
      props.addChildNode(n)
      dust.append((n, -100, .zero))
    }
    // The grinding spark at the bit.
    let sm = Tex.glowMaterial(PlatformColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1), strength: 1)
    sparkNode = SCNNode(geometry: SCNPlane(width: 0.22, height: 0.22))
    sparkNode.geometry?.materials = [sm]
    sparkNode.renderingOrder = 63
    sparkNode.isHidden = true
    props.addChildNode(sparkNode)
    // Scan beam: a translucent additive cone from Supply to the crates.
    let bm = SCNMaterial()
    bm.lightingModel = .constant
    bm.diffuse.contents = CrewIDs.color("supply").withAlphaComponent(0.20)
    bm.blendMode = .add
    bm.writesToDepthBuffer = false
    bm.isDoubleSided = true
    beamCone.materials = [bm]
    let cn = SCNNode(geometry: beamCone)
    cn.eulerAngles.x = .pi / 2
    cn.position = SCNVector3(0, 0, -0.5)
    beamHolder.addChildNode(cn)
    beamHolder.renderingOrder = 61
    props.addChildNode(beamHolder)
    // Hologram: "34/36" in Supply's colour.
    let c = CrewIDs.color("supply")
    holo.node.renderingOrder = 85
    holo.update(key: "holo34") { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0.72), radius: 36)
      ctx.setStrokeColor(c.withAlphaComponent(0.95).cgColor)
      ctx.setLineWidth(6)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4), cornerWidth: 32, cornerHeight: 32, transform: nil))
      ctx.strokePath()
      CrewIcon.draw(ctx, id: "supply", in: CGRect(x: 30, y: 24, width: 52, height: 52), color: c)
      _ = Draw.text("CRATES", at: CGPoint(x: 96, y: 28), size: 44, weight: .heavy, color: c, width: size.width - 120)
      _ = Draw.text("34/36", at: CGPoint(x: 0, y: 92), size: 150, weight: .heavy, color: c, width: size.width, align: .center)
    }
    holo.node.isHidden = true
    props.addChildNode(holo.node)
  }

  // ---------------------------------------------------------------- state from the server

  /// A new vr_state: the crew table, the cue, and the line being said.
  func apply(_ st: VRState, now: TimeInterval) {
    cue = st.scene?.cue
    act = st.scene?.act
    RealityCheck.insideAllowed = act == "explore"
    var speaking = st.speaking
    if let c = st.crew {
      sawContract = true
      state = c
    } else {
      sawContract = false
      (state, speaking) = Crew.legacy(st)
      if !primed { primed = true; lastSeq = speaking?.seq ?? -1; speaking = nil } // an old tape's last line is not news
    }
    ingest(speaking, now: now)
  }

  /// Old tapes: `robots[role]` mapped onto the five crew ids (requester -> engineer, receiver/ap/treasury -> supply, controller -> rules).
  private static func legacy(_ st: VRState) -> ([String: VRState.Crew], VRState.Speaking?) {
    var crew: [String: VRState.Crew] = [:]
    var newest: (id: String, r: VRState.Robot)?
    for (role, r) in st.robots ?? [:] {
      guard let seq = r.seq, (r.short ?? r.text) != nil else { continue }
      if seq > (newest?.r.seq ?? -1) { newest = (CrewIDs.id(forRole: role), r) }
    }
    for id in CrewIDs.all {
      var c = VRState.Crew()
      if let n = newest, n.id == id {
        switch n.r.mood ?? "calm" {
        case "suspicious": c.mood = "alarmed"
        case "worried": c.mood = "worried"
        case "happy": c.mood = "happy"
        default: c.mood = "calm"
        }
      }
      crew[id] = c
    }
    for r in st.thinking ?? [] { crew[CrewIDs.id(forRole: r)]?.thinking = true }
    guard let n = newest else { return (crew, nil) }
    return (crew, VRState.Speaking(seq: n.r.seq, speaker: n.id, to: "judge", text: n.r.text ?? n.r.short, holdMs: nil, via: nil))
  }

  private func ingest(_ sp: VRState.Speaking?, now: TimeInterval) {
    guard let sp, let seq = sp.seq, let text = sp.text, !text.isEmpty, let speaker = sp.speaker, bots[speaker] != nil else { return }
    guard seq != lastSeq else { return }
    lastSeq = seq
    let words = text.split(separator: " ").count
    let hold = max(Double(sp.holdMs ?? 0) / 1000, 2.5 + 0.4 * Double(words))
    let line = Line(seq: seq, speaker: speaker, to: sp.to ?? "judge", text: text, hold: hold)
    if let c = current, now < c.shownAt + c.hold {
      queue.append(line)
      if queue.count > 3 { queue.removeFirst() }
    } else {
      show(line, now: now)
    }
  }

  private func show(_ l: Line, now: TimeInterval) {
    var l = l
    l.shownAt = now
    current = l
    Sound.shared.speak(role: CrewIDs.legacyRole(l.speaker))
    if state[l.speaker]?.mood == "alarmed" { Sound.shared.play("alert", volume: 0.5) }
  }

  // ---------------------------------------------------------------- queries for BaseScene

  /// The robots the judge can see right now (gaze test, off-view arrow).
  var liveBots: [Robot] { bots.values.filter { $0.isVisible } }

  /// The robot whose line is on screen (or just was), if it is visible.
  func speakerBot(now: TimeInterval) -> Robot? {
    guard let c = current, now < c.shownAt + c.hold + 1, let b = bots[c.speaker], b.isVisible else { return nil }
    return b
  }

  /// Director camera: look at the speaker (inside only; yaw right-positive degrees, pitch up-positive).
  func directorLook(now: TimeInterval) -> (Float, Float)? {
    guard director?.isOutside == false, let b = speakerBot(now: now) else { return nil }
    let p = b.pos
    return (atan2(p.x, -p.z) * 180 / .pi, 0)
  }

  // ---------------------------------------------------------------- per frame

  private func partName() -> String { director?.isOutside == true ? "outside" : "inside" }

  private func defaultPlace(_ id: String, part: String) -> String {
    (id == "life" || id == "rules") ? "inside" : part
  }

  private func word(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

  func update(now: TimeInterval, eye: SIMD3<Float>, fwd: SIMD3<Float>, link: Link, hovered: String?, needsCommander: Bool) {
    self.link = link
    let dt = Float(min(0.1, max(0.001, now - lastNow)))
    lastNow = now
    guard let director else { return }
    let part = partName()
    let partFlipped = lastPart != nil && lastPart != part
    lastPart = part
    // Promote the next queued line when the current one has had its time.
    if let c = current, let n = queue.first, now >= c.shownAt + c.hold { queue.removeFirst(); show(n, now: now) }
    let speakingLine: Line? = current.flatMap { now < $0.shownAt + $0.hold + 0.8 ? $0 : nil }
    let lookLine: Line? = current.flatMap { now < $0.shownAt + $0.hold + 3 ? $0 : nil } // turned toward the listener a beat after it speaks
    let approaching = state.values.contains { $0.approach == true }
    let thinkingRoles = Set(link.thinkingRoles.map { CrewIDs.id(forRole: $0) })
    let ground: (Float, Float) -> Float = { [outside] x, z in outside.groundY(x, z) }
    let judgeYaw = director.yaw

    // 1. Where each robot is and whether it shows.
    for id in CrewIDs.all {
      guard let bot = bots[id] else { continue }
      let st = state[id]
      var place = word(st?.place) ?? defaultPlace(id, part: part)
      // The server may move the crew inside before the headset has walked in: hold the outdoor post (up to 8 s) until the part flips.
      if place == "inside", part == "outside", wasVisible[id] == true, !partFlipped {
        let until = holdUntil[id] ?? now + 8
        holdUntil[id] = until
        if now < until { place = part }
      } else if place == part { holdUntil[id] = nil }
      let shows = place == part
      // Target and facing for the place it is in.
      var task = word(st?.task) ?? ""
      var tpos: SIMD3<Float>
      var look: SIMD3<Float>? = nil
      var homeYaw: Float
      var tagScale: Float = 1
      var armOut = false
      let atJudge = task == "judge"
      if part == "outside" {
        var mk = CrewMarks.outside(id, eye: eye, yaw: judgeYaw, ground: ground)
        if atJudge { mk = CrewMarks.outside("engineer", eye: eye, yaw: judgeYaw, ground: ground); mk.pos.x += id == "engineer" ? 0 : (id == "supply" ? 1.5 : -2.5) }
        tpos = mk.pos
        task = atJudge ? "judge" : mk.task
        if id == "science" && !atJudge {
          // Hover above the rock, back and to the side of it, arm onto the top.
          let toRock = simd_normalize(SIMD3(mk.pos.x - eye.x, 0, mk.pos.z - eye.z))
          let yawR = atan2(toRock.x, toRock.z)
          let rt = SIMD3<Float>(cos(yawR), 0, -sin(yawR))
          tpos = mk.pos + SIMD3(0, 1.0, 0) - toRock * 0.33 - rt * 0.22
          homeYaw = yawR
          armOut = true
        } else {
          let v = (mk.look ?? eye) - tpos
          homeYaw = atan2(v.x, v.z)
        }
        let dist = simd_length(tpos - eye)
        tagScale = max(1, min(4, dist / 3))
      } else {
        let m = (approaching && st?.approach == true) ? CrewMarks.approach : CrewMarks.inside(id)
        let p = Room.ring(m.deg, r: m.r, y: m.y)
        tpos = SIMD3(Float(p.x), Float(p.y), Float(p.z))
        if atJudge && st?.approach != true {
          let q = Room.ring(CrewMarks.inside(id).deg * 0.45, r: 1.7, y: 1.7)
          tpos = SIMD3(Float(q.x), Float(q.y), Float(q.z))
        }
        if st?.approach == true || atJudge { task = "judge" } else if task.isEmpty || task == "judge" { task = m.task }
        // Idle facing: its work (outward), turned a little toward the commander.
        let outward = atan2(tpos.x, tpos.z)
        let toward = atan2(-tpos.x, -tpos.z)
        var d = toward - outward
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        homeYaw = outward + d * 0.35
        if st?.approach == true || atJudge { homeYaw = toward }
      }
      // Leans in toward the judge while saying something to them (inside).
      if part == "inside", shows, let l = speakingLine, l.speaker == id, l.to == "judge" {
        let dir = simd_normalize(SIMD3(-tpos.x, 0, -tpos.z))
        tpos += dir * 0.35
      }
      bot.task = task
      bot.target = tpos
      bot.homeYaw = homeYaw
      bot.tagScale = tagScale
      bot.armOut = armOut && shows
      bot.maxSpeed = (st?.approach == true) ? 1.3 : (part == "outside" ? 1.8 : 1.1)
      // Visibility: fade when the place changes; snap while the fade-to-black covers a part switch.
      let want: Float = shows ? 1 : 0
      if partFlipped {
        bot.alpha = want
        if shows { bot.snap(to: tpos) }
      } else if shows && !(wasVisible[id] ?? false) && bot.alpha < 0.01 {
        // Appearing: from where it will stand (the Engineer floats up from below).
        bot.snap(to: part == "outside" && id == "engineer" ? tpos - SIMD3(0, 1.3, 0) : tpos)
        bot.alpha = min(1, bot.alpha + dt * 2.5)
      } else {
        let a = bot.alpha + (want > bot.alpha ? 1 : -1) * dt * 2.5
        bot.alpha = want > bot.alpha ? min(want, a) : max(want, a)
      }
      // A jump of many metres (the other set, a late state): never glide it across the map in view; fade it in at the new post.
      if simd_distance(bot.pos, tpos) > 12 {
        bot.alpha = 0
        bot.snap(to: part == "outside" && id == "engineer" ? tpos - SIMD3(0, 1.3, 0) : tpos)
      }
      wasVisible[id] = shows
      bot.thinking = (st?.thinking ?? false) || thinkingRoles.contains(id)
      switch st?.mood ?? "calm" {
      case "alarmed": bot.mood = "suspicious"
      case "worried": bot.mood = "worried"
      case "happy": bot.mood = "happy"
      default: bot.mood = "calm"
      }
      bot.speaking = shows && speakingLine?.speaker == id
      bot.cueOn = shows && cue == id && (id == "science" || id == "engineer")
      bot.hovered = hovered == id
    }

    // 2. Who looks at what.
    let rim = rimPoint(from: eye)
    for id in CrewIDs.all {
      guard let bot = bots[id], !bot.node.isHidden else { continue }
      let st = state[id]
      func spot(_ token: String?) -> SIMD3<Float>? {
        switch token {
        case "judge": return eye
        case "rim": return bot.pos + simd_normalize(rim - bot.pos) * 40 + SIMD3(0, 6, 0)
        case .some(let t) where t != id: if let o = bots[t], o.isVisible { return o.pos } else { return nil }
        default: return nil
        }
      }
      var lp: SIMD3<Float>?
      if let l = lookLine {
        if l.speaker == id { lp = spot(l.to) ?? eye }
        else if let s = bots[l.speaker], s.isVisible { lp = s.pos }
      }
      if lp == nil, approaching, st?.approach != true { lp = eye }
      if lp == nil { lp = spot(st?.lookAt) }
      if lp == nil, needsCommander { lp = eye }
      if lp == nil {
        // Now and then it glances at the judge from its work.
        let period = 9.0 + Double(abs(id.hashValue % 5))
        if (now + Double(abs(id.hashValue % 7))).truncatingRemainder(dividingBy: period) < 1.4 { lp = eye }
      }
      bot.lookPoint = lp
    }

    for bot in bots.values { bot.update(now: now, user: eye) }

    // 3. Outdoor props and the bubble.
    updateProps(now: now, eye: eye, part: part)
    updateBubble(now: now, dt: dt, eye: eye, fwd: fwd, part: part)

    // 4. Cue timers and the headset's input notices.
    if now >= autoCloseAt {
      autoCloseAt = .infinity
      if director.closeUp.isOpen { director.closeUp.close() }
    }
    #if !os(macOS)
    let open = director.closeUp.isOpen
    if open != lastCloseUpOpen { lastCloseUpOpen = open; link.closeup(open: open) }
    let rc = RealityCheck.shared.wantOn
    if rc != lastReality { lastReality = rc; link.reality(on: rc) }
    #endif
  }

  /// The crater rim the Engineer turns to: a fixed point far out along `Spots.rimDir` (the storm wall moves between sets, the rim doesn't).
  private func rimPoint(from eye: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(Spots.rim.x, eye.y + 6, Spots.rim.y)
  }

  // ---------------------------------------------------------------- the one bubble

  private func updateBubble(now: TimeInterval, dt: Float, eye: SIMD3<Float>, fwd: SIMD3<Float>, part: String) {
    guard let c = current, let bot = bots[c.speaker], bot.isVisible else {
      bubble.node.opacity = max(0, bubble.node.opacity - CGFloat(dt * 6))
      if bubble.node.opacity < 0.01 { bubble.node.isHidden = true }
      return
    }
    let end = c.shownAt + c.hold + 10
    let tail = Float(max(0, min(1, (end - now) / 1.5)))
    let fadeIn = Float(max(0, min(1, (now - c.shownAt) / 0.2)))
    let a = min(tail, fadeIn)
    guard a > 0.01 else { bubble.node.isHidden = true; return }
    bubble.node.isHidden = false
    bubble.node.opacity = CGFloat(a)
    let p = bot.pos
    let toBot = SIMD3(p.x - eye.x, 0, p.z - eye.z)
    let dist = max(0.5, simd_length(toBot))
    let radial = dist > 0.01 ? toBot / dist : SIMD3<Float>(0, 0, -1)
    let right = SIMD3<Float>(-radial.z, 0, radial.x)
    let outside = part == "outside"
    let k: Float = outside ? max(1, min(6, dist / 3)) : 1
    let w = Float(SpeechBubble.w) * k, h = Float(SpeechBubble.h) * k
    let side: Float = p.x < 0 ? 1 : -1
    var centre: SIMD3<Float>
    if outside {
      let base = p + right * side * (w / 2 + 0.3 * k) + SIMD3(0, 0.75 * k, 0) - radial * 0.2 * k
      centre = base
      // Keep it in the view: the head's horizontal field is about +-38 degrees; stay inside it, with the bubble's own half-width.
      let fh = SIMD3(fwd.x, 0, fwd.z)
      if simd_length(fh) > 0.1 {
        let f = simd_normalize(fh)
        let rgt = SIMD3<Float>(-f.z, 0, f.x)
        var v = centre - eye
        let hd = max(0.5, hypot(v.x, v.z))
        var rel = atan2(simd_dot(v, rgt), simd_dot(v, f))
        let half = atan2(w / 2, hd)
        let maxRel = max(Float(8) * .pi / 180, Float(36) * .pi / 180 - half)
        rel = max(-maxRel, min(maxRel, rel))
        let el = max(-Float(10) * .pi / 180, min(Float(24) * .pi / 180, atan2(v.y, hd)))
        v = f * cos(rel) * hd + rgt * sin(rel) * hd
        centre = eye + SIMD3(v.x, tan(el) * hd, v.z)
      }
      bubbleOffset = .zero
    } else {
      var best = SIMD3<Float>(0, 0.2, 0), bestArea = Float.infinity, bestSide = side
      let others = bots.values.filter { $0 !== bot && $0.isVisible }
      search: for sd in [side, -side] {
        let sbase = p + right * sd * (w / 2 + 0.28) - radial * 0.15
        for dx in [Float(0), 0.35, 0.7] {
          for dy in [Float(0.2), 0.5, 0.8, -0.55, -0.85] {
            let off = right * sd * dx + SIMD3(0, dy, 0)
            let cand = Crew.clampInside(sbase + off, halfW: w / 2, halfH: h / 2)
            let area = ScreenRects.overlap(center: cand, w: w, h: h, user: eye) + 3 * Crew.botOverlap(center: cand, w: w, h: h, user: eye, others: others) + (sd == side ? 0 : 0.002)
            if area < bestArea { bestArea = area; best = SIMD3(dx, dy, 0); bestSide = sd }
            if area == 0 { break search }
          }
        }
      }
      let base = p + right * bestSide * (w / 2 + 0.28) - radial * 0.15
      let target = right * bestSide * best.x + SIMD3(0, best.y, 0)
      bubbleOffset += (target - bubbleOffset) * 0.12
      centre = Crew.clampInside(base + bubbleOffset, halfW: w / 2, halfH: h / 2)
    }
    bubble.node.simdPosition = centre
    bubble.node.simdScale = SIMD3(repeating: k)
    let tu = eye - centre
    bubble.node.simdEulerAngles = SIMD3(0, atan2(tu.x, tu.z), 0)
    let tailLeft = simd_dot(centre - p, right) > 0
    let key = "\(c.seq)|\(tailLeft)"
    if key != bubbleShownKey {
      bubbleShownKey = key
      bubble.set(text: c.text, name: bot.name, color: bot.color, deny: false, tailLeft: tailLeft, key: "crew|\(c.seq)|\(c.speaker)", icon: c.speaker)
    }
  }

  /// Angular overlap (radians squared) of a bubble with the other robots' bodies, as seen from `user`.
  static func botOverlap(center: SIMD3<Float>, w: Float, h: Float, user: SIMD3<Float>, others: [Robot]) -> Float {
    let d = center - user
    let refAz = atan2(d.x, -d.z)
    let dir = SIMD3<Float>(d.x, 0, d.z)
    let n = simd_length(dir) > 0.01 ? simd_normalize(dir) : SIMD3<Float>(0, 0, -1)
    let right = SIMD3<Float>(-n.z, 0, n.x)
    let a = ScreenRects.box(center: center, right: right, w: w, h: h, user: user, refAz: refAz)
    var total: Float = 0
    for o in others {
      let b = ScreenRects.box(center: o.pos, right: right, w: 0.7, h: 1.0, user: user, refAz: refAz)
      let ox = min(a.az1, b.az1) - max(a.az0, b.az0)
      let oy = min(a.el1, b.el1) - max(a.el0, b.el0)
      if ox > 0, oy > 0 { total += ox * oy }
    }
    return total
  }

  /// Inside the round room: below the ceiling, off the floor, away from the wall.
  static func clampInside(_ c: SIMD3<Float>, halfW: Float, halfH: Float) -> SIMD3<Float> {
    var p = c
    p.y = max(0.8 + halfH, min(Room.height - 0.35 - halfH, p.y))
    let maxR = Room.radius - 0.35 - halfW
    let r = hypot(p.x, p.z)
    if r > maxR, r > 0.01 { p.x *= maxR / r; p.z *= maxR / r }
    return p
  }

  // ---------------------------------------------------------------- outside props

  private func updateProps(now: TimeInterval, eye: SIMD3<Float>, part: String) {
    let out = part == "outside"
    props.isHidden = !out
    guard out else { return }
    let ground: (Float, Float) -> Float = { [outside] x, z in outside.groundY(x, z) }
    // Science's rock sits where the robot works.
    let rk = CrewMarks.rock(ground: ground)
    rock.simdPosition = rk
    let sci = bots["science"]
    let grinding = sci.map { $0.isVisible && $0.armOut } ?? false
    rock.isHidden = !(sci?.alpha ?? 0 > 0.01)
    // Dust puffs and a spark while grinding.
    let top = rk + SIMD3(0, 0.62, 0)
    let toUser = SIMD3(eye.x - rk.x, 0, eye.z - rk.z)
    let faceYaw = atan2(toUser.x, toUser.z)
    if grinding && now >= nextPuff {
      nextPuff = now + 0.11
      if let i = dust.firstIndex(where: { now - $0.born > 1.2 }) {
        let ang = Float.random(in: 0...(2 * .pi))
        dust[i].born = now
        dust[i].vel = SIMD3(cos(ang) * 0.22, Float.random(in: 0.35...0.7), sin(ang) * 0.22)
        dust[i].node.simdPosition = top + SIMD3(Float.random(in: -0.1...0.1), 0, Float.random(in: -0.1...0.1))
        dust[i].node.isHidden = false
      }
    }
    for i in dust.indices {
      let age = Float(now - dust[i].born)
      let n = dust[i].node
      if age > 1.2 { n.isHidden = true; continue }
      n.simdPosition += dust[i].vel * (1.0 / 60)
      let s = 0.6 + 1.5 * age
      n.simdScale = SIMD3(repeating: s)
      n.opacity = CGFloat(0.55 * (1 - age / 1.2))
      n.simdEulerAngles = SIMD3(0, faceYaw, 0)
    }
    sparkNode.isHidden = !grinding
    if grinding {
      sparkNode.simdPosition = top + SIMD3(0, 0.03, 0)
      sparkNode.simdEulerAngles = SIMD3(0, faceYaw, 0)
      sparkNode.opacity = CGFloat(0.5 + 0.5 * abs(sin(Float(now) * 31)))
    }
    // Supply: scan beam to the crates and the 34/36 hologram.
    let sup = bots["supply"]
    let scanning = sup.map { $0.isVisible && $0.task == "lander" } ?? false
    beamHolder.isHidden = !scanning
    holo.node.isHidden = !scanning
    if scanning, let s = sup {
      let c = CrewMarks.crates(ground: ground)
      let origin = s.node.simdPosition + SIMD3(0, -0.05, 0)
      let sweep = SIMD3<Float>(sin(Float(now) * 1.4) * 0.9, sin(Float(now) * 0.9) * 0.25, cos(Float(now) * 1.4) * 0.5)
      let tgt = c.crates + sweep
      let len = simd_distance(origin, tgt)
      if abs(len - beamLen) > 0.05 { beamLen = len; beamCone.height = CGFloat(len); beamCone.bottomRadius = CGFloat(max(0.25, len * 0.12)) ; beamHolder.childNodes.first?.position = SCNVector3(0, 0, -len / 2) }
      beamHolder.simdPosition = origin
      beamHolder.look(at: SCNVector3(tgt), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
      // Hologram: above and beside Supply, facing the judge, scaled so it reads from afar.
      let toJ = SIMD3(eye.x - origin.x, 0, eye.z - origin.z)
      let d = max(1, simd_length(toJ))
      let k = max(1, min(5, d / 3.5))
      let radial = toJ / d
      let rt = SIMD3<Float>(radial.z, 0, -radial.x)
      holo.node.simdPosition = origin + rt * (0.75 * k) + SIMD3(0, 0.55 * k + 0.2, 0)
      holo.node.simdScale = SIMD3(repeating: k)
      holo.node.simdEulerAngles = SIMD3(0, atan2(toJ.x, toJ.z), 0)
      holo.node.opacity = CGFloat(0.85 + 0.15 * sin(Float(now) * 5))
    }
  }

  // ---------------------------------------------------------------- taps

  /// The Cardboard button with the reticle on `robot`. Returns a label when the crew handled it (a cue), else nil
  /// (the caller falls through to tap-to-ask).
  func handleTap(robot id: String?, now: TimeInterval) -> String? {
    guard let id, let bot = bots[id], bot.isVisible, cue == id, let director else { return nil }
    switch id {
    case "science":
      guard !director.closeUp.isOpen else { return nil }
      openCloseUp?()
      autoCloseAt = now + 5
      link?.tap(target: "science")
      return "close-up"
    case "engineer":
      RealityCheck.toggle()
      link?.tap(target: "engineer")
      return RealityCheck.shared.wantOn ? "reality check" : "reality check off"
    default:
      return nil
    }
  }
}
