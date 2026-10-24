import SceneKit
import UIKit
import simd

/// Spike C-17 (research/spike-17-ground-level.md): the judge stands OUTSIDE on the real Jezero
/// terrain at ground level, with near-field detail (a tiled detail texture and scattered small
/// rocks). Enabled by the `--ground` launch argument, `-ground YES`, or `"ground": true` in
/// ares.json (`ARES_GROUND=1 scripts/build-ios.sh`). It cycles through configurations and reports
/// the fps of each in the `vr_stats` message. Without the flag nothing here runs.
final class GroundSpike {
  struct Config {
    let rocks: Int
    let detail: Bool
    let batched: Bool
    var hideRoom = false
    var storm = false
    var faceHab = false
    var label: String {
      "r\(rocks)-\(detail ? "detail" : "plain")-\(batched ? "batched" : "loose")" + (hideRoom ? "-noroom" : "") + (storm ? "-storm" : "") + (faceHab ? "-facehab" : "")
    }
  }

  static let configs: [Config] = [
    Config(rocks: 0, detail: false, batched: true), Config(rocks: 0, detail: true, batched: true),
    Config(rocks: 150, detail: false, batched: true), Config(rocks: 150, detail: true, batched: true),
    Config(rocks: 400, detail: false, batched: true), Config(rocks: 400, detail: true, batched: true),
    Config(rocks: 400, detail: true, batched: false),
    Config(rocks: 400, detail: true, batched: true, hideRoom: true),
    Config(rocks: 400, detail: true, batched: true, storm: true),
    Config(rocks: 400, detail: true, batched: true, hideRoom: true, storm: true),
    Config(rocks: 400, detail: true, batched: true, faceHab: true),
  ]

  static var enabled: Bool {
    let a = ProcessInfo.processInfo.arguments
    if a.contains("--ground") || UserDefaults.standard.bool(forKey: "ground") { return true }
    if let url = Bundle.main.url(forResource: "ares", withExtension: "json"), let d = try? Data(contentsOf: url),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["ground"] as? Bool == true { return true }
    return false
  }

  private let world: BaseScene
  private let node = SCNNode()
  private var terrainMat: SCNMaterial?
  private var detailImage: UIImage?
  private var baseIntensity: CGFloat = 1
  private var detailTransform = SCNMatrix4Identity
  private var sectors: [(base: SCNNode, extra: SCNNode)] = []
  private var loose = SCNNode()
  private(set) var judge = SIMD3<Float>(0, 0, 0)
  private(set) var groundY: Float = 0

  // Cycle bookkeeping.
  private let window: Double
  private let hold: Int?
  private var startedAt: Double?
  private var current = -1
  private var samples: [Double] = []
  private var lastFps = 0.0
  private var results: [String: [Double]] = [:]
  private(set) var label = "init"

  init(world: BaseScene) {
    self.world = world
    let args = ProcessInfo.processInfo.arguments
    func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    window = Double(arg("--ground-window") ?? "") ?? 70
    hold = Int(arg("--ground-hold") ?? "")
    world.scene.rootNode.addChildNode(node)
    placeJudge()
    buildRocks()
    prepareDetail()
    apply(hold ?? 0)
  }

  // ---------------------------------------------------------------- placement

  private var nearTerrain: SCNNode? { world.outside.root.childNode(withName: "terrain-near", recursively: false) }

