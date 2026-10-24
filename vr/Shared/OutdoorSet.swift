import SceneKit
import QuartzCore
import ModelIO
import SceneKit.ModelIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// The outdoor set for part 1 (world frame, laid out in `Spots`): the landing pad with the cargo lander and its
/// pallets, the science outcrop, survey flags, footprints and tyre tracks, the habitat exterior with its pressure
/// door, a tunnel to a second module, and batched near-field rocks around every station.
/// Draw calls stay low: pieces are merged per material, rocks are one node per station, decals are a few meshes.
final class OutdoorSet {
  /// Everything visible only while the judge stands outside (hidden when inside; the window sees the rest).
  let outdoorOnly = SCNNode()
  /// Habitat shell, door, module, tunnel: hidden inside so the window view is clear.
  let habitat = SCNNode()
  /// Always there (lander, pad, outcrop): seen through the window too.
  let always = SCNNode()
  private(set) var rockChunks: [(spot: SIMD2<Float>, node: SCNNode)] = []
  let doorSign = SpritePanel(width: 2.9, height: 0.62, pixelsPerMeter: 330)
  private let doorMat = SCNMaterial()
  private let doorGlow = SCNNode()
  private let scanLine = SCNNode()
  private let scanCone = SCNNode()
  private weak var outside: Outside?
  private var h: (Float, Float) -> Float { { [weak self] x, z in self?.outside?.groundY(x, z) ?? 0.4 } }
  private var hOpt: (Float, Float) -> Float? { { [weak self] x, z in self?.outside?.height(x, z) } }

  init(outside: Outside, scene: SCNScene) {
    self.outside = outside
    buildPad()
    buildCargo()
    buildOutcrop()
    buildHabitat()
    buildTracks()
    buildFlags()
    buildRocks()
    for g in [outdoorOnly, habitat, always] { scene.rootNode.addChildNode(g) }
    habitat.name = "habitat"
  }

  // ---------------------------------------------------------------- helpers

  private func place(_ n: SCNNode, _ p: SIMD2<Float>, yaw: Float = 0, lift: Float = 0) {
    n.simdPosition = SIMD3(p.x, h(p.x, p.y) + lift, p.y)
    n.simdEulerAngles.y = yaw
  }

