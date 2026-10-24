import SceneKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Free roam outside: floating station pills the judge can gaze at and press ("Cargo", "Scientist", "Solar field",
/// "Rover · reality check"). Each pill is a billboard whose size grows with distance, so it always reads about 13 degrees wide.
/// Shown only while the judge picks stations (not in the director's fixed order, not at the storm door).
final class StationMarkers {
  struct Marker {
    let id: String // the `vr_station` id
    let label: String
    let world: SIMD3<Float>
    let color: PlatformColor
    let panel: SpritePanel
    let holder = SCNNode()
    var hovered = false
    var shownHere = false
  }

  private(set) var markers: [Marker] = []
  private let root = SCNNode()
  private static let width: CGFloat = 3.4, height: CGFloat = 0.62

  init(scene: SCNScene, ground: (Float, Float) -> Float) {
    func at(_ p: SIMD2<Float>, up: Float) -> SIMD3<Float> { SIMD3(p.x, ground(p.x, p.y) + up, p.y) }
    let defs: [(String, String, SIMD3<Float>, PlatformColor)] = [
      ("pad", "Cargo", at(Spots.crates, up: 4.0), Palette.green),
      ("science", "Scientist", at(Spots.scientist, up: 3.2), Palette.amber),
      ("solar", "Solar field", at(SIMD2(-18, -31), up: 4.2), Palette.cyan),
      ("rover", "Rover · reality check", at(Spots.roverPos, up: 4.2), Palette.violet),
    ]
    for (id, label, w, c) in defs {
      let panel = SpritePanel(width: Self.width, height: Self.height, pixelsPerMeter: 190)
      var m = Marker(id: id, label: label, world: w, color: c, panel: panel)
      m.holder.simdPosition = w
      m.holder.constraints = [{ let b = SCNBillboardConstraint(); b.freeAxes = .Y; return b }()]
      panel.node.renderingOrder = 3000
      panel.node.geometry?.firstMaterial?.readsFromDepthBuffer = false
      m.holder.addChildNode(panel.node)
      m.holder.isHidden = true
      root.addChildNode(m.holder)
      markers.append(m)
      Self.draw(panel, label: label, color: c, hovered: false)
    }
    scene.rootNode.addChildNode(root)
  }

  private static func draw(_ p: SpritePanel, label: String, color: PlatformColor, hovered: Bool) {
    p.update(key: "\(label)|\(hovered)") { ctx, size in
      let r = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
      let path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
      ctx.addPath(path)
      ctx.setFillColor(hovered ? color.withAlphaComponent(0.96).cgColor : PlatformColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 0.82).cgColor)
      ctx.fillPath()
      ctx.addPath(path)
      ctx.setStrokeColor(color.cgColor)
      ctx.setLineWidth(hovered ? 8 : 5)
      ctx.strokePath()
      _ = Draw.text(label, at: CGPoint(x: 0, y: size.height * 0.17), size: size.height * 0.5, weight: .heavy, color: hovered ? PlatformColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1) : Palette.text, width: size.width, align: .center)
    }
  }

  /// Per frame: visibility, size by distance, hover. `current` is the station the judge stands at (its pill is hidden, except the
  /// rover's, which at the rover reads "Tap: reality check").
  func update(eye: SIMD3<Float>, visible: Bool, current: String?) {
    for m in markers {
      let show = visible && (m.id != current || m.id == "rover")
      m.holder.isHidden = !show
      guard show else { continue }
      m.holder.simdScale = SIMD3(repeating: max(3, simd_distance(m.world, eye)) / 14)
    }
  }

  func hideAll() { for m in markers { m.holder.isHidden = true } }

  /// The pill under the reticle (or nil): redraws the pills whose highlight or label changed.
  func setHover(_ id: String?, current: String?) {
    for i in markers.indices {
      let m = markers[i]
      let hov = id == m.id
      let here = m.id == current
      if hov != m.hovered || here != m.shownHere {
        markers[i].hovered = hov
        markers[i].shownHere = here
        Self.draw(m.panel, label: here ? "Tap: reality check" : m.label, color: m.color, hovered: hov)
      }
    }
  }

  /// Distance along the ray to the nearest visible pill under the reticle (generous: the pill's half-width, a bit taller).
  func hit(origin: SIMD3<Float>, fwd: SIMD3<Float>) -> (id: String, d: Float)? {
    var best: (String, Float)?
    for m in markers where !m.holder.isHidden {
      let c = m.world
      let t = simd_dot(c - origin, fwd)
      guard t > 1, t < 80 else { continue }
      let s = Float(max(3, simd_distance(c, origin)) / 14)
      guard simd_length(c - (origin + fwd * t)) < 1.5 * s else { continue }
      if t < (best?.1 ?? .infinity) { best = (m.id, t) }
    }
    return best
  }
}
