import MetalKit
import SceneKit
import UIKit
import simd

/// Touch-down fires immediately: the Cardboard button is a short capacitive tap.
final class VRView: MTKView {
  var onTouchDown: (() -> Void)?
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    onTouchDown?()
  }
}

final class VRViewController: UIViewController, MTKViewDelegate {
  private var mtkView: VRView!
  private var device: MTLDevice!
  private var queue: MTLCommandQueue!
  private let cardboard = CardboardSession()
  private var scnRenderer: SCNRenderer!
  let world = BaseScene()
  private var eyeColor: [MTLTexture] = []
  private var eyeDepth: [MTLTexture] = []
  private let startTime = CACurrentMediaTime()
  private var configured = false
  /// SceneKit renders upright into the eye textures; Cardboard's UVs assume bottom-left origin.
  var flipV = false
  private(set) var link: Link!
  private var captureRequested = false
  private var poseOverride: simd_float4x4?
  // Demo-video recording: undistorted left eye, optional director camera.
  private var recording = false
  private var recordEvery = 5
  private var recordDirector = true
  private var recordTex: MTLTexture?
  private var recordFrame = 0
  private var recordInFlight = 0
  private var directorYaw: Float = 0
  private var directorPitch: Float = 0
  private static let encodeQueue = DispatchQueue(label: "ares.encode", qos: .utility)
  private var overrideFrames = 0
  private var frameCount = 0
  private var lastFpsTime = CACurrentMediaTime()
  private(set) var fps: Double = 0
  private var statsTick = 0

  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }

  override func loadView() {
    device = MTLCreateSystemDefaultDevice()
    queue = device.makeCommandQueue()
    let v = VRView(frame: UIScreen.main.bounds, device: device)
    v.colorPixelFormat = .bgra8Unorm_srgb
    v.depthStencilPixelFormat = .invalid
    v.framebufferOnly = false
    v.preferredFramesPerSecond = 60
    v.isMultipleTouchEnabled = true
    v.delegate = self
    v.onTouchDown = { [weak self] in self?.world.tap() }
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
    lp.minimumPressDuration = 2.0
    // Two fingers: the viewer's lever is a single touch, so a judge holding it can't open the camera.
    lp.numberOfTouchesRequired = 2
    v.addGestureRecognizer(lp)
    mtkView = v
    view = v
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cardboard.ensureDeviceParams()
    scnRenderer = SCNRenderer(device: device, options: nil)
    scnRenderer.scene = world.scene
    scnRenderer.pointOfView = world.eyes[0]
    scnRenderer.isJitteringEnabled = false
    link = Link(world: world)
    world.onDecide = { [weak self] escalationId, optionId in self?.link.decide(escalationId: escalationId, optionId: optionId) }
    link.onRecenter = { [weak self] in self?.cardboard.recenter() }
    link.onScanViewer = { [weak self] in self?.cardboard.scanViewerQR() }
    // "Forward" = wherever the phone faces shortly after launch (then on demand from the console).
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.cardboard.recenter() }
    link.onCaptureRequest = { [weak self] yaw, pitch in
      guard let self else { return }
      if let yaw {
        // World-to-head view for a head turned `yaw` degrees right and `pitch` up.
        let y = Float(-yaw * .pi / 180), p = Float(pitch ?? 0) * .pi / 180
        let rot = simd_quatf(angle: y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: p, axis: SIMD3(1, 0, 0))
        self.poseOverride = simd_float4x4(rot).inverse
        self.overrideFrames = 3
      }
      self.captureRequested = true
    }
    link.onRecord = { [weak self] on, fps, director in
      guard let self else { return }
      self.recording = on
      self.recordEvery = max(1, 60 / max(1, fps))
      self.recordDirector = director
      self.recordFrame = 0
    }
    link.start()
  }

  @objc private func longPress(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    cardboard.scanViewerQR()
  }

  func resume() {
    cardboard.resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.cardboard.recenter() }
    mtkView?.isPaused = false
  }

  func pause() {
    cardboard.pause()
    mtkView?.isPaused = true
  }

  private func configureIfNeeded(_ view: MTKView) {
    guard !configured || cardboard.paramsChanged else { return }
    let size = view.drawableSize
    let w = Int32(max(size.width, size.height))
    let h = Int32(min(size.width, size.height))
    guard w > 0, cardboard.configure(device: device, colorFormat: view.colorPixelFormat, screenWidth: w, screenHeight: h) else { return }
    let eyeW = Int(w) / 2
    let eyeH = Int(h)
    eyeColor = (0..<2).map { _ in makeTexture(.bgra8Unorm_srgb, eyeW, eyeH, [.renderTarget, .shaderRead]) }
    for i in 0..<2 {
      world.eyes[i].camera?.projectionTransform = SCNMatrix4(cardboard.projection[i])
      world.eyes[i].simdTransform = cardboard.eyeFromHead[i].inverse // head-from-eye, fixed
    }
    eyeDepth = (0..<2).map { _ in makeTexture(.depth32Float, eyeW, eyeH, [.renderTarget]) }
    configured = true
  }

  private func makeTexture(_ fmt: MTLPixelFormat, _ w: Int, _ h: Int, _ usage: MTLTextureUsage) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: false)
    d.usage = usage
    d.storageMode = fmt == .depth32Float ? .private : .private
    return device.makeTexture(descriptor: d)!
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    configured = false
  }

  func draw(in view: MTKView) {
    configureIfNeeded(view)
    guard configured, let cmd = queue.makeCommandBuffer() else {
      // Never a silent black screen: a dark red frame means "no viewer profile".
      if let d = view.currentDrawable, let rpd = view.currentRenderPassDescriptor, let c = queue.makeCommandBuffer() {
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.25, green: 0.02, blue: 0.02, alpha: 1)
        rpd.colorAttachments[0].loadAction = .clear
        c.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        c.present(d)
        c.commit()
      }
      return
    }
    let now = CACurrentMediaTime() - startTime
    var headView = cardboard.headView()
    if overrideFrames > 0, let o = poseOverride {
      headView = o
      overrideFrames -= 1
    } else if recording && recordDirector {
      // Director camera: ease toward whatever matters right now (speaker, cards, window).
      let (ty, tp) = world.directorTarget(now: now)
      directorYaw += (ty - directorYaw) * 0.025
      directorPitch += (tp - directorPitch) * 0.025
      let rot = simd_quatf(angle: -directorYaw * .pi / 180, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: directorPitch * .pi / 180, axis: SIMD3(1, 0, 0))
      headView = simd_float4x4(rot).inverse
    }
    world.update(time: now, headView: headView, fps: fps, link: link)

    world.head.simdTransform = (headView * world.viewOffset).inverse // world-from-head
    // SceneKit renders committed state: commit this frame's head pose (and scene updates) now,
    // or both eyes would draw the previous frame's single camera (no stereo, +1 frame latency).
    SCNTransaction.flush()
    for eye in 0..<2 {
      scnRenderer.pointOfView = world.eyes[eye]
      let rpd = MTLRenderPassDescriptor()
      rpd.colorAttachments[0].texture = eyeColor[eye]
      rpd.colorAttachments[0].loadAction = .clear
      rpd.colorAttachments[0].storeAction = .store
      rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
      rpd.depthAttachment.texture = eyeDepth[eye]
      rpd.depthAttachment.loadAction = .clear
      rpd.depthAttachment.storeAction = .dontCare
      rpd.depthAttachment.clearDepth = 1
      scnRenderer.render(atTime: now, viewport: CGRect(x: 0, y: 0, width: eyeColor[eye].width, height: eyeColor[eye].height), commandBuffer: cmd, passDescriptor: rpd)
    }

    if recording {
      recordFrame += 1
      if recordFrame % recordEvery == 0 && recordInFlight < 3 {
        let src = eyeColor[0]
        if recordTex == nil || recordTex!.width != src.width {
          let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: src.pixelFormat, width: src.width, height: src.height, mipmapped: false)
          d.storageMode = .shared
          d.usage = [.shaderRead]
          recordTex = device.makeTexture(descriptor: d)
        }
        if let dst = recordTex, let blit = cmd.makeBlitCommandEncoder() {
          blit.copy(from: src, to: dst)
          blit.endEncoding()
          recordInFlight += 1
          cmd.addCompletedHandler { [weak self] _ in self?.encodeRecorded(dst) }
        }
      }
    }

    guard let drawable = view.currentDrawable, let rpd = view.currentRenderPassDescriptor else {
      cmd.commit()
      return
    }
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].loadAction = .clear
    if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
      cardboard.renderToDisplay(encoder: enc, left: eyeColor[0], right: eyeColor[1], flipV: flipV)
      enc.endEncoding()
    }
    // With a forced pose, capture on the last overridden frame so scene updates have settled.
    let capture = captureRequested && overrideFrames == 0
    if capture { captureRequested = false; poseOverride = nil }
    let tex = drawable.texture
    if capture {
      cmd.addCompletedHandler { [weak self] _ in self?.sendCapture(tex) }
    }
    cmd.present(drawable)
    cmd.commit()

    frameCount += 1
    let t = CACurrentMediaTime()
    if t - lastFpsTime >= 1 {
      fps = Double(frameCount) / (t - lastFpsTime)
      frameCount = 0
      lastFpsTime = t
      statsTick += 1
      if statsTick % 2 == 0 {
        let e0 = world.eyes[0].simdWorldPosition, e1 = world.eyes[1].simdWorldPosition
        link.sendStats(["fps": fps, "thermal": ProcessInfo.processInfo.thermalState.rawValue, "flipV": flipV, "w": Int(cardboard.width), "h": Int(cardboard.height), "uptime": t - startTime,
                        "eyeFromHeadL": [cardboard.eyeFromHead[0].columns.3.x, cardboard.eyeFromHead[0].columns.3.y, cardboard.eyeFromHead[0].columns.3.z],
                        "eyeFromHeadR": [cardboard.eyeFromHead[1].columns.3.x, cardboard.eyeFromHead[1].columns.3.y, cardboard.eyeFromHead[1].columns.3.z],
                        "eyeSepWorld": simd_distance(e0, e1), "projL00": cardboard.projection[0].columns.0.x, "projL20": cardboard.projection[0].columns.2.x, "projR20": cardboard.projection[1].columns.2.x])
      }
    }
  }

  private func encodeRecorded(_ tex: MTLTexture) {
    let w = tex.width, h = tex.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    Self.encodeQueue.async { [weak self] in
      defer { DispatchQueue.main.async { self?.recordInFlight -= 1 } }
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info), let img = ctx.makeImage(),
            let jpg = UIImage(cgImage: img).jpegData(compressionQuality: 0.8) else { return }
      self?.link.uploadFrame(jpg)
    }
  }

  /// Debug: read back the final frame and post it to the server so it can be checked remotely.
  private func sendCapture(_ tex: MTLTexture) {
    let w = tex.width
    let h = tex.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info.rawValue), let img = ctx.makeImage() else { return }
    let ui = UIImage(cgImage: img)
    guard let jpg = ui.jpegData(compressionQuality: 0.7) else { return }
    link.uploadCapture(jpg, info: ["fps": fps, "thermal": ProcessInfo.processInfo.thermalState.rawValue])
  }
}

extension SCNMatrix4 {
  init(_ m: simd_float4x4) {
    self.init(m11: m.columns.0.x, m12: m.columns.0.y, m13: m.columns.0.z, m14: m.columns.0.w,
              m21: m.columns.1.x, m22: m.columns.1.y, m23: m.columns.1.z, m24: m.columns.1.w,
              m31: m.columns.2.x, m32: m.columns.2.y, m33: m.columns.2.z, m34: m.columns.2.w,
              m41: m.columns.3.x, m42: m.columns.3.y, m43: m.columns.3.z, m44: m.columns.3.w)
  }
}
