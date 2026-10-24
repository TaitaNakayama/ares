import SceneKit
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Texture helpers for the interior: Poly Haven 1k maps from the bundle, composited with code-drawn
/// wear so a handful of small images carry the "lived-in" look. Everything is built once at launch.
enum Tex {
  /// A bundled image (flat resources) as a CGImage.
  static func cg(_ name: String, _ ext: String = "jpg") -> CGImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext),
          let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
  }

  /// Draws `img` into a top-left-origin context (the Bitmap convention) without it landing upside down.
  static func draw(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: r.minX, y: r.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    ctx.restoreGState()
  }

  /// Small deterministic generator so every launch (and the Mac spectator) paints the same wear.
  struct RNG {
    var s: UInt64
    mutating func next() -> CGFloat {
      s = s &* 6364136223846793005 &+ 1442695040888963407
      return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
  }

  static func material(_ image: Any?, repeats: Bool = false, mip: Bool = true) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .lambert
    m.diffuse.contents = image
    if mip { m.diffuse.mipFilter = .linear }
    m.diffuse.minificationFilter = .linear
    m.diffuse.magnificationFilter = .linear
    if repeats { m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat }
    return m
  }

  // ---------------------------------------------------------------- wall panel

  /// One painted-metal wall panel (0.35 m x 3.2 m): warm paint over the ribbed shutter relief, seams,
  /// rivets, grime near the floor and scuffs at hand height. `variant` shifts the relief and wear.
  static func wallPanel(variant: Int) -> PlatformImage {
    let size = CGSize(width: 128, height: 1024)
    let tint: [PlatformColor] = [
      PlatformColor(red: 0.78, green: 0.78, blue: 0.75, alpha: 1),
      PlatformColor(red: 0.74, green: 0.74, blue: 0.70, alpha: 1),
      PlatformColor(red: 0.80, green: 0.80, blue: 0.77, alpha: 1),
    ]
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      var rng = RNG(s: UInt64(1234 + variant * 77))
      c.setFillColor(tint[variant % 3].cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      if let relief = cg("painted_metal_shutter_diff_1k") {
        c.saveGState()
        c.setBlendMode(.softLight)
        c.setAlpha(0.7)
        Tex.draw(c, relief, in: CGRect(x: -CGFloat(variant) * 160, y: 0, width: 512, height: 1024))
        c.restoreGState()
      }
      if let grunge = cg("metal_plate_02_diff_1k") {
        // Floor grime and hand-height scuffs, clipped to their bands.
        for (y0, y1, a) in [(CGFloat(780), CGFloat(1024), CGFloat(0.55)), (CGFloat(560), CGFloat(700), CGFloat(0.28)), (CGFloat(0), CGFloat(60), CGFloat(0.35))] {
          c.saveGState()
          c.clip(to: CGRect(x: 0, y: y0, width: size.width, height: y1 - y0))
          c.setBlendMode(.multiply)
          c.setAlpha(a)
          Tex.draw(c, grunge, in: CGRect(x: -CGFloat(variant) * 200, y: y0 - 100, width: 512, height: 512))
          c.restoreGState()
        }
      }
      // Soft darkening toward the floor (ambient occlusion by hand) and a rim of dirt at the top.
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      if let g = CGGradient(colorsSpace: cs, colors: [PlatformColor(white: 0, alpha: 0.0).cgColor, PlatformColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 0.45).cgColor] as CFArray, locations: [0, 1]) {
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 800), end: CGPoint(x: 0, y: 1024), options: [])
      }
      // Scuff strokes at hand height (light paint-through marks).
      for _ in 0..<14 {
        let x = rng.next() * 110 + 8, y = 560 + rng.next() * 160
        c.setStrokeColor(PlatformColor(red: 0.95, green: 0.9, blue: 0.82, alpha: 0.18 + rng.next() * 0.2).cgColor)
        c.setLineWidth(1 + rng.next() * 1.5)
        c.move(to: CGPoint(x: x, y: y))
        c.addLine(to: CGPoint(x: x + rng.next() * 26 - 6, y: y + rng.next() * 12))
        c.strokePath()
      }
      // Seams and rivets.
      c.setFillColor(PlatformColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0.75).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 3, height: 1024))
      c.fill(CGRect(x: 125, y: 0, width: 3, height: 1024))
      c.setFillColor(PlatformColor(white: 1, alpha: 0.10).cgColor)
      c.fill(CGRect(x: 3, y: 0, width: 2, height: 1024))
      for y in stride(from: CGFloat(40), through: 980, by: 135) {
        for x in [CGFloat(14), CGFloat(114)] {
          c.setFillColor(PlatformColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.7).cgColor)
          c.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
          c.setFillColor(PlatformColor(white: 1, alpha: 0.22).cgColor)
          c.fillEllipse(in: CGRect(x: x - 3, y: y - 4, width: 4, height: 4))
        }
      }
    }
  }

  // ---------------------------------------------------------------- floor

  /// Rubber-tile floor: the Poly Haven tiles lifted from near-black to charcoal, with the old centre rings.
  static func floorImage() -> PlatformImage {
    let size = CGSize(width: 1024, height: 1024)
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      c.setFillColor(PlatformColor(red: 0.20, green: 0.19, blue: 0.19, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      if let t = cg("rubber_tiles_diff_1k") {
        // 3 x 3 repeats across the 8.1 m disc: tiles about 0.7 m x 1.35 m.
        for i in 0..<3 { for j in 0..<3 {
          c.saveGState()
          c.setAlpha(1)
          Tex.draw(c, t, in: CGRect(x: CGFloat(i) * 341.34, y: CGFloat(j) * 341.34, width: 341.34, height: 341.34))
          c.restoreGState()
        } }
        // Lift the near-black rubber toward a warm charcoal.
        c.setBlendMode(.screen)
        c.setFillColor(PlatformColor(red: 0.22, green: 0.20, blue: 0.19, alpha: 1).cgColor)
        c.fill(CGRect(origin: .zero, size: size))
        c.setBlendMode(.normal)
      }
      c.setStrokeColor(PlatformColor(white: 1, alpha: 0.07).cgColor)
      c.setLineWidth(3)
      for r in stride(from: 90.0, through: 500.0, by: 100.0) {
        c.strokeEllipse(in: CGRect(x: 512 - r, y: 512 - r, width: 2 * r, height: 2 * r))
      }
      // Yellow safety ring around the commander's spot and a worn path.
      c.setStrokeColor(PlatformColor(red: 0.9, green: 0.5, blue: 0.22, alpha: 0.55).cgColor)
      c.setLineWidth(6)
      c.strokeEllipse(in: CGRect(x: 512 - 140, y: 512 - 140, width: 280, height: 280))
      if let g = cg("metal_plate_02_diff_1k") {
        c.saveGState()
        c.setBlendMode(.multiply)
        c.setAlpha(0.18)
        Tex.draw(c, g, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        c.restoreGState()
      }
    }
  }

  // ---------------------------------------------------------------- ceiling

  static func ceilingImage() -> PlatformImage {
    let size = CGSize(width: 512, height: 512)
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      c.setFillColor(PlatformColor(red: 0.62, green: 0.58, blue: 0.53, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      if let g = cg("metal_plate_02_diff_1k") {
        c.saveGState()
        c.setBlendMode(.softLight)
        Tex.draw(c, g, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        c.restoreGState()
      }
      c.setStrokeColor(PlatformColor(red: 0.12, green: 0.1, blue: 0.08, alpha: 0.5).cgColor)
      c.setLineWidth(2)
      for i in 0...8 {
        let p = CGFloat(i) * 64
        c.move(to: CGPoint(x: p, y: 0)); c.addLine(to: CGPoint(x: p, y: 512))
        c.move(to: CGPoint(x: 0, y: p)); c.addLine(to: CGPoint(x: 512, y: p))
      }
      c.strokePath()
    }
  }

  // ---------------------------------------------------------------- misc

  /// Brushed aluminium strip.
  static func brushed() -> PlatformImage {
    let size = CGSize(width: 256, height: 64)
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      var rng = RNG(s: 99)
      c.setFillColor(PlatformColor(red: 0.62, green: 0.63, blue: 0.64, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      for y in 0..<64 {
        let v = 0.5 + rng.next() * 0.2
        c.setFillColor(PlatformColor(white: v, alpha: 0.55).cgColor)
        c.fill(CGRect(x: 0, y: CGFloat(y), width: 256, height: 1))
      }
    }
  }

  /// Soft radial glow for sprites (white-ish; tint with the material colour). Additive, no bloom pass.
  static func glow(_ color: PlatformColor) -> PlatformImage {
    let size = CGSize(width: 128, height: 128)
    return Bitmap.image(size: size, scale: 1) { c in
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      let (r, g, b, _) = color.rgba()
      let cols = [PlatformColor(red: r, green: g, blue: b, alpha: 1).cgColor,
                  PlatformColor(red: r, green: g, blue: b, alpha: 0.35).cgColor,
                  PlatformColor(red: r, green: g, blue: b, alpha: 0).cgColor]
      if let grad = CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: [0, 0.4, 1]) {
        c.drawRadialGradient(grad, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
      }
    }
  }

  /// Additive, depth-tested but not depth-writing glow material.
  static func glowMaterial(_ color: PlatformColor, strength: CGFloat = 1) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = glow(color)
    m.blendMode = .add
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    m.transparency = strength
    return m
  }
}
