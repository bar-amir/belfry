import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// One row in the panel: a single thread, or every CI run for one repository and branch collapsed together.
struct InboxItem: Identifiable, Equatable {
    let id: String
    /// Newest first.
    let threads: [GitHubThread]
    var primary: GitHubThread { threads[0] }
    var count: Int { threads.count }
    var repo: String { primary.repository.fullName }
}

/// How a row leaves the list.
enum ExitKind: Equatable { case done, mute }

/// A Done or Mute that is shown immediately but sent to GitHub only after the undo window closes.
struct PendingAction: Equatable {
    enum Kind { case done, mute }
    let kind: Kind
    let threadIds: Set<String>
    let message: String
}

@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    /// Every unread thread from GitHub.
    @Published private(set) var allThreads: [GitHubThread] = []
    @Published private(set) var problem: FetchProblem?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasToken = false
    @Published private(set) var login: String?
    /// nil until checked; false when macOS will not show Belfry's banners.
    @Published private(set) var bannersAllowed: Bool?
    /// Open PRs waiting on your review, newest activity first.
    @Published private(set) var reviewRequests: [ReviewRequest] = []
    /// PR URL -> login of whoever asked for the review.
    @Published private(set) var requesters: [String: String] = [:]
    /// Resolved "what happened" per thread, keyed by thread id and valid for one `updated_at`.
    @Published private(set) var details: [String: (updatedAt: String, detail: ThreadDetail)] = [:]
    @Published private(set) var pending: PendingAction?
    /// Rows playing their exit animation, and when each starts (for the cascade in Done with N).
    @Published private(set) var exiting: [String: ExitKind] = [:]
    private(set) var exitDelay: [String: Double] = [:]
    @Published var search = ""
    @Published var selection: String?

    @AppStorage("selectedTab") var selectedTab: ThreadTab = .all
    @AppStorage("prSubTab") var prSubTab: PRSubTab = .all
    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Double = 60
    @AppStorage("soundEnabled") var soundEnabled = true
    @AppStorage("ciFilter") var ciFilter: CIFilter = .all
    @AppStorage("groupCI") var groupCI = true
    @AppStorage("doneOnOpen") var doneOnOpen = false

    /// How long Done and Mute wait before they reach GitHub, so Undo can take them back.
    let undoWindow: TimeInterval = 6
    /// Most banners posted in one poll; anything beyond becomes a single summary banner.
    private let maxBannersPerPoll = 8

    private var loadingDetails: Set<String> = []
    private var lastModified: String?
    private var serverPollInterval: TimeInterval = 60
    private var pollTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var seen: SeenStore

    private init() {
        seen = SeenStore.load()
    }

    // MARK: Derived lists

    /// Threads the CI filter lets through, minus anything waiting in the undo window.
    var threads: [GitHubThread] {
        let hidden = pending?.threadIds ?? []
        return allThreads.filter { ciFilter.allows($0) && !hidden.contains($0.id) }
    }

    var hiddenByFilter: Int { allThreads.filter { !ciFilter.allows($0) }.count }

    /// Rows for a set of threads, with CI runs collapsed per repository and branch when enabled.
    func items(from threads: [GitHubThread]) -> [InboxItem] {
        var singles: [InboxItem] = []
        var groups: [String: [GitHubThread]] = [:]
        for thread in threads {
            if groupCI, thread.isCI {
                let branch = CIRun(title: thread.subject.title)?.branch ?? thread.subject.title
                groups["ci:\(thread.repository.fullName):\(branch)", default: []].append(thread)
            } else {
                singles.append(InboxItem(id: thread.id, threads: [thread]))
            }
        }
        let collapsed = groups.map { key, value in
            InboxItem(id: key, threads: value.sorted { $0.updatedAt > $1.updatedAt })
        }
        return (singles + collapsed).sorted { $0.primary.updatedAt > $1.primary.updatedAt }
    }

    /// Rows per tab, after the CI filter and the search text.
    func count(for tab: ThreadTab) -> Int { items(from: threads.filter { tab.contains($0) && matchesSearch($0) }).count }

    func count(for sub: PRSubTab) -> Int {
        sub == .review ? visibleReviews.count
            : threads.filter {
                ThreadTab.pullRequests.contains($0) && sub.contains(detail(for: $0)) && matchesSearch($0)
            }.count
    }

    /// The menu-bar number: rows in All after the CI filter. Search never changes it.
    var unreadCount: Int { items(from: threads).count }

    private func matchesSearch(_ thread: GitHubThread) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        let haystack = [thread.subject.title, thread.repository.fullName, thread.reasonLabel,
                        detail(for: thread)?.summary ?? "", detail(for: thread)?.number.map { "#\($0)" } ?? ""]
            .joined(separator: " ").lowercased()
        return query.split(separator: " ").allSatisfy { haystack.contains($0) }
    }

    /// Rows in the current tab, sub-tab and search.
    var visibleItems: [InboxItem] {
        items(from: threads.filter { thread in
            selectedTab.contains(thread)
                && (selectedTab != .pullRequests || prSubTab.contains(detail(for: thread)))
                && matchesSearch(thread)
        })
    }

    var groupedByRepo: [(repo: String, items: [InboxItem])] {
        var order: [String] = []
        var groups: [String: [InboxItem]] = [:]
        for item in visibleItems {
            if groups[item.repo] == nil { order.append(item.repo) }
            groups[item.repo, default: []].append(item)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// Rows in display order, for keyboard movement.
    var flatVisibleItems: [InboxItem] { groupedByRepo.flatMap(\.items) }

    var visibleReviews: [ReviewRequest] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return reviewRequests }
        return reviewRequests.filter { "\($0.title) \($0.repoFullName) #\($0.number)".lowercased().contains(query) }
    }

    var showingReviews: Bool { selectedTab == .pullRequests && prSubTab == .review }

    // MARK: Snapshot fixtures

    /// Puts the store into a fixed state for `--snapshot` renders. Never called in normal use.
    func applyFixture(threads: [GitHubThread], details: [String: ThreadDetail], reviews: [ReviewRequest],
                      requesters: [String: String], problem: FetchProblem? = nil, hasToken: Bool = true,
                      bannersAllowed: Bool? = true, checked: Date? = Date(), refreshing: Bool = false,
                      pending: PendingAction? = nil, selection: String? = nil, search: String = "") {
        allThreads = threads
        self.details = details.reduce(into: [:]) { result, item in
            let updated = threads.first { $0.id == item.key }?.updatedAt ?? ""
            result[item.key] = (updated, item.value)
        }
        reviewRequests = reviews
        self.requesters = requesters
        self.problem = problem
        self.hasToken = hasToken
        self.bannersAllowed = bannersAllowed
        lastChecked = checked
        isRefreshing = refreshing
        self.pending = pending
        self.selection = selection
        self.search = search
        login = hasToken ? "you" : nil
    }

    // MARK: Token

    /// Keychain first; `BELFRY_GITHUB_TOKEN` in the environment is a development fallback.
    private func currentToken() -> String? {
        Keychain.readToken() ?? ProcessInfo.processInfo.environment["BELFRY_GITHUB_TOKEN"]
    }

    /// Checks the token with GitHub before storing it. Returns an error message, or nil on success.
    func connect(token raw: String) async -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "Paste a token first." }
        do {
            login = try await GitHubClient(token: token).validate()
        } catch {
            if case GitHubError.unauthorized = error { return "GitHub didn't accept that token. Check you copied all of it." }
            return error.localizedDescription
        }
        Keychain.saveToken(token)
        lastModified = nil
        problem = nil
        refreshNow()
        return nil
    }

    func disconnect() {
        Keychain.deleteToken()
        login = nil
        refreshNow()
    }

    static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo&description=Belfry")!

    // MARK: Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let wait = max(self.pollIntervalSeconds, self.serverPollInterval, 30)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func refreshNow() {
        pollTask?.cancel()
        pollTask = nil
        start()
    }

    func poll() async {
        guard let token = currentToken() else {
            hasToken = false
            allThreads = []
            reviewRequests = []
            problem = nil
            return
        }
        hasToken = true
        isRefreshing = true
        defer { isRefreshing = false }

        let client = GitHubClient(token: token)
        if login == nil { login = await client.viewerLogin() }
        let announcedReviews = await pollReviewRequests(client: client)
        do {
            let result = try await client.fetchNotifications(ifModifiedSince: lastModified)
            if let interval = result.pollInterval { serverPollInterval = interval }
            lastModified = result.lastModified
            lastChecked = Date()
            problem = nil
            if let fresh = result.threads { // nil on 304: nothing changed
                allThreads = fresh.filter(\.unread)
                await notifyNew(allThreads, client: client, skipping: announcedReviews)
            }
            requestBannerPermissionIfNeeded()
        } catch {
            problem = FetchProblem(error)
        }
        // PR sub-tabs sort by review state, so resolve every PR thread up front. This also runs after a 304,
        // which retries any lookup that failed earlier (failed PR lookups are not cached).
        for thread in allThreads where thread.subject.type == "PullRequest" { loadDetail(for: thread) }
    }

    // MARK: Banners

    /// Asks for notification permission once there is something worth announcing, not at launch.
    private func requestBannerPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                Task { @MainActor in self.refreshBannerPermission() }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                Task { @MainActor in self.refreshBannerPermission() }
            }
        }
    }

    /// Refreshes the review list and announces PRs that newly need your review.
    /// Returns the PR URLs announced, so the matching notification thread isn't announced twice.
    private func pollReviewRequests(client: GitHubClient) async -> Set<String> {
        let current: [ReviewRequest]
        do { current = try await client.reviewRequests() } catch {
            NSLog("Belfry: review search failed: \(error.localizedDescription)")
            return []
        }
        reviewRequests = current
        for pr in current where requesters[pr.id] == nil {
            if let who = await client.requester(for: pr, login: login) { requesters[pr.id] = who }
        }

        let previous = seen.pendingReviews
        let dayAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))
        let fresh = current.filter { pr in
            if let previous { return !previous.contains(pr.id) }
            return pr.updatedAt >= dayAgo // first check: only announce recent requests
        }
        seen.pendingReviews = current.map(\.id)
        seen.save()
        for pr in fresh { postReviewBanner(for: pr) }
        return Set(fresh.map(\.id))
    }

    private func postReviewBanner(for pr: ReviewRequest) {
        let content = UNMutableNotificationContent()
        content.title = pr.title
        content.subtitle = "\(pr.repoFullName) #\(pr.number) · Review requested"
        content.body = requesters[pr.id].map { "@\($0) asked for your review" } ?? "Waiting for your review"
        content.threadIdentifier = pr.repoFullName
        content.userInfo = [AppDelegate.urlKey: pr.htmlURL]
        if soundEnabled { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "review-\(pr.id)", content: content, trigger: nil))
    }

    private func notifyNew(_ threads: [GitHubThread], client: GitHubClient, skipping announcedReviews: Set<String>) async {
        let firstRun = seen.isFirstRun
        let dayAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))

        var toNotify: [GitHubThread] = []
        for thread in threads where seen.isNew(thread) {
            // On the very first run only announce the last day's activity; seed the rest silently.
            // Filtered-out threads are still marked seen, so re-enabling CI doesn't replay old runs.
            let alreadyAnnounced = thread.reason == "review_requested"
                && thread.subject.url.flatMap(URL.init(string:)).flatMap(GitHubClient.rewrite)
                    .map { announcedReviews.contains($0.absoluteString) } == true
            if ciFilter.allows(thread), !alreadyAnnounced, !firstRun || thread.updatedAt >= dayAgo {
                toNotify.append(thread)
            }
            seen.mark(thread)
        }
        seen.save()

        toNotify.sort { $0.updatedAt > $1.updatedAt }
        for thread in toNotify.prefix(maxBannersPerPoll) {
            let detail = await client.details(for: thread)
            details[thread.id] = (thread.updatedAt, detail)
            postBanner(for: thread, detail: detail)
        }
        let overflow = toNotify.count - maxBannersPerPoll
        if overflow > 0 { postSummaryBanner(count: overflow) }
    }

    private func postBanner(for thread: GitHubThread, detail: ThreadDetail) {
        let content = UNMutableNotificationContent()
        content.title = thread.displayTitle
        let number = detail.number.map { " #\($0)" } ?? ""
        content.subtitle = "\(thread.repository.fullName)\(number) · \(thread.reasonLabel)"
        content.body = detail.summary ?? Self.typeLabel(thread.subject.type)
        content.threadIdentifier = thread.repository.fullName
        content.userInfo = [AppDelegate.urlKey: detail.url.absoluteString, AppDelegate.threadKey: thread.id]
        if soundEnabled { content.sound = .default }
        let request = UNNotificationRequest(identifier: "thread-\(thread.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func postSummaryBanner(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(count) more GitHub notifications"
        content.body = "Open the Belfry menu to see them all."
        content.userInfo = [AppDelegate.urlKey: "https://github.com/notifications"]
        if soundEnabled { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "summary-\(UUID().uuidString)", content: content, trigger: nil))
    }

    /// Re-reads macOS's permission; banners are silently dropped while it is denied.
    func refreshBannerPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let styleOK = settings.alertStyle != .none
            let undecided = settings.authorizationStatus == .notDetermined
            Task { @MainActor in self.bannersAllowed = undecided ? nil : (allowed && styleOK) }
        }
    }

    static let notificationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.baramir.belfry")!

    func openNotificationSettings() {
        NSWorkspace.shared.open(Self.notificationSettingsURL)
    }

    func sendTestBanner() {
        requestBannerPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Belfry is ringing"
        content.subtitle = "Test notification"
        content.body = "Banners for new GitHub notifications will look like this."
        content.userInfo = [AppDelegate.urlKey: "https://github.com/notifications"]
        if soundEnabled { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case "PullRequest": return "Pull request"
        case "CheckSuite": return "Workflow run"
        default: return type
        }
    }

    // MARK: Details

    func detail(for thread: GitHubThread) -> ThreadDetail? {
        guard let cached = details[thread.id], cached.updatedAt == thread.updatedAt else { return nil }
        return cached.detail
    }

    /// Fetches a row's detail when it scrolls into view.
    func loadDetail(for thread: GitHubThread) {
        guard detail(for: thread) == nil, !loadingDetails.contains(thread.id), let token = currentToken() else { return }
        loadingDetails.insert(thread.id)
        Task {
            let detail = await GitHubClient(token: token).details(for: thread)
            // A PR always resolves to some summary; nil means the lookup failed, so retry on the next poll.
            if detail.summary != nil || thread.subject.type != "PullRequest" {
                details[thread.id] = (thread.updatedAt, detail)
            }
            loadingDetails.remove(thread.id)
        }
    }

    // MARK: Actions

    func open(_ item: InboxItem) {
        let thread = item.primary
        if thread.isCI, let run = CIRun(title: thread.subject.title),
           var c = URLComponents(string: thread.repository.htmlURL + "/actions") {
            c.queryItems = [URLQueryItem(name: "query", value: "branch:\(run.branch)")]
            if let url = c.url { NSWorkspace.shared.open(url) }
        } else if let cached = detail(for: thread) {
            NSWorkspace.shared.open(cached.url)
        } else if let token = currentToken() {
            Task { NSWorkspace.shared.open(await GitHubClient(token: token).htmlURL(for: thread)) }
        }
        if doneOnOpen { markDone([item]) }
    }

    func open(_ pr: ReviewRequest) {
        if let url = URL(string: pr.htmlURL) { NSWorkspace.shared.open(url) }
    }

    func copyLink(_ item: InboxItem) {
        let url = detail(for: item.primary)?.url.absoluteString ?? item.primary.repository.htmlURL
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    /// Plays the exit animation, then marks the rows done or muted in one undoable action.
    func requestExit(_ kind: ExitKind, _ items: [InboxItem], label: String? = nil, animated: Bool) {
        let items = items.filter { exiting[$0.id] == nil }
        guard !items.isEmpty else { return }
        guard animated else {
            if kind == .done { markDone(items, label: label) } else { mute(items) }
            return
        }
        let stagger = 0.045
        for (index, item) in items.enumerated() {
            exitDelay[item.id] = Double(min(index, 12)) * stagger
            exiting[item.id] = kind
        }
        let total = 0.62 + Double(min(items.count - 1, 12)) * stagger
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            guard let self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                for item in items { self.exiting[item.id] = nil }
                if kind == .done { self.markDone(items, label: label) } else { self.mute(items) }
            }
        }
    }

    func markDone(_ items: [InboxItem], label: String? = nil) {
        stage(.done, items, message: label ?? Self.describe(items, verb: "Marked", suffix: "done"))
    }

    func mute(_ items: [InboxItem]) {
        stage(.mute, items, message: Self.describe(items, verb: "Muted", suffix: ""))
    }

    func doneAllVisible() {
        let items = flatVisibleItems
        markDone(items, label: "Marked \(items.reduce(0) { $0 + $1.count }) done")
    }

    func doneAll(inRepo repo: String) {
        let items = flatVisibleItems.filter { $0.repo == repo }
        markDone(items, label: "Marked \(repo) done")
    }

    private static func describe(_ items: [InboxItem], verb: String, suffix: String) -> String {
        let total = items.reduce(0) { $0 + $1.count }
        let what = items.count == 1 ? "“\(items[0].primary.displayTitle)”" : "\(total) notifications"
        return [verb, what, suffix].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Hides the threads now and sends the change after the undo window. A second action commits the first.
    private func stage(_ kind: PendingAction.Kind, _ items: [InboxItem], message: String) {
        let ids = Set(items.flatMap { $0.threads.map(\.id) })
        guard !ids.isEmpty else { return }
        commitPending()
        advanceSelection(past: Set(items.map(\.id)))
        pending = PendingAction(kind: kind, threadIds: ids, message: message)
        let window = undoWindow
        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commitPending()
        }
    }

    func undo() {
        commitTask?.cancel()
        commitTask = nil
        pending = nil
    }

    /// Sends the staged action to GitHub now.
    func commitPending() {
        commitTask?.cancel()
        commitTask = nil
        guard let action = pending, let token = currentToken() else { pending = nil; return }
        pending = nil
        allThreads.removeAll { action.threadIds.contains($0.id) }
        lastModified = nil
        Task {
            let client = GitHubClient(token: token)
            for id in action.threadIds {
                do {
                    if action.kind == .mute { try await client.mute(threadId: id) }
                    try await client.markDone(threadId: id)
                } catch {
                    NSLog("Belfry: \(action.kind) failed for \(id): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Keyboard selection

    func moveSelection(by step: Int) {
        let ids = showingReviews ? visibleReviews.map(\.id) : flatVisibleItems.map(\.id)
        guard !ids.isEmpty else { selection = nil; return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = step > 0 ? ids.first : ids.last
            return
        }
        selection = ids[max(0, min(ids.count - 1, index + step))]
    }

    var selectedItem: InboxItem? { flatVisibleItems.first { $0.id == selection } }

    /// Keeps a selection after the selected rows disappear, so keyboard triage can continue.
    private func advanceSelection(past removed: Set<String>) {
        guard let current = selection, removed.contains(current) else { return }
        let ids = flatVisibleItems.map(\.id)
        guard let index = ids.firstIndex(of: current) else { return }
        selection = ids[(index + 1)...].first { !removed.contains($0) }
            ?? ids[..<index].last { !removed.contains($0) }
    }
}

/// Last-notified `updated_at` per thread, persisted so restarts don't re-announce old threads.
struct SeenStore: Codable {
    var updatedAtByThread: [String: String] = [:]
    var isFirstRun = true
    /// PR URLs that were waiting on your review at the last poll; nil until the first review check.
    var pendingReviews: [String]?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Belfry", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("seen-threads.json")
    }

    static func load() -> SeenStore {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(SeenStore.self, from: data)
        else { return SeenStore() }
        return store
    }

    func isNew(_ thread: GitHubThread) -> Bool {
        guard let last = updatedAtByThread[thread.id] else { return true }
        return thread.updatedAt > last // ISO 8601 UTC strings sort chronologically
    }

    mutating func mark(_ thread: GitHubThread) {
        updatedAtByThread[thread.id] = thread.updatedAt
    }

    mutating func save() {
        isFirstRun = false
        if updatedAtByThread.count > 5000 {
            let keep = updatedAtByThread.sorted { $0.value > $1.value }.prefix(4000)
            updatedAtByThread = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

/// Which CI notifications (workflow and check-suite runs) to show and announce.
enum CIFilter: String, CaseIterable, Identifiable {
    case all, failuresOnly, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All CI runs"
        case .failuresOnly: return "Failures only"
        case .none: return "None"
        }
    }

    func allows(_ thread: GitHubThread) -> Bool {
        guard thread.isCI else { return true }
        switch self {
        case .all: return true
        case .failuresOnly: return thread.isCIFailure
        case .none: return false
        }
    }
}

/// Tabs in the dropdown, by notification subject type.
enum ThreadTab: String, CaseIterable, Identifiable {
    case all, pullRequests, issues, ci, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .pullRequests: return "PRs"
        case .issues: return "Issues"
        case .ci: return "CI"
        case .other: return "Other"
        }
    }

    func contains(_ thread: GitHubThread) -> Bool {
        switch self {
        case .all: return true
        case .pullRequests: return thread.subject.type == "PullRequest"
        case .issues: return thread.subject.type == "Issue"
        case .ci: return thread.isCI
        case .other: return !thread.isCI && thread.subject.type != "PullRequest" && thread.subject.type != "Issue"
        }
    }
}

/// Nested tabs under PRs. Review comes from search; the rest sort PR notifications by latest activity.
enum PRSubTab: String, CaseIterable, Identifiable {
    case all, review, comments, approved, changesRequested, closed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .review: return "Review"
        case .comments: return "Comments"
        case .approved: return "Approved"
        case .changesRequested: return "Changes"
        case .closed: return "Closed"
        }
    }

    /// `detail` is nil while it is still loading; such rows only appear under All.
    func contains(_ detail: ThreadDetail?) -> Bool {
        switch self {
        case .all: return true
        case .review: return false
        case .comments: return detail?.tags.contains(.comment) == true
        case .approved: return detail?.tags.contains(.approved) == true
        case .changesRequested: return detail?.tags.contains(.changesRequested) == true
        case .closed: return detail?.tags.contains(.closed) == true
        }
    }
}
