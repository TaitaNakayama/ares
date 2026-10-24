import Foundation
import simd

/// Where the judge stands outside, in WORLD coordinates (x right, -z toward the delta; the habitat is at the
/// origin, its window and pressure door face -z). Everything is inside the terrain wedge (bearing within
/// +-82 degrees of -z) and 16-18 m apart, so a leg takes about 12 s at walking pace.
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

  static let start = Spot(pos: [2, -57], look: [26, -55])
  static let pad = Spot(pos: [15, -43], look: [26, -55])
  static let science = Spot(pos: [1, -34], look: [-2.6, -36.2])
  static let solar = Spot(pos: [-11, -22], look: [-22, -35])
  /// The parked rover (world x, z) and where the judge stands to look at it (reality check).
  static let roverPos = SIMD2<Float>(-0.8, -22)
  static let rover = Spot(pos: [3.6, -16.5], look: roverPos)
  static let door = Spot(pos: [0, -11], look: [0, -5.5]) // 2 m further back than round 2, so the habitat and door read in context
  /// Where the glide ends before the fade (about 1 m from the door).
  static let doorStep = Spot(pos: [0, -6.7], look: [0, -5.5])

  /// The lit footpath to the door: from the pad's direction, curving in, ending just short of the doorstep (world x, z).
  static let doorPath: [SIMD2<Float>] = [[14, -15], [10, -13.2], [7, -11.3], [4.4, -9.2], [2.2, -7.6], [0.4, -6.7]]
  /// Lamp posts along it: two on the pad-side run and a pair on each side of the final approach (these four are in the door view).
  static let doorLights: [SIMD2<Float>] = [[10.4, -14.3], [6.4, -11.9], [3.0, -8.6], [-3.0, -8.6], [2.4, -6.9], [-2.4, -6.9]]

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
  static let lander = SIMD2<Float>(27, -55)
  static let crates = SIMD2<Float>(22, -50)
  static let cargoKeeper = SIMD2<Float>(18.8, -47)
  static let outcrop = SIMD2<Float>(-3.9, -34.8)
  static let scientist = SIMD2<Float>(-1.3, -37.6)
  static let engineer = SIMD2<Float>(-14.5, -26.5)
  static let fieldCenter = SIMD2<Float>(-22, -35)
  static let habRadius: Float = 4.3
  static let moduleCenter = SIMD2<Float>(11, -1.5)
  static let doorFaceZ: Float = -5.5
  static let drill = SIMD2<Float>(-10, -60)
}

/// The judge's walk: a straight glide between spots at about 1.4 m/s with a 0.5 s ease-in and ease-out
/// (no acceleration jumps), the facing turning smoothly alongside. A new target while walking continues
/// from the current position at the current speed.
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
  mutating func go(to spot: Spots.Spot, now: TimeInterval, speed v: Float = 1.4, snap: Bool = false) {
    if snap {
      pos = spot.pos; from = spot.pos; to = spot.pos; yaw = spot.yaw; fromYaw = yaw; toYaw = yaw; moving = false
      return
    }
    // Already walking: carry on at speed (no new ease-in).
    rampIn = moving ? 0 : 0.5
    from = pos; fromYaw = yaw
    to = spot.pos; toYaw = spot.yaw
    len = simd_distance(from, to)
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
