import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A flat in-world screen whose content is drawn with CoreText into a texture.
/// Redrawn only when its content changes, so it costs nothing per frame.
final class TextPanel {
  let node: SCNNode
  private let material = SCNMaterial()
  private let pixelSize: CGSize
  private var lastKey = ""

  init(width: CGFloat, height: CGFloat, pixelsPerMeter: CGFloat = 640, emissive: Bool = true) {
    pixelSize = CGSize(width: width * pixelsPerMeter, height: height * pixelsPerMeter)
    let plane = SCNPlane(width: width, height: height)
    plane.cornerRadius = min(width, height) * 0.04
    material.lightingModel = .constant
    material.isDoubleSided = false
    material.diffuse.contents = PlatformColor.black
    material.diffuse.mipFilter = .linear
    if emissive { material.emission.contents = PlatformColor.black }
    plane.materials = [material]
    node = SCNNode(geometry: plane)
  }

  /// Panels render off the render thread; the newest request wins.
  private static let queue = DispatchQueue(label: "ares.panels", qos: .userInitiated)
  private var generation = 0

  /// `draw` paints into a context sized `pixelSize` (origin top-left). `key` decides redraws.
  /// Drawing happens on a background queue so the headset never drops a frame for text.
  func update(key: String, _ draw: @escaping (CGContext, CGSize) -> Void) {
    guard key != lastKey else { return }
    lastKey = key
    generation += 1
    let gen = generation
    let size = pixelSize
    Self.queue.async { [weak self] in
      let img = Bitmap.image(size: size, scale: 1, opaque: true) { ctx in draw(ctx, size) }
      DispatchQueue.main.async {
        guard let self, gen == self.generation else { return }
        self.material.diffuse.contents = img
      }
    }
  }
}

enum Palette {
  static let bg = PlatformColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
  static let panel = PlatformColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
  static let text = PlatformColor(white: 0.94, alpha: 1)
  static let dim = PlatformColor(white: 0.62, alpha: 1)
  static let amber = PlatformColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1)
  static let red = PlatformColor(red: 1.0, green: 0.36, blue: 0.33, alpha: 1)
  static let green = PlatformColor(red: 0.38, green: 0.86, blue: 0.55, alpha: 1)
  static let cyan = PlatformColor(red: 0.36, green: 0.84, blue: 0.95, alpha: 1)
  static let gold = PlatformColor(red: 0.98, green: 0.80, blue: 0.30, alpha: 1)
  static let violet = PlatformColor(red: 0.70, green: 0.52, blue: 1.0, alpha: 1)
  static let orange = PlatformColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1)
  static let blue = PlatformColor(red: 0.45, green: 0.66, blue: 1.0, alpha: 1)

  static func role(_ r: String) -> PlatformColor {
    switch r {
    case "requester": return orange
    case "receiver": return green
    case "ap": return cyan
    case "treasury": return gold
    case "controller": return violet
    case "remote_authority": return blue
    default: return text
    }
  }
}

/// Text drawing helpers (bold sans, large: cap height must stay >= ~1.5 deg in the headset).
enum Draw {
  static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: PlatformFont.Weight = .semibold, color: PlatformColor = Palette.text, width: CGFloat? = nil, maxLines: Int = 1, align: NSTextAlignment = .left) -> CGFloat {
    let font = PlatformFont.systemFont(ofSize: size, weight: weight)
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineBreakMode = maxLines == 1 ? .byTruncatingTail : .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    let w = width ?? 4000
    let h = font.lineHeight * CGFloat(maxLines)
    let rect = (s as NSString).boundingRect(with: CGSize(width: w, height: h), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    (s as NSString).draw(with: CGRect(x: p.x, y: p.y, width: w, height: min(h, ceil(rect.height))), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
    return min(h, ceil(rect.height))
  }

  static func fill(_ ctx: CGContext, _ r: CGRect, _ c: PlatformColor, radius: CGFloat = 0) {
    ctx.setFillColor(c.cgColor)
    if radius > 0 {
      #if os(macOS)
      ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
      #else
      ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: radius).cgPath)
      #endif
      ctx.fillPath()
    } else {
      ctx.fill(r)
    }
  }

  static func bar(_ ctx: CGContext, _ r: CGRect, fraction: CGFloat, color: PlatformColor) {
    fill(ctx, r, PlatformColor(white: 1, alpha: 0.12), radius: r.height / 2)
    fill(ctx, CGRect(x: r.minX, y: r.minY, width: max(r.height, r.width * max(0, min(1, fraction))), height: r.height), color, radius: r.height / 2)
  }
}

