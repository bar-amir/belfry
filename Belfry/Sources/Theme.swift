import AppKit
import SwiftUI

/// Belfry's "starlight" look: a quiet night sky, one ice-blue accent, a moonlight-white primary action, and GitHub's
/// state colours muted so they inform rather than shout. The panel is always dark by design; every text colour
/// clears 4.5:1 on `canvas`. Glass comes from macOS itself (Liquid Glass on macOS 26 and later).
enum Theme {
    static let canvas = dyn("#F3F6FB", "#080B11")
    static let text = dyn("#1B2230", "#E8EDF3")
    static let secondaryText = dyn("#535D6D", "#9DA7B3")
    static let tertiaryText = dyn("#65707F", "#7F8996")
    static let surface = dyn("#FFFFFF", "#0E131C")
    static let glass = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.04, darkAlpha: 0.045)
    static let glassStrong = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.07, darkAlpha: 0.08)
    static let hover = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.04, darkAlpha: 0.04)
    static let hairline = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.09, darkAlpha: 0.08)
    static let hairlineStrong = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.16, darkAlpha: 0.15)
    /// Stand-in for glass where the system can't composite it (offscreen renders).
    static let glassFallback = dyn("#FFFFFF", "#182030")

    /// Ice blue: selection, focus, the tab bar.
    static let accent = dyn("#2D65C8", "#9CC3FF")
    /// The one primary button: ink by day, moonlight by night.
    static let moon = dyn("#1B2230", "#E8EDF3")
    static let onMoon = dyn("#F3F6FB", "#0B0F16")
    static let moonSheen = dyn("#FFFFFF", "#FFFFFF", lightAlpha: 0.12, darkAlpha: 0.7)
    static let moonGlow = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.18, darkAlpha: 0.18)

    static let open = dyn("#2B7148", "#7FCB97")
    static let merged = dyn("#6A49BE", "#B8A4EE")
    static let danger = dyn("#B83F35", "#EE9A93")
    static let attention = dyn("#7E5B0E", "#DCC07A")

    /// Sky glows, stars and the planet.
    static let skyGlowA = dyn("#C9DBF6", "#2B3C5E", lightAlpha: 0.9, darkAlpha: 0.45)
    static let skyGlowB = dyn("#CDE9EE", "#1D3B48", lightAlpha: 0.8, darkAlpha: 0.35)
    static let star = dyn("#6E8BB8", "#DCE7FF")
    static let ring = dyn("#1B2230", "#FFFFFF", lightAlpha: 0.18, darkAlpha: 0.14)

    /// A barely-there sheen used for titles.
    static let starlight = LinearGradient(colors: [dyn("#1B2230", "#FFFFFF"), dyn("#2D4F86", "#C9DDFF")],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    /// A colour that follows the panel's appearance.
    static func dyn(_ light: String, _ dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark).withAlphaComponent(darkAlpha) : NSColor(hex: light).withAlphaComponent(lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

/// How the panel looks: the night sky always, or night and day following macOS.
enum PanelAppearance: String, CaseIterable, Identifiable {
    case system, night
    var id: String { rawValue }
    var label: String { self == .system ? "Match system" : "Always night sky" }
}

/// One rhythm for the panel. Everything outside a card sits on `gutter`; everything inside one on `cardInset`.
enum Spacing {
    /// Outer margin: header, search, tabs, cards and the floating footer all start and end here.
    static let gutter: CGFloat = 16
    /// Inside a card: rows and the card header.
    static let cardInset: CGFloat = 14
    static let bar: CGFloat = 12
    static let section: CGFloat = 14
    static let inner: CGFloat = 10
    static let item: CGFloat = 8
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Rendering mode

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
private struct FrozenTimeKey: EnvironmentKey { static let defaultValue: TimeInterval? = nil }

extension EnvironmentValues {
    /// True while `--snapshot` renders offscreen, where system glass can't composite.
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }

    /// A fixed clock for the starfield and other ambient motion, used when rendering animation frames.
    var frozenTime: TimeInterval? {
        get { self[FrozenTimeKey.self] }
        set { self[FrozenTimeKey.self] = newValue }
    }
}

// MARK: - Glass

/// System glass where macOS has it, a frosted fallback elsewhere.
struct LiquidGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    @Environment(\.snapshotMode) private var snapshotMode

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !snapshotMode {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else if !snapshotMode {
            content
                .background(.regularMaterial, in: shape)
                .background(shape.fill(tint?.opacity(0.18) ?? .clear))
                .overlay(shape.stroke(Theme.hairlineStrong))
        } else {
            // Offscreen renders can't blur what's behind, so the stand-in is nearly opaque.
            content
                .background(shape.fill(Theme.glassFallback))
                .background(shape.fill(tint?.opacity(0.18) ?? .clear))
                .overlay(shape.stroke(LinearGradient(colors: [Theme.hairlineStrong, Theme.hairline],
                                                     startPoint: .top, endPoint: .bottom)))
        }
    }
}

extension View {
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, interactive: interactive))
    }

    /// A quiet, mostly opaque card for content (repository boxes). Glass is kept for controls that float.
    func card(cornerRadius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.surface.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.hairline))
    }

    func glow(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.45), radius: radius)
    }
}