  /// World-space terrain height under (x, z), from the near mesh.
  private func ground(x: Float, z: Float) -> Float? {
    guard let t = nearTerrain else { return nil }
    let a = t.convertPosition(SCNVector3(x, 3000, z), from: nil), b = t.convertPosition(SCNVector3(x, -3000, z), from: nil)
    guard let h = t.hitTestWithSegment(from: a, to: b, options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue]).first else { return nil }
    return Float(t.convertPosition(h.localCoordinates, to: nil).y)
  }

  private func placeJudge() {
    // 40 m from the habitat, on compass azimuth 305 (centre of the terrain wedge, which only covers az 223-387).
    // Default facing is outward (-Z: the wedge); the faceHab config turns the judge to look back at the habitat.
    let az: Float = 305 * .pi / 180
    let local = SCNVector3(sin(az) * 40, 0, -cos(az) * 40)
    let w = world.outside.root.convertPosition(local, to: nil)
    let gy = ground(x: Float(w.x), z: Float(w.z)) ?? 0
    groundY = gy
    judge = SIMD3(Float(w.x), gy + 1.6, Float(w.z))
    face(hab: false)
    print("[ground] judge at", judge, "ground", gy)
  }

  private func face(hab: Bool) {
    let yaw: Float = hab ? atan2(judge.x, judge.z) : 0 // forward = -Z (out) or toward the origin
    var t = matrix_identity_float4x4
    t.columns.3 = SIMD4(-judge.x, -judge.y, -judge.z, 1)
    world.viewOffset = simd_float4x4(simd_quatf(angle: -yaw, axis: SIMD3(0, 1, 0))) * t
  }

  /// Everything indoors: scene children other than the head, terrain/props, lights, particles and this spike's nodes.
  private func setRoomHidden(_ hidden: Bool) {
    let keep: [SCNNode] = [world.head, world.outside.root, world.outside.sunNode, world.outside.ambientNode, node]
    if hidden {
      for n in world.scene.rootNode.childNodes where !n.isHidden && !keep.contains(where: { $0 === n }) && n.particleSystems?.isEmpty != false {
        n.isHidden = true
        hiddenByUs.append(n)
      }
    } else {
      for n in hiddenByUs { n.isHidden = false }
      hiddenByUs = []
    }
  }

  // ---------------------------------------------------------------- rocks

  private func rockGeometry(seed: UInt64) -> SCNGeometry {
    var rng = SplitMix(seed)
    // Icosahedron, subdivided once (80 faces), radii jittered, squashed: a flat-shaded pebble.
    let t: Float = (1 + sqrt(5.0)) / 2
    var v: [SIMD3<Float>] = [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]].map { simd_normalize($0) }
    var f: [[Int]] = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
    var mid: [UInt64: Int] = [:]
    func m(_ a: Int, _ b: Int) -> Int {
      let k = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
      if let i = mid[k] { return i }
      v.append(simd_normalize((v[a] + v[b]) / 2)); mid[k] = v.count - 1; return v.count - 1
    }
    var f2: [[Int]] = []
    for tri in f {
      let a = m(tri[0], tri[1]), b = m(tri[1], tri[2]), c = m(tri[2], tri[0])
      f2 += [[tri[0], a, c], [tri[1], b, a], [tri[2], c, b], [a, b, c]]
    }
    f = f2
    let radii = v.map { _ in Float(0.72 + 0.4 * rng.unit()) }
    let sy = Float(0.5 + 0.25 * rng.unit()), sx = Float(0.9 + 0.3 * rng.unit())
    var pos: [SCNVector3] = [], nor: [SCNVector3] = [], col: [SIMD4<Float>] = []
    for tri in f {
      let p = tri.map { i -> SIMD3<Float> in
        var q = v[i] * radii[i]
        q.y = max(q.y * sy, -0.12)
        q.x *= sx
        return q
      }
      let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
      let shade = Float(0.78 + 0.3 * rng.unit())
      for q in p {
        pos.append(SCNVector3(q.x, q.y, q.z)); nor.append(SCNVector3(n.x, n.y, n.z)); col.append(SIMD4(shade, shade, shade, 1))
      }
    }
    let colData = col.withUnsafeBufferPointer { Data(buffer: $0) }
    let idx: [UInt32] = (0..<UInt32(pos.count)).map { $0 }
    return SCNGeometry(sources: [
      SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
      SCNGeometrySource(data: colData, semantic: .color, vectorCount: col.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16),
    ], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
  }

  private func buildRocks() {
    let mat = SCNMaterial()
    mat.lightingModel = .lambert
    mat.diffuse.contents = UIColor(red: 0.43, green: 0.30, blue: 0.22, alpha: 1)
    let variants = (0..<6).map { rockGeometry(seed: UInt64($0 + 11)) }
    for g in variants { g.materials = [mat] }
    var rng = SplitMix(2026)
    let nSectors = 8
    let baseN = (0..<nSectors).map { _ in SCNNode() }, extraN = (0..<nSectors).map { _ in SCNNode() }
    var placed = 0
    for i in 0..<400 {
      // Denser near the feet: radius 1.5 .. 25 m with a bias toward the judge.
      let r = Float(1.5 + 23.5 * pow(rng.unit(), 1.6)), a = Float(rng.unit()) * 2 * .pi
      let x = judge.x + cos(a) * r, z = judge.z + sin(a) * r
      guard let y = ground(x: x, z: z) else { continue }
      let size = Float(0.05 * exp(1.1 * rng.gauss())) * 2.4 // median ~0.12 m, a few boulders
      let s = min(max(size, 0.04), 0.9)
      let rock = SCNNode(geometry: variants[i % variants.count])
      rock.simdPosition = SIMD3(x, y - 0.02 * s, z)
      rock.simdEulerAngles = SIMD3(Float(rng.unit()) * 0.3 - 0.15, Float(rng.unit()) * 2 * .pi, Float(rng.unit()) * 0.3 - 0.15)
      rock.simdScale = SIMD3(s, s * Float(0.8 + 0.4 * rng.unit()), s * Float(0.8 + 0.4 * rng.unit()))
      // Sector by azimuth around the judge, so chunks cull when the head turns.
      let sector = min(nSectors - 1, Int((a / (2 * .pi)) * Float(nSectors)))
      (i < 150 ? baseN[sector] : extraN[sector]).addChildNode(rock)
      // The unbatched variant is a separate set of nodes sharing the same geometry.
      loose.addChildNode(rock.clone())
      placed += 1
    }
    node.addChildNode(loose)
    for s in 0..<nSectors {
      let b = baseN[s].flattenedClone(), e = extraN[s].flattenedClone()
      node.addChildNode(b)
      node.addChildNode(e)
      sectors.append((b, e))
    }
    print("[ground] rocks built:", placed)
  }

  // ---------------------------------------------------------------- detail texture

  /// Tileable 512 px grayscale noise (value-noise octaves), values 0.72..1.0.
  private func prepareDetail() {
    let n = 512
    var rng = SplitMix(7)
    func lattice(_ p: Int) -> [Float] { (0..<(p * p)).map { _ in Float(rng.unit()) } }
    let octaves: [(Int, Float, [Float])] = [(8, 0.35, lattice(8)), (16, 0.25, lattice(16)), (32, 0.2, lattice(32)), (64, 0.12, lattice(64)), (128, 0.08, lattice(128))]
    func sm(_ t: Float) -> Float { t * t * (3 - 2 * t) }
    var px = [UInt8](repeating: 255, count: n * n * 4)
    for y in 0..<n {
      for x in 0..<n {
        var v: Float = 0
        for (p, w, L) in octaves {
          let fx = Float(x) / Float(n) * Float(p), fy = Float(y) / Float(n) * Float(p)
          let x0 = Int(fx), y0 = Int(fy), tx = sm(fx - Float(x0)), ty = sm(fy - Float(y0))
          let a = L[(y0 % p) * p + x0 % p], b = L[(y0 % p) * p + (x0 + 1) % p]
          let c = L[((y0 + 1) % p) * p + x0 % p], d = L[((y0 + 1) % p) * p + (x0 + 1) % p]
          let top = a + (b - a) * tx, bot = c + (d - c) * tx
          v += w * (top + (bot - top) * ty)
        }
        let g = UInt8(255 * (0.72 + 0.28 * min(1, max(0, v))))
        let i = (y * n + x) * 4
        px[i] = g; px[i + 1] = g; px[i + 2] = g
      }
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    detailImage = px.withUnsafeMutableBytes { p in
      CGContext(data: p.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue).flatMap { $0.makeImage() }.map { UIImage(cgImage: $0) }
    }
    terrainMat = nearTerrain?.geometry?.firstMaterial
    baseIntensity = terrainMat?.diffuse.intensity ?? 1
    // One tile per ~1.2 m: the terrain UVs span ~5600 m.
    detailTransform = SCNMatrix4MakeScale(4700, 4700, 1)
  }

  // ---------------------------------------------------------------- configs

  private func apply(_ idx: Int) {
    let c = Self.configs[idx % Self.configs.count]
    current = idx % Self.configs.count
    label = c.label
    for s in sectors {
      s.base.isHidden = !(c.batched && c.rocks >= 150)
      s.extra.isHidden = !(c.batched && c.rocks >= 400)
    }
    loose.isHidden = c.batched || c.rocks == 0
    face(hab: c.faceHab)
    setRoomHidden(c.hideRoom)
    stormOn = c.storm
    world.outside.apply(tau: c.storm ? 4.6 : 0.6, sunAzimuth: 120, sunElevation: 45)
    if let m = terrainMat {
      if c.detail {
        m.multiply.contents = detailImage
        m.multiply.wrapS = .repeat
        m.multiply.wrapT = .repeat
        m.multiply.mipFilter = .linear
        m.multiply.minificationFilter = .linear
        m.multiply.magnificationFilter = .linear
        m.multiply.maxAnisotropy = 8
        m.multiply.contentsTransform = detailTransform
        m.diffuse.intensity = baseIntensity / 0.86 // the detail map averages ~0.86: keep overall brightness
      } else {
        m.multiply.contents = nil
        m.diffuse.intensity = baseIntensity
      }
    }
    samples = []
    frames = 0; over20 = 0; over33 = 0
  }

  /// Called every frame with the app's one-second fps estimate.
  func update(time: Double, fps: Double) {
    if startedAt == nil { startedAt = time }
    let el = time - startedAt!
    if hold == nil {
      let idx = Int(el / window)
      if idx != last {
        flush()
        last = idx
        apply(idx)
      }
    }
    let inWindow = hold == nil ? el.truncatingRemainder(dividingBy: window) : el
    // Skip the first 10 s of a window (shader compile / texture upload hitches); take each new one-second value once.
    if inWindow > 10 && fps != lastFps { samples.append(fps) }
    lastFps = fps
    let dt = time - prevT
    prevT = time
    if inWindow > 10 && dt < 1 { frames += 1; if dt > 0.020 { over20 += 1 }; if dt > 0.0334 { over33 += 1 } }
    // The server's state updates reset tau; hold the storm for the storm configs.
    if stormOn && Int(time) % 3 == 0 { world.outside.apply(tau: 4.6, sunAzimuth: 120, sunElevation: 45) }
  }
  private var last = 0
  private var stormOn = false
  private var hiddenByUs: [SCNNode] = []
  private var prevT = 0.0
  private var frames = 0, over20 = 0, over33 = 0

  /// [avg fps, min fps, seconds sampled, frames, frames over 20 ms, frames over 33 ms]
  private func summary() -> [Double] {
    [samples.reduce(0, +) / Double(samples.count), samples.min()!, Double(samples.count), Double(frames), Double(over20), Double(over33)]
  }

  private func flush() {
    guard samples.count >= 5 else { return }
    results[label] = summary()
  }

  var stats: [String: Any] {
    var live = results
    if samples.count >= 3 { live[label] = summary() }
    return ["ground": true, "cfg": label, "cfgIndex": current, "cfgAvgFps": live[label]?[0] ?? 0, "cfgMinFps": live[label]?[1] ?? 0, "cfgResults": live]
  }
}

struct SplitMix {
  var s: UInt64
  init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
  mutating func next() -> UInt64 {
    s = s &+ 0x9E3779B97F4A7C15
    var z = s
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func gauss() -> Double { sqrt(-2 * log(max(unit(), 1e-12))) * cos(2 * .pi * unit()) }
}
