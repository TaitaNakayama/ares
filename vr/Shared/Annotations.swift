import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// A flat in-world sprite drawn with CoreText into a transparent texture (rounded labels, bubbles, arrows).
/// Redrawn only when its key changes, off the render thread.
final class SpritePanel {
  let node: SCNNode
  private let material = SCNMaterial()
  private let pixelSize: CGSize
  private var lastKey = ""
  private var generation = 0
  private static let queue = DispatchQueue(label: "ares.sprites", qos: .userInitiated)

  init(width: CGFloat, height: CGFloat, pixelsPerMeter: CGFloat) {
    pixelSize = CGSize(width: width * pixelsPerMeter, height: height * pixelsPerMeter)
    let plane = SCNPlane(width: width, height: height)
    material.lightingModel = .constant
    material.isDoubleSided = true
    material.diffuse.contents = PlatformColor.clear
    material.diffuse.mipFilter = .linear
    material.writesToDepthBuffer = false
    plane.materials = [material]
    node = SCNNode(geometry: plane)
    node.renderingOrder = 80
  }

  func update(key: String, _ draw: @escaping (CGContext, CGSize) -> Void) {
    guard key != lastKey else { return }
    lastKey = key
    generation += 1
    let gen = generation
    let size = pixelSize
    Self.queue.async { [weak self] in
      let img = Bitmap.image(size: size, scale: 1, opaque: false) { ctx in draw(ctx, size) }
      DispatchQueue.main.async {
        guard let self, gen == self.generation else { return }
        self.material.diffuse.contents = img
      }
    }
  }
}

enum RoleLabel {
  static func title(_ role: String) -> String {
    switch role {
    case "requester": return "Requester"
    case "receiver": return "Receiver"
    case "ap": return "AP"
    case "treasury": return "Treasury"
    case "controller": return "Controller"
    default: return role.capitalized
    }
  }
}

/// Small vector icons for the five crew members, drawn in code (y down). `rect` is the square to draw in.
enum CrewIcon {
  static func draw(_ ctx: CGContext, id: String, in rect: CGRect, color: PlatformColor) {
    let s = min(rect.width, rect.height)
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.scaleBy(x: s, y: s)
    ctx.setFillColor(color.cgColor)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    func rrect(_ r: CGRect, _ rad: CGFloat) { ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); ctx.fillPath() }
    switch id {
    case "engineer": // wrench
      ctx.rotate(by: -.pi / 4)
      rrect(CGRect(x: -0.085, y: -0.12, width: 0.17, height: 0.62), 0.07)
      ctx.fillEllipse(in: CGRect(x: -0.2, y: -0.52, width: 0.4, height: 0.4))
      ctx.setBlendMode(.clear)
      ctx.fill(CGRect(x: -0.075, y: -0.56, width: 0.15, height: 0.26))
      ctx.setBlendMode(.normal)
    case "life": // droplet
      let p = CGMutablePath()
      p.move(to: CGPoint(x: 0, y: -0.5))
      p.addCurve(to: CGPoint(x: 0.3, y: 0.15), control1: CGPoint(x: 0.08, y: -0.28), control2: CGPoint(x: 0.3, y: -0.08))
      p.addCurve(to: CGPoint(x: 0, y: 0.48), control1: CGPoint(x: 0.3, y: 0.36), control2: CGPoint(x: 0.16, y: 0.48))
      p.addCurve(to: CGPoint(x: -0.3, y: 0.15), control1: CGPoint(x: -0.16, y: 0.48), control2: CGPoint(x: -0.3, y: 0.36))
      p.addCurve(to: CGPoint(x: 0, y: -0.5), control1: CGPoint(x: -0.3, y: -0.08), control2: CGPoint(x: -0.08, y: -0.28))
      ctx.addPath(p)
      ctx.fillPath()
    case "science": // microscope
      rrect(CGRect(x: -0.32, y: 0.36, width: 0.64, height: 0.11), 0.04)
      rrect(CGRect(x: -0.08, y: 0.18, width: 0.34, height: 0.07), 0.03)
      ctx.setLineWidth(0.09)
      ctx.addArc(center: CGPoint(x: -0.02, y: 0.06), radius: 0.30, startAngle: -0.9, endAngle: 1.5, clockwise: false)
      ctx.strokePath()
      ctx.saveGState()
      ctx.translateBy(x: 0.02, y: -0.14)
      ctx.rotate(by: -0.45)
      rrect(CGRect(x: -0.09, y: -0.34, width: 0.18, height: 0.5), 0.05)
      rrect(CGRect(x: -0.05, y: 0.14, width: 0.1, height: 0.12), 0.02)
      ctx.restoreGState()
    case "supply": // box with tape
      rrect(CGRect(x: -0.4, y: -0.3, width: 0.8, height: 0.66), 0.07)
      ctx.setBlendMode(.clear)
      ctx.fill(CGRect(x: -0.07, y: -0.3, width: 0.14, height: 0.24))
      ctx.fill(CGRect(x: -0.4, y: -0.12, width: 0.8, height: 0.035))
      ctx.setBlendMode(.normal)
    default: // rules: shield with a check
      let p = CGMutablePath()
      p.move(to: CGPoint(x: 0, y: -0.5))
      p.addLine(to: CGPoint(x: 0.38, y: -0.34))
      p.addCurve(to: CGPoint(x: 0, y: 0.5), control1: CGPoint(x: 0.38, y: 0.2), control2: CGPoint(x: 0.14, y: 0.4))
      p.addCurve(to: CGPoint(x: -0.38, y: -0.34), control1: CGPoint(x: -0.14, y: 0.4), control2: CGPoint(x: -0.38, y: 0.2))
      p.closeSubpath()
      ctx.addPath(p)
      ctx.fillPath()
      ctx.setBlendMode(.clear)
      ctx.setLineWidth(0.09)
      ctx.move(to: CGPoint(x: -0.15, y: 0.0)); ctx.addLine(to: CGPoint(x: -0.03, y: 0.14)); ctx.addLine(to: CGPoint(x: 0.17, y: -0.14))
      ctx.strokePath()
      ctx.setBlendMode(.normal)
    }
    ctx.restoreGState()
  }
}

