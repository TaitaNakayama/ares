import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The science close-up, floating in front of the judge. Page 0: the rover's own stereo pair (Mastcam-Z, sol 1529), the left
/// eye's frame to the left eye and the right eye's to the right (two coincident quads with eye-specific category bits).
/// Page 1: the real WATSON image (flat). The button turns the page, then closes.
/// Shared by the headset and the Mac spectator (the spectator opens it when the headset says it is open and shows the left frame, mono).
final class CloseUpPanel {
  /// Category bits of the two stereo quads. Eye cameras mask out the other eye's quad (`configureEyeCameras`).
  static let leftBit = 1 << 4, rightBit = 1 << 5
  /// The left camera sees everything but the right quad and vice versa; mono cameras (video) get the left frame only.
  static func configureEyeCameras(left: SCNNode, right: SCNNode, mono: [SCNNode] = []) {
    left.camera?.categoryBitMask = ~rightBit
    right.camera?.categoryBitMask = ~leftBit
    for m in mono { m.camera?.categoryBitMask = ~rightBit }
  }

  static let fallbackImage = "perseverance-sol1526-watson-kenmore"
  static let fallbackCaption = "Perseverance, SHERLOC WATSON camera: abrasion patch \"Kenmore\", sol 1526 (2025-06-05). Credit NASA/JPL-Caltech/MSSS, PIA26576."
  static let stereoCaption = "Perseverance Mastcam-Z, sol 1529, left and right eyes: real stereo. Credit NASA/JPL-Caltech/ASU. Depth exaggerated: 24 cm camera spacing."
  static let stereoCaptionMono = "Perseverance Mastcam-Z, sol 1529, left eye shown: stereo in the headset. Credit NASA/JPL-Caltech/ASU. Depth exaggerated: 24 cm camera spacing."
  /// Stereo pair after prep (CREDITS.md): 24 px black strip cropped, right frame shifted up 34 px, 20 px horizontal convergence shift.
  static let stereoAspect: CGFloat = 1604.0 / 1166.0
  /// Captures (`--closeup`): the panel stays open while the camera looks elsewhere.
  static let keepOpen = ProcessInfo.processInfo.arguments.contains("--closeup")
  static let width: CGFloat = 1.5, height: CGFloat = 1.72

  let node: SCNNode
  private let panel = TextPanel(width: CloseUpPanel.width, height: CloseUpPanel.height, pixelsPerMeter: 700, emissive: true)
  private(set) var isOpen = false
  private(set) var openedAt: TimeInterval = 0
  private var awayFor: TimeInterval = 0
  private var lastTick: TimeInterval = 0
  private var key = ""
  /// 0 = stereo pair, 1 = WATSON.
  private(set) var page = 0
  private var lastSci: VRState.Science?
  private let stereoNode = SCNNode()
  private var anchorEye = SIMD3<Float>(0, 1.6, 0), anchorDir = SIMD3<Float>(0, 0, -1)

  init() {
    node = panel.node
    node.name = "closeup"
    node.opacity = 0
    node.isHidden = true
    node.renderingOrder = 200
    for m in node.geometry?.materials ?? [] { m.readsFromDepthBuffer = false }
    // The stereo quads sit on the panel's image area (px 36,96 and the panel width minus 72), a hair in front of it.
    let iw = (Self.width * 700 - 72) / 700, ih = iw / Self.stereoAspect
    let cy = (Self.height * 700 / 2 - (96 + ih * 700 / 2)) / 700
    for (name, bit) in [("L", Self.leftBit), ("R", Self.rightBit)] {
      let m = SCNMaterial()
      m.lightingModel = .constant
      m.diffuse.contents = Tex.cg("pers-stereo-\(name)")
      m.diffuse.mipFilter = .linear
      m.readsFromDepthBuffer = false
      let q = SCNNode(geometry: SCNPlane(width: iw, height: ih))
      q.geometry?.materials = [m]
      q.name = "stereo" + name
      q.position = SCNVector3(0, cy, 0.003)
      q.renderingOrder = 201
      q.categoryBitMask = bit
      #if os(macOS)
      q.isHidden = name == "R" // the spectator is mono: the left eye's frame
      #endif
      stereoNode.addChildNode(q)
    }
    node.addChildNode(stereoNode)
  }

