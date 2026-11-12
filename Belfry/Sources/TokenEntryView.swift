import SwiftUI

/// Connecting a GitHub token inside the panel: the first-run welcome, or repairing a token that stopped working.
struct TokenEntryView: View {
    enum Kind { case welcome, repair }

    @EnvironmentObject private var store: NotificationStore
    let kind: Kind
    @State private var token = ""
    @State private var error: String?
    @State private var checking = false
    @State private var shake: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.section) {
            VStack(spacing: 6) {
                OrbitView(size: 70)
                Text(kind == .welcome ? "Belfry" : "Reconnect Belfry")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.auroraDiagonal)
                    .glow(Color(hex: "#6E7BFF"), radius: 10)
                Text(kind == .welcome
                     ? "GitHub notifications as Mac banners, with what actually happened: who approved, who commented, which build failed."
                     : "Your GitHub token stopped working. It may have expired or been revoked. Make a new one and paste it below; nothing else changes.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 12) {
                step(1, "Create a token on GitHub",
                     caption: "A classic token with the notifications and repo scopes. The link fills them in.") {
                    Button("Create token…") { NSWorkspace.shared.open(NotificationStore.newTokenURL) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                step(2, "Paste it here", caption: nil) { EmptyView() }
                HStack(spacing: Spacing.item) {
                    SecureField("", text: $token, prompt: Text("ghp_…").foregroundStyle(Theme.tertiaryText))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .focused($fieldFocused)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#05080F").opacity(0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            error != nil ? AnyShapeStyle(Theme.danger)
                                : (fieldFocused ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Theme.hairlineStrong)),
                            lineWidth: fieldFocused || error != nil ? 1.5 : 1))
                        .offset(x: shake)
                        .accessibilityLabel("GitHub token")
                        .onSubmit(connect)
                    Button(action: connect) {
                        if checking { ProgressView().controlSize(.small).tint(.white) } else { Text("Connect") }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(checking || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.leading, 32)
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                        .padding(.leading, 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .glass(cornerRadius: 12)

            Label("The token stays in your Mac's Keychain. Belfry only talks to api.github.com.", systemImage: "lock.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Spacing.gutter)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: error)
    }

    private func step<Trailing: View>(_ n: Int, _ title: String, caption: String?,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.auroraDiagonal))
                .glow(Theme.accent, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if let caption {
                    Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func connect() {
        guard !checking else { return }
        checking = true
        error = nil
        Task {
            error = await store.connect(token: token)
            checking = false
            if error == nil {
                token = ""
            } else {
                // A short shake says "not that one" without a dialog.
                withAnimation(.spring(response: 0.12, dampingFraction: 0.2)) { shake = 8 }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { shake = 0 }
            }
        }
    }
}
