import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
    // Painted-metal wall panels: three paint variants; the window's sill and header pieces show the
    // bottom / top slice of the same panel texture so seams and grime line up.
    let panels = (0..<3).map { Tex.material(Tex.wallPanel(variant: $0)) }
    func slice(_ m: SCNMaterial, y0: Float, y1: Float) -> SCNMaterial {
      let c = m.copy() as! SCNMaterial
      let f = (y1 - y0) / height
      c.diffuse.contentsTransform = SCNMatrix4MakeScale(1, CGFloat(f), 1)
      c.diffuse.wrapT = .clamp
      c.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(1, CGFloat(f), 1), SCNMatrix4MakeTranslation(0, CGFloat(y0 / height), 0))
      return c
    }
    let sillPanels = panels.map { slice($0, y0: 0, y1: sill) }
    let headPanels = panels.map { slice($0, y0: header, y1: height) }
    let trim = mat(PlatformColor(red: 0.90, green: 0.50, blue: 0.22, alpha: 1), rough: 0.5)
    let alu = Tex.material(Tex.brushed())
    let kick = mat(PlatformColor(red: 0.20, green: 0.19, blue: 0.19, alpha: 1), rough: 0.6)
    let frame = mat(PlatformColor(white: 0.25, alpha: 1), rough: 0.4)
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
        let v = i % 3
        p.geometry?.materials = [!inWindow ? panels[v] : (y0 == 0 ? sillPanels[v] : headPanels[v])]
        p.position = ring(c, r: radius, y: (y0 + y1) / 2)
        p.look(at: SCNVector3(0, (y0 + y1) / 2, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        shell.addChildNode(p)
      }
      // Waist trim band around the room (skipped across the window).
      if !inWindow {
        let band = SCNNode(geometry: SCNPlane(width: w, height: 0.06))
        band.geometry?.materials = [alu]
        band.position = ring(c, r: radius - 0.01, y: 1.05)
        band.look(at: SCNVector3(0, 1.05, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        shell.addChildNode(band)
        let accent = SCNNode(geometry: SCNPlane(width: w, height: 0.018))
        accent.geometry?.materials = [trim]
        accent.position = ring(c, r: radius - 0.014, y: 1.095)
        accent.look(at: SCNVector3(0, 1.095, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        shell.addChildNode(accent)
        // Brushed-aluminium crown trim under the ceiling and a dark kick plate at the floor.
        for (mm, hh, yy, off) in [(alu, Float(0.10), Float(height - 0.05), Float(0.012)), (kick, Float(0.14), Float(0.07), Float(0.012))] {
          let t = SCNNode(geometry: SCNPlane(width: w, height: CGFloat(hh)))
          t.geometry?.materials = [mm]
          t.position = ring(c, r: radius - off, y: yy)
          t.look(at: SCNVector3(0, yy, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
          shell.addChildNode(t)
        }
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
      mull.simdEulerAngles.y = -m * .pi / 180
      shell.addChildNode(mull)
      m += 10
    }
    var s = -windowHalfAngle
    while s < windowHalfAngle {
      for y in [sill, header] {
        let bar = SCNNode(geometry: SCNBox(width: CGFloat(2 * radius * sin(2.5 * .pi / 180)) + 0.02, height: 0.08, length: 0.22, chamferRadius: 0.01))
        bar.geometry?.materials = [frame]
        bar.position = ring(s + 2.5, r: radius - 0.08, y: y)
        bar.simdEulerAngles.y = -(s + 2.5) * .pi / 180
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
    ceil.geometry?.materials = [Tex.material(Tex.ceilingImage())]
    ceil.position = SCNVector3(0, height + 0.02, 0)
    shell.addChildNode(ceil)
    // Consoles: an arc desk under the window.
    let desk = mat(PlatformColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 1), rough: 0.5)
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
      front.simdEulerAngles.y = -(d + 2.5) * .pi / 180
      shell.addChildNode(front)
      d += 6
    }
    let flat = shell.flattenedClone()
    flat.name = "room"
    root.addChildNode(flat)

    // Emissive details stay separate (constant lighting).
    let glow = SCNMaterial()
    glow.lightingModel = .constant
    glow.diffuse.contents = PlatformColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
    let ringLight = SCNNode(geometry: SCNTorus(ringRadius: 2.2, pipeRadius: 0.035))
    ringLight.geometry?.materials = [glow]
    ringLight.position = SCNVector3(0, height - 0.05, 0)
    root.addChildNode(ringLight)
    let strip = SCNMaterial()
    strip.lightingModel = .constant
    strip.diffuse.contents = PlatformColor(red: 0.36, green: 0.84, blue: 0.95, alpha: 1)
    var k: Float = -33
    while k < 33 {
      let led = SCNNode(geometry: SCNBox(width: 0.30, height: 0.015, length: 0.01, chamferRadius: 0))
      led.geometry?.materials = [strip]
      led.position = ring(k + 2.5, r: 2.78, y: 0.72)
      led.simdEulerAngles.y = -(k + 2.5) * .pi / 180
      root.addChildNode(led)
      k += 6
    }
    // Warm ceiling strips: emissive bars plus a soft additive glow sprite on the ceiling (no bloom pass).
    let strips = SCNNode()
    let sprites = SCNNode()
    let stripMat = SCNMaterial()
    stripMat.lightingModel = .constant
    stripMat.diffuse.contents = PlatformColor(red: 1.0, green: 0.90, blue: 0.70, alpha: 1)
    let halo = Tex.glowMaterial(PlatformColor(red: 1.0, green: 0.78, blue: 0.5, alpha: 1), strength: 0.55)
    for k in 0..<8 {
      let deg = Float(k) * 45 + 22.5
      let bar = SCNNode(geometry: SCNBox(width: 0.10, height: 0.02, length: 1.5, chamferRadius: 0))
      bar.geometry?.materials = [stripMat]
      bar.position = ring(deg, r: 2.9, y: height - 0.03)
      bar.simdEulerAngles.y = -deg * .pi / 180
      strips.addChildNode(bar)
      let s = SCNNode(geometry: SCNPlane(width: 0.9, height: 2.3))
      s.geometry?.materials = [halo]
      s.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
      let holder = SCNNode()
      holder.position = ring(deg, r: 2.9, y: height - 0.045)
      holder.simdEulerAngles.y = -deg * .pi / 180
      holder.addChildNode(s)
      sprites.addChildNode(holder)
    }
    root.addChildNode(strips.flattenedClone())
    let spriteFlat = sprites.flattenedClone()
    spriteFlat.renderingOrder = 50
    root.addChildNode(spriteFlat)
    // Interior light: warm key from the ceiling, plus a cool fill from the screens on each side.
    let lamp = SCNNode()
    lamp.light = SCNLight()
    lamp.light?.type = .omni
    lamp.light?.intensity = 620
    lamp.light?.color = PlatformColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1)
    lamp.light?.attenuationStartDistance = 3
    lamp.light?.attenuationEndDistance = 9
    lamp.position = SCNVector3(0, 2.9, 0.5)
    root.addChildNode(lamp)
    for side: Float in [-1, 1] {
      let fill = SCNNode()
      fill.light = SCNLight()
      fill.light?.type = .omni
      fill.light?.intensity = 220
      fill.light?.color = PlatformColor(red: 0.62, green: 0.74, blue: 0.85, alpha: 1)
      fill.light?.attenuationStartDistance = 1.5
      fill.light?.attenuationEndDistance = 5
      fill.position = SCNVector3(side * 2.7, 1.8, -1.2)
      root.addChildNode(fill)
    }
    Dressing.build(into: root)
  }

  static func mat(_ c: PlatformColor, rough: CGFloat) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .lambert
    m.diffuse.contents = c
    m.isDoubleSided = false
    return m
  }

  static func floorMaterial() -> SCNMaterial {
    Tex.material(Tex.floorImage())
  }
}
