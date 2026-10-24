import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// void mask: near black, only below 20% of the height (the sky and horizon are never black)
var void = [Bool](repeating: false, count: w * h)
for y in Int(Double(h) * 0.2)..<h { for x in 0..<w {
  let i = (y * w + x) * 4
  if Int(px[i]) + Int(px[i+1]) + Int(px[i+2]) < 36 { void[y * w + x] = true } } }
// dilate by r px (separable box) to eat the ragged JPEG edge
func dilate(_ m: [Bool], _ r: Int) -> [Bool] {
  var a = m, b = m
  for y in 0..<h { var last = -10000
    for x in 0..<w { if m[y*w+x] { last = x }; if x - last <= r { a[y*w+x] = true } }
    last = 100000
    for x in stride(from: w-1, through: 0, by: -1) { if m[y*w+x] { last = x }; if last - x <= r { a[y*w+x] = true } } }
  for x in 0..<w { var last = -10000
    for y in 0..<h { if a[y*w+x] { last = y }; if y - last <= r { b[y*w+x] = true } }
    last = 100000
    for y in stride(from: h-1, through: 0, by: -1) { if a[y*w+x] { last = y }; if last - y <= r { b[y*w+x] = true } } }
  return b
}
let mask = dilate(void, 10)

// coarse grid of valid-pixel averages, then diffuse into the voids
let cs = 32, gw = w / cs, gh = h / cs
var sum = [Double](repeating: 0, count: gw * gh * 3), cnt = [Double](repeating: 0, count: gw * gh)
for y in 0..<(gh*cs) { for x in 0..<(gw*cs) where !mask[y*w+x] {
  let g = (y/cs) * gw + x/cs, i = (y*w+x)*4
  sum[g*3] += Double(px[i]); sum[g*3+1] += Double(px[i+1]); sum[g*3+2] += Double(px[i+2]); cnt[g] += 1 } }
var grid = [Double](repeating: 0, count: gw * gh * 3), valid = [Bool](repeating: false, count: gw * gh)
for g in 0..<(gw*gh) where cnt[g] > Double(cs*cs) * 0.5 { valid[g] = true; for c in 0..<3 { grid[g*3+c] = sum[g*3+c] / cnt[g] } }
for _ in 0..<600 {
  var n = grid
  for gy in 0..<gh { for gx in 0..<gw where !valid[gy*gw+gx] {
    var a = [Double](repeating: 0, count: 3); var k = 0.0
    for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
      let x2 = (gx + dx + gw) % gw, y2 = gy + dy
      if y2 < 0 || y2 >= gh { continue }
      let j = y2*gw+x2
      if valid[j] || (grid[j*3] + grid[j*3+1] + grid[j*3+2]) > 0 { for c in 0..<3 { a[c] += grid[j*3+c] }; k += 1 } }
    if k > 0 { for c in 0..<3 { n[(gy*gw+gx)*3+c] = a[c] / k } } } }
  grid = n
}
func sample(_ fx: Double, _ fy: Double, _ c: Int) -> Double {
  let x = min(max(fx / Double(cs) - 0.5, 0), Double(gw - 1)), y = min(max(fy / Double(cs) - 0.5, 0), Double(gh - 1))
  let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, gw - 1), y1 = min(y0 + 1, gh - 1)
  let tx = x - Double(x0), ty = y - Double(y0)
  let a = grid[(y0*gw+x0)*3+c] * (1-tx) + grid[(y0*gw+x1)*3+c] * tx
  let b = grid[(y1*gw+x0)*3+c] * (1-tx) + grid[(y1*gw+x1)*3+c] * tx
  return a * (1-ty) + b * ty
}
// feather: blurred mask weight
var wgt = [Float](repeating: 0, count: w * h)
for i in 0..<(w*h) { wgt[i] = mask[i] ? 1 : 0 }
// cheap box blur radius 6, two passes
func blur(_ a: [Float], _ r: Int) -> [Float] {
  var t = a, o = a
  for y in 0..<h { var s: Float = 0
    for x in -r..<(w+r) { if x + r < w { s += a[y*w+x+r] }; if x - r - 1 >= 0 { s -= a[y*w+x-r-1] }; if x >= 0 && x < w { t[y*w+x] = s / Float(2*r+1) } } }
  for x in 0..<w { var s: Float = 0
    for y in -r..<(h+r) { if y + r < h { s += t[(y+r)*w+x] }; if y - r - 1 >= 0 { s -= t[(y-r-1)*w+x] }; if y >= 0 && y < h { o[y*w+x] = s / Float(2*r+1) } } }
  return o
}
wgt = blur(blur(wgt, 6), 6)
var seed: UInt64 = 12345
for y in 0..<h { for x in 0..<w {
  let k = Double(wgt[y*w+x]); if k <= 0.001 { continue }
  seed = seed &* 6364136223846793005 &+ 1442695040888963407
  let noise = 0.88 + 0.12 * Double((seed >> 40) & 255) / 255
  let i = (y*w+x)*4
  for c in 0..<3 {
    let fill = sample(Double(x), Double(y), c) * 0.82 * noise
    px[i+c] = UInt8(max(0, min(255, Double(px[i+c]) * (1-k) + fill * k))) } } }
let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
CGImageDestinationFinalize(dest)
print("done", w, h)
