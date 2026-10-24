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
      // Warm light pool from the ceiling strips: a soft gradient over the top of the wall (baked, no light cost).
      if let g = CGGradient(colorsSpace: cs, colors: [PlatformColor(red: 1.0, green: 0.72, blue: 0.40, alpha: 0.42).cgColor, PlatformColor(red: 1.0, green: 0.72, blue: 0.40, alpha: 0.12).cgColor, PlatformColor(red: 1.0, green: 0.72, blue: 0.40, alpha: 0.0).cgColor] as CFArray, locations: [0, 0.45, 1]) {
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 340), options: [])
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
    let n: CGFloat = 1024
    let size = CGSize(width: n, height: n)
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      c.setFillColor(PlatformColor(red: 0.62, green: 0.58, blue: 0.53, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      if let g = cg("metal_plate_02_diff_1k") {
        c.saveGState()
        c.setBlendMode(.softLight)
        Tex.draw(c, g, in: CGRect(x: 0, y: 0, width: n, height: n))
        c.restoreGState()
      }
      // Panel grid (1 m panels), seams with a lighter lip, rivets at the corners.
      c.setStrokeColor(PlatformColor(red: 0.12, green: 0.1, blue: 0.08, alpha: 0.55).cgColor)
      c.setLineWidth(3)
      let step = n / 8
      for i in 0...8 {
        let p = CGFloat(i) * step
        c.move(to: CGPoint(x: p, y: 0)); c.addLine(to: CGPoint(x: p, y: n))
        c.move(to: CGPoint(x: 0, y: p)); c.addLine(to: CGPoint(x: n, y: p))
      }
      c.strokePath()
      c.setStrokeColor(PlatformColor(white: 1, alpha: 0.10).cgColor)
      c.setLineWidth(2)
      for i in 0...8 {
        let p = CGFloat(i) * step + 4
        c.move(to: CGPoint(x: p, y: 0)); c.addLine(to: CGPoint(x: p, y: n))
        c.move(to: CGPoint(x: 0, y: p)); c.addLine(to: CGPoint(x: n, y: p))
      }
      c.strokePath()
      c.setFillColor(PlatformColor(white: 0.2, alpha: 0.55).cgColor)
      for i in 0..<8 { for j in 0..<8 {
        for (dx, dy) in [(CGFloat(14), CGFloat(14)), (step - 14, 14), (14, step - 14), (step - 14, step - 14)] {
          c.fillEllipse(in: CGRect(x: CGFloat(i) * step + dx - 3, y: CGFloat(j) * step + dy - 3, width: 6, height: 6))
        }
      } }
      // Grime streaks.
      var rng = RNG(s: 7)
      for _ in 0..<40 {
        let x = rng.next() * n, y = rng.next() * n
        c.setFillColor(PlatformColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 0.05 + rng.next() * 0.07).cgColor)
        c.fillEllipse(in: CGRect(x: x, y: y, width: 40 + rng.next() * 120, height: 20 + rng.next() * 50))
      }
      // Darker edge gradient toward the walls (the disc spans the full texture).
      let cs = CGColorSpaceCreateDeviceRGB()
      let cols = [CGColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0), CGColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0.10), CGColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0.72)] as CFArray
      if let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0.5, 0.72, 1.0]) {
        c.drawRadialGradient(g, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: n / 2 * 1.02, options: [.drawsAfterEndLocation])
      }
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

  /// A bundled colour map pulled toward grey (`amount` 0...1 of the saturation removed) and slightly darkened,
  /// so saturated props sit in the painted-metal palette while keeping a hint of their colour.
  static func muted(_ name: String, amount: CGFloat) -> PlatformImage {
    let size = CGSize(width: 1024, height: 1024)
    return Bitmap.image(size: size, scale: 1, opaque: true) { c in
      if let img = cg(name) { Tex.draw(c, img, in: CGRect(origin: .zero, size: size)) }
      c.setBlendMode(.saturation)
      c.setFillColor(PlatformColor(white: 0.5, alpha: amount).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      c.setBlendMode(.multiply)
      c.setFillColor(PlatformColor(red: 0.84, green: 0.82, blue: 0.78, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
    }
  }

  /// Soft contact shadow: a dark core that fills the footprint (about 80% of the square) and a wide soft falloff
  /// to the edge, drawn as nested rounded rectangles so boxes get box-shaped shadows.
  static func blob() -> PlatformImage {
    let size = CGSize(width: 128, height: 128)
    return Bitmap.image(size: size, scale: 1) { c in
      let layers = 30
      for i in 0..<layers {
        let inset = 3 + CGFloat(i) * 0.42
        let r = CGRect(x: inset, y: inset, width: 128 - inset * 2, height: 128 - inset * 2)
        c.setFillColor(PlatformColor(red: 0.015, green: 0.01, blue: 0.008, alpha: 0.115).cgColor)
        c.addPath(CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil))
        c.fillPath()
      }
    }
  }

  /// Soft round drop shadow for floating pads (radial falloff, 128 px).
  static func discShadow() -> PlatformImage {
    let size = CGSize(width: 128, height: 128)
    return Bitmap.image(size: size, scale: 1) { c in
      let cs = CGColorSpaceCreateDeviceRGB()
      let cols = [CGColor(red: 0.01, green: 0.008, blue: 0.006, alpha: 0.9), CGColor(red: 0.01, green: 0.008, blue: 0.006, alpha: 0.45), CGColor(red: 0.01, green: 0.008, blue: 0.006, alpha: 0)] as CFArray
      if let g = CGGradient(colorsSpace: cs, colors: cols, locations: [0, 0.55, 1]) {
        c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
      }
    }
  }

  /// Contact shadow: a rounded rect, dark across the core, fading over `fx` / `fy` (fractions of the width / height) at the
  /// edge. 128 px; the caller sizes the plane so the fade is the same ~0.2 m on every footprint.
  static func contact(fx: CGFloat, fy: CGFloat) -> PlatformImage {
    let size = CGSize(width: 128, height: 128)
    return Bitmap.image(size: size, scale: 1) { c in
      let layers = 48
      for i in 0..<layers {
        let t = CGFloat(i) / CGFloat(layers - 1)
        let ix = 2 + t * fx * 124, iy = 2 + t * fy * 124
        let r = CGRect(x: ix, y: iy, width: 128 - ix * 2, height: 128 - iy * 2)
        c.setFillColor(PlatformColor(red: 0.012, green: 0.008, blue: 0.006, alpha: 0.075).cgColor)
        c.addPath(CGPath(roundedRect: r, cornerWidth: min(r.width, r.height) * 0.3, cornerHeight: min(r.width, r.height) * 0.3, transform: nil))
        c.fillPath()
      }
    }
  }

  /// Round floor drain grille: rim, dark bowl, radial slats, bolts. 512 px.
  static func drain() -> PlatformImage {
    let size = CGSize(width: 512, height: 512)
    return Bitmap.image(size: size, scale: 1) { c in
      let ctr = CGPoint(x: 256, y: 256)
      c.setFillColor(PlatformColor(white: 0.0, alpha: 0.35).cgColor)
      c.fillEllipse(in: CGRect(x: 6, y: 6, width: 500, height: 500))
      c.setFillColor(PlatformColor(red: 0.40, green: 0.39, blue: 0.37, alpha: 1).cgColor)
      c.fillEllipse(in: CGRect(x: 36, y: 36, width: 440, height: 440))
      c.setFillColor(PlatformColor(red: 0.27, green: 0.26, blue: 0.25, alpha: 1).cgColor)
      c.fillEllipse(in: CGRect(x: 52, y: 52, width: 408, height: 408))
      c.setFillColor(PlatformColor(white: 0.03, alpha: 1).cgColor)
      c.fillEllipse(in: CGRect(x: 76, y: 76, width: 360, height: 360))
      // grille bars
      c.setStrokeColor(PlatformColor(red: 0.43, green: 0.42, blue: 0.40, alpha: 1).cgColor)
      c.setLineWidth(14)
      c.saveGState()
      c.addEllipse(in: CGRect(x: 76, y: 76, width: 360, height: 360)); c.clip()
      for i in 0..<9 { let y = 76 + CGFloat(i) * 45; c.move(to: CGPoint(x: 70, y: y)); c.addLine(to: CGPoint(x: 442, y: y)); c.strokePath() }
      c.setLineWidth(10)
      c.move(to: CGPoint(x: 256, y: 70)); c.addLine(to: CGPoint(x: 256, y: 442)); c.strokePath()
      c.restoreGState()
      // rim highlight and bolts
      c.setStrokeColor(PlatformColor(white: 0.62, alpha: 0.5).cgColor); c.setLineWidth(4)
      c.strokeEllipse(in: CGRect(x: 40, y: 40, width: 432, height: 432))
      c.setFillColor(PlatformColor(white: 0.12, alpha: 1).cgColor)
      for k in 0..<8 {
        let a = CGFloat(k) * .pi / 4 + .pi / 8
        c.fillEllipse(in: CGRect(x: ctr.x + cos(a) * 196 - 8, y: ctr.y + sin(a) * 196 - 8, width: 16, height: 16))
      }
    }
  }

  /// A worn walking path (kind 0 of this function): a soft light strip along +x with scuff streaks, 512x128.
  static func pathWear() -> PlatformImage {
    let size = CGSize(width: 512, height: 128)
    return Bitmap.image(size: size, scale: 1) { c in
      var rng = RNG(s: 4242)
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      let cols = [PlatformColor(white: 0.88, alpha: 0.0).cgColor, PlatformColor(white: 0.88, alpha: 0.22).cgColor, PlatformColor(white: 0.88, alpha: 0.0).cgColor]
      if let g = CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: [0, 0.5, 1]) {
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 128), options: [])
      }
      // fade the two ends
      c.setBlendMode(.destinationIn)
      let ends = [PlatformColor(white: 0, alpha: 0).cgColor, PlatformColor(white: 0, alpha: 1).cgColor, PlatformColor(white: 0, alpha: 1).cgColor, PlatformColor(white: 0, alpha: 0).cgColor]
      if let g = CGGradient(colorsSpace: cs, colors: ends as CFArray, locations: [0, 0.18, 0.82, 1]) {
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 512, y: 0), options: [])
      }
      c.setBlendMode(.normal)
      c.setLineCap(.round)
      for _ in 0..<30 {
        let x = rng.next() * 420 + 30, y = 30 + rng.next() * 68
        c.setStrokeColor(PlatformColor(white: rng.next() > 0.4 ? 0.9 : 0.0, alpha: 0.08 + rng.next() * 0.1).cgColor)
        c.setLineWidth(1.5 + rng.next() * 3)
        c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + 20 + rng.next() * 70, y: y + rng.next() * 6 - 3)); c.strokePath()
      }
    }
  }

  /// Scuffed matte screen bezel, front face: dark grey-blue paint, edge wear, scratches and four screws.
  /// `border` is the visible frame width as a fraction of the shorter side (the centre is hidden by the screen).
  static func bezel(size: CGSize) -> PlatformImage {
    Bitmap.image(size: size, scale: 1, opaque: true) { c in
      var rng = RNG(s: 909)
      c.setFillColor(PlatformColor(red: 0.20, green: 0.215, blue: 0.23, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      if let img = cg("metal_plate_02_diff_1k") {
        c.setAlpha(0.22); c.setBlendMode(.overlay)
        Tex.draw(c, img, in: CGRect(origin: .zero, size: size))
        c.setAlpha(1); c.setBlendMode(.normal)
      }
      c.setLineCap(.round)
      for _ in 0..<70 {
        let x = rng.next() * size.width, y = rng.next() * size.height
        let l = 8 + rng.next() * 40
        c.setStrokeColor(PlatformColor(white: rng.next() > 0.45 ? 0.75 : 0.02, alpha: 0.10 + rng.next() * 0.16).cgColor)
        c.setLineWidth(1 + rng.next() * 2.2)
        let a = rng.next() * .pi
        c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l)); c.strokePath()
      }
      // worn edges
      c.setStrokeColor(PlatformColor(white: 0.62, alpha: 0.35).cgColor); c.setLineWidth(3)
      c.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
      c.setStrokeColor(PlatformColor(white: 0, alpha: 0.35).cgColor); c.setLineWidth(5)
      c.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14))
      for (x, y) in [(CGFloat(18), CGFloat(18)), (size.width - 18, 18), (18, size.height - 18), (size.width - 18, size.height - 18)] {
        c.setFillColor(PlatformColor(white: 0.07, alpha: 1).cgColor); c.fillEllipse(in: CGRect(x: x - 8, y: y - 8, width: 16, height: 16))
        c.setFillColor(PlatformColor(white: 0.5, alpha: 0.7).cgColor); c.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 6, height: 6))
      }
    }
  }

  /// Floor decals: kind 0 = yellow stand-clear line with chevrons, 1 = scuffs and tyre-ish streaks, 2 = worn path.
  static func floorMarks(kind: Int) -> PlatformImage {
    let size = kind == 0 ? CGSize(width: 512, height: 128) : CGSize(width: 512, height: 512)
    return Bitmap.image(size: size, scale: 1) { c in
      var rng = RNG(s: UInt64(700 + kind))
      switch kind {
      case 0:
        c.setFillColor(PlatformColor(red: 0.88, green: 0.68, blue: 0.14, alpha: 0.55).cgColor)
        c.fill(CGRect(x: 0, y: 8, width: 512, height: 14))
        c.fill(CGRect(x: 0, y: 106, width: 512, height: 14))
        c.setStrokeColor(PlatformColor(red: 0.88, green: 0.68, blue: 0.14, alpha: 0.5).cgColor)
        c.setLineWidth(12)
        for i in 0..<5 {
          let x = 70 + CGFloat(i) * 90
          c.move(to: CGPoint(x: x, y: 34)); c.addLine(to: CGPoint(x: x + 28, y: 64)); c.addLine(to: CGPoint(x: x, y: 94))
        }
        c.strokePath()
        c.setBlendMode(.destinationOut) // worn gaps
        c.setFillColor(PlatformColor(white: 0, alpha: 0.55).cgColor)
        for _ in 0..<16 { c.fill(CGRect(x: rng.next() * 500, y: rng.next() * 120, width: 6 + rng.next() * 30, height: 4 + rng.next() * 8)) }
      case 1:
        c.setLineCap(.round)
        for _ in 0..<26 {
          let x = rng.next() * 440 + 30, y = rng.next() * 440 + 30
          let l = 30 + rng.next() * 110, a = rng.next() * 0.5 - 0.25
          c.setStrokeColor(PlatformColor(white: rng.next() > 0.5 ? 0.85 : 0.0, alpha: 0.04 + rng.next() * 0.07).cgColor)
          c.setLineWidth(2 + rng.next() * 5)
          c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + l, y: y + l * a)); c.strokePath()
        }
      default:
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let cols = [PlatformColor(white: 0.85, alpha: 0.16).cgColor, PlatformColor(white: 0.85, alpha: 0).cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: [0, 1]) {
          c.saveGState()
          c.translateBy(x: 256, y: 256); c.scaleBy(x: 1, y: 0.4); c.translateBy(x: -256, y: -256)
          c.drawRadialGradient(g, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256), endRadius: 256, options: [])
          c.restoreGState()
        }
        for _ in 0..<10 {
          let x = rng.next() * 400 + 50, y = 210 + rng.next() * 90
          c.setStrokeColor(PlatformColor(white: 0.9, alpha: 0.12).cgColor)
          c.setLineWidth(2 + rng.next() * 3)
          c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + 60 + rng.next() * 80, y: y + rng.next() * 10 - 5)); c.strokePath()
        }
      }
    }
  }

  /// Alpha-blended decal that lies on a surface: unlit, no depth write.
  static func decalMaterial(_ image: Any?) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = image
    m.diffuse.mipFilter = .linear
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    return m
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
