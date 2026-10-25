import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The three wall screens, drawn with the `Kit` design system (ScreenKit.swift). Text is sized for
/// Cardboard: nothing below 30 px, body text 38 px and up. Each screen redraws only when its key changes.
final class WallScreens {
  let power = TextPanel(width: 2.1, height: 1.2, pixelsPerMeter: 640)
  let money = TextPanel(width: 2.1, height: 1.2, pixelsPerMeter: 640)
  let waiting = TextPanel(width: 1.5, height: 0.62, pixelsPerMeter: 900)
  // Client-side history of values the state gives us (no invented data): one sample every 3 s.
  private var tauHistory: [Double] = []
  private var solarHistory: [Double] = []
  private var loadHistory: [Double] = []
  private var sampleSerial = 0
  private var lastSample: TimeInterval = -10
  /// The crisis: a red additive wash over the POWER screen that pulses while `world.power.level` is critical.
  private let powerGlow = SCNNode()
  private var powerLevel = "ok"

  /// Beat names, from the story definition in world-mars (storyBeat): the demo's 7 steps.
  static let beatNames = ["", "Delivery", "Dust storm", "Battery request", "Quote flagged", "Blocked, sent to Earth", "Commander decides", "Earth's verdict"]

  /// LOCATION screen on the rear wall, above the debug panel: Sol clock, dust, Earth delay, over the orbital map.
  let location = TextPanel(width: 1.5, height: 0.84, pixelsPerMeter: 660)

