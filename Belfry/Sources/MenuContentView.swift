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
        VStack(spacing: 0) {
            mainTabs
            if store.selectedTab == .pullRequests { prSubTabs }
        }
    }

    private var mainTabs: some View {
        FlowLayout(spacing: 4) {
            ForEach(ThreadTab.allCases) { tab in
                TabChip(label: tab.label, count: store.count(for: tab), selected: store.selectedTab == tab) {
                    store.selectedTab = tab
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    /// Review is always offered; other categories appear only when they have items.
    private var prSubTabs: some View {
        let visible = PRSubTab.allCases.filter {
            $0 == .all || $0 == .review || $0 == store.prSubTab || store.count(for: $0) > 0
        }
        return FlowLayout(spacing: 4) {
            ForEach(visible) { sub in
                TabChip(label: sub.label,
                        count: sub == .all ? store.count(for: .pullRequests) : store.count(for: sub),
                        selected: store.prSubTab == sub,
                        small: true) {
                    store.prSubTab = sub
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        } else if store.selectedTab == .pullRequests && store.prSubTab == .review {
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
            ScrollView(.vertical) {
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
            ScrollView(.vertical) {
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
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            Button { store.markRead(thread) } label: { Image(systemName: "checkmark") }
                .buttonStyle(.borderless)
                .help("Mark as read")
                .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(requestLine).lineLimit(2)
                    .font(.callout)
                    .foregroundStyle(Color.primary.opacity(0.8))
                Text("\(pr.repoFullName) #\(pr.number)\(pr.draft == true ? " · draft" : "") · updated \(ThreadRow.relative(pr.updatedAt))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// A tab rendered as a compact pill with an optional count.
struct TabChip: View {
    let label: String
    let count: Int
    let selected: Bool
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                if count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .font(small ? .caption : .callout)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, small ? 7 : 9)
            .padding(.vertical, small ? 2 : 3)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(small ? 0.05 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out left to right and wraps onto new lines instead of overflowing.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
