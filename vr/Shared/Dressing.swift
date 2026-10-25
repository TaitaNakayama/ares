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

  // ---------------------------------------------------------------- sized text plates

  /// Minimum glyph height (em, metres) for any label in the room: the decision-card detail size
  /// (30 px at 640 px/m on the wall screens, about 0.047 m). Anything smaller is deleted, not shrunk.
  static let minEm: CGFloat = 0.045
  private static let plateScale: CGFloat = 700 // texture pixels per metre on label plates

  private static func textWidth(_ s: String, px: CGFloat) -> CGFloat {
    ceil((s as NSString).size(withAttributes: [.font: PlatformFont.systemFont(ofSize: px, weight: .heavy)]).width)
  }

  /// The one stencil style used on every sign and equipment face: heavy caps on a flat plate with hairline rules.
  /// The font shrinks to fit `rect` (never clips).
  private static func drawPlate(_ c: CGContext, _ rect: CGRect, _ text: String, size: CGFloat, bg: PlatformColor, fg: PlatformColor) {
    c.setFillColor(bg.cgColor)
    c.fill(rect)
    c.setFillColor(fg.withAlphaComponent(0.8).cgColor)
    c.fill(CGRect(x: rect.minX + 4, y: rect.minY + 3, width: rect.width - 8, height: 2))
    c.fill(CGRect(x: rect.minX + 4, y: rect.maxY - 5, width: rect.width - 8, height: 2))
    let px = min(size, (rect.width - 24) / textWidth(text, px: 1))
    let lh = PlatformFont.systemFont(ofSize: px, weight: .heavy).lineHeight
    _ = Draw.text(text, at: CGPoint(x: rect.minX, y: rect.midY - lh / 2), size: px, weight: .heavy, color: fg, width: rect.width, align: .center)
  }

  /// A wall sign whose plate is measured from its text, with padding, and pushed off the curved wall
  /// by the chord sagitta so its ends never sink into the panels.
  private static func plate(_ text: String, em: CGFloat, bg: PlatformColor, fg: PlatformColor) -> (SCNMaterial, CGFloat, CGFloat) {
    let px = em * plateScale
    let wpx = ceil(textWidth(text, px: px) + px * 1.4), hpx = ceil(px * 1.9)
    let m = picture(CGSize(width: wpx, height: hpx)) { c in drawPlate(c, CGRect(x: 0, y: 0, width: wpx, height: hpx), text, size: px, bg: bg, fg: fg) }
    return (m, wpx / plateScale, hpx / plateScale)
  }

  private static func wallSign(_ text: String, deg: Float, y: Float, em: CGFloat = 0.08, bg: PlatformColor, fg: PlatformColor) -> SCNNode {
    let (m, wm, hm) = plate(text, em: em, bg: bg, fg: fg)
    let off = Float(wm * wm / (8 * CGFloat(Room.radius))) + 0.012
    let h = holder(deg, r: Room.radius - off, y: y)
    h.addChildNode(flat(m, w: wm, h: hm, at: .init(0, 0, 0)))
    return h
  }

  // ---------------------------------------------------------------- props from the bundle

  private static var templates: [String: SCNNode] = [:]
  private static var propMats: [String: SCNMaterial] = [:]

  /// A Poly Haven .usdc prop (Z-up in the file) standing on y = 0 with its diffuse JPG; geometry is shared between clones.
  private static func prop(_ id: String, diffuse: String, scale: Float = 1, mute: CGFloat? = nil) -> SCNNode? {
    if templates[id + (mute == nil ? "" : "-m")] == nil {
      guard let url = Bundle.main.url(forResource: id + "_1k", withExtension: "usdc"),
            let scene = try? SCNScene(url: url, options: nil) else { return nil }
      let merged = scene.rootNode.flattenedClone()
      let key = diffuse + (mute == nil ? "" : "-muted")
      if propMats[key] == nil { propMats[key] = Tex.material(mute == nil ? Tex.cg(diffuse) : Tex.muted(diffuse, amount: mute!)) }
      merged.enumerateHierarchy { n, _ in n.geometry?.materials = [propMats[key]!] }
      let upright = SCNNode()
      upright.eulerAngles.x = -.pi / 2
      upright.addChildNode(merged)
      templates[id + (mute == nil ? "" : "-m")] = upright
    }
    let n = templates[id + (mute == nil ? "" : "-m")]!.clone()
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
    labBench(lit)
    door(lit, emis)
    sideTable(lit)
    floorCables(lit)
    ceilingDetail(lit)
    let decals = SCNNode()
    groundDecals(decals)

    root.addChildNode(bake(lit))
    let labLights = LabLights(holder: { deg, r in holder(deg, r: r) })
    root.addChildNode(labLights.node)
    lab = labLights
    root.addChildNode(bake(emis))
    let d = bake(decals)
    d.renderingOrder = 40
    root.addChildNode(d)
    let g = bake(glowNodes)
    g.renderingOrder = 60
    root.addChildNode(g)
  }

  /// Merges a hierarchy into one flat node per material. flattenedClone on nested holders mis-places
  /// children here, so every geometry is first re-parented flat with its world transform.
  static func bake(_ group: SCNNode) -> SCNNode {
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
        _ = Draw.text("ARES", at: CGPoint(x: 0, y: 100), size: 58, weight: .heavy, color: PlatformColor(white: 0.96, alpha: 1), width: 256, align: .center)
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
        _ = Draw.text("CREW", at: CGPoint(x: 0, y: 178), size: 50, weight: .heavy, color: PlatformColor(white: 0.96, alpha: 1), width: 256, align: .center)
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
    let body = solid(PlatformColor(red: 0.30, green: 0.32, blue: 0.33, alpha: 1))
    let names = ["T. VASQUEZ", "M. LINDQVIST"]
    let tints = [PlatformColor(red: 0.38, green: 0.47, blue: 0.47, alpha: 1), PlatformColor(red: 0.50, green: 0.40, blue: 0.36, alpha: 1)]
    for (i, deg) in [Float(141.5), Float(149.5)].enumerated() {
      let h = holder(deg, r: 3.66)
      h.addChildNode(box(0.50, 1.95, 0.46, body, at: SCNVector3(0, 0.975, 0)))
      let door = picture(CGSize(width: 256, height: 1024)) { c in
        c.setFillColor(tints[i].cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 256, height: 1024))
        c.setFillColor(PlatformColor(white: 1, alpha: 0.06).cgColor) // paint sheen, left edge
        c.fill(CGRect(x: 0, y: 0, width: 70, height: 1024))
        c.setFillColor(PlatformColor(white: 0, alpha: 0.25).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 256, height: 8))
        c.fill(CGRect(x: 0, y: 1016, width: 256, height: 8))
        for k in 0..<7 { c.fill(CGRect(x: 40, y: 50 + CGFloat(k) * 16, width: 176, height: 6)) } // vent slots
        c.setFillColor(PlatformColor(white: 0.82, alpha: 1).cgColor)
        c.fill(CGRect(x: 205, y: 470, width: 14, height: 90)) // handle
        c.setFillColor(PlatformColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1).cgColor)
        c.fill(CGRect(x: 14, y: 200, width: 228, height: 64)) // name tape
        let npx = min(30, 212 / textWidth(names[i], px: 1))
        _ = Draw.text(names[i], at: CGPoint(x: 0, y: 232 - PlatformFont.systemFont(ofSize: npx, weight: .heavy).lineHeight / 2), size: npx, weight: .heavy, color: PlatformColor(white: 0.1, alpha: 1), width: 256, align: .center)
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
    let p = holder(145.5, r: Room.radius - 0.012, y: 2.4) // above the lockers
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
    out.addChildNode(wallSign("HYDROPONICS", deg: -123, y: 2.55, bg: PlatformColor(red: 0.08, green: 0.22, blue: 0.12, alpha: 1), fg: PlatformColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1)))
    out.addChildNode(h)
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
      if let b = prop("Barrel_01", diffuse: "Barrel_01_explosive_diff_1k", scale: 0.8, mute: 0.62) {
        let bh = holder(deg, r: 3.58)
        b.simdEulerAngles.y = ry
        bh.addChildNode(b)
        out.addChildNode(bh)
      }
    }
    out.addChildNode(wallSign("STORES A", deg: -142, y: 2.4, bg: PlatformColor(red: 0.85, green: 0.62, blue: 0.12, alpha: 1), fg: PlatformColor(white: 0.08, alpha: 1)))
  }

  // ---------------------------------------------------------------- equipment with stencilled labels

  /// A gauge with depth: dark bezel, light inner ring, dial face with ticks, needle and a soft glass highlight.
  private static func dial(_ c: CGContext, _ ctr: CGPoint, r: CGFloat, needle: CGFloat) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    c.setFillColor(PlatformColor(white: 0.07, alpha: 1).cgColor)
    c.fillEllipse(in: CGRect(x: ctr.x - r - 9, y: ctr.y - r - 9, width: 2 * r + 18, height: 2 * r + 18))
    c.setStrokeColor(PlatformColor(white: 0.55, alpha: 1).cgColor)
    c.setLineWidth(3)
    c.strokeEllipse(in: CGRect(x: ctr.x - r - 6, y: ctr.y - r - 6, width: 2 * r + 12, height: 2 * r + 12))
    c.setFillColor(PlatformColor(red: 0.86, green: 0.85, blue: 0.80, alpha: 1).cgColor)
    c.fillEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: 2 * r, height: 2 * r))
    c.setStrokeColor(PlatformColor(white: 0.15, alpha: 1).cgColor)
    c.setLineWidth(2)
    for i in 0...8 {
      let a = -CGFloat.pi * 1.25 + CGFloat(i) * CGFloat.pi * 1.5 / 8
      c.move(to: CGPoint(x: ctr.x + cos(a) * r * 0.74, y: ctr.y + sin(a) * r * 0.74))
      c.addLine(to: CGPoint(x: ctr.x + cos(a) * r * 0.92, y: ctr.y + sin(a) * r * 0.92))
    }
    c.strokePath()
    let na = -CGFloat.pi / 2 + needle
    c.setStrokeColor(PlatformColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1).cgColor)
    c.setLineWidth(4)
    c.move(to: ctr); c.addLine(to: CGPoint(x: ctr.x + cos(na) * r * 0.78, y: ctr.y + sin(na) * r * 0.78)); c.strokePath()
    c.setFillColor(PlatformColor(white: 0.12, alpha: 1).cgColor)
    c.fillEllipse(in: CGRect(x: ctr.x - 5, y: ctr.y - 5, width: 10, height: 10))
    c.saveGState()
    c.addEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: 2 * r, height: 2 * r))
    c.clip()
    if let g = CGGradient(colorsSpace: cs, colors: [PlatformColor(white: 1, alpha: 0.55).cgColor, PlatformColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
      let hc = CGPoint(x: ctr.x - r * 0.35, y: ctr.y - r * 0.45)
      c.drawRadialGradient(g, startCenter: hc, startRadius: 0, endCenter: hc, endRadius: r * 0.95, options: [])
    }
    c.restoreGState()
  }

  private static func equipmentFront(_ title: String, size: CGSize, accent: PlatformColor) -> SCNMaterial {
    picture(size) { c in
      let w = size.width, h = size.height
      c.setFillColor(PlatformColor(red: 0.45, green: 0.50, blue: 0.52, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: h))
      c.setFillColor(PlatformColor(white: 0.12, alpha: 0.55).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: 6))
      c.fill(CGRect(x: 0, y: h - 6, width: w, height: 6))
      // stencil title on a dark plate
      drawPlate(c, CGRect(x: 20, y: 24, width: w - 40, height: 74), title, size: 46, bg: PlatformColor(white: 0.10, alpha: 1), fg: accent)
      // gauges: bezel ring, tick marks, needle and a glass highlight
      for k in 0..<2 {
        dial(c, CGPoint(x: w * (0.30 + CGFloat(k) * 0.40), y: 190), r: 42, needle: k == 0 ? -0.9 : 0.7)
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
    let a = holder(-102.5, r: 3.62) // beside the hydroponics corner, where Life works
    a.addChildNode(box(0.96, 1.7, 0.58, steel, at: SCNVector3(0, 0.85, 0), chamfer: 0.015))
    a.addChildNode(flat(equipmentFront("O2 SCRUBBER B", size: CGSize(width: 512, height: 640), accent: PlatformColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1)), w: 0.92, h: 1.65, at: SCNVector3(0, 0.85, 0.292)))
    out.addChildNode(a)
    // WATER RECYCLER: cabinet plus two tanks.
    let w = holder(-166.5, r: 3.62)
    w.addChildNode(box(0.8, 1.3, 0.55, steel, at: SCNVector3(0, 0.65, 0), chamfer: 0.015))
    w.addChildNode(flat(equipmentFront("WATER RECYCLER", size: CGSize(width: 512, height: 512), accent: PlatformColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)), w: 0.76, h: 1.26, at: SCNVector3(0, 0.65, 0.277)))
    let tank = solid(PlatformColor(red: 0.45, green: 0.50, blue: 0.53, alpha: 1))
    let tankGeo = SCNCylinder(radius: 0.2, height: 1.9); tankGeo.radialSegmentCount = 16
    let t = SCNNode(geometry: tankGeo)
    t.geometry?.materials = [tank]
    t.position = SCNVector3(0.1, 0.95, -0.2)
    w.addChildNode(t)
    let (nm, nw, nh) = plate("N2", em: 0.09, bg: PlatformColor(white: 0.10, alpha: 1), fg: PlatformColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1))
    w.addChildNode(flat(nm, w: nw, h: nh, at: SCNVector3(0.1, 1.6, 0.006)))
    out.addChildNode(w)
  }

  // ---------------------------------------------------------------- whiteboard

  private static func whiteboard(_ out: SCNNode) {
    // 1120 x 700 px on a 1.4 x 0.875 m board (800 px/m): every line is >= 44 px (0.055 m) tall.
    let board = picture(CGSize(width: 1120, height: 700)) { c in
      c.setFillColor(PlatformColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 1120, height: 700))
      // ghosted old marker smears
      c.setFillColor(PlatformColor(white: 0.7, alpha: 0.10).cgColor)
      for k in 0..<6 { c.fill(CGRect(x: 60 + CGFloat(k) * 170, y: 560 + CGFloat(k % 3) * 36, width: 130, height: 14)) }
      let blue = PlatformColor(red: 0.10, green: 0.25, blue: 0.70, alpha: 1)
      let green = PlatformColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1)
      _ = Draw.text("SOL 100 PLAN", at: CGPoint(x: 40, y: 24), size: 92, weight: .heavy, color: blue, width: 700)
      c.setStrokeColor(blue.cgColor); c.setLineWidth(7)
      c.move(to: CGPoint(x: 40, y: 140)); c.addLine(to: CGPoint(x: 640, y: 146)); c.strokePath()
      let lines = ["Ice drill", "Solar string", "Dust storm prep"]
      for (i, l) in lines.enumerated() {
        let y = 190 + CGFloat(i) * 130
        c.setStrokeColor((i == 0 ? green : blue).cgColor); c.setLineWidth(7)
        c.stroke(CGRect(x: 44, y: y + 10, width: 56, height: 56))
        if i == 0 { c.move(to: CGPoint(x: 52, y: y + 40)); c.addLine(to: CGPoint(x: 70, y: y + 62)); c.addLine(to: CGPoint(x: 112, y: y - 4)); c.strokePath() }
        _ = Draw.text(l, at: CGPoint(x: 126, y: y), size: 66, weight: .semibold, color: blue, width: 640)
      }
      // one big sticky note
      c.saveGState()
      c.translateBy(x: 900, y: 190)
      c.rotate(by: -0.05)
      c.setShadow(offset: CGSize(width: 4, height: 6), blur: 8, color: PlatformColor(white: 0, alpha: 0.3).cgColor)
      c.setFillColor(PlatformColor(red: 1.0, green: 0.90, blue: 0.35, alpha: 1).cgColor)
      c.fill(CGRect(x: -130, y: -130, width: 260, height: 260))
      c.setShadow(offset: .zero, blur: 0)
      _ = Draw.text("Call\nEarth?", at: CGPoint(x: -110, y: -84), size: 62, weight: .bold, color: PlatformColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1), width: 230, maxLines: 2)
      c.restoreGState()
      // little rover doodle
      c.setStrokeColor(green.cgColor); c.setLineWidth(6)
      c.stroke(CGRect(x: 800, y: 500, width: 170, height: 56))
      c.strokeEllipse(in: CGRect(x: 810, y: 548, width: 40, height: 40))
      c.strokeEllipse(in: CGRect(x: 920, y: 548, width: 40, height: 40))
      c.move(to: CGPoint(x: 885, y: 500)); c.addLine(to: CGPoint(x: 910, y: 450)); c.strokePath()
    }
    // Pushed off the curved wall by more than the chord sagitta (0.061 m at +-0.7 m) so the ends never sink in.
    let h = holder(103, r: Room.radius - 0.11, y: 2.07)
    h.addChildNode(box(1.48, 0.96, 0.03, Tex.material(Tex.brushed()), at: SCNVector3(0, 0, -0.005)))
    h.addChildNode(flat(board, w: 1.4, h: 0.875, at: SCNVector3(0, 0, 0.012)))
    h.addChildNode(box(0.9, 0.03, 0.06, Tex.material(Tex.brushed()), at: SCNVector3(0, -0.5, 0.03))) // marker tray
    out.addChildNode(h)
    let p = holder(84, r: Room.radius - 0.012, y: 2.35)
    p.addChildNode(patchNode(1, size: 0.3))
    out.addChildNode(p)
  }

  // ---------------------------------------------------------------- the lab bench (Science, +110 degrees)

  /// The lab's lamp and strip light (they go dark when the lab is paused). One per scene.
  static var lab: LabLights?

  /// A bench under the whiteboard: cabinet and worktop, a sample rack of vials, a microscope, two dishes. The lights are `LabLights`.
  private static func labBench(_ out: SCNNode) {
    let steel = solid(PlatformColor(red: 0.30, green: 0.33, blue: 0.35, alpha: 1))
    let panel = solid(PlatformColor(red: 0.24, green: 0.27, blue: 0.29, alpha: 1))
    let dark = solid(PlatformColor(white: 0.10, alpha: 1))
    let alu = Tex.material(Tex.brushed())
    let h = holder(106, r: 3.55)
    h.addChildNode(box(1.3, 0.85, 0.5, steel, at: SCNVector3(0, 0.425, 0), chamfer: 0.01))
    h.addChildNode(box(1.34, 0.045, 0.58, alu, at: SCNVector3(0, 0.8725, 0.03), chamfer: 0.006))
    for x: CGFloat in [-0.32, 0.32] {
      for y: CGFloat in [0.62, 0.22] {
        h.addChildNode(box(0.60, 0.34, 0.01, panel, at: SCNVector3(x, y, 0.255)))
        h.addChildNode(box(0.22, 0.02, 0.02, dark, at: SCNVector3(x, y + 0.12, 0.27)))
      }
    }
    // Sample rack: a tray with two rows of vials in the sample colours.
    h.addChildNode(box(0.38, 0.03, 0.15, dark, at: SCNVector3(-0.42, 0.91, 0.06)))
    let tints: [PlatformColor] = [PlatformColor(red: 0.30, green: 0.80, blue: 0.95, alpha: 1), PlatformColor(red: 1.0, green: 0.70, blue: 0.25, alpha: 1), PlatformColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1), PlatformColor(red: 0.85, green: 0.45, blue: 0.85, alpha: 1)]
    for row in 0..<2 {
      for k in 0..<4 {
        let vial = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.10))
        vial.geometry?.materials = [solid(tints[(k + row) % 4])]
        vial.position = SCNVector3(-0.55 + CGFloat(k) * 0.085, 0.975, 0.025 + CGFloat(row) * 0.07)
        h.addChildNode(vial)
        let cap = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.016))
        cap.geometry?.materials = [solid(PlatformColor(white: 0.9, alpha: 1))]
        cap.position = SCNVector3(vial.position.x, 1.03, vial.position.z)
        h.addChildNode(cap)
      }
    }
    // Microscope: base, stage, an arm, the tube leaning toward the user, the eyepiece.
    let scope = solid(PlatformColor(red: 0.80, green: 0.80, blue: 0.78, alpha: 1))
    h.addChildNode(box(0.16, 0.025, 0.24, scope, at: SCNVector3(0.0, 0.91, 0.06), chamfer: 0.006))
    h.addChildNode(box(0.11, 0.01, 0.11, dark, at: SCNVector3(0.0, 0.99, 0.10)))
    let arm = box(0.04, 0.30, 0.045, scope, at: SCNVector3(0, 1.06, -0.03), chamfer: 0.008)
    arm.simdEulerAngles.x = -0.25
    h.addChildNode(arm)
    let tube = SCNNode(geometry: SCNCylinder(radius: 0.028, height: 0.20))
    tube.geometry?.materials = [scope]
    tube.position = SCNVector3(0, 1.13, 0.045)
    tube.simdEulerAngles.x = -0.45
    h.addChildNode(tube)
    let eye = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.07))
    eye.geometry?.materials = [dark]
    eye.position = SCNVector3(0, 1.235, 0.00)
    eye.simdEulerAngles.x = -0.45
    h.addChildNode(eye)
    let obj = SCNNode(geometry: SCNCylinder(radius: 0.013, height: 0.05))
    obj.geometry?.materials = [dark]
    obj.position = SCNVector3(0, 1.03, 0.10)
    h.addChildNode(obj)
    // Two dishes.
    for x: CGFloat in [0.20, 0.30] {
      let d = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.012))
      d.geometry?.materials = [solid(PlatformColor(red: 0.75, green: 0.85, blue: 0.85, alpha: 1))]
      d.position = SCNVector3(x, 0.901, 0.15)
      h.addChildNode(d)
    }
    out.addChildNode(h)
    out.addChildNode(wallSign("LAB BENCH · SCIENCE", deg: 106, y: 2.72, em: 0.08, bg: PlatformColor(red: 0.08, green: 0.22, blue: 0.12, alpha: 1), fg: PlatformColor(red: 0.85, green: 1.0, blue: 0.85, alpha: 1)))
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
      drawPlate(c, CGRect(x: 70, y: 790, width: 372, height: 96), "AIRLOCK B", size: 62, bg: PlatformColor(white: 0.10, alpha: 1), fg: PlatformColor(red: 0.96, green: 0.78, blue: 0.08, alpha: 1))
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

  // ---------------------------------------------------------------- ceiling

  /// Ducts and pipes crossing the ceiling, channel housings around each cove tube, two access hatches. Merged by
  /// material with the rest of the dressing (a handful of draw calls); the panel grid and edge darkening live in the
  /// ceiling texture. Everything keeps clear of the ring light (r 2.2) so it still reads.
  private static func ceilingDetail(_ out: SCNNode) {
    let H = CGFloat(Room.height)
    let duct = solid(PlatformColor(red: 0.50, green: 0.49, blue: 0.46, alpha: 1))
    let flange = solid(PlatformColor(red: 0.30, green: 0.29, blue: 0.28, alpha: 1))
    let orange = solid(PlatformColor(red: 0.78, green: 0.42, blue: 0.20, alpha: 1))
    let blue = solid(PlatformColor(red: 0.30, green: 0.40, blue: 0.50, alpha: 1))
    let dark = solid(PlatformColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
    // Duct A across the room in front of the window, duct B down the right side.
    func ductRun(_ a: SCNNode, len: CGFloat, w: CGFloat, h: CGFloat) {
      a.addChildNode(box(len, h, w, duct, at: SCNVector3(0, 0, 0), chamfer: 0.015))
      var x = -len / 2 + 0.7
      while x < len / 2 - 0.3 {
        a.addChildNode(box(0.09, h + 0.05, w + 0.05, flange, at: SCNVector3(x, 0, 0)))
        a.addChildNode(box(0.04, 0.12, 0.04, dark, at: SCNVector3(x + 0.5, h / 2 + 0.06, 0)))
        x += 1.25
      }
    }
    let a = SCNNode(); a.position = SCNVector3(0, H - 0.16, -2.6)
    ductRun(a, len: 5.6, w: 0.44, h: 0.30)
    out.addChildNode(a)
    let b = SCNNode(); b.position = SCNVector3(2.85, H - 0.14, 0.2); b.simdEulerAngles.y = .pi / 2
    ductRun(b, len: 5.0, w: 0.38, h: 0.26)
    out.addChildNode(b)
    // Pipes: a pair along the left side and one crossing under duct A.
    func pipe(_ m: SCNMaterial, r: CGFloat, len: CGFloat, at p: SCNVector3, yaw: Float) {
      let holder = SCNNode()
      holder.position = p
      holder.simdEulerAngles.y = yaw
      let g = SCNCylinder(radius: r, height: len); g.radialSegmentCount = 10
      let n = SCNNode(geometry: g)
      n.geometry?.materials = [m]
      n.eulerAngles.z = SCNFloat.pi / 2
      holder.addChildNode(n)
      var t = -len / 2 + 0.6
      while t < len / 2 - 0.2 {
        let c = SCNNode(geometry: SCNCylinder(radius: r + 0.012, height: 0.05))
        c.geometry?.materials = [dark]
        c.eulerAngles.z = SCNFloat.pi / 2
        c.position = SCNVector3(t, 0, 0)
        holder.addChildNode(c)
        t += 1.1
      }
      out.addChildNode(holder)
    }
    pipe(orange, r: 0.055, len: 5.2, at: SCNVector3(-2.75, H - 0.09, 0.1), yaw: .pi / 2)
    pipe(blue, r: 0.04, len: 5.2, at: SCNVector3(-2.5, H - 0.075, 0.1), yaw: .pi / 2)
    pipe(blue, r: 0.05, len: 4.6, at: SCNVector3(0, H - 0.42, -2.0), yaw: 0)
    // Channel housings around each cove tube (rails and back plate; the tube stays visible between them).
    for k in 0..<8 {
      let deg = Float(k) * 45 + 22.5
      let h = holder(deg, r: 3.3, y: Float(H) - 0.03)
      h.addChildNode(box(1.72, 0.05, 0.03, dark, at: SCNVector3(0, 0, 0.10)))
      h.addChildNode(box(1.72, 0.05, 0.03, dark, at: SCNVector3(0, 0, -0.10)))
      h.addChildNode(box(1.72, 0.012, 0.24, flange, at: SCNVector3(0, 0.022, 0)))
      for sx: CGFloat in [-0.87, 0.87] { h.addChildNode(box(0.04, 0.06, 0.23, dark, at: SCNVector3(sx, 0, 0))) }
      out.addChildNode(h)
    }
    // Two access hatches with hazard frames.
    let hatch = picture(CGSize(width: 256, height: 256)) { c in
      c.setFillColor(PlatformColor(red: 0.34, green: 0.35, blue: 0.35, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
      c.setFillColor(PlatformColor(red: 0.90, green: 0.72, blue: 0.12, alpha: 1).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: 256, height: 20)); c.fill(CGRect(x: 0, y: 236, width: 256, height: 20))
      c.fill(CGRect(x: 0, y: 0, width: 20, height: 256)); c.fill(CGRect(x: 236, y: 0, width: 20, height: 256))
      c.setFillColor(PlatformColor(white: 0.05, alpha: 1).cgColor)
      var x: CGFloat = -256
      while x < 256 { c.fill(CGRect(x: x, y: 0, width: 10, height: 20)); c.fill(CGRect(x: x, y: 236, width: 10, height: 20)); c.fill(CGRect(x: 0, y: x + 256, width: 20, height: 10)); c.fill(CGRect(x: 236, y: x + 256, width: 20, height: 10)); x += 24 }
      c.setFillColor(PlatformColor(white: 0.22, alpha: 1).cgColor)
      c.fill(CGRect(x: 36, y: 36, width: 184, height: 184))
      c.setFillColor(PlatformColor(white: 0.6, alpha: 1).cgColor)
      c.fill(CGRect(x: 96, y: 118, width: 64, height: 20))
      for (bx, by) in [(CGFloat(46), CGFloat(46)), (200, 46), (46, 200), (200, 200)] { c.fillEllipse(in: CGRect(x: bx - 6, y: by - 6, width: 12, height: 12)) }
    }
    for (x, z, yaw) in [(CGFloat(-1.15), CGFloat(0.95), Float(0.3)), (1.25, -0.6, Float(-0.2))] {
      let g = SCNPlane(width: 0.8, height: 0.8)
      let n = SCNNode(geometry: g)
      n.geometry?.materials = [hatch]
      n.eulerAngles.x = .pi / 2
      let hh = SCNNode()
      hh.position = SCNVector3(x, H - 0.034, z)
      hh.simdEulerAngles.y = yaw
      hh.addChildNode(n)
      out.addChildNode(hh)
      let rim = box(0.86, 0.03, 0.86, dark, at: SCNVector3(x, H - 0.015, z))
      rim.simdEulerAngles.y = yaw
      out.addChildNode(rim)
    }
  }

  // ---------------------------------------------------------------- floor decals

  /// Contact-shadow blobs under every machine, locker, shelf, barrel and table, plus floor markings and scuffs.
  /// Unlit alpha decals on floor-hugging planes (no lights, no shadow maps).
  private static func groundDecals(_ out: SCNNode) {
    let blob = Tex.decalMaterial(Tex.blob())
    // (angle, radius, local x, local z, width, depth)
    let spots: [(Float, Float, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (141.5, 3.66, 0, 0.04, 0.95, 0.85), (149.5, 3.66, 0, 0.04, 0.95, 0.85), // lockers
      (106, 3.6, 0, 0.05, 1.5, 0.7), // lab bench
      (-123, 3.62, 0, 0, 2.1, 1.0),   // hydroponics
      (-142, 3.62, 0, 0, 1.7, 0.95),  // storage rack
      (-153.5, 3.58, 0, 0, 0.95, 0.95), (-157, 3.58, 0, 0, 0.95, 0.95), // barrels
      (-166.5, 3.62, 0, 0.05, 1.25, 0.95), // water recycler
      (-102.5, 3.62, 0, 0.05, 1.45, 0.95),    // O2 scrubber
      (126, 3.84, 0, 0.12, 1.7, 0.55),     // pressure door
      (166, 3.62, 0, 0, 1.5, 0.9),         // side table
    ]
    for (deg, r, x, z, w, d) in spots {
      let h = holder(deg, r: r, y: 0.008)
      let n = SCNNode(geometry: SCNPlane(width: w * 1.25 + 0.5, height: d * 1.4 + 0.55))
      n.geometry?.materials = [blob]
      n.eulerAngles.x = -.pi / 2
      n.position = SCNVector3(x, 0, z + 0.12)
      h.addChildNode(n)
      out.addChildNode(h)
    }
    // Tight contact shadows hugging each footprint (visibly darker at the base, fading ~0.15 m out).
    // (angle, radius, local x, local z, footprint width, footprint depth)
    let feet: [(Float, Float, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (141.5, 3.66, 0, 0, 0.50, 0.46), (149.5, 3.66, 0, 0, 0.50, 0.46), // lockers
      (106, 3.6, 0, 0, 1.3, 0.55), // lab bench
      (-123, 3.62, 0, 0, 1.5, 0.5),    // hydroponics
      (-142, 3.62, 0, 0, 1.25, 0.55),  // storage rack
      (-153.5, 3.58, 0, 0, 0.62, 0.62), (-157, 3.58, 0, 0, 0.62, 0.62), // barrels
      (-166.5, 3.62, 0, -0.04, 0.8, 0.65), // water recycler
      (-102.5, 3.62, 0, 0, 0.96, 0.58),       // O2 scrubber
      (126, 3.84, 0, 0.1, 1.3, 0.3),       // pressure door sill
      (166, 3.62, 0, 0, 1.0, 0.5),         // side table
    ]
    for (deg, r, x, z, fw, fd) in feet {
      let h = holder(deg, r: r, y: 0.010)
      let fade: CGFloat = 0.5
      let pw = fw + 0.06 + 2 * fade, pd = fd + 0.06 + 2 * fade
      let n = SCNNode(geometry: SCNPlane(width: pw, height: pd))
      n.geometry?.materials = [Tex.decalMaterial(Tex.contact(fx: fade / pw, fy: fade / pd))]
      n.eulerAngles.x = -.pi / 2
      n.position = SCNVector3(x, 0, z + 0.12)
      h.addChildNode(n)
      out.addChildNode(h)
    }
    // Console arc: one long soft shadow strip under the desks.
    var a: Float = -34
    while a < 34 {
      let h = holder(a + 2.5, r: 2.78, y: 0.008)
      let n = SCNNode(geometry: SCNPlane(width: 0.9, height: 0.95))
      n.geometry?.materials = [blob]
      n.eulerAngles.x = -.pi / 2
      n.position = SCNVector3(0, 0, 0.1)
      h.addChildNode(n)
      out.addChildNode(h)
      a += 6
    }
    // Markings: stand-clear line with chevrons in front of the airlock, scuffs where the crew walks.
    let line = Tex.decalMaterial(Tex.floorMarks(kind: 0))
    let scuff = Tex.decalMaterial(Tex.floorMarks(kind: 1))
    let worn = Tex.decalMaterial(Tex.floorMarks(kind: 2))
    func lay(_ m: SCNMaterial, deg: Float, r: Float, w: CGFloat, d: CGFloat, spin: Float = 0) {
      let h = holder(deg, r: r, y: 0.004)
      let n = SCNNode(geometry: SCNPlane(width: w, height: d))
      n.geometry?.materials = [m]
      n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
      let spinner = SCNNode()
      spinner.simdEulerAngles.y = spin
      spinner.addChildNode(n)
      h.addChildNode(spinner)
      out.addChildNode(h)
    }
    lay(line, deg: 126, r: 3.0, w: 1.6, d: 0.4)
    lay(line, deg: -146, r: 3.05, w: 1.5, d: 0.375, spin: 0.15)
    lay(worn, deg: 126, r: 2.4, w: 2.4, d: 2.4)
    lay(worn, deg: -123, r: 2.7, w: 2.2, d: 2.2, spin: 0.7)
    lay(worn, deg: 170, r: 2.5, w: 2.0, d: 2.0, spin: 1.5)
    lay(scuff, deg: 100, r: 2.9, w: 1.8, d: 1.8, spin: 0.4)
    lay(scuff, deg: -100, r: 2.5, w: 1.6, d: 1.6, spin: 2.0)
    lay(scuff, deg: 150, r: 2.2, w: 1.4, d: 1.4, spin: 1.1)
    lay(scuff, deg: -160, r: 2.6, w: 1.6, d: 1.6, spin: 2.8)
    lay(scuff, deg: 60, r: 3.2, w: 1.4, d: 1.4, spin: 0.9)
    lay(scuff, deg: -60, r: 3.1, w: 1.4, d: 1.4, spin: 1.9)
    // More scuffs across the central floor, and a worn ring around the commander's seat.
    lay(scuff, deg: 0, r: 1.3, w: 1.8, d: 1.8, spin: 0.3)
    lay(scuff, deg: 90, r: 1.4, w: 1.7, d: 1.7, spin: 1.3)
    lay(scuff, deg: -90, r: 1.5, w: 1.7, d: 1.7, spin: 2.4)
    lay(scuff, deg: 180, r: 1.2, w: 1.9, d: 1.9, spin: 0.8)
    lay(scuff, deg: 45, r: 2.2, w: 1.6, d: 1.6, spin: 2.2)
    lay(scuff, deg: -45, r: 2.1, w: 1.6, d: 1.6, spin: 0.6)
    lay(scuff, deg: 135, r: 2.3, w: 1.5, d: 1.5, spin: 1.7)
    lay(scuff, deg: -135, r: 2.2, w: 1.5, d: 1.5, spin: 2.9)
    lay(worn, deg: 0, r: 0.0, w: 2.2, d: 2.2, spin: 0.2)
    // Floor drain grille at the centre (a flat lit-looking decal, plus its shadow lip).
    let drainH = holder(0, r: 0, y: 0.009)
    let drainN = SCNNode(geometry: SCNPlane(width: 0.75, height: 0.75))
    drainN.geometry?.materials = [Tex.decalMaterial(Tex.drain())]
    drainN.eulerAngles.x = -.pi / 2
    drainH.addChildNode(drainN)
    out.addChildNode(drainH)
    // Worn path from the airlock to the commander's seat.
    let path = Tex.decalMaterial(Tex.pathWear())
    let a0x = Float(Room.ring(126, r: 3.35, y: 0).x), a0z = Float(Room.ring(126, r: 3.35, y: 0).z)
    let a1x: Float = 0.35, a1z: Float = 0.2
    let dx = a1x - a0x, dz = a1z - a0z
    let len = CGFloat(sqrt(dx * dx + dz * dz))
    let pn = SCNNode(geometry: SCNPlane(width: len, height: 1.1))
    pn.geometry?.materials = [path]
    pn.eulerAngles.x = -.pi / 2
    let ph = SCNNode()
    ph.position = SCNVector3(SCNFloat((a0x + a1x) / 2), 0.006, SCNFloat((a0z + a1z) / 2))
    ph.simdEulerAngles.y = atan2(-dz, dx)
    ph.addChildNode(pn)
    out.addChildNode(ph)
  }

  /// Two cable runs from the console front across the floor to the central junction hatch, with clamps.
  private static func floorCables(_ out: SCNNode) {
    let rubber = solid(PlatformColor(white: 0.06, alpha: 1))
    let blueRun = solid(PlatformColor(red: 0.13, green: 0.24, blue: 0.40, alpha: 1))
    let clamp = solid(PlatformColor(red: 0.62, green: 0.50, blue: 0.14, alpha: 1))
    let plate = solid(PlatformColor(red: 0.30, green: 0.30, blue: 0.29, alpha: 1))
    // Junction hatch just in front of the drain.
    out.addChildNode(box(0.38, 0.03, 0.30, plate, at: SCNVector3(0.55, 0.015, 0.45), chamfer: 0.01))
    out.addChildNode(box(0.22, 0.012, 0.16, clamp, at: SCNVector3(0.55, 0.034, 0.45)))
    let runs: [(Float, SCNMaterial, Float)] = [(-14, rubber, 0.55), (13, blueRun, -0.45)]
    for (deg, m, bow) in runs {
      let start = Room.ring(deg, r: 2.68, y: 0)
      let p0x = Float(start.x), p0z = Float(start.z)
      let p2x: Float = 0.55, p2z: Float = 0.45
      let mx: Float = (p0x + p2x) / 2 + bow
      let mz: Float = (p0z + p2z) / 2
      var px = p0x, pz = p0z
      let n = 14
      for i in 1...n {
        let t = Float(i) / Float(n)
        let u = 1 - t
        let x: Float = u * u * p0x + 2 * u * t * mx + t * t * p2x
        let z: Float = u * u * p0z + 2 * u * t * mz + t * t * p2z
        let dx = x - px, dz = z - pz
        let l = CGFloat(sqrt(dx * dx + dz * dz))
        let yaw = atan2(-dz, dx)
        let seg = box(l + 0.01, 0.028, 0.04, m, at: SCNVector3(SCNFloat((px + x) / 2), 0.014, SCNFloat((pz + z) / 2)))
        seg.simdEulerAngles.y = yaw
        out.addChildNode(seg)
        if i % 4 == 0 && i < n {
          let c = box(0.07, 0.04, 0.09, clamp, at: SCNVector3(SCNFloat(x), 0.016, SCNFloat(z)))
          c.simdEulerAngles.y = yaw
          out.addChildNode(c)
        }
        px = x; pz = z
      }
    }
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
