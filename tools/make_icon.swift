import AppKit
import CoreGraphics

// Usage: swift tools/make_icon.swift NavCal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Renders NavCal's 1024x1024 app icon: a calendar page with a navigation arrow on a blue gradient.
// App Store icons must be opaque, so the bitmap has no alpha channel.
let size = 1024
let out = CommandLine.arguments[1]

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let S = CGFloat(size)

// Background: deep indigo (top) to bright sky blue (bottom). CG's origin is bottom-left.
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x0EA5E9), rgb(0x1E3A8A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: S * 0.8, y: 0), end: CGPoint(x: S * 0.2, y: S), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Calendar page.
let card = CGRect(x: 192, y: 170, width: 640, height: 640)
let radius: CGFloat = 120
let cardPath = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: CGColor(gray: 0, alpha: 0.35))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(cardPath)
ctx.fillPath()
ctx.restoreGState()

// Red header band, clipped to the card's rounded top.
let headerHeight: CGFloat = 170
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
ctx.setFillColor(rgb(0xEF4444))
ctx.fill(CGRect(x: card.minX, y: card.maxY - headerHeight, width: card.width, height: headerHeight))
ctx.restoreGState()

// Binder rings poking above the header.
for x in [card.minX + 170, card.maxX - 170] {
    let ring = CGRect(x: x - 32, y: card.maxY - 60, width: 64, height: 110)
    ctx.setFillColor(rgb(0xF8FAFC))
    ctx.addPath(CGPath(roundedRect: ring, cornerWidth: 32, cornerHeight: 32, transform: nil))
    ctx.fillPath()
}

// Navigation arrow (SF Symbol "location.fill") centered in the page body.
let body = CGRect(x: card.minX, y: card.minY, width: card.width, height: card.height - headerHeight)
let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: rgb(0x2563EB))!]))
let arrow = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let arrowSize = arrow.size
let arrowRect = CGRect(x: body.midX - arrowSize.width / 2, y: body.midY - arrowSize.height / 2 - 6,
                       width: arrowSize.width, height: arrowSize.height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
arrow.draw(in: arrowRect)
NSGraphicsContext.restoreGraphicsState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(image.width)x\(image.height) alpha=\(image.alphaInfo.rawValue)")
