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
  var flipV = true
  private(set) var link: Link!
  private var captureRequested = false
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
    v.isMultipleTouchEnabled = false
    v.delegate = self
    v.onTouchDown = { [weak self] in self?.world.tap() }
    let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
    lp.minimumPressDuration = 2.0
    v.addGestureRecognizer(lp)
    mtkView = v
    view = v
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cardboard.ensureDeviceParams()
    scnRenderer = SCNRenderer(device: device, options: nil)
    scnRenderer.scene = world.scene
    scnRenderer.pointOfView = world.cameraNode
    scnRenderer.isJitteringEnabled = false
    link = Link(world: world)
    world.onDecide = { [weak self] escalationId, optionId in self?.link.decide(escalationId: escalationId, optionId: optionId) }
    link.onCaptureRequest = { [weak self] in self?.captureRequested = true }
    link.start()
  }

  @objc private func longPress(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    cardboard.scanViewerQR()
  }

  func resume() {
    cardboard.resume()
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
    guard configured, let cmd = queue.makeCommandBuffer() else { return }
    let now = CACurrentMediaTime() - startTime
    let headView = cardboard.headView()
    world.update(time: now, headView: headView, fps: fps, link: link)

    for eye in 0..<2 {
      let eyeView = cardboard.eyeFromHead[eye] * headView * world.viewOffset
      world.cameraNode.simdTransform = eyeView.inverse
      world.camera.projectionTransform = SCNMatrix4(cardboard.projection[eye])
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
    let capture = captureRequested
    captureRequested = false
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
        link.sendStats(["fps": fps, "thermal": ProcessInfo.processInfo.thermalState.rawValue, "flipV": flipV, "w": Int(cardboard.width), "h": Int(cardboard.height), "uptime": t - startTime])
      }
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
