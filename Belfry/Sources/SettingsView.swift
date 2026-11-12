import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NotificationStore
    @State private var tokenInput = ""
    @State private var tokenSaved = Keychain.readToken() != nil
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    private let intervals: [Double] = [60, 120, 300, 600, 900]

    var body: some View {
        Form {
            Section("GitHub token") {
                SecureField(tokenSaved ? "Token saved in Keychain — paste to replace" : "ghp_…", text: $tokenInput)
                HStack {
                    Button("Save") {
                        store.saveToken(tokenInput)
                        tokenInput = ""
                        tokenSaved = Keychain.readToken() != nil
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove", role: .destructive) {
                        Keychain.deleteToken()
                        tokenSaved = false
                        store.refreshNow()
                    }
                    .disabled(!tokenSaved)
                    Spacer()
                    Link("Create a token…",
                         destination: URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo&description=Belfry")!)
                }
                Text("Classic token with the notifications and repo scopes. Stored only in your login Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Picker("Check every", selection: $store.pollIntervalSeconds) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(seconds < 120 ? "minute" : "\(Int(seconds / 60)) minutes").tag(seconds)
                    }
                }
                Text("GitHub's X-Poll-Interval is respected when it asks for a longer wait.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Play sound with banners", isOn: $store.soundEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Button("Send test banner") { store.sendTestBanner() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
