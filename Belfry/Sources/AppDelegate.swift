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
            Task { @MainActor in NotificationStore.shared.refreshBannerPermission() }
        }
        // Pick up changes made in System Settings while Belfry runs.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationStore.shared.refreshBannerPermission() }
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
            let threads = (try await client.fetchNotifications(ifModifiedSince: nil).threads ?? []).filter(\.unread)
            let reviews = try await client.reviewRequests()
            let me = await client.viewerLogin()
            print("Review requests for @\(me ?? "?"): \(reviews.count)")
            for pr in reviews {
                let who = await client.requester(for: pr, login: me)
                print("    \(pr.repoFullName) #\(pr.number) \(pr.title) — asked by @\(who ?? "?")")
            }
            print("Tabs: " + ThreadTab.allCases.map { tab in "\(tab.label) \(threads.filter(tab.contains).count)" }
                .joined(separator: " · "))
            var prDetails: [ThreadDetail] = []
            for thread in threads where thread.subject.type == "PullRequest" {
                prDetails.append(await client.details(for: thread))
            }
            print("PR sub-tabs: " + PRSubTab.allCases.map { sub in
                let n = sub == .review ? reviews.count : prDetails.filter(sub.contains).count
                return "\(sub.label) \(n)"
            }.joined(separator: " · "))
            print("CI filter: " + CIFilter.allCases.map { f in "\(f.label) → \(threads.filter(f.allows).count)" }
                .joined(separator: " · "))
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
