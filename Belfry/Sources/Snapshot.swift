import AppKit
import SwiftUI

/// `Belfry --snapshot <folder>` renders every screen and state to 2x PNGs, in light and dark, from fixture
/// data with fictional repositories. Used for design review and audits; never touches GitHub.
@MainActor
enum Snapshot {
    /// A fixed evening for reproducible skies: 2026-11-12 20:00 UTC.
    static let skyDate: Date = ProcessInfo.processInfo.environment["BELFRY_SKY_DATE"]
        .flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date(timeIntervalSince1970: 1_794_513_600)

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
                    .environment(\.snapshotMode, true)
                    .environment(\.frozenTime, 12)
                    .environment(\.skyDate, Snapshot.skyDate)
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
            render(SettingsView().environmentObject(store).environment(\.snapshotMode, true), dark: dark,
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

// MARK: - Action animation frames

/// `Belfry --animations <folder>` renders each action animation frame by frame (30 fps) from fixtures, so the
/// micro-interactions can be reviewed as video. Each clip goes to its own subfolder as 000.png, 001.png, …
@MainActor
enum AnimationFrames {
    static let fps = 30.0

    static func renderAll(to folder: URL) {
        let store = NotificationStore.shared
        let f = Fixtures()
        f.applyNormal(store)
        let rows = ["1", "2", "3"].compactMap { id in store.items(from: f.threads).first { $0.id == id } }
        let ids = rows.map(\.id)

        func clip(_ name: String, seconds: Double, frame: (Double) -> DemoState) {
            let dir = folder.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let count = Int(seconds * fps)
            for i in 0..<count {
                let t = Double(i) / fps
                let view = ActionDemo(rows: rows, state: frame(t), time: 12 + t)
                    .environmentObject(store)
                    .environment(\.snapshotMode, true)
                    .environment(\.frozenTime, 12 + t)
                    .environment(\.skyDate, Snapshot.skyDate)
                Snapshot.render(view, dark: true, to: dir.appendingPathComponent(String(format: "%03d.png", i)))
            }
        }

        let target = ids[1]
        clip("1-done", seconds: 2.0) { t in
            var s = DemoState(caption: "Mark done", keys: ["E"], selected: target)
            let p = ease(progress(t, 0.25, 0.6))
            s.exit[target] = (.done, p)
            s.collapse[target] = easeOut(progress(t, 0.85, 0.3))
            s.toast = easeOut(progress(t, 0.8, 0.3))
            s.toastMark = progress(t, 0.85, 0.5)
            s.pending = PendingAction(kind: .done, threadIds: [], message: "Marked “Cache invoice totals per account” done")
            return s
        }
        clip("2-mute", seconds: 2.0) { t in
            var s = DemoState(caption: "Mute thread", keys: ["M"], selected: target)
            s.exit[target] = (.mute, ease(progress(t, 0.25, 0.7)))
            s.collapse[target] = easeOut(progress(t, 0.95, 0.3))
            s.toast = easeOut(progress(t, 0.9, 0.3))
            s.toastMark = progress(t, 0.95, 0.6)
            s.pending = PendingAction(kind: .mute, threadIds: [], message: "Muted “Cache invoice totals per account”")
            return s
        }
        clip("3-open", seconds: 1.3) { t in
            var s = DemoState(caption: "Open in browser", keys: ["↵"], selected: ids[0])
            s.open[ids[0]] = easeOut(progress(t, 0.25, 0.5))
            return s
        }
        clip("4-done-all", seconds: 2.4) { t in
            var s = DemoState(caption: "Done with 3", keys: ["⌘", "⌫"], selected: nil)
            for (index, id) in ids.enumerated() {
                let start = 0.3 + Double(index) * 0.06
                s.exit[id] = (.done, ease(progress(t, start, 0.6)))
                s.collapse[id] = easeOut(progress(t, start + 0.6, 0.3))
            }
            s.empty = easeOut(progress(t, 1.25, 0.4))
            s.toast = easeOut(progress(t, 1.1, 0.3))
            s.toastMark = progress(t, 1.15, 0.5)
            s.pending = PendingAction(kind: .done, threadIds: [], message: "Marked 3 done")
            return s
        }
        clip("5-undo", seconds: 1.8) { t in
            var s = DemoState(caption: "Undo", keys: ["⌘", "Z"], selected: target)
            let back = progress(t, 0.35, 0.5)
            s.collapse[target] = 1 - easeOutBack(back)
            s.reenter[target] = easeOut(back)
            s.toast = 1 - easeOut(progress(t, 0.3, 0.25))
            s.toastMark = 1
            s.pending = PendingAction(kind: .done, threadIds: [], message: "Marked “Cache invoice totals per account” done")
            return s
        }
        print("Wrote animation frames to \(folder.path)")
    }

    static func progress(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        max(0, min(1, (t - start) / duration))
    }

    static func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

struct DemoState {
    var caption: String
    var keys: [String]
    var selected: String?
    var exit: [String: (ExitKind, Double)] = [:]
    var open: [String: Double] = [:]
    var collapse: [String: Double] = [:]
    var reenter: [String: Double] = [:]
    var toast: Double = 0
    var toastMark: Double = 0
    var pending: PendingAction?
    var empty: Double = 0
}

/// One frame of an action animation: a caption, a repository card with three rows, and the floating footer.
struct ActionDemo: View {
    let rows: [InboxItem]
    let state: DemoState
    let time: Double
    private let rowHeight: CGFloat = 84

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(state.caption)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.starlight)
                HStack(spacing: 3) { ForEach(state.keys, id: \.self) { Kbd($0) } }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                        (Text("acme/").foregroundStyle(Theme.secondaryText) + Text("api").foregroundStyle(Theme.text).bold())
                            .font(.system(size: 12.5))
                        Spacer()
                        Counter(count: rows.filter { (state.collapse[$0.id] ?? 0) < 0.5 }.count)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    ForEach(rows) { item in
                        let collapse = state.collapse[item.id] ?? 0
                        let reenter = state.reenter[item.id]
                        ItemRow(item: item, selected: state.selected == item.id,
                                demoExit: state.exit[item.id], demoOpen: state.open[item.id])
                            .opacity(reenter ?? 1)
                            .scaleEffect(reenter.map { 0.94 + 0.06 * $0 } ?? 1, anchor: .top)
                            .frame(height: max(0, rowHeight * (1 - collapse)), alignment: .top)
                            .clipped()
                    }
                }
                .card()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(1 - state.empty)

                EmptyStateView(title: "You're all caught up", message: "Nothing new under the stars.")
                    .opacity(state.empty)
                    .scaleEffect(0.96 + 0.04 * state.empty)
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 0)
            ZStack {
                FooterBar(pending: nil, showingReviews: false, total: rows.count, doneAll: {}, undo: {})
                    .opacity(1 - state.toast)
                FooterBar(pending: state.pending, showingReviews: false, total: 0, doneAll: {}, undo: {},
                          toastProgress: state.toastMark)
                    .opacity(state.toast)
                    .offset(y: 14 * (1 - state.toast))
            }
            .padding(10)
        }
        .frame(width: panelWidth, height: 430)
        .background(SpaceBackground())
        .environment(\.colorScheme, .dark)
    }
}