/// Always-readable label above a robot: icon + one-word name, in the agent's colour. `active` (speaking) fills the pill.
final class Nametag {
  let node: SCNNode
  private let sprite: SpritePanel
  private let name: String, role: String, color: PlatformColor
  private var suffix = ""
  private var active = false
  init(name: String, role: String, color: PlatformColor) {
    self.name = name; self.role = CrewIDs.id(forRole: role); self.color = color
    let w: CGFloat = 1.12, h: CGFloat = 0.17
    sprite = SpritePanel(width: w, height: h, pixelsPerMeter: 800)
    node = sprite.node
    node.name = "nametag"
    node.renderingOrder = 70
    redraw()
  }

  /// " · thinking…" or " · tap to ask" after the name; "" for none.
  func setSuffix(_ s: String) {
    guard s != suffix else { return }
    suffix = s
    redraw()
  }

  /// The agent is speaking: the pill fills with its colour.
  func setActive(_ on: Bool) {
    guard on != active else { return }
    active = on
    redraw()
  }

  private func redraw() {
    let label = name + suffix
    let color = self.color, id = role, active = self.active
    sprite.update(key: "\(label)|\(active)") { ctx, size in
      let bg = active ? PlatformColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.98) : PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.92)
      Draw.fill(ctx, CGRect(origin: .zero, size: size), bg, radius: size.height / 2)
      if active { Draw.fill(ctx, CGRect(origin: .zero, size: size), color.withAlphaComponent(0.30), radius: size.height / 2) }
      ctx.setStrokeColor(color.withAlphaComponent(0.95).cgColor)
      ctx.setLineWidth(active ? 9 : 5)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: size.height / 2 - 3, cornerHeight: size.height / 2 - 3, transform: nil))
      ctx.strokePath()
      let ih = size.height * 0.62
      let iconRect = CGRect(x: size.height * 0.30, y: (size.height - ih) / 2, width: ih, height: ih)
      CrewIcon.draw(ctx, id: id, in: iconRect, color: color)
      let left = iconRect.maxX + size.height * 0.12
      var fs: CGFloat = 70
      var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      while (label as NSString).size(withAttributes: [.font: font]).width > size.width - left - 40, fs > 30 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
      let tw = (label as NSString).size(withAttributes: [.font: font]).width
      _ = Draw.text(label, at: CGPoint(x: left + (size.width - left - 30 - tw) / 2, y: (size.height - font.lineHeight) / 2), size: fs, weight: .heavy, color: color, width: size.width)
    }
  }
}

/// Speech bubble with a tail toward the speaker. The tail is on the left or right edge.
final class SpeechBubble {
  let node: SCNNode
  private let sprite: SpritePanel
  static let w: CGFloat = 1.5, h: CGFloat = 0.62
  /// Outdoor bubbles (see `enlarge`) get a bigger name header.
  fileprivate var headerScale: CGFloat = 1
  init() {
    sprite = SpritePanel(width: Self.w, height: Self.h, pixelsPerMeter: 760)
    node = sprite.node
    node.name = "bubble"
    node.opacity = 0
    node.isHidden = true
  }

