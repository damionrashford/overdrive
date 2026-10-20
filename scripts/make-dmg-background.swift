// Renders the disk image background: a dark panel with the app mark, an arrow from the app slot
// to the Applications slot and one instruction. Writes 1x and 2x PNGs; package.sh joins them.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "dmg-background"
let base = CGSize(width: 660, height: 400)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(scale: CGFloat, to file: String) {
    let size = CGSize(width: base.width * scale, height: base.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.scaleBy(x: scale, y: scale)

    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x12141C), color(0x0A0B10)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: base.height), end: CGPoint(x: 0, y: 0), options: [])
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x38BDF8, 0.16), color(0x38BDF8, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 180, y: 240), startRadius: 0, endCenter: CGPoint(x: 180, y: 240), endRadius: 320, options: [])

    // Arrow between the two icon slots (icons sit at y≈190 in Finder coordinates; this is bottom-up).
    let y: CGFloat = base.height - 190
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 268, y: y))
    arrow.addLine(to: CGPoint(x: 392, y: y))
    arrow.move(to: CGPoint(x: 372, y: y + 14))
    arrow.addLine(to: CGPoint(x: 392, y: y))
    arrow.addLine(to: CGPoint(x: 372, y: y - 14))
    ctx.addPath(arrow)
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "Drag Overdrive to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.9), .paragraphStyle: paragraph])
    title.draw(in: CGRect(x: 0, y: 46, width: base.width, height: 24))
    let note = NSAttributedString(string: "If macOS blocks the first launch: System Settings › Privacy & Security › Open Anyway.", attributes: [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 1, alpha: 0.5), .paragraphStyle: paragraph])
    note.draw(in: CGRect(x: 40, y: 22, width: base.width - 80, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

render(scale: 1, to: out + ".png")
render(scale: 2, to: out + "@2x.png")
print("wrote \(out).png and \(out)@2x.png")
