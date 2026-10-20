// Renders the 1024px app icon: three glowing arcs (CPU, memory, GPU) on a dark squircle.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid: 824px body centred in 1024 with a soft drop shadow.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(squircle)
ctx.setFillColor(color(0x0B0D18))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x1B2040), color(0x07080F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: size / 2, y: body.maxY), end: CGPoint(x: size / 2, y: body.minY), options: [])
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x22D3EE, 0.28), color(0x22D3EE, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size * 0.7, y: size * 0.72), startRadius: 0,
                       endCenter: CGPoint(x: size * 0.7, y: size * 0.72), endRadius: 520, options: [])
ctx.restoreGState()

let center = CGPoint(x: size / 2, y: size / 2)
let rings: [(radius: CGFloat, fraction: CGFloat, colors: [UInt32])] = [
    (300, 0.78, [0x22D3EE, 0x3B82F6]),
    (215, 0.62, [0xE879F9, 0x8B5CF6]),
    (130, 0.48, [0xFCD34D, 0xF97316]),
]
let line: CGFloat = 56
for ring in rings {
    // Track
    ctx.setLineWidth(line)
    ctx.setStrokeColor(color(0xFFFFFF, 0.06))
    ctx.addArc(center: center, radius: ring.radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Arc, clockwise from 12 o'clock, stroked into a mask then filled with its gradient.
    let start = CGFloat.pi / 2
    let end = start - .pi * 2 * ring.fraction
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: ring.radius, startAngle: start, endAngle: end, clockwise: true)
    let stroked = arc.copy(strokingWithWidth: line, lineCap: .round, lineJoin: .round, miterLimit: 10)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: color(ring.colors[1], 0.85))
    ctx.addPath(stroked)
    ctx.setFillColor(color(ring.colors[1]))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: ring.colors.map { color($0) } as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: center.x - ring.radius, y: center.y + ring.radius),
                           end: CGPoint(x: center.x + ring.radius, y: center.y - ring.radius), options: [])
    ctx.restoreGState()
}

// Core dot
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: color(0xFFFFFF, 0.8))
ctx.setFillColor(color(0xFFFFFF, 0.95))
ctx.fillEllipse(in: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
ctx.restoreGState()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
