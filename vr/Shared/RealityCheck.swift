import SceneKit
import ImageIO
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// "Reality check": from the rover outside, the whole simulated world fades out (0.6 s) and the judge stands inside Perseverance's own
/// 360-degree panorama (Mastcam-Z, sols 53-64, Van Zyl Overlook, PIA24663). One inside-facing mesh around the head, one 8192 px
/// texture, a caption card. The headset toggles it (rover tap, or the debug flag) and streams `rc` so the Mac mirrors it (mono).
///
/// Panorama geometry (verify-10: projection not stated, treated as equirectangular 360 x 80 deg): 9 deg of sky above the horizon,
/// 71 deg of ground below, so the real horizon sits at eye level. Above and below that band the first and last pixel rows are stretched
/// (sky towards the zenith, ground towards the nadir). The black gaps in the master (where the rover deck was) are filled with smooth,
/// darker ground colour in the bundled copy (scripts/fill-pano-voids.swift) and the caption says so.
final class RealityCheck {
  static let shared = RealityCheck()
  static func toggle() { shared.toggle() }

  static let caption = "This is what Perseverance actually saw here. Mastcam-Z, sols 53-64 (2021), Van Zyl Overlook, Jezero crater floor. Credit NASA/JPL-Caltech/ASU/MSSS. Direction not aligned with the base. Gaps where the rover stood are filled with simulated ground."
  static let panoName = "pers-pano-vanzyl-8192-filled"
  /// Degrees of sky above the horizon and of ground below it in the 360 x 80 degree master.
  static let skyDeg: Float = 9, groundDeg: Float = 71
  static let radius: Float = 10 // inside the minimum outdoor fog start (20 m), so the mesh is never hazed
  static let order = 5000 // above the world, below the reticle (10000) and the fade-to-black quad (30000)

  private weak var world: BaseScene?
  private let sphere = SCNNode()
  private let card = TextPanel(width: 1.7, height: 0.78, pixelsPerMeter: 640, emissive: true)
  private let material = SCNMaterial()
  private(set) var wantOn = false
  /// 0 = simulated world, 1 = panorama.
  private(set) var fade: Float = 0
  private var lastNow: TimeInterval?
  private var hidden: [SCNNode] = []
  private var eye = SIMD3<Float>(0, 1.6, 0)
  private var forward = SIMD3<Float>(0, 0, -1)
  private var textureReady = false
  /// Called on the main thread once the panorama texture is attached (the renderer pre-uploads it).
  var onTextureReady: ((SCNNode) -> Void)?
  /// Load time of the 8192 texture, for the logs.
  private(set) var loadSeconds: Double = 0

  var isActive: Bool { wantOn || fade > 0 }
  /// True while a stereo close-up or story state would make it wrong to show (outside only, not at the storm door).
  var isAllowed: Bool {
    guard let d = world?.director else { return false }
    return d.isOutside && d.station != "door" && !d.isEntering
  }

