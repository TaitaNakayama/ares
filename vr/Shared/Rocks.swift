import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// Small deterministic generator (the same scatter on the headset and the Mac spectator).
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

/// Near-field rocks: flat-shaded 80-triangle pebbles (6 variants), merged per station into ONE node
/// (one draw call). Batching is the measured-safe way (spike C-17: loose nodes would cost ~1 draw per rock).
enum RockField {
  private static let variants: [SCNGeometry] = {
    let mat = SCNMaterial()
    mat.lightingModel = .lambert
    mat.diffuse.contents = PlatformColor(red: 0.43, green: 0.30, blue: 0.22, alpha: 1)
    return (0..<6).map { i in
      let g = geometry(seed: UInt64(i + 11))
      g.materials = [mat]
      return g
    }
  }()

  /// Icosahedron, subdivided once (80 faces), radii jittered, squashed.
  static func geometry(seed: UInt64) -> SCNGeometry {
    var rng = SplitMix(seed)
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

  /// `count` rocks within `radius` m of `center` (world x, z), resting on the terrain (sunk 2% of their size),
  /// denser near the centre. `avoid` rejects spots (the habitat, the pad, the walkway).
  static func chunk(center: SIMD2<Float>, count: Int, radius: Float, seed: UInt64, height: (Float, Float) -> Float?, avoid: (SIMD2<Float>) -> Bool) -> SCNNode {
    var rng = SplitMix(seed)
    let holder = SCNNode()
    var placed = 0, tries = 0
    while placed < count && tries < count * 6 {
      tries += 1
      let r = 1.2 + (radius - 1.2) * Float(pow(rng.unit(), 1.5)), a = Float(rng.unit()) * 2 * .pi
      let p = SIMD2(center.x + cos(a) * r, center.y + sin(a) * r)
      guard !avoid(p), let y = height(p.x, p.y) else { continue }
      let size = Float(0.05 * exp(1.1 * rng.gauss())) * 2.4
      let s = min(max(size, 0.04), 0.9)
      let rock = SCNNode(geometry: variants[placed % variants.count])
      rock.simdPosition = SIMD3(p.x, y - 0.02 * s, p.y)
      rock.simdEulerAngles = SIMD3(Float(rng.unit()) * 0.3 - 0.15, Float(rng.unit()) * 2 * .pi, Float(rng.unit()) * 0.3 - 0.15)
      rock.simdScale = SIMD3(s, s * Float(0.8 + 0.4 * rng.unit()), s * Float(0.8 + 0.4 * rng.unit()))
      holder.addChildNode(rock)
      placed += 1
    }
    let merged = holder.flattenedClone()
    merged.name = "rocks"
    return merged
  }
}

/// Tileable grayscale grit for the near terrain's `multiply` channel (mean about 0.86), one tile per ~1.2 m.
enum DetailTexture {
  static let image: PlatformImage? = {
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
    return px.withUnsafeMutableBytes { p in
      CGContext(data: p.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue).flatMap { $0.makeImage() }.map { PlatformImage(cgImage: $0) }
    }
  }()
}

/// Meshes draped on the terrain (scorch, pad markings, footprints, tyre tracks): the grid follows the
/// real height field, lifted a few cm so it never z-fights with the ground.
enum Drape {
  /// A square patch `half` m each side, rotated by `yaw` about Y, UV 0..1.
  static func patch(center: SIMD2<Float>, half: Float, yaw: Float, cell: Float, lift: Float, height: (Float, Float) -> Float?) -> SCNGeometry {
    let n = max(2, Int((2 * half / cell).rounded()))
    var pos: [SCNVector3] = [], nor: [SCNVector3] = [], uv: [CGPoint] = []
    let c = cos(yaw), s = sin(yaw)
    for j in 0...n {
      for i in 0...n {
        let u = Float(i) / Float(n), v = Float(j) / Float(n)
        let lx = (u - 0.5) * 2 * half, lz = (v - 0.5) * 2 * half
        let x = center.x + lx * c + lz * s, z = center.y - lx * s + lz * c
        let y = (height(x, z) ?? 0) + lift
        pos.append(SCNVector3(x, y, z)); nor.append(SCNVector3(0, 1, 0)); uv.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
      }
    }
    var idx: [UInt32] = []
    for j in 0..<n {
      for i in 0..<n {
        let a = UInt32(j * (n + 1) + i), b = a + 1, d = a + UInt32(n + 1), e = d + 1
        idx += [a, d, b, b, d, e]
      }
    }
    return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
  }

