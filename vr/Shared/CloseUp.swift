import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The science close-up: the real Perseverance WATSON image with its caption, floating in front of the judge.
/// Shared by the headset and the Mac spectator (the spectator opens it when the headset says it is open).
final class CloseUpPanel {
  static let fallbackImage = "perseverance-sol1526-watson-kenmore"
  static let fallbackCaption = "Perseverance, SHERLOC WATSON camera: abrasion patch \"Kenmore\", sol 1526 (2025-06-05). Credit NASA/JPL-Caltech/MSSS, PIA26576."
  static let width: CGFloat = 1.5, height: CGFloat = 1.72

  let node: SCNNode
  private let panel = TextPanel(width: CloseUpPanel.width, height: CloseUpPanel.height, pixelsPerMeter: 700, emissive: true)
  private(set) var isOpen = false
  private(set) var openedAt: TimeInterval = 0
  private var awayFor: TimeInterval = 0
  private var lastTick: TimeInterval = 0
  private var key = ""

  init() {
    node = panel.node
    node.name = "closeup"
    node.opacity = 0
    node.isHidden = true
    node.renderingOrder = 200
    for m in node.geometry?.materials ?? [] { m.readsFromDepthBuffer = false }
  }

  /// Draws the panel for this science reference (nil = the bundled defaults).
  func configure(_ sci: VRState.Science?) {
    let imageName = ((sci?.image).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackImage + ".jpg").replacingOccurrences(of: ".jpg", with: "")
    let caption = (sci?.caption).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackCaption
    let target = sci?.target ?? "Kenmore"
    let sol = sci?.sol.map { "sol \(Int($0))" } ?? "sol 1526"
    let credit = sci?.credit ?? "NASA/JPL-Caltech/MSSS"
    let k = "\(imageName)|\(caption)|\(target)|\(sol)|\(credit)"
    guard k != key else { return }
    key = k
    let img = Tex.cg(imageName)
    panel.update(key: k) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1))
      ctx.setStrokeColor(Scientist.tagColor.cgColor)
      ctx.setLineWidth(8)
      ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
      _ = Draw.text("REAL MARS · \(target) · \(sol)", at: CGPoint(x: 36, y: 22), size: 50, weight: .heavy, color: Palette.amber, width: size.width - 72)
      let iw = size.width - 72
      let ih = iw * 1175 / 1577
      if let img { Tex.draw(ctx, img, in: CGRect(x: 36, y: 96, width: iw, height: ih)) }
      var y = 96 + ih + 28
      y += Draw.text(caption, at: CGPoint(x: 36, y: y), size: 44, weight: .semibold, color: Palette.text, width: size.width - 72, maxLines: 4) + 14
      _ = Draw.text("Press the button or look away to close", at: CGPoint(x: 36, y: size.height - 70), size: 40, weight: .bold, color: Palette.dim, width: size.width - 72)
      _ = credit
    }
  }

  /// Opens it 1.75 m ahead of `eye` along the horizontal part of `forward`.
  func open(eye: SIMD3<Float>, forward: SIMD3<Float>, now: TimeInterval) {
    guard !isOpen else { return }
    isOpen = true
    openedAt = now
    awayFor = 0
    lastTick = now
    var f = SIMD3(forward.x, 0, forward.z)
    f = simd_length(f) > 0.05 ? simd_normalize(f) : SIMD3(0, 0, -1)
    node.simdPosition = eye + f * 1.75 + SIMD3(0, -0.06, 0)
    node.look(at: SCNVector3(eye.x, eye.y - 0.06, eye.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    node.isHidden = false
    node.removeAllActions()
    node.runAction(.fadeIn(duration: 0.25))
  }

  func close() {
    guard isOpen else { return }
    isOpen = false
    node.removeAllActions()
    node.runAction(.sequence([.fadeOut(duration: 0.25), .hide()]))
  }

  /// Looking away for 3 s closes it. Returns true when it just closed.
  @discardableResult
  func tick(now: TimeInterval, eye: SIMD3<Float>, forward: SIMD3<Float>) -> Bool {
    guard isOpen else { return false }
    let dt = min(0.2, max(0, now - lastTick))
    lastTick = now
    let to = simd_normalize(node.simdPosition - eye)
    let looking = simd_dot(simd_normalize(forward), to) > cos(32 * Float.pi / 180)
    awayFor = looking ? 0 : awayFor + dt
    if awayFor > 3 { close(); return true }
    return false
  }
}
