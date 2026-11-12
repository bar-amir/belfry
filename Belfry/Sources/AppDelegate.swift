import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let urlKey = "url"
    static let threadKey = "threadId"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--dump") {
            Task { await Self.dumpAndExit() }
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { NSLog("Belfry: notification authorization error: \(error)") }
            NSLog("Belfry: notifications authorized = \(granted)")
        }
        Task { @MainActor in
            NotificationStore.shared.start()
        }
    }

    /// `Belfry --dump`: prints what each unread row would say, then quits. Handy for debugging without the UI.
    private static func dumpAndExit() async {
        guard let token = Keychain.readToken() ?? ProcessInfo.processInfo.environment["BELFRY_GITHUB_TOKEN"] else {
            print("No token"); exit(1)
        }
        let client = GitHubClient(token: token)
        do {
            let threads = try await client.fetchNotifications(ifModifiedSince: nil).threads ?? []
            for thread in threads.prefix(15) {
                let d = await client.details(for: thread)
                print("[\(thread.repository.fullName)\(d.number.map { " #\($0)" } ?? "")] \(thread.displayTitle)")
                print("    \(d.summary ?? "—")  ·  \(thread.reasonLabel)")
                print("    \(d.url.absoluteString)")
            }
            exit(0)
        } catch {
            print("Error: \(error.localizedDescription)"); exit(1)
        }
    }

    // Show banners even though a menu-bar app is technically always "active".
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let urlString = info[Self.urlKey] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
