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
        case "ci_activity": return "CI"
        case "assign": return "Assigned"
        case "author": return "Activity on your thread"
        case "state_change": return "State changed"
        case "subscribed": return "Watching"
        case "manual": return "Subscribed"
        case "approval_requested": return "Approval requested"
        case "security_alert": return "Security alert"
        case "invitation": return "Invitation"
        case "member_feature_requested": return "Feature requested"
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
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

    /// Turns a thread's API subject URL into the page a person would open.
    func htmlURL(for thread: GitHubThread) async -> URL {
        let repoURL = URL(string: thread.repository.htmlURL) ?? URL(string: "https://github.com/notifications")!
        guard let apiString = thread.subject.url, let apiURL = URL(string: apiString) else {
            switch thread.subject.type {
            case "CheckSuite", "WorkflowRun": return repoURL.appendingPathComponent("actions")
            case "Discussion": return repoURL.appendingPathComponent("discussions")
            default: return repoURL
            }
        }
        // Prefer the latest comment's anchor when it points somewhere other than the subject itself.
        if let comment = thread.subject.latestCommentURL, comment != apiString,
           let commentURL = URL(string: comment),
           let html = try? await fetchHTMLURL(commentURL) {
            return html
        }
        if let html = try? await fetchHTMLURL(apiURL) { return html }
        return Self.rewrite(apiURL) ?? repoURL
    }

    private func fetchHTMLURL(_ url: URL) async throws -> URL? {
        let (data, response) = try await session.data(for: request(url))
        _ = try check(response, data)
        struct HTML: Decodable { let html_url: String? }
        return try JSONDecoder().decode(HTML.self, from: data).html_url.flatMap(URL.init(string:))
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