  private func mat(_ c: PlatformColor, rough: Float = 0.7, emissive: PlatformColor? = nil) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = c
    m.specular.contents = PlatformColor(white: CGFloat(0.25 * (1 - rough)), alpha: 1)
    m.shininess = 0.2
    if let e = emissive { m.emission.contents = e }
    return m
  }

  private func imageMat(_ img: PlatformImage, repeatX: Float = 1, repeatY: Float = 1, lit: Bool = true) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = lit ? .blinn : .constant
    m.diffuse.contents = img
    m.diffuse.wrapS = .repeat
    m.diffuse.wrapT = .repeat
    m.diffuse.mipFilter = .linear
    m.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(repeatX), CGFloat(repeatY), 1)
    m.specular.contents = PlatformColor(white: 0.12, alpha: 1)
    m.shininess = 0.15
    return m
  }

  private func decalMat(_ img: PlatformImage, wrap: Bool = false) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = img
    m.diffuse.mipFilter = .linear
    if wrap { m.diffuse.wrapS = .clamp; m.diffuse.wrapT = .repeat }
    m.isDoubleSided = true
    m.blendMode = .alpha
    m.writesToDepthBuffer = false
    return m
  }

  private func decal(_ g: SCNGeometry, _ m: SCNMaterial, order: Int) -> SCNNode {
    g.materials = [m]
    let n = SCNNode(geometry: g)
    n.renderingOrder = order
    return n
  }

  /// A Poly Haven rock (.usdc, Z-up) standing on y = 0, scaled to `height` metres.
  private func rockProp(_ id: String, height: Float) -> SCNNode? {
    guard let url = Bundle.main.url(forResource: id + "_1k", withExtension: "usdc"),
          let sc = try? SCNScene(url: url, options: nil) else { return nil }
    let merged = sc.rootNode.flattenedClone()
    let m = Tex.material(Tex.cg(id + "_diff_1k"))
    merged.enumerateHierarchy { n, _ in n.geometry?.materials = [m] }
    let upright = SCNNode()
    upright.eulerAngles.x = -.pi / 2
    upright.addChildNode(merged)
    let holder = SCNNode()
    holder.addChildNode(upright)
    let (lo, hi) = sc.rootNode.boundingBox // file space, Z up (children included; the flattened clone loses it)
    let hh = Float(hi.z - lo.z)
    if hh > 0.001 {
      let k = height / hh
      upright.simdScale = SIMD3(repeating: k)
      upright.simdPosition = SIMD3(0, -Float(lo.z) * k - 0.08 * height, 0) // sunk a little into the ground
    }
    return holder
  }

  // ---------------------------------------------------------------- landing pad, lander, cargo

  private static func padTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 1024, height: 1024), scale: 1, opaque: false) { ctx in
      var rng = SplitMix(5)
      let c = CGPoint(x: 512, y: 512)
      // Slab: dusty concrete-grey disc with mottling.
      ctx.setFillColor(PlatformColor(red: 0.50, green: 0.46, blue: 0.42, alpha: 0.96).cgColor)
      ctx.fillEllipse(in: CGRect(x: 40, y: 40, width: 944, height: 944))
      for _ in 0..<260 {
        let r = 20 + CGFloat(rng.unit()) * 70
        let a = CGFloat(rng.unit()) * 2 * .pi, d = CGFloat(rng.unit()) * 430
        let t = 0.40 + CGFloat(rng.unit()) * 0.2
        ctx.setFillColor(PlatformColor(red: t, green: t * 0.92, blue: t * 0.84, alpha: 0.18).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * d - r, y: c.y + sin(a) * d - r, width: r * 2, height: r * 2))
      }
      // Painted rings and the pad mark.
      let yellow = PlatformColor(red: 0.90, green: 0.70, blue: 0.20, alpha: 0.9)
      ctx.setStrokeColor(yellow.cgColor)
      ctx.setLineWidth(18)
      ctx.strokeEllipse(in: CGRect(x: 70, y: 70, width: 884, height: 884))
      ctx.setLineWidth(8)
      ctx.strokeEllipse(in: CGRect(x: 120, y: 120, width: 784, height: 784))
      // Hazard ticks on the outer ring.
      for i in 0..<48 {
        let a = CGFloat(i) / 48 * 2 * .pi
        ctx.setFillColor((i % 2 == 0 ? yellow : PlatformColor(white: 0.12, alpha: 0.85)).cgColor)
        ctx.saveGState()
        ctx.translateBy(x: c.x + cos(a) * 470, y: c.y + sin(a) * 470)
        ctx.rotate(by: a)
        ctx.fill(CGRect(x: -22, y: -7, width: 44, height: 14))
        ctx.restoreGState()
      }
      _ = Draw.text("PAD 1", at: CGPoint(x: 0, y: 150), size: 120, weight: .heavy, color: PlatformColor(red: 0.95, green: 0.95, blue: 0.9, alpha: 0.85), width: 1024, align: .center)
      _ = Draw.text("CARGO · SIMULATED", at: CGPoint(x: 0, y: 810), size: 60, weight: .bold, color: PlatformColor(red: 0.95, green: 0.95, blue: 0.9, alpha: 0.75), width: 1024, align: .center)
      // Centre cross.
      ctx.setStrokeColor(PlatformColor(red: 0.95, green: 0.95, blue: 0.9, alpha: 0.7).cgColor)
      ctx.setLineWidth(14)
      ctx.move(to: CGPoint(x: 430, y: 512)); ctx.addLine(to: CGPoint(x: 594, y: 512))
      ctx.move(to: CGPoint(x: 512, y: 430)); ctx.addLine(to: CGPoint(x: 512, y: 594))
      ctx.strokePath()
    }
  }

  private static func scorchTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 512, height: 512), scale: 1, opaque: false) { ctx in
      var rng = SplitMix(9)
      let cs = CGColorSpaceCreateDeviceRGB()
      // Radial soot, then blast streaks.
      let g = CGGradient(colorsSpace: cs, colors: [PlatformColor(red: 0.03, green: 0.025, blue: 0.02, alpha: 0.92).cgColor, PlatformColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 0.55).cgColor, PlatformColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 0).cgColor] as CFArray, locations: [0, 0.45, 1])!
      ctx.drawRadialGradient(g, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256), endRadius: 250, options: [])
      for _ in 0..<70 {
        let a = CGFloat(rng.unit()) * 2 * .pi
        let r0 = 40 + CGFloat(rng.unit()) * 80, r1 = r0 + 40 + CGFloat(rng.unit()) * 130
        ctx.setStrokeColor(PlatformColor(red: 0.04, green: 0.03, blue: 0.025, alpha: 0.10 + 0.25 * CGFloat(rng.unit())).cgColor)
        ctx.setLineWidth(2 + CGFloat(rng.unit()) * 7)
        ctx.move(to: CGPoint(x: 256 + cos(a) * r0, y: 256 + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: 256 + cos(a) * r1, y: 256 + sin(a) * r1))
        ctx.strokePath()
      }
    }
  }

  private func buildPad() {
    let l = Spots.lander
    let g = Drape.patch(center: l, half: 9.5, yaw: 0, cell: 0.6, lift: 0.07, height: hOpt)
    always.addChildNode(decal(g, decalMat(Self.padTexture()), order: 30))
    let s = Drape.patch(center: l + SIMD2(1.5, -1.0), half: 12, yaw: 0.6, cell: 0.8, lift: 0.1, height: hOpt)
    always.addChildNode(decal(s, decalMat(Self.scorchTexture()), order: 31))
    // The cargo lander (Kenney craft_cargoA, CC0), dust-dulled.
    if let lander = outside?.loadProp("craft_cargoA") {
      let k: Float = 6
      lander.simdScale = SIMD3(repeating: k)
      place(lander, l, yaw: 2.2, lift: 0.0)
      lander.enumerateHierarchy { n, _ in
        for m in n.geometry?.materials ?? [] { m.multiply.contents = PlatformColor(red: 0.88, green: 0.80, blue: 0.72, alpha: 1) }
      }
      lander.name = "lander"
      always.addChildNode(lander)
    }
    // Pad lamp posts (emissive tops: they carry the pad through the storm).
    let post = mat(PlatformColor(white: 0.35, alpha: 1))
    let lampM = mat(PlatformColor(white: 0.1, alpha: 1), emissive: PlatformColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 1))
    let posts = SCNNode()
    for i in 0..<4 {
      let a = Float(i) / 4 * 2 * .pi + 0.4
      let p = l + SIMD2(cos(a), sin(a)) * 9.2
      let pole = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 3.0))
      pole.geometry?.materials = [post]
      place(pole, p, lift: 1.5)
      posts.addChildNode(pole)
      let lamp = SCNNode(geometry: SCNBox(width: 0.5, height: 0.14, length: 0.3, chamferRadius: 0.03))
      lamp.geometry?.materials = [lampM]
      place(lamp, p, yaw: -a, lift: 3.0)
      posts.addChildNode(lamp)
    }
    always.addChildNode(Dressing.bake(posts))
  }

  private static func crateTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 256, height: 256), scale: 1, opaque: true) { ctx in
      var rng = SplitMix(21)
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 256, height: 256), PlatformColor(red: 0.30, green: 0.34, blue: 0.38, alpha: 1))
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 256, height: 22), PlatformColor(red: 0.92, green: 0.52, blue: 0.20, alpha: 1))
      Draw.fill(ctx, CGRect(x: 0, y: 234, width: 256, height: 22), PlatformColor(red: 0.92, green: 0.52, blue: 0.20, alpha: 1))
      ctx.setStrokeColor(PlatformColor(white: 0.14, alpha: 1).cgColor)
      ctx.setLineWidth(5)
      ctx.stroke(CGRect(x: 6, y: 6, width: 244, height: 244))
      ctx.move(to: CGPoint(x: 128, y: 28)); ctx.addLine(to: CGPoint(x: 128, y: 228)); ctx.strokePath()
      _ = Draw.text("ARES CARGO", at: CGPoint(x: 0, y: 44), size: 30, weight: .heavy, color: PlatformColor(white: 0.9, alpha: 1), width: 256, align: .center)
      _ = Draw.text("SIM-\(1000 + Int(rng.unit() * 8999))", at: CGPoint(x: 0, y: 86), size: 26, weight: .bold, color: PlatformColor(white: 0.8, alpha: 1), width: 256, align: .center)
      // A barcode.
      var x: CGFloat = 54
      while x < 202 {
        let w = 2 + CGFloat(rng.unit() * 5)
        ctx.setFillColor(PlatformColor(white: 0.92, alpha: 1).cgColor)
        ctx.fill(CGRect(x: x, y: 150, width: w, height: 50))
        x += w + 2 + CGFloat(rng.unit() * 4)
      }
      // Wear.
      for _ in 0..<30 {
        ctx.setFillColor(PlatformColor(red: 0.7, green: 0.5, blue: 0.35, alpha: 0.10).cgColor)
        ctx.fill(CGRect(x: CGFloat(rng.unit()) * 256, y: 160 + CGFloat(rng.unit()) * 96, width: 4 + CGFloat(rng.unit()) * 20, height: 3 + CGFloat(rng.unit()) * 10))
      }
    }
  }

  private func buildCargo() {
    let c = Spots.crates
    let group = SCNNode()
    let crate = imageMat(Self.crateTexture())
    let pallet = mat(PlatformColor(red: 0.36, green: 0.30, blue: 0.24, alpha: 1))
    // Three pallets with stacked crates, one tilted box dropped nearby.
    let layout: [(SIMD2<Float>, Float, Int)] = [(c, 0.2, 3), (c + SIMD2(1.9, 0.5), -0.25, 2), (c + SIMD2(-0.4, 1.9), 0.5, 2)]
    for (p, yaw, n) in layout {
      let base = SCNNode()
      let pal = SCNNode(geometry: SCNBox(width: 1.3, height: 0.14, length: 1.3, chamferRadius: 0.01))
      pal.geometry?.materials = [pallet]
      pal.position = SCNVector3(0, 0.07, 0)
      base.addChildNode(pal)
      for k in 0..<n {
        let b = SCNNode(geometry: SCNBox(width: 1.1, height: 0.8, length: 1.1, chamferRadius: 0.03))
        b.geometry?.materials = [crate]
        b.position = SCNVector3(0, 0.14 + 0.4 + Float(k) * 0.81, 0)
        b.simdEulerAngles.y = Float(k) * 0.12
        base.addChildNode(b)
      }
      place(base, p, yaw: yaw)
      group.addChildNode(base)
    }
    let tipped = SCNNode(geometry: SCNBox(width: 0.9, height: 0.7, length: 0.9, chamferRadius: 0.03))
    tipped.geometry?.materials = [crate]
    place(tipped, c + SIMD2(3.4, 1.9), yaw: 0.9, lift: 0.3)
    tipped.simdEulerAngles.z = 0.12
    group.addChildNode(tipped)
    if let barrels = outside?.loadProp("barrels") {
      for (i, off) in [SIMD2<Float>(-2.4, -0.6), SIMD2(-2.9, 0.9), SIMD2(-1.9, 2.2)].enumerated() {
        let b = barrels.clone()
        b.simdScale = SIMD3(repeating: 2.6)
        place(b, c + off, yaw: Float(i) * 1.1)
        group.addChildNode(b)
      }
    }
    if let gen = outside?.loadProp("machine_generator") {
      gen.simdScale = SIMD3(repeating: 2.4)
      place(gen, c + SIMD2(4.6, -1.8), yaw: 2.6)
      group.addChildNode(gen)
    }
    always.addChildNode(Dressing.bake(group))
    // Scan beam: the Cargo Keeper sweeps the stack. A pulsing amber cone from its hover point and a line rising and falling on the crates.
    let from = SIMD3(Spots.cargoKeeper.x, groundY(Spots.cargoKeeper) + 1.15, Spots.cargoKeeper.y)
    let to = SIMD3(c.x, groundY(c) + 0.9, c.y)
    let aim = SCNNode()
    aim.simdPosition = (from + to) / 2
    aim.look(at: SCNVector3(to), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    let dist = simd_distance(from, to)
    let cone = SCNCone(topRadius: 0.01, bottomRadius: 0.55, height: CGFloat(dist))
    let bm = SCNMaterial()
    bm.lightingModel = .constant
    bm.diffuse.contents = PlatformColor(red: 0.20, green: 0.13, blue: 0.04, alpha: 1)
    bm.blendMode = .add
    bm.writesToDepthBuffer = false
    bm.isDoubleSided = true
    cone.materials = [bm]
    scanCone.geometry = cone
    scanCone.simdEulerAngles.x = .pi / 2
    aim.addChildNode(scanCone)
    scanCone.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])))
    aim.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.09, z: 0, duration: 1.3), .rotateBy(x: 0, y: -0.18, z: 0, duration: 2.6), .rotateBy(x: 0, y: 0.09, z: 0, duration: 1.3)])))
    outdoorOnly.addChildNode(aim)
    let line = SCNPlane(width: 3.4, height: 0.05)
    let lm = bm.copy() as! SCNMaterial
    lm.diffuse.contents = PlatformColor(red: 0.8, green: 0.5, blue: 0.12, alpha: 1)
    line.materials = [lm]
    scanLine.geometry = line
    scanLine.simdPosition = SIMD3(c.x, groundY(c) + 0.3, c.y)
    scanLine.look(at: SCNVector3(from), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    scanLine.renderingOrder = 50
    scanLine.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 1.5, z: 0, duration: 1.4), .moveBy(x: 0, y: -1.5, z: 0, duration: 1.4)])))
    outdoorOnly.addChildNode(scanLine)
  }

  private func groundY(_ p: SIMD2<Float>) -> Float { h(p.x, p.y) }

  // ---------------------------------------------------------------- science outcrop, flags

  private func buildOutcrop() {
    let c = Spots.outcrop
    let group = SCNNode()
    let pieces: [(String, SIMD2<Float>, Float, Float)] = [
      ("moon_rock_02", c, 1.6, 0.4), ("moon_rock_02", c + SIMD2(-1.3, -0.5), 1.0, 2.0), ("moon_rock_04", c + SIMD2(1.2, -1.2), 1.3, 3.6),
      ("moon_rock_02", c + SIMD2(0.6, 1.6), 0.7, 5.0),
    ]
    for (id, p, hgt, yaw) in pieces {
      guard let r = rockProp(id, height: hgt) else { continue }
      place(r, p, yaw: yaw)
      group.addChildNode(r)
    }
    always.addChildNode(Dressing.bake(group))
    // The sampling spot: a dark abraded patch on the ground by the rock, and a yellow sample flag.
    let patch = Drape.patch(center: Spots.scientist + SIMD2(-0.7, -0.5), half: 0.7, yaw: 0.4, cell: 0.2, lift: 0.04, height: hOpt)
    let pm = SCNMaterial()
    pm.lightingModel = .constant
    pm.diffuse.contents = Bitmap.image(size: CGSize(width: 64, height: 64), scale: 1, opaque: false) { ctx in
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [PlatformColor(red: 0.22, green: 0.13, blue: 0.09, alpha: 0.9).cgColor, PlatformColor(red: 0.22, green: 0.13, blue: 0.09, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
      ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }
    pm.blendMode = .alpha
    pm.writesToDepthBuffer = false
    patch.materials = [pm]
    let pn = SCNNode(geometry: patch)
    pn.renderingOrder = 32
    outdoorOnly.addChildNode(pn)
    outdoorOnly.addChildNode(flag(at: Spots.scientist + SIMD2(0.9, -1.3), color: PlatformColor(red: 1.0, green: 0.85, blue: 0.15, alpha: 1), height: 1.0))
  }

  private func flag(at p: SIMD2<Float>, color: PlatformColor, height: Float) -> SCNNode {
    let n = SCNNode()
    let pole = SCNNode(geometry: SCNCylinder(radius: 0.012, height: CGFloat(height)))
    pole.geometry?.materials = [mat(PlatformColor(white: 0.85, alpha: 1))]
    pole.position = SCNVector3(0, height / 2, 0)
    n.addChildNode(pole)
    let cloth = SCNPlane(width: 0.32, height: 0.2)
    let m = mat(color, emissive: color.withAlphaComponent(0.25))
    m.isDoubleSided = true
    cloth.materials = [m]
    let c = SCNNode(geometry: cloth)
    c.position = SCNVector3(0.16, height - 0.12, 0)
    n.addChildNode(c)
    n.simdPosition = SIMD3(p.x, groundY(p), p.y)
    n.simdEulerAngles.y = Float(abs(p.x * 7 + p.y * 3).truncatingRemainder(dividingBy: 6))
    return n
  }

  private func buildFlags() {
    let orange = PlatformColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1)
    let pts: [SIMD2<Float>] = [[8, -48], [12, -39], [6, -41], [-6, -31], [-4, -25], [-3, -15], [3, -14], [-6, -12], [5, -22], [-17, -28], [-9, -34], [18, -40], [24, -43], [30, -48], [33, -62], [20, -62]]
    let group = SCNNode()
    for p in pts { group.addChildNode(flag(at: p, color: orange, height: 1.05)) }
    outdoorOnly.addChildNode(Dressing.bake(group))
  }

  // ---------------------------------------------------------------- footprints and tyre tracks

  private static func footTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 128, height: 256), scale: 1, opaque: false) { ctx in
      func boot(_ x: CGFloat, _ y: CGFloat) {
        ctx.setFillColor(PlatformColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: x - 11, y: y - 30, width: 22, height: 14))
        ctx.fillEllipse(in: CGRect(x: x - 12, y: y - 24, width: 24, height: 58))
        ctx.setFillColor(PlatformColor(red: 0.62, green: 0.44, blue: 0.30, alpha: 0.35).cgColor)
        for k in 0..<5 { ctx.fill(CGRect(x: x - 9, y: y - 20 + CGFloat(k) * 10, width: 18, height: 3)) }
      }
      boot(34, 70)
      boot(94, 198)
    }
  }

  private static func tyreTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 128, height: 128), scale: 1, opaque: false) { ctx in
      for x in [CGFloat(20), 98] {
        ctx.setFillColor(PlatformColor(red: 0.18, green: 0.11, blue: 0.08, alpha: 0.5).cgColor)
        ctx.fill(CGRect(x: x - 14, y: 0, width: 28, height: 128))
        ctx.setFillColor(PlatformColor(red: 0.55, green: 0.38, blue: 0.27, alpha: 0.5).cgColor)
        for k in 0..<10 { ctx.fill(CGRect(x: x - 14, y: CGFloat(k) * 13 + 3, width: 28, height: 4)) }
      }
    }
  }

  private func buildTracks() {
    let path: [SIMD2<Float>] = [Spots.start.pos, Spots.pad.pos, Spots.science.pos, Spots.solar.pos, Spots.door.pos, Spots.doorStep.pos]
    // Two sets of prints a little apart so the crew's trail is not one ruler-straight line.
    for (k, off) in [Float(0.35), -0.4].enumerated() {
      let pts = path.enumerated().map { i, p -> SIMD2<Float> in
        let jitter = Float(sin(Double(i) * 1.7 + Double(k))) * 0.5
        return p + SIMD2(off + jitter, 0)
      }
      let g = Drape.ribbon(points: pts, width: 1.0, vPerMeter: 1 / 1.45, lift: 0.045, height: hOpt)
      outdoorOnly.addChildNode(decal(g, decalMat(Self.footTexture(), wrap: true), order: 33))
    }
    // Rover tyre tracks from the pad area to the parked rover.
    let rover: [SIMD2<Float>] = [[36, -76], [28, -60], [14, -45], [6, -33], [0.5, -25], [-0.8, -22.8]]
    let g = Drape.ribbon(points: rover, width: 1.35, vPerMeter: 1 / 1.0, lift: 0.05, height: hOpt)
    outdoorOnly.addChildNode(decal(g, decalMat(Self.tyreTexture(), wrap: true), order: 34))
  }

  // ---------------------------------------------------------------- rocks

  private func buildRocks() {
    let spots: [SIMD2<Float>] = [Spots.pad.pos, Spots.science.pos, Spots.solar.pos, Spots.door.pos]
    let avoid: (SIMD2<Float>) -> Bool = { p in
      if simd_length(p) < 5.8 { return true }                                        // the habitat
      if simd_distance(p, Spots.moduleCenter) < 4.4 { return true }                   // the second module and tunnel
      if abs(p.y - Spots.moduleCenter.y) < 1.4 && p.x > 3 && p.x < 9 { return true }
      if simd_distance(p, Spots.lander) < 10.5 { return true }                        // the pad
      if simd_distance(p, Spots.crates) < 4.5 { return true }
      if simd_distance(p, Spots.outcrop) < 2.6 || simd_distance(p, Spots.scientist) < 1.6 { return true }
      if simd_distance(p, Spots.fieldCenter) < 0 { return true }
      for s in [Spots.start.pos, Spots.pad.pos, Spots.science.pos, Spots.solar.pos, Spots.door.pos] where simd_distance(p, s) < 1.1 { return true }
      return false
    }
    for (i, s) in spots.enumerated() {
      let node = RockField.chunk(center: s, count: 140, radius: 15, seed: UInt64(100 + i), height: hOpt, avoid: avoid)
      outdoorOnly.addChildNode(node)
      rockChunks.append((s, node))
    }
  }

  // ---------------------------------------------------------------- habitat exterior

  private static func shellTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 1024, height: 512), scale: 1, opaque: true) { ctx in
      var rng = SplitMix(77)
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 1024, height: 512), PlatformColor(red: 0.80, green: 0.77, blue: 0.72, alpha: 1))
      // Panels: 4 columns x 2 rows, each a touch different.
      for r in 0..<2 {
        for c in 0..<4 {
          let t = 0.94 + 0.08 * CGFloat(rng.unit())
          Draw.fill(ctx, CGRect(x: CGFloat(c) * 256 + 3, y: CGFloat(r) * 256 + 3, width: 250, height: 250), PlatformColor(red: 0.80 * t, green: 0.77 * t, blue: 0.72 * t, alpha: 1))
          // Rivets.
          ctx.setFillColor(PlatformColor(white: 0.45, alpha: 0.7).cgColor)
          for k in 0..<12 {
            let x = CGFloat(c) * 256 + 14 + CGFloat(k) * 20
            ctx.fillEllipse(in: CGRect(x: x, y: CGFloat(r) * 256 + 12, width: 4, height: 4))
            ctx.fillEllipse(in: CGRect(x: x, y: CGFloat(r) * 256 + 240, width: 4, height: 4))
          }
        }
      }
      ctx.setStrokeColor(PlatformColor(white: 0.30, alpha: 0.8).cgColor)
      ctx.setLineWidth(3)
      for c in 0...4 { ctx.move(to: CGPoint(x: CGFloat(c) * 256, y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(c) * 256, y: 512)) }
      for r in 0...2 { ctx.move(to: CGPoint(x: 0, y: CGFloat(r) * 256)); ctx.addLine(to: CGPoint(x: 1024, y: CGFloat(r) * 256)) }
      ctx.strokePath()
      // An orange service stripe, scuffs, and regolith dust climbing the lower wall.
      Draw.fill(ctx, CGRect(x: 0, y: 372, width: 1024, height: 14), PlatformColor(red: 0.85, green: 0.45, blue: 0.20, alpha: 1))
      for _ in 0..<60 {
        ctx.setFillColor(PlatformColor(red: 0.35, green: 0.30, blue: 0.26, alpha: 0.06 + 0.10 * CGFloat(rng.unit())).cgColor)
        ctx.fill(CGRect(x: CGFloat(rng.unit()) * 1024, y: CGFloat(rng.unit()) * 400, width: 3 + CGFloat(rng.unit()) * 8, height: 20 + CGFloat(rng.unit()) * 80))
      }
      for y in 0..<512 {
        let a = 0.55 * pow(CGFloat(y) / 512, 2.2)
        ctx.setFillColor(PlatformColor(red: 0.60, green: 0.42, blue: 0.29, alpha: a).cgColor)
        ctx.fill(CGRect(x: 0, y: CGFloat(y), width: 1024, height: 1))
      }
    }
  }

  private static func doorTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 512, height: 768), scale: 1, opaque: true) { ctx in
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 512, height: 768), PlatformColor(red: 0.30, green: 0.32, blue: 0.35, alpha: 1))
      // Hazard stripe frame.
      let yellow = PlatformColor(red: 0.95, green: 0.72, blue: 0.12, alpha: 1)
      ctx.saveGState()
      ctx.clip(to: [CGRect(x: 0, y: 0, width: 512, height: 40), CGRect(x: 0, y: 728, width: 512, height: 40), CGRect(x: 0, y: 0, width: 40, height: 768), CGRect(x: 472, y: 0, width: 40, height: 768)])
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 512, height: 768), PlatformColor(white: 0.1, alpha: 1))
      ctx.setFillColor(yellow.cgColor)
      var x: CGFloat = -800
      while x < 1300 {
        ctx.move(to: CGPoint(x: x, y: 768)); ctx.addLine(to: CGPoint(x: x + 40, y: 768)); ctx.addLine(to: CGPoint(x: x + 40 + 768, y: 0)); ctx.addLine(to: CGPoint(x: x + 768, y: 0)); ctx.fillPath()
        x += 80
      }
      ctx.restoreGState()
      // Door leaf, seam, porthole, wheel.
      Draw.fill(ctx, CGRect(x: 60, y: 60, width: 392, height: 648), PlatformColor(red: 0.58, green: 0.60, blue: 0.62, alpha: 1), radius: 14)
      ctx.setStrokeColor(PlatformColor(white: 0.2, alpha: 1).cgColor)
      ctx.setLineWidth(6)
      ctx.move(to: CGPoint(x: 256, y: 64)); ctx.addLine(to: CGPoint(x: 256, y: 704)); ctx.strokePath()
      let glass = CGRect(x: 168, y: 130, width: 176, height: 176)
      Draw.fill(ctx, glass.insetBy(dx: -12, dy: -12), PlatformColor(white: 0.25, alpha: 1), radius: 100)
      ctx.setFillColor(PlatformColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1).cgColor)
      ctx.fillEllipse(in: glass)
      ctx.setFillColor(PlatformColor(red: 0.85, green: 0.6, blue: 0.4, alpha: 0.35).cgColor)
      ctx.fillEllipse(in: CGRect(x: 190, y: 148, width: 70, height: 40))
      ctx.setStrokeColor(PlatformColor(white: 0.2, alpha: 1).cgColor)
      ctx.setLineWidth(14)
      ctx.strokeEllipse(in: CGRect(x: 196, y: 440, width: 120, height: 120))
      for k in 0..<3 { let a = CGFloat(k) * .pi / 3; ctx.move(to: CGPoint(x: 256 + cos(a) * 60, y: 500 + sin(a) * 60)); ctx.addLine(to: CGPoint(x: 256 - cos(a) * 60, y: 500 - sin(a) * 60)) }
      ctx.strokePath()
      _ = Draw.text("AIRLOCK 1", at: CGPoint(x: 0, y: 620), size: 54, weight: .heavy, color: PlatformColor(white: 0.12, alpha: 1), width: 512, align: .center)
      _ = Draw.text("PRESSURE DOOR", at: CGPoint(x: 0, y: 672), size: 30, weight: .bold, color: PlatformColor(white: 0.2, alpha: 1), width: 512, align: .center)
    }
  }

  private func buildHabitat() {
    let shellMat = imageMat(Self.shellTexture(), repeatX: 6, repeatY: 1)
    let roofMat = mat(PlatformColor(red: 0.62, green: 0.60, blue: 0.57, alpha: 1), rough: 0.8)
    let steel = mat(PlatformColor(white: 0.40, alpha: 1), rough: 0.5)
    let dark = mat(PlatformColor(white: 0.12, alpha: 1))
    let glow = mat(PlatformColor(white: 0.1, alpha: 1), emissive: PlatformColor(red: 1.0, green: 0.74, blue: 0.40, alpha: 1))
    let group = SCNNode()
    let gy = (outside?.groundY(0, -4.3) ?? 0.4) - 0.3
    let r = Spots.habRadius
    // Main shell: a drum with a roof deck and parapet. One-sided, so the room's interior is untouched.
    let drum = SCNCylinder(radius: CGFloat(r), height: 3.7)
    drum.radialSegmentCount = 40
    drum.materials = [shellMat, roofMat, roofMat]
    let drumN = SCNNode(geometry: drum)
    drumN.position = SCNVector3(0, gy + 1.55, 0)
    group.addChildNode(drumN)
    let parapet = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(r), pipeRadius: 0.14))
    parapet.geometry?.materials = [steel]
    parapet.position = SCNVector3(0, gy + 3.4, 0)
    group.addChildNode(parapet)
    // Windows glowing warm: the shelter.
    for deg in [-52, -34, -17, 17, 34, 52, 130, 160, -130, -160] as [Float] {
      let a = deg * .pi / 180
      let w = SCNNode(geometry: SCNBox(width: 1.1, height: 0.5, length: 0.08, chamferRadius: 0.04))
      w.geometry?.materials = [glow]
      w.position = SCNVector3(sin(a) * (r + 0.02), gy + 2.1, -cos(a) * (r + 0.02))
      w.simdEulerAngles.y = -a
      group.addChildNode(w)
      let frame = SCNNode(geometry: SCNBox(width: 1.3, height: 0.7, length: 0.06, chamferRadius: 0.04))
      frame.geometry?.materials = [dark]
      frame.position = SCNVector3(sin(a) * (r + 0.01), gy + 2.1, -cos(a) * (r + 0.01))
      frame.simdEulerAngles.y = -a
      group.addChildNode(frame)
    }
    // Roof gear: vents, a mast with a beacon, a small dish.
    for (x, z) in [(1.5, 0.8), (-1.8, 1.4), (0.4, 2.0)] as [(Float, Float)] {
      let v = SCNNode(geometry: SCNBox(width: 0.8, height: 0.35, length: 0.6, chamferRadius: 0.05))
      v.geometry?.materials = [steel]
      v.position = SCNVector3(x, gy + 3.55, z)
      group.addChildNode(v)
    }
    let mast = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 2.6))
    mast.geometry?.materials = [steel]
    mast.position = SCNVector3(-1.2, gy + 4.6, -0.8)
    group.addChildNode(mast)
    let beaconMat = mat(PlatformColor(white: 0.1, alpha: 1), emissive: PlatformColor(red: 1.0, green: 0.2, blue: 0.15, alpha: 1))
    let beacon = SCNNode(geometry: SCNSphere(radius: 0.1))
    beacon.geometry?.materials = [beaconMat]
    beacon.position = SCNVector3(-1.2, gy + 5.95, -0.8)
    beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.15, duration: 0.8), .wait(duration: 0.8), .fadeOpacity(to: 1, duration: 0.2), .wait(duration: 0.6)])))
    habitat.addChildNode(beacon)
    // Pressure door: a vestibule box on the front with the door in its face, lit, with a doorstep.
    let vest = SCNNode(geometry: SCNBox(width: 3.0, height: 3.0, length: 1.5, chamferRadius: 0.08))
    vest.geometry?.materials = [imageMat(Self.shellTexture(), repeatX: 1.2, repeatY: 1)]
    vest.position = SCNVector3(0, gy + 1.5, -4.4)
    habitat.addChildNode(vest)
    doorMat.lightingModel = .constant
    doorMat.diffuse.contents = Self.doorTexture()
    doorMat.diffuse.mipFilter = .linear
    doorMat.emission.contents = PlatformColor.black
    let doorPlane = SCNPlane(width: 1.7, height: 2.55)
    doorPlane.materials = [doorMat]
    let door = SCNNode(geometry: doorPlane)
    door.position = SCNVector3(0, gy + 1.38, Spots.doorFaceZ + 0.02)
    door.simdEulerAngles.y = .pi
    door.name = "pressure-door"
    habitat.addChildNode(door)
    let step = SCNNode(geometry: SCNBox(width: 3.2, height: 0.22, length: 1.1, chamferRadius: 0.03))
    step.geometry?.materials = [mat(PlatformColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1))]
    step.position = SCNVector3(0, gy + 0.11, Spots.doorFaceZ - 0.35)
    group.addChildNode(step)
    for sx in [Float(-1.15), 1.15] {
      let lamp = SCNNode(geometry: SCNBox(width: 0.3, height: 0.14, length: 0.14, chamferRadius: 0.03))
      lamp.geometry?.materials = [glow]
      lamp.position = SCNVector3(sx, gy + 2.85, Spots.doorFaceZ - 0.08)
      group.addChildNode(lamp)
    }
    // Hover highlight: an amber additive halo around the door.
    let halo = SCNPlane(width: 2.5, height: 3.3)
    let hm = SCNMaterial()
    hm.lightingModel = .constant
    hm.blendMode = .add
    hm.writesToDepthBuffer = false
    hm.diffuse.contents = Tex.glow(PlatformColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1))
    halo.materials = [hm]
    doorGlow.geometry = halo
    doorGlow.position = SCNVector3(0, gy + 1.38, Spots.doorFaceZ - 0.06)
    doorGlow.simdEulerAngles.y = .pi
    doorGlow.opacity = 0
    doorGlow.renderingOrder = 60
    habitat.addChildNode(doorGlow)
    // The prompt above the door.
    doorSign.node.position = SCNVector3(0, gy + 3.85, Spots.doorFaceZ - 0.3)
    doorSign.node.simdEulerAngles.y = .pi
    doorSign.node.opacity = 0
    drawDoorSign(armed: false)
    habitat.addChildNode(doorSign.node)

    // Second module, joined by a tunnel.
    let m2 = Spots.moduleCenter
    let module = SCNCylinder(radius: 3.0, height: 3.1)
    module.radialSegmentCount = 36
    module.materials = [imageMat(Self.shellTexture(), repeatX: 4, repeatY: 1), roofMat, roofMat]
    let moduleN = SCNNode(geometry: module)
    moduleN.simdPosition = SIMD3(m2.x, (outside?.groundY(m2.x, m2.y) ?? 0.4) + 1.2, m2.y)
    group.addChildNode(moduleN)
    let tunnel = SCNCylinder(radius: 0.95, height: CGFloat(m2.x - r + 0.6))
    tunnel.materials = [imageMat(Self.shellTexture(), repeatX: 1, repeatY: 1), roofMat, roofMat]
    let tn = SCNNode(geometry: tunnel)
    tn.simdPosition = SIMD3((m2.x + r) / 2 - 0.3, (outside?.groundY(7, m2.y) ?? 0.4) + 0.9, m2.y)
    tn.eulerAngles.z = .pi / 2
    group.addChildNode(tn)
    for (dx, dz) in [(Float(-1.6), Float(-2.55)), (1.6, -2.55)] {
      let w = SCNNode(geometry: SCNBox(width: 0.9, height: 0.4, length: 0.06, chamferRadius: 0.03))
      w.geometry?.materials = [glow]
      w.simdPosition = SIMD3(m2.x + dx, (outside?.groundY(m2.x, m2.y) ?? 0.4) + 1.9, m2.y + dz)
      w.simdEulerAngles.y = dx < 0 ? 0.55 : -0.55
      group.addChildNode(w)
    }
    habitat.addChildNode(Dressing.bake(group))
  }

  func drawDoorSign(armed: Bool) {
    doorSign.update(key: armed ? "armed" : "idle") { ctx, size in
      let accent = Palette.amber
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.94), radius: 36)
      ctx.setStrokeColor(accent.cgColor)
      ctx.setLineWidth(7)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4), cornerWidth: 32, cornerHeight: 32, transform: nil))
      ctx.strokePath()
      _ = Draw.text("ENTER THE BASE", at: CGPoint(x: 0, y: 26), size: 100, weight: .heavy, color: accent, width: size.width, align: .center)
      _ = Draw.text("Look at the door and press the button", at: CGPoint(x: 0, y: 144), size: 46, weight: .bold, color: Palette.text, width: size.width, align: .center)
    }
  }

  // ---------------------------------------------------------------- per frame

  /// Door state: `armed` = the door is the station and in reach (prompt shown), `hovered` = the reticle is on it.
  func setDoor(armed: Bool, hovered: Bool) {
    let want: CGFloat = armed ? 1 : 0
    if doorSign.node.opacity != want { doorSign.node.opacity += (want - doorSign.node.opacity) * 0.15 }
    doorGlow.opacity = hovered ? 0.5 : (armed ? 0.10 + 0.06 * CGFloat(sin(CACurrentMediaTime() * 3)) : 0)
    doorMat.emission.contents = hovered ? PlatformColor(red: 0.35, green: 0.2, blue: 0.05, alpha: 1) : PlatformColor.black
  }

  /// Rock chunks are only drawn near the judge.
  func updateRocks(eye: SIMD3<Float>) {
    for (spot, node) in rockChunks { node.isHidden = simd_distance(SIMD2(eye.x, eye.z), spot) > 42 }
  }
}
