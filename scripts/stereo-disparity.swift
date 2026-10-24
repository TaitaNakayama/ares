// Per-patch horizontal disparity between the two eyes of a Cardboard frame capture (2622x1206).
// With symmetric FOV, identical eye textures make right(x) == left(x - L) where L = lens separation in px.
// Real stereo makes near-object patches match at shifts below L (left eye sees near things further right).
import CoreGraphics
import Foundation
import ImageIO

let path = CommandLine.arguments[1]
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
let W = img.width, H = img.height
var buf = [UInt8](repeating: 0, count: W * H * 4)
let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
func lum(_ x: Int, _ y: Int) -> Float { let i = (y * W + x) * 4; return 0.299 * Float(buf[i]) + 0.587 * Float(buf[i + 1]) + 0.114 * Float(buf[i + 2]) }

let lensSep = Int((0.0639 / 0.0254 * 460).rounded())   // inter_lens_distance in px at 460 dpi
let leftCentre = Int(((Double(W) / 460 * 0.0254 - 0.0639) / 2 / 0.0254 * 460).rounded())
let patch = 48
var shifts: [Int: Int] = [:]
var textured = 0
var report: [String] = []
for py in stride(from: H / 2 - 360, through: H / 2 + 360, by: 60) {
  for px in stride(from: leftCentre - 420, through: leftCentre + 420, by: 60) {
    // skip flat patches (sky, black)
    var mean: Float = 0, sq: Float = 0
    for y in py..<(py + patch) { for x in px..<(px + patch) { let v = lum(x, y); mean += v; sq += v * v } }
    let n = Float(patch * patch); mean /= n
    let varc = sq / n - mean * mean
    if varc < 60 { continue }
    textured += 1
    var best = (s: 0, e: Float.greatestFiniteMagnitude)
    var atL: Float = 0
    for s in (lensSep - 60)...(lensSep + 20) {
      var e: Float = 0
      for y in stride(from: py, to: py + patch, by: 2) { for x in stride(from: px, to: px + patch, by: 2) { e += abs(lum(x, y) - lum(x + s, y)) } }
      if e < best.e { best = (s, e) }
      if s == lensSep { atL = e }
    }
    shifts[best.s - lensSep, default: 0] += 1
    report.append("(\(px),\(py)) d=\(best.s - lensSep) err=\(Int(best.e / 576)) errAtL=\(Int(atL / 576))")
  }
}
print("\(path.split(separator: "/").last!): \(W)x\(H), lens separation \(lensSep) px, left lens centre x=\(leftCentre), textured patches \(textured)")
print("  histogram of (best shift - lens separation): \(shifts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "))")
if CommandLine.arguments.contains("-v") { report.forEach { print("   " + $0) } }
