import AppKit
import SwiftUI

/// `Belfry --snapshot <folder>` renders every screen and state to 2x PNGs, in light and dark, from fixture
/// data with fictional repositories. Used for design review and audits; never touches GitHub.
@MainActor
enum Snapshot {
    static func renderAll(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = NotificationStore.shared
        let f = Fixtures()

        func menu(_ name: String, tab: ThreadTab = .all, sub: PRSubTab = .all, setup: () -> Void) {
            setup()
            store.selectedTab = tab
            store.prSubTab = sub
            for dark in [false, true] {
                let view = MenuContentView()
                    .environmentObject(store)
                    .background(Color(nsColor: .windowBackgroundColor))
                render(view, dark: dark, to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        menu("01-menu-all") { f.applyNormal(store) }
        menu("02-menu-prs", tab: .pullRequests) { f.applyNormal(store) }
        menu("03-menu-prs-review", tab: .pullRequests, sub: .review) { f.applyNormal(store) }
        menu("04-menu-prs-approved", tab: .pullRequests, sub: .approved) { f.applyNormal(store) }
        menu("05-menu-ci", tab: .ci) { f.applyNormal(store) }
        menu("06-menu-empty") {
            store.applyFixture(threads: [], details: [:], reviews: [], requesters: [:])
        }
        menu("07-menu-loading") {
            store.applyFixture(threads: [], details: [:], reviews: [], requesters: [:], checked: nil, refreshing: true)
        }
        menu("08-menu-welcome") {
            store.applyFixture(threads: [], details: [:], reviews: [], requesters: [:], hasToken: false, checked: nil)
        }
        menu("09-menu-bad-token") {
            store.applyFixture(threads: [], details: [:], reviews: [], requesters: [:], problem: .badToken)
        }
        menu("10-menu-banners-blocked") {
            store.applyFixture(threads: f.threads, details: f.details, reviews: f.reviews,
                               requesters: f.requesters, bannersAllowed: false)
        }
        menu("11-menu-long-text") { f.applyLong(store) }
        menu("12-menu-unresolved-details") {
            store.applyFixture(threads: f.threads, details: [:], reviews: f.reviews, requesters: [:])
        }
        menu("13-menu-offline") {
            store.applyFixture(threads: f.threads, details: f.details, reviews: f.reviews,
                               requesters: f.requesters, problem: .offline,
                               checked: Date().addingTimeInterval(-600))
        }
        menu("14-menu-undo") {
            store.applyFixture(threads: f.threads, details: f.details, reviews: f.reviews, requesters: f.requesters,
                               pending: PendingAction(kind: .done, threadIds: ["4"],
                                                      message: "Marked “Upgrade the router to v7” done"))
        }
        menu("15-menu-selected") {
            store.applyFixture(threads: f.threads, details: f.details, reviews: f.reviews, requesters: f.requesters,
                               selection: "2")
        }
        menu("16-menu-search-none") {
            store.applyFixture(threads: f.threads, details: f.details, reviews: f.reviews, requesters: f.requesters,
                               search: "qzvkt")
        }
        menu("17-menu-ci-failures-empty") {
            store.ciFilter = .none
            store.applyFixture(threads: f.threads.filter(\.isCI), details: f.details, reviews: [], requesters: [:])
        }
        store.ciFilter = .all

        f.applyNormal(store)
        for dark in [false, true] {
            render(SettingsView().environmentObject(store), dark: dark,
                   to: folder.appendingPathComponent("20-settings-\(dark ? "dark" : "light").png"))
            for (name, count, err) in [("idle", 0, false), ("count", 12, false), ("error", 0, true)] {
                render(MenuBarLabel(count: count, hasError: err).padding(6),
                       dark: dark, to: folder.appendingPathComponent("30-menubar-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        print("Wrote snapshots to \(folder.path)")
    }

    /// Lays the view out in an offscreen window (so AppKit-backed controls draw) and writes a 2x PNG.
    static func render<V: View>(_ view: V, dark: Bool, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        // Measured views settle over a few layout passes; resize until the fitting size stops changing.
        var size = host.fittingSize
        for _ in 0..<8 {
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            let next = host.fittingSize
            if next == size { break }
            size = next
        }
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.display()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        appearance?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Fictional notifications covering every row type.
@MainActor
struct Fixtures {
    let threads: [GitHubThread]
    let details: [String: ThreadDetail]
    let reviews: [ReviewRequest]
    let requesters: [String: String]

    init() {
        let now = Date()
        func ago(_ minutes: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutes * 60))
        }
        func thread(_ id: String, _ repo: String, _ type: String, _ reason: String, _ title: String,
                    _ minutes: Double, number: Int? = nil) -> GitHubThread {
            let kind = type == "PullRequest" ? "pulls" : "issues"
            let url = number.map { "\"https://api.github.com/repos/\(repo)/\(kind)/\($0)\"" } ?? "null"
            let json = """
            {"id":"\(id)","unread":true,"reason":"\(reason)","updated_at":"\(ago(minutes))",
             "subject":{"title":"\(title)","url":\(url),"latest_comment_url":null,"type":"\(type)"},
             "repository":{"full_name":"\(repo)","html_url":"https://github.com/\(repo)"}}
            """
            return try! JSONDecoder().decode(GitHubThread.self, from: Data(json.utf8))
        }
        threads = [
            thread("1", "acme/api", "PullRequest", "review_requested", "Add rate limiting to the public endpoints", 4, number: 412),
            thread("2", "acme/api", "PullRequest", "author", "Cache invoice totals per account", 25, number: 409),
            thread("3", "acme/web", "PullRequest", "comment", "Dark mode for the billing page", 70, number: 1180),
            thread("4", "acme/web", "PullRequest", "author", "Upgrade the router to v7", 190, number: 1175),
            thread("5", "acme/api", "CheckSuite", "ci_activity", "CI workflow run failed for feat/rate-limits branch", 6),
            thread("5b", "acme/api", "CheckSuite", "ci_activity", "CI workflow run failed for feat/rate-limits branch", 31),
            thread("5c", "acme/api", "CheckSuite", "ci_activity", "Lint workflow run failed for feat/rate-limits branch", 33),
            thread("6", "acme/web", "CheckSuite", "ci_activity", "Deploy preview workflow run succeeded for main branch", 40),
            thread("7", "acme/web", "Issue", "mention", "Billing page flickers on Safari 19", 300, number: 1166),
        ]
        func d(_ repo: String, _ n: Int?, _ summary: String?, _ tags: Set<ActivityKind> = []) -> ThreadDetail {
            ThreadDetail(url: URL(string: "https://github.com/\(repo)")!, number: n, summary: summary, tags: tags)
        }
        details = [
            "1": d("acme/api", 412, "Open by @dana · waiting for your review"),
            "2": d("acme/api", 409, "@lee approved: Looks good, one nit on naming.", [.approved, .comment]),
            "3": d("acme/web", 1180, "@sam commented: Can we keep the old palette behind a flag?", [.comment]),
            "4": d("acme/web", 1175, "Merged by @you", [.closed]),
            "5": d("acme/api", nil, "✗ Failed on feat/rate-limits"),
            "6": d("acme/web", nil, "✓ Succeeded on main"),
            "7": d("acme/web", 1166, "@rio commented: @you can you take a look at this one?", [.comment]),
        ]
        func review(_ repo: String, _ n: Int, _ title: String, _ author: String, _ minutes: Double) -> ReviewRequest {
            let json = """
            {"number":\(n),"title":"\(title)","html_url":"https://github.com/\(repo)/pull/\(n)",
             "repository_url":"https://api.github.com/repos/\(repo)","updated_at":"\(ago(minutes))",
             "draft":false,"user":{"login":"\(author)"}}
            """
            return try! JSONDecoder().decode(ReviewRequest.self, from: Data(json.utf8))
        }
        reviews = [
            review("acme/api", 412, "Add rate limiting to the public endpoints", "dana", 4),
            review("acme/mobile", 88, "Offline queue for card payments", "kim", 1440),
        ]
        requesters = [reviews[0].id: "dana", reviews[1].id: "lee"]
    }

    func applyNormal(_ store: NotificationStore) {
        store.applyFixture(threads: threads, details: details, reviews: reviews, requesters: requesters)
    }

    func applyLong(_ store: NotificationStore) {
        var long = threads
        let json = """
        {"id":"99","unread":true,"reason":"review_requested","updated_at":"\(threads[0].updatedAt)",
         "subject":{"title":"Refactor the entire authentication middleware so session tokens rotate on every privileged request and old tokens are revoked across all regions","url":"https://api.github.com/repos/acme-international-holdings/platform-authentication-service/pulls/12345","latest_comment_url":null,"type":"PullRequest"},
         "repository":{"full_name":"acme-international-holdings/platform-authentication-service","html_url":"https://github.com/acme-international-holdings/platform-authentication-service"}}
        """
        long.insert(try! JSONDecoder().decode(GitHubThread.self, from: Data(json.utf8)), at: 0)
        var d = details
        d["99"] = ThreadDetail(url: URL(string: "https://github.com")!, number: 12345,
                               summary: "@a-very-long-username-for-testing commented: This is a long first line of a comment that goes on well past the width of the panel to check wrapping.",
                               tags: [.comment])
        store.applyFixture(threads: long, details: d, reviews: reviews, requesters: requesters)
    }
}
