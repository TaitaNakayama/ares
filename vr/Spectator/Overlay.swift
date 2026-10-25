import AppKit

/// 2D layer over the 3D view, for the people at the table: where the judge looks, what the agents
/// say, the decision in front of the judge, and how far the story has got.
/// Top-left origin; mouse events pass through to the 3D view.
final class OverlayView: NSView {
  let dot = GazeDotView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
  let subtitles = SubtitleView()
  let card = DecisionCardView()
  /// The show's three-option decision (Act 3); `card` above stays for older states with a `waiting` escalation only.
  let showCard = ShowDecisionView()
  let cue = CueHintView()
  let badges = BadgeView()
  let thinking = ThinkingView()
  let titleCard = TitleCardView()
  /// Points at the speaker when the judge isn't looking at them (the mirror shows the judge's view, not the speaker).
  let speakerArrow = SpeakerArrowView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    for v in [badges, card, showCard, cue, subtitles, thinking, titleCard, speakerArrow, dot] as [NSView] { addSubview(v) }
    card.alphaValue = 0
    showCard.alphaValue = 0
    titleCard.alphaValue = 0
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
    // The show's card sits low and compact, so the judge's view above it (and the gaze on the 3D world) stays visible.
    let showH = b.height * 0.31
    showCard.frame = NSRect(x: b.width * 0.08, y: b.height - showH - b.height * 0.025, width: b.width * 0.84, height: showH)
    cue.frame = NSRect(x: 0, y: thinking.frame.maxY + 4, width: b.width, height: max(30, b.height * 0.045))
    // Subtitles sit low; while a decision card is up they go to the top, under the cue, so nothing stacks on the card.
    let subH = b.height * 0.15
    let upCard: NSView? = showCard.isUp ? showCard : (card.isUp ? card : nil)
    let subY = upCard != nil ? cue.frame.maxY + 22 : (b.height - subH - b.height * 0.025)
    subtitles.frame = NSRect(x: b.width * 0.08, y: subY, width: b.width * 0.84, height: subH)
    subtitles.topAligned = upCard != nil
    titleCard.frame = NSRect(x: b.width * 0.05, y: b.height * 0.28, width: b.width * 0.9, height: b.height * 0.36)
    speakerArrow.frame = b
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
  /// The show's crew: colour (from `crew[id].color`) and an SF Symbol for the role icon.
  var tint: NSColor? = nil
  var symbol: String? = nil
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
  /// Stack from the top of the frame (while a decision card holds the bottom) instead of the bottom.
  var topAligned = false { didSet { if topAligned != oldValue { needsDisplay = true } } }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard !items.isEmpty else { return }
    let textSize = max(22, bounds.height * 0.24)
    let nameSize = textSize * 0.62
    var blocks: [(Subtitle, NSAttributedString, NSAttributedString, CGFloat)] = []
    let width = bounds.width - 56
    for s in items {
      let color = s.tint ?? SpectatorPalette.role(s.role)
      let name = NSMutableAttributedString(string: s.name.uppercased(), attributes: [.font: NSFont.systemFont(ofSize: nameSize, weight: .heavy), .foregroundColor: color, .kern: 1.2])
      if s.refused { name.append(NSAttributedString(string: "   REFUSED BY POLICY", attributes: [.font: NSFont.systemFont(ofSize: nameSize, weight: .heavy), .foregroundColor: SpectatorPalette.red])) }
      let para = NSMutableParagraphStyle()
      para.lineBreakMode = .byWordWrapping
      let body = NSAttributedString(string: s.text, attributes: [.font: NSFont.systemFont(ofSize: textSize, weight: .semibold), .foregroundColor: NSColor(white: 0.97, alpha: 1), .paragraphStyle: para])
      let bodyH = min(ceil(body.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]).height), textSize * 1.25 * 2)
      blocks.append((s, name, body, bodyH))
    }
    // Newest at the bottom, stacked upward (or, top-aligned, from the top edge down).
    let total = blocks.reduce(CGFloat(0)) { $0 + nameSize * 1.35 + $1.3 + 26 + 10 } - 10
    var y = topAligned ? total : bounds.height
    for (s, name, body, bodyH) in blocks.reversed() {
      let h = nameSize * 1.35 + bodyH + 26
      y -= h
      let box = NSRect(x: 0, y: y, width: bounds.width, height: h)
      NSColor(white: 0.02, alpha: 0.78).setFill()
      NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
      let accent = s.tint ?? SpectatorPalette.role(s.role)
      accent.setFill()
      NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: 10, height: box.height), xRadius: 5, yRadius: 5).fill()
      var nameX = box.minX + 28
      if let sym = s.symbol, let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: nameSize * 1.1, weight: .heavy)) {
        let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); accent.set(); r.fill(using: .sourceAtop); return true }
        let side = nameSize * 1.25
        tinted.draw(in: NSRect(x: nameX, y: box.minY + 8, width: side * img.size.width / max(1, img.size.height), height: side), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        nameX += side * img.size.width / max(1, img.size.height) + 12
      }
      name.draw(at: NSPoint(x: nameX, y: box.minY + 10))
      body.draw(with: NSRect(x: box.minX + 28, y: box.minY + 12 + nameSize * 1.35, width: width, height: bodyH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
      y -= 10
    }
  }
}

