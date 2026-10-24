import AppKit

/// 2D layer over the 3D view, for the people at the table: where the judge looks, what the agents
/// say, the decision in front of the judge, and how far the story has got.
/// Top-left origin; mouse events pass through to the 3D view.
final class OverlayView: NSView {
  let dot = GazeDotView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
  let subtitles = SubtitleView()
  let card = DecisionCardView()
  let badges = BadgeView()
  let thinking = ThinkingView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    for v in [badges, card, subtitles, thinking, dot] as [NSView] { addSubview(v) }
    card.alphaValue = 0
    dot.isHidden = true
  }

  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    let b = bounds
    badges.frame = NSRect(x: 0, y: 0, width: b.width, height: max(70, b.height * 0.09))
    thinking.frame = NSRect(x: 0, y: badges.frame.maxY + 6, width: b.width, height: max(34, b.height * 0.05))
    let cardH = b.height * 0.44
    card.frame = NSRect(x: b.width * 0.06, y: b.height - cardH - b.height * 0.03, width: b.width * 0.88, height: cardH)
    // Subtitles sit low; while a decision is up they move above it.
    let subH = b.height * 0.25
    let subY = card.isUp ? card.frame.minY - subH - 8 : b.height - subH - b.height * 0.03
    subtitles.frame = NSRect(x: b.width * 0.05, y: subY, width: b.width * 0.9, height: subH)
  }

  /// `p` in this view's coordinates, or nil when the judge looks outside the picture.
  func placeDot(_ p: CGPoint?) {
    guard let p, bounds.insetBy(dx: -10, dy: -10).contains(p) else { dot.isHidden = true; return }
    dot.isHidden = false
    dot.setFrameOrigin(NSPoint(x: p.x - dot.frame.width / 2, y: p.y - dot.frame.height / 2))
  }
}

/// The judge's gaze: a ring with a dark outline, visible on the bright window and the dark wall.
final class GazeDotView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    let r = bounds.insetBy(dx: 5, dy: 5)
    NSColor(white: 0, alpha: 0.55).setStroke()
    let outer = NSBezierPath(ovalIn: r)
    outer.lineWidth = 9
    outer.stroke()
    NSColor.white.setStroke()
    let ring = NSBezierPath(ovalIn: r)
    ring.lineWidth = 4.5
    ring.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)).fill()
  }
}

// MARK: - Subtitles

struct Subtitle {
  let seq: Int
  let role: String
  let name: String
  let text: String
  let refused: Bool
  var shownAt: TimeInterval = 0
  var duration: TimeInterval = 4
}

/// Every agent line, in order, each on screen long enough to read. At most two at once; a backlog
/// (time-lapse bursts) shortens display times but never drops a line.
final class SubtitleQueue {
  private(set) var visible: [Subtitle] = []
  private var pending: [Subtitle] = []
  private var seen = Set<Int>()
  private var newest = -1

  /// Reading time: about 15 characters a second plus a beat to find the line, 3-9 s.
  static func readingTime(_ text: String) -> TimeInterval { min(9, max(3, 1.5 + Double(text.count) / 15)) }

  func push(_ s: Subtitle) {
    guard !seen.contains(s.seq), s.seq > newest - 50 else { return }
    seen.insert(s.seq)
    newest = max(newest, s.seq)
    pending.append(s)
    pending.sort { $0.seq < $1.seq }
  }

  /// Forget everything (the run was reset or switched between live and the recording).
  func clear() {
    visible = []
    pending = []
    seen = []
    newest = -1
  }

  /// Returns true when what's on screen changed.
  func tick(now: TimeInterval) -> Bool {
    let before = visible.map(\.seq)
    visible.removeAll { now - $0.shownAt > $0.duration }
    while visible.count < 2, !pending.isEmpty {
      var s = pending.removeFirst()
      let backlog = pending.count
      let base = Self.readingTime(s.text)
      s.duration = backlog >= 3 ? max(2.2, base * 0.6) : base
      s.shownAt = now
      visible.append(s)
    }
    return visible.map(\.seq) != before
  }
}

