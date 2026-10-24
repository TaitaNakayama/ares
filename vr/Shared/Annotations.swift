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

/// "Rule Keeper · Controller": always-readable label above a robot, in its colour.
final class Nametag {
  let node: SCNNode
  private let sprite: SpritePanel
  private let name: String, role: String, color: PlatformColor
  private var suffix = ""
  init(name: String, role: String, color: PlatformColor) {
    self.name = name; self.role = role; self.color = color
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

  private func redraw() {
    let label = "\(name) · \(RoleLabel.title(role))" + suffix
    let color = self.color
    sprite.update(key: label) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.92), radius: size.height / 2)
      ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
      ctx.setLineWidth(5)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: size.height / 2 - 3, cornerHeight: size.height / 2 - 3, transform: nil))
      ctx.strokePath()
      var fs: CGFloat = 70
      var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      while (label as NSString).size(withAttributes: [.font: font]).width > size.width - 70, fs > 30 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
      let tw = (label as NSString).size(withAttributes: [.font: font]).width
      _ = Draw.text(label, at: CGPoint(x: (size.width - tw) / 2, y: (size.height - font.lineHeight) / 2), size: fs, weight: .heavy, color: color, width: size.width)
    }
  }
}

/// Speech bubble with a tail toward the speaker. The tail is on the left or right edge.
final class SpeechBubble {
  let node: SCNNode
  private let sprite: SpritePanel
  static let w: CGFloat = 1.5, h: CGFloat = 0.62
  init() {
    sprite = SpritePanel(width: Self.w, height: Self.h, pixelsPerMeter: 760)
    node = sprite.node
    node.name = "bubble"
    node.opacity = 0
    node.isHidden = true
  }

  /// `tailLeft`: the speaker is to the bubble's left (as seen by the viewer).
  func set(text: String, name: String, color: PlatformColor, deny: Bool, tailLeft: Bool, key: String) {
    sprite.update(key: "\(key)|\(tailLeft)") { ctx, size in
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
      _ = Draw.text(name.uppercased(), at: CGPoint(x: body.minX + 36, y: body.minY + 22), size: 42, weight: .heavy, color: color)
      if deny { _ = Draw.text("REFUSED", at: CGPoint(x: body.maxX - 250, y: body.minY + 24), size: 38, weight: .heavy, color: Palette.red) }
      // Fit the whole text: shrink the font until it wraps within the bubble (never cut a word before the last line).
      let avail = body.height - 80 - 22, tw = body.width - 72
      var fs: CGFloat = 64
      var lines = 1
      while true {
        let f = PlatformFont.systemFont(ofSize: fs, weight: .bold)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let r = (text as NSString).boundingRect(with: CGSize(width: tw, height: 4000), options: [.usesLineFragmentOrigin], attributes: [.font: f, .paragraphStyle: para], context: nil)
        lines = max(1, Int((ceil(r.height) / f.lineHeight).rounded()))
        if ceil(r.height) <= avail || fs <= 38 { break }
        fs -= 3
      }
      let lh = PlatformFont.systemFont(ofSize: fs, weight: .bold).lineHeight
      _ = Draw.text(text, at: CGPoint(x: body.minX + 36, y: body.minY + 80), size: fs, weight: .bold, color: Palette.text, width: tw, maxLines: max(lines, Int(avail / lh)))
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
