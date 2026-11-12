import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    @Published private(set) var threads: [GitHubThread] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasToken = false
    /// Resolved "what happened" per thread, keyed by thread id and valid for one `updated_at`.
    @Published private(set) var details: [String: (updatedAt: String, detail: ThreadDetail)] = [:]
    private var loadingDetails: Set<String> = []

    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Double = 60
    @AppStorage("soundEnabled") var soundEnabled = true

    /// Most banners posted in one poll; anything beyond becomes a single summary banner.
    private let maxBannersPerPoll = 8

    private var lastModified: String?
    private var serverPollInterval: TimeInterval = 60
    private var pollTask: Task<Void, Never>?
    private var seen: SeenStore

    var unreadCount: Int { threads.count }

    var groupedByRepo: [(repo: String, threads: [GitHubThread])] {
        Dictionary(grouping: threads, by: { $0.repository.fullName })
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
            threads = []
            lastError = GitHubError.missingToken.errorDescription
            return
        }
        hasToken = true
        isRefreshing = true
        defer { isRefreshing = false }

        let client = GitHubClient(token: token)
        do {
            let result = try await client.fetchNotifications(ifModifiedSince: lastModified)
            if let interval = result.pollInterval { serverPollInterval = interval }
            lastModified = result.lastModified
            lastChecked = Date()
            lastError = nil
            guard let fresh = result.threads else { return } // 304: nothing changed
            threads = fresh.filter(\.unread)
            await notifyNew(threads, client: client)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Banners

    private func notifyNew(_ threads: [GitHubThread], client: GitHubClient) async {
        let firstRun = seen.isFirstRun
        let dayAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))

        var toNotify: [GitHubThread] = []
        for thread in threads where seen.isNew(thread) {
            // On the very first run only announce the last day's activity; seed the rest silently.
            if !firstRun || thread.updatedAt >= dayAgo { toNotify.append(thread) }
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

    func sendTestBanner() {
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
        threads.removeAll { $0.id == thread.id }
        lastModified = nil
        Task {
            do { try await GitHubClient(token: token).markRead(threadId: thread.id) }
            catch { lastError = error.localizedDescription; refreshNow() }
        }
    }

    func markAllRead() {
        guard let token = currentToken() else { return }
        threads = []
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
