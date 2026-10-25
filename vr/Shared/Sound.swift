import AVFoundation

/// Audio for the control room. Everything ambient and every chime is synthesized in code:
/// - an interior hum (low tone plus dull noise, slow 0.1 Hz wobble),
/// - wind that follows dust opacity (tau) with slow gusts, muffled while the listener is inside,
/// - a two-note chime per agent line (pitch set per crew member, pentatonic), a tick when an agent starts thinking,
///   and a deeper two-tone when the commander decides,
/// - the low pulsing power alarm (only while `world.alarm`), the pressure door's hiss and its seal.
/// The short Kenney CC0 wavs still back `play` (hover / select / alert / saved).
/// One AVAudioEngine: a single source node for ambience plus a small pool of player nodes for cues.
final class Sound {
  static let shared = Sound()
  private var players: [String: [AVAudioPlayer]] = [:]

  /// The spectator view stays silent: the headset makes the sounds.
  var muted = false {
    didSet { engine?.mainMixerNode.outputVolume = muted ? 0 : 1 }
  }

  private var engine: AVAudioEngine?
  private let ambience = Ambience()
  private var cuePlayers: [AVAudioPlayerNode] = []
  private var nextCue = 0
  private var chimes: [String: AVAudioPCMBuffer] = [:]
  private var tick: AVAudioPCMBuffer?
  private var decide: AVAudioPCMBuffer?
  private var hiss: AVAudioPCMBuffer?
  private var seal: AVAudioPCMBuffer?
  private var lastDoorAt = 0.0
  private var lastChimeAt = 0.0, lastTickAt = 0.0, lastDecideAt = 0.0

