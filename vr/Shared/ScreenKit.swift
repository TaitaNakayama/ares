import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The wall-screen design system. One family (the system font), two weights: `.heavy` for numbers and
/// titles, `.semibold` for labels. Four sizes, none below the smallest text the screens used before
/// (30 px for credit lines). Everything draws into a top-left-origin CGContext (the Bitmap convention).
enum Kit {
  enum Size {
    static let credit: CGFloat = 48   // citations and "SIMULATED" notes (one line each); 86% of the label size
    static let label: CGFloat = 56    // card labels, list rows
    static let value: CGFloat = 64    // secondary numbers, headings
    static let hero: CGFloat = 100    // the one big number on a screen
  }
  /// The palette's screen fill (#9FB7C9): the one blue the screens use, in place of a saturated blue.
  static let screenBlue = PlatformColor(red: 0.624, green: 0.718, blue: 0.788, alpha: 1)
  static let pad: CGFloat = 24
  static let gap: CGFloat = 20

  /// Dark glass: vertical gradient, faint grid and scanlines, thin accent bezel.
  static func chrome(_ ctx: CGContext, _ size: CGSize, accent: PlatformColor) {
    let space = CGColorSpaceCreateDeviceRGB()
    let top = PlatformColor(red: 0.075, green: 0.085, blue: 0.10, alpha: 1).cgColor
    let bot = PlatformColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 1).cgColor
    if let g = CGGradient(colorsSpace: space, colors: [top, bot] as CFArray, locations: [0, 1]) {
      ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    } else {
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
    }
    ctx.setStrokeColor(PlatformColor(white: 1, alpha: 0.035).cgColor)
    ctx.setLineWidth(1)
    var x: CGFloat = 0
    while x <= size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)); x += 48 }
    var y: CGFloat = 0
    while y <= size.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += 48 }
    ctx.strokePath()
    ctx.setFillColor(PlatformColor(white: 0, alpha: 0.10).cgColor)
    y = 0
    while y < size.height { ctx.fill(CGRect(x: 0, y: y, width: size.width, height: 2)); y += 6 }
    inset(ctx, CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5), radius: 18, color: accent.withAlphaComponent(0.55), width: 3)
  }

  static func inset(_ ctx: CGContext, _ r: CGRect, radius: CGFloat, color: PlatformColor, width: CGFloat) {
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.addPath(rounded(r, radius))
    ctx.strokePath()
  }

  static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
  }

  /// A raised glass card.
  static func card(_ ctx: CGContext, _ r: CGRect, accent: PlatformColor? = nil) {
    ctx.addPath(rounded(r, 16)); ctx.setFillColor(PlatformColor(white: 1, alpha: 0.055).cgColor); ctx.fillPath()
    inset(ctx, r, radius: 16, color: (accent ?? PlatformColor(white: 1, alpha: 1)).withAlphaComponent(accent == nil ? 0.10 : 0.35), width: 2)
  }

  /// Footer line (citation / SIMULATED note): `Size.credit`, shrunk only as far as needed to stay on one line (never below 38).
  static func footer(_ s: String, size: CGSize, y: CGFloat? = nil, max top: CGFloat = Size.credit, color: PlatformColor = Palette.dim) {
    var fs = top
    let w = size.width - 56
    while fs > 34, (s as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: fs, weight: .semibold)]).width > w { fs -= 1 }
    _ = Draw.text(s, at: CGPoint(x: 28, y: y ?? size.height - 64), size: fs, weight: .semibold, color: color, width: w)
  }

  /// Right-aligned text ending at `right`.
  static func textRight(_ s: String, right: CGFloat, y: CGFloat, size: CGFloat, weight: PlatformFont.Weight = .semibold, color: PlatformColor = Palette.text, width: CGFloat = 700) {
    _ = Draw.text(s, at: CGPoint(x: right - width, y: y), size: size, weight: weight, color: color, width: width, align: .right)
  }

  /// Header: icon + title on the left, a clock/link readout on the right.
  static func header(_ ctx: CGContext, _ size: CGSize, title: String, color: PlatformColor, icon: Icon.Fn, right: String?, rightIcon: Icon.Fn? = nil, rightColor: PlatformColor = Palette.dim) {
    icon(ctx, CGRect(x: 28, y: 28, width: 52, height: 52), color)
    _ = Draw.text(title, at: CGPoint(x: 96, y: 26), size: 58, weight: .heavy, color: color)
    if let right {
      textRight(right, right: size.width - 32, y: 34, size: Size.label, color: rightColor, width: 560)
      if let rightIcon {
        let w = CGFloat(right.count) * Size.label * 0.56
        rightIcon(ctx, CGRect(x: size.width - 32 - w - 46, y: 34, width: 38, height: 38), rightColor)
      }
    }
  }

  // MARK: gauges

  static func arcPath(_ c: CGPoint, r: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = 64
    for i in 0...steps {
      let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
      let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
  }

  /// 240-degree ring gauge, open at the bottom.
  static func ring(_ ctx: CGContext, center: CGPoint, radius: CGFloat, thickness: CGFloat, fraction: CGFloat, color: PlatformColor) {
    ctx.setLineCap(.round)
    ctx.setLineWidth(thickness)
    ctx.setStrokeColor(PlatformColor(white: 1, alpha: 0.12).cgColor)
    ctx.addPath(arcPath(center, r: radius, from: 150, to: 390)); ctx.strokePath()
    let f = max(0.001, min(1, fraction))
    ctx.setStrokeColor(color.cgColor)
    ctx.addPath(arcPath(center, r: radius, from: 150, to: 150 + 240 * f)); ctx.strokePath()
    ctx.setLineCap(.butt)
  }

  /// Line chart with a soft fill; `lo`/`hi` fix the vertical scale.
  static func spark(_ ctx: CGContext, _ r: CGRect, _ v: [Double], lo: Double, hi: Double, color: PlatformColor, fill: Bool = true) {
    guard v.count > 1, hi > lo else { return }
    func pt(_ i: Int) -> CGPoint {
      CGPoint(x: r.minX + CGFloat(i) / CGFloat(v.count - 1) * r.width,
              y: r.maxY - CGFloat((min(max(v[i], lo), hi) - lo) / (hi - lo)) * r.height)
    }
    let line = CGMutablePath()
    for i in 0..<v.count { if i == 0 { line.move(to: pt(i)) } else { line.addLine(to: pt(i)) } }
    if fill {
      let area = CGMutablePath(); area.addPath(line)
      area.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); area.addLine(to: CGPoint(x: r.minX, y: r.maxY)); area.closeSubpath()
      ctx.addPath(area); ctx.setFillColor(color.withAlphaComponent(0.16).cgColor); ctx.fillPath()
    }
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(5)
    ctx.addPath(line); ctx.strokePath()
    ctx.setLineCap(.butt)
    let e = pt(v.count - 1)
    Draw.fill(ctx, CGRect(x: e.x - 7, y: e.y - 7, width: 14, height: 14), color, radius: 7)
  }

  /// A small status chip: coloured dot + label.
  static func chip(_ ctx: CGContext, at p: CGPoint, text: String, color: PlatformColor, size: CGFloat = Size.label) {
    let w = max(CGFloat(text.count) * size * 0.62 + 72, 150)
    let r = CGRect(x: p.x, y: p.y, width: w, height: size + 22)
    ctx.addPath(rounded(r, r.height / 2)); ctx.setFillColor(color.withAlphaComponent(0.16).cgColor); ctx.fillPath()
    inset(ctx, r, radius: r.height / 2, color: color.withAlphaComponent(0.7), width: 2)
    Draw.fill(ctx, CGRect(x: r.minX + 20, y: r.midY - 8, width: 16, height: 16), color, radius: 8)
    _ = Draw.text(text, at: CGPoint(x: r.minX + 48, y: r.minY + 9), size: size, weight: .heavy, color: color, width: w - 56)
  }
}

