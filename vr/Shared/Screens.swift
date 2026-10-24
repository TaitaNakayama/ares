import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The three wall screens. Text is sized for Cardboard: body cap height >= ~1.5 degrees.
final class WallScreens {
  let power = TextPanel(width: 2.1, height: 1.2, pixelsPerMeter: 640)
  let money = TextPanel(width: 2.1, height: 1.2, pixelsPerMeter: 640)
  let waiting = TextPanel(width: 1.5, height: 0.62, pixelsPerMeter: 900)
  private var tauHistory: [Double] = []
  private var lastTauSample: TimeInterval = -10

  init(root: SCNNode) {
    for (panel, deg) in [(power, Float(-63)), (money, Float(63))] {
      let n = panel.node
      // Flat panels on a curved wall: mount inside the curve so the edges don't sink into it.
      n.position = Room.ring(deg, r: Room.radius - 0.28, y: 1.78)
      n.look(at: SCNVector3(0, 1.78, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      root.addChildNode(n)
      let bezel = SCNNode(geometry: SCNBox(width: 2.22, height: 1.32, length: 0.04, chamferRadius: 0.03))
      bezel.geometry?.firstMaterial?.diffuse.contents = PlatformColor(white: 0.16, alpha: 1)
      bezel.position = SCNVector3(0, 0, -0.025)
      n.addChildNode(bezel)
    }
    // "Waiting for you" sits on the console under the window, tilted up toward the user.
    let w = waiting.node
    w.position = Room.ring(0, r: 2.62, y: 1.0)
    w.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    root.addChildNode(w)
  }

  func update(_ s: VRState?, now: TimeInterval, linkText: String) {
    if let tau = s?.tau, now - lastTauSample > 1 {
      lastTauSample = now
      tauHistory.append(tau)
      if tauHistory.count > 90 { tauHistory.removeFirst() }
    }
    drawPower(s)
    drawMoney(s, linkText: linkText)
    drawWaiting(s)
  }

  private func drawPower(_ s: VRState?) {
    let p = s?.power
    let soc = p?.socPct ?? 0
    let tau = s?.tau ?? 0
    let left = p?.solsLeft
    let key = "\(Int(soc))|\(Int((p?.solarKWhPerSol ?? 0) / 5))|\(Int(left.map { $0 * 10 } ?? -1))|\(Int(tau * 10))|\(p?.drillOn ?? true)|\(tauHistory.count / 3)"
    let hist = tauHistory
    power.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("POWER", at: CGPoint(x: 48, y: 30), size: 58, weight: .heavy, color: Palette.orange)
      let low = (left ?? 99) < 6
      _ = Draw.text("\(Int(soc.rounded()))%", at: CGPoint(x: 48, y: 104), size: 170, weight: .heavy, color: low ? Palette.red : Palette.text)
      Draw.bar(ctx, CGRect(x: 52, y: 320, width: 560, height: 36), fraction: CGFloat(soc / 100), color: low ? Palette.red : Palette.green)
      let reserve = left.map { String(format: "%.1f sols left", $0) } ?? "Charging"
      _ = Draw.text(reserve, at: CGPoint(x: 48, y: 380), size: 74, weight: .bold, color: low ? Palette.amber : Palette.text)
      _ = Draw.text("Solar \(Int(p?.solarKWhPerSol ?? 0)) · Use \(Int(p?.loadKWhPerSol ?? 0)) kWh/sol", at: CGPoint(x: 48, y: 480), size: 54, weight: .semibold, color: Palette.dim)
      _ = Draw.text("Ice drill \((p?.drillOn ?? true) ? "ON" : "OFF")", at: CGPoint(x: 48, y: 560), size: 54, weight: .bold, color: (p?.drillOn ?? true) ? Palette.text : Palette.amber)
      // Dust opacity sparkline.
      let gx: CGFloat = 690, gy: CGFloat = 130, gw: CGFloat = 600, gh: CGFloat = 300
      Draw.fill(ctx, CGRect(x: gx, y: gy, width: gw, height: gh), Palette.panel, radius: 12)
      _ = Draw.text(String(format: "Dust τ %.1f", tau), at: CGPoint(x: gx + 24, y: gy + 16), size: 58, weight: .bold, color: tau > 2 ? Palette.amber : Palette.text)
      if hist.count > 1 {
        ctx.setStrokeColor(Palette.amber.cgColor)
        ctx.setLineWidth(6)
        for (i, v) in hist.enumerated() {
          let x = gx + 20 + CGFloat(i) / CGFloat(max(1, hist.count - 1)) * (gw - 40)
          let y = gy + gh - 20 - CGFloat(min(v, 6) / 6) * (gh - 110)
          if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.strokePath()
      }
      _ = Draw.text("Solar model: Opportunity rover, 2018 dust storm (JPL)", at: CGPoint(x: 48, y: size.height - 62), size: 30, weight: .medium, color: Palette.dim)
    }
  }

  private func drawMoney(_ s: VRState?, linkText: String) {
    let m = s?.money
    let pays = (m?.payments ?? []).prefix(3)
    let key = "\(m?.cashText ?? "")|\(m?.runwayDays ?? 0)|\(m?.savedText ?? "")|\(pays.map { $0.id }.joined())|\(linkText)"
    money.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("MONEY", at: CGPoint(x: 48, y: 30), size: 58, weight: .heavy, color: Palette.gold)
      _ = Draw.text(linkText, at: CGPoint(x: size.width - 520, y: 42), size: 32, weight: .semibold, color: linkText.hasPrefix("Live") ? Palette.green : Palette.red, width: 480, align: .right)
      _ = Draw.text(Self.short(m?.cashText ?? "—"), at: CGPoint(x: 48, y: 104), size: 130, weight: .heavy)
      _ = Draw.text("Runway \(m?.runwayDays ?? 0) days", at: CGPoint(x: 48, y: 270), size: 70, weight: .bold, color: (m?.runwayDays ?? 999) < 150 ? Palette.amber : Palette.text)
      _ = Draw.text("Saved \(Self.short(m?.savedText ?? "$0"))", at: CGPoint(x: 48, y: 366), size: 78, weight: .heavy, color: Palette.green)
      var y: CGFloat = 480
      for p in pays {
        _ = Draw.text("Paid \(Self.short(p.amountText ?? "")) · \(p.vendor ?? "")", at: CGPoint(x: 48, y: y), size: 46, weight: .semibold, color: Palette.dim, width: size.width - 96)
        y += 62
      }
      _ = Draw.text("Suppliers, prices and budget are SIMULATED", at: CGPoint(x: 48, y: size.height - 62), size: 30, weight: .medium, color: Palette.dim)
    }
  }

  private func drawWaiting(_ s: VRState?) {
    let w = s?.waiting?.first
    let earth = s?.earth?.first
    let key = "\(w?.id ?? "")|\(w?.decideByText ?? "")|\(earth?.replyInMin ?? -1)|\(s?.lightTimeMin.map { Int($0 * 10) } ?? 0)"
    let light = s?.lightTimeMin ?? 0
    waiting.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      _ = Draw.text("WAITING FOR YOU", at: CGPoint(x: 40, y: 26), size: 52, weight: .heavy, color: w != nil ? Palette.amber : Palette.dim)
      if let w {
        _ = Draw.text("Decision needed\(w.decideByText.map { " by \($0)" } ?? "")", at: CGPoint(x: 40, y: 112), size: 60, weight: .bold, width: size.width - 80)
        _ = Draw.text("Look at a choice above, then press the button.", at: CGPoint(x: 40, y: 200), size: 46, weight: .semibold, color: Palette.text, width: size.width - 80, maxLines: 2)
      } else {
        _ = Draw.text("Nothing needs you. The team is handling it.", at: CGPoint(x: 40, y: 112), size: 52, weight: .semibold, color: Palette.dim, width: size.width - 80, maxLines: 2)
      }
      let earthLine = earth.map { "Earth reply in ~\($0.replyInMin ?? 0) min" } ?? String(format: "Earth is %.1f light-minutes away", light)
      _ = Draw.text(earthLine, at: CGPoint(x: 40, y: size.height - 92), size: 46, weight: .bold, color: Palette.blue, width: size.width - 80)
    }
  }

  /// "$169,461,067.33" -> "$169.5M" so the big numbers stay legible.
  static func short(_ money: String) -> String {
    let digits = money.filter { $0.isNumber || $0 == "." }
    guard let v = Double(digits) else { return money }
    let neg = money.hasPrefix("-")
    let s: String
    if v >= 1e9 { s = String(format: "$%.2fB", v / 1e9) }
    else if v >= 1e6 { s = String(format: "$%.1fM", v / 1e6) }
    else if v >= 1e3 { s = String(format: "$%.0fk", v / 1e3) }
    else { s = String(format: "$%.0f", v) }
    return neg ? "-" + s : s
  }
}
