import Foundation
import QuartzCore
import simd

/// The judge's head orientation as the headset streams it (`vr_pose`, 30 Hz), plus what they gaze at.
/// Written from the network queue, read from the main and render threads.
final class HeadPose: @unchecked Sendable {
  struct Sample {
    var q: simd_quatf
    var at: TimeInterval
    var gaze: Int?
    var cardsShown: Bool
    var fovX: Float?
    /// The judge's head position and scene yaw (the walk outside); nil from older headset builds.
    var p: SIMD3<Float>?
    var yaw: Float?
    var closeUp = false
    /// The reality check (real panorama) is showing in the headset.
    var reality = false
  }

  private let lock = NSLock()
  private var sample = Sample(q: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), at: -100, gaze: nil, cardsShown: false, fovX: nil)
  private var connected = false

  /// `vr_pose`: q = [x, y, z, w] of the head's world orientation.
  func receive(_ m: [String: Any]) {
    guard let a = m["q"] as? [Double], a.count == 4 else { return }
    let q = simd_quatf(ix: Float(a[0]), iy: Float(a[1]), iz: Float(a[2]), r: Float(a[3]))
    guard q.length > 0.5 else { return }
    let gaze = (m["gaze"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
    let fov = (m["fov"] as? Double).map(Float.init)
    var pos: SIMD3<Float>?
    // A non-finite position or yaw would poison the smoothed camera for good (NaN never recovers): dropped.
    if let pa = m["p"] as? [Double], pa.count == 3, pa.allSatisfy(\.isFinite) { pos = SIMD3(Float(pa[0]), Float(pa[1]), Float(pa[2])) }
    let yaw = (m["wy"] as? Double).flatMap { $0.isFinite ? Float($0) : nil }
    lock.lock()
    sample = Sample(q: simd_normalize(q), at: CACurrentMediaTime(), gaze: gaze, cardsShown: m["cards"] as? Bool ?? false, fovX: fov ?? sample.fovX, p: pos, yaw: yaw, closeUp: m["cu"] as? Bool ?? false, reality: m["rc"] as? Bool ?? false)
    lock.unlock()
  }

  /// The server's word on whether an authenticated headset is connected.
  func setConnected(_ on: Bool) {
    lock.lock()
    connected = on
    lock.unlock()
  }

  func latest() -> Sample {
    lock.lock()
    defer { lock.unlock() }
    return sample
  }

  var isConnected: Bool {
    lock.lock()
    defer { lock.unlock() }
    return connected
  }

  /// Live = a headset has streamed its pose recently. A short gap (the phone reconnecting, a stalled frame) holds the last pose
  /// instead of handing the camera to the director, which would swing to the speaker: 4 s while the server still reports the
  /// headset, 2.5 s once it says it's gone (a reconnect closes the old socket before the new one opens).
  func isLive(now: TimeInterval = CACurrentMediaTime()) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return now - sample.at < (connected ? 4.0 : 2.5)
  }
}

/// Frame-rate-independent exponential slerp: light smoothing for the judge's head, slow easing into the drift.
struct OrientationSmoother {
  private(set) var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

  mutating func step(toward target: simd_quatf, dt: Double, timeConstant: Double) -> simd_quatf {
    var t = target
    if simd_dot(q.vector, t.vector) < 0 { t = simd_quatf(vector: -t.vector) } // shortest way round
    let a = Float(1 - exp(-max(0, dt) / max(0.001, timeConstant)))
    q = simd_normalize(simd_slerp(q, t, a))
    return q
  }
}

enum CameraMath {
  /// Orientation for a head turned `yaw` degrees right and `pitch` degrees up.
  static func orientation(yaw: Float, pitch: Float) -> simd_quatf {
    simd_quatf(angle: -yaw * .pi / 180, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch * .pi / 180, axis: SIMD3(1, 0, 0))
  }

  /// The unattended camera: a slow look around the control room (robots, screens, window).
  static func drift(at t: TimeInterval) -> simd_quatf {
    let yaw = 30 * sin(2 * .pi * t / 52) + 6 * sin(2 * .pi * t / 13)
    let pitch = 1 + 3 * sin(2 * .pi * t / 31)
    return orientation(yaw: Float(yaw), pitch: Float(pitch))
  }
}