  /// Builds the mesh and starts loading the panorama off the main thread.
  func install(world: BaseScene) {
    guard self.world == nil else { return }
    self.world = world
    material.lightingModel = .constant
    material.diffuse.contents = PlatformColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1)
    material.diffuse.wrapS = .repeat
    material.diffuse.wrapT = .clamp
    material.diffuse.mipFilter = .linear
    material.cullMode = .front // we look at the inside
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    sphere.geometry = Self.makeMesh()
    sphere.geometry?.materials = [material]
    sphere.name = "realitySphere"
    sphere.renderingOrder = Self.order
    sphere.opacity = 0
    sphere.isHidden = true
    sphere.castsShadow = false
    card.node.name = "realityCard"
    card.node.renderingOrder = Self.order + 1000
    card.node.opacity = 0
    card.node.isHidden = true
    for m in card.node.geometry?.materials ?? [] { m.readsFromDepthBuffer = false; m.writesToDepthBuffer = false }
    world.scene.rootNode.addChildNode(sphere)
    world.scene.rootNode.addChildNode(card.node)
    card.update(key: "rc-caption") { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1))
      ctx.setStrokeColor(Palette.amber.cgColor)
      ctx.setLineWidth(8)
      ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
      _ = Draw.text("REAL MARS · NOT A SIMULATION", at: CGPoint(x: 34, y: 20), size: 40, weight: .heavy, color: Palette.amber, width: size.width - 68)
      _ = Draw.text(Self.caption, at: CGPoint(x: 34, y: 78), size: 36, weight: .semibold, color: Palette.text, width: size.width - 68, maxLines: 6)
      _ = Draw.text("Press the button to return", at: CGPoint(x: 34, y: size.height - 56), size: 32, weight: .bold, color: Palette.dim, width: size.width - 68)
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let t0 = CACurrentMediaTime()
      guard let url = Bundle.main.url(forResource: Self.panoName, withExtension: "jpg"),
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return }
      let dt = CACurrentMediaTime() - t0
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadSeconds = dt
        self.material.diffuse.contents = img
        self.textureReady = true
        NSLog("RealityCheck: panorama %dx%d decoded in %.0f ms", img.width, img.height, dt * 1000)
        self.onTextureReady?(self.sphere)
      }
    }
  }

  /// Toggles when allowed (the rover tap, the debug key). Turning off is always allowed.
  func toggle() { set(!wantOn) }

  /// Sets the wanted state (the spectator follows the headset's `rc` flag).
  func set(_ on: Bool) {
    guard on != wantOn, world != nil else { return }
    if on && !(isAllowed && textureReady) { return }
    wantOn = on
    if on {
      world?.director.closeUp.close()
      // Start facing the rock-strewn middle of the panorama (the horizon-ward 40% of the 360), whichever way the judge looks.
      let h0 = atan2(forward.x, -forward.z)
      sphere.simdEulerAngles = SIMD3(0, 0.40 * 2 * .pi - h0, 0)
      sphere.isHidden = false
      card.node.isHidden = false
      var f = SIMD3(forward.x, 0, forward.z)
      f = simd_length(f) > 0.05 ? simd_normalize(f) : SIMD3(0, 0, -1)
      card.node.simdPosition = eye + f * 1.9 + SIMD3(0, -0.72, 0)
      card.node.look(at: SCNVector3(eye.x, eye.y - 0.55, eye.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    } else {
      restoreWorld()
    }
  }

  /// Per frame, main thread. `eye`/`forward` are the judge's head position and look direction (world).
  func update(now: TimeInterval, eye: SIMD3<Float>, forward: SIMD3<Float>) {
    guard world != nil else { return }
    let dt = Float(min(0.1, max(0, now - (lastNow ?? now))))
    lastNow = now
    self.eye = eye
    self.forward = forward
    if wantOn && !isAllowed { set(false) }
    let target: Float = wantOn ? 1 : 0
    if fade != target {
      let step = dt / 0.6
      fade = fade < target ? min(target, fade + step) : max(target, fade - step)
      sphere.opacity = CGFloat(fade)
      card.node.opacity = CGFloat(fade)
      if fade <= 0 { sphere.isHidden = true; card.node.isHidden = true }
    }
    sphere.simdPosition = eye
    if wantOn && fade >= 0.999 && hidden.isEmpty { hideWorld() }
  }

  /// Fully covered: stop drawing the simulated world (60 fps; one panorama is all that is on screen).
  private func hideWorld() {
    guard let w = world else { return }
    for n in w.scene.rootNode.childNodes where !n.isHidden && n !== sphere && n !== card.node && n !== w.head && n.camera == nil
      && !(n.childNodes.first?.geometry is SCNTorus) /* the reticle */ {
      n.isHidden = true
      hidden.append(n)
    }
  }

  private func restoreWorld() {
    for n in hidden { n.isHidden = false }
    hidden.removeAll()
  }

  // MARK: mesh

  /// Rows run from the zenith to the nadir; columns wrap once around. u = heading / 360 (0 = scene -Z, growing towards +X),
  /// v = 0 at the top of the image.
  private static func makeMesh() -> SCNGeometry {
    let cols = 96
    var rows: [Float] = [90, 55, 28]
    var el = skyDeg
    while el >= -groundDeg { rows.append(el); el -= 2 }
    rows.append(-90)
    var pos: [SCNVector3] = [], uv: [CGPoint] = []
    let r = Self.radius
    for e in rows {
      let phi = e * .pi / 180
      let v = min(1, max(0, (skyDeg - e) / (skyDeg + groundDeg))) // SceneKit's v = 0 is the top row of an image
      for c in 0...cols {
        let u = Float(c) / Float(cols)
        let th = u * 2 * .pi
        pos.append(SCNVector3(r * cos(phi) * sin(th), r * sin(phi), -r * cos(phi) * cos(th)))
        uv.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
      }
    }
    var idx: [UInt32] = []
    let stride = cols + 1
    for rI in 0..<(rows.count - 1) {
      for c in 0..<cols {
        let a = UInt32(rI * stride + c), b = a + 1, d = a + UInt32(stride), e = d + 1
        // Outward-facing counter-clockwise (rows go downward, columns clockwise seen from above); cullMode .front shows the inside.
        idx.append(contentsOf: [a, b, d, b, e, d])
      }
    }
    let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(textureCoordinates: uv)],
                        elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    return g
  }
}
