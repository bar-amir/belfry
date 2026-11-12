import Foundation

struct GitHubThread: Codable, Identifiable, Equatable {
    struct Subject: Codable, Equatable {
        let title: String
        let url: String?
        let latestCommentURL: String?
        let type: String

        enum CodingKeys: String, CodingKey {
            case title, url, type
            case latestCommentURL = "latest_comment_url"
        }
    }

    struct Repository: Codable, Equatable {
        let fullName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case htmlURL = "html_url"
        }
    }

    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: String
    let subject: Subject
    let repository: Repository

    enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository
        case updatedAt = "updated_at"
    }

    var reasonLabel: String {
        switch reason {
        case "review_requested": return "Review requested"
        case "mention": return "Mentioned"
        case "team_mention": return "Team mentioned"
        case "comment": return "Comment"
        case "ci_activity": return "CI run"
        case "assign": return "Assigned"
        case "author":
            switch subject.type {
            case "PullRequest": return "Your pull request"
            case "Issue": return "Your issue"
            default: return "Your thread"
            }
        case "state_change": return "State changed"
        case "subscribed": return "Watching repo"
        case "manual": return "Subscribed"
        case "approval_requested": return "Approval requested"
        case "security_alert": return "Security alert"
        case "invitation": return "Invitation"
        case "member_feature_requested": return "Feature requested"
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// CI titles are long sentences; show just the workflow name and put the outcome in the detail line.
    var displayTitle: String {
        CIRun(title: subject.title)?.workflow ?? subject.title
    }

    var isCI: Bool {
        reason == "ci_activity" || subject.type == "CheckSuite" || subject.type == "WorkflowRun"
    }

    var isCIFailure: Bool {
        guard isCI else { return false }
        if let run = CIRun(title: subject.title) { return run.outcome == "failed" || run.outcome == "timed out" }
        let t = subject.title.lowercased()
        return t.contains("fail") || t.contains("timed out")
    }

    var typeSymbol: String {
        switch subject.type {
        case "PullRequest": return "arrow.triangle.pull"
        case "Issue": return "smallcircle.filled.circle"
        case "CheckSuite": return "checkmark.seal"
        case "Release": return "tag"
        case "Discussion": return "bubble.left.and.bubble.right"
        case "Commit": return "point.3.connected.trianglepath.dotted"
        default: return "bell"
        }
    }
}

enum GitHubError: LocalizedError {
    case missingToken
    case unauthorized
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "No GitHub token. Add one in Settings."
        case .unauthorized: return "GitHub rejected the token (401). Check its scopes."
        case let .http(code, body): return "GitHub returned \(code): \(body.prefix(140))"
        }
    }
}

struct FetchResult {
    /// nil when GitHub answered 304 Not Modified.
    let threads: [GitHubThread]?
    let lastModified: String?
    let pollInterval: TimeInterval?
}