final class SubtitleView: NSView {
  var items: [Subtitle] = [] { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard !items.isEmpty else { return }
    let textSize = max(22, bounds.height * 0.17)
    let nameSize = textSize * 0.62
    var blocks: [(Subtitle, NSAttributedString, NSAttributedString, CGFloat)] = []
    let width = bounds.width - 56
    for s in items {
      let color = SpectatorPalette.role(s.role)
      let name = NSMutableAttributedString(string: s.name.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: nameSize, weight: .heavy), .foregroundColor: color, .kern: 1.2])
      if s.refused { name.append(NSAttributedString(string: "   REFUSED BY POLICY", attributes: [.font: NSFont.systemFont(ofSize: nameSize, weight: .heavy), .foregroundColor: SpectatorPalette.red])) }
      let para = NSMutableParagraphStyle()
      para.lineBreakMode = .byWordWrapping
      let body = NSAttributedString(string: s.text, attributes: [.font: NSFont.systemFont(ofSize: textSize, weight: .semibold), .foregroundColor: NSColor(white: 0.97, alpha: 1), .paragraphStyle: para])
      let bodyH = min(ceil(body.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]).height), textSize * 1.25 * 2)
      blocks.append((s, name, body, bodyH))
    }
    // Newest at the bottom, stacked upward.
    var y = bounds.height
    for (s, name, body, bodyH) in blocks.reversed() {
      let h = nameSize * 1.35 + bodyH + 26
      y -= h
      let box = NSRect(x: 0, y: y, width: bounds.width, height: h)
      NSColor(white: 0.02, alpha: 0.78).setFill()
      NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
      SpectatorPalette.role(s.role).setFill()
      NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: 10, height: box.height), xRadius: 5, yRadius: 5).fill()
      name.draw(at: NSPoint(x: box.minX + 28, y: box.minY + 10))
      body.draw(with: NSRect(x: box.minX + 28, y: box.minY + 12 + nameSize * 1.35, width: width, height: bodyH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
      y -= 10
    }
  }
}

// MARK: - Thinking

/// "<Name> is thinking…": a subtle centred pill under the badges while an agent's brain is deciding.
final class ThinkingView: NSView {
  var roles: [String] = [] { didSet { if roles != oldValue { needsDisplay = true } } }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard !roles.isEmpty else { return }
    let size = max(15, bounds.height * 0.46)
    let text = NSMutableAttributedString()
    for (i, role) in roles.enumerated() {
      let name = RobotCrew.layout.first { $0.role == role }?.name ?? role
      if i > 0 { text.append(NSAttributedString(string: "   ", attributes: [.font: NSFont.systemFont(ofSize: size)])) }
      text.append(NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: SpectatorPalette.role(role)]))
      text.append(NSAttributedString(string: " is thinking…", attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor(white: 0.9, alpha: 1)]))
    }
    let ts = text.size()
    let box = NSRect(x: (bounds.width - ts.width) / 2 - 18, y: 0, width: ts.width + 36, height: bounds.height)
    NSColor(white: 0.02, alpha: 0.6).setFill()
    NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
    text.draw(at: NSPoint(x: box.minX + 18, y: (bounds.height - ts.height) / 2))
  }
}

// MARK: - Decision card

/// The judge's decision, enlarged: the option they're gazing at is highlighted, and the one they
/// chose is shown when they press the button.
final class DecisionCardView: NSView {
  struct Option: Equatable { let id: String; let label: String; let detail: String; var proposedBy: String? = nil }
  private(set) var isUp = false
  private var title = ""
  private var options: [Option] = []
  private var gazed: Int?
  private var chosen: (label: String, at: TimeInterval)?
  override var isFlipped: Bool { true }

