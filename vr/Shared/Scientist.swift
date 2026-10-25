import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// Retired: the human scientist is gone. Science is a robot now (Robots.swift / Crew.swift, id `science`, green).
/// This empty shell only keeps the old call sites in `OutdoorDirector` and `CloseUp` compiling: it has no geometry,
/// cannot be gazed at (its hit points sit far below the world) and never speaks.
final class Scientist {
  static let tagColor = PlatformColor(red: 0.84, green: 0.87, blue: 0.91, alpha: 1)
  let node = SCNNode()
  let bubble = SpeechBubble()
  var hovered = false
  var role: String { "scientist" }

  init(at p: SIMD3<Float>, facing yaw: Float) {
    node.isHidden = true
    bubble.node.isHidden = true
  }

  /// Out of reach on purpose (`OutdoorDirector.scientistHit` tests these points).
  var worldPosition: SIMD3<Float> { SIMD3(0, -5000, 0) }
  var tagPosition: SIMD3<Float> { SIMD3(0, -5000, 0) }

  func setName(_ n: String?) {}
  func hear(text: String, seq: Int, now: TimeInterval) {}
  func isSpeaking(now: TimeInterval) -> Bool { false }
  func update(now: TimeInterval, user: SIMD3<Float>, bubbleWanted: Bool) {}
}