/// Simple vector glyphs, drawn into a square-ish rect.
enum Icon {
  typealias Fn = (CGContext, CGRect, PlatformColor) -> Void

  static let bolt: Fn = { ctx, r, c in
    let p = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(0.58, 0), (0.18, 0.56), (0.46, 0.56), (0.38, 1), (0.82, 0.40), (0.54, 0.40)]
    for (i, q) in pts.enumerated() {
      let pt = CGPoint(x: r.minX + q.0 * r.width, y: r.minY + q.1 * r.height)
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(c.cgColor); ctx.fillPath()
  }

  static let battery: Fn = { ctx, r, c in
    let body = CGRect(x: r.minX, y: r.minY + r.height * 0.22, width: r.width * 0.88, height: r.height * 0.56)
    Kit.inset(ctx, body, radius: 6, color: c, width: 4)
    Draw.fill(ctx, CGRect(x: body.maxX + 3, y: r.midY - r.height * 0.12, width: r.width * 0.09, height: r.height * 0.24), c, radius: 2)
    Draw.fill(ctx, CGRect(x: body.minX + 8, y: body.minY + 8, width: body.width * 0.55, height: body.height - 16), c, radius: 3)
  }

  static let coins: Fn = { ctx, r, c in
    for i in 0..<3 {
      let y = r.maxY - r.height * 0.28 - CGFloat(i) * r.height * 0.26
      let e = CGRect(x: r.minX + 2, y: y - r.height * 0.14, width: r.width - 4, height: r.height * 0.28)
      ctx.addEllipse(in: e)
      ctx.setFillColor(PlatformColor(white: 0.07, alpha: 1).cgColor); ctx.fillPath()
      ctx.addEllipse(in: e); ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.strokePath()
    }
  }

