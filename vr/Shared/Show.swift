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

  private let titleText = SpritePanel(width: 1.3, height: 0.31, pixelsPerMeter: 700)
  private var cameraCards: [(black: SCNNode, text: SCNNode)] = []
  private var blackTarget: Float = 0
  private var blackLevel: Float = 0
  private var shownBlackText = ""
  /// The window text ("25 MINUTES LATER") and the end card, both drawn on the glass.
  private let windowText = SpritePanel(width: 3.4, height: 0.9, pixelsPerMeter: 360)
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
    for (panel, y, order, w, h) in [(windowText, Float(1.78), 90, Float(3.4), Float(0.9)), (endCard, Float(1.74), 91, Float(3.5), Float(1.5))] {
      let n = panel.node
      n.position = Room.ring(0, r: 2.2, y: y) // in front of the crew (Rules hovers at the console, 2.6 m out), same visual size as at the glass
      n.simdScale = SIMD3(repeating: 2.2 / 3.5)
      n.look(at: SCNVector3(0, y, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      n.renderingOrder = order
      n.opacity = 0
      n.isHidden = true
      panel.node.geometry?.firstMaterial?.isDoubleSided = false
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
  }

  // MARK: state

  func apply(_ st: VRState, now: TimeInterval) {
    act = st.scene?.act
    cue = st.scene?.cue
    applyWorld(st.world)
    let rc = st.scene?.reality
    RealityCheck.shared.configure(offer: rc?.offer ?? false, caption: rc?.caption, credit: rc?.credit)
    let ti = st.scene?.title
    let text = ti?.text ?? ""
    let style = ti?.style ?? ""
    title = text.isEmpty ? nil : (text, style)
    // Black title: opaque black with the text. It fades in quickly and out slowly (the real terrain fades in).
    if style == "black" && !text.isEmpty {
      blackTarget = 1
      if text != shownBlackText {
        shownBlackText = text
        drawTitle(text)
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
    Dressing.lab?.set(on: (w.lab ?? "on") != "paused")
    if let d = w.drill { outside?.setDrill(on: d != "off") }
  }

  private func drawTitle(_ text: String) {
    titleText.update(key: "t|" + text) { ctx, size in
      var fs: CGFloat = 76
      var font = PlatformFont.systemFont(ofSize: fs, weight: .semibold)
      let kern: CGFloat = 5
      func width(_ f: PlatformFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: f, .kern: kern]).width }
      while width(font) > size.width - 30, fs > 22 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .semibold) }
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PlatformColor(white: 0.96, alpha: 1), .kern: kern, .paragraphStyle: para]
      (text as NSString).draw(with: CGRect(x: 0, y: (size.height - font.lineHeight) / 2, width: size.width, height: font.lineHeight), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    }
  }

  private func drawWindow(_ text: String) {
    windowText.update(key: "w|" + text) { ctx, size in
      let r = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 40)
      Draw.fill(ctx, r, PlatformColor(red: 0.06, green: 0.04, blue: 0.03, alpha: 0.55), radius: r.height / 2)
      var fs: CGFloat = 120
      var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      func width(_ f: PlatformFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: f, .kern: 6]).width }
      while width(font) > size.width - 120, fs > 30 { fs -= 4; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      (text as NSString).draw(with: CGRect(x: 0, y: (size.height - font.lineHeight) / 2, width: size.width, height: font.lineHeight), options: [.usesLineFragmentOrigin], attributes: [.font: font, .foregroundColor: PlatformColor(white: 0.97, alpha: 1), .kern: 6, .paragraphStyle: para], context: nil)
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
    // Black: in at once-ish (0.35 s), out over 1.4 s.
    if blackLevel < blackTarget { blackLevel = min(blackTarget, blackLevel + dt / 0.35) } else if blackLevel > blackTarget { blackLevel = max(blackTarget, blackLevel - dt / 1.4) }
    for c in cameraCards {
      c.black.opacity = CGFloat(blackLevel)
      c.black.isHidden = blackLevel <= 0.001
      c.text.opacity = CGFloat(blackLevel)
      c.text.isHidden = blackLevel <= 0.001
    }
    if windowLevel < windowTarget { windowLevel = min(windowTarget, windowLevel + dt / 0.8) } else if windowLevel > windowTarget { windowLevel = max(windowTarget, windowLevel - dt / 1.2) }
    windowText.node.opacity = CGFloat(windowLevel)
    windowText.node.isHidden = windowLevel <= 0.001
    if endLevel < endTarget { endLevel = min(endTarget, endLevel + dt / 1.2) } else if endLevel > endTarget { endLevel = max(endTarget, endLevel - dt / 1.2) }
    endCard.node.opacity = CGFloat(endLevel)
    endCard.node.isHidden = endLevel <= 0.001
  }

  /// The black title is covering the view (the spectator hides its own card then).
  var blackCovering: Bool { blackLevel > 0.5 }
}
