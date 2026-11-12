import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NotificationStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var confirmDisconnect = false
    @AppStorage("animatedSky") private var animatedSky = true

    private let intervals: [Double] = [60, 120, 300, 600, 900]

    var body: some View {
        Form {
            Section("GitHub account") {
                if store.hasToken {
                    LabeledContent("Connected as") {
                        HStack(spacing: Spacing.item) {
                            Text(store.login.map { "@\($0)" } ?? "checking…").fontWeight(.semibold)
                            Button("Disconnect…", role: .destructive) { confirmDisconnect = true }
                        }
                    }
                    Text("The token is stored in your login Keychain. To use a different one, disconnect and paste it in the Belfry menu.")
                        .font(.caption).foregroundStyle(Color.secondary)
                } else {
                    Text("Not connected. Open the Belfry menu in the menu bar to paste a token.")
                        .foregroundStyle(Color.secondary)
                }
            }

            Section("Banners") {
                LabeledContent("macOS permission") {
                    HStack(spacing: Spacing.item) {
                        switch store.bannersAllowed {
                        case true?: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
                        case false?: Label("Off", systemImage: "bell.slash.fill").foregroundStyle(Color.red)
                        case nil: Text("Not asked yet").foregroundStyle(Color.secondary)
                        }
                        Button("Notification Settings…") { store.openNotificationSettings() }
                    }
                }
                Toggle("Play a sound", isOn: $store.soundEnabled)
                LabeledContent("Try it") {
                    Button("Send Test Banner") { store.sendTestBanner() }
                }
            }

            Section("Inbox") {
                Picker("Check GitHub every", selection: $store.pollIntervalSeconds) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(seconds < 120 ? "minute" : "\(Int(seconds / 60)) minutes").tag(seconds)
                    }
                }
                Picker("CI runs", selection: $store.ciFilter) {
                    ForEach(CIFilter.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Group CI runs by branch", isOn: $store.groupCI)
                Toggle("Mark done when opened", isOn: $store.doneOnOpen)
                Text("The CI choice applies to the list, the menu-bar count and banners. Hidden runs stay in your GitHub inbox. GitHub may ask Belfry to check less often; it always waits at least that long.")
                    .font(.caption).foregroundStyle(Color.secondary)
            }

            Section("General") {
                Toggle("Animated sky", isOn: $animatedSky)
                Toggle("Open Belfry at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(Color.red)
                }
            }

            Section {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Belfry \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .fontWeight(.semibold)
                        Text("No analytics. Talks only to api.github.com.")
                            .font(.caption).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Link("Source on GitHub", destination: URL(string: "https://github.com/bar-amir/belfry")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { store.refreshBannerPermission() }
        .confirmationDialog("Disconnect from GitHub?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } message: {
            Text("Belfry removes the token from your Keychain and stops checking. The token itself stays valid on GitHub.")
        }
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