  /// Draws the panel for this science reference (nil = the bundled defaults).
  func configure(_ sci: VRState.Science?) {
    lastSci = sci
    stereoNode.isHidden = page != 0
    let imageName = ((sci?.image).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackImage + ".jpg").replacingOccurrences(of: ".jpg", with: "")
    let caption = (sci?.caption).flatMap { $0.isEmpty ? nil : $0 } ?? Self.fallbackCaption
    let target = sci?.target ?? "Kenmore"
    let sol = sci?.sol.map { "sol \(Int($0))" } ?? "sol 1526"
    let credit = sci?.credit ?? "NASA/JPL-Caltech/MSSS"
    let k = "p\(page)|\(imageName)|\(caption)|\(target)|\(sol)|\(credit)"
    guard k != key else { return }
    key = k
    let stereo = page == 0
    let img = stereo ? nil : Tex.cg(imageName)
    #if os(macOS)
    let stereoText = Self.stereoCaptionMono
    #else
    let stereoText = Self.stereoCaption
    #endif
    panel.update(key: k) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1))
      ctx.setStrokeColor(Scientist.tagColor.cgColor)
      ctx.setLineWidth(8)
      ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
      if stereo {
        _ = Draw.text("REAL MARS · STEREO · sol 1529", at: CGPoint(x: 36, y: 22), size: 50, weight: .heavy, color: Palette.amber, width: size.width - 72)
        let ih = (size.width - 72) / Self.stereoAspect
        _ = Draw.text(stereoText, at: CGPoint(x: 36, y: 96 + ih + 28), size: 42, weight: .semibold, color: Palette.text, width: size.width - 72, maxLines: 5)
        _ = Draw.text("Press the button for the WATSON close-up", at: CGPoint(x: 36, y: size.height - 70), size: 40, weight: .bold, color: Palette.dim, width: size.width - 72)
        return
      }
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

  /// Opens it ahead of `eye` along the horizontal part of `forward`: 2.4 m for the stereo page (the subject's own distance, so the
  /// screen plane sits where the rover saw the patch), 1.75 m for WATSON; same angular size either way.
  func open(eye: SIMD3<Float>, forward: SIMD3<Float>, now: TimeInterval) {
    guard !isOpen else { return }
    isOpen = true
    openedAt = now
    awayFor = 0
    lastTick = now
    var f = SIMD3(forward.x, 0, forward.z)
    f = simd_length(f) > 0.05 ? simd_normalize(f) : SIMD3(0, 0, -1)
    anchorEye = eye
    anchorDir = f
    if page != 0 { page = 0 }
    configure(lastSci)
    place()
    node.isHidden = false
    node.removeAllActions()
    node.runAction(.fadeIn(duration: 0.25))
  }

  private func place() {
    let d: Float = page == 0 ? 2.4 : 1.75
    let k = d / 1.75
    node.simdScale = SIMD3(repeating: k)
    node.simdPosition = anchorEye + anchorDir * d + SIMD3(0, -0.06 * k, 0)
    node.look(at: SCNVector3(anchorEye.x, anchorEye.y - 0.06 * k, anchorEye.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
  }

  /// The button while open: stereo -> WATSON -> closed. Returns true when it only turned the page.
  func advance() -> Bool {
    guard isOpen else { return false }
    if page == 0 {
      page = 1
      awayFor = 0
      configure(lastSci)
      place()
      return true
    }
    close()
    return false
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
    if awayFor > 3 && !Self.keepOpen { close(); return true }
    return false
  }
}
