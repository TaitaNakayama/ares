import SceneKit
import UIKit

/// Round control room, radius 4 m, with a curved window facing -Z (toward the delta).
/// Static geometry is flattened so the whole shell costs a handful of draw calls.
enum Room {
  static let radius: Float = 4.0
  static let windowHalfAngle: Float = 40 // degrees either side of -Z
  static let sill: Float = 0.85
  static let header: Float = 2.75
  static let height: Float = 3.2

  /// Position on a circle: angle in degrees, 0 = -Z (straight ahead), positive = to the right.
  static func ring(_ deg: Float, r: Float, y: Float) -> SCNVector3 {
    let a = deg * .pi / 180
    return SCNVector3(sin(a) * r, y, -cos(a) * r)
  }

  static func build(into root: SCNNode) {
    let shell = SCNNode()
    let wall = mat(UIColor(red: 0.88, green: 0.86, blue: 0.82, alpha: 1), rough: 0.8)
    let wallDark = mat(UIColor(red: 0.74, green: 0.72, blue: 0.69, alpha: 1), rough: 0.8)
    let trim = mat(UIColor(red: 0.90, green: 0.50, blue: 0.22, alpha: 1), rough: 0.5)
    let frame = mat(UIColor(white: 0.25, alpha: 1), rough: 0.4)
    let seg: Float = 5
    let w = CGFloat(2 * radius * sin(seg / 2 * .pi / 180)) + 0.01
    var a: Float = -180
    var i = 0
    while a < 180 {
      let c = a + seg / 2
      let inWindow = abs(c) < windowHalfAngle
      let pieces: [(Float, Float)] = inWindow ? [(Float(0), sill), (header, height)] : [(Float(0), height)]
      for (y0, y1) in pieces {
        let p = SCNNode(geometry: SCNPlane(width: w, height: CGFloat(y1 - y0)))
        p.geometry?.materials = [i % 4 == 0 ? wallDark : wall]
        p.position = ring(c, r: radius, y: (y0 + y1) / 2)
        p.look(at: SCNVector3(0, (y0 + y1) / 2, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        shell.addChildNode(p)
      }
      // Waist trim band around the room (skipped across the window).
      if !inWindow {
        let band = SCNNode(geometry: SCNPlane(width: w, height: 0.06))
        band.geometry?.materials = [trim]
        band.position = ring(c, r: radius - 0.01, y: 1.05)
        band.look(at: SCNVector3(0, 1.05, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        shell.addChildNode(band)
      }
      a += seg
      i += 1
    }
    // Window frame: mullions, sill and header.
    var m = -windowHalfAngle
    while m <= windowHalfAngle + 0.01 {
      let mull = SCNNode(geometry: SCNBox(width: 0.08, height: CGFloat(header - sill), length: 0.12, chamferRadius: 0.01))
      mull.geometry?.materials = [frame]
      mull.position = ring(m, r: radius - 0.04, y: (sill + header) / 2)
      mull.eulerAngles.y = -m * .pi / 180
      shell.addChildNode(mull)
      m += 10
    }
    var s = -windowHalfAngle
    while s < windowHalfAngle {
      for y in [sill, header] {
        let bar = SCNNode(geometry: SCNBox(width: CGFloat(2 * radius * sin(2.5 * .pi / 180)) + 0.02, height: 0.08, length: 0.22, chamferRadius: 0.01))
        bar.geometry?.materials = [frame]
        bar.position = ring(s + 2.5, r: radius - 0.08, y: y)
        bar.eulerAngles.y = -(s + 2.5) * .pi / 180
        shell.addChildNode(bar)
      }
      s += 5
    }
    // Floor and ceiling.
    let floor = SCNNode(geometry: SCNCylinder(radius: CGFloat(radius + 0.05), height: 0.04))
    floor.geometry?.materials = [floorMaterial()]
    floor.position = SCNVector3(0, -0.02, 0)
    shell.addChildNode(floor)
    let ceil = SCNNode(geometry: SCNCylinder(radius: CGFloat(radius + 0.05), height: 0.04))
    ceil.geometry?.materials = [mat(UIColor(white: 0.82, alpha: 1), rough: 0.9)]
    ceil.position = SCNVector3(0, height + 0.02, 0)
    shell.addChildNode(ceil)
    // Consoles: an arc desk under the window.
    let desk = mat(UIColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 1), rough: 0.5)
    var d: Float = -34
    while d < 34 {
      let top = SCNNode(geometry: SCNBox(width: 0.40, height: 0.06, length: 0.55, chamferRadius: 0.02))
      top.geometry?.materials = [desk]
      top.position = ring(d + 2.5, r: 3.05, y: 0.82)
      top.eulerAngles = SCNVector3(-0.25, -(d + 2.5) * .pi / 180, 0)
      shell.addChildNode(top)
      let front = SCNNode(geometry: SCNBox(width: 0.40, height: 0.78, length: 0.05, chamferRadius: 0.01))
      front.geometry?.materials = [desk]
      front.position = ring(d + 2.5, r: 2.80, y: 0.40)
      front.eulerAngles.y = -(d + 2.5) * .pi / 180
      shell.addChildNode(front)
      d += 6
    }
    let flat = shell.flattenedClone()
    flat.name = "room"
    root.addChildNode(flat)

    // Emissive details stay separate (constant lighting).
    let glow = SCNMaterial()
    glow.lightingModel = .constant
    glow.diffuse.contents = UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
    let ringLight = SCNNode(geometry: SCNTorus(ringRadius: 2.2, pipeRadius: 0.035))
    ringLight.geometry?.materials = [glow]
    ringLight.position = SCNVector3(0, height - 0.05, 0)
    root.addChildNode(ringLight)
    let strip = SCNMaterial()
    strip.lightingModel = .constant
    strip.diffuse.contents = UIColor(red: 0.36, green: 0.84, blue: 0.95, alpha: 1)
    var k: Float = -33
    while k < 33 {
      let led = SCNNode(geometry: SCNBox(width: 0.30, height: 0.015, length: 0.01, chamferRadius: 0))
      led.geometry?.materials = [strip]
      led.position = ring(k + 2.5, r: 2.78, y: 0.72)
      led.eulerAngles.y = -(k + 2.5) * .pi / 180
      root.addChildNode(led)
      k += 6
    }
    // Interior light: warm, soft.
    let lamp = SCNNode()
    lamp.light = SCNLight()
    lamp.light?.type = .omni
    lamp.light?.intensity = 520
    lamp.light?.color = UIColor(red: 1.0, green: 0.90, blue: 0.78, alpha: 1)
    lamp.light?.attenuationStartDistance = 3
    lamp.light?.attenuationEndDistance = 9
    lamp.position = SCNVector3(0, 2.9, 0.5)
    root.addChildNode(lamp)
  }

  static func mat(_ c: UIColor, rough: CGFloat) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .lambert
    m.diffuse.contents = c
    m.isDoubleSided = false
    return m
  }

  static func floorMaterial() -> SCNMaterial {
    let size = CGSize(width: 512, height: 512)
    let img = UIGraphicsImageRenderer(size: size).image { ctx in
      let c = ctx.cgContext
      c.setFillColor(UIColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 1).cgColor)
      c.fill(CGRect(origin: .zero, size: size))
      c.setStrokeColor(UIColor(white: 1, alpha: 0.08).cgColor)
      c.setLineWidth(3)
      for r in stride(from: 40.0, through: 250.0, by: 52.0) {
        c.strokeEllipse(in: CGRect(x: 256 - r, y: 256 - r, width: 2 * r, height: 2 * r))
      }
      c.setStrokeColor(UIColor(red: 0.9, green: 0.5, blue: 0.22, alpha: 0.5).cgColor)
      c.setLineWidth(5)
      c.strokeEllipse(in: CGRect(x: 256 - 70, y: 256 - 70, width: 140, height: 140))
    }
    let m = SCNMaterial()
    m.lightingModel = .lambert
    m.diffuse.contents = img
    return m
  }
}