// MARK: - Sky

/// A quiet night sky: two faint glows and a slowly twinkling starfield (still under Reduce Motion).
struct SpaceBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.frozenTime) private var frozenTime
    @AppStorage("animatedSky") private var animatedSky = true

    var body: some View {
        ZStack {
            Theme.canvas
            RadialGradient(colors: [Theme.skyGlowA, .clear], center: UnitPoint(x: 0.1, y: 0),
                           startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Theme.skyGlowB, .clear], center: UnitPoint(x: 0.95, y: 0.35),
                           startRadius: 0, endRadius: 280)
            if let frozenTime {
                StarField(time: frozenTime)
            } else if reduceMotion || !animatedSky {
                StarField(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    StarField(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct StarField: View {
    let time: TimeInterval
    private static let stars: [(x: Double, y: Double, r: Double, phase: Double)] = {
        var generator = SeededGenerator(seed: 0xBE11F7)
        return (0..<80).map { _ in
            (Double.random(in: 0...1, using: &generator), Double.random(in: 0...1, using: &generator),
             Double.random(in: 0.3...1.0, using: &generator), Double.random(in: 0...(2 * .pi), using: &generator))
        }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let twinkle = 0.55 + 0.45 * sin(time * 0.8 + star.phase)
                let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.r * 2, height: star.r * 2)
                context.opacity = 0.18 + 0.45 * twinkle * star.r
                context.fill(Path(ellipseIn: rect), with: .color(Theme.star))
            }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Buttons

/// Moonlight: the one primary action per screen.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onMoon)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(
                Capsule().fill(Theme.moon)
                    .overlay(Capsule().fill(LinearGradient(colors: [Theme.moonSheen, .clear],
                                                           startPoint: .top, endPoint: .center)))
            )
            .shadow(color: isEnabled ? Theme.moonGlow : .clear, radius: 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule())
    }
}

/// Glass with a hairline: every secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .frame(height: height)
            .liquidGlass(Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

/// A round glass icon button for row and header actions.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var tint: Color = Theme.text
    /// At rest: an outline only, so a column of them stays light. Same hit area.
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .modifier(IconSurface(quiet: quiet))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

private struct IconSurface: ViewModifier {
    let quiet: Bool
    func body(content: Content) -> some View {
        if quiet {
            content.overlay(Circle().stroke(Theme.hairlineStrong))
        } else {
            content.liquidGlass(Circle(), interactive: true)
        }
    }
}

// MARK: - Small pieces

struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: "\u{200E}" + text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.glassStrong))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairlineStrong))
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// A count that ticks when it changes.
struct Counter: View {
    let count: Int
    var lit = false

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(lit ? Theme.accent : Theme.secondaryText)
            .contentTransition(.numericText(value: Double(count)))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 17)
            .background(Capsule().fill(lit ? Theme.accent.opacity(0.16) : Theme.glassStrong))
    }
}

/// A GitHub-style label pill, tinted quietly by meaning.
struct LabelPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(color.opacity(0.10)))
            .overlay(Capsule().stroke(color.opacity(0.28)))
    }
}

struct BranchPill: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.10)))
    }
}

/// A five-by-five mirrored identicon drawn locally from a login.
struct Identicon: View {
    let login: String
    var size: CGFloat = 16

    var body: some View {
        let hash = login.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        let color = Color(hue: hue, saturation: 0.38, brightness: 0.92)
        Canvas { context, canvasSize in
            let cell = canvasSize.width / 6
            let inset = cell / 2
            for row in 0..<5 {
                for col in 0..<3 where (hash >> UInt64(row * 3 + col + 8)) & 1 == 1 {
                    for x in Set([col, 4 - col]) {
                        let rect = CGRect(x: inset + CGFloat(x) * cell, y: inset + CGFloat(row) * cell, width: cell, height: cell)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Theme.glassStrong))
        .clipShape(Circle())
        .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 0.75))
        .accessibilityHidden(true)
    }
}
