import AppKit
import SwiftUI

/// Belfry's deep-space look: a dark canvas with nebula glow and stars, glass surfaces, an aurora gradient for the
/// one primary action, and GitHub's familiar state colours (open green, merged purple, failed red) as light sources.
/// The panel is always dark by design; text colours are chosen for at least 4.5:1 on `canvas`.
enum Theme {
    static let canvas = Color(hex: "#070B14")
    static let text = Color(hex: "#E6EDF3")
    static let secondaryText = Color(hex: "#9AA4B2")
    static let tertiaryText = Color(hex: "#7D8794")
    static let glass = Color.white.opacity(0.045)
    static let glassStrong = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.09)
    static let hairlineStrong = Color.white.opacity(0.16)

    static let accent = Color(hex: "#58A6FF")
    static let open = Color(hex: "#3FB950")
    static let merged = Color(hex: "#A371F7")
    static let danger = Color(hex: "#FF6B63")
    static let attention = Color(hex: "#E3B341")
    static let cyan = Color(hex: "#39D0E6")

    static let aurora = LinearGradient(colors: [Color(hex: "#A371F7"), Color(hex: "#6E7BFF"), Color(hex: "#39D0E6")],
                                       startPoint: .leading, endPoint: .trailing)
    static let auroraDiagonal = LinearGradient(colors: [Color(hex: "#A371F7"), Color(hex: "#58A6FF"), Color(hex: "#39D0E6")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum Spacing {
    static let gutter: CGFloat = 14
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

// MARK: - Space background

/// Deep-space canvas: nebula glows and a slowly twinkling starfield (static under Reduce Motion).
struct SpaceBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.canvas
            RadialGradient(colors: [Color(hex: "#6E40C9").opacity(0.32), .clear], center: UnitPoint(x: 0.08, y: 0.0),
                           startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color(hex: "#1F6FEB").opacity(0.24), .clear], center: UnitPoint(x: 0.95, y: 0.12),
                           startRadius: 0, endRadius: 240)
            RadialGradient(colors: [Color(hex: "#39D0E6").opacity(0.10), .clear], center: UnitPoint(x: 0.6, y: 1.05),
                           startRadius: 0, endRadius: 300)
            if reduceMotion {
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

/// Seeded stars, so the sky is the same every time it opens.
struct StarField: View {
    let time: TimeInterval
    private static let stars: [(x: Double, y: Double, r: Double, phase: Double)] = {
        var generator = SeededGenerator(seed: 0xBE11F7)
        return (0..<90).map { _ in
            (Double.random(in: 0...1, using: &generator), Double.random(in: 0...1, using: &generator),
             Double.random(in: 0.35...1.1, using: &generator), Double.random(in: 0...(2 * .pi), using: &generator))
        }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let twinkle = 0.55 + 0.45 * sin(time * 0.9 + star.phase)
                let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.r * 2, height: star.r * 2)
                context.opacity = 0.25 + 0.5 * twinkle * (star.r / 1.1)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
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

// MARK: - Surfaces

extension View {
    /// Frosted glass with a hairline border.
    func glass(cornerRadius: CGFloat = 10, strong: Bool = false) -> some View {
        // Tinted, mostly opaque glass: the nebula glows through, individual stars don't cross text.
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(hex: "#0C1220").opacity(0.82)))
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(strong ? Theme.glassStrong : Theme.glass))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(strong ? Theme.hairlineStrong : Theme.hairline))
    }

    /// A soft coloured glow, used on state icons and the primary button.
    func glow(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.55), radius: radius)
    }
}

// MARK: - Buttons

/// The one aurora call to action per screen, with a sheen that sweeps across on hover.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, height: height, enabled: isEnabled)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let height: CGFloat
    let enabled: Bool
    @State private var sheen: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Theme.aurora)
                    .overlay(
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width * 0.45)
                                .offset(x: sheen * geo.size.width)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22)))
            .glow(Color(hex: "#6E7BFF"), radius: enabled ? 8 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
            .saturation(enabled ? 1 : 0.2)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside, enabled, !reduceMotion else { return }
                sheen = -0.5
                withAnimation(.easeInOut(duration: 0.7)) { sheen = 1.1 }
            }
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
            .padding(.horizontal, 10)
            .frame(height: height)
            .glass(cornerRadius: 7, strong: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Square glass icon button for row and header actions.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var tint: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .glass(cornerRadius: 8, strong: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Small pieces

/// A keycap with a lit bottom edge.
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
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 3)
            }
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
            .foregroundStyle(lit ? .white : Theme.secondaryText)
            .contentTransition(.numericText(value: Double(count)))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 17)
            .background(Capsule().fill(lit ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Theme.glassStrong)))
    }
}

/// A GitHub-style label pill tinted by meaning.
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
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.45)))
    }
}

/// A branch name, monospaced, as GitHub shows refs.
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
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.13)))
    }
}

/// A five-by-five mirrored identicon drawn locally from a login, so people are recognisable without loading images.
struct Identicon: View {
    let login: String
    var size: CGFloat = 16

    var body: some View {
        let hash = login.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        let color = Color(hue: hue, saturation: 0.65, brightness: 0.95)
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
        .background(Circle().fill(Color.white.opacity(0.08)))
        .clipShape(Circle())
        .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 0.75))
        .accessibilityHidden(true)
    }
}

/// Small uppercase label.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.secondaryText)
    }
}