  static let antenna: Fn = { ctx, r, c in
    ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
    ctx.addPath(Kit.arcPath(CGPoint(x: r.midX, y: r.minY + r.height * 0.35), r: r.width * 0.42, from: 20, to: 160)); ctx.strokePath()
    ctx.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.35)); ctx.addLine(to: CGPoint(x: r.midX + r.width * 0.28, y: r.minY + r.height * 0.05)); ctx.strokePath()
    ctx.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.55)); ctx.addLine(to: CGPoint(x: r.midX, y: r.maxY)); ctx.strokePath()
    ctx.move(to: CGPoint(x: r.midX - r.width * 0.25, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.midX + r.width * 0.25, y: r.maxY)); ctx.strokePath()
    ctx.setLineCap(.butt)
  }

  static let clock: Fn = { ctx, r, c in
    ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
    ctx.strokeEllipse(in: r.insetBy(dx: 3, dy: 3))
    ctx.move(to: CGPoint(x: r.midX, y: r.midY)); ctx.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.22)); ctx.strokePath()
    ctx.move(to: CGPoint(x: r.midX, y: r.midY)); ctx.addLine(to: CGPoint(x: r.midX + r.width * 0.22, y: r.midY + r.height * 0.1)); ctx.strokePath()
    ctx.setLineCap(.butt)
  }

  static let warning: Fn = { ctx, r, c in
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.midX, y: r.minY + 2)); p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 3)); p.addLine(to: CGPoint(x: r.minX + 1, y: r.maxY - 3)); p.closeSubpath()
    ctx.addPath(p); ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.setLineJoin(.round); ctx.strokePath()
    Draw.fill(ctx, CGRect(x: r.midX - 2.5, y: r.minY + r.height * 0.34, width: 5, height: r.height * 0.30), c, radius: 2)
    Draw.fill(ctx, CGRect(x: r.midX - 3, y: r.minY + r.height * 0.72, width: 6, height: 6), c, radius: 3)
  }

  static let pin: Fn = { ctx, r, c in
    let cx = r.midX, top = r.minY + 2, rad = r.width * 0.34
    ctx.setFillColor(c.cgColor)
    ctx.addEllipse(in: CGRect(x: cx - rad, y: top, width: rad * 2, height: rad * 2)); ctx.fillPath()
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx - rad * 0.9, y: top + rad * 1.5)); p.addLine(to: CGPoint(x: cx, y: r.maxY - 2)); p.addLine(to: CGPoint(x: cx + rad * 0.9, y: top + rad * 1.5)); p.closeSubpath()
    ctx.addPath(p); ctx.fillPath()
    ctx.setFillColor(PlatformColor(white: 0.06, alpha: 1).cgColor)
    ctx.addEllipse(in: CGRect(x: cx - rad * 0.4, y: top + rad * 0.6, width: rad * 0.8, height: rad * 0.8)); ctx.fillPath()
  }

  static let check: Fn = { ctx, r, c in
    ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(6); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY)); ctx.addLine(to: CGPoint(x: r.minX + r.width * 0.4, y: r.maxY - r.height * 0.2)); ctx.addLine(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.minY + r.height * 0.2)); ctx.strokePath()
    ctx.setLineCap(.butt)
  }

  /// Dust: three wavy wind lines.
  static let dust: Fn = { ctx, r, c in
    ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
    for i in 0..<3 {
      let y = r.minY + r.height * (0.2 + 0.3 * CGFloat(i))
      ctx.move(to: CGPoint(x: r.minX, y: y))
      ctx.addCurve(to: CGPoint(x: r.maxX, y: y), control1: CGPoint(x: r.minX + r.width * 0.3, y: y - r.height * 0.18), control2: CGPoint(x: r.minX + r.width * 0.6, y: y + r.height * 0.18))
      ctx.strokePath()
    }
    ctx.setLineCap(.butt)
  }

  /// A cargo box with a strap and a label: "something is on its way".
  static let box: Fn = { ctx, r, c in
    let body = CGRect(x: r.minX + 2, y: r.minY + r.height * 0.26, width: r.width - 4, height: r.height * 0.70)
    ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(5); ctx.setLineJoin(.round)
    ctx.stroke(body)
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: body.minX - 4, y: body.minY)); lid.addLine(to: CGPoint(x: body.minX + 6, y: r.minY + 2)); lid.addLine(to: CGPoint(x: body.maxX - 6, y: r.minY + 2)); lid.addLine(to: CGPoint(x: body.maxX + 4, y: body.minY)); lid.closeSubpath()
    ctx.addPath(lid); ctx.strokePath()
    ctx.move(to: CGPoint(x: body.midX, y: body.minY)); ctx.addLine(to: CGPoint(x: body.midX, y: body.maxY)); ctx.strokePath()
    Draw.fill(ctx, CGRect(x: body.minX + 10, y: body.maxY - 18, width: body.width * 0.28, height: 8), c, radius: 3)
  }

  static let drill: Fn = { ctx, r, c in
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.midX - r.width * 0.22, y: r.minY)); p.addLine(to: CGPoint(x: r.midX + r.width * 0.22, y: r.minY))
    p.addLine(to: CGPoint(x: r.midX + r.width * 0.22, y: r.minY + r.height * 0.45)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX - r.width * 0.22, y: r.minY + r.height * 0.45)); p.closeSubpath()
    ctx.addPath(p); ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(4); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.move(to: CGPoint(x: r.midX - r.width * 0.22, y: r.minY + r.height * 0.22)); ctx.addLine(to: CGPoint(x: r.midX + r.width * 0.22, y: r.minY + r.height * 0.32)); ctx.strokePath()
  }
}
