import ModelIO
import SceneKit
import SceneKit.ModelIO
import UIKit
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
  private let dust = SCNParticleSystem()
  private var lastSkyKey = ""
  private(set) var drillOn = true
  /// World rotation that puts compass azimuth `viewAzimuth` straight ahead (-Z).
  static let viewAzimuth: Float = 305

  init(scene: SCNScene) {
    self.scene = scene
    // Terrain frame: +X east, +Y up, +Z south. Rotating about Y by -(360-305) degrees
    // turns azimuth 305 (toward the delta) into world -Z.
    root.eulerAngles.y = -(360 - Self.viewAzimuth) * .pi / 180
    scene.rootNode.addChildNode(root)
    loadTerrain()
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
      m.diffuse.contents = tex.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIColor(red: 0.6, green: 0.42, blue: 0.3, alpha: 1)
      m.diffuse.mipFilter = .linear
      m.diffuse.wrapS = .clamp
      m.diffuse.wrapT = .clamp
      m.isDoubleSided = false
      node.geometry?.materials = [m]
      node.name = "terrain-\(name)"
      root.addChildNode(node)
    }
  }

  /// Point at compass azimuth (deg) and distance (m), in the terrain frame (+X east, +Z south).
  private func ground(az: Float, dist: Float, y: Float = 0) -> SCNVector3 {
    let a = az * .pi / 180
    return SCNVector3(sin(a) * dist, y, -cos(a) * dist)
  }

  private func buildPanels() {
    let field = SCNNode()
    let panel = SCNBox(width: 2.0, height: 0.05, length: 1.0, chamferRadius: 0.01)
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = UIColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1)
    m.metalness.contents = 0.7
    m.roughness.contents = 0.25
    panel.materials = [m]
    let legGeo = SCNBox(width: 0.06, height: 0.9, length: 0.06, chamferRadius: 0)
    legGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.55, alpha: 1)
    for row in 0..<5 {
      for col in 0..<10 {
        let p = SCNNode(geometry: panel)
        p.position = SCNVector3(Float(col) * 2.2, 1.0, Float(row) * 2.6)
        p.eulerAngles.x = 0.33 // tilted toward the equator (south)
        field.addChildNode(p)
        let leg = SCNNode(geometry: legGeo)
        leg.position = SCNVector3(Float(col) * 2.2, 0.45, Float(row) * 2.6)
        field.addChildNode(leg)
      }
    }
    let flat = field.flattenedClone()
    flat.position = ground(az: 282, dist: 34)
    flat.eulerAngles.y = 0.2
    flat.name = "panels"
    root.addChildNode(flat)
  }

  private func buildDrill() {
    let rig = SCNNode()
    let steel = SCNMaterial()
    steel.diffuse.contents = UIColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1)
    let orange = SCNMaterial()
    orange.diffuse.contents = UIColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 1)
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
    bm.diffuse.contents = UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
    beacon.geometry = SCNSphere(radius: 0.25)
    beacon.geometry?.materials = [bm]
    beacon.position = SCNVector3(0, h + 0.4, 0)
    beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: 0.6), .fadeOpacity(to: 1, duration: 0.6)])))
    rig.addChildNode(beacon)
    rig.position = ground(az: 322, dist: 48)
    rig.name = "drill"
    root.addChildNode(rig)
  }

  private func buildDust() {
    dust.birthRate = 0
    dust.particleLifeSpan = 6
    dust.particleSize = 0.25
    dust.particleSizeVariation = 0.2
    dust.particleColor = UIColor(red: 0.75, green: 0.52, blue: 0.34, alpha: 0.35)
    dust.particleColorVariation = SCNVector4(0, 0, 0, 0.15)
    dust.emitterShape = SCNBox(width: 60, height: 8, length: 30, chamferRadius: 0)
    dust.acceleration = SCNVector3(0, 0, 0)
    dust.particleVelocity = 6
    dust.particleVelocityVariation = 2
    dust.emittingDirection = SCNVector3(1, 0.05, 0)
    dust.spreadingAngle = 10
    dust.blendMode = .alpha
    dust.isLightingEnabled = false
    dust.particleImage = Outside.softDot()
    let n = SCNNode()
    n.position = SCNVector3(-10, 3, -30)
    n.addParticleSystem(dust)
    scene?.rootNode.addChildNode(n)
  }

  static func softDot() -> UIImage {
    let size = CGSize(width: 32, height: 32)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
      ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }
  }

  // ---------------------------------------------------------------- state

  func setDrill(on: Bool) {
    guard on != drillOn else { return }
    drillOn = on
    if on {
      drillHead.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2.0)), forKey: "spin")
      (beacon.geometry?.firstMaterial)?.diffuse.contents = UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
    } else {
      drillHead.removeAction(forKey: "spin")
      (beacon.geometry?.firstMaterial)?.diffuse.contents = UIColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 1)
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
  private func makeSky(tau: Float, sunWorld: SIMD3<Float>, sunElev: Float) -> [UIImage] {
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
      return UIImage(cgImage: ctx.makeImage()!)
    }
  }

  /// Applies dust opacity and the real sun position (Mars24, from the server) to sky, light and fog.
  func apply(tau rawTau: Double, sunAzimuth: Double, sunElevation: Double) {
    let tau = Float(rawTau)
    let az = Float(sunAzimuth) * .pi / 180
    let el = Float(sunElevation) * .pi / 180
    // Terrain frame -> world: the same Y rotation as the terrain root.
    let local = SIMD3<Float>(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
    let rot = simd_quatf(angle: root.eulerAngles.y, axis: SIMD3(0, 1, 0))
    let sunWorld = simd_normalize(rot.act(local))

    // Direct beam: Beer-Lambert through tau along the slant path.
    let transmit = exp(-tau / max(sin(el), 0.08))
    let daylight = min(1, max(0, (Float(sunElevation) + 4) / 12))
    sunNode.light?.intensity = CGFloat(1400 * transmit * daylight)
    let red = min(1, tau / 5)
    sunNode.light?.color = UIColor(red: 1.0, green: CGFloat(0.93 - 0.2 * red), blue: CGFloat(0.84 - 0.32 * red), alpha: 1)
    sunNode.simdPosition = sunWorld * 100
    sunNode.simdLook(at: .zero)
    ambientNode.light?.intensity = CGFloat((260 + 240 * (1 - transmit)) * max(0.25, daylight) * exp(-0.12 * tau))
    ambientNode.light?.color = UIColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1)

    // Fog: rim gone in a storm, faint haze on a clear day. Starts outside the room.
    let t = min(1, max(0, (tau - 0.4) / 4.4))
    scene?.fogStartDistance = CGFloat(3000 * pow(1 - t, 2) + 60)
    scene?.fogEndDistance = CGFloat(90_000 * pow(1 - t, 3) + 1800)
    let horizon = Self.skyColor(dir: simd_normalize(SIMD3(sunWorld.x, 0.02, sunWorld.z) * -1 + SIMD3(0, 0.02, 0)), sun: sunWorld, tau: tau, sunElev: Float(sunElevation))
    scene?.fogColor = UIColor(red: CGFloat(horizon.x), green: CGFloat(horizon.y), blue: CGFloat(horizon.z), alpha: 1)

    dust.birthRate = CGFloat(max(0, (tau - 1.2)) * 120)

    let key = "\(Int(tau * 10))|\(Int(sunAzimuth / 4))|\(Int(sunElevation / 2))"
    if key != lastSkyKey {
      lastSkyKey = key
      scene?.background.contents = makeSky(tau: tau, sunWorld: sunWorld, sunElev: Float(sunElevation))
    }
  }
}
