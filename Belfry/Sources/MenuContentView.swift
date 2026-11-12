import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.bannersAllowed == false { permissionWarning }
            tabs
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 400)
        .onAppear { store.refreshBannerPermission() }
    }

    private var header: some View {
        HStack {
            Text("Notifications").font(.headline)
            if store.unreadCount > 0 {
                Text("\(store.unreadCount)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            }
            Spacer()
            if store.isRefreshing { ProgressView().controlSize(.small) }
            Button { store.refreshNow() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
            Button("Mark all read") { store.markAllRead() }
                .buttonStyle(.borderless)
                .disabled(store.unreadCount == 0)
        }
        .padding(10)
    }

    private var permissionWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            Text("macOS is blocking Belfry's banners.").font(.callout)
            Spacer()
            Button("Fix…") { store.openNotificationSettings() }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    private var tabs: some View {
        Picker("", selection: $store.selectedTab) {
            ForEach(ThreadTab.allCases) { tab in
                let n = store.count(for: tab)
                Text(n > 0 ? "\(tab.label) \(n)" : tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                if !store.hasToken {
                    Button("Open Settings…") { showSettings() }
                }
            }
            .padding(12)
        } else if store.selectedTab == .review {
            reviewList
        } else if store.groupedByRepo.isEmpty {
            Text(store.lastChecked == nil ? "Checking GitHub…"
                 : store.selectedTab != .all && !store.threads.isEmpty ? "Nothing in \(store.selectedTab.label)."
                 : store.hiddenCount > 0 ? "Nothing to show. \(store.hiddenCount) CI runs hidden."
                 : "You're all caught up.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(store.groupedByRepo, id: \.repo) { group in
                        Section {
                            ForEach(group.threads) { ThreadRow(thread: $0) }
                        } header: {
                            Text(group.repo)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.bar)
                        }
                    }
                }
            }
            // A ScrollView has no ideal height inside a MenuBarExtra window, so size it explicitly.
            .frame(height: listHeight)
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        if store.reviewRequests.isEmpty {
            Text("No pull requests are waiting on your review.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.reviewRequests) { ReviewRow(pr: $0) }
                }
            }
            .frame(height: min(max(CGFloat(store.reviewRequests.count) * 70, 80), 460))
        }
    }

    private var listHeight: CGFloat {
        let rows = store.groupedByRepo.reduce(0) { $0 + $1.threads.count }
        let estimate = CGFloat(rows) * 66 + CGFloat(store.groupedByRepo.count) * 24
        return min(max(estimate, 80), 460)
    }

    private var footer: some View {
        HStack {
            Picker("", selection: $store.ciFilter) {
                ForEach(CIFilter.allCases) { Text("CI: \($0.label)").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Which CI runs to show and announce")
            if let checked = store.lastChecked {
                Text("Checked \(checked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings…") { showSettings() }.buttonStyle(.borderless)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
        .padding(10)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

struct ThreadRow: View {
    @EnvironmentObject private var store: NotificationStore
    let thread: GitHubThread
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: thread.typeSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayTitle).lineLimit(2)
                if let summary = detail?.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(summary.hasPrefix("✗") ? Color.red : Color.primary.opacity(0.8))
                        .lineLimit(2)
                }
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { store.markRead(thread) } label: { Image(systemName: "checkmark") }
                .buttonStyle(.borderless)
                .help("Mark as read")
                .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.open(thread) }
        .onAppear { store.loadDetail(for: thread) }
        .help("Open in browser")
    }

    private var detail: ThreadDetail? { store.detail(for: thread) }

    private var meta: String {
        let number = detail?.number.map { "#\($0) · " } ?? ""
        return "\(number)\(thread.reasonLabel) · \(Self.relative(thread.updatedAt))"
    }

    private static let parser = ISO8601DateFormatter()
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ iso: String) -> String {
        guard let date = parser.date(from: iso) else { return iso }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ReviewRow: View {
    @EnvironmentObject private var store: NotificationStore
    let pr: ReviewRequest
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye")
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title).lineLimit(2)
                Text(requestLine)
                    .font(.callout)
                    .foregroundStyle(Color.primary.opacity(0.8))
                Text("\(pr.repoFullName) #\(pr.number)\(pr.draft == true ? " · draft" : "") · updated \(ThreadRow.relative(pr.updatedAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.open(pr) }
        .help("Open in browser")
    }

    private var requestLine: String {
        let author = pr.user.map { "by @\($0.login)" } ?? ""
        if let who = store.requesters[pr.id] {
            return who == pr.user?.login ? "@\(who) asked for your review" : "@\(who) asked for your review · \(author)"
        }
        return "Waiting for your review \(author)"
    }
}