  /// `tailLeft`: the speaker is to the bubble's left (as seen by the viewer).
  func set(text: String, name: String, color: PlatformColor, deny: Bool, tailLeft: Bool, key: String, icon: String? = nil) {
    let hsc = headerScale
    sprite.update(key: "\(key)|\(tailLeft)|\(hsc)|\(icon ?? "")") { ctx, size in
      let tail: CGFloat = 70
      let body = CGRect(x: tailLeft ? tail : 0, y: 0, width: size.width - tail, height: size.height).insetBy(dx: 4, dy: 4)
      let bg = PlatformColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 0.95)
      // Tail: a triangle from the lower side edge toward the speaker.
      let ty = body.maxY - 80
      let p = CGMutablePath()
      if tailLeft {
        p.move(to: CGPoint(x: body.minX + 2, y: ty - 34)); p.addLine(to: CGPoint(x: 2, y: ty + 40)); p.addLine(to: CGPoint(x: body.minX + 2, y: ty + 34))
      } else {
        p.move(to: CGPoint(x: body.maxX - 2, y: ty - 34)); p.addLine(to: CGPoint(x: size.width - 2, y: ty + 40)); p.addLine(to: CGPoint(x: body.maxX - 2, y: ty + 34))
      }
      p.closeSubpath()
      ctx.setFillColor(color.cgColor)
      ctx.addPath(p)
      ctx.fillPath()
      Draw.fill(ctx, body.insetBy(dx: -4, dy: -4), color, radius: 44)
      Draw.fill(ctx, body.insetBy(dx: 5, dy: 5), bg, radius: 40)
      let hs = 42 * hsc
      let headH = hs * 1.25
      var nameX = body.minX + 36
      if let icon {
        CrewIcon.draw(ctx, id: icon, in: CGRect(x: nameX, y: body.minY + 14, width: hs * 1.2, height: hs * 1.2), color: color)
        nameX += hs * 1.2 + 14
      }
      _ = Draw.text(name.uppercased(), at: CGPoint(x: nameX, y: body.minY + 18), size: hs, weight: .heavy, color: color)
      if deny {
        let rs = hs * 0.9
        let rw = ("REFUSED" as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: rs, weight: .heavy)]).width
        _ = Draw.text("REFUSED", at: CGPoint(x: body.maxX - rw - 36, y: body.minY + 20), size: rs, weight: .heavy, color: Palette.red)
      }
      // Never truncate: wrap to as many lines as fit at the largest size (up to 64 px), shrinking only when even that does not fit.
      let top = body.minY + 18 + headH + 6
      let avail = body.maxY - 22 - top, tw = body.width - 72
      var fs: CGFloat = 64
      while true {
        let f = PlatformFont.systemFont(ofSize: fs, weight: .bold)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let r = (text as NSString).boundingRect(with: CGSize(width: tw, height: 4000), options: [.usesLineFragmentOrigin], attributes: [.font: f, .paragraphStyle: para], context: nil)
        if ceil(r.height) <= avail || fs <= 22 { break }
        fs -= 2
      }
      let lh = PlatformFont.systemFont(ofSize: fs, weight: .bold).lineHeight
      _ = Draw.text(text, at: CGPoint(x: body.minX + 36, y: top), size: fs, weight: .bold, color: Palette.text, width: tw, maxLines: max(3, Int(avail / lh) + 1))
    }
  }
}

/// Head-locked arrow at the edge of the view, pointing toward an off-screen speaker.
final class OffscreenArrow {
  let node = SCNNode()
  private let sprite = SpritePanel(width: 0.2, height: 0.2, pixelsPerMeter: 600)
  init() {
    node.addChildNode(sprite.node)
    sprite.node.renderingOrder = 9_000
    sprite.node.geometry?.firstMaterial?.readsFromDepthBuffer = false
    node.isHidden = true
  }

  func setColor(_ c: PlatformColor, key: String) {
    sprite.update(key: key) { ctx, size in
      let c0 = CGPoint(x: size.width / 2, y: size.height / 2)
      Draw.fill(ctx, CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.88), radius: size.width / 2)
      let r = size.width * 0.30
      let p = CGMutablePath()
      p.move(to: CGPoint(x: c0.x + r, y: c0.y))
      p.addLine(to: CGPoint(x: c0.x - r * 0.55, y: c0.y - r * 0.95))
      p.addLine(to: CGPoint(x: c0.x - r * 0.25, y: c0.y))
      p.addLine(to: CGPoint(x: c0.x - r * 0.55, y: c0.y + r * 0.95))
      p.closeSubpath()
      ctx.setFillColor(c.cgColor)
      ctx.addPath(p)
      ctx.fillPath()
    }
  }

  /// `v` is the target direction in head space (x right, y up, -z forward).
  /// Returns head-space position and in-plane angle for the arrow, or nil when the target is in view.
  static func place(local v: SIMD3<Float>) -> (pos: SIMD3<Float>, angle: Float)? {
    let tx: Float = tan(40 * .pi / 180), ty: Float = tan(30 * .pi / 180)
    if v.z < -0.1, abs(v.x / -v.z) < tx, abs(v.y / -v.z) < ty { return nil }
    var dx = v.x, dy = v.y
    if hypot(dx, dy) < 0.001 { dx = 1; dy = 0 }
    let n = simd_normalize(SIMD2(dx, dy))
    let d: Float = 1.2
    // Keep the arrow inside the view: scale the direction onto a rounded rectangle.
    let hx = d * 0.80, hy = d * 0.55
    let s = min(hx / max(abs(n.x), 0.001), hy / max(abs(n.y), 0.001))
    return (SIMD3(n.x * s, n.y * s, -d), atan2(n.y, n.x))
  }
}

