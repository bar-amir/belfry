import SwiftUI

@main
struct BelfryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NotificationStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(count: store.unreadCount, hasError: !store.hasToken || store.problem == .badToken)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

struct MenuBarLabel: View {
    let count: Int
    let hasError: Bool

    var body: some View {
        if hasError {
            Image(systemName: "bell.slash")
        } else if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "bell.badge.fill")
                    .symbolEffect(.bounce, value: count)
                Text("\(count)")
            }
        } else {
            Image(systemName: "bell")
        }
    }
}