  /// A scuffed matte bezel behind a screen (`w` x `h` metres of screen), plus a faint cool glow decal on the wall.
  private static func frame(for n: SCNNode, w: CGFloat, h: CGFloat) {
    let bw = w + 0.16, bh = h + 0.16
    let bezel = SCNBox(width: bw, height: bh, length: 0.04, chamferRadius: 0.025)
    let front = Tex.material(Tex.bezel(size: CGSize(width: 512, height: (512 * bh / bw).rounded())))
    let side = Room.mat(PlatformColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1), rough: 0.8)
    bezel.materials = [front, side, side, side, side, side]
    let bn = SCNNode(geometry: bezel)
    bn.position = SCNVector3(0, 0, -0.025)
    n.addChildNode(bn)
    let wt = n.simdWorldTransform
    ScreenRects.all.append(.init(center: SIMD3(wt.columns.3.x, wt.columns.3.y, wt.columns.3.z), right: simd_normalize(SIMD3(wt.columns.0.x, wt.columns.0.y, wt.columns.0.z)), w: Float(bw), h: Float(bh)))
  }

  private static func wallGlow(deg: Float, y: Float, w: CGFloat, h: CGFloat) -> SCNNode {
    let g = SCNNode(geometry: SCNPlane(width: w + 1.2, height: h + 1.0))
    g.geometry?.materials = [Tex.glowMaterial(PlatformColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1), strength: 0.38)]
    g.position = Room.ring(deg, r: Room.radius - 0.04, y: y)
    g.look(at: SCNVector3(0, y, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    g.renderingOrder = 45
    return g
  }

  init(root: SCNNode) {
    ScreenRects.all = []
    for (panel, deg) in [(power, Float(-63)), (money, Float(63))] {
      let n = panel.node
      // Flat panels on a curved wall: mount inside the curve so the edges don't sink into it.
      n.position = Room.ring(deg, r: Room.radius - 0.28, y: 1.78)
      n.look(at: SCNVector3(0, 1.78, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
      root.addChildNode(n)
      Self.frame(for: n, w: 2.1, h: 1.2)
      root.addChildNode(Self.wallGlow(deg: deg, y: 1.78, w: 2.1, h: 1.2))
    }
    // Red wash over the POWER screen (hidden until the level drops).
    let pg = SCNPlane(width: 2.4, height: 1.5)
    let pgm = SCNMaterial()
    pgm.lightingModel = .constant
    pgm.diffuse.contents = Tex.glow(PlatformColor(red: 1.0, green: 0.12, blue: 0.08, alpha: 1))
    pgm.blendMode = .add
    pgm.writesToDepthBuffer = false
    pg.materials = [pgm]
    powerGlow.geometry = pg
    powerGlow.position = SCNVector3(0, 0, 0.012)
    powerGlow.renderingOrder = 60
    powerGlow.opacity = 0
    powerGlow.isHidden = true
    power.node.addChildNode(powerGlow)
    // "Waiting for you" sits on the console under the window, tilted up toward the user.
    let w = waiting.node
    w.position = Room.ring(0, r: 2.62, y: 1.0)
    w.look(at: SCNVector3(0, 1.6, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    root.addChildNode(w)
    Self.frame(for: w, w: 1.5, h: 0.62)
    // Rear wall.
    let l = location.node
    l.position = Room.ring(180, r: Room.radius - 0.2, y: 2.4)
    l.look(at: SCNVector3(0, 2.4, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    root.addChildNode(l)
    Self.frame(for: l, w: 1.5, h: 0.84)
    root.addChildNode(Self.wallGlow(deg: 180, y: 2.4, w: 1.5, h: 0.84))
  }

  /// `ok` | `low` | `critical` (from `world.power.level`): the POWER screen goes amber, or red and pulsing.
  private func setPowerLevel(_ level: String) {
    guard level != powerLevel else { return }
    powerLevel = level
    powerGlow.removeAllActions()
    switch level {
    case "critical":
      powerGlow.isHidden = false
      powerGlow.opacity = 0.2
      powerGlow.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.75, duration: 0.45), .fadeOpacity(to: 0.15, duration: 0.45)])))
    case "low":
      powerGlow.isHidden = false
      powerGlow.runAction(.fadeOpacity(to: 0.22, duration: 0.5))
    default:
      powerGlow.runAction(.sequence([.fadeOut(duration: 0.8), .hide()]))
    }
  }

  func update(_ s: VRState?, now: TimeInterval, linkText: String) {
    setPowerLevel(s?.world?.power?.level ?? "ok")
    if now - lastSample > 3 {
      lastSample = now
      sampleSerial += 1
      if let tau = s?.tau { tauHistory.append(tau); if tauHistory.count > 30 { tauHistory.removeFirst() } }
      if let p = s?.power, let sol = p.solarKWhPerSol, let ld = p.loadKWhPerSol {
        solarHistory.append(sol); loadHistory.append(ld)
        if solarHistory.count > 30 { solarHistory.removeFirst(); loadHistory.removeFirst() }
      }
    }
    drawPower(s)
    drawMoney(s, linkText: linkText)
    drawWaiting(s)
    drawLocation(s)
  }

  // MARK: POWER

  private func drawPower(_ s: VRState?) {
    let p = s?.power
    let wl = s?.world?.power?.level ?? "ok"
    let soc = s?.world?.power?.socPct ?? p?.socPct ?? 0
    let tau = s?.tau ?? 0
    let left = p?.solsLeft
    let drill = s?.world?.drill.map { $0 != "off" } ?? p?.drillOn ?? true
    let time = s?.time ?? ""
    let key = "\(Int(soc))|\(Int(left.map { $0 * 10 } ?? -1))|\(Int(tau * 10))|\(drill)|\(Int(p?.solarKWhPerSol ?? 0))|\(Int(p?.loadKWhPerSol ?? 0))|\(time)|\(sampleSerial)|\(wl)"
    let tauH = tauHistory, solarH = solarHistory, loadH = loadHistory
    let solar = p?.solarKWhPerSol ?? 0, load = p?.loadKWhPerSol ?? 0
    power.update(key: key) { ctx, size in
      let crit = wl == "critical", lowLevel = wl == "low"
      let accent = crit ? Palette.red : lowLevel ? Palette.amber : Palette.orange
      Kit.chrome(ctx, size, accent: accent)
      Kit.header(ctx, size, title: crit ? "POWER · CRITICAL" : lowLevel ? "POWER · LOW" : "POWER", color: accent, icon: crit ? Icon.warning : Icon.bolt, right: time.isEmpty ? nil : time, rightIcon: Icon.clock)
      let low = (left ?? 99) < 6 || crit || lowLevel
      let tone = crit ? Palette.red : low ? Palette.amber : Palette.green
      // Battery ring.
      let c1 = CGRect(x: 24, y: 104, width: 560, height: 392)
      Kit.card(ctx, c1)
      let center = CGPoint(x: c1.midX, y: c1.minY + 186)
      Kit.ring(ctx, center: center, radius: 140, thickness: 28, fraction: CGFloat(soc / 100), color: tone)
      Icon.battery(ctx, CGRect(x: center.x - 28, y: center.y - 104, width: 56, height: 38), Palette.dim)
      _ = Draw.text("\(Int(soc.rounded()))%", at: CGPoint(x: c1.minX, y: center.y - 62), size: 84, weight: .heavy, color: crit ? Palette.red : low ? Palette.amber : Palette.text, width: c1.width, align: .center)
      let reserve = crit ? "Critical" : lowLevel ? "Low" : (left.map { String(format: "%.1f sols left", $0) } ?? "Charging")
      _ = Draw.text(reserve, at: CGPoint(x: c1.minX, y: c1.maxY - 78), size: Kit.Size.label, weight: .heavy, color: crit ? Palette.red : low ? Palette.amber : Palette.text, width: c1.width, align: .center)
      // Solar vs use.
      let c2 = CGRect(x: 604, y: 104, width: 716, height: 392)
      Kit.card(ctx, c2)
      _ = Draw.text("kWh per sol", at: CGPoint(x: c2.minX + 24, y: c2.minY + 10), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text("Solar \(Int(solar))", at: CGPoint(x: c2.minX + 24, y: c2.minY + 78), size: Kit.Size.value, weight: .heavy, color: Palette.green, width: 340)
      Kit.textRight("Use \(Int(load))", right: c2.maxX - 24, y: c2.minY + 78, size: Kit.Size.value, weight: .heavy, color: Palette.amber, width: 330)
      let lo = (min(solarH.min() ?? solar, loadH.min() ?? load, solar, load)) * 0.85
      let hi = max(solarH.max() ?? solar, loadH.max() ?? load, solar, load, 1) * 1.05
      let g = CGRect(x: c2.minX + 28, y: c2.minY + 172, width: c2.width - 56, height: c2.height - 204)
      ctx.setStrokeColor(PlatformColor(white: 1, alpha: 0.10).cgColor); ctx.setLineWidth(1)
      for i in 0...3 { let y = g.minY + g.height * CGFloat(i) / 3; ctx.move(to: CGPoint(x: g.minX, y: y)); ctx.addLine(to: CGPoint(x: g.maxX, y: y)) }
      ctx.strokePath()
      if solarH.count > 1 {
        Kit.spark(ctx, g, solarH, lo: lo, hi: hi, color: Palette.green)
        Kit.spark(ctx, g, loadH, lo: lo, hi: hi, color: Palette.amber, fill: false)
      } else {
        _ = Draw.text("Collecting readings", at: CGPoint(x: g.minX, y: g.midY - 30), size: Kit.Size.label, color: Palette.dim, width: g.width, align: .center)
      }
      // Bottom row: ice drill chip + dust.
      let c3 = CGRect(x: 24, y: 512, width: 560, height: 176)
      Kit.card(ctx, c3)
      Icon.drill(ctx, CGRect(x: c3.minX + 28, y: c3.minY + 20, width: 40, height: 52), Palette.dim)
      _ = Draw.text("Ice drill", at: CGPoint(x: c3.minX + 88, y: c3.minY + 10), size: Kit.Size.label, color: Palette.dim)
      Kit.chip(ctx, at: CGPoint(x: c3.minX + 28, y: c3.minY + 84), text: drill ? "ON" : "OFF", color: drill ? Palette.green : Palette.amber)
      let c4 = CGRect(x: 604, y: 512, width: 716, height: 176)
      Kit.card(ctx, c4)
      let dustTone = tau > 2 ? Palette.amber : Palette.text
      Icon.dust(ctx, CGRect(x: c4.minX + 26, y: c4.minY + 20, width: 56, height: 44), tau > 2 ? Palette.amber : Palette.dim)
      _ = Draw.text("Dust", at: CGPoint(x: c4.minX + 98, y: c4.minY + 10), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text(String(format: "τ %.1f", tau), at: CGPoint(x: c4.minX + 26, y: c4.minY + 84), size: Kit.Size.value, weight: .heavy, color: dustTone)
      if tauH.count > 1 {
        Kit.spark(ctx, CGRect(x: c4.minX + 250, y: c4.minY + 40, width: c4.width - 284, height: c4.height - 80), tauH, lo: 0, hi: max(4, (tauH.max() ?? 0) * 1.1), color: Palette.amber)
      }
      Kit.footer("Solar model: Opportunity rover, 2018 storm (JPL)", size: size)
    }
  }

  // MARK: MONEY

  private func drawMoney(_ s: VRState?, linkText: String) {
    let m = s?.money
    let pays = Array((m?.payments ?? []).prefix(2))
    let time = s?.time ?? ""
    let big = m?.savedBig
    let incoming = m?.incoming
    let key = "\(m?.cashText ?? "")|\(m?.runwayDays ?? 0)|\(m?.savedText ?? "")|\(m?.committedText ?? "")|\(pays.map { $0.id }.joined())|\(linkText)|\(time)|\(big ?? "")|\(incoming?.label ?? "")|\(incoming?.eta ?? "")"
    money.update(key: key) { ctx, size in
      // Later: ONE big number, what Earth's answer saved.
      if let big, !big.isEmpty {
        Kit.chrome(ctx, size, accent: Palette.green)
        Kit.header(ctx, size, title: "MONEY", color: Palette.gold, icon: Icon.coins, right: linkText, rightColor: linkText.hasPrefix("Live") ? Palette.green : Palette.red)
        var fs: CGFloat = 330
        var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
        while (big as NSString).size(withAttributes: [.font: font]).width > size.width - 80, fs > 100 { fs -= 10; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
        _ = Draw.text(big, at: CGPoint(x: 0, y: 150), size: fs, weight: .heavy, color: Palette.green, width: size.width, align: .center)
        _ = Draw.text("SAVED", at: CGPoint(x: 0, y: 150 + font.lineHeight * 0.95), size: 86, weight: .heavy, color: Palette.text, width: size.width, align: .center)
        _ = Draw.text("The new account was a scam. Payment blocked.", at: CGPoint(x: 0, y: size.height - 150), size: 44, weight: .semibold, color: Palette.dim, width: size.width, align: .center)
        Kit.footer("Suppliers, prices and budget are SIMULATED", size: size)
        return
      }
      Kit.chrome(ctx, size, accent: Palette.gold)
      Kit.header(ctx, size, title: "MONEY", color: Palette.gold, icon: Icon.coins, right: linkText, rightColor: linkText.hasPrefix("Live") ? Palette.green : Palette.red)
      let runway = m?.runwayDays ?? 0
      let c1 = CGRect(x: 24, y: 104, width: 760, height: 210)
      Kit.card(ctx, c1)
      _ = Draw.text("Cash", at: CGPoint(x: c1.minX + 28, y: c1.minY + 8), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text(Self.short(m?.cashText ?? "—"), at: CGPoint(x: c1.minX + 28, y: c1.minY + 68), size: Kit.Size.hero, weight: .heavy, width: c1.width - 56)
      let c2 = CGRect(x: 804, y: 104, width: 516, height: 210)
      Kit.card(ctx, c2)
      let rcol = runway < 150 ? Palette.amber : Palette.text
      _ = Draw.text("Runway", at: CGPoint(x: c2.minX + 28, y: c2.minY + 8), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text("\(runway)", at: CGPoint(x: c2.minX + 28, y: c2.minY + 68), size: Kit.Size.hero, weight: .heavy, color: rcol, width: 300)
      let rw = ("\(runway)" as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: Kit.Size.hero, weight: .heavy)]).width
      _ = Draw.text("days", at: CGPoint(x: c2.minX + 28 + rw + 14, y: c2.minY + 104), size: Kit.Size.value, weight: .heavy, color: Palette.dim, width: 190)
      Draw.bar(ctx, CGRect(x: c2.minX + 28, y: c2.maxY - 24, width: c2.width - 56, height: 12), fraction: CGFloat(min(runway, 365)) / 365, color: runway < 150 ? Palette.amber : Palette.gold)
      // Saved + committed.
      let c3 = CGRect(x: 24, y: 334, width: 636, height: 150)
      Kit.card(ctx, c3, accent: Palette.green)
      _ = Draw.text("Saved so far", at: CGPoint(x: c3.minX + 28, y: c3.minY + 6), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text(Self.short(m?.savedText ?? "$0"), at: CGPoint(x: c3.minX + 28, y: c3.minY + 64), size: 72, weight: .heavy, color: Palette.green, width: c3.width - 56)
      let c4 = CGRect(x: 684, y: 334, width: 636, height: 150)
      Kit.card(ctx, c4)
      _ = Draw.text("Committed", at: CGPoint(x: c4.minX + 28, y: c4.minY + 6), size: Kit.Size.label, color: Palette.dim)
      _ = Draw.text(m?.committedText.map { Self.short($0) } ?? "—", at: CGPoint(x: c4.minX + 28, y: c4.minY + 64), size: 72, weight: .heavy, color: Palette.text, width: c4.width - 56)
      // Cargo on its way (the batteries were bought).
      if let incoming, let label = incoming.label, !label.isEmpty {
        let c6 = CGRect(x: 24, y: 504, width: 1296, height: 196)
        Kit.card(ctx, c6, accent: Palette.orange)
        Icon.box(ctx, CGRect(x: c6.minX + 36, y: c6.minY + 34, width: 130, height: 128), Palette.orange)
        _ = Draw.text("Incoming cargo", at: CGPoint(x: c6.minX + 200, y: c6.minY + 14), size: Kit.Size.label, color: Palette.dim, width: 700)
        _ = Draw.text(label + (incoming.eta.map { " · " + $0 } ?? ""), at: CGPoint(x: c6.minX + 200, y: c6.minY + 78), size: 78, weight: .heavy, color: Palette.text, width: c6.width - 230)
        Kit.footer("Suppliers, prices and budget are SIMULATED", size: size)
        return
      }
      // Last payments.
      let c5 = CGRect(x: 24, y: 504, width: 1296, height: 196)
      Kit.card(ctx, c5)
      _ = Draw.text("Recent payments", at: CGPoint(x: c5.minX + 28, y: c5.minY + 4), size: Kit.Size.label, color: Palette.dim)
      if pays.isEmpty {
        _ = Draw.text("None yet", at: CGPoint(x: c5.minX + 28, y: c5.minY + 84), size: Kit.Size.label, weight: .semibold, color: Palette.dim)
      }
      var y = c5.minY + 72
      for p in pays {
        Draw.fill(ctx, CGRect(x: c5.minX + 28, y: y + 20, width: 16, height: 16), Palette.gold, radius: 8)
        _ = Draw.text(p.vendor ?? "", at: CGPoint(x: c5.minX + 64, y: y), size: Kit.Size.label, weight: .semibold, width: 800)
        Kit.textRight(Self.short(p.amountText ?? ""), right: c5.maxX - 28, y: y, size: Kit.Size.label, weight: .heavy, color: Palette.gold, width: 340)
        y += 60
      }
      Kit.footer("Suppliers, prices and budget are SIMULATED", size: size)
    }
  }

  // MARK: WAITING / EARTH / MISSION

  private func drawWaiting(_ s: VRState?) {
    let w = s?.waiting?.first
    let earth = s?.earth?.first
    let light = s?.lightTimeMin ?? 0
    let time = s?.time ?? ""
    let beat = s?.storyBeat ?? 0
    let beats = s?.storyBeats ?? 7
    let mode = s?.agentMode
    let key = "\(w?.id ?? "")|\(w?.decideByText ?? "")|\(earth?.id ?? "")|\(earth?.replyInMin ?? -1)|\(earth?.replyEtaText ?? "")|\(Int(light * 10))|\(time)|\(beat)|\(mode ?? "")"
    waiting.update(key: key) { ctx, size in
      let tone = w != nil ? Palette.amber : Palette.green
      Kit.chrome(ctx, size, accent: tone)
      Kit.header(ctx, size, title: w != nil ? "WAITING FOR YOU" : "ALL CLEAR", color: tone, icon: w != nil ? Icon.warning : Icon.check, right: time.isEmpty ? nil : time, rightIcon: Icon.clock)
      if let w {
        _ = Draw.text("Decision needed\(w.decideByText.map { " by \($0)" } ?? "")", at: CGPoint(x: 32, y: 100), size: Kit.Size.value, weight: .heavy, width: size.width - 64)
        _ = Draw.text("Look at a choice above, then press the button.", at: CGPoint(x: 32, y: 168), size: 50, color: Palette.text, width: size.width - 64)
      } else {
        _ = Draw.text("Nothing needs you. The team is handling it.", at: CGPoint(x: 32, y: 108), size: 52, weight: .semibold, color: Palette.dim, width: size.width - 64)
      }
      // Earth link.
      let c1 = CGRect(x: 24, y: 232, width: size.width - 48, height: 156)
      Kit.card(ctx, c1, accent: Kit.screenBlue)
      Icon.antenna(ctx, CGRect(x: c1.minX + 24, y: c1.minY + 24, width: 58, height: 62), Kit.screenBlue)
      _ = Draw.text(String(format: "Earth is %.1f light-min away", light), at: CGPoint(x: c1.minX + 104, y: c1.minY + 18), size: 52, weight: .heavy, color: Kit.screenBlue, width: c1.width - 128)
      let ver = earth.map { e -> String in
        let who = e.vendor.map { " · \($0)" } ?? ""
        let eta = e.replyInMin.map { "reply in ~\($0) min" } ?? e.replyEtaText.map { "reply \($0)" } ?? "waiting"
        return "Verification pending\(who): \(eta)"
      } ?? "No verifications pending"
      _ = Draw.text(ver, at: CGPoint(x: c1.minX + 104, y: c1.minY + 82), size: 46, weight: .semibold, color: earth != nil ? Palette.text : Palette.dim, width: c1.width - 128)
      // Mission strip: beat N of 7 + name, progress dots, agent mode.
      let y0 = size.height - 164
      if beat > 0 {
        _ = Draw.text("Beat \(beat) of \(beats) · \(Self.beatNames[min(beat, 7)])", at: CGPoint(x: 32, y: y0), size: 48, weight: .heavy, color: Palette.text, width: size.width - 400)
      } else {
        _ = Draw.text("Mission starting", at: CGPoint(x: 32, y: y0), size: 48, weight: .heavy, color: Palette.dim, width: 600)
      }
      if let mode { Kit.textRight("Agents: \(mode)", right: size.width - 32, y: y0, size: 46, color: Palette.cyan, width: 360) }
      for i in 1...max(1, beats) {
        let x = 32 + CGFloat(i - 1) * ((size.width - 64) / CGFloat(beats))
        let w = (size.width - 64) / CGFloat(beats) - 12
        Draw.fill(ctx, CGRect(x: x, y: y0 + 56, width: w, height: 14), i <= beat ? (i == beat ? Palette.amber : Palette.green) : PlatformColor(white: 1, alpha: 0.14), radius: 7)
      }
    }
  }

  // MARK: LOCATION

  private func drawLocation(_ s: VRState?) {
    let time = s?.time ?? "Sol —"
    let tau = s?.tau ?? 0
    let light = s?.lightTimeMin ?? 0
    let sunEl = s?.sun?.elevation
    let key = "\(time)|\(Int(tau * 10))|\(Int(light * 10))|\(Int(sunEl ?? -99))"
    location.update(key: key) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), Palette.bg)
      // Orbital map (NASA/JPL-Caltech/USGS/University of Arizona, PIA23976): aspect-fill, desaturated, darkened.
      if let img = Tex.cg("jezero_orbital_map_pia23976_1k") {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let k = max(size.width / iw, size.height / ih)
        let r = CGRect(x: (size.width - iw * k) / 2, y: (size.height - ih * k) / 2, width: iw * k, height: ih * k)
        Tex.draw(ctx, img, in: r)
      }
      ctx.setBlendMode(.saturation)
      ctx.setFillColor(PlatformColor(white: 0.5, alpha: 0.8).cgColor)
      ctx.fill(CGRect(origin: .zero, size: size))
      ctx.setBlendMode(.normal)
      let space = CGColorSpaceCreateDeviceRGB()
      let cols = [PlatformColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 0.86).cgColor, PlatformColor(red: 0.04, green: 0.045, blue: 0.055, alpha: 0.12).cgColor]
      if let g = CGGradient(colorsSpace: space, colors: cols as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
      }
      Kit.inset(ctx, CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5), radius: 18, color: Palette.cyan.withAlphaComponent(0.55), width: 3)
      Icon.pin(ctx, CGRect(x: 28, y: 24, width: 44, height: 56), Palette.cyan)
      _ = Draw.text("LOCATION", at: CGPoint(x: 90, y: 22), size: 58, weight: .heavy, color: Palette.cyan)
      _ = Draw.text("Jezero Crater", at: CGPoint(x: 32, y: 108), size: 46, weight: .semibold, color: Palette.dim, width: 600)
      _ = Draw.text(time, at: CGPoint(x: 32, y: 152), size: 80, weight: .heavy, width: size.width - 64)
      var y: CGFloat = 270
      func row(_ label: String, _ value: String, _ color: PlatformColor) {
        _ = Draw.text(label, at: CGPoint(x: 32, y: y), size: 46, weight: .semibold, color: Palette.dim, width: 190)
        _ = Draw.text(value, at: CGPoint(x: 230, y: y), size: 46, weight: .heavy, color: color, width: size.width - 262)
        y += 64
      }
      row("Dust", String(format: "τ %.1f", tau), tau > 2 ? Palette.amber : Palette.text)
      row("Earth", String(format: "%.1f light-min away", light), Kit.screenBlue)
      if let e = sunEl { row("Sun", e >= 0 ? String(format: "%.0f° above horizon", e) : String(format: "%.0f° below horizon", -e), Palette.gold) }
      ctx.setFillColor(PlatformColor(white: 0, alpha: 0.62).cgColor)
      ctx.fill(CGRect(x: 6, y: size.height - 66, width: size.width - 12, height: 56))
      Kit.footer("NASA/JPL-Caltech/USGS/U. Arizona, PIA23976", size: size, y: size.height - 58, max: 38)
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