// MARK: - One line at a time (the show's `speaking`)

/// Subtitles from `speaking` only: ONE line at a time, in the speaker's colour with name and icon, held at least
/// 4 s + 0.6 s per word and until the next line replaces it (it fades 10 s after the server's hold if nothing follows).
final class SpeakingTracker {
  private(set) var current: Subtitle?
  private var seq = -1
  private var shownAt: TimeInterval = 0
  private var minHold: TimeInterval = 0
  private var holdMs: Double = 0

  static let symbols = ["wrench": "wrench.fill", "droplet": "drop.fill", "heart": "heart.fill", "microscope": "microscope", "box": "shippingbox.fill", "shield": "shield.fill"]

  func clear() { current = nil; seq = -1 }

  /// Returns true when what is on screen changed.
  func update(_ sp: VRState.Speaking?, crew: [String: VRState.Crew]?, now: TimeInterval) -> Bool {
    let before = current?.seq
    if let sp, let n = sp.seq, let text = sp.text, !text.isEmpty, n != seq {
      seq = n
      let id = sp.speaker ?? ""
      let c = crew?[id]
      let tint = ShowColors.hex(c?.color) ?? ShowColors.crew(id)
      current = Subtitle(seq: n, role: id, name: c?.name ?? ShowColors.name(id), text: text, refused: false, tint: tint, symbol: Self.symbols[c?.icon ?? ""])
      shownAt = now
      minHold = 4 + 0.6 * Double(text.split(separator: " ").count)
      holdMs = Double(sp.holdMs ?? 0)
    } else if current != nil {
      let age = now - shownAt
      if sp == nil && age >= minHold { current = nil }
      else if age > max(minHold, holdMs / 1000) + 10 { current = nil }
    }
    return current?.seq != before
  }
}

// MARK: - The cue ("look at ...")

/// A subtle hint pill under the badges naming the one glowing thing the judge is meant to look at.
final class CueHintView: NSView {
  var cue: String? { didSet { if cue != oldValue { needsDisplay = true } } }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let what: String
    var tail = ""
    switch cue {
    case "science": what = "Science"
    case "engineer": what = "Engineer"; tail = "  ·  TAP"
    case "door": what = "the door"
    case "card": what = "AN OPTION"; tail = "  ·  TAP TO CHOOSE"
    case "enter": what = "THE MARKER"; tail = "  ·  TAP TO ENTER THE SIMULATION"
    default: return
    }
    let size = max(13, bounds.height * 0.44)
    let text = NSMutableAttributedString(string: "LOOK AT  ", attributes: [.font: NSFont.systemFont(ofSize: size * 0.8, weight: .bold), .foregroundColor: NSColor(white: 0.75, alpha: 1), .kern: 1.5])
    let color: NSColor = (cue == "science" || cue == "engineer") ? ShowColors.crew(cue) : SpectatorPalette.amber
    text.append(NSAttributedString(string: what, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color]))
    if !tail.isEmpty { text.append(NSAttributedString(string: tail, attributes: [.font: NSFont.systemFont(ofSize: size * 0.8, weight: .bold), .foregroundColor: NSColor(white: 0.75, alpha: 1), .kern: 1.5])) }
    let ts = text.size()
    let box = NSRect(x: (bounds.width - ts.width) / 2 - 16, y: 0, width: ts.width + 32, height: bounds.height)
    NSColor(white: 0.02, alpha: 0.88).setFill()
    NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
    text.draw(at: NSPoint(x: box.minX + 16, y: (bounds.height - ts.height) / 2))
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

