import SceneKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

/// The crew scientist: a suited human kneeling at the outcrop with a hand corer, built from primitives.
/// Not one of the five agents, so it wears a neutral grey-white, never an agent colour. Its lines arrive
/// like a robot's (`robots.scientist`) and show in a speech bubble; looking at it and pressing opens the
/// credited Perseverance close-up.
final class Scientist {
  static let tagColor = PlatformColor(red: 0.84, green: 0.87, blue: 0.91, alpha: 1)
  let node = SCNNode()
  let bubble = SpeechBubble()
  private let tag = SpritePanel(width: 1.9, height: 0.17, pixelsPerMeter: 640)
  private let tagNode = SCNNode()
  private let armR = SCNNode()
  private let armL = SCNNode()
  private let spinner = SCNNode()
  private let head = SCNNode()
  private let home: SIMD3<Float>
  private let faceYaw: Float
  private var name = "Science Officer Okonkwo"
  private var suffix = ""
  private var text = ""
  private var lastSeq = -1
  private var spokeAt: TimeInterval = -100
  private var bubbleVisible = false
  private var shownText = ""
  var hovered = false { didSet { if hovered != oldValue { redrawTag() } } }
  var role: String { "scientist" }

  init(at p: SIMD3<Float>, facing yaw: Float) {
    home = p
    faceYaw = yaw
    node.simdPosition = p
    node.simdEulerAngles.y = yaw
    build()
    tagNode.addChildNode(tag.node)
    tagNode.position = SCNVector3(0, 1.72, 0)
    tag.node.scale = SCNVector3(1.5, 1.5, 1.5) // already 1.9 m wide: 1.5x reads from 5 m outdoors
    bubble.enlarge(2.4, tailLeft: false) // he is 4 m away: 2.4x (was 1.5x), placed on the judge's left (he stands at the right of the view)
    node.addChildNode(tagNode)
    redrawTag()
  }

  /// Body centre in the scene, for the gaze test.
  var worldPosition: SIMD3<Float> { home + SIMD3(0, 0.8, 0) }
  var tagPosition: SIMD3<Float> { home + SIMD3(0, 1.72, 0) }

  func setName(_ n: String?) {
    guard let n, !n.isEmpty, n != name else { return }
    name = n
    redrawTag()
  }

