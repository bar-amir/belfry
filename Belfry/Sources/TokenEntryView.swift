import SwiftUI

/// Connecting a GitHub token inside the panel: the first-run welcome, or repairing a token that stopped working.
struct TokenEntryView: View {
    enum Kind { case welcome, repair }

    @EnvironmentObject private var store: NotificationStore
    let kind: Kind
    @State private var token = ""
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind == .welcome ? "Welcome to Belfry" : "Your GitHub token stopped working")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(kind == .welcome
                         ? "GitHub notifications as Mac banners, with what actually happened: who approved, who commented, which build failed."
                         : "It may have expired or been revoked. Make a new one and paste it here; nothing else changes.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(1, "Create a token on GitHub",
                 caption: "A classic token with the notifications and repo scopes. The link fills them in.") {
                Button("Create token…") { NSWorkspace.shared.open(NotificationStore.newTokenURL) }
                    .buttonStyle(SecondaryButtonStyle())
            }

            step(2, "Paste it here", caption: nil) {
                EmptyView()
            }
            HStack(spacing: Spacing.item) {
                SecureField("ghp_…", text: $token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.strip))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(error == nil ? Theme.border : Theme.badText))
                    .accessibilityLabel("GitHub token")
                    .onSubmit(connect)
                Button(action: connect) {
                    if checking { ProgressView().controlSize(.small) } else { Text("Connect") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(checking || token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 30)
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.badText)
                    .padding(.leading, 30)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("The token stays in your Mac's Keychain. Belfry only talks to api.github.com.",
                  systemImage: "lock.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(Spacing.gutter)
        .padding(.bottom, 4)
    }

    private func step<Trailing: View>(_ n: Int, _ title: String, caption: String?,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent))
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
            if error == nil { token = "" }
        }
    }
}