  /// Returns true when the layout must change (the card appeared or went away).
  func update(waitingReason: String?, options new: [Option], gazed g: Int?, chosen c: (label: String, at: TimeInterval)?, now: TimeInterval) -> Bool {
    let showChoice = c.map { now - $0.at < 4.0 } ?? false
    let up = !new.isEmpty || showChoice
    var dirty = false
    if new != options && !new.isEmpty { options = new; dirty = true }
    if let r = waitingReason, r != title { title = r; dirty = true }
    if g != gazed { gazed = g; dirty = true }
    let wasChosen = chosen?.label
    chosen = showChoice ? c : nil
    if chosen?.label != wasChosen { dirty = true }
    if dirty { needsDisplay = true }
    guard up != isUp else { return false }
    isUp = up
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = up ? 0.35 : 0.5
      animator().alphaValue = up ? 1 : 0
    }
    if !up { options = [] }
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !options.isEmpty || chosen != nil else { return }
    let b = bounds
    NSColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: b, xRadius: 22, yRadius: 22).fill()
    let headSize = max(16, b.height * 0.065)
    let head = chosen.map { "COMMANDER CHOSE: \($0.label.uppercased())" } ?? "THE COMMANDER DECIDES"
    NSAttributedString(string: head, attributes: [.font: NSFont.systemFont(ofSize: headSize, weight: .heavy), .foregroundColor: chosen != nil ? SpectatorPalette.green : SpectatorPalette.amber, .kern: 1.5])
      .draw(at: NSPoint(x: 32, y: 22))
    let why = BaseSceneText.firstSentence(title)
    NSAttributedString(string: why, attributes: [.font: NSFont.systemFont(ofSize: headSize * 0.62, weight: .medium), .foregroundColor: NSColor(white: 0.7, alpha: 1)])
      .draw(with: NSRect(x: 32, y: 22 + headSize * 1.4, width: b.width - 64, height: headSize * 0.62 * 1.3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    let top = 22 + headSize * 1.4 + headSize * 0.62 * 1.6 + 8
    let gap: CGFloat = 18
    let cw = (b.width - 64 - gap) / 2
    let ch = (b.height - top - 24 - gap) / 2
    for (i, o) in options.prefix(4).enumerated() {
      let r = NSRect(x: 32 + CGFloat(i % 2) * (cw + gap), y: top + CGFloat(i / 2) * (ch + gap), width: cw, height: ch)
      let isChosen = chosen?.label == o.label
      let isGazed = gazed == i && chosen == nil
      (isChosen ? NSColor(red: 0.07, green: 0.20, blue: 0.11, alpha: 1) : isGazed ? NSColor(red: 0.20, green: 0.15, blue: 0.06, alpha: 1) : NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)).setFill()
      let box = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
      box.fill()
      (isChosen ? SpectatorPalette.green : isGazed ? SpectatorPalette.amber : NSColor(white: 1, alpha: 0.22)).setStroke()
      box.lineWidth = isChosen || isGazed ? 6 : 2
      box.stroke()
      let labelSize = max(15, ch * 0.2)
      NSAttributedString(string: o.label, attributes: [.font: NSFont.systemFont(ofSize: labelSize, weight: .heavy), .foregroundColor: isChosen ? SpectatorPalette.green : isGazed ? SpectatorPalette.amber : NSColor(white: 0.95, alpha: 1)])
        .draw(with: NSRect(x: r.minX + 22, y: r.minY + 16, width: r.width - 44, height: labelSize * 2.6), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
      // Cards without a proposer put the detail right under the label so a long line gets two lines at full size.
      let labelH0 = min(ceil(NSAttributedString(string: o.label, attributes: [.font: NSFont.systemFont(ofSize: labelSize, weight: .heavy)]).boundingRect(with: NSSize(width: r.width - 44, height: 1000), options: [.usesLineFragmentOrigin]).height), labelSize * 2.6)
      var detailTop = r.minY + 16 + labelH0 + 8
      if let by = o.proposedBy, !by.isEmpty {
        let c = RobotCrew.color(forAgent: by) ?? Palette.violet
        let labelH = min(ceil(NSAttributedString(string: o.label, attributes: [.font: NSFont.systemFont(ofSize: labelSize, weight: .heavy)]).boundingRect(with: NSSize(width: r.width - 44, height: 1000), options: [.usesLineFragmentOrigin]).height), labelSize * 2.6)
        let tagTop = r.minY + 16 + labelH + 4
        NSAttributedString(string: "proposed by \(by)", attributes: [.font: NSFont.systemFont(ofSize: labelSize * 0.6, weight: .bold), .foregroundColor: c])
          .draw(with: NSRect(x: r.minX + 22, y: tagTop, width: r.width - 44, height: labelSize * 0.8), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        detailTop = tagTop + labelSize * 0.8 + 4
      }
      // Never cut a word: wrap, and shrink the font until the whole sentence fits the box.
      let dRect = NSRect(x: r.minX + 22, y: detailTop, width: r.width - 44, height: r.maxY - detailTop - 10)
      let dText = BaseSceneText.firstSentence(o.detail)
      var dSize = labelSize * 0.68
      while dSize > 9 {
        let h = (dText as NSString).boundingRect(with: NSSize(width: dRect.width, height: 4000), options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: dSize, weight: .medium)]).height
        if ceil(h) <= dRect.height { break }
        dSize -= 1
      }
      NSAttributedString(string: dText, attributes: [.font: NSFont.systemFont(ofSize: dSize, weight: .medium), .foregroundColor: NSColor(white: 0.68, alpha: 1)])
        .draw(with: dRect, options: [.usesLineFragmentOrigin])
      if isGazed || isChosen {
        let tag = isChosen ? "CHOSEN" : "LOOKING"
        let t = NSAttributedString(string: tag, attributes: [.font: NSFont.systemFont(ofSize: labelSize * 0.6, weight: .heavy), .foregroundColor: isChosen ? SpectatorPalette.green : SpectatorPalette.amber, .kern: 1.5])
        t.draw(at: NSPoint(x: r.maxX - t.size().width - 20, y: r.maxY - t.size().height - 14))
      }
    }
  }
}

