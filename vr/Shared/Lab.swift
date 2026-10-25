import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The lights of Science's lab bench (the bench itself is baked into the room by `Dressing.labBench`): a bench lamp with its own
/// glow, a strip light over the bench and a cool pool on the wall. All of it goes dark when `world.lab == "paused"`, and a small
/// "LAB PAUSED" sign comes up. Costs nothing per frame: two emissive materials and a few sprites.
final class LabLights {
  let node = SCNNode()
  private let bulb: SCNMaterial
  private let strip: SCNMaterial
  private var glows: [SCNNode] = []
  private let paused = SpritePanel(width: 0.62, height: 0.15, pixelsPerMeter: 400)
  private(set) var isOn = true
  private static let bulbOn = PlatformColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 1)
  private static let stripOn = PlatformColor(red: 0.80, green: 0.93, blue: 1.0, alpha: 1)
  private static let off = PlatformColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)

  /// `holder` places a node in the bench's frame (angle and radius on the wall, local +z toward the room's centre).
  init(holder: (Float, Float) -> SCNNode) {
    bulb = SCNMaterial()
    bulb.lightingModel = .constant
    bulb.diffuse.contents = Self.bulbOn
    strip = SCNMaterial()
    strip.lightingModel = .constant
    strip.diffuse.contents = Self.stripOn
    let h = holder(106, 3.55)
    // Lamp: weighted base, two arm segments, a shade, the bulb.
    let steel = SCNMaterial()
    steel.lightingModel = .lambert
    steel.diffuse.contents = PlatformColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 1)
    func part(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3, _ e: SCNVector3 = SCNVector3Zero) {
      g.materials = [m]
      let n = SCNNode(geometry: g)
      n.position = p
      n.eulerAngles = e
      h.addChildNode(n)
    }
    part(SCNCylinder(radius: 0.07, height: 0.025), steel, SCNVector3(0.46, 0.93, 0.08))
    part(SCNCylinder(radius: 0.008, height: 0.34), steel, SCNVector3(0.46, 1.10, 0.08), SCNVector3(0, 0, 0.18))
    part(SCNCylinder(radius: 0.008, height: 0.28), steel, SCNVector3(0.40, 1.30, 0.10), SCNVector3(0, 0, -1.0))
    part(SCNCone(topRadius: 0.025, bottomRadius: 0.085, height: 0.10), steel, SCNVector3(0.30, 1.40, 0.14), SCNVector3(0.5, 0, 0.5))
    let b = SCNSphere(radius: 0.03)
    b.materials = [bulb]
    let bn = SCNNode(geometry: b)
    bn.position = SCNVector3(0.285, 1.355, 0.15)
    h.addChildNode(bn)
    // The strip over the bench, on the wall.
    let s = SCNBox(width: 1.1, height: 0.03, length: 0.06, chamferRadius: 0.012)
    s.materials = [strip]
    let sn = SCNNode(geometry: s)
    sn.position = SCNVector3(0, 1.58, -0.02)
    h.addChildNode(sn)
    // Glows (additive sprites): around the lamp, a pool on the wall behind, and the strip's wash down onto the bench.
    func glow(_ c: PlatformColor, strength: CGFloat, w: CGFloat, hh: CGFloat, at p: SCNVector3) {
      let pl = SCNPlane(width: w, height: hh)
      pl.materials = [Tex.glowMaterial(c, strength: strength)]
      let n = SCNNode(geometry: pl)
      n.position = p
      n.renderingOrder = 55
      h.addChildNode(n)
      glows.append(n)
    }
    glow(PlatformColor(red: 1.0, green: 0.92, blue: 0.72, alpha: 1), strength: 0.55, w: 0.9, hh: 0.9, at: SCNVector3(0.30, 1.36, 0.22))
    glow(PlatformColor(red: 1.0, green: 0.90, blue: 0.70, alpha: 1), strength: 0.30, w: 1.8, hh: 1.2, at: SCNVector3(0.2, 1.15, -0.04))
    glow(PlatformColor(red: 0.70, green: 0.88, blue: 1.0, alpha: 1), strength: 0.26, w: 1.6, hh: 0.8, at: SCNVector3(0, 1.38, 0.0))
    paused.node.position = SCNVector3(0, 1.58, 0.03)
    paused.node.opacity = 0
    paused.node.isHidden = true
    paused.update(key: "paused") { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 0.9), radius: size.height / 2)
      ctx.setStrokeColor(Palette.amber.cgColor)
      ctx.setLineWidth(5)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: size.height / 2 - 3, cornerHeight: size.height / 2 - 3, transform: nil))
      ctx.strokePath()
      let t = "LAB PAUSED"
      let font = PlatformFont.systemFont(ofSize: 78, weight: .heavy)
      let w = (t as NSString).size(withAttributes: [.font: font]).width
      _ = Draw.text(t, at: CGPoint(x: (size.width - w) / 2, y: (size.height - font.lineHeight) / 2), size: 78, weight: .heavy, color: Palette.amber, width: size.width)
    }
    h.addChildNode(paused.node)
    node.addChildNode(h)
  }

  /// Lamp and lab lights on or off (with a short fade).
  func set(on: Bool) {
    guard on != isOn else { return }
    isOn = on
    bulb.diffuse.contents = on ? Self.bulbOn : Self.off
    strip.diffuse.contents = on ? Self.stripOn : Self.off
    for g in glows {
      g.removeAllActions()
      g.runAction(on ? .fadeIn(duration: 0.5) : .fadeOut(duration: 0.7))
    }
    paused.node.removeAllActions()
    if on {
      paused.node.runAction(.sequence([.fadeOut(duration: 0.3), .hide()]))
    } else {
      paused.node.isHidden = false
      paused.node.runAction(.fadeIn(duration: 0.6))
    }
  }
}