// MARK: - The show's decision (three options)

/// The enlarged decision card for the table: three options with their icons and speakers, the one the judge is gazing at
/// highlighted (amber) and the chosen one in green.
final class ShowDecisionView: NSView {
  struct Opt: Equatable { let id: String; let label: String; let icon: String; let speaker: String; let tint: NSColor; var cost: String = "" }
  /// One line under the question: why the commander has to choose.
  var reason = "Power runs out before Earth can answer." { didSet { if reason != oldValue { needsDisplay = true } } }
  private(set) var isUp = false
  private var options: [Opt] = []
  private var gazed: String?
  private var chosen: String?
  private var chosenLabel: String?
  private var hideTimer: TimeInterval?
  override var isFlipped: Bool { true }

  /// `localChosen`: the label the judge chose just now (the `vr_choice` message), shown even before the server clears the card.
  /// Returns true when the layout must change (the card appeared or went away).
  func update(_ d: VRState.Decision?, crew: [String: VRState.Crew]?, gazedFallback: Int?, localChosen: (label: String, at: TimeInterval)?, now: TimeInterval) -> Bool {
    let opts: [Opt] = (d?.options ?? []).prefix(3).map { o in
      let sp = o.speaker ?? ""
      return Opt(id: o.id, label: o.label ?? o.id, icon: o.icon ?? "", speaker: sp, tint: ShowColors.hex(crew?[sp]?.color) ?? ShowColors.crew(sp), cost: o.cost ?? "")
    }
    var dirty = false
    if !opts.isEmpty, opts != options { options = opts; dirty = true }
    var g = d?.gazed
    if g == nil, let i = gazedFallback, i < opts.count { g = opts[i].id }
    if g != gazed { gazed = g; dirty = true }
    var ch = d?.chosen
    if ch == nil, let lc = localChosen, now - lc.at < 4, let o = options.first(where: { $0.label == lc.label }) { ch = o.id }
    if ch != chosen { chosen = ch; dirty = true }
    if dirty { needsDisplay = true }
    let up = !opts.isEmpty || (ch != nil && !options.isEmpty)
    guard up != isUp else { return false }
    isUp = up
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = up ? 0.35 : 0.5
      animator().alphaValue = up ? 1 : 0
    }
    if !up { options = []; chosen = nil; gazed = nil }
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !options.isEmpty, let cg = NSGraphicsContext.current?.cgContext else { return }
    let b = bounds
    NSColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: b, xRadius: 22, yRadius: 22).fill()
    let headSize = max(16, b.height * 0.06)
    let chosenOpt = options.first { $0.id == chosen }
    let head = NSMutableAttributedString(string: chosenOpt.map { "COMMANDER CHOSE: \($0.label.uppercased())" } ?? "WHAT DO WE GIVE UP?", attributes: [.font: NSFont.systemFont(ofSize: headSize, weight: .heavy), .foregroundColor: chosenOpt != nil ? SpectatorPalette.green : SpectatorPalette.violet, .kern: 1.5])
    // Why there's a choice at all (the round-2 table reviewer saw the question without its reason).
    if chosenOpt == nil, !reason.isEmpty {
      head.append(NSAttributedString(string: "   \(reason)", attributes: [.font: NSFont.systemFont(ofSize: headSize * 0.8, weight: .semibold), .foregroundColor: NSColor(white: 0.8, alpha: 1)]))
    }
    head.draw(at: NSPoint(x: 32, y: 20))
    let top = 20 + headSize * 1.5 + 6
    let gap: CGFloat = 20
    let n = CGFloat(options.count)
    let cw = (b.width - 64 - gap * (n - 1)) / n
    let ch = b.height - top - 24
    for (i, o) in options.enumerated() {
      let r = NSRect(x: 32 + CGFloat(i) * (cw + gap), y: top, width: cw, height: ch)
      let isChosen = chosen == o.id
      let isGazed = gazed == o.id && chosen == nil
      let dim = chosen != nil && !isChosen
      (isChosen ? NSColor(red: 0.07, green: 0.20, blue: 0.11, alpha: 1) : isGazed ? NSColor(red: 0.20, green: 0.15, blue: 0.06, alpha: 1) : NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: dim ? 0.5 : 1)).setFill()
      let box = NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16)
      box.fill()
      (isChosen ? SpectatorPalette.green : isGazed ? SpectatorPalette.amber : o.tint.withAlphaComponent(dim ? 0.25 : 0.8)).setStroke()
      box.lineWidth = isChosen || isGazed ? 7 : 3
      box.stroke()
      o.tint.withAlphaComponent(dim ? 0.3 : 1).setFill()
      NSBezierPath(roundedRect: NSRect(x: r.minX + 14, y: r.minY, width: r.width - 28, height: 8), xRadius: 4, yRadius: 4).fill()
      let iconSize = min(ch * 0.30, cw * 0.4)
      DecisionCards.drawIcon(cg, kind: o.icon, center: CGPoint(x: r.midX, y: r.minY + 24 + iconSize / 2), size: iconSize, color: o.tint.withAlphaComponent(dim ? 0.35 : 1))
      let labelSize = max(15, min(ch * 0.14, cw * 0.1))
      let para = NSMutableParagraphStyle()
      para.alignment = .center
      para.lineBreakMode = .byWordWrapping
      let labelTop = r.minY + 24 + iconSize + 14
      NSAttributedString(string: o.label, attributes: [.font: NSFont.systemFont(ofSize: labelSize, weight: .heavy), .foregroundColor: NSColor(white: dim ? 0.5 : 0.97, alpha: 1), .paragraphStyle: para])
        .draw(with: NSRect(x: r.minX + 14, y: labelTop, width: r.width - 28, height: labelSize * 2.7), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
      let sp = ShowColors.name(o.speaker).uppercased()
      if !o.cost.isEmpty {
        // The tradeoff, in the speaker's colour (replaces "<NAME> WILL SAY").
        let cp = NSMutableParagraphStyle()
        cp.alignment = .center
        cp.lineBreakMode = .byWordWrapping
        let cTop = labelTop + labelSize * 2.35
        let cRect = NSRect(x: r.minX + 14, y: cTop, width: r.width - 28, height: max(10, r.maxY - labelSize * 0.9 - cTop))
        // Shrink until the whole cost fits (it was cut mid-phrase: "Fewer batteries, and they").
        var fs = labelSize * 0.66
        var cost = NSAttributedString(string: o.cost, attributes: [.font: NSFont.systemFont(ofSize: fs, weight: .heavy), .foregroundColor: o.tint.withAlphaComponent(dim ? 0.45 : 1), .paragraphStyle: cp])
        while fs > 11, cost.boundingRect(with: NSSize(width: cRect.width, height: 1000), options: [.usesLineFragmentOrigin]).height > cRect.height {
          fs -= 1
          cost = NSAttributedString(string: o.cost, attributes: [.font: NSFont.systemFont(ofSize: fs, weight: .heavy), .foregroundColor: o.tint.withAlphaComponent(dim ? 0.45 : 1), .paragraphStyle: cp])
        }
        cost.draw(with: cRect, options: [.usesLineFragmentOrigin])
      } else if !sp.isEmpty {
        NSAttributedString(string: "\(sp) WILL SAY", attributes: [.font: NSFont.systemFont(ofSize: labelSize * 0.5, weight: .heavy), .foregroundColor: o.tint.withAlphaComponent(dim ? 0.4 : 1), .kern: 1])
          .draw(at: NSPoint(x: r.minX + 16, y: r.maxY - labelSize * 0.9))
      }
      if isGazed || isChosen {
        let t = NSAttributedString(string: isChosen ? "CHOSEN" : "LOOKING", attributes: [.font: NSFont.systemFont(ofSize: labelSize * 0.55, weight: .heavy), .foregroundColor: isChosen ? SpectatorPalette.green : SpectatorPalette.amber, .kern: 1.5])
        t.draw(at: NSPoint(x: r.maxX - t.size().width - 16, y: r.maxY - labelSize * 0.9))
      }
    }
  }
}

