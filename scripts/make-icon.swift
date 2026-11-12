// Renders Belfry's app icon into the asset catalog.
// Usage: swift scripts/make-icon.swift Belfry/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

    // Squircle background: dusk indigo to deep teal.
    let bg = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.16, blue: 0.38, alpha: 1),
                        NSColor(red: 0.05, green: 0.42, blue: 0.47, alpha: 1)])!.draw(in: bg, angle: -70)

    let stone = NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
    let brass = NSColor(red: 0.98, green: 0.74, blue: 0.27, alpha: 1)

    // Tower: pointed roof, belfry arch frame, base.
    stone.setFill()
    let roof = NSBezierPath()
    roof.move(to: p(512, 830)); roof.line(to: p(705, 640)); roof.line(to: p(319, 640)); roof.close()
    roof.fill()
    let frame = NSBezierPath(rect: r(345, 300, 334, 340))
    let arch = NSBezierPath()
    arch.move(to: p(395, 300)); arch.line(to: p(395, 500))
    arch.appendArc(withCenter: p(512, 500), radius: 117 * s, startAngle: 180, endAngle: 0, clockwise: true)
    arch.line(to: p(629, 300)); arch.close()
    frame.append(arch.reversed)
    frame.windingRule = .evenOdd
    frame.fill()
    NSBezierPath(roundedRect: r(300, 236, 424, 70), xRadius: 14 * s, yRadius: 14 * s).fill()

    // Bell inside the arch.
    brass.setFill()
    let bell = NSBezierPath()
    bell.move(to: p(512, 588))
    bell.curve(to: p(586, 470), controlPoint1: p(560, 588), controlPoint2: p(586, 540))
    bell.curve(to: p(626, 382), controlPoint1: p(586, 420), controlPoint2: p(626, 410))
    bell.line(to: p(398, 382))
    bell.curve(to: p(438, 470), controlPoint1: p(398, 410), controlPoint2: p(438, 420))
    bell.curve(to: p(512, 588), controlPoint1: p(438, 540), controlPoint2: p(464, 588))
    bell.close()
    bell.fill()
    NSBezierPath(ovalIn: r(486, 336, 52, 52)).fill()

    // Sound arcs.
    brass.setStroke()
    for (radius, alpha) in [(215.0, 0.9), (275.0, 0.55)] {
        for (start, end) in [(-28.0, 28.0), (152.0, 208.0)] {
            let wave = NSBezierPath()
            wave.appendArc(withCenter: p(512, 470), radius: radius * s, startAngle: start, endAngle: end)
            wave.lineWidth = 26 * s
            wave.lineCapStyle = .round
            brass.withAlphaComponent(alpha).setStroke()
            wave.stroke()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(size: CGFloat(px)).write(to: outDir.appendingPathComponent(name))
        images.append(["size": "\(base)x\(base)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
