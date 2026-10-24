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
      _ = Draw.text(text, at: CGPoint(x: body.minX + 36, y: body.minY + 80), size: 64, weight: .bold, color: Palette.text, width: body.width - 72, maxLines: 3)
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