// MARK: - the decision card (Act 3)

/// The crew's colours (docs/demo/script.md), for the decision card and the spectator overlay.
enum ShowColors {
  static func hex(_ s: String?) -> PlatformColor? {
    guard var h = s?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return PlatformColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
  }

  static func crew(_ id: String?) -> PlatformColor {
    switch id {
    case "engineer": return hex("#4DA3FF")!
    case "life": return hex("#F2F4F7")!
    case "science": return hex("#3BD16F")!
    case "supply": return hex("#FF9A3C")!
    case "rules": return hex("#A97BFF")!
    default: return Palette.amber
    }
  }

  static func name(_ id: String?) -> String {
    guard let id, !id.isEmpty else { return "" }
    return id.prefix(1).uppercased() + id.dropFirst()
  }
}

/// Three large options in an arc in front of the judge (placed where they were looking when the decision came up), each with a
/// big icon, at most four words and the colour of the crew member who will speak its trade-off. Gaze resting 0.6 s on one
/// highlights it (and is reported through `onGaze`); the button chooses the one under the reticle (`tap`).
final class DecisionCards {
  struct Option: Equatable {
    let id: String; let label: String; let icon: String; let speaker: String; let color: PlatformColor
    static func == (a: Option, b: Option) -> Bool { a.id == b.id && a.label == b.label && a.icon == b.icon && a.speaker == b.speaker }
  }
  enum Mark { case idle, gaze, chosen, dim }

  static let cardW: CGFloat = 0.80, cardH: CGFloat = 1.0
  static let ppm: CGFloat = 600
  static let radius: Float = 1.95
  static let dwell: TimeInterval = 0.6

  let root = SCNNode()
  private var panels: [TextPanel] = []
  private var holders: [SCNNode] = []
  private let title = SpritePanel(width: 1.9, height: 0.24, pixelsPerMeter: 500)
  private(set) var options: [Option] = []
  private(set) var decisionId = ""
  /// The option highlighted by gaze (after the dwell), or nil.
  private(set) var gazedIndex: Int?
  /// The option the judge chose (locally), or the server's `chosen`.
  private(set) var chosenIndex: Int?
  /// Visible and accepting gaze and taps.
  private(set) var isActive = false
  var onGaze: ((String?) -> Void)?
  private var wantPlace = true
  private var hitIndex: Int?
  private var hitSince: TimeInterval = 0
  private var reported: String?

  init() {
    for i in 0..<3 {
      let p = TextPanel(width: Self.cardW, height: Self.cardH, pixelsPerMeter: Self.ppm)
      let h = SCNNode()
      h.name = "decision:\(i)"
      h.addChildNode(p.node)
      h.isHidden = true
      root.addChildNode(h)
      panels.append(p)
      holders.append(h)
    }
    title.node.isHidden = true
    title.node.renderingOrder = 85
    root.addChildNode(title.node)
    root.opacity = 0
    root.isHidden = true
  }