// MARK: - Window and end titles (flat, centred)

/// "25 MINUTES LATER", "SCAM BLOCKED · $1.4M SAVED" and the end card, drawn flat over the mirror so they are always whole and
/// centred for the table, whatever the judge's head does (the headset shows them on the window glass).
final class TitleCardView: NSView {
  private var text = ""
  private var style = ""
  override var isFlipped: Bool { true }

  func set(text t: String, style st: String) {
    guard t != text || st != style else { return }
    let wasUp = !text.isEmpty
    text = t
    style = st
    needsDisplay = true
    let up = !t.isEmpty
    if up != wasUp {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = up ? 0.5 : 0.3
        animator().alphaValue = up ? 1 : 0
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !text.isEmpty else { return }
    let b = bounds
    NSColor(white: 0.02, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: b, xRadius: 26, yRadius: 26).fill()
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = .byWordWrapping
    // "SCAM BLOCKED · $1.4M SAVED" reads as two lines: the verdict in white, the amount in green.
    let parts = text.components(separatedBy: " · ")
    let out = NSMutableAttributedString()
    var size = style == "end" ? b.height * 0.17 : b.height * 0.22
    func build() {
      out.setAttributedString(NSAttributedString())
      for (i, p) in parts.enumerated() {
        if i > 0 { out.append(NSAttributedString(string: "\n")) }
        let green = i > 0 && p.contains("$")
        out.append(NSAttributedString(string: p, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: green ? SpectatorPalette.green : NSColor(white: 0.97, alpha: 1), .paragraphStyle: para, .kern: style == "end" ? 0.5 : 2]))
      }
    }
    build()
    let inner = b.insetBy(dx: 40, dy: 24)
    while size > 18, out.boundingRect(with: NSSize(width: inner.width, height: 2000), options: [.usesLineFragmentOrigin]).height > inner.height { size -= 2; build() }
    let h = out.boundingRect(with: NSSize(width: inner.width, height: 2000), options: [.usesLineFragmentOrigin]).height
    out.draw(with: NSRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h + 4), options: [.usesLineFragmentOrigin])
  }
}

