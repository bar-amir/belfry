import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let urlKey = "url"
    static let threadKey = "threadId"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--sky-check") {
            Self.skyCheck()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--animations"), i + 1 < CommandLine.arguments.count {
            AnimationFrames.renderAll(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.renderAll(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if CommandLine.arguments.contains("--dump") {
            Task { await Self.dumpAndExit() }
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Permission is requested after the first successful check, when there is something to announce.
        Task { @MainActor in NotificationStore.shared.refreshBannerPermission() }
        // Pick up changes made in System Settings while Belfry runs.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationStore.shared.refreshBannerPermission() }
        }
        Task { @MainActor in
            NotificationStore.shared.start()
        }
    }

    /// `Belfry --sky-check`: prints positions for sanity checks against known sky facts.
    @MainActor private static func skyCheck() {
        let zone = SkyLocation.timeZoneCoordinate()
        print("Time zone location:", zone.name, String(format: "%.2f, %.2f", zone.lat, zone.lon))
        let lat = zone.lat, lon = zone.lon
        let iso = ISO8601DateFormatter()
        let jan1 = iso.date(from: "2026-01-01T00:00:00Z")!
        print(String(format: "GMST 2026-01-01 0h UT: %.2f deg = %.2f h", Astronomy.localSiderealTime(jan1, longitude: 0),
                     Astronomy.localSiderealTime(jan1, longitude: 0) / 15))
        let now = Snapshot.skyDate
        let lst = Astronomy.localSiderealTime(now, longitude: lon)
        for (name, ra, dec) in [("Polaris", 37.95, 89.264), ("Sirius", 101.287, -16.716), ("Vega", 279.235, 38.784),
                                ("Betelgeuse", 88.793, 7.407), ("Fomalhaut", 344.413, -29.622)] {
            let h = Astronomy.horizontal(ra: ra, dec: dec, latitude: lat, lst: lst)
            print(String(format: "%@ at %@: alt %.1f az %.1f", name, iso.string(from: now), h.alt, h.az))
        }
        // Local solar noon: when the Sun crosses the meridian.
        var best = (alt: -90.0, az: 0.0, t: now)
        let day = iso.date(from: "2026-11-12T00:00:00Z")!
        for minute in stride(from: 0, to: 1440, by: 2) {
            let t = day.addingTimeInterval(Double(minute) * 60)
            let s = Astronomy.sun(t)
            let h = Astronomy.horizontal(ra: s.ra, dec: s.dec, latitude: lat, lst: Astronomy.localSiderealTime(t, longitude: lon))
            if h.alt > best.alt { best = (h.alt, h.az, t) }
        }
        let sunDec = Astronomy.sun(best.t).dec
        print(String(format: "Sun highest 2026-11-12: alt %.1f az %.1f at %@ (expected alt %.1f)", best.alt, best.az,
                     iso.string(from: best.t), 90 - lat + sunDec))
        let m = Astronomy.moon(now)
        let mh = Astronomy.horizontal(ra: m.ra, dec: m.dec, latitude: lat, lst: lst)
        print(String(format: "Moon position: alt %.1f az %.1f", mh.alt, mh.az))
        print(String(format: "Moon at %@: illuminated %.2f, %@", iso.string(from: now), m.illuminated, m.waxing ? "waxing" : "waning"))
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