  private func redrawTag() {
    let label = "\(name) · Science" + (hovered ? " · tap for close-up" : "")
    tag.update(key: label) { ctx, size in
      Draw.fill(ctx, CGRect(origin: .zero, size: size), PlatformColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.92), radius: size.height / 2)
      ctx.setStrokeColor(Scientist.tagColor.withAlphaComponent(0.9).cgColor)
      ctx.setLineWidth(5)
      ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: size.height / 2 - 3, cornerHeight: size.height / 2 - 3, transform: nil))
      ctx.strokePath()
      var fs: CGFloat = 70
      var font = PlatformFont.systemFont(ofSize: fs, weight: .heavy)
      while (label as NSString).size(withAttributes: [.font: font]).width > size.width - 70, fs > 30 { fs -= 2; font = PlatformFont.systemFont(ofSize: fs, weight: .heavy) }
      let h = (label as NSString).size(withAttributes: [.font: font]).height
      _ = Draw.text(label, at: CGPoint(x: 0, y: (size.height - h) / 2), size: fs, weight: .heavy, color: Scientist.tagColor, width: size.width, align: .center)
    }
  }

  // ---------------------------------------------------------------- body

  private func m(_ c: PlatformColor, shine: Float = 0.2) -> SCNMaterial {
    let mm = SCNMaterial()
    mm.lightingModel = .blinn
    mm.diffuse.contents = c
    let (cr, cg, cb, _) = c.rgba()
    mm.emission.contents = PlatformColor(red: cr * 0.22, green: cg * 0.22, blue: cb * 0.22, alpha: 1)
    mm.specular.contents = PlatformColor(white: CGFloat(shine), alpha: 1)
    mm.shininess = 0.25
    return mm
  }

  /// A cylinder between two points (in this node's space).
  private func limb(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r: Float, _ mat: SCNMaterial) -> SCNNode {
    let len = simd_distance(a, b)
    let cyl = SCNCylinder(radius: CGFloat(r), height: CGFloat(len))
    cyl.radialSegmentCount = 10
    cyl.materials = [mat]
    let n = SCNNode(geometry: cyl)
    let holder = SCNNode()
    holder.simdPosition = (a + b) / 2
    holder.look(at: SCNVector3(b), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    n.simdEulerAngles.x = .pi / 2 // cylinder axis Y -> toward -Z of the aim node
    holder.addChildNode(n)
    return holder
  }

  private func build() {
    let suit = m(PlatformColor(red: 0.90, green: 0.89, blue: 0.86, alpha: 1))
    let shade = m(PlatformColor(red: 0.74, green: 0.73, blue: 0.70, alpha: 1))
    let slate = m(PlatformColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1))
    let dark = m(PlatformColor(white: 0.16, alpha: 1))
    let visor = m(PlatformColor(red: 0.20, green: 0.15, blue: 0.08, alpha: 1), shine: 0.95)
    visor.shininess = 0.9
    let dust = m(PlatformColor(red: 0.62, green: 0.46, blue: 0.34, alpha: 1))
    let body = SCNNode()
    node.addChildNode(body)
    // Legs: left knee down, right foot planted.
    body.addChildNode(limb([-0.13, 0.52, -0.05], [-0.13, 0.10, 0.12], r: 0.085, suit))
    body.addChildNode(limb([-0.13, 0.10, 0.12], [-0.13, 0.10, -0.38], r: 0.075, shade))
    body.addChildNode(limb([0.13, 0.56, -0.03], [0.15, 0.58, 0.40], r: 0.085, suit))
    body.addChildNode(limb([0.15, 0.58, 0.40], [0.15, 0.10, 0.46], r: 0.075, shade))
    for (x, y, z) in [(Float(0.15), Float(0.05), Float(0.50)), (-0.13, 0.05, -0.42)] {
      let boot = SCNNode(geometry: SCNBox(width: 0.14, height: 0.10, length: 0.30, chamferRadius: 0.04))
      boot.geometry?.materials = [dust]
      boot.position = SCNVector3(x, y, z)
      body.addChildNode(boot)
    }
    // Torso leaning toward the rock, with a life-support pack.
    let torso = SCNNode()
    torso.position = SCNVector3(0, 0.60, 0)
    torso.simdEulerAngles.x = 0.42
    let chest = SCNNode(geometry: SCNCapsule(capRadius: 0.19, height: 0.66))
    chest.geometry?.materials = [suit]
    chest.position = SCNVector3(0, 0.30, 0)
    torso.addChildNode(chest)
    let band = SCNNode(geometry: SCNTorus(ringRadius: 0.19, pipeRadius: 0.02))
    band.geometry?.materials = [slate]
    band.position = SCNVector3(0, 0.12, 0)
    torso.addChildNode(band)
    let pack = SCNNode(geometry: SCNBox(width: 0.34, height: 0.50, length: 0.20, chamferRadius: 0.05))
    pack.geometry?.materials = [shade]
    pack.position = SCNVector3(0, 0.34, -0.25)
    torso.addChildNode(pack)
    let chestBox = SCNNode(geometry: SCNBox(width: 0.14, height: 0.10, length: 0.04, chamferRadius: 0.01))
    chestBox.geometry?.materials = [slate]
    chestBox.position = SCNVector3(0, 0.40, 0.19)
    torso.addChildNode(chestBox)
    // Helmet: shell, visor, neck ring.
    head.position = SCNVector3(0, 0.80, 0.05)
    let shell = SCNNode(geometry: SCNSphere(radius: 0.19))
    shell.geometry?.materials = [suit]
    head.addChildNode(shell)
    let vis = SCNNode(geometry: SCNSphere(radius: 0.15))
    vis.geometry?.materials = [visor]
    vis.position = SCNVector3(0, 0, 0.09)
    vis.scale = SCNVector3(1.0, 0.78, 0.8)
    head.addChildNode(vis)
    torso.addChildNode(head)
    body.addChildNode(torso)
    // Arms hang from the shoulders. The right arm works the corer; the left holds a sample bag near the ground.
    armR.position = SCNVector3(0.26, 1.10, 0.14)
    armR.addChildNode(limb([0, 0, 0], [0.04, -0.24, 0.18], r: 0.06, suit))
    armR.addChildNode(limb([0.04, -0.24, 0.18], [0.04, -0.20, 0.44], r: 0.055, shade))
    // The corer: a tube with an orange handle, pointing down at the rock.
    spinner.position = SCNVector3(0.04, -0.20, 0.46)
    let handle = SCNNode(geometry: SCNBox(width: 0.07, height: 0.12, length: 0.07, chamferRadius: 0.02))
    handle.geometry?.materials = [m(PlatformColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 1))]
    spinner.addChildNode(handle)
    let tube = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 0.40))
    tube.geometry?.materials = [m(PlatformColor(white: 0.7, alpha: 1), shine: 0.7)]
    tube.position = SCNVector3(0, -0.24, 0)
    spinner.addChildNode(tube)
    armR.addChildNode(spinner)
    body.addChildNode(armR)
    armL.position = SCNVector3(-0.26, 1.08, 0.12)
    armL.addChildNode(limb([0, 0, 0], [-0.04, -0.34, 0.10], r: 0.06, suit))
    armL.addChildNode(limb([-0.04, -0.34, 0.10], [-0.06, -0.62, 0.30], r: 0.055, shade))
    let bag = SCNNode(geometry: SCNBox(width: 0.18, height: 0.16, length: 0.12, chamferRadius: 0.04))
    bag.geometry?.materials = [dark]
    bag.position = SCNVector3(-0.07, -0.70, 0.32)
    armL.addChildNode(bag)
    body.addChildNode(armL)
    // Sampling: the right arm dips the corer to the rock and lifts, in bursts; the tube twists; the left arm steadies.
    let dip = SCNAction.rotateBy(x: 0.22, y: 0, z: 0, duration: 0.45)
    dip.timingMode = .easeInEaseOut
    let lift = dip.reversed()
    armR.runAction(.repeatForever(.sequence([.wait(duration: 0.8), dip, lift, dip, lift, dip, lift, .wait(duration: 1.6)])))
    spinner.runAction(.repeatForever(.sequence([.wait(duration: 0.8), .rotateBy(x: 0, y: .pi * 6, z: 0, duration: 2.7), .wait(duration: 1.6)])))
    armL.runAction(.repeatForever(.sequence([.rotateBy(x: 0.06, y: 0, z: 0, duration: 1.7), .rotateBy(x: -0.06, y: 0, z: 0, duration: 1.7)])))
    // Helmet follows the work.
    head.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0.18, z: 0, duration: 2.2), .rotateBy(x: 0, y: -0.18, z: 0, duration: 2.2)])))
    // Soft grounding shadow (a dark disc, no real shadows).
    let sh = SCNNode(geometry: SCNPlane(width: 1.5, height: 1.5))
    let sm = SCNMaterial()
    sm.lightingModel = .constant
    sm.diffuse.contents = Bitmap.image(size: CGSize(width: 64, height: 64), scale: 1, opaque: false) { ctx in
      let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [PlatformColor(red: 0.1, green: 0.05, blue: 0.03, alpha: 0.55).cgColor, PlatformColor(red: 0.1, green: 0.05, blue: 0.03, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
      ctx.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
    }
    sm.blendMode = .alpha
    sm.writesToDepthBuffer = false
    sh.geometry?.materials = [sm]
    sh.eulerAngles.x = -.pi / 2
    sh.position = SCNVector3(0, 0.03, 0)
    sh.renderingOrder = 35
    node.addChildNode(sh)
  }

  // ---------------------------------------------------------------- speech

  func hear(text: String, seq: Int, now: TimeInterval) {
    guard seq != lastSeq else { return }
    lastSeq = seq
    self.text = text
    spokeAt = now
  }

  func isSpeaking(now: TimeInterval) -> Bool { now - spokeAt < 9 && !text.isEmpty }

  func update(now: TimeInterval, user: SIMD3<Float>, bubbleWanted: Bool) {
    // Nametag turns to the viewer, upright.
    let toUser = user - home
    let yawUser = atan2(toUser.x, toUser.z)
    tagNode.simdEulerAngles.y = yawUser - node.simdEulerAngles.y
    // The scientist looks up at whoever is looking at them while speaking.
    let speaking = isSpeaking(now: now) && bubbleWanted
    if speaking != bubbleVisible {
      bubbleVisible = speaking
      bubble.node.removeAllActions()
      if speaking {
        bubble.node.isHidden = false
        bubble.node.runAction(.fadeIn(duration: 0.2))
      } else {
        bubble.node.runAction(.sequence([.fadeOut(duration: 0.4), .hide()]))
      }
    }
    guard speaking else { return }
    // Beside the figure, toward the viewer's right, above the work.
    var radial = SIMD3(home.x - user.x, 0, home.z - user.z)
    radial = simd_length(radial) > 0.01 ? simd_normalize(radial) : SIMD3(0, 0, -1)
    let right = SIMD3<Float>(-radial.z, 0, radial.x)
    let w = Float(SpeechBubble.w)
    let c = home - right * (w / 2 + 1.2) - radial * 0.1 + SIMD3(0, 1.7, 0) // the bubble grows upward from its lower edge: lift it clear of the boulder
    bubble.node.simdPosition = c
    let tu = user - c
    bubble.node.simdEulerAngles = SIMD3(0, atan2(tu.x, tu.z), 0)
    if shownText != text {
      shownText = text
      bubble.set(text: text, name: name, color: Scientist.tagColor, deny: false, tailLeft: false, key: "sci|\(text)")
    }
  }
}
