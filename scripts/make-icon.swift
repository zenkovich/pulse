// Draws the app icon and writes an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Pulse.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    // Apple's icon grid: an 824pt body centred in 1024, continuous corners.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: color(0x000000, 0.35).cgColor)
    color(0x0e1626).setFill()
    shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [color(0x1b2a45), color(0x0b1220)])!.draw(in: body, angle: -90)

    // Faint chart grid.
    color(0xffffff, 0.06).setStroke()
    for i in 1..<6 {
        let y = body.minY + body.height * CGFloat(i) / 6
        let line = NSBezierPath()
        line.move(to: CGPoint(x: body.minX, y: y))
        line.line(to: CGPoint(x: body.maxX, y: y))
        line.lineWidth = 3 * s
        line.stroke()
    }

    // Per-core bars along the bottom, like the menu bar "cores" icon.
    let bars: [CGFloat] = [0.20, 0.32, 0.18, 0.26, 0.55, 0.72, 0.48, 0.64, 0.40, 0.58]
    let barWidth = 44 * s, gap = 22 * s
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    var x = body.midX - totalWidth / 2
    for value in bars {
        let h = 230 * s * value
        let rect = CGRect(x: x, y: body.minY + 92 * s, width: barWidth, height: h)
        color(0x3987e5, 0.35).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10 * s, yRadius: 10 * s).fill()
        x += barWidth + gap
    }

    // The pulse line.
    let points: [(CGFloat, CGFloat)] = [(0.10, 0.56), (0.30, 0.56), (0.38, 0.47), (0.46, 0.80), (0.55, 0.30),
                                        (0.63, 0.62), (0.69, 0.56), (0.90, 0.56)]
    let path = CGMutablePath()
    for (i, p) in points.enumerated() {
        let point = CGPoint(x: body.minX + body.width * p.0, y: body.minY + body.height * p.1)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * s, color: color(0x3987e5, 0.9).cgColor)
    ctx.addPath(path)
    ctx.setLineWidth(46 * s)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x5aa2f0).cgColor, color(0x2fd39a).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.midY),
                           end: CGPoint(x: body.maxX, y: body.midY), options: [])
    ctx.restoreGState()

    // End dot with a ring in the background color.
    let end = CGPoint(x: body.minX + body.width * 0.90, y: body.minY + body.height * 0.56)
    color(0x0f1a2d).setFill()
    NSBezierPath(ovalIn: CGRect(x: end.x - 46 * s, y: end.y - 46 * s, width: 92 * s, height: 92 * s)).fill()
    color(0x2fd39a).setFill()
    NSBezierPath(ovalIn: CGRect(x: end.x - 32 * s, y: end.y - 32 * s, width: 64 * s, height: 64 * s)).fill()
    ctx.restoreGState()
}

let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                              ("512x512@2x", 1024)]
for (name, pixels) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    drawIcon(in: context.cgContext, size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(name).png"))
}
