import AVFoundation

/// Small audio cues (Kenney CC0). Played through the phone speaker inside the viewer.
final class Sound {
  static let shared = Sound()
  private var players: [String: [AVAudioPlayer]] = [:]
  private var rumble: AVAudioPlayer?

  /// The spectator view stays silent: the headset makes the sounds.
  var muted = false {
    didSet { if muted { rumble?.volume = 0 } }
  }

  private init() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
    for name in ["hover", "select", "alert", "saved", "blip"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
      // A few voices each, so quick repeats don't cut each other off.
      players[name] = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
      players[name]?.forEach { $0.prepareToPlay() }
    }
    if let url = Bundle.main.url(forResource: "rumble", withExtension: "wav"), let p = try? AVAudioPlayer(contentsOf: url) {
      p.numberOfLoops = -1
      p.volume = 0
      p.prepareToPlay()
      p.play()
      rumble = p
    }
  }

  func play(_ name: String, volume: Float = 0.7) {
    guard !muted, let voices = players[name], let p = voices.first(where: { !$0.isPlaying }) ?? voices.first else { return }
    p.currentTime = 0
    p.volume = volume
    p.play()
  }

  /// Storm ambience follows dust opacity.
  func setStorm(tau: Double) {
    guard !muted else { return }
    let v = Float(max(0, min(1, (tau - 0.8) / 4))) * 0.35
    rumble?.setVolume(v, fadeDuration: 1.5)
  }
}
