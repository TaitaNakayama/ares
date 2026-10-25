import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The SHOW side of the Mars crew demo: the title and end cards, the window text, and how the world state (`world.*`,
/// `scene.*`, `money.*`) turns into things you can see and hear. The crew (robots, bubbles, look-at) is Crew.swift / Robots.swift.
///
/// Everything here reads the show contract in docs/demo/script.md (decoded by `VRState` in Link.swift) and is cheap per frame:
/// a few sprite panels whose textures redraw only when their text changes.
final class ShowDirector {
  // MARK: the contract, as the scene needs it

  /// The dust level that drives the sky, the fog and the storm wall (tau 0.6 clear ... 4.6 storm).
  /// `world.dust` (0...1) is authoritative when the server sends a world; older states use `tau`.
  static func effectiveTau(_ st: VRState) -> Double {
    if let d = st.world?.dust { return 0.6 + 4.0 * max(0, min(1, d)) }
    return st.tau ?? 0.6
  }

  // MARK: cards

  private let titleText = SpritePanel(width: 1.3, height: 0.5, pixelsPerMeter: 700)
  private var cameraCards: [(black: SCNNode, text: SCNNode)] = []
  private var blackTarget: Float = 0
  private var blackLevel: Float = 0
  private var textLevel: Float = 0
  private var shownSub = ""
  /// The cue pill on the headset (the spectator draws its own in the overlay).
  var showsCuePill = true
  /// The Mac spectator draws window and end titles as flat overlays (whole and centred whatever the head does); it hides these.
  var showsTitleCards = true
  private let cuePill = SpritePanel(width: 0.74, height: 0.1, pixelsPerMeter: 700)
  private var cuePillNodes: [SCNNode] = []
  private var cueShown = ""
  private var cueLevel: Float = 0
  private var quoteGlanceUntil: TimeInterval = 0
  private var hadQuote = false
  private var shownBlackText = ""
  /// The window text ("25 MINUTES LATER") and the end card, both drawn on the glass.
  private let windowText = SpritePanel(width: 3.4, height: 1.4, pixelsPerMeter: 360)
  private let endCard = SpritePanel(width: 3.5, height: 1.5, pixelsPerMeter: 360)
  private var windowTarget: Float = 0
  private var windowLevel: Float = 0
  private var endTarget: Float = 0
  private var endLevel: Float = 0
  private var windowShown = ""
  private var lastNow: TimeInterval = 0

  /// What is on show right now, for the spectator overlay (it mirrors these cards).
  private(set) var title: (text: String, style: String)?
  /// "science" | "door" | "card" | "engineer" | nil.
  private(set) var cue: String?
  private(set) var act: String?

  private weak var outside: Outside?

  init(scene: SCNScene, outside: Outside) {
    self.outside = outside
    for (panel, y, order, w, h) in [(windowText, Float(2.58), 90, Float(3.4), Float(1.4)), (endCard, Float(1.74), 91, Float(3.5), Float(1.5))] {
      let n = panel.node
      n.position = Room.ring(0, r: 2.2, y: y) // in front of the crew (Rules hovers at the console, 2.6 m out), same visual size as at the glass
      n.simdScale = SIMD3(repeating: (panel === windowText ? 1.6 : 2.2) / 3.5) // the window title sits high and a bit smaller (clear of the ice drill's sign)
      n.look(at: SCNVector3(0, y, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      n.renderingOrder = order
      n.opacity = 0
      n.isHidden = true
      panel.node.geometry?.firstMaterial?.isDoubleSided = false
      // Always in front of the robots, their tags and bubbles.
      panel.node.geometry?.firstMaterial?.readsFromDepthBuffer = false
      n.renderingOrder = 8_000 + order
      _ = (w, h)
      scene.rootNode.addChildNode(n)
    }
    titleText.node.geometry?.firstMaterial?.readsFromDepthBuffer = false
  }

  /// The title card lives on the camera (a black quad, then the text), so it covers whatever is in front of it.
  func attach(to camera: SCNNode) {
    let q = SCNNode(geometry: SCNPlane(width: 6, height: 6))
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = PlatformColor.black
    m.readsFromDepthBuffer = false
    m.writesToDepthBuffer = false
    q.geometry?.materials = [m]
    q.position = SCNVector3(0, 0, -0.24)
    q.renderingOrder = 30_500
    q.opacity = CGFloat(blackLevel)
    q.isHidden = blackLevel <= 0.001
    camera.addChildNode(q)
    let t = titleText.node.clone() // shares the geometry (and so the texture)
    t.position = SCNVector3(0, 0, -0.9)
    t.renderingOrder = 31_000
    t.opacity = CGFloat(blackLevel)
    t.isHidden = blackLevel <= 0.001
    camera.addChildNode(t)
    cameraCards.append((q, t))
    if showsCuePill {
      let c = cuePill.node.clone()
      c.position = SCNVector3(0, -0.34, -0.9)
      c.renderingOrder = 31_100
      c.opacity = 0
      c.isHidden = true
      c.geometry?.firstMaterial?.readsFromDepthBuffer = false
      camera.addChildNode(c)
      cuePillNodes.append(c)
    }
  }

  /// Where the window / end title hangs (world), for the spectator's director camera; nil when none is up.
  var titleAim: SIMD3<Float>? {
    if windowTarget > 0 { return windowText.node.simdPosition }
    if endTarget > 0 { return endCard.node.simdPosition }
    return nil
  }

  /// A window or end title is up: nametags and bubbles step aside.
  var labelsHidden: Bool { windowTarget > 0 || endTarget > 0 }

  /// The flagged quote just appeared: the director looks at the centre screen for about 3 s.
  func quoteGlance(now: TimeInterval) -> Bool { now < quoteGlanceUntil }

  // MARK: state

  func apply(_ st: VRState, now: TimeInterval) {
    act = st.scene?.act
    cue = st.scene?.cue
    applyWorld(st.world)
    let hasQuote = st.world?.quote != nil
    if hasQuote && !hadQuote { quoteGlanceUntil = lastNow + 3 }
    hadQuote = hasQuote
    let rc = st.scene?.reality
    RealityCheck.shared.configure(offer: rc?.offer ?? false, caption: rc?.caption, credit: rc?.credit, enter: rc?.enter ?? false)
    RealityCheck.shared.follow(serverOn: rc?.on)
    let ti = st.scene?.title
    let text = ti?.text ?? ""
    let style = ti?.style ?? ""
    title = text.isEmpty ? nil : (text, style)
    // Black title: opaque black with the text. It fades in quickly and out slowly (the real terrain fades in).
    if style == "black" && !text.isEmpty {
      blackTarget = 1
      let sub = ti?.sub ?? ""
      if text != shownBlackText || sub != shownSub {
        shownBlackText = text
        shownSub = sub
        drawTitle(text, sub: sub)
        if blackLevel == 0 && lastNow == 0 { blackLevel = 1 } // the very first state: no flash of the world before the title
      }
    } else {
      blackTarget = 0
    }
    windowTarget = style == "window" && !text.isEmpty ? 1 : 0
    endTarget = style == "end" && !text.isEmpty ? 1 : 0
    if windowTarget > 0 && text != windowShown {
      windowShown = text
      drawWindow(text)
    }
    if endTarget > 0 && text != endShown {
      endShown = text
      drawEnd(text)
    }
  }

  private var endShown = ""

  // MARK: the world (the crisis and its consequences)

  /// `world.*` -> what you can see and hear: the solar field outside fades with `power.panels`, the alarm sounds while
  /// `alarm`, the lab's lights follow `lab`, the ice drill follows `drill`. (The window's darkness is `dust` via the tau.)
  private func applyWorld(_ w: VRState.World?) {
    guard let w else { return }
    outside?.setPanels(level: Float(w.power?.panels ?? 1))
    Sound.shared.setAlarm(w.alarm ?? false)
    Room.alarm?.setActive(w.alarm ?? false)
    Dressing.lab?.set(on: (w.lab ?? "on") != "paused")
    if let d = w.drill { outside?.setDrill(on: d != "off") }
  }

  private func drawTitle(_ text: String, sub: String) {
    titleText.update(key: "t2|" + text + "|" + sub) { ctx, size in
      var fs: CGFloat = 76
      var font = PlatformFont.systemFont(ofSize: fs, weight: .semibold)
      let kern: CGFloat = 5
      func width(_ f: PlatformFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: f, .kern: kern]).width }
      while width(font) > size.width - 30, fs > 22 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .semibold) }
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PlatformColor(white: 0.96, alpha: 1), .kern: kern, .paragraphStyle: para]
      // The title alone sits in the middle; with a sub line the pair is centred (title above, the stake smaller and dimmer below).
      let subFont = PlatformFont.systemFont(ofSize: 38, weight: .medium)
      let subPara = NSMutableParagraphStyle()
      subPara.alignment = .center
      subPara.lineBreakMode = .byWordWrapping
      let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: PlatformColor(white: 0.66, alpha: 1), .paragraphStyle: subPara]
      let subH = sub.isEmpty ? 0 : ceil((sub as NSString).boundingRect(with: CGSize(width: size.width - 80, height: 400), options: [.usesLineFragmentOrigin], attributes: subAttrs, context: nil).height)
      let gap: CGFloat = sub.isEmpty ? 0 : 26
      let top = (size.height - (font.lineHeight + gap + subH)) / 2
      (text as NSString).draw(with: CGRect(x: 0, y: top, width: size.width, height: font.lineHeight), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
      if !sub.isEmpty {
        (sub as NSString).draw(with: CGRect(x: 40, y: top + font.lineHeight + gap, width: size.width - 80, height: subH + 4), options: [.usesLineFragmentOrigin], attributes: subAttrs, context: nil)
      }
    }
  }

  private func drawWindow(_ text: String) {
    // "SCAM BLOCKED · $1.4M SAVED" goes on two big lines; "25 MINUTES LATER" stays on one.
    let lines = text.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    windowText.update(key: "w2|" + text) { ctx, size in
      var fs: CGFloat = 150
      func font(_ f: CGFloat) -> PlatformFont { PlatformFont.systemFont(ofSize: f, weight: .heavy) }
      func widest(_ f: CGFloat) -> CGFloat { lines.map { ($0 as NSString).size(withAttributes: [.font: font(f), .kern: 6]).width }.max() ?? 0 }
      while widest(fs) > size.width - 140, fs > 30 { fs -= 4 }
      let lh = font(fs).lineHeight
      let total = lh * CGFloat(lines.count)
      let r = CGRect(x: 6, y: (size.height - total) / 2 - 34, width: size.width - 12, height: total + 68)
      Draw.fill(ctx, r, PlatformColor(red: 0.06, green: 0.04, blue: 0.03, alpha: 0.62), radius: min(r.height / 2, 90))
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      for (i, l) in lines.enumerated() {
        let c = (lines.count > 1 && i == lines.count - 1) ? PlatformColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1) : PlatformColor(white: 0.97, alpha: 1)
        (l as NSString).draw(with: CGRect(x: 0, y: (size.height - total) / 2 + CGFloat(i) * lh, width: size.width, height: lh), options: [.usesLineFragmentOrigin], attributes: [.font: font(fs), .foregroundColor: c, .kern: 6, .paragraphStyle: para], context: nil)
      }
    }
  }

  private func drawEnd(_ text: String) {
    // "An AI crew that keeps a Mars base alive. And knows when to ask you." -> one line per sentence.
    var lines: [String] = []
    var cur = ""
    for ch in text {
      cur.append(ch)
      if ch == "." { lines.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
    }
    if !cur.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(cur.trimmingCharacters(in: .whitespaces)) }
    endCard.update(key: "e|" + text) { ctx, size in
      let r = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
      Draw.fill(ctx, r, PlatformColor(red: 0.05, green: 0.035, blue: 0.03, alpha: 0.72), radius: 44)
      ctx.setStrokeColor(PlatformColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 0.9).cgColor)
      ctx.setLineWidth(5)
      ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 3, dy: 3), cornerWidth: 42, cornerHeight: 42, transform: nil))
      ctx.strokePath()
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      // Both lines at one size, the first in white, the second in amber.
      var fs: CGFloat = 78
      func fits(_ f: CGFloat) -> Bool {
        let font = PlatformFont.systemFont(ofSize: f, weight: .heavy)
        return lines.allSatisfy { ($0 as NSString).size(withAttributes: [.font: font]).width < size.width - 110 }
      }
      while !fits(fs), fs > 24 { fs -= 2 }
      let font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      let total = font.lineHeight * CGFloat(lines.count) * 1.12
      var y = (size.height - total) / 2
      for (i, l) in lines.enumerated() {
        let c = i == 0 ? PlatformColor(white: 0.97, alpha: 1) : PlatformColor(red: 1.0, green: 0.74, blue: 0.34, alpha: 1)
        (l as NSString).draw(with: CGRect(x: 0, y: y, width: size.width, height: font.lineHeight), options: [.usesLineFragmentOrigin], attributes: [.font: font, .foregroundColor: c, .paragraphStyle: para], context: nil)
        y += font.lineHeight * 1.12
      }
    }
  }

  // MARK: per frame

  func update(now: TimeInterval) {
    let dt = Float(min(0.1, max(0, now - lastNow)))
    lastNow = now == 0 ? 0.0001 : now
    // Black: in at once-ish (0.35 s); out within 0.4 s (the text a little sooner), so it never hangs over the world.
    if blackLevel < blackTarget { blackLevel = min(blackTarget, blackLevel + dt / 0.35) } else if blackLevel > blackTarget { blackLevel = max(blackTarget, blackLevel - dt / 0.4) }
    if textLevel < blackTarget { textLevel = min(blackTarget, textLevel + dt / 0.35) } else if textLevel > blackTarget { textLevel = max(blackTarget, textLevel - dt / 0.25) }
    for c in cameraCards {
      c.black.opacity = CGFloat(blackLevel)
      c.black.isHidden = blackLevel <= 0.001
      c.text.opacity = CGFloat(textLevel)
      c.text.isHidden = textLevel <= 0.001
    }
    if windowLevel < windowTarget { windowLevel = min(windowTarget, windowLevel + dt / 0.8) } else if windowLevel > windowTarget { windowLevel = max(windowTarget, windowLevel - dt / 0.3) }
    windowText.node.opacity = CGFloat(windowLevel)
    windowText.node.isHidden = windowLevel <= 0.001 || !showsTitleCards
    if endLevel < endTarget { endLevel = min(endTarget, endLevel + dt / 1.2) } else if endLevel > endTarget { endLevel = max(endTarget, endLevel - dt / 0.3) }
    endCard.node.opacity = CGFloat(endLevel)
    endCard.node.isHidden = endLevel <= 0.001 || !showsTitleCards
    Room.alarm?.update(now: now)
    // The cue pill (headset): "LOOK AT AN OPTION · TAP TO CHOOSE" and friends, in the cue's colour.
    let want = showsCuePill ? Self.cuePillText(cue) : nil
    if let w = want, w != cueShown { cueShown = w; drawCuePill(w, color: cue) }
    let cueTarget: Float = (want != nil && blackLevel < 0.3 && windowLevel < 0.1 && endLevel < 0.1) ? 1 : 0
    cueLevel += (cueTarget - cueLevel) * min(1, dt * 8)
    for n in cuePillNodes {
      n.opacity = CGFloat(cueLevel)
      n.isHidden = cueLevel < 0.02
    }
  }

  /// Text of the cue pill, or nil for none. (The headset has the door's own sign and the Science glow.)
  static func cuePillText(_ cue: String?) -> String? {
    switch cue {
    case "card": return "LOOK AT AN OPTION · TAP TO CHOOSE"
    case "enter": return "TAP TO ENTER THE SIMULATION"
    case "engineer": return "LOOK AT Engineer · TAP"
    case "science": return "LOOK AT Science · TAP"
    default: return nil
    }
  }

  private func drawCuePill(_ text: String, color: String?) {
    let accent: PlatformColor = (color == "science" || color == "engineer") ? ShowColors.crew(color) : Palette.amber
    cuePill.update(key: "cue|" + text) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.82), radius: size.height / 2)
      ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
      ctx.setLineWidth(4)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerWidth: size.height / 2 - 2, cornerHeight: size.height / 2 - 2, transform: nil))
      ctx.strokePath()
      var fs: CGFloat = 46
      var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      while (text as NSString).size(withAttributes: [.font: font, .kern: 1.5]).width > size.width - 50, fs > 20 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
      let w = (text as NSString).size(withAttributes: [.font: font, .kern: 1.5]).width
      (text as NSString).draw(at: CGPoint(x: (size.width - w) / 2, y: (size.height - font.lineHeight) / 2), withAttributes: [.font: font, .foregroundColor: accent, .kern: 1.5])
    }
  }

  /// The black title is covering the view (the spectator hides its own card then).
  var blackCovering: Bool { blackLevel > 0.5 }
}