// MARK: - Where the speaker is

/// A chevron at the screen edge in the speaker's colour, pointing at a speaker who is out of the judge's view.
final class SpeakerArrowView: NSView {
  /// Direction on screen (radians, 0 = right, positive = down in this flipped view), or nil when the speaker is in view.
  private var angle: CGFloat?
  private var color: NSColor = .white
  override var isFlipped: Bool { true }

  func set(angle a: CGFloat?, color c: NSColor) {
    let changed = (a == nil) != (angle == nil) || abs((a ?? 0) - (angle ?? 0)) > 0.02 || c != color
    angle = a
    color = c
    if changed { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let a = angle else { return }
    let b = bounds.insetBy(dx: 60, dy: 90)
    let c = CGPoint(x: bounds.midX, y: bounds.midY)
    // Where the ray from the centre leaves the inset rectangle.
    let dx = cos(a), dy = sin(a)
    let tx = dx == 0 ? .infinity : (dx > 0 ? b.maxX - c.x : b.minX - c.x) / dx
    let ty = dy == 0 ? .infinity : (dy > 0 ? b.maxY - c.y : b.minY - c.y) / dy
    let t = min(tx, ty)
    let p = CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    let s: CGFloat = 34
    let path = NSBezierPath()
    path.move(to: CGPoint(x: p.x + dx * s, y: p.y + dy * s))
    path.line(to: CGPoint(x: p.x - dy * s * 0.8 - dx * s * 0.4, y: p.y + dx * s * 0.8 - dy * s * 0.4))
    path.line(to: CGPoint(x: p.x + dy * s * 0.8 - dx * s * 0.4, y: p.y - dx * s * 0.8 - dy * s * 0.4))
    path.close()
    NSColor(white: 0.02, alpha: 0.85).setStroke()
    path.lineWidth = 8
    path.stroke()
    color.setFill()
    path.fill()
  }
}

// MARK: - Badges

final class BadgeView: NSView {
  enum Mode: Equatable { case live, replay, mouse, director }
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
      case .director: return ("SHOW", SpectatorPalette.violet, "camera follows the story")
      }
    }()
    let label = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.white, .kern: 2])
    let subS = NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: size * 0.62, weight: .semibold), .foregroundColor: NSColor(white: 0.85, alpha: 1)])
    let pillW = size * 0.9 + label.size().width + 30 + subS.size().width + 24
    let pill = NSRect(x: 24, y: 20, width: pillW, height: size * 1.7)
    NSColor(white: 0.02, alpha: 0.9).setFill()
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
      NSColor(white: 0.02, alpha: 0.9).setFill()
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
