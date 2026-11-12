// Renders Belfry's app icon into the asset catalog: a glowing bell tower in deep space.
// Usage: swift scripts/make-icon.swift Belfry/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

    // Deep-space squircle with nebula glows.
    let bg = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [hex(0x16213A), hex(0x070A10)])!.draw(in: bg, relativeCenterPosition: NSPoint(x: -0.2, y: 0.5))
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    let cg = NSGraphicsContext.current!.cgContext
    func nebula(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: NSColor) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        cg.drawRadialGradient(gradient, startCenter: p(x, y), startRadius: 0, endCenter: p(x, y), endRadius: radius * s, options: [])
    }
    nebula(300, 800, 420, hex(0x2B3C5E, 0.75))
    nebula(800, 420, 380, hex(0x1D3B48, 0.6))
    nebula(380, 200, 340, hex(0x9CC3FF, 0.12))
    var rng = LCG(s: 0xBE11F7)
    for _ in 0..<70 {
        let x = 110 + rng.next() * 800, y = 110 + rng.next() * 800, d = 3 + rng.next() * 7
        hex(0xFFFFFF, 0.35 + rng.next() * 0.55).setFill()
        NSBezierPath(ovalIn: r(x, y, d, d)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Glow under everything that follows.
    let glow = NSShadow()
    glow.shadowColor = hex(0x9CC3FF, 0.75)
    glow.shadowBlurRadius = 40 * s
    glow.shadowOffset = .zero

    // Tower: pointed roof, belfry arch, base.
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    hex(0x2A3550).setFill()
    let roof = NSBezierPath()
    roof.move(to: p(512, 820)); roof.line(to: p(700, 640)); roof.line(to: p(324, 640)); roof.close()
    roof.fill()
    let frame = NSBezierPath(rect: r(350, 310, 324, 330))
    let arch = NSBezierPath()
    arch.move(to: p(398, 310)); arch.line(to: p(398, 505))
    arch.appendArc(withCenter: p(512, 505), radius: 114 * s, startAngle: 180, endAngle: 0, clockwise: true)
    arch.line(to: p(626, 310)); arch.close()
    frame.append(arch.reversed)
    frame.windingRule = .evenOdd
    frame.fill()
    NSBezierPath(roundedRect: r(306, 248, 412, 68), xRadius: 14 * s, yRadius: 14 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Aurora bell.
    let bell = NSBezierPath()
    bell.move(to: p(512, 590))
    bell.curve(to: p(584, 474), controlPoint1: p(558, 590), controlPoint2: p(584, 542))
    bell.curve(to: p(622, 390), controlPoint1: p(584, 426), controlPoint2: p(622, 416))
    bell.line(to: p(402, 390))
    bell.curve(to: p(440, 474), controlPoint1: p(402, 416), controlPoint2: p(440, 426))
    bell.curve(to: p(512, 590), controlPoint1: p(440, 542), controlPoint2: p(466, 590))
    bell.close()
    NSGraphicsContext.saveGraphicsState()
    let bellGlow = NSShadow()
    bellGlow.shadowColor = hex(0xC9DDFF, 1)
    bellGlow.shadowBlurRadius = 36 * s
    bellGlow.shadowOffset = .zero
    bellGlow.set()
    hex(0xC9DDFF).setFill()
    bell.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [hex(0xFFFFFF), hex(0xC9DDFF), hex(0x7F9CC9)])!.draw(in: bell, angle: -70)
    NSGradient(colors: [hex(0xFFFFFF), hex(0x9CC3FF)])!.draw(in: NSBezierPath(ovalIn: r(487, 344, 50, 50)), angle: -60)

    // Signal arcs: purple inside, cyan outside.
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    for (radius, color) in [(215.0, hex(0xC9DDFF)), (278.0, hex(0x9CC3FF, 0.6))] {
        for (start, end) in [(-28.0, 28.0), (152.0, 208.0)] {
            let wave = NSBezierPath()
            wave.appendArc(withCenter: p(512, 475), radius: radius * s, startAngle: start, endAngle: end)
            wave.lineWidth = 26 * s
            wave.lineCapStyle = .round
            color.setStroke()
            wave.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    // A thin rim of light on the squircle.
    hex(0xFFFFFF, 0.14).setStroke()
    bg.lineWidth = 4 * s
    bg.stroke()

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
