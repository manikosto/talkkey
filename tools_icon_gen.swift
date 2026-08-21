import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let px = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1024
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high
// All geometry below is authored in 1024-space; scale the CTM so each
// exported size is rendered natively instead of downsampled.
let s = CGFloat(px) / 1024.0
ctx.scaleBy(x: s, y: s)

// macOS icon grid: 824x824 body centered in a 1024 canvas.
// The body doubles as a keycap — TalkKey is "hold a key and talk".
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 186
let squircle = CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// MARK: Drop shadow + base

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgba(0, 0, 0, 0.4))
ctx.addPath(squircle)
ctx.setFillColor(rgba(0.05, 0.05, 0.08))
ctx.fillPath()
ctx.restoreGState()

// MARK: Keycap side walls (outer bevel)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let wall = CGGradient(colorsSpace: space, colors: [
    rgba(0.30, 0.30, 0.38),   // lit top edge
    rgba(0.15, 0.15, 0.21),
    rgba(0.075, 0.075, 0.115) // shaded bottom
] as CFArray, locations: [0, 0.35, 1])!
ctx.drawLinearGradient(wall, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// MARK: Keycap face (inset, slightly lifted toward the top)

let faceRect = CGRect(x: 100 + 46, y: 100 + 58, width: 824 - 92, height: 824 - 92)
let faceRadius: CGFloat = 148
let face = CGPath(roundedRect: faceRect, cornerWidth: faceRadius, cornerHeight: faceRadius, transform: nil)

// Inner shadow under the face rim
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgba(0, 0, 0, 0.55))
ctx.addPath(face)
ctx.setFillColor(rgba(0.10, 0.10, 0.15))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(face)
ctx.clip()

let faceGrad = CGGradient(colorsSpace: space, colors: [
    rgba(0.155, 0.155, 0.215),
    rgba(0.085, 0.085, 0.128),
    rgba(0.055, 0.055, 0.088)
] as CFArray, locations: [0, 0.6, 1])!
ctx.drawLinearGradient(faceGrad, start: CGPoint(x: 512, y: faceRect.maxY),
                       end: CGPoint(x: 512, y: faceRect.minY), options: [])

// Coral ambient glow behind the waveform
let glow = CGGradient(colorsSpace: space, colors: [
    rgba(1.0, 0.35, 0.27, 0.30),
    rgba(1.0, 0.35, 0.27, 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 380, options: [])

// MARK: Waveform

let heights: [CGFloat] = [0.34, 0.62, 0.88, 1.0, 0.88, 0.62, 0.34]
let maxH: CGFloat = 400
let barW: CGFloat = 60
let gap: CGFloat = 38
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = 512 - total / 2

let barGrad = CGGradient(colorsSpace: space, colors: [
    rgba(1.0, 0.55, 0.38),
    rgba(1.0, 0.37, 0.28),
    rgba(0.90, 0.22, 0.36)
] as CFArray, locations: [0, 0.5, 1])!

for h in heights {
    let bh = maxH * h
    let rect = CGRect(x: x, y: 512 - bh / 2, width: barW, height: bh)
    let path = CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)

    // Glow pass
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 48, color: rgba(1.0, 0.35, 0.27, 0.6))
    ctx.addPath(path)
    ctx.setFillColor(rgba(1.0, 0.38, 0.3))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient pass
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(barGrad, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()

    x += barW + gap
}

// Face sheen
let sheen = CGGradient(colorsSpace: space, colors: [
    rgba(1, 1, 1, 0.10),
    rgba(1, 1, 1, 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: faceRect.maxY),
                       end: CGPoint(x: 512, y: faceRect.maxY - 260), options: [])

ctx.restoreGState()

// Face rim highlight — sells the keycap depth
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: faceRect.insetBy(dx: 1.5, dy: 1.5),
                   cornerWidth: faceRadius, cornerHeight: faceRadius, transform: nil))
ctx.setStrokeColor(rgba(1, 1, 1, 0.07))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// Outer hairline
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: iconRect.insetBy(dx: 2, dy: 2),
                   cornerWidth: radius - 2, cornerHeight: radius - 2, transform: nil))
ctx.setStrokeColor(rgba(1, 1, 1, 0.12))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
