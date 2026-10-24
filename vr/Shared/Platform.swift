import CoreGraphics

/// The scene code is shared by the iOS headset app and the macOS spectator view. These are the
/// only platform differences it needs: colour, font and image types, and drawing into a bitmap
/// with a top-left origin (UIKit's convention, which every panel layout assumes).
#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage

extension NSFont {
  /// UIFont.lineHeight equivalent.
  var lineHeight: CGFloat { ceil(ascender - descender + leading) }
}

extension NSImage {
  convenience init(cgImage: CGImage) {
    self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }
}

extension NSColor {
  /// RGBA components; NSColor raises for non-RGB colours (e.g. white(alpha:)), so convert first.
  func rgba() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    let c = usingColorSpace(.sRGB) ?? self
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
  }
}
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage

extension UIColor {
  func rgba() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
  }
}
#endif

enum Bitmap {
  /// Draws into a bitmap whose origin is top-left (y down) and returns it as an image SceneKit takes.
  /// `scale` nil = the platform default (the screen scale on iOS, 1 on macOS). Safe off the main thread.
  static func image(size: CGSize, scale: CGFloat? = nil, opaque: Bool = false, _ draw: (CGContext) -> Void) -> PlatformImage {
    #if os(macOS)
    let s = scale ?? 1
    let w = max(1, Int((size.width * s).rounded())), h = max(1, Int((size.height * s).rounded()))
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info) else { return NSImage(size: size) }
    // Flip to UIKit's top-left origin so NSString drawing and rectangles land where iOS puts them.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: s, y: -s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = ctx.makeImage() else { return NSImage(size: size) }
    return NSImage(cgImage: cg, size: size)
    #else
    // Exactly the renderers the headset used before this code was shared.
    guard let scale else { return UIGraphicsImageRenderer(size: size).image { draw($0.cgContext) } }
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = scale
    fmt.opaque = opaque
    return UIGraphicsImageRenderer(size: size, format: fmt).image { draw($0.cgContext) }
    #endif
  }
}
