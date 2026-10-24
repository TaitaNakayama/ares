import SceneKit
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