/// World-space rectangles of the wall screens, so tags and bubbles can keep out of their way
/// (measured as angular boxes from the commander's seat).
enum ScreenRects {
  struct Rect { let center: SIMD3<Float>; let right: SIMD3<Float>; let w: Float; let h: Float }
  nonisolated(unsafe) static var all: [Rect] = []

  struct Box { var az0: Float, az1: Float, el0: Float, el1: Float }

  private static func wrap(_ a: Float) -> Float {
    var d = a
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
  }

  /// Angular box (azimuth relative to `refAz`, elevation) of a rectangle seen from `user`.
  static func box(center: SIMD3<Float>, right: SIMD3<Float>, w: Float, h: Float, user: SIMD3<Float>, refAz: Float) -> Box {
    var b = Box(az0: .infinity, az1: -.infinity, el0: .infinity, el1: -.infinity)
    for sx in [Float(-0.5), 0.5] {
      for sy in [Float(-0.5), 0.5] {
        let v = center + right * (w * sx) + SIMD3(0, h * sy, 0) - user
        let az = wrap(atan2(v.x, -v.z) - refAz)
        let el = atan2(v.y, hypot(v.x, v.z))
        b.az0 = min(b.az0, az); b.az1 = max(b.az1, az)
        b.el0 = min(b.el0, el); b.el1 = max(b.el1, el)
      }
    }
    return b
  }

  /// Overlap area (radians squared) of a billboard of w x h at `center` with any screen, as seen from `user`.
  static func overlap(center: SIMD3<Float>, w: Float, h: Float, user: SIMD3<Float>, pad: Float = 0.03) -> Float {
    let d = center - user
    let refAz = atan2(d.x, -d.z)
    let dir = SIMD3<Float>(d.x, 0, d.z)
    let n = simd_length(dir) > 0.01 ? simd_normalize(dir) : SIMD3<Float>(0, 0, -1)
    let right = SIMD3<Float>(-n.z, 0, n.x)
    let a = box(center: center, right: right, w: w, h: h, user: user, refAz: refAz)
    var total: Float = 0
    for s in all {
      let b = box(center: s.center, right: s.right, w: s.w, h: s.h, user: user, refAz: refAz)
      let ox = min(a.az1 + pad, b.az1) - max(a.az0 - pad, b.az0)
      let oy = min(a.el1 + pad, b.el1) - max(a.el0 - pad, b.el0)
      if ox > 0, oy > 0 { total += ox * oy }
    }
    return total
  }
}

/// A world consequence made visible: something the commander chose that the scene should show.
/// Add a case and handle it in `BaseScene.applyState`; today only the ice drill.
enum Consequence: Hashable {
  case iceDrillOffline

  static func active(in st: VRState) -> Set<Consequence> {
    var s = Set<Consequence>()
    if st.power?.drillOn == false { s.insert(.iceDrillOffline) }
    return s
  }
}

/// Outdoor sizing: the judge stands 5 to 30 m from the speakers (3 m indoors), so tags and bubbles are drawn larger.
/// The scale is applied about the edge that must stay put (the tail edge of a bubble, the lower edge of a tag), so a bigger
/// bubble grows away from its speaker instead of over it. Indoor labels never call this.
extension SpeechBubble {
  /// `tailLeft`: the speaker is to the bubble's left (the tail edge stays fixed there).
  func enlarge(_ k: CGFloat, tailLeft: Bool, lift: CGFloat = 0) {
    headerScale = 1.5
    let kk = SCNFloat(k)
    let inv: SCNFloat = 1 / kk
    let sign: SCNFloat = tailLeft ? -1 : 1
    let halfW = SCNFloat(Self.w / 2), halfH = SCNFloat(Self.h / 2)
    node.scale = SCNVector3(kk, kk, kk)
    node.pivot = SCNMatrix4MakeTranslation(halfW * (1 - inv) * sign, -halfH * (1 - inv) - SCNFloat(lift) * inv, 0) // `lift` metres up, clear of the nametag
  }
}