  private init() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
    for name in ["hover", "select", "alert", "saved"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { continue }
      // A few voices each, so quick repeats don't cut each other off.
      players[name] = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
      players[name]?.forEach { $0.prepareToPlay() }
    }
    #if os(iOS)
    startEngine()   // the headset prewarms at launch; the muted Mac spectator never starts it
    #endif
  }

  private func startEngine() {
    guard engine == nil else { return }
    let e = AVAudioEngine()
    let sr = e.outputNode.outputFormat(forBus: 0).sampleRate
    let rate = sr > 0 ? sr : 44100
    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
    ambience.sampleRate = Float(rate)
    let amb = ambience
    let src = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
      amb.render(frames: Int(frames), abl: abl)
      return noErr
    }
    e.attach(src)
    e.connect(src, to: e.mainMixerNode, format: fmt)
    for _ in 0..<4 {
      let p = AVAudioPlayerNode()
      e.attach(p)
      e.connect(p, to: e.mainMixerNode, format: fmt)
      cuePlayers.append(p)
    }
    // Pentatonic degrees from C5 (Hz); each role plays two of them.
    let scale: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.7]
    let pairs: [String: (Int, Int)] = [
      "requester": (0, 2), "receiver": (1, 3), "controller": (2, 4), "ap": (3, 5), "treasury": (4, 6),
      // The crew: each member has its own two-note voice.
      "engineer": (0, 2), "life": (3, 5), "science": (2, 4), "supply": (1, 3), "rules": (4, 6),
    ]
    for (role, ab) in pairs {
      chimes[role] = Self.render(rate: rate, peak: 0.2, notes: [(scale[ab.0], 0, 0.17), (scale[ab.1], 0.09, 0.2)], length: 0.3, decay: 11, harmonic: 0.15)
    }
    chimes["default"] = Self.render(rate: rate, peak: 0.2, notes: [(scale[0], 0, 0.17), (scale[3], 0.09, 0.2)], length: 0.3, decay: 11, harmonic: 0.15)
    tick = Self.render(rate: rate, peak: 0.08, notes: [(1250, 0, 0.1)], length: 0.07, decay: 55, harmonic: 0)
    decide = Self.render(rate: rate, peak: 0.28, notes: [(196, 0, 0.45), (130.8, 0.17, 0.5)], length: 0.75, decay: 4.5, harmonic: 0.25)
    hiss = Self.renderHiss(rate: rate)
    seal = Self.renderSeal(rate: rate)
    e.mainMixerNode.outputVolume = muted ? 0 : 1
    e.prepare()
    do { try e.start() } catch { return }
    cuePlayers.forEach { $0.play() }
    engine = e
    #if os(iOS)
    NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in
      guard let self, let e = self.engine, !e.isRunning else { return }
      try? e.start()
      self.cuePlayers.forEach { $0.play() }
    }
    NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
      guard let self, let e = self.engine, (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue else { return }
      try? AVAudioSession.sharedInstance().setActive(true)
      if !e.isRunning { try? e.start(); self.cuePlayers.forEach { $0.play() } }
    }
    #endif
  }

  /// Sum of decaying sine notes (freq, start s, relative gain) with a soft 8 ms attack.
  private static func render(rate: Double, peak: Float, notes: [(Float, Double, Float)], length: Double, decay: Float, harmonic: Float) -> AVAudioPCMBuffer? {
    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(rate * length)) else { return nil }
    let n = Int(rate * length)
    buf.frameLength = AVAudioFrameCount(n)
    let d = buf.floatChannelData![0]
    for i in 0..<n { d[i] = 0 }
    for (f, start, g) in notes {
      let s0 = Int(start * rate)
      guard s0 < n else { continue }
      for i in s0..<n {
        let t = Float(Double(i - s0) / rate)
        let env = min(1, t / 0.008) * expf(-decay * t)
        let ph = 2 * Float.pi * f * t
        d[i] += (sinf(ph) + harmonic * sinf(2 * ph)) * env * g
      }
    }
    var m: Float = 0
    for i in 0..<n { m = max(m, abs(d[i])) }
    if m > 0 { let k = peak / m; for i in 0..<n { d[i] *= k } }
    return buf
  }

  /// The pressure door's hiss: a 1.3 s burst of high-passed noise with a quick swell and a long fade.
  private static func renderHiss(rate: Double) -> AVAudioPCMBuffer? {
    let length = 1.4
    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(rate * length)) else { return nil }
    let n = Int(rate * length)
    buf.frameLength = AVAudioFrameCount(n)
    let d = buf.floatChannelData![0]
    var seed: UInt32 = 0x9E3779B9
    var lp: Float = 0, lp2: Float = 0
    for i in 0..<n {
      seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
      let w = Float(Int32(bitPattern: seed)) / 2147483648
      lp += 0.35 * (w - lp)       // soften the very top
      lp2 += 0.04 * (lp - lp2)    // and take the low end out: high-passed hiss
      let t = Float(Double(i) / rate)
      let env = min(1, t / 0.07) * expf(-2.6 * t)
      d[i] = (lp - lp2) * env
    }
    var m: Float = 0
    for i in 0..<n { m = max(m, abs(d[i])) }
    if m > 0 { let k = 0.26 / m; for i in 0..<n { d[i] *= k } }
    return buf
  }

  /// The door sealing: a low thump with a short metallic click on top.
  private static func renderSeal(rate: Double) -> AVAudioPCMBuffer? {
    let length = 0.9
    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(rate * length)) else { return nil }
    let n = Int(rate * length)
    buf.frameLength = AVAudioFrameCount(n)
    let d = buf.floatChannelData![0]
    var seed: UInt32 = 0x2545F491
    for i in 0..<n {
      let t = Float(Double(i) / rate)
      seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
      let w = Float(Int32(bitPattern: seed)) / 2147483648
      let thump = sinf(2 * Float.pi * (62 - 22 * min(1, t * 4)) * t) * expf(-7 * t)
      let click = w * expf(-90 * t) * 0.5 + sinf(2 * Float.pi * 880 * t) * expf(-45 * (t - 0.11).magnitude) * (t > 0.1 ? 0.18 : 0)
      d[i] = min(1, t / 0.004) * (thump + click)
    }
    var m: Float = 0
    for i in 0..<n { m = max(m, abs(d[i])) }
    if m > 0 { let k = 0.42 / m; for i in 0..<n { d[i] *= k } }
    return buf
  }

  private func cue(_ buf: AVAudioPCMBuffer?) {
    guard !muted, let buf else { return }
    startEngine()
    guard engine?.isRunning == true, !cuePlayers.isEmpty else { return }
    let p = cuePlayers[nextCue % cuePlayers.count]
    nextCue += 1
    p.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
    if !p.isPlaying { p.play() }
  }

  func play(_ name: String, volume: Float = 0.7) {
    guard !muted, let voices = players[name], let p = voices.first(where: { !$0.isPlaying }) ?? voices.first else { return }
    p.currentTime = 0
    p.volume = volume
    p.play()
  }

  /// Soft two-note chime when an agent speaks, pitched per role.
  func speak(role: String) {
    let t = CFAbsoluteTimeGetCurrent()
    guard t - lastChimeAt > 0.25 else { return }
    lastChimeAt = t
    cue(chimes[role] ?? chimes["default"] ?? nil)
  }

  /// A quieter tick when an agent begins to think.
  func thinkingStarted() {
    let t = CFAbsoluteTimeGetCurrent()
    guard t - lastTickAt > 0.3 else { return }
    lastTickAt = t
    cue(tick)
  }

  /// Deeper two-tone when the commander decides.
  func decided() {
    let t = CFAbsoluteTimeGetCurrent()
    guard t - lastDecideAt > 1.0 else { return }
    lastDecideAt = t
    cue(decide)
  }

  /// The pressure door opens with a hiss.
  func doorHiss() {
    let t = CFAbsoluteTimeGetCurrent()
    guard t - lastDoorAt > 0.5 else { return }
    lastDoorAt = t
    cue(hiss)
  }

  /// The door seals behind the judge: thump and click, with the room's hum coming up.
  func doorSeal() { cue(seal) }

  /// The power alarm: low and pulsing, only while it is on (`world.alarm`).
  func setAlarm(_ on: Bool) {
    guard !muted else { return }
    startEngine()
    ambience.alarm = on ? 1 : 0
  }

  /// Wind follows dust opacity (0.6 calm, 4.6 storm).
  func setStorm(tau: Double) {
    guard !muted else { return }
    startEngine()
    ambience.storm = Float(max(0, min(1, (tau - 0.6) / 4)))
  }

  /// Cross-fades hum and wind (~1.5 s). The headset stays in the control room, so this is for completeness.
  func setOutside(_ outside: Bool) { ambience.outside = outside ? 1 : 0 }
}

