import Foundation
import Metal
import simd

/// Thin Swift wrapper over the Google Cardboard C SDK: head tracking, lens profile,
/// per-eye matrices and the Metal distortion pass.
final class CardboardSession {
  /// Official Cardboard V2 (I/O 2015) viewer profile, from Google's GVR docs
  /// (GvrCardboardHelpers.SetViewerProfile example). Used when no viewer QR was scanned,
  /// because the SDK's own fallback is the older V1 profile.
  static let cardboardV2URI = "https://google.com/cardboard/cfg?p=CgZHb29nbGUSEkNhcmRib2FyZCBJL08gMjAxNR0rGBU9JQHegj0qEAAASEIAAEhCAABIQgAASEJYADUpXA89OggeZnc-Ej6aPlAAYAM"

  private(set) var headTracker: OpaquePointer?
  private var lens: OpaquePointer?
  private var distortion: OpaquePointer?
  private var paramsChangedCount: Int32 = -1

  private(set) var eyeFromHead: [simd_float4x4] = [matrix_identity_float4x4, matrix_identity_float4x4]
  private(set) var projection: [simd_float4x4] = [matrix_identity_float4x4, matrix_identity_float4x4]
  private(set) var width: Int32 = 0
  private(set) var height: Int32 = 0
  let zNear: Float = 0.05
  let zFar: Float = 60_000

  init() {
    headTracker = CardboardHeadTracker_create()
  }

  deinit {
    if let d = distortion { CardboardDistortionRenderer_destroy(d) }
    if let l = lens { CardboardLensDistortion_destroy(l) }
    if let h = headTracker { CardboardHeadTracker_destroy(h) }
  }

  var ready: Bool { lens != nil && distortion != nil }

  func resume() { if let h = headTracker { CardboardHeadTracker_resume(h) } }
  func pause() { if let h = headTracker { CardboardHeadTracker_pause(h) } }
  func recenter() { if let h = headTracker { CardboardHeadTracker_recenter(h) } }

  /// Makes sure a viewer profile is saved; returns true when one exists.
  @discardableResult
  func ensureDeviceParams() -> Bool {
    var buf: UnsafeMutablePointer<UInt8>?
    var size: Int32 = 0
    CardboardQrCode_getSavedDeviceParams(&buf, &size)
    if let b = buf { CardboardQrCode_destroy(b) }
    if size > 0 { return true }
    let uri = Array(Self.cardboardV2URI.utf8)
    uri.withUnsafeBufferPointer { CardboardQrCode_saveDeviceParams($0.baseAddress, Int32($0.count)) }
    return false
  }

  func scanViewerQR() { CardboardQrCode_scanQrCodeAndSaveDeviceParams() }

  var paramsChanged: Bool { paramsChangedCount != CardboardQrCode_getDeviceParamsChangedCount() }

  /// (Re)builds lens distortion + distortion renderer for a landscape screen in pixels.
  func configure(device: MTLDevice, colorFormat: MTLPixelFormat, screenWidth: Int32, screenHeight: Int32) -> Bool {
    var buf: UnsafeMutablePointer<UInt8>?
    var size: Int32 = 0
    CardboardQrCode_getSavedDeviceParams(&buf, &size)
    defer { if let b = buf { CardboardQrCode_destroy(b) } }
    guard size > 0, let params = buf else { return false }

    if let l = lens { CardboardLensDistortion_destroy(l) }
    lens = CardboardLensDistortion_create(params, size, screenWidth, screenHeight)
    guard let lens else { return false }
    width = screenWidth
    height = screenHeight

    for (i, eye) in [kLeft, kRight].enumerated() {
      var m = [Float](repeating: 0, count: 16)
      m.withUnsafeMutableBufferPointer { CardboardLensDistortion_getEyeFromHeadMatrix(lens, eye, $0.baseAddress) }
      eyeFromHead[i] = Self.matrix(m)
      m.withUnsafeMutableBufferPointer { CardboardLensDistortion_getProjectionMatrix(lens, eye, zNear, zFar, $0.baseAddress) }
      projection[i] = Self.matrix(m)
    }

    if distortion == nil {
      var cfg = CardboardMetalDistortionRendererConfig(
        mtl_device: UInt64(UInt(bitPattern: Unmanaged.passUnretained(device as AnyObject).toOpaque())),
        color_attachment_pixel_format: UInt64(colorFormat.rawValue),
        depth_attachment_pixel_format: UInt64(MTLPixelFormat.invalid.rawValue),
        stencil_attachment_pixel_format: UInt64(MTLPixelFormat.invalid.rawValue))
      distortion = CardboardMetalDistortionRenderer_create(&cfg)
    }
    guard let distortion else { return false }
    var leftMesh = CardboardMesh()
    var rightMesh = CardboardMesh()
    CardboardLensDistortion_getDistortionMesh(lens, kLeft, &leftMesh)
    CardboardLensDistortion_getDistortionMesh(lens, kRight, &rightMesh)
    CardboardDistortionRenderer_setMesh(distortion, &leftMesh, kLeft)
    CardboardDistortionRenderer_setMesh(distortion, &rightMesh, kRight)
    paramsChangedCount = CardboardQrCode_getDeviceParamsChangedCount()
    return true
  }

  /// World-to-head view matrix (as in Google's HelloCardboard), predicted 50 ms ahead.
  func headView() -> simd_float4x4 {
    guard let h = headTracker else { return matrix_identity_float4x4 }
    var pos = [Float](repeating: 0, count: 3)
    var q = [Float](repeating: 0, count: 4)
    let t = Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) + 50_000_000
    pos.withUnsafeMutableBufferPointer { p in
      q.withUnsafeMutableBufferPointer { o in
        CardboardHeadTracker_getPose(h, t, kLandscapeLeft, p.baseAddress, o.baseAddress)
      }
    }
    let rot = simd_float4x4(simd_quatf(ix: q[0], iy: q[1], iz: q[2], r: q[3]))
    var tr = matrix_identity_float4x4
    tr.columns.3 = SIMD4(pos[0], pos[1], pos[2], 1)
    return tr * rot
  }

  /// Draws both eye textures through the lens distortion into the current render encoder.
  func renderToDisplay(encoder: MTLRenderCommandEncoder, left: MTLTexture, right: MTLTexture, flipV: Bool) {
    guard let distortion else { return }
    var target = CardboardMetalDistortionRendererTargetConfig(
      render_command_encoder: UInt64(UInt(bitPattern: Unmanaged.passUnretained(encoder as AnyObject).toOpaque())),
      screen_width: width,
      screen_height: height)
    func desc(_ t: MTLTexture) -> CardboardEyeTextureDescription {
      CardboardEyeTextureDescription(
        texture: UInt64(UInt(bitPattern: Unmanaged.passUnretained(t as AnyObject).toOpaque())),
        left_u: 0, right_u: 1,
        top_v: flipV ? 0 : 1, bottom_v: flipV ? 1 : 0)
    }
    var l = desc(left)
    var r = desc(right)
    withUnsafeMutablePointer(to: &target) { tp in
      CardboardDistortionRenderer_renderEyeToDisplay(distortion, UInt64(UInt(bitPattern: tp)), 0, 0, width, height, &l, &r)
    }
  }

  static func matrix(_ m: [Float]) -> simd_float4x4 {
    // Cardboard matrices are column-major float[16], like OpenGL.
    simd_float4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]), SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
  }
}