final class GitHubClient {
    private let session: URLSession
    private let token: String
    private let api = URL(string: "https://api.github.com")!

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        // Conditional requests must reach GitHub, not a local cache.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Belfry/0.1", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func check(_ response: URLResponse, _ data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.http(0, "No response") }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        if http.statusCode >= 400 {
            throw GitHubError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return http
    }

    /// Fetches unread notifications. Pass the previous `Last-Modified` value to get a cheap 304.
    func fetchNotifications(ifModifiedSince: String?) async throws -> FetchResult {
        var components = URLComponents(url: api.appendingPathComponent("notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "50")]
        var next: URL? = components.url
        var all: [GitHubThread] = []
        var lastModified: String?
        var pollInterval: TimeInterval?
        var page = 0

        while let url = next, page < 10 {
            var req = request(url)
            if page == 0, let ifModifiedSince {
                req.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
            }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw GitHubError.http(0, "No response") }
            if page == 0 {
                lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                pollInterval = http.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init)
                if http.statusCode == 304 {
                    return FetchResult(threads: nil, lastModified: ifModifiedSince, pollInterval: pollInterval)
                }
            }
            _ = try check(response, data)
            all += try JSONDecoder().decode([GitHubThread].self, from: data)
            next = Self.nextLink(http.value(forHTTPHeaderField: "Link"))
            page += 1
        }
        return FetchResult(threads: all, lastModified: lastModified, pollInterval: pollInterval)
    }

    /// Open pull requests currently waiting on your review (direct or via a team).
    func reviewRequests() async throws -> [ReviewRequest] {
        var c = URLComponents(url: api.appendingPathComponent("search/issues"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "q", value: "is:open is:pr review-requested:@me archived:false"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        struct Page: Decodable { let items: [ReviewRequest] }
        return try await fetch(Page.self, c.url!).items
    }

    private var cachedLogin: String?

    func viewerLogin() async -> String? {
        if let cachedLogin { return cachedLogin }
        struct Me: Decodable { let login: String }
        cachedLogin = try? await fetch(Me.self, api.appendingPathComponent("user")).login
        return cachedLogin
    }

    /// Who most recently asked `login` (or one of their teams) to review this PR.
    func requester(for pr: ReviewRequest, login: String?) async -> String? {
        struct Event: Decodable {
            struct User: Decodable { let login: String }
            struct Team: Decodable { let slug: String }
            let event: String
            let actor: User?
            let requested_reviewer: User?
            let requested_team: Team?
        }
        var c = URLComponents(url: api.appendingPathComponent("repos/\(pr.repoFullName)/issues/\(pr.number)/events"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = c.url, let events = try? await fetch([Event].self, url) else { return nil }
        let match = events.last { e in
            e.event == "review_requested" && (e.requested_reviewer?.login == login || e.requested_team != nil)
        }
        return match?.actor?.login
    }

    func markRead(threadId: String) async throws {
        let url = api.appendingPathComponent("notifications/threads/\(threadId)")
        let (data, response) = try await session.data(for: request(url, method: "PATCH"))
        _ = try check(response, data)
    }

    func markAllRead() async throws {
        var req = request(api.appendingPathComponent("notifications"), method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{\"read\":true}".utf8)
        let (data, response) = try await session.data(for: req)
        _ = try check(response, data)
    }

    /// Resolves what actually happened on a thread and where to open it.
    func details(for thread: GitHubThread) async -> ThreadDetail {
        let repoURL = URL(string: thread.repository.htmlURL) ?? URL(string: "https://github.com/notifications")!
        let number = thread.subject.url.flatMap { URL(string: $0)?.lastPathComponent }.flatMap(Int.init)

        guard let apiString = thread.subject.url, let apiURL = URL(string: apiString) else {
            if let run = CIRun(title: thread.subject.title) {
                var c = URLComponents(url: repoURL.appendingPathComponent("actions"), resolvingAgainstBaseURL: false)!
                c.queryItems = [URLQueryItem(name: "query", value: "branch:\(run.branch)")]
                return ThreadDetail(url: c.url ?? repoURL, number: nil, summary: run.summary)
            }
            switch thread.subject.type {
            case "CheckSuite", "WorkflowRun":
                return ThreadDetail(url: repoURL.appendingPathComponent("actions"), number: nil, summary: nil)
            case "Discussion":
                return ThreadDetail(url: repoURL.appendingPathComponent("discussions"), number: nil, summary: nil)
            default:
                return ThreadDetail(url: repoURL, number: nil, summary: nil)
            }
        }
        let fallbackURL = Self.rewrite(apiURL) ?? repoURL

        // A distinct latest comment is the most specific thing to show.
        if let comment = thread.subject.latestCommentURL, comment != apiString,
           let commentURL = URL(string: comment),
           let item = try? await fetch(APIItem.self, commentURL) {
            let who = item.user?.login.map { "@\($0)" } ?? "Someone"
            let verb = item.tagName != nil ? "released \(item.tagName!)" : "commented"
            let body = item.body.map(Self.snippet).flatMap { $0.isEmpty ? nil : $0 }
            let summary = body.map { "\(who) \(verb): \($0)" } ?? "\(who) \(verb)"
            return ThreadDetail(url: item.htmlURL.flatMap(URL.init(string:)) ?? fallbackURL,
                                number: number, summary: summary)
        }

        guard let subject = try? await fetch(APIItem.self, apiURL) else {
            return ThreadDetail(url: fallbackURL, number: number, summary: nil)
        }
        let url = subject.htmlURL.flatMap(URL.init(string:)) ?? fallbackURL

        // For PRs, a review submitted around the notification time is usually the news.
        if thread.subject.type == "PullRequest",
           let review = await latestReview(apiURL), Self.near(review.submittedAt, thread.updatedAt) {
            let who = review.user?.login.map { "@\($0)" } ?? "Someone"
            let verb: String
            switch review.state {
            case "APPROVED": verb = "approved"
            case "CHANGES_REQUESTED": verb = "requested changes"
            case "DISMISSED": verb = "had a review dismissed"
            default: verb = "reviewed"
            }
            let body = review.body.map(Self.snippet).flatMap { $0.isEmpty ? nil : $0 }
            let reviewURL = review.htmlURL.flatMap(URL.init(string:)) ?? url
            return ThreadDetail(url: reviewURL, number: number,
                                summary: body.map { "\(who) \(verb): \($0)" } ?? "\(who) \(verb)")
        }
        return ThreadDetail(url: url, number: number, summary: Self.stateSummary(subject, type: thread.subject.type))
    }

    func htmlURL(for thread: GitHubThread) async -> URL {
        await details(for: thread).url
    }

    private func fetch<T: Decodable>(_ type: T.Type, _ url: URL) async throws -> T {
        let (data, response) = try await session.data(for: request(url))
        _ = try check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func latestReview(_ pullURL: URL) async -> APIReview? {
        var c = URLComponents(url: pullURL.appendingPathComponent("reviews"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = c.url, let reviews = try? await fetch([APIReview].self, url) else { return nil }
        return reviews.filter { $0.state != "PENDING" }.max { ($0.submittedAt ?? "") < ($1.submittedAt ?? "") }
    }

    private static func stateSummary(_ item: APIItem, type: String) -> String? {
        let author = item.user?.login.map { " by @\($0)" } ?? ""
        switch type {
        case "PullRequest":
            if item.merged == true || item.mergedAt != nil {
                return "Merged" + (item.mergedBy?.login.map { " by @\($0)" } ?? "")
            }
            if item.state == "closed" { return "Closed without merging" }
            return (item.draft == true ? "Draft" : "Open") + author
        case "Issue":
            if item.state == "closed" {
                return item.stateReason == "not_planned" ? "Closed as not planned" : "Closed as completed"
            }
            return "Open" + author
        case "Release":
            return "Released \(item.tagName ?? "")" + (item.author?.login.map { " by @\($0)" } ?? "")
        default:
            return nil
        }
    }

    /// True when a review landed within a few minutes of the notification's update.
    private static func near(_ a: String?, _ b: String) -> Bool {
        let f = ISO8601DateFormatter()
        guard let a, let da = f.date(from: a), let db = f.date(from: b) else { return false }
        return abs(da.timeIntervalSince(db)) < 300
    }

    /// First meaningful line of a markdown body, flattened to plain text and trimmed for a banner.
    static func snippet(_ body: String) -> String {
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<") || line.hasPrefix(">") || line.hasPrefix("![") { continue }
            if line.range(of: #"^\[[^\]]+\]:"#, options: .regularExpression) != nil { continue } // link refs, bot metadata
            let cleaned = line
                .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            // Skip lines that were only a reply reference such as "Re: <link>".
            if cleaned.isEmpty || cleaned.range(of: #"^(Re|re|RE):?$"#, options: .regularExpression) != nil { continue }
            return cleaned.count > 140 ? String(cleaned.prefix(139)) + "…" : cleaned
        }
        return ""
    }

    /// Offline fallback: api.github.com/repos/o/r/pulls/1 -> github.com/o/r/pull/1
    static func rewrite(_ apiURL: URL) -> URL? {
        var path = apiURL.path
        guard path.hasPrefix("/repos/") else { return nil }
        path.removeFirst("/repos".count)
        path = path.replacingOccurrences(of: "/pulls/", with: "/pull/")
            .replacingOccurrences(of: "/commits/", with: "/commit/")
        return URL(string: "https://github.com" + path)
    }

    static func nextLink(_ header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces[1...].contains("rel=\"next\"") else { continue }
            return URL(string: pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
        }
        return nil
    }
}

struct ThreadDetail: Equatable {
    let url: URL
    let number: Int?
    /// What happened, e.g. "@sam approved" or "@kim commented: looks good".
    let summary: String?
}

/// Loose shape shared by issues, pull requests, comments and releases.
private struct APIItem: Decodable {
    struct User: Decodable { let login: String? }
    let htmlURL: String?
    let state: String?
    let stateReason: String?
    let merged: Bool?
    let mergedAt: String?
    let mergedBy: User?
    let draft: Bool?
    let user: User?
    let author: User?
    let body: String?
    let tagName: String?

    enum CodingKeys: String, CodingKey {
        case state, merged, draft, user, author, body
        case htmlURL = "html_url"
        case stateReason = "state_reason"
        case mergedAt = "merged_at"
        case mergedBy = "merged_by"
        case tagName = "tag_name"
    }
}

private struct APIReview: Decodable {
    let user: APIItem.User?
    let state: String
    let body: String?
    let htmlURL: String?
    let submittedAt: String?

    enum CodingKeys: String, CodingKey {
        case user, state, body
        case htmlURL = "html_url"
        case submittedAt = "submitted_at"
    }
}

/// Parses GitHub's CI notification titles: "<workflow> workflow run <outcome> for <branch> branch".
struct CIRun {
    let workflow: String
    let outcome: String
    let branch: String

    init?(title: String) {
        guard let runRange = title.range(of: " workflow run "),
              let forRange = title.range(of: " for ", range: runRange.upperBound..<title.endIndex)
        else { return nil }
        workflow = String(title[..<runRange.lowerBound])
        outcome = String(title[runRange.upperBound..<forRange.lowerBound])
        var rest = String(title[forRange.upperBound...])
        if rest.hasSuffix(" branch") { rest.removeLast(" branch".count) }
        branch = rest
    }

    var summary: String {
        let mark: String
        switch outcome {
        case "failed": mark = "✗ Failed"
        case "succeeded": mark = "✓ Succeeded"
        case "cancelled": mark = "Cancelled"
        default: mark = outcome.capitalized
        }
        return "\(mark) on \(branch)"
    }
}

/// A pull request from the `review-requested:@me` search.
struct ReviewRequest: Decodable, Identifiable, Equatable {
    struct User: Decodable, Equatable { let login: String }
    let number: Int
    let title: String
    let htmlURL: String
    let repositoryURL: String
    let updatedAt: String
    let draft: Bool?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case number, title, draft, user
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
        case updatedAt = "updated_at"
    }

    var id: String { htmlURL }

    /// "https://api.github.com/repos/o/r" -> "o/r"
    var repoFullName: String {
        repositoryURL.components(separatedBy: "/repos/").last ?? repositoryURL
    }
}