  /// A strip along a polyline (world x, z), `width` m wide, V running along the path at `vPerMeter`.
  static func ribbon(points: [SIMD2<Float>], width: Float, vPerMeter: Float, lift: Float, step: Float = 0.7, height: (Float, Float) -> Float?) -> SCNGeometry {
    // Resample at `step` metres.
    var pts: [SIMD2<Float>] = []
    for k in 0..<(points.count - 1) {
      let a = points[k], b = points[k + 1]
      let len = simd_distance(a, b)
      let m = max(1, Int(len / step))
      for i in 0..<m { pts.append(a + (b - a) * (Float(i) / Float(m))) }
    }
    pts.append(points[points.count - 1])
    var pos: [SCNVector3] = [], nor: [SCNVector3] = [], uv: [CGPoint] = []
    var dist: Float = 0
    for (i, p) in pts.enumerated() {
      let prev = pts[max(0, i - 1)], next = pts[min(pts.count - 1, i + 1)]
      var d = next - prev
      d = simd_length(d) > 1e-4 ? simd_normalize(d) : SIMD2(0, 1)
      let side = SIMD2<Float>(-d.y, d.x) * (width / 2)
      if i > 0 { dist += simd_distance(p, pts[i - 1]) }
      for (k, sgn) in [Float(-1), 1].enumerated() {
        let q = p + side * sgn
        pos.append(SCNVector3(q.x, (height(q.x, q.y) ?? 0) + lift, q.y)); nor.append(SCNVector3(0, 1, 0))
        uv.append(CGPoint(x: CGFloat(k), y: CGFloat(dist * vPerMeter)))
      }
    }
    var idx: [UInt32] = []
    for i in 0..<(pts.count - 1) {
      let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
      idx += [a, c, b, b, c, d]
    }
    return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
  }
}

/// Terrain height under any (x, z), looked up in triangle cells built once from the near mesh (the terrain frame).
final class HeightField {
  private var cells: [Int64: [Int32]] = [:]
  private var verts: [SIMD3<Float>] = []
  private var tris: [SIMD3<Int32>] = []
  private let cellSize: Float = 4

  private func key(_ cx: Int, _ cz: Int) -> Int64 { Int64(cx) << 32 | Int64(UInt32(truncatingIfNeeded: cz)) }

  /// Triangles with all vertices within `limit` m of the origin only (the stations are within ~100 m).
  init?(geometry: SCNGeometry, limit: Float = 220) {
    guard let src = geometry.sources(for: .vertex).first, src.bytesPerComponent == 4, src.componentsPerVector == 3 else { return nil }
    let count = src.vectorCount
    var all = [SIMD3<Float>](repeating: .zero, count: count)
    src.data.withUnsafeBytes { raw in
      for i in 0..<count {
        let o = src.dataOffset + i * src.dataStride
        all[i] = SIMD3(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self))
      }
    }
    verts = all
    for el in geometry.elements where el.primitiveType == .triangles {
      el.data.withUnsafeBytes { raw in
        let bpi = el.bytesPerIndex
        func idx(_ k: Int) -> Int32 {
          bpi == 2 ? Int32(raw.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self)) : Int32(truncatingIfNeeded: raw.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self))
        }
        for t in 0..<el.primitiveCount {
          let a = idx(t * 3), b = idx(t * 3 + 1), c = idx(t * 3 + 2)
          let pa = all[Int(a)], pb = all[Int(b)], pc = all[Int(c)]
          guard max(abs(pa.x), abs(pa.z)) < limit, max(abs(pb.x), abs(pb.z)) < limit, max(abs(pc.x), abs(pc.z)) < limit else { continue }
          let ti = Int32(tris.count)
          tris.append(SIMD3(a, b, c))
          let minx = min(pa.x, pb.x, pc.x), maxx = max(pa.x, pb.x, pc.x), minz = min(pa.z, pb.z, pc.z), maxz = max(pa.z, pb.z, pc.z)
          for cx in Int(floor(minx / cellSize))...Int(floor(maxx / cellSize)) {
            for cz in Int(floor(minz / cellSize))...Int(floor(maxz / cellSize)) { cells[key(cx, cz), default: []].append(ti) }
          }
        }
      }
    }
    if tris.isEmpty { return nil }
  }

  /// Height at terrain-frame (x, z), or nil off the mesh.
  func height(x: Float, z: Float) -> Float? {
    guard let list = cells[key(Int(floor(x / cellSize)), Int(floor(z / cellSize)))] else { return nil }
    for ti in list {
      let t = tris[Int(ti)]
      let a = verts[Int(t.x)], b = verts[Int(t.y)], c = verts[Int(t.z)]
      let d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
      if abs(d) < 1e-9 { continue }
      let l1 = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
      let l2 = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
      let l3 = 1 - l1 - l2
      if l1 >= -1e-4, l2 >= -1e-4, l3 >= -1e-4 { return l1 * a.y + l2 * b.y + l3 * c.y }
    }
    return nil
  }
}
