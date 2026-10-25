import Foundation
import simd

/// Where the judge stands outside, in WORLD coordinates (x right, -z toward the delta; the habitat is at the
/// origin, its window and pressure door face -z). Everything is inside the terrain wedge (bearing within
/// +-82 degrees of -z).
///
/// Act 1 layout, seen from the single start spot facing the base (the judge looks toward +z, so +x is on their LEFT):
/// the base with its pressure door dead ahead; the cargo lander and its crates to the left; the rock Science grinds ahead
/// and slightly right; the ice drill, the solar field and the dish to the right.
enum Spots {
  struct Spot {
    let pos: SIMD2<Float>
    /// What the judge faces on arrival (world x, z).
    let look: SIMD2<Float>
    var yaw: Float { Spots.yaw(from: pos, to: look) }
  }

  /// Scene yaw (rotation about +Y applied to the Cardboard head) that points the head's forward (-Z) from `a` to `b`.
  static func yaw(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
    let d = b - a
    return atan2(-d.x, -d.y)
  }

  /// The single judge start spot: 13.5 m in front of the base, facing it.
  static let start = Spot(pos: [0, -13.5], look: [0, -5.5])
  // Free-roam stations (Act 4 markers only; the default flow has none).
  static let pad = Spot(pos: [5, -14.5], look: [10, -9])
  static let science = Spot(pos: [-1.5, -14.5], look: [-4.5, -9])
  static let solar = Spot(pos: [-7, -14.5], look: [-17, -14])
  /// The parked rover (world x, z) and where the judge stands to look at it.
  static let roverPos = SIMD2<Float>(7.5, -4.5)
  static let rover = Spot(pos: [4, -13], look: roverPos)
  static let door = Spot(pos: [0, -9], look: [0, -5.5])
  /// Where the Act 1 walk ends (just inside the door plane: the judge glides through the open door while the screen fades).
  static let doorStep = Spot(pos: [0, -5.0], look: [0, -4.5])
  /// The walk to the door takes this long, at a steady speed with a gentle ease at both ends.
  static let doorWalkSeconds: Double = 4.0

  /// The lit footpath to the door: straight in from the start spot.
  static let doorPath: [SIMD2<Float>] = [[0.1, -14], [0.1, -12], [0, -10], [0, -8], [0, -6.9]]
  /// Lamp posts either side of it.
  static let doorLights: [SIMD2<Float>] = [[2.3, -12.2], [-2.3, -12.2], [2.4, -9.0], [-2.4, -8.2], [2.4, -6.8], [-2.4, -6.8]]

  static func spot(_ station: String?) -> Spot? {
    switch station {
    case "pad": return pad
    case "science": return science
    case "solar": return solar
    case "rover": return rover
    case "door": return door
    default: return nil
    }
  }

  // Set pieces (world x, z).
  static let lander = SIMD2<Float>(14.5, -8.5)
  static let crates = SIMD2<Float>(7.4, -10.4)
  /// Supply scans the crates from here (outside).
  static let cargoKeeper = SIMD2<Float>(4.4, -11.8)
  /// The rock Science grinds (outcrop) and where Science hovers beside it (scientist).
  static let outcrop = SIMD2<Float>(-4.6, -8.8)
  static let scientist = SIMD2<Float>(-2.4, -11.0)
  /// Engineer floats up here, beside the judge (a little to the right).
  static let engineer = SIMD2<Float>(-2.2, -13.4)
  static let fieldCenter = SIMD2<Float>(-19.5, -15.5)
  static let habRadius: Float = 4.3
  static let moduleCenter = SIMD2<Float>(9.5, 2.5)
  static let doorFaceZ: Float = -5.5
  static let drill = SIMD2<Float>(-6.8, -10.8)
  static let dish = SIMD2<Float>(-9.5, -5.5)
  /// The crater rim as a world direction from the base (unit x, z): ahead of the judge, beyond the base and a little to the
  /// right. `crew.engineer.lookAt == "rim"` points here and the dust wall rises over it.
  static let rimDir = SIMD2<Float>(-0.32, 0.947)
  /// A point far out along `rimDir`: what the Engineer looks at.
  static let rim = rimDir * 400
}

/// The judge's walk: a straight glide between spots at about 1.4 m/s with a 0.5 s ease-in and ease-out
/// (no acceleration jumps), the facing turning smoothly alongside. A new target while walking continues
/// from the current position at the current speed. With `duration` the walk takes exactly that long.
struct Journey {
  private(set) var pos: SIMD2<Float>
  private(set) var yaw: Float
  private var from: SIMD2<Float>
  private var to: SIMD2<Float>
  private var fromYaw: Float
  private var toYaw: Float
  private var t0: TimeInterval = 0
  private var len: Float = 0
  private var total: Float = 0
  private var rampIn: Float = 0.5
  private let rampOut: Float = 0.5
  private var speed: Float = 1.4
  private(set) var moving = false
  private var clock: TimeInterval = 0
  private var wasMoving = false

  init(at spot: Spots.Spot) {
    pos = spot.pos; from = spot.pos; to = spot.pos
    yaw = spot.yaw; fromYaw = spot.yaw; toYaw = spot.yaw
  }

  /// Walk to `spot` (or `pos` facing `yaw`). `snap` jumps there at once.
  mutating func go(to spot: Spots.Spot, now: TimeInterval, speed v0: Float = 1.4, duration: Double? = nil, snap: Bool = false) {
    var v = v0
    if snap {
      pos = spot.pos; from = spot.pos; to = spot.pos; yaw = spot.yaw; fromYaw = yaw; toYaw = yaw; moving = false
      return
    }
    // Already walking: carry on at speed (no new ease-in).
    rampIn = moving ? 0 : 0.5
    from = pos; fromYaw = yaw
    to = spot.pos; toYaw = spot.yaw
    len = simd_distance(from, to)
    // A fixed duration: one cruise speed with a 0.5 s ease at both ends (distance = v * (T - 0.5)).
    if let d = duration, len > 0.05 { rampIn = 0.5; v = len / Float(max(0.8, d) - 0.5) }
    speed = v
    total = len / v + (rampIn + rampOut) / 2
    t0 = now
    moving = len > 0.05
    if !moving { yaw = toYaw; pos = to }
  }

  /// Distance walked after `t` seconds.
  private func travelled(_ t: Float) -> Float {
    if t <= 0 { return 0 }
    if t >= total { return len }
    if rampIn > 0 && t < rampIn { return speed * t * t / (2 * rampIn) }
    if t > total - rampOut { let r = total - t; return len - speed * r * r / (2 * rampOut) }
    return speed * (t - rampIn / 2)
  }

  mutating func step(now: TimeInterval) {
    clock = now
    guard moving else { return }
    let t = Float(now - t0)
    let s = travelled(t)
    let p = len > 0 ? min(1, s / len) : 1
    pos = from + (to - from) * p
    var d = toYaw - fromYaw
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    let e = p * p * (3 - 2 * p)
    yaw = fromYaw + d * e
    if t >= total { moving = false; pos = to; yaw = toYaw }
  }
}
