import ModelIO
import SceneKit
import SceneKit.ModelIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// Everything outside the window: Jezero terrain (USGS HiRISE + CTX), sky, sun, fog,
/// solar panels, the ice drill and blowing dust. One `tau` (dust opacity) drives it all,
/// the same number the power model uses.
final class Outside {
  let root = SCNNode()
  let sunNode = SCNNode()
  let ambientNode = SCNNode()
  private weak var scene: SCNScene?
  private let drillHead = SCNNode()
  private let beacon = SCNNode()
  private var lamps: [SCNNode] = []
  private let drillSign = SpritePanel(width: 22, height: 4.8, pixelsPerMeter: 51)
  private let dust = SCNParticleSystem()
  private var lastSkyKey = ""
  private var skyBusy = false
  private(set) var drillOn = true
  /// Real terrain heights (terrain frame) for placing things on the ground.
  private(set) var heights: HeightField?
  private let dustNode = SCNNode()
  private var outdoor = false
  private var lastTau: Double = 0.6
  private var lastSun: (Double, Double) = (120, 45)
  private var terrainMat: SCNMaterial?
  /// (sun direction in world space, elevation deg, beam strength 0...1), called whenever the sun or the dust changes.
  var onSun: ((SIMD3<Float>, Float, Float) -> Void)?
  private(set) var sunInfo: (SIMD3<Float>, Float, Float) = (SIMD3(0, 0.7, -0.7), 45, 0.8)
  private var baseDiffuseIntensity: CGFloat = 1
  /// World rotation that puts compass azimuth `viewAzimuth` straight ahead (-Z).
  static let viewAzimuth: Float = 305

  init(scene: SCNScene) {
    self.scene = scene
    // Terrain frame: +X east, +Y up, +Z south. Rotating about Y by -(360-305) degrees
    // turns azimuth 305 (toward the delta) into world -Z.
    root.simdEulerAngles.y = -(360 - Self.viewAzimuth) * .pi / 180
    scene.rootNode.addChildNode(root)
    loadTerrain()
    buildProps()
    buildPanels()
    buildDrill()
    buildDust()

    sunNode.light = SCNLight()
    sunNode.light?.type = .directional
    sunNode.light?.castsShadow = false
    scene.rootNode.addChildNode(sunNode)
    ambientNode.light = SCNLight()
    ambientNode.light?.type = .ambient
    scene.rootNode.addChildNode(ambientNode)
    scene.fogDensityExponent = 1.4
    apply(tau: 0.6, sunAzimuth: 120, sunElevation: 45)
  }

  // ---------------------------------------------------------------- terrain