/// Procedural ambience rendered on the audio thread: parameters are plain floats written from the main thread.
private final class Ambience {
  var sampleRate: Float = 44100
  var storm: Float = 0
  var outside: Float = 0
  var alarm: Float = 0
  private var alarmEnv: Float = 0, alarmPhase: Float = 0, alarmLFO: Float = 0
  // audio-thread state
  private var seed: UInt32 = 0x1234ABCD
  private var phase: Float = 0, wobble: Float = 0
  private var brown: Float = 0
  private var low: Float = 0, band: Float = 0
  private var mix: Float = 0, k: Float = 0
  private var gust: Float = 0.5, gustTarget: Float = 0.5, gustLeft = 0

  @inline(__always) private func noise() -> Float {
    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
    return Float(Int32(bitPattern: seed)) / 2147483648
  }

  func render(frames: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
    let bufs = UnsafeMutableAudioBufferListPointer(abl)
    guard let out = bufs.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
    let sr = sampleRate
    let smooth = 1 - expf(-1 / (sr * 0.5))        // ~1.5 s to settle (3 time constants of 0.5 s)
    let gustSmooth = 1 - expf(-1 / (sr * 1.2))
    let twoPi = 2 * Float.pi
    let humInc = twoPi * 55 / sr, wobInc = twoPi * 0.1 / sr
    // Filter coefficients per block.
    let cutoff = (260 + 1100 * k) * (0.55 + 0.45 * mix)
    let f = 2 * sinf(Float.pi * min(cutoff, sr * 0.2) / sr)
    let q: Float = 1.3
    for i in 0..<frames {
      mix += (outside - mix) * smooth
      k += (storm - k) * smooth * 0.3
      if gustLeft <= 0 {
        gustTarget = (noise() + 1) * 0.5
        gustLeft = Int(sr * (2 + 3 * (noise() + 1) * 0.5))
      }
      gustLeft -= 1
      gust += (gustTarget - gust) * gustSmooth * 0.6
      let n = noise()
      // Interior hum.
      phase += humInc; if phase > twoPi { phase -= twoPi }
      wobble += wobInc; if wobble > twoPi { wobble -= twoPi }
      brown += 0.02 * (n - brown)
      let wob = 1 + 0.18 * sinf(wobble)
      let hum = (0.028 * sinf(phase) + 0.008 * sinf(2 * phase) + brown * 0.35) * wob
      // Wind: band-passed noise (state-variable filter).
      low += f * band
      let high = n - low - q * band
      band += f * high
      let level = (0.025 + 0.2 * k) * (0.5 + 0.9 * gust) * (0.3 + 0.7 * mix)
      // Alarm: a low two-tone (about 170 and 215 Hz) gated at 1.1 Hz, soft edges, under everything else.
      alarmEnv += (alarm - alarmEnv) * smooth * 2
      var al: Float = 0
      if alarmEnv > 0.001 {
        alarmLFO += twoPi * 1.1 / sr; if alarmLFO > twoPi { alarmLFO -= twoPi }
        let gate = max(0, min(1, sinf(alarmLFO) * 2.2 + 0.5))
        alarmPhase += twoPi * (sinf(alarmLFO) > 0 ? 215 : 170) / sr; if alarmPhase > twoPi { alarmPhase -= twoPi }
        al = (sinf(alarmPhase) + 0.35 * sinf(2 * alarmPhase)) * 0.085 * gate * alarmEnv
      }
      out[i] = hum * (1 - mix) + band * level * 1.6 + al
    }
    if bufs.count > 1 { for b in 1..<bufs.count { if let d = bufs[b].mData { memcpy(d, out, frames * 4) } } }
  }
}