  /// The decision from the state (nil or no options = no card).
  func apply(_ d: VRState.Decision?, crew: [String: VRState.Crew]?, now: TimeInterval) {
    let opts: [Option] = (d?.options ?? []).prefix(3).map { o in
      let sp = o.speaker ?? ""
      let c = ShowColors.hex(crew?[sp]?.color) ?? ShowColors.crew(sp)
      return Option(id: o.id, label: o.label ?? o.id, icon: o.icon ?? "", speaker: sp, color: c)
    }
    guard let d, !opts.isEmpty else {
      if isActive { dismiss(after: 0.1) }
      return
    }
    let newId = d.id ?? ""
    if !isActive || newId != decisionId || opts != options {
      let fresh = !isActive || newId != decisionId
      options = opts
      decisionId = newId
      if fresh { chosenIndex = nil; gazedIndex = nil; hitIndex = nil; reported = nil; wantPlace = true }
      isActive = true
      root.isHidden = false
      root.removeAllActions()
      root.runAction(.fadeIn(duration: 0.4))
      if fresh { Sound.shared.play("saved", volume: 0.5) }
      for i in 0..<3 { holders[i].isHidden = i >= opts.count }
      title.update(key: "title") { ctx, size in
        let t = "WHAT DO WE GIVE UP?"
        var fs: CGFloat = 80
        var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
        while ("WHAT DO WE GIVE UP?" as NSString).size(withAttributes: [.font: font, .kern: 4]).width > size.width - 60, fs > 30 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
        let w = (t as NSString).size(withAttributes: [.font: font, .kern: 4]).width
        Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.05, green: 0.045, blue: 0.08, alpha: 0.82), radius: size.height / 2)
        ctx.setStrokeColor(ShowColors.crew("rules").cgColor)
        ctx.setLineWidth(5)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: size.height / 2 - 3, cornerHeight: size.height / 2 - 3, transform: nil))
        ctx.strokePath()
        (t as NSString).draw(at: CGPoint(x: (size.width - w) / 2, y: (size.height - font.lineHeight) / 2), withAttributes: [.font: font, .foregroundColor: PlatformColor(white: 0.96, alpha: 1), .kern: 4])
      }
      title.node.isHidden = false
    }
    // The server's echo of what was chosen (the spectator and a restarted headset agree on it).
    if let ch = d.chosen, let i = opts.firstIndex(where: { $0.id == ch }) { chosenIndex = i }
    refreshMarks()
  }

  private func dismiss(after t: TimeInterval) {
    isActive = false
    gazedIndex = nil
    hitIndex = nil
    // After a local choice the highlight stays up a moment (the `afterChoice` action owns the fade).
    if chosenIndex == nil || root.action(forKey: "afterChoice") == nil {
      root.removeAllActions()
      root.runAction(.sequence([.wait(duration: t), .fadeOut(duration: 0.35), .hide()]))
    }
    if reported != nil { reported = nil; onGaze?(nil) }
  }

  private func refreshMarks() {
    for i in 0..<min(3, options.count) {
      let m: Mark
      if let c = chosenIndex { m = i == c ? .chosen : .dim } else if gazedIndex == i { m = .gaze } else { m = .idle }
      draw(i, m)
    }
  }

  private func draw(_ i: Int, _ mark: Mark) {
    let o = options[i]
    let key = "\(o.id)|\(o.label)|\(o.icon)|\(o.speaker)|\(mark)"
    let accent = o.color
    let name = ShowColors.name(o.speaker)
    panels[i].update(key: key) { ctx, size in
      let bg: PlatformColor
      switch mark {
      case .gaze: bg = PlatformColor(red: 0.17, green: 0.14, blue: 0.08, alpha: 1)
      case .chosen: bg = PlatformColor(red: 0.07, green: 0.20, blue: 0.11, alpha: 1)
      case .dim: bg = PlatformColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1)
      case .idle: bg = PlatformColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
      }
      Draw.fill(ctx, CGRect(origin: .zero, size: size), bg, radius: 36)
      let line: PlatformColor = mark == .gaze ? Palette.amber : mark == .chosen ? Palette.green : accent.withAlphaComponent(mark == .dim ? 0.25 : 0.9)
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: size.width, height: 22), accent.withAlphaComponent(mark == .dim ? 0.3 : 1))
      ctx.setStrokeColor(line.cgColor)
      ctx.setLineWidth(mark == .gaze || mark == .chosen ? 18 : 7)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 9, dy: 9), cornerWidth: 32, cornerHeight: 32, transform: nil))
      ctx.strokePath()
      let ic = accent.withAlphaComponent(mark == .dim ? 0.35 : 1)
      Self.drawIcon(ctx, kind: o.icon, center: CGPoint(x: size.width / 2, y: 188), size: 210, color: ic)
      let tc: PlatformColor = mark == .dim ? PlatformColor(white: 0.5, alpha: 1) : PlatformColor(white: 0.97, alpha: 1)
      _ = Draw.text(o.label, at: CGPoint(x: 28, y: 322), size: 68, weight: .heavy, color: tc, width: size.width - 56, maxLines: 3, align: .center)
      // Who speaks its trade-off.
      if !name.isEmpty {
        ctx.setFillColor(accent.withAlphaComponent(mark == .dim ? 0.35 : 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: 36, y: size.height - 84, width: 26, height: 26))
        _ = Draw.text(name.uppercased(), at: CGPoint(x: 76, y: size.height - 90), size: 40, weight: .heavy, color: accent.withAlphaComponent(mark == .dim ? 0.4 : 1), width: 200)
      }
      if mark == .gaze { _ = Draw.text("TAP", at: CGPoint(x: size.width - 190, y: size.height - 90), size: 44, weight: .heavy, color: Palette.amber, width: 150, align: .right) }
      if mark == .chosen { _ = Draw.text("CHOSEN", at: CGPoint(x: size.width - 250, y: size.height - 90), size: 44, weight: .heavy, color: Palette.green, width: 210, align: .right) }
    }
    let target: CGFloat = mark == .gaze ? 1.07 : 1
    holders[i].removeAction(forKey: "scale")
    holders[i].runAction(.scale(to: target, duration: 0.12), forKey: "scale")
  }

  /// Vector icons (drill, flask, battery) in the speaker's colour.
  static func drawIcon(_ ctx: CGContext, kind: String, center c: CGPoint, size s: CGFloat, color: PlatformColor) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.setStrokeColor(color.cgColor)
    ctx.setFillColor(color.cgColor)
    ctx.setLineWidth(s * 0.055)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    let u = s / 2 // half size
    switch kind {
    case "drill":
      // A rig: the shank and chuck on top, a fluted bit tapering to a point.
      ctx.stroke(CGRect(x: -u * 0.28, y: -u * 0.95, width: u * 0.56, height: u * 0.34))
      ctx.fill(CGRect(x: -u * 0.50, y: -u * 0.62, width: u * 1.0, height: u * 0.18))
      let bit = CGMutablePath()
      bit.move(to: CGPoint(x: -u * 0.32, y: -u * 0.42)); bit.addLine(to: CGPoint(x: u * 0.32, y: -u * 0.42))
      bit.addLine(to: CGPoint(x: u * 0.30, y: u * 0.30)); bit.addLine(to: CGPoint(x: 0, y: u * 0.98)); bit.addLine(to: CGPoint(x: -u * 0.30, y: u * 0.30)); bit.closeSubpath()
      ctx.addPath(bit); ctx.strokePath()
      for k in 0..<4 {
        let y = -u * 0.30 + CGFloat(k) * u * 0.27
        ctx.move(to: CGPoint(x: -u * 0.30, y: y + u * 0.16)); ctx.addLine(to: CGPoint(x: u * 0.30, y: y)); ctx.strokePath()
      }
    case "flask":
      // An Erlenmeyer flask, half full, with bubbles.
      let f = CGMutablePath()
      f.move(to: CGPoint(x: -u * 0.22, y: -u * 0.95)); f.addLine(to: CGPoint(x: -u * 0.22, y: -u * 0.35)); f.addLine(to: CGPoint(x: -u * 0.78, y: u * 0.80))
      f.addLine(to: CGPoint(x: u * 0.78, y: u * 0.80)); f.addLine(to: CGPoint(x: u * 0.22, y: -u * 0.35)); f.addLine(to: CGPoint(x: u * 0.22, y: -u * 0.95))
      ctx.addPath(f); ctx.strokePath()
      ctx.move(to: CGPoint(x: -u * 0.34, y: -u * 0.95)); ctx.addLine(to: CGPoint(x: u * 0.34, y: -u * 0.95)); ctx.strokePath()
      let liquid = CGMutablePath()
      liquid.move(to: CGPoint(x: -u * 0.58, y: u * 0.25)); liquid.addLine(to: CGPoint(x: u * 0.58, y: u * 0.25))
      liquid.addLine(to: CGPoint(x: u * 0.74, y: u * 0.74)); liquid.addLine(to: CGPoint(x: -u * 0.74, y: u * 0.74)); liquid.closeSubpath()
      ctx.addPath(liquid); ctx.fillPath()
      ctx.strokeEllipse(in: CGRect(x: -u * 0.12, y: -u * 0.16, width: u * 0.16, height: u * 0.16))
      ctx.strokeEllipse(in: CGRect(x: u * 0.06, y: -u * 0.34, width: u * 0.11, height: u * 0.11))
    case "battery":
      // A battery cell with a bolt and a terminal.
      let body = CGRect(x: -u * 0.62, y: -u * 0.72, width: u * 1.24, height: u * 1.62)
      ctx.addPath(CGPath(roundedRect: body, cornerWidth: u * 0.16, cornerHeight: u * 0.16, transform: nil)); ctx.strokePath()
      ctx.fill(CGRect(x: -u * 0.24, y: -u * 0.96, width: u * 0.48, height: u * 0.22))
      let bolt = CGMutablePath()
      bolt.move(to: CGPoint(x: u * 0.12, y: -u * 0.54)); bolt.addLine(to: CGPoint(x: -u * 0.34, y: u * 0.14)); bolt.addLine(to: CGPoint(x: -u * 0.02, y: u * 0.14))
      bolt.addLine(to: CGPoint(x: -u * 0.12, y: u * 0.74)); bolt.addLine(to: CGPoint(x: u * 0.36, y: -u * 0.10)); bolt.addLine(to: CGPoint(x: u * 0.04, y: -u * 0.10)); bolt.closeSubpath()
      ctx.addPath(bolt); ctx.fillPath()
    default:
      ctx.strokeEllipse(in: CGRect(x: -u * 0.7, y: -u * 0.7, width: u * 1.4, height: u * 1.4))
    }
    ctx.restoreGState()
  }

  // MARK: per frame

  /// `eye` / `fwd`: the judge's head and where they look (world). Places the cards the first frame, tracks the gaze dwell.
  func update(now: TimeInterval, eye: SIMD3<Float>, fwd: SIMD3<Float>) {
    guard isActive, !root.isHidden else { return }
    if wantPlace {
      wantPlace = false
      var f = SIMD3(fwd.x, 0, fwd.z)
      f = simd_length(f) > 0.05 ? simd_normalize(f) : SIMD3(0, 0, -1)
      let yaw0 = atan2(f.x, -f.z) // 0 = toward -z
      let step = 2 * asin(Float((Self.cardW + 0.10) / 2) / Self.radius)
      let n = max(1, options.count)
      for i in 0..<3 {
        let a = yaw0 + (Float(i) - Float(n - 1) / 2) * step
        let dir = SIMD3<Float>(sin(a), 0, -cos(a))
        let p = eye + dir * Self.radius
        holders[i].simdPosition = SIMD3(p.x, eye.y - 0.02, p.z)
        holders[i].simdLook(at: SIMD3(eye.x, eye.y - 0.02, eye.z), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, 1))
      }
      let tp = eye + SIMD3<Float>(sin(yaw0), 0, -cos(yaw0)) * Self.radius
      title.node.simdPosition = SIMD3(tp.x, eye.y + 0.74, tp.z)
      title.node.simdLook(at: SIMD3(eye.x, eye.y + 0.74, eye.z), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, 1))
    }
    guard chosenIndex == nil else { return }
    let hit = Self.hit(holders: holders, count: options.count, origin: eye, fwd: fwd)
    if hit != hitIndex {
      hitIndex = hit
      hitSince = now
      if gazedIndex != nil && gazedIndex != hit { gazedIndex = nil; refreshMarks() }
      if hit == nil, reported != nil { reported = nil; onGaze?(nil) }
    }
    if let h = hit, now - hitSince >= Self.dwell, gazedIndex != h {
      gazedIndex = h
      refreshMarks()
      Sound.shared.play("hover", volume: 0.5)
      if reported != options[h].id { reported = options[h].id; onGaze?(options[h].id) }
    }
  }

  /// The option under the ray (a little generous), nearest first.
  private static func hit(holders: [SCNNode], count: Int, origin: SIMD3<Float>, fwd: SIMD3<Float>) -> Int? {
    var best: (Int, Float)?
    for i in 0..<min(3, count) where !holders[i].isHidden {
      let inv = holders[i].simdWorldTransform.inverse
      let o = inv * SIMD4(origin.x, origin.y, origin.z, 1)
      let d = inv * SIMD4(fwd.x, fwd.y, fwd.z, 0)
      guard abs(d.z) > 1e-4 else { continue }
      let t = -o.z / d.z
      guard t > 0.2 else { continue }
      let x = o.x + d.x * t, y = o.y + d.y * t
      guard abs(x) < Float(cardW) / 2 * 1.06, abs(y) < Float(cardH) / 2 * 1.06 else { continue }
      if t < (best?.1 ?? .infinity) { best = (i, t) }
    }
    return best?.0
  }

  /// The ray hits a card (for the reticle to grow).
  var isHit: Bool { isActive && hitIndex != nil && chosenIndex == nil }

  /// The button: chooses the card under the reticle. Returns (decision id, option id).
  func tap() -> (String, String)? {
    guard isActive, chosenIndex == nil, let h = hitIndex, h < options.count, !decisionId.isEmpty else { return nil }
    chosenIndex = h
    gazedIndex = nil
    refreshMarks()
    Sound.shared.play("select", volume: 0.9)
    // The highlight stays up a moment, then the cards fade (the server's `decision` goes away on its own).
    root.removeAllActions()
    root.runAction(.sequence([.wait(duration: 2.2), .fadeOut(duration: 0.4), .hide()]), forKey: "afterChoice")
    if reported != nil { reported = nil; onGaze?(nil) }
    return (decisionId, options[h].id)
  }
}
