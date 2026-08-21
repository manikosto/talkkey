import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Authored in 1x points (660x420); rendered at 1x and 2x for the DMG's
// background .tiff so it stays crisp on Retina.
let W: CGFloat = 660, H: CGFloat = 420
let scale = CommandLine.arguments.count > 2 ? CGFloat(Int(CommandLine.arguments[2])!) : 1
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.scaleBy(x: scale, y: scale)

// Background: same near-black gradient as the app itself
let bg = CGGradient(colorsSpace: space, colors: [
    rgba(0.085, 0.085, 0.125),
    rgba(0.05, 0.05, 0.08)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// Coral glow behind where the app icon sits
let glow = CGGradient(colorsSpace: space, colors: [
    rgba(1.0, 0.35, 0.27, 0.16),
    rgba(1.0, 0.35, 0.27, 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 175, y: 205), startRadius: 0,
                       endCenter: CGPoint(x: 175, y: 205), endRadius: 210, options: [])

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          centerX: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if tracking != 0 { attrs[.kern] = tracking }
    let str = NSAttributedString(string: text, attributes: attrs)
    let width = str.size().width
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    str.draw(at: NSPoint(x: centerX - width / 2, y: y))
    NSGraphicsContext.restoreGraphicsState()
}

draw("TalkKey", size: 25, weight: .bold, color: .white, centerX: W / 2, y: 356)
draw("Drag the app into your Applications folder",
     size: 12.5, weight: .regular,
     color: NSColor(white: 1, alpha: 0.42), centerX: W / 2, y: 330)

// Arrow between the two icon slots
let arrowY: CGFloat = 205
let x0: CGFloat = 268, x1: CGFloat = 392
ctx.saveGState()
ctx.setStrokeColor(rgba(1, 1, 1, 0.28))
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: x0, y: arrowY))
ctx.addLine(to: CGPoint(x: x1 - 11, y: arrowY))
ctx.strokePath()

ctx.setFillColor(rgba(1, 1, 1, 0.28))
ctx.move(to: CGPoint(x: x1, y: arrowY))
ctx.addLine(to: CGPoint(x: x1 - 15, y: arrowY + 9))
ctx.addLine(to: CGPoint(x: x1 - 15, y: arrowY - 9))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// Footer hint
draw("Then hold Right ⌘ anywhere to dictate",
     size: 11, weight: .medium,
     color: NSColor(white: 1, alpha: 0.3), centerX: W / 2, y: 40)

let image = ctx.makeImage()!
let out = CommandLine.arguments[1]
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
