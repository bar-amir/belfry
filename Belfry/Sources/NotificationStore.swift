import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    /// Every unread thread from GitHub; `threads` is what the CI filter lets through.
    @Published private(set) var allThreads: [GitHubThread] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasToken = false
    /// nil until checked; false when macOS will not show Belfry's banners.
    @Published private(set) var bannersAllowed: Bool?
    @Published var selectedTab: ThreadTab = .all
    /// Open PRs waiting on your review, newest activity first.
    @Published private(set) var reviewRequests: [ReviewRequest] = []
    /// PR URL -> login of whoever asked for the review.
    @Published private(set) var requesters: [String: String] = [:]
    /// Resolved "what happened" per thread, keyed by thread id and valid for one `updated_at`.
    @Published private(set) var details: [String: (updatedAt: String, detail: ThreadDetail)] = [:]
    private var loadingDetails: Set<String> = []

    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Double = 60
    @AppStorage("soundEnabled") var soundEnabled = true
    @AppStorage("ciFilter") var ciFilter: CIFilter = .all

    var threads: [GitHubThread] { allThreads.filter { ciFilter.allows($0) } }
    var hiddenCount: Int { allThreads.count - threads.count }

    /// Most banners posted in one poll; anything beyond becomes a single summary banner.
    private let maxBannersPerPoll = 8

    private var lastModified: String?
    private var serverPollInterval: TimeInterval = 60
    private var pollTask: Task<Void, Never>?
    private var seen: SeenStore

    var unreadCount: Int { threads.count }

    func count(for tab: ThreadTab) -> Int {
        tab == .review ? reviewRequests.count : threads.filter(tab.contains).count
    }

    private var tabThreads: [GitHubThread] { threads.filter(selectedTab.contains) }

    var groupedByRepo: [(repo: String, threads: [GitHubThread])] {
        Dictionary(grouping: tabThreads, by: { $0.repository.fullName })
            .map { (repo: $0.key, threads: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { ($0.threads.first?.updatedAt ?? "") > ($1.threads.first?.updatedAt ?? "") }
    }

    private init() {
        seen = SeenStore.load()
    }

    // MARK: Token

    /// Keychain first; `BELFRY_GITHUB_TOKEN` in the environment is a development fallback.
    private func currentToken() -> String? {
        Keychain.readToken() ?? ProcessInfo.processInfo.environment["BELFRY_GITHUB_TOKEN"]
    }

    func saveToken(_ token: String) {
        Keychain.saveToken(token)
        lastModified = nil
        refreshNow()
    }

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
            lastError = GitHubError.missingToken.errorDescription
            return
        }
        hasToken = true
        isRefreshing = true
        defer { isRefreshing = false }

        let client = GitHubClient(token: token)
        let announcedReviews = await pollReviewRequests(client: client)
        do {
            let result = try await client.fetchNotifications(ifModifiedSince: lastModified)
            if let interval = result.pollInterval { serverPollInterval = interval }
            lastModified = result.lastModified
            lastChecked = Date()
            lastError = nil
            guard let fresh = result.threads else { return } // 304: nothing changed
            allThreads = fresh.filter(\.unread)
            await notifyNew(allThreads, client: client, skipping: announcedReviews)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Banners

    /// Refreshes the review list and announces PRs that newly need your review.
    /// Returns the PR URLs announced, so the matching notification thread isn't announced twice.
    private func pollReviewRequests(client: GitHubClient) async -> Set<String> {
        let current: [ReviewRequest]
        do { current = try await client.reviewRequests() } catch {
            NSLog("Belfry: review search failed: \(error.localizedDescription)")
            return []
        }
        reviewRequests = current
        let login = await client.viewerLogin()
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

    func open(_ pr: ReviewRequest) {
        if let url = URL(string: pr.htmlURL) { NSWorkspace.shared.open(url) }
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
            Task { @MainActor in self.bannersAllowed = allowed && styleOK }
        }
    }

    static let notificationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.baramir.belfry")!

    func openNotificationSettings() {
        NSWorkspace.shared.open(Self.notificationSettingsURL)
    }

    func sendTestBanner() {
        refreshBannerPermission()
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

    // MARK: Actions

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
            details[thread.id] = (thread.updatedAt, detail)
            loadingDetails.remove(thread.id)
        }
    }

    func open(_ thread: GitHubThread) {
        if let cached = detail(for: thread) {
            NSWorkspace.shared.open(cached.url)
            return
        }
        guard let token = currentToken() else { return }
        Task {
            let url = await GitHubClient(token: token).htmlURL(for: thread)
            NSWorkspace.shared.open(url)
        }
    }

    func markRead(_ thread: GitHubThread) {
        guard let token = currentToken() else { return }
        allThreads.removeAll { $0.id == thread.id }
        lastModified = nil
        Task {
            do { try await GitHubClient(token: token).markRead(threadId: thread.id) }
            catch { lastError = error.localizedDescription; refreshNow() }
        }
    }

    func markAllRead() {
        guard let token = currentToken() else { return }
        allThreads = []
        lastModified = nil
        Task {
            do { try await GitHubClient(token: token).markAllRead() }
            catch { lastError = error.localizedDescription; refreshNow() }
        }
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
    case all, review, pullRequests, issues, ci, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .review: return "Review"
        case .pullRequests: return "PRs"
        case .issues: return "Issues"
        case .ci: return "CI"
        case .other: return "Other"
        }
    }

    func contains(_ thread: GitHubThread) -> Bool {
        switch self {
        case .all: return true
        case .review: return thread.reason == "review_requested"
        case .pullRequests: return thread.subject.type == "PullRequest"
        case .issues: return thread.subject.type == "Issue"
        case .ci: return thread.isCI
        case .other: return !thread.isCI && thread.subject.type != "PullRequest" && thread.subject.type != "Issue"
        }
    }
}