// MARK: - Badges

final class BadgeView: NSView {
  enum Mode: Equatable { case live, replay, mouse }
  var mode: Mode = .replay { didSet { if mode != oldValue { needsDisplay = true } } }
  var beat: (n: Int, of: Int)? { didSet { if beat?.n != oldValue?.n { needsDisplay = true } } }
  var debugText = "" { didSet { if debugText != oldValue { needsDisplay = true } } }
  override var isFlipped: Bool { true }

  static let beatNames = ["", "Short delivery", "Dust storm", "Batteries needed", "Suspicious quote", "Blocked, asking Earth", "Commander decides", "Earth's answer"]

  override func draw(_ dirtyRect: NSRect) {
    let size = max(15, bounds.height * 0.3)
    let (text, color, sub): (String, NSColor, String) = {
      switch mode {
      case .live: return ("LIVE", SpectatorPalette.red, "the commander's view")
      case .replay: return ("REPLAY", SpectatorPalette.amber, "recorded run")
      case .mouse: return ("DEBUG", SpectatorPalette.violet, "mouse camera, no headset")
      }
    }()
    let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.white, .kern: 2])
    let subS = NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: size * 0.62, weight: .semibold), .foregroundColor: NSColor(white: 0.85, alpha: 1)])
    let pillW = size * 0.9 + label.size().width + 30 + subS.size().width + 24
    let pill = NSRect(x: 24, y: 20, width: pillW, height: size * 1.7)
    NSColor(white: 0.02, alpha: 0.75).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.minX + 16, y: pill.midY - size * 0.3, width: size * 0.6, height: size * 0.6)).fill()
    label.draw(at: NSPoint(x: pill.minX + 16 + size * 0.9, y: pill.midY - label.size().height / 2))
    subS.draw(at: NSPoint(x: pill.minX + 16 + size * 0.9 + label.size().width + 14, y: pill.midY - subS.size().height / 2))
    if let b = beat, b.n > 0 {
      let name = b.n < Self.beatNames.count ? Self.beatNames[b.n] : ""
      let s = NSMutableAttributedString(string: "\(b.n) of \(b.of)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.white])
      s.append(NSAttributedString(string: "  \(name)", attributes: [.font: NSFont.systemFont(ofSize: size * 0.75, weight: .semibold), .foregroundColor: NSColor(white: 0.85, alpha: 1)]))
      let w = s.size().width + 44
      let r = NSRect(x: bounds.width - w - 24, y: 20, width: w, height: size * 1.7)
      NSColor(white: 0.02, alpha: 0.75).setFill()
      NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
      s.draw(at: NSPoint(x: r.minX + 22, y: r.midY - s.size().height / 2))
    }
    if !debugText.isEmpty {
      NSAttributedString(string: debugText, attributes: [.font: NSFont.monospacedSystemFont(ofSize: size * 0.55, weight: .medium), .foregroundColor: NSColor(white: 0.8, alpha: 0.9)])
        .draw(at: NSPoint(x: 26, y: pill.maxY + 8))
    }
  }
}

enum SpectatorPalette {
  static let amber = NSColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1)
  static let red = NSColor(red: 1.0, green: 0.30, blue: 0.28, alpha: 1)
  static let green = NSColor(red: 0.38, green: 0.86, blue: 0.55, alpha: 1)
  static let violet = NSColor(red: 0.70, green: 0.52, blue: 1.0, alpha: 1)

  /// The agents' colours, as in the headset (Palette.role).
  static func role(_ r: String) -> NSColor { Palette.role(r) }
}

enum BaseSceneText {
  static func firstSentence(_ s: String) -> String { BaseScene.firstSentence(s) }
}