  private func loadTerrain() {
    for name in ["far", "near"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "obj", subdirectory: "terrain") ?? Bundle.main.url(forResource: name, withExtension: "obj") else { continue }
      let asset = MDLAsset(url: url)
      guard let mesh = asset.object(at: 0) as? MDLMesh else { continue }
      let node = SCNNode(mdlObject: mesh)
      let m = SCNMaterial()
      m.lightingModel = .lambert
      let tex = Bundle.main.url(forResource: "\(name)_albedo", withExtension: "jpg", subdirectory: "terrain") ?? Bundle.main.url(forResource: "\(name)_albedo", withExtension: "jpg")
      m.diffuse.contents = tex.flatMap { PlatformImage(contentsOfFile: $0.path) } ?? PlatformColor(red: 0.6, green: 0.42, blue: 0.3, alpha: 1)
      m.diffuse.mipFilter = .linear
      m.diffuse.wrapS = .clamp
      m.diffuse.wrapT = .clamp
      m.isDoubleSided = false
      node.geometry?.materials = [m]
      node.name = "terrain-\(name)"
      root.addChildNode(node)
      if name == "near" {
        if let g = node.geometry { heights = HeightField(geometry: g) }
        terrainMat = m
        baseDiffuseIntensity = m.diffuse.intensity
      }
    }
    // The terrain only covers a wedge (az 210-390); a flat regolith plain under it keeps the ground from ending in void.
    let fill = SCNNode(geometry: SCNCylinder(radius: 3000, height: 0.02))
    let fm = SCNMaterial()
    fm.lightingModel = .lambert
    fm.diffuse.contents = PlatformColor(red: 0.50, green: 0.36, blue: 0.27, alpha: 1)
    fill.geometry?.materials = [fm]
    fill.position = SCNVector3(0, 0.1, 0)
    fill.name = "terrain-fill"
    scene?.rootNode.addChildNode(fill)
  }

  // ---------------------------------------------------------------- ground queries (world frame)

  /// World (x, z) -> terrain frame (the terrain root is only rotated about Y).
  func toTerrain(_ w: SIMD2<Float>) -> SIMD2<Float> {
    let a = -root.simdEulerAngles.y
    return SIMD2(w.x * cos(a) + w.y * sin(a), -w.x * sin(a) + w.y * cos(a))
  }

  /// Terrain height under world (x, z); nil off the mesh.
  func height(_ x: Float, _ z: Float) -> Float? {
    let t = toTerrain(SIMD2(x, z))
    return heights?.height(x: t.x, z: t.y)
  }

  func groundY(_ x: Float, _ z: Float) -> Float { height(x, z) ?? 0.4 }

  /// Near-field detail (grit multiplied into the regolith) only while the judge stands outside.
  func setDetail(_ on: Bool) {
    guard let m = terrainMat else { return }
    if on, let img = DetailTexture.image {
      m.multiply.contents = img
      m.multiply.wrapS = .repeat
      m.multiply.wrapT = .repeat
      m.multiply.mipFilter = .linear
      m.multiply.minificationFilter = .linear
      m.multiply.magnificationFilter = .linear
      m.multiply.maxAnisotropy = 8
      m.multiply.contentsTransform = SCNMatrix4MakeScale(3000, 3000, 1)
      m.diffuse.intensity = baseDiffuseIntensity / CGFloat(DetailTexture.mean)
    } else {
      m.multiply.contents = nil
      m.diffuse.intensity = baseDiffuseIntensity
    }
  }

  /// The judge is outside (ground level): grittier fog, a capped particle count, no wall-sized drill sign.
  func setOutdoor(_ on: Bool) {
    guard on != outdoor else { return }
    outdoor = on
    // Back inside: the emitter returns to its window-view spot, otherwise the grit it followed the judge with blows through the room.
    if !on { dustNode.position = SCNVector3(-10, 3, -30); dust.reset() }
    drillSign.node.isHidden = on
    setDetail(on)
    applyDust(tau: lastTau)
    reapplyFog()
  }

  /// Keeps the dust emitter around the judge (outside) so the grit blows past them, upwind of the view.
  func followJudge(_ eye: SIMD3<Float>) {
    guard outdoor else { return }
    dustNode.simdPosition = SIMD3(eye.x - 34, eye.y - 0.6, eye.z)
  }

  /// Kenney Space Kit (CC0) props: habitat domes, a landed cargo rocket, the Earth-link dish, a rover, rocks.
  /// Positions are world (x right, -z toward the delta); see `Spots` for the outdoor layout.
  private func buildProps() {
    let atBearing: [(String, Float, Float, Float, Float)] = [
      // name, azimuth, distance (m), scale, yaw (deg, terrain frame)
      ("rover", 303, 22, 8, 60),
      ("rock_largeA", 318, 10, 3, 0),
      ("rock_largeB", 289, 21, 4, 45),
    ]
    for (name, az, dist, scale, yaw) in atBearing {
      guard let n = loadProp(name) else { continue }
      n.scale = SCNVector3(scale, scale, scale)
      n.simdEulerAngles.y = yaw * .pi / 180
      n.position = ground(az: az, dist: dist, y: groundHeight(az: az, dist: dist))
      root.addChildNode(n)
    }
    let atWorld: [(String, SIMD2<Float>, Float, Float)] = [
      ("hangar_roundA", [60, -92], 5, 20),
      ("hangar_roundB", [91, -85], 5, -30),
      ("satelliteDish_large", [-9.5, -6.5], 7, 120),
      ("rocks_smallA", [3.6, -8.4], 6, 10),
      ("supports_high", [46, -50], 4, 0),
    ]
    for (name, w, scale, yaw) in atWorld {
      guard let n = loadProp(name) else { continue }
      n.scale = SCNVector3(scale, scale, scale)
      n.simdEulerAngles.y = yaw * .pi / 180
      let t = toTerrain(w)
      n.position = SCNVector3(t.x, groundY(w.x, w.y), t.y)
      root.addChildNode(n)
    }
  }

  func loadProp(_ name: String) -> SCNNode? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "obj") else { return nil }
    let asset = MDLAsset(url: url)
    asset.loadTextures()
    let n = SCNNode()
    for i in 0..<asset.count {
      let child = SCNNode(mdlObject: asset.object(at: i))
      for m in child.geometry?.materials ?? [] { m.lightingModel = .lambert }
      n.addChildNode(child)
    }
    return n.flattenedClone()
  }

  /// Terrain height under a point (terrain frame), so props sit on the real ground.
  private func groundHeight(az: Float, dist: Float) -> Float {
    let p = ground(az: az, dist: dist)
    if let h = heights?.height(x: Float(p.x), z: Float(p.z)) { return h }
    let from = root.convertPosition(SCNVector3(p.x, 2000, p.z), to: nil)
    let to = root.convertPosition(SCNVector3(p.x, -2000, p.z), to: nil)
    let hits = root.hitTestWithSegment(from: from, to: to, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
    guard let h = hits.first(where: { $0.node.name?.hasPrefix("terrain") ?? false }) else { return 0 }
    return Float(root.convertPosition(h.worldCoordinates, from: nil).y)
  }

  /// Point at compass azimuth (deg) and distance (m), in the terrain frame (+X east, +Z south).
  private func ground(az: Float, dist: Float, y: Float = 0) -> SCNVector3 {
    let a = az * .pi / 180
    return SCNVector3(sin(a) * dist, y, -cos(a) * dist)
  }

  /// Cell-gridded solar cells under a light coat of dust (code-drawn, 256 x 128).
  private static func panelTexture() -> PlatformImage {
    Bitmap.image(size: CGSize(width: 256, height: 128), scale: 1, opaque: true) { ctx in
      var rng = SplitMix(31)
      Draw.fill(ctx, CGRect(x: 0, y: 0, width: 256, height: 128), PlatformColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1))
      for r in 0..<6 {
        for c in 0..<12 {
          let tone = 0.85 + 0.15 * CGFloat(rng.unit())
          Draw.fill(ctx, CGRect(x: 6 + CGFloat(c) * 20.5, y: 6 + CGFloat(r) * 19.8, width: 19, height: 18.5), PlatformColor(red: 0.07 * tone, green: 0.10 * tone, blue: 0.22 * tone, alpha: 1))
        }
      }
      // Dust: a warm veil, heavier toward the lower edge, plus a few streaks.
      for y in 0..<128 {
        ctx.setFillColor(PlatformColor(red: 0.72, green: 0.52, blue: 0.36, alpha: 0.10 + 0.22 * CGFloat(y) / 128).cgColor)
        ctx.fill(CGRect(x: 0, y: CGFloat(y), width: 256, height: 1))
      }
      for _ in 0..<26 {
        ctx.setFillColor(PlatformColor(red: 0.75, green: 0.55, blue: 0.38, alpha: 0.10 + 0.12 * CGFloat(rng.unit())).cgColor)
        ctx.fill(CGRect(x: CGFloat(rng.unit()) * 256, y: CGFloat(rng.unit()) * 128, width: 2 + CGFloat(rng.unit()) * 5, height: 12 + CGFloat(rng.unit()) * 40))
      }
    }
  }

  /// Panel rows on legs that follow the real ground (world frame, axis-aligned: the rows run east-west).
  private func buildPanels() {
    let field = SCNNode()
    let panel = SCNBox(width: 2.0, height: 0.05, length: 1.0, chamferRadius: 0.01)
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = Self.panelTexture()
    m.diffuse.mipFilter = .linear
    m.specular.contents = PlatformColor(white: 0.45, alpha: 1)
    m.shininess = 0.35
    panel.materials = [m]
    let legMat = SCNMaterial()
    legMat.diffuse.contents = PlatformColor(white: 0.55, alpha: 1)
    let center = Spots.fieldCenter
    for row in 0..<5 {
      for col in 0..<10 {
        let x = center.x + (Float(col) - 4.5) * 2.2, z = center.y + (Float(row) - 2) * 2.6
        let gy = groundY(x, z)
        let p = SCNNode(geometry: panel)
        p.position = SCNVector3(x, gy + 1.0, z)
        p.eulerAngles.x = 0.33 // tilted toward the equator (south)
        field.addChildNode(p)
        let leg = SCNNode(geometry: SCNBox(width: 0.06, height: 0.9, length: 0.06, chamferRadius: 0))
        leg.geometry?.materials = [legMat]
        leg.position = SCNVector3(x, gy + 0.45, z)
        field.addChildNode(leg)
      }
    }
    let flat = field.flattenedClone()
    flat.name = "panels"
    scene?.rootNode.addChildNode(flat)
  }

  private func buildDrill() {
    let rig = SCNNode()
    let steel = SCNMaterial()
    steel.diffuse.contents = PlatformColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1)
    let orange = SCNMaterial()
    orange.diffuse.contents = PlatformColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 1)
    // Lattice tower: four legs + cross braces.
    let h: Float = 9
    for (dx, dz) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
      let leg = SCNNode(geometry: SCNCylinder(radius: 0.08, height: CGFloat(h)))
      leg.geometry?.materials = [orange]
      leg.position = SCNVector3(dx * 0.9, h / 2, dz * 0.9)
      rig.addChildNode(leg)
    }
    for k in 0..<6 {
      let y = Float(k) * 1.5 + 0.5
      for (a, b) in [((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))] as [((Float, Float), (Float, Float))] {
        let bar = SCNNode(geometry: SCNBox(width: 1.8, height: 0.06, length: 0.06, chamferRadius: 0))
        bar.geometry?.materials = [steel]
        bar.position = SCNVector3((a.0 + b.0) * 0.45, y, (a.1 + b.1) * 0.45)
        bar.eulerAngles.y = a.1 == b.1 ? 0 : .pi / 2
        rig.addChildNode(bar)
      }
    }
    let base = SCNNode(geometry: SCNBox(width: 3.2, height: 0.6, length: 3.2, chamferRadius: 0.1))
    base.geometry?.materials = [steel]
    base.position = SCNVector3(0, 0.3, 0)
    rig.addChildNode(base)
    let tank = SCNNode(geometry: SCNCylinder(radius: 0.9, height: 2.4))
    tank.geometry?.materials = [steel]
    tank.position = SCNVector3(2.6, 1.2, 0.4)
    rig.addChildNode(tank)
    // Drill string + rotating head.
    let shaft = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 8))
    shaft.geometry?.materials = [steel]
    shaft.position = SCNVector3(0, 4, 0)
    drillHead.addChildNode(shaft)
    let head = SCNNode(geometry: SCNCone(topRadius: 0.5, bottomRadius: 0.1, height: 0.9))
    head.geometry?.materials = [orange]
    head.position = SCNVector3(0, 0.5, 0)
    drillHead.addChildNode(head)
    let fins = SCNNode(geometry: SCNBox(width: 1.6, height: 0.12, length: 0.2, chamferRadius: 0))
    fins.geometry?.materials = [orange]
    fins.position = SCNVector3(0, 7.6, 0)
    drillHead.addChildNode(fins)
    rig.addChildNode(drillHead)
    drillHead.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2.0)), forKey: "spin")
    // Beacon (cheap glow: emissive sphere + additive halo quad).
    let bm = SCNMaterial()
    bm.lightingModel = .constant
    bm.diffuse.contents = PlatformColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
    beacon.geometry = SCNSphere(radius: 0.25)
    beacon.geometry?.materials = [bm]
    beacon.position = SCNVector3(0, h + 0.4, 0)
    beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])), forKey: "pulse")
    rig.addChildNode(beacon)
    // Work lamps up the tower: lit while the drill runs, dark when it is powered down.
    for (i, (dx, dz)) in [(-1, -1), (1, 1), (-1, 1)].enumerated() {
      let lm = SCNMaterial()
      lm.lightingModel = .constant
      lm.diffuse.contents = Self.lampOn
      let lamp = SCNNode(geometry: SCNSphere(radius: 0.22))
      lamp.geometry?.materials = [lm]
      lamp.position = SCNVector3(Float(dx) * 1.0, 3.0 + Float(i) * 2.6, Float(dz) * 1.0)
      rig.addChildNode(lamp)
      lamps.append(lamp)
    }
    let dt = toTerrain(Spots.drill)
    rig.position = SCNVector3(dt.x, groundY(Spots.drill.x, Spots.drill.y), dt.y)
    rig.name = "drill"
    root.addChildNode(rig)
    // Status sign beside the tower (toward the middle of the window: the controller robot hovers in front of the tower itself),
    // in world space, turned toward the commander's seat (yaw only).
    let rigWorld = rig.worldPosition
    let signPos = SCNVector3(rigWorld.x - 21, rigWorld.y + 5, rigWorld.z)
    drillSign.node.position = signPos
    scene?.rootNode.addChildNode(drillSign.node)
    drillSign.node.look(at: SCNVector3(0, signPos.y, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    drawSign(online: true)
  }

  private func buildDust() {
    dust.birthRate = 0
    dust.particleLifeSpan = 6
    // Fine wind-blown grit: small, faint, streaked along the wind.
    dust.particleSize = 0.05
    dust.particleSizeVariation = 0.03
    dust.stretchFactor = 0.06
    dust.particleColor = PlatformColor(red: 0.80, green: 0.58, blue: 0.40, alpha: 0.22)
    dust.particleColorVariation = SCNVector4(0, 0, 0, 0.15)
    dust.emitterShape = SCNBox(width: 60, height: 8, length: 30, chamferRadius: 0)
    dust.acceleration = SCNVector3(0, 0, 0)
    dust.particleVelocity = 14
    dust.particleVelocityVariation = 4
    dust.emittingDirection = SCNVector3(1, 0.05, 0)
    dust.spreadingAngle = 10
    dust.blendMode = .alpha
    dust.isLightingEnabled = false
    dust.particleImage = Outside.softDot()
    dustNode.position = SCNVector3(-10, 3, -30)
    dustNode.addParticleSystem(dust)
    scene?.rootNode.addChildNode(dustNode)
  }

  /// Wind-blown grit. Inside (the window view) it can reach ~8000 particles at tau 4.6; at ground level the
  /// particles are larger and fewer (at most ~1500 alive) so the storm stays cheap to draw.
  private func applyDust(tau: Double) {
    if outdoor {
      dust.particleLifeSpan = 5
      dust.particleSize = 0.14
      dust.particleSizeVariation = 0.08
      dust.stretchFactor = 0.10
      dust.particleColor = PlatformColor(red: 0.78, green: 0.56, blue: 0.38, alpha: 0.20)
      dust.birthRate = CGFloat(min(300, max(8, (tau - 0.8) * 90))) // 300/s x 5 s = 1500 alive at the peak
    } else {
      dust.particleLifeSpan = 6
      dust.particleSize = 0.05
      dust.particleSizeVariation = 0.03
      dust.stretchFactor = 0.06
      dust.particleColor = PlatformColor(red: 0.80, green: 0.58, blue: 0.40, alpha: 0.22)
      // A trickle even on clear days keeps the particle shader warm (no hitch when the storm starts).
      dust.birthRate = CGFloat(max(0.5, (tau - 1.2) * 400))
    }
  }

  static func softDot() -> PlatformImage {
    let size = CGSize(width: 32, height: 32)
    return Bitmap.image(size: size) { ctx in
      let colors = [PlatformColor.white.cgColor, PlatformColor.white.withAlphaComponent(0).cgColor] as CFArray
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
      ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }
  }

  // ---------------------------------------------------------------- state

  private static let lampOn = PlatformColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 1)
  private static let lampOff = PlatformColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)

  private func drawSign(online: Bool) {
    drillSign.update(key: online ? "on" : "off") { ctx, size in
      let accent = online ? Palette.green : Palette.red
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.94), radius: 40)
      ctx.setStrokeColor(accent.cgColor)
      ctx.setLineWidth(8)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5), cornerWidth: 36, cornerHeight: 36, transform: nil))
      ctx.strokePath()
      _ = Draw.text("ICE DRILL", at: CGPoint(x: 0, y: 24), size: 56, weight: .heavy, color: Palette.dim, width: size.width, align: .center)
      _ = Draw.text(online ? "ONLINE" : "OFFLINE", at: CGPoint(x: 0, y: 96), size: 128, weight: .heavy, color: accent, width: size.width, align: .center)
    }
  }

  /// Consequences of the commander's choices that show up out in the world.
  func show(_ consequences: Set<Consequence>) {
    setDrill(on: !consequences.contains(.iceDrillOffline))
  }

  private func setDrill(on: Bool) {
    guard on != drillOn else { return }
    drillOn = on
    drawSign(online: on)
    let bm = beacon.geometry?.firstMaterial
    if on {
      drillHead.removeAllActions()
      drillHead.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2.0)), forKey: "spin")
      bm?.diffuse.contents = PlatformColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
      beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])), forKey: "pulse")
      for l in lamps { l.geometry?.firstMaterial?.diffuse.contents = Self.lampOn }
    } else {
      // Spin down (ease out), then stand still; lights go dark.
      drillHead.removeAction(forKey: "spin")
      let down = SCNAction.rotateBy(x: 0, y: .pi * 0.8, z: 0, duration: 1.4)
      down.timingMode = .easeOut
      drillHead.runAction(down, forKey: "spin")
      beacon.removeAction(forKey: "pulse")
      beacon.opacity = 1
      bm?.diffuse.contents = Self.lampOff
      for l in lamps { l.geometry?.firstMaterial?.diffuse.contents = Self.lampOff }
    }
  }

  /// Sky colour (linear-ish sRGB) for a view direction: Mars sky is butterscotch by day,
  /// darker/redder/flatter as dust rises, with a bluish halo near a low sun.
  private static func skyColor(dir d: SIMD3<Float>, sun: SIMD3<Float>, tau: Float, sunElev: Float) -> SIMD3<Float> {
    let t = min(1, max(0, (tau - 0.4) / 4.5))
    let up = max(0, d.y)
    let zenith = mix(SIMD3<Float>(0.55, 0.42, 0.31), SIMD3<Float>(0.24, 0.14, 0.09), t: t)
    let horizon = mix(SIMD3<Float>(0.86, 0.70, 0.53), SIMD3<Float>(0.42, 0.26, 0.16), t: t)
    var c = mix(horizon, zenith, t: pow(up, 0.55))
    if d.y < 0 { c = horizon * (1 - min(1, -d.y * 2) * 0.35) }
    let cosA = max(0, simd_dot(d, sun))
    let halo = pow(cosA, 24) * (1 - t * 0.85)
    let blue = SIMD3<Float>(0.55, 0.66, 0.82)
    let lowSun = 1 - min(1, max(0, sunElev / 25))
    c = mix(c, blue, t: halo * (0.25 + 0.6 * lowSun))
    c += SIMD3<Float>(1.0, 0.92, 0.80) * pow(cosA, 600) * (1 - t) * 2.5 // the sun disc
    let day = min(1, max(0.15, (sunElev + 6) / 20))
    return simd_clamp(c * day, SIMD3(repeating: 0), SIMD3(repeating: 1))
  }

  private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> { a + (b - a) * t }

  /// Cube-map sky (background isn't fogged, so the sky stays sky while the ground hazes out).
  private func makeSky(tau: Float, sunWorld: SIMD3<Float>, sunElev: Float) -> [PlatformImage] {
    let n = 128
    // Face order SceneKit expects: +X, -X, +Y, -Y, +Z, -Z.
    let faces: [(Float, Float) -> SIMD3<Float>] = [
      { u, v in SIMD3(1, -v, -u) }, { u, v in SIMD3(-1, -v, u) },
      { u, v in SIMD3(u, 1, v) }, { u, v in SIMD3(u, -1, -v) },
      { u, v in SIMD3(u, -v, 1) }, { u, v in SIMD3(-u, -v, -1) },
    ]
    return faces.map { f in
      var px = [UInt8](repeating: 255, count: n * n * 4)
      for y in 0..<n {
        for x in 0..<n {
          let u = 2 * (Float(x) + 0.5) / Float(n) - 1
          let v = 2 * (Float(y) + 0.5) / Float(n) - 1
          let c = Self.skyColor(dir: simd_normalize(f(u, v)), sun: sunWorld, tau: tau, sunElev: sunElev)
          let i = (y * n + x) * 4
          px[i] = UInt8(c.x * 255); px[i + 1] = UInt8(c.y * 255); px[i + 2] = UInt8(c.z * 255)
        }
      }
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
      return PlatformImage(cgImage: ctx.makeImage()!)
    }
  }

  private func reapplyFog() { apply(tau: lastTau, sunAzimuth: lastSun.0, sunElevation: lastSun.1) }

  /// Applies dust opacity and the real sun position (Mars24, from the server) to sky, light and fog.
  func apply(tau rawTau: Double, sunAzimuth: Double, sunElevation: Double) {
    let tau = Float(rawTau)
    let az = Float(sunAzimuth) * .pi / 180
    let el = Float(sunElevation) * .pi / 180
    // Terrain frame -> world: the same Y rotation as the terrain root.
    let local = SIMD3<Float>(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
    let rot = simd_quatf(angle: root.simdEulerAngles.y, axis: SIMD3(0, 1, 0))
    let sunWorld = simd_normalize(rot.act(local))

    // Direct beam: Beer-Lambert through tau along the slant path.
    let transmit = exp(-tau / max(sin(el), 0.08))
    let daylight = min(1, max(0, (Float(sunElevation) + 4) / 12))
    sunNode.light?.intensity = CGFloat(1400 * transmit * daylight)
    sunInfo = (sunWorld, Float(sunElevation), min(1, transmit * daylight * 1.4))
    onSun?(sunInfo.0, sunInfo.1, sunInfo.2)
    let red = min(1, tau / 5)
    sunNode.light?.color = PlatformColor(red: 1.0, green: CGFloat(0.93 - 0.2 * red), blue: CGFloat(0.84 - 0.32 * red), alpha: 1)
    sunNode.simdPosition = sunWorld * 100
    sunNode.simdLook(at: .zero)
    ambientNode.light?.intensity = CGFloat((260 + 240 * (1 - transmit)) * max(0.25, daylight) * exp(-0.12 * tau))
    ambientNode.light?.color = PlatformColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1)

    // Fog: rim gone in a storm, faint haze on a clear day. Starts outside the room.
    lastTau = rawTau
    lastSun = (sunAzimuth, sunElevation)
    let t = min(1, max(0, (tau - 0.4) / 4.4))
    if outdoor {
      // Ground level: the storm closes the horizon in to a few hundred metres.
      scene?.fogStartDistance = CGFloat(900 * pow(1 - t, 2) + 20)
      scene?.fogEndDistance = CGFloat(9000 * pow(1 - t, 3) + 420)
    } else {
      scene?.fogStartDistance = CGFloat(3000 * pow(1 - t, 2) + 60)
      scene?.fogEndDistance = CGFloat(90_000 * pow(1 - t, 3) + 1800)
    }
    let horizon = Self.skyColor(dir: simd_normalize(SIMD3(sunWorld.x, 0.02, sunWorld.z) * -1 + SIMD3(0, 0.02, 0)), sun: sunWorld, tau: tau, sunElev: Float(sunElevation))
    scene?.fogColor = PlatformColor(red: CGFloat(horizon.x), green: CGFloat(horizon.y), blue: CGFloat(horizon.z), alpha: 1)

    applyDust(tau: rawTau)

    let key = "\(Int(tau * 10))|\(Int(sunAzimuth / 4))|\(Int(sunElevation / 2))"
    if key != lastSkyKey && !skyBusy {
      lastSkyKey = key
      skyBusy = true
      let elev = Float(sunElevation)
      // The cube map is computed off the render thread, then swapped in.
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        let faces = self.makeSky(tau: tau, sunWorld: sunWorld, sunElev: elev)
        DispatchQueue.main.async {
          self.scene?.background.contents = faces
          self.skyBusy = false
        }
      }
    }
  }
}
