import SceneKit
import ModelIO
import SceneKit.ModelIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Set dressing for the control room: everything that makes it feel lived in. Built once at launch from
/// primitives and a few CC0 props, merged into a handful of nodes (flattenedClone) so it stays cheap.
/// Angles follow Room.ring: 0 = straight ahead (the window), positive = to the right, 180 = behind.
/// Keep-clear zones: the window arc (+-45), the wall screens (+-47..79 above 1.1 m), the debug panel
/// (172..188), the robots' paths in front of the desks, and the decision cards (1.9 m ahead).
enum Dressing {
  // ---------------------------------------------------------------- small helpers

  /// A node at a wall angle/radius whose local +Z points at the room centre.
  private static func holder(_ deg: Float, r: Float, y: Float = 0) -> SCNNode {
    let h = SCNNode()
    h.position = Room.ring(deg, r: r, y: y)
    h.simdEulerAngles.y = -deg * .pi / 180
    return h
  }

  private static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero, chamfer: CGFloat = 0) -> SCNNode {
    let n = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: chamfer))
    n.geometry?.materials = [m]
    n.position = p
    return n
  }

  private static func flat(_ m: SCNMaterial, w: CGFloat, h: CGFloat, at p: SCNVector3) -> SCNNode {
    let n = SCNNode(geometry: SCNPlane(width: w, height: h))
    n.geometry?.materials = [m]
    n.position = p
    return n
  }

  private static func solid(_ c: PlatformColor) -> SCNMaterial { Room.mat(c, rough: 0.7) }

  private static func emissive(_ c: PlatformColor) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = c
    return m
  }

  /// A lit textured plane material (image drawn in code).
  private static func picture(_ size: CGSize, opaque: Bool = true, _ draw: @escaping (CGContext) -> Void) -> SCNMaterial {
    let m = Tex.material(Bitmap.image(size: size, scale: 1, opaque: opaque, draw))
    return m
  }

  // ---------------------------------------------------------------- props from the bundle

  private static var templates: [String: SCNNode] = [:]
  private static var propMats: [String: SCNMaterial] = [:]

  /// A Poly Haven .usdc prop (Z-up in the file) standing on y = 0 with its diffuse JPG; geometry is shared between clones.
  private static func prop(_ id: String, diffuse: String, scale: Float = 1) -> SCNNode? {
    if templates[id] == nil {
      guard let url = Bundle.main.url(forResource: id + "_1k", withExtension: "usdc"),
            let scene = try? SCNScene(url: url, options: nil) else { return nil }
      let merged = scene.rootNode.flattenedClone()
      if propMats[diffuse] == nil { propMats[diffuse] = Tex.material(Tex.cg(diffuse)) }
      merged.enumerateHierarchy { n, _ in n.geometry?.materials = [propMats[diffuse]!] }
      let upright = SCNNode()
      upright.eulerAngles.x = -.pi / 2
      upright.addChildNode(merged)
      templates[id] = upright
    }
    let n = templates[id]!.clone()
    n.scale = SCNVector3(scale, scale, scale)
    return n
  }

  private static func mug() -> SCNNode? {
    guard let url = Bundle.main.url(forResource: "mug", withExtension: "obj") else { return nil }
    let asset = MDLAsset(url: url)
    let n = SCNNode()
    let m = Tex.material(Tex.cg("foodkit_colormap", "png"), mip: false)
    for i in 0..<asset.count {
      let c = SCNNode(mdlObject: asset.object(at: i))
      c.geometry?.materials = [m]
      n.addChildNode(c)
    }
    n.scale = SCNVector3(0.34, 0.34, 0.34)
    return n.flattenedClone()
  }

  // ---------------------------------------------------------------- build

  static func build(into root: SCNNode) {
    let lit = SCNNode()      // everything lit and static: merged by material
    let glowNodes = SCNNode() // additive sprites
    let emis = SCNNode()     // emissive bars and LEDs

    consoles(lit)
    cables(lit)
    pipes(lit)
    vents(lit)
    lockers(lit)
    hydroponics(lit, emis, glowNodes)
    storage(lit)
    equipment(lit, emis)
    whiteboard(lit)
    door(lit, emis)
    sideTable(lit)

    root.addChildNode(bake(lit))
    root.addChildNode(bake(emis))
    let g = bake(glowNodes)
    g.renderingOrder = 60
    root.addChildNode(g)
  }

  /// Merges a hierarchy into one flat node per material. flattenedClone on nested holders mis-places
  /// children here, so every geometry is first re-parented flat with its world transform.
  private static func bake(_ group: SCNNode) -> SCNNode {
    let flatGroup = SCNNode()
    group.enumerateHierarchy { n, _ in
      guard n.geometry != nil else { return }
      let c = n.clone()
      c.childNodes.forEach { $0.removeFromParentNode() }
      c.transform = n.worldTransform
      flatGroup.addChildNode(c)
    }
    return flatGroup.flattenedClone()
  }

  // ---------------------------------------------------------------- consoles

  /// Key/LED surfaces laid on the arc desk, matching each desk segment's transform exactly.
  private static func consoles(_ out: SCNNode) {
    let faces = (0..<2).map { v in
      picture(CGSize(width: 256, height: 400)) { c in
        var rng = Tex.RNG(s: UInt64(40 + v))
        c.setFillColor(PlatformColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 256, height: 384))
        c.setFillColor(PlatformColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1).cgColor)
        c.fill(CGRect(x: 10, y: 10, width: 236, height: 90))
        let cols: [PlatformColor] = [PlatformColor(red: 0.23, green: 0.88, blue: 0.48, alpha: 1), PlatformColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1), PlatformColor(red: 0.36, green: 0.84, blue: 0.95, alpha: 1)]
        for r in 0..<2 { for i in 0..<10 {
          c.setFillColor(cols[Int(rng.next() * 3) % 3].withAlphaComponent(0.5 + rng.next() * 0.5).cgColor)
          c.fillEllipse(in: CGRect(x: 22 + CGFloat(i) * 22, y: 24 + CGFloat(r) * 30, width: 10, height: 10))
        } }
        // keycaps
        for r in 0..<6 { for i in 0..<9 {
          c.setFillColor(PlatformColor(white: 0.30 + rng.next() * 0.1, alpha: 1).cgColor)
          c.fill(CGRect(x: 12 + CGFloat(i) * 26, y: 130 + CGFloat(r) * 28, width: 22, height: 22))
        } }
        // a slider bank and one big button
        for i in 0..<5 {
          c.setFillColor(PlatformColor(white: 0.05, alpha: 1).cgColor)
          c.fill(CGRect(x: 20 + CGFloat(i) * 30, y: 310, width: 6, height: 60))
          c.setFillColor(PlatformColor(red: 0.9, green: 0.5, blue: 0.22, alpha: 1).cgColor)
          c.fill(CGRect(x: 14 + CGFloat(i) * 30, y: 322 + rng.next() * 30, width: 18, height: 9))
        }
        c.setFillColor(PlatformColor(red: 0.8, green: 0.2, blue: 0.18, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: 190, y: 322, width: 44, height: 44))
      }
    }
    var d: Float = -34
    var i = 0
    while d < 34 {
      // On the desk's front panel (the face the commander sees), just ahead of it.
      let h = SCNNode()
      h.position = Room.ring(d + 2.5, r: 2.765, y: 0.40)
      h.simdEulerAngles.y = -(d + 2.5) * .pi / 180
      h.addChildNode(flat(faces[i % 2], w: 0.38, h: 0.64, at: .init(0, 0, 0)))
      out.addChildNode(h)
      d += 6
      i += 1
    }
  }

  // ---------------------------------------------------------------- cables, pipes, vents

  private static func cables(_ out: SCNNode) {
    let tray = solid(PlatformColor(white: 0.22, alpha: 1))
    let wires = [solid(PlatformColor(white: 0.06, alpha: 1)), solid(PlatformColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1)), solid(PlatformColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1))]
    let seg: Float = 5
    let w = CGFloat(2 * Room.radius * sin(seg / 2 * .pi / 180)) + 0.01
    for side: Float in [-1, 1] {
      var a: Float = 82
      while a < 172 {
        let deg = side * (a + seg / 2)
        // Wall tray at 0.32 m with three cables, and loose cables along the floor edge.
        let h = holder(deg, r: Room.radius - 0.05, y: 0.32)
        h.addChildNode(box(w, 0.07, 0.09, tray))
        for (k, m) in wires.enumerated() {
          h.addChildNode(box(w, 0.018, 0.018, m, at: SCNVector3(0, 0.045, CGFloat(k - 1) * 0.026)))
        }
        out.addChildNode(h)
        let f = holder(deg, r: Room.radius - 0.30, y: 0.015)
        for (k, m) in wires.enumerated() {
          f.addChildNode(box(w, 0.02, 0.02, m, at: SCNVector3(0, 0, CGFloat(k) * 0.035 + CGFloat(sin(deg * 0.35)) * 0.05)))
        }
        out.addChildNode(f)
        a += seg
      }
      // Vertical tray up the wall beside each screen, cables climbing out of the horizontal run.
      let v = holder(side * 85, r: Room.radius - 0.05, y: 1.65)
      v.addChildNode(box(0.14, 2.7, 0.07, tray))
      for (k, m) in wires.enumerated() {
        v.addChildNode(box(0.016, 2.7, 0.016, m, at: SCNVector3(CGFloat(k - 1) * 0.03, 0, 0.045)))
      }
      out.addChildNode(v)
      // Feeder from the vertical tray to the screen's outer edge.
      let fd = holder(side * 82, r: Room.radius - 0.05, y: 2.6)
      fd.addChildNode(box(0.36, 0.06, 0.07, tray))
      fd.addChildNode(box(0.36, 0.016, 0.016, wires[0], at: SCNVector3(0, 0.04, 0.02)))
      fd.addChildNode(box(0.36, 0.016, 0.016, wires[1], at: SCNVector3(0, 0.04, -0.01)))
      out.addChildNode(fd)
    }
  }

  private static func pipes(_ out: SCNNode) {
    let grey = solid(PlatformColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1))
    let blue = solid(PlatformColor(red: 0.25, green: 0.42, blue: 0.62, alpha: 1))
    let seg: Float = 5
    let len = CGFloat(2 * Room.radius * sin(seg / 2 * .pi / 180)) + 0.01
    let cyl = SCNCylinder(radius: 0.045, height: len); cyl.radialSegmentCount = 10
    let cyl2 = SCNCylinder(radius: 0.032, height: len); cyl2.radialSegmentCount = 8
    var a: Float = 50
    while a < 310 {
      let deg = a + seg / 2
      if abs(deg - 180) > 14 { // keep the debug panel's wall clear
        for (g, mm, y, r) in [(cyl, grey, Float(2.92), Float(0.12)), (cyl2, blue, Float(2.80), Float(0.10))] {
          let h = holder(deg, r: Room.radius - r, y: y)
          let n = SCNNode(geometry: g)
          n.geometry?.materials = [mm]
          n.eulerAngles.z = .pi / 2
          h.addChildNode(n)
          out.addChildNode(h)
        }
        // A bracket every 30 degrees.
        if Int(a) % 30 == 0 {
          let h = holder(deg, r: Room.radius - 0.06, y: 2.86)
          h.addChildNode(box(0.05, 0.22, 0.06, solid(PlatformColor(white: 0.2, alpha: 1))))
          out.addChildNode(h)
        }
      }
      a += seg
    }
  }

  private static func vents(_ out: SCNNode) {
    let grille = picture(CGSize(width: 256, height: 192)) { c in
      c.setFillColor(PlatformColor(red: 0.58, green: 0.58, blue: 0.56, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
      c.setFillColor(PlatformColor(white: 0.10, alpha: 1).cgColor)
      c.fill(CGRect(x: 14, y: 14, width: 228, height: 164))
      for i in 0..<8 {
        c.setFillColor(PlatformColor(white: 0.72, alpha: 1).cgColor)
        c.fill(CGRect(x: 14, y: 22 + CGFloat(i) * 20, width: 228, height: 9))
      }
      for p in [CGPoint(x: 6, y: 6), CGPoint(x: 250, y: 6), CGPoint(x: 6, y: 186), CGPoint(x: 250, y: 186)] {
        c.setFillColor(PlatformColor(white: 0.3, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
      }
    }
    for deg: Float in [-110.5, -164, 137, 157] {
      let h = holder(deg, r: Room.radius - 0.012, y: 2.3)
      h.addChildNode(flat(grille, w: 0.5, h: 0.375, at: .init(0, 0, 0)))
      out.addChildNode(h)
    }
  }

  // ---------------------------------------------------------------- crew lockers and patches

  static func patch(_ kind: Int) -> PlatformImage {
    Bitmap.image(size: CGSize(width: 256, height: 256), scale: 1) { c in
      let ctr = CGPoint(x: 128, y: 128)
      c.setFillColor((kind == 0 ? PlatformColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1) : PlatformColor(red: 0.20, green: 0.10, blue: 0.08, alpha: 1)).cgColor)
      c.fillEllipse(in: CGRect(x: 4, y: 4, width: 248, height: 248))
      c.setStrokeColor(PlatformColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1).cgColor)
      c.setLineWidth(10)
      c.strokeEllipse(in: CGRect(x: 10, y: 10, width: 236, height: 236))
      c.saveGState()
      c.addEllipse(in: CGRect(x: 18, y: 18, width: 220, height: 220))
      c.clip()
      if kind == 0 {
        // Rust planet with a crater, a small cardboard-grey habitat dome and stars.
        c.setFillColor(PlatformColor(red: 0.76, green: 0.36, blue: 0.20, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: 38, y: 98, width: 180, height: 180))
        c.setFillColor(PlatformColor(red: 0.58, green: 0.26, blue: 0.14, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: 120, y: 150, width: 44, height: 26))
        c.fillEllipse(in: CGRect(x: 70, y: 176, width: 28, height: 16))
        c.setFillColor(PlatformColor(white: 0.9, alpha: 1).cgColor)
        for p in [CGPoint(x: 60, y: 50), CGPoint(x: 190, y: 70), CGPoint(x: 150, y: 40), CGPoint(x: 90, y: 80), CGPoint(x: 210, y: 120)] {
          c.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 5, height: 5))
        }
        c.setFillColor(PlatformColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: 56, y: 56, width: 34, height: 34))
        c.restoreGState()
        _ = Draw.text("ARES", at: CGPoint(x: 0, y: 108), size: 40, weight: .heavy, color: PlatformColor(white: 0.96, alpha: 1), width: 256, align: .center)
        _ = Draw.text("JEZERO BASE", at: CGPoint(x: 0, y: 206), size: 22, weight: .bold, color: PlatformColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1), width: 256, align: .center)
      } else {
        // Sunrise over ridges with a ring of dots for the crew.
        c.setFillColor(PlatformColor(red: 0.95, green: 0.60, blue: 0.25, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: 78, y: 70, width: 100, height: 100))
        c.setFillColor(PlatformColor(red: 0.45, green: 0.18, blue: 0.10, alpha: 1).cgColor)
        let ridge = CGMutablePath()
        ridge.move(to: CGPoint(x: 10, y: 190)); ridge.addLine(to: CGPoint(x: 70, y: 130)); ridge.addLine(to: CGPoint(x: 110, y: 165))
        ridge.addLine(to: CGPoint(x: 160, y: 110)); ridge.addLine(to: CGPoint(x: 250, y: 190)); ridge.addLine(to: CGPoint(x: 250, y: 250)); ridge.addLine(to: CGPoint(x: 10, y: 250))
        c.addPath(ridge); c.fillPath()
        c.restoreGState()
        _ = Draw.text("SOL ONE-HUNDRED", at: CGPoint(x: 0, y: 36), size: 20, weight: .heavy, color: PlatformColor(red: 0.95, green: 0.72, blue: 0.30, alpha: 1), width: 256, align: .center)
        _ = Draw.text("CREW", at: CGPoint(x: 0, y: 204), size: 30, weight: .heavy, color: PlatformColor(white: 0.96, alpha: 1), width: 256, align: .center)
        _ = ctr
      }
    }
  }

  private static func patchNode(_ kind: Int, size: CGFloat) -> SCNNode {
    let m = Tex.material(patch(kind))
    m.isDoubleSided = false
    let n = SCNNode(geometry: SCNPlane(width: size, height: size))
    n.geometry?.materials = [m]
    return n
  }

  private static func lockers(_ out: SCNNode) {
    let body = solid(PlatformColor(red: 0.28, green: 0.34, blue: 0.38, alpha: 1))
    let names = ["T. VASQUEZ", "M. LINDQVIST"]
    let tints = [PlatformColor(red: 0.26, green: 0.45, blue: 0.50, alpha: 1), PlatformColor(red: 0.55, green: 0.30, blue: 0.24, alpha: 1)]
    for (i, deg) in [Float(-92.5), Float(-100.5)].enumerated() {
      let h = holder(deg, r: 3.66)
      h.addChildNode(box(0.50, 1.95, 0.46, body, at: SCNVector3(0, 0.975, 0)))
      let door = picture(CGSize(width: 256, height: 1024)) { c in
        c.setFillColor(tints[i].cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 256, height: 1024))
        c.setFillColor(PlatformColor(white: 0, alpha: 0.25).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 256, height: 8))
        c.fill(CGRect(x: 0, y: 1016, width: 256, height: 8))
        for k in 0..<7 { c.fill(CGRect(x: 40, y: 50 + CGFloat(k) * 16, width: 176, height: 6)) } // vent slots
        c.setFillColor(PlatformColor(white: 0.82, alpha: 1).cgColor)
        c.fill(CGRect(x: 205, y: 470, width: 14, height: 90)) // handle
        c.setFillColor(PlatformColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1).cgColor)
        c.fill(CGRect(x: 30, y: 200, width: 196, height: 70)) // name tape
        _ = Draw.text(names[i], at: CGPoint(x: 0, y: 214), size: 27, weight: .heavy, color: PlatformColor(white: 0.1, alpha: 1), width: 256, align: .center)
        _ = Draw.text("CREW " + String(i + 1), at: CGPoint(x: 0, y: 320), size: 26, weight: .bold, color: PlatformColor(white: 1, alpha: 0.7), width: 256, align: .center)
        // scuffs near the handle and the bottom edge
        c.setStrokeColor(PlatformColor(white: 1, alpha: 0.25).cgColor)
        c.setLineWidth(2)
        for k in 0..<6 { c.move(to: CGPoint(x: 150 + CGFloat(k) * 9, y: 520 + CGFloat(k % 3) * 20)); c.addLine(to: CGPoint(x: 160 + CGFloat(k) * 9, y: 540 + CGFloat(k % 3) * 20)) }
        c.strokePath()
        c.setFillColor(PlatformColor(white: 0, alpha: 0.3).cgColor)
        c.fill(CGRect(x: 0, y: 940, width: 256, height: 84))
      }
      h.addChildNode(flat(door, w: 0.48, h: 1.9, at: SCNVector3(0, 0.975, 0.232)))
      out.addChildNode(h)
    }
    // Patch above the lockers.
    let p = holder(-96.5, r: Room.radius - 0.012, y: 2.4)
    p.addChildNode(patchNode(0, size: 0.34))
    out.addChildNode(p)
  }

  // ---------------------------------------------------------------- hydroponics

  private static func hydroponics(_ out: SCNNode, _ emis: SCNNode, _ glow: SCNNode) {
    let frame = solid(PlatformColor(red: 0.62, green: 0.64, blue: 0.66, alpha: 1))
    let top = solid(PlatformColor(red: 0.20, green: 0.24, blue: 0.22, alpha: 1))
    let h = holder(-123, r: 3.62)
    for sx: CGFloat in [-0.72, 0.72] {
      for sz: CGFloat in [-0.22, 0.22] {
        h.addChildNode(box(0.05, 2.1, 0.05, frame, at: SCNVector3(sx, 1.05, sz)))
      }
    }
    for y: CGFloat in [0.72, 1.32, 1.92] {
      h.addChildNode(box(1.5, 0.04, 0.5, top, at: SCNVector3(0, y, 0), chamfer: 0.005))
    }
    // Trays and plants on the two lower shelves.
    for (k, x) in [CGFloat(-0.3), 0.3].enumerated() {
      if let t = prop("seeding_tray_01", diffuse: "seeding_tray_01_diff_1k", scale: 1.9) {
        t.position = SCNVector3(x, 0.74, 0.02)
        t.simdEulerAngles.y = Float(k) * 0.4
        h.addChildNode(t)
      }
    }
    for (k, x) in [CGFloat(-0.35), 0.4].enumerated() {
      if let t = prop("potted_plant_04", diffuse: "potted_plant_04_diff_1k", scale: 1.6) {
        t.position = SCNVector3(x, 1.34, CGFloat(k % 2) * 0.05)
        t.simdEulerAngles.y = Float(k) * 1.3
        h.addChildNode(t)
      }
    }
    // Grow lights under the two upper shelves, magenta, with glow sprites.
    let magenta = PlatformColor(red: 1.0, green: 0.37, blue: 0.82, alpha: 1)
    let bar = emissive(PlatformColor(red: 1.0, green: 0.55, blue: 0.9, alpha: 1))
    let halo = Tex.glowMaterial(magenta, strength: 0.22)
    let hh = holder(-123, r: 3.62)
    for y: CGFloat in [1.28, 1.88] {
      hh.addChildNode(box(1.3, 0.025, 0.07, bar, at: SCNVector3(0, y, 0.12)))
    }
    emis.addChildNode(hh)
    // Light pooling on the wall behind and on the shelf fronts.
    let g = holder(-123, r: Room.radius - 0.03)
    g.addChildNode(flat(halo, w: 2.6, h: 2.2, at: SCNVector3(0, 1.35, 0)))
    glow.addChildNode(g)
    for y: CGFloat in [0.9, 1.5] {
      let f = holder(-123, r: 3.62)
      let s = flat(halo, w: 1.6, h: 0.9, at: SCNVector3(0, y, 0.30))
      f.addChildNode(s)
      glow.addChildNode(f)
    }
    // Stencilled sign above the corner.
    let sign = holder(-123, r: Room.radius - 0.012, y: 2.55)
    sign.addChildNode(flat(stencil("HYDROPONICS · BAY 2", w: 640, h: 96, bg: PlatformColor(red: 0.08, green: 0.22, blue: 0.12, alpha: 1), fg: PlatformColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1)), w: 1.3, h: 0.195, at: .init(0, 0, 0)))
    out.addChildNode(sign)
    out.addChildNode(h)
  }

  /// A stencilled label plate: bold caps on a flat colour with hazard-style end caps.
  private static func stencil(_ text: String, w: CGFloat, h: CGFloat, bg: PlatformColor, fg: PlatformColor) -> SCNMaterial {
    picture(CGSize(width: w, height: h)) { c in
      c.setFillColor(bg.cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: h))
      c.setFillColor(fg.withAlphaComponent(0.85).cgColor)
      c.fill(CGRect(x: 4, y: 4, width: w - 8, height: 3))
      c.fill(CGRect(x: 4, y: h - 7, width: w - 8, height: 3))
      _ = Draw.text(text, at: CGPoint(x: 0, y: h * 0.18), size: h * 0.40, weight: .heavy, color: fg, width: w, align: .center)
    }
  }

  // ---------------------------------------------------------------- storage

  private static func storage(_ out: SCNNode) {
    let h = holder(-142, r: 3.62)
    if let rack = prop("steel_frame_shelves_01", diffuse: "steel_frame_shelves_01_diff_1k") {
      h.addChildNode(rack)
    }
    // Crates on the shelves (positions tuned by eye against the rack in the spectator view).
    for (x, y, ry) in [(CGFloat(-0.25), CGFloat(0.12), Float(0)), (0.27, 0.12, 0.2), (-0.2, 1.02, 0.1)] {
      if let c = prop("plastic_crate_02", diffuse: "plastic_crate_02_diff_1k", scale: 1.0) {
        c.position = SCNVector3(x, y, 0)
        c.simdEulerAngles.y = ry
        h.addChildNode(c)
      }
    }
    if let m = prop("medical_box", diffuse: "medical_box_diff_1k", scale: 1.0) {
      m.position = SCNVector3(0.25, 1.52, 0)
      h.addChildNode(m)
    }
    out.addChildNode(h)
    // Barrels beside the rack.
    for (deg, ry) in [(Float(-153.5), Float(0)), (Float(-157), Float(1))] {
      if let b = prop("Barrel_01", diffuse: "Barrel_01_explosive_diff_1k", scale: 0.8) {
        let bh = holder(deg, r: 3.58)
        b.simdEulerAngles.y = ry
        bh.addChildNode(b)
        out.addChildNode(bh)
      }
    }
    let sign = holder(-142, r: Room.radius - 0.012, y: 2.4)
    sign.addChildNode(flat(stencil("STORES A · DRY GOODS", w: 640, h: 96, bg: PlatformColor(red: 0.85, green: 0.62, blue: 0.12, alpha: 1), fg: PlatformColor(white: 0.08, alpha: 1)), w: 1.2, h: 0.18, at: .init(0, 0, 0)))
    out.addChildNode(sign)
  }

  // ---------------------------------------------------------------- equipment with stencilled labels

  private static func equipmentFront(_ title: String, size: CGSize, accent: PlatformColor) -> SCNMaterial {
    picture(size) { c in
      let w = size.width, h = size.height
      c.setFillColor(PlatformColor(red: 0.45, green: 0.50, blue: 0.52, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: h))
      c.setFillColor(PlatformColor(white: 0.12, alpha: 0.55).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: 6))
      c.fill(CGRect(x: 0, y: h - 6, width: w, height: 6))
      // stencil title on a dark plate
      c.setFillColor(PlatformColor(white: 0.10, alpha: 1).cgColor)
      c.fill(CGRect(x: 20, y: 24, width: w - 40, height: 74))
      _ = Draw.text(title, at: CGPoint(x: 0, y: 36), size: 46, weight: .heavy, color: accent, width: w, align: .center)
      // gauges
      for k in 0..<2 {
        let cx = w * (0.30 + CGFloat(k) * 0.40), cy: CGFloat = 190
        c.setFillColor(PlatformColor(white: 0.9, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: cx - 42, y: cy - 42, width: 84, height: 84))
        c.setStrokeColor(PlatformColor(white: 0.1, alpha: 1).cgColor)
        c.setLineWidth(5)
        c.strokeEllipse(in: CGRect(x: cx - 42, y: cy - 42, width: 84, height: 84))
        c.setStrokeColor(PlatformColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1).cgColor)
        c.setLineWidth(4)
        c.move(to: CGPoint(x: cx, y: cy)); c.addLine(to: CGPoint(x: cx + 26 * (k == 0 ? 1 : -0.6), y: cy - 24))
        c.strokePath()
      }
      // status LEDs and button row
      for k in 0..<4 {
        let col: PlatformColor = k == 3 ? Palette.amber : Palette.green
        c.setFillColor(col.cgColor)
        c.fillEllipse(in: CGRect(x: 40 + CGFloat(k) * 40, y: 290, width: 22, height: 22))
      }
      c.setFillColor(PlatformColor(white: 0.15, alpha: 1).cgColor)
      for k in 0..<3 { c.fill(CGRect(x: 40 + CGFloat(k) * 70, y: 350, width: 54, height: 30)) }
      // grille and hazard strip at the foot
      for k in 0..<6 {
        c.setFillColor(PlatformColor(white: 0.18, alpha: 1).cgColor)
        c.fill(CGRect(x: 30, y: 430 + CGFloat(k) * 16, width: w - 60, height: 7))
      }
      c.saveGState()
      c.clip(to: CGRect(x: 0, y: h - 46, width: w, height: 46))
      c.setFillColor(PlatformColor(red: 0.95, green: 0.78, blue: 0.1, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: h - 46, width: w, height: 46))
      c.setFillColor(PlatformColor(white: 0.06, alpha: 1).cgColor)
      var x: CGFloat = -60
      while x < w + 60 {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: h)); p.addLine(to: CGPoint(x: x + 22, y: h)); p.addLine(to: CGPoint(x: x + 22 + 46, y: h - 46)); p.addLine(to: CGPoint(x: x + 46, y: h - 46))
        c.addPath(p); c.fillPath()
        x += 44
      }
      c.restoreGState()
    }
  }

  private static func equipment(_ out: SCNNode, _ emis: SCNNode) {
    let steel = solid(PlatformColor(red: 0.36, green: 0.40, blue: 0.42, alpha: 1))
    // O2 SCRUBBER B
    let a = holder(146, r: 3.62)
    a.addChildNode(box(0.96, 1.7, 0.58, steel, at: SCNVector3(0, 0.85, 0), chamfer: 0.015))
    a.addChildNode(flat(equipmentFront("O2 SCRUBBER B", size: CGSize(width: 512, height: 640), accent: PlatformColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1)), w: 0.92, h: 1.65, at: SCNVector3(0, 0.85, 0.292)))
    out.addChildNode(a)
    // WATER RECYCLER: cabinet plus two tanks.
    let w = holder(-166.5, r: 3.62)
    w.addChildNode(box(0.8, 1.3, 0.55, steel, at: SCNVector3(0, 0.65, 0), chamfer: 0.015))
    w.addChildNode(flat(equipmentFront("WATER RECYCLER", size: CGSize(width: 512, height: 512), accent: PlatformColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)), w: 0.76, h: 1.26, at: SCNVector3(0, 0.65, 0.277)))
    let tank = solid(PlatformColor(red: 0.30, green: 0.46, blue: 0.62, alpha: 1))
    let tankGeo = SCNCylinder(radius: 0.2, height: 1.9); tankGeo.radialSegmentCount = 16
    let t = SCNNode(geometry: tankGeo)
    t.geometry?.materials = [tank]
    t.position = SCNVector3(0.1, 0.95, -0.2)
    w.addChildNode(t)
    out.addChildNode(w)
  }

  // ---------------------------------------------------------------- whiteboard

  private static func whiteboard(_ out: SCNNode) {
    let board = picture(CGSize(width: 1280, height: 800)) { c in
      c.setFillColor(PlatformColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
      // ghosted old marker smears
      c.setFillColor(PlatformColor(white: 0.7, alpha: 0.10).cgColor)
      for k in 0..<6 { c.fill(CGRect(x: 60 + CGFloat(k) * 190, y: 500 + CGFloat(k % 3) * 40, width: 150, height: 14)) }
      let blue = PlatformColor(red: 0.10, green: 0.25, blue: 0.70, alpha: 1)
      let red = PlatformColor(red: 0.78, green: 0.15, blue: 0.12, alpha: 1)
      let green = PlatformColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1)
      _ = Draw.text("SOL 100 PLAN", at: CGPoint(x: 40, y: 24), size: 84, weight: .heavy, color: blue, width: 800)
      c.setStrokeColor(blue.cgColor); c.setLineWidth(7)
      c.move(to: CGPoint(x: 40, y: 125)); c.addLine(to: CGPoint(x: 700, y: 131)); c.strokePath()
      let lines: [(String, PlatformColor, Bool)] = [
        ("Ice drill: core sample 7", blue, true), ("Re-seat solar string 14", blue, true),
        ("Dust storm prep (check τ)", red, false), ("Swap water filter", blue, false), ("Order O2 sensors", green, false),
      ]
      for (i, l) in lines.enumerated() {
        let y = 160 + CGFloat(i) * 92
        c.setStrokeColor(l.1.cgColor); c.setLineWidth(6)
        c.stroke(CGRect(x: 44, y: y + 8, width: 44, height: 44))
        if l.2 { c.move(to: CGPoint(x: 50, y: y + 30)); c.addLine(to: CGPoint(x: 64, y: y + 48)); c.addLine(to: CGPoint(x: 100, y: y - 6)); c.strokePath() }
        _ = Draw.text(l.0, at: CGPoint(x: 112, y: y), size: 54, weight: .semibold, color: l.1, width: 780)
        if l.2 { c.setLineWidth(5); c.move(to: CGPoint(x: 112, y: y + 32)); c.addLine(to: CGPoint(x: 620, y: y + 32)); c.strokePath() }
      }
      // little rover doodle
      c.setStrokeColor(green.cgColor); c.setLineWidth(5)
      c.stroke(CGRect(x: 880, y: 560, width: 150, height: 50))
      c.strokeEllipse(in: CGRect(x: 888, y: 600, width: 34, height: 34))
      c.strokeEllipse(in: CGRect(x: 988, y: 600, width: 34, height: 34))
      c.move(to: CGPoint(x: 955, y: 560)); c.addLine(to: CGPoint(x: 975, y: 520)); c.strokePath()
      _ = Draw.text("fictional crew, fictional sol", at: CGPoint(x: 780, y: 740), size: 28, weight: .medium, color: PlatformColor(white: 0.45, alpha: 1), width: 480, align: .right)
      // sticky notes
      let notes: [(CGRect, PlatformColor, String, CGFloat)] = [
        (CGRect(x: 860, y: 40, width: 190, height: 190), PlatformColor(red: 1.0, green: 0.90, blue: 0.35, alpha: 1), "call\nEarth?", -0.05),
        (CGRect(x: 1070, y: 90, width: 170, height: 170), PlatformColor(red: 1.0, green: 0.62, blue: 0.75, alpha: 1), "who ate the\nlast potato", 0.06),
        (CGRect(x: 880, y: 270, width: 180, height: 180), PlatformColor(red: 0.62, green: 0.90, blue: 1.0, alpha: 1), "robots:\nbe nice", 0.04),
      ]
      for n in notes {
        c.saveGState()
        c.translateBy(x: n.0.midX, y: n.0.midY)
        c.rotate(by: n.3)
        c.setShadow(offset: CGSize(width: 4, height: 6), blur: 8, color: PlatformColor(white: 0, alpha: 0.3).cgColor)
        c.setFillColor(n.1.cgColor)
        c.fill(CGRect(x: -n.0.width / 2, y: -n.0.height / 2, width: n.0.width, height: n.0.height))
        c.setShadow(offset: .zero, blur: 0)
        _ = Draw.text(n.2, at: CGPoint(x: -n.0.width / 2 + 14, y: -n.0.height / 2 + 24), size: 30, weight: .bold, color: PlatformColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1), width: n.0.width - 24, maxLines: 3)
        c.restoreGState()
      }
    }
    let h = holder(103, r: Room.radius - 0.10, y: 1.55)
    h.addChildNode(box(1.68, 1.08, 0.03, Tex.material(Tex.brushed()), at: SCNVector3(0, 0, -0.005)))
    h.addChildNode(flat(board, w: 1.6, h: 1.0, at: SCNVector3(0, 0, 0.012)))
    h.addChildNode(box(0.9, 0.03, 0.06, Tex.material(Tex.brushed()), at: SCNVector3(0, -0.56, 0.03))) // marker tray
    out.addChildNode(h)
    let p = holder(103, r: Room.radius - 0.012, y: 2.35)
    p.addChildNode(patchNode(1, size: 0.3))
    out.addChildNode(p)
  }

  // ---------------------------------------------------------------- pressure door

  private static func door(_ out: SCNNode, _ emis: SCNNode) {
    let face = picture(CGSize(width: 512, height: 1024)) { c in
      c.setFillColor(PlatformColor(red: 0.42, green: 0.45, blue: 0.47, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 512, height: 1024))
      // warning border: yellow/black diagonal stripes
      c.saveGState()
      let outer = CGRect(x: 0, y: 0, width: 512, height: 1024)
      let inner = outer.insetBy(dx: 40, dy: 40)
      c.addRect(outer); c.addRect(inner)
      c.clip(using: .evenOdd)
      c.setFillColor(PlatformColor(red: 0.96, green: 0.78, blue: 0.08, alpha: 1).cgColor)
      c.fill(outer)
      c.setFillColor(PlatformColor(white: 0.05, alpha: 1).cgColor)
      var x: CGFloat = -1100
      while x < 700 {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 30, y: 0)); p.addLine(to: CGPoint(x: x + 30 + 1100, y: 1100)); p.addLine(to: CGPoint(x: x + 1100, y: 1100))
        c.addPath(p); c.fillPath()
        x += 62
      }
      c.restoreGState()
      // porthole, wheel, label
      c.setFillColor(PlatformColor(white: 0.08, alpha: 1).cgColor)
      c.fillEllipse(in: CGRect(x: 176, y: 150, width: 160, height: 160))
      c.setFillColor(PlatformColor(red: 0.55, green: 0.32, blue: 0.22, alpha: 0.9).cgColor)
      c.fillEllipse(in: CGRect(x: 190, y: 164, width: 132, height: 132))
      c.setStrokeColor(PlatformColor(white: 0.75, alpha: 1).cgColor); c.setLineWidth(10)
      c.strokeEllipse(in: CGRect(x: 176, y: 150, width: 160, height: 160))
      c.setFillColor(PlatformColor(white: 0.1, alpha: 1).cgColor)
      c.fill(CGRect(x: 70, y: 780, width: 372, height: 130))
      _ = Draw.text("AIRLOCK B", at: CGPoint(x: 0, y: 792), size: 62, weight: .heavy, color: PlatformColor(red: 0.96, green: 0.78, blue: 0.08, alpha: 1), width: 512, align: .center)
      _ = Draw.text("PRESSURE DOOR · CYCLE FIRST", at: CGPoint(x: 70, y: 868), size: 22, weight: .bold, color: PlatformColor(white: 0.9, alpha: 1), width: 372, align: .center)
    }
    let h = holder(126, r: 3.84)
    h.addChildNode(box(1.2, 2.3, 0.14, solid(PlatformColor(white: 0.2, alpha: 1)), at: SCNVector3(0, 1.15, 0)))
    h.addChildNode(flat(face, w: 1.0, h: 2.0, at: SCNVector3(0, 1.1, 0.075)))
    // Hand wheel.
    let torus = SCNTorus(ringRadius: 0.2, pipeRadius: 0.022); torus.ringSegmentCount = 20; torus.pipeSegmentCount = 6
    let ring = SCNNode(geometry: torus)
    ring.geometry?.materials = [solid(PlatformColor(red: 0.8, green: 0.2, blue: 0.15, alpha: 1))]
    ring.eulerAngles.x = .pi / 2
    ring.position = SCNVector3(0, 1.05, 0.12)
    h.addChildNode(ring)
    for k in 0..<3 {
      let s = box(0.4, 0.03, 0.03, solid(PlatformColor(red: 0.8, green: 0.2, blue: 0.15, alpha: 1)), at: SCNVector3(0, 1.05, 0.12))
      s.simdEulerAngles.z = Float(k) * .pi / 3
      h.addChildNode(s)
    }
    out.addChildNode(h)
    // Status lamps above the door: red (sealed) and a dim green.
    let lamps = holder(126, r: 3.86)
    lamps.addChildNode(box(0.1, 0.1, 0.05, emissive(PlatformColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 1)), at: SCNVector3(-0.08, 2.45, 0.08)))
    lamps.addChildNode(box(0.1, 0.1, 0.05, emissive(PlatformColor(red: 0.2, green: 0.55, blue: 0.3, alpha: 1)), at: SCNVector3(0.08, 2.45, 0.08)))
    emis.addChildNode(lamps)
  }

  // ---------------------------------------------------------------- side table: first aid, toolbox, mug

  private static func sideTable(_ out: SCNNode) {
    let steel = solid(PlatformColor(red: 0.34, green: 0.36, blue: 0.38, alpha: 1))
    let h = holder(166, r: 3.62)
    h.addChildNode(box(1.0, 0.05, 0.5, steel, at: SCNVector3(0, 0.80, 0)))
    for sx: CGFloat in [-0.46, 0.46] { h.addChildNode(box(0.05, 0.8, 0.45, steel, at: SCNVector3(sx, 0.4, 0))) }
    if let t = prop("metal_toolbox", diffuse: "metal_toolbox_diff_1k", scale: 1.0) {
      t.position = SCNVector3(-0.3, 0.825, 0)
      h.addChildNode(t)
    }
    if let m = mug() {
      m.position = SCNVector3(0.25, 0.825, 0.05)
      m.simdEulerAngles.y = 0.6
      h.addChildNode(m)
    }
    out.addChildNode(h)
  }
}
