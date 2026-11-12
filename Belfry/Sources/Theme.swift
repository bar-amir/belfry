import AppKit
import SwiftUI

/// Belfry's palette. Quiet inside: one ink accent, warm paper for selection, and semantic colours that keep
/// their meaning everywhere (green done/approved, red failed/changes, amber attention, violet merged).
/// Every text colour clears 4.5:1 on `surface` in both appearances.
enum Theme {
    static let accent = Color.dynamic(light: "#171714", dark: "#F3EBDD")
    static let onAccent = Color.dynamic(light: "#F3EBDD", dark: "#171714")
    /// Selected rows and chips.
    static let accentSoft = Color.dynamic(light: "#F3EBDD", dark: "#2E2D2A")
    static let text = Color.dynamic(light: "#1C1C1F", dark: "#F2F2F5")
    static let secondaryText = Color.dynamic(light: "#55555E", dark: "#A9A9B3")
    static let tertiaryText = Color.dynamic(light: "#6B6B75", dark: "#8E8E98")
    static let controlText = Color.dynamic(light: "#3A3A42", dark: "#D8D8DE")
    static let surface = Color.dynamic(light: "#FFFFFF", dark: "#1D1D21")
    static let strip = Color.dynamic(light: "#F7F7F9", dark: "#242429")
    static let hover = Color.dynamic(light: "#F4F4F6", dark: "#27272C")
    static let border = Color.dynamic(light: "#E2E2E6", dark: "#36363D")
    static let controlBorder = Color.dynamic(light: "#D9D9DF", dark: "#45454D")
    static let kbdFill = Color.dynamic(light: "#F1F1F4", dark: "#2C2C32")

    static let goodText = Color.dynamic(light: "#14513A", dark: "#8FD9B4")
    static let goodFill = Color.dynamic(light: "#E6F2EC", dark: "#1C3A2D")
    static let badText = Color.dynamic(light: "#8A2418", dark: "#F2A196")
    static let badFill = Color.dynamic(light: "#FBEAE7", dark: "#43231F")
    static let warnText = Color.dynamic(light: "#7A4A00", dark: "#F2C879")
    static let warnFill = Color.dynamic(light: "#FBF1DE", dark: "#3D2F14")
    static let mergedText = Color.dynamic(light: "#5B2DA8", dark: "#C9B0F5")
    static let mergedFill = Color.dynamic(light: "#F1EAFB", dark: "#33264A")
}

/// One spacing scale, so every screen has the same rhythm (points).
enum Spacing {
    static let gutter: CGFloat = 16
    static let bar: CGFloat = 12
    static let section: CGFloat = 16
    static let inner: CGFloat = 10
    static let item: CGFloat = 8
    static let control: CGFloat = 28
}

extension Color {
    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
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

// MARK: - Buttons

/// The one ink call to action per screen.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(configuration.isPressed ? 0.82 : 1)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// White, bordered. Every secondary action uses this.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 7).fill(configuration.isPressed ? Theme.strip : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// A square bordered icon button (28 pt) for row and toolbar actions.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.controlText)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 7).fill(configuration.isPressed ? Theme.strip : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Tabs and filter chips; `selected` gets the ink outline and paper tint.
struct ChipButtonStyle: ButtonStyle {
    var selected = false
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.controlText)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Theme.accentSoft : (configuration.isPressed ? Theme.strip : Theme.surface)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? Theme.accent : Theme.controlBorder, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
    }
}

// MARK: - Small pieces

/// A keycap for shortcut hints.
struct Kbd: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: "\u{200E}" + text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.controlText)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.kbdFill))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.controlBorder, lineWidth: 0.5))
    }
}

/// "↑ ↓ move" style hint.
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

/// Small uppercase label, used for section headers.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// A count in a capsule, e.g. on tabs.
struct CountBadge: View {
    let count: Int
    var selected = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(selected ? Theme.onAccent : Theme.secondaryText)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(selected ? Theme.accent : Theme.kbdFill))
    }
}
