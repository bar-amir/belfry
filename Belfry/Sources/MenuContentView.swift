import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Namespace private var tabs

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.bannersAllowed == false && store.hasToken {
                FlashBar(symbol: "bell.slash.fill", color: Theme.attention, text: "Banners are off for Belfry in macOS.",
                         action: ("Turn on…", store.openNotificationSettings))
            }
            if !store.hasToken {
                TokenEntryView(kind: .welcome)
            } else if store.problem == .badToken {
                TokenEntryView(kind: .repair)
            } else {
                controls
                if let problem = store.problem {
                    FlashBar(symbol: problem == .offline ? "wifi.slash" : "exclamationmark.triangle.fill",
                             color: Theme.attention, text: problemText(problem), action: ("Try again", store.refreshNow))
                }
                content
                footer
            }
        }
        .frame(width: 440)
        .background(SpaceBackground())
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            store.refreshBannerPermission()
        }
        .onKeyPress(.upArrow) { store.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { store.moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { openSelection(); return .handled }
        .onKeyPress(.escape) {
            if !store.search.isEmpty { store.search = ""; return .handled }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "emEM/")) { press in
            guard !searchFocused else { return .ignored }
            switch press.characters.lowercased() {
            case "e": if let item = store.selectedItem { withAnimation(rowSpring) { store.markDone([item]) } }
            case "m": if let item = store.selectedItem { withAnimation(rowSpring) { store.mute([item]) } }
            default: searchFocused = true
            }
            return .handled
        }
        .background(shortcuts)
    }

    private var rowSpring: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .glow(Color(hex: "#6E7BFF"), radius: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Inbox")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if store.hasToken && store.unreadCount > 0 { Counter(count: store.unreadCount, lit: true) }
                }
                Text(statusLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if store.hasToken {
                Button { store.refreshNow() } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                        .animation(store.isRefreshing && !reduceMotion
                                   ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                   value: store.isRefreshing)
                }
                .buttonStyle(IconButtonStyle())
                .help("Check GitHub now (⌘R)")
                .accessibilityLabel(store.isRefreshing ? "Checking GitHub" : "Check GitHub now")
            }
            moreMenu
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.bar)
    }

    private var statusLine: String {
        guard store.hasToken else { return "Not connected" }
        if store.problem == .badToken { return "Token stopped working" }
        let who = store.login.map { "@\($0)" } ?? "GitHub"
        guard let checked = store.lastChecked else { return "\(who) · checking…" }
        return "\(who) · checked \(checked.formatted(date: .omitted, time: .shortened))"
    }

    private var moreMenu: some View {
        Menu {
            Button("Settings…") { showSettings() }.keyboardShortcut(",")
            Button("Open GitHub Notifications") {
                NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
            }
            Divider()
            Button("Quit Belfry") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .glass(cornerRadius: 8)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    private func problemText(_ problem: FetchProblem) -> String {
        switch problem {
        case .offline:
            let since = store.lastChecked.map { " Showing what was there at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
            return "Can't reach GitHub." + since
        case .badToken: return "Your GitHub token stopped working."
        case let .other(message): return message
        }
    }

    // MARK: Search and tabs

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, 10)
            underlineNav
            if store.selectedTab == .pullRequests {
                prFilters
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(rowSpring, value: store.selectedTab)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.secondaryText)
            TextField("", text: $store.search, prompt: Text("Filter by title, repo or #number").foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onSubmit { listFocused = true; store.moveSelection(by: 1) }
            if store.search.isEmpty {
                Kbd("⌘F")
            } else {
                Button { store.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#05080F").opacity(0.85)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(searchFocused ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Theme.hairlineStrong),
                        lineWidth: searchFocused ? 1.5 : 1)
        )
        .glow(searchFocused ? Theme.accent : .clear, radius: 6)
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }

    /// GitHub-style underline tabs; the lit bar glides to the selected tab.
    private var underlineNav: some View {
        HStack(spacing: 2) {
            ForEach(ThreadTab.allCases) { tab in
                let n = store.count(for: tab)
                if tab != .other || n > 0 || store.selectedTab == .other {
                    let selected = store.selectedTab == tab
                    Button {
                        withAnimation(rowSpring) {
                            store.selectedTab = tab
                            store.selection = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.label)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                            if n > 0 { Counter(count: n) }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(Theme.aurora)
                                    .frame(height: 2.5)
                                    .glow(Theme.accent, radius: 5)
                                    .matchedGeometryEffect(id: "underline", in: tabs)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            ciFilterMenu
        }
        .padding(.horizontal, Spacing.gutter - 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var prFilters: some View {
        FlowLayout(spacing: 6) {
            ForEach(PRSubTab.allCases.filter {
                $0 == .all || $0 == .review || $0 == store.prSubTab || store.count(for: $0) > 0
            }) { sub in
                let n = sub == .all ? store.count(for: .pullRequests) : store.count(for: sub)
                let selected = store.prSubTab == sub
                Button {
                    withAnimation(rowSpring) {
                        store.prSubTab = sub
                        store.selection = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(sub.label)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                        if n > 0 {
                            Text(verbatim: "\(n)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected ? Theme.accent : Theme.tertiaryText)
                                .contentTransition(.numericText(value: Double(n)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.16))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent.opacity(0.55)))
                                .matchedGeometryEffect(id: "prpill", in: tabs)
                        } else {
                            RoundedRectangle(cornerRadius: 7).fill(Theme.glass)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ciFilterMenu: some View {
        Menu {
            Picker("CI runs", selection: $store.ciFilter) {
                ForEach(CIFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Group runs by branch", isOn: $store.groupCI)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(store.ciFilter.shortLabel)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(store.ciFilter == .all ? Theme.secondaryText : Theme.accent)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(store.ciFilter == .all ? Theme.glass : Theme.accent.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(store.ciFilter == .all ? Theme.hairline : Theme.accent.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Which CI runs to show and announce")
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if store.lastChecked == nil && store.allThreads.isEmpty {
            ShimmerRows()
        } else if store.showingReviews {
            if store.visibleReviews.isEmpty {
                EmptyStateView(title: "Nothing waiting on your review",
                               message: "Pull requests where someone asks for your review land here.")
            } else {
                MeasuredScroll {
                    VStack(spacing: 0) {
                        ForEach(store.visibleReviews) { pr in
                            ReviewRow(pr: pr, selected: store.selection == pr.id)
                            if pr.id != store.visibleReviews.last?.id { RowDivider() }
                        }
                    }
                    .glass(cornerRadius: 12)
                    .padding(Spacing.gutter)
                }
            }
        } else if store.groupedByRepo.isEmpty {
            emptyState
        } else {
            MeasuredScroll {
                LazyVStack(spacing: 12) {
                    ForEach(store.groupedByRepo, id: \.repo) { group in
                        RepoBox(repo: group.repo, items: group.items)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(Spacing.gutter)
                .animation(rowSpring, value: store.flatVisibleItems.map(\.id))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = store.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            EmptyStateView(title: "No notifications match “\(query)”",
                           message: "Try fewer words, a repo name or a #number.",
                           action: ("Clear filter", { store.search = "" }))
        } else if store.selectedTab != .all && !store.threads.isEmpty {
            EmptyStateView(title: "Nothing in \(store.selectedTab.label)",
                           message: "The other tabs still have notifications.",
                           action: ("Show all", { store.selectedTab = .all }))
        } else if store.hiddenByFilter > 0 {
            EmptyStateView(title: "You're all caught up",
                           message: "\(store.hiddenByFilter) CI runs are hidden by your filter.",
                           action: ("Show all CI runs", { store.ciFilter = .all }))
        } else {
            EmptyStateView(title: "You're all caught up", message: "Nothing new in orbit.")
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        Group {
            if let pending = store.pending {
                HStack(spacing: Spacing.item) {
                    Image(systemName: pending.kind == .mute ? "bell.slash.fill" : "checkmark.seal.fill")
                        .foregroundStyle(Theme.open)
                        .glow(Theme.open, radius: 6)
                        .symbolEffect(.bounce, value: pending.message)
                    Text(pending.message)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { withAnimation(rowSpring) { store.undo() } } label: {
                        HStack(spacing: 6) { Text("Undo"); Kbd("⌘Z") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    KeyHint(keys: ["↑", "↓"], label: "move")
                    KeyHint(keys: ["↵"], label: "open")
                    if !store.showingReviews {
                        KeyHint(keys: ["E"], label: "done")
                        KeyHint(keys: ["M"], label: "mute")
                    }
                    Spacer()
                    if !store.showingReviews {
                        let total = store.flatVisibleItems.count
                        Button { withAnimation(rowSpring) { store.doneAllVisible() } } label: {
                            Label(total > 0 ? "Done with \(total)" : "Done", systemImage: "checkmark")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(total == 0)
                        .help("Mark everything in this view done (⌘⌫). You can undo for a few seconds.")
                        .keyboardShortcut(.delete, modifiers: .command)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(height: 54)
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .animation(rowSpring, value: store.pending)
    }

    /// Invisible buttons that carry the panel's keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { searchFocused = true }.keyboardShortcut("f")
            Button("") { store.refreshNow() }.keyboardShortcut("r")
            Button("") { withAnimation(rowSpring) { store.undo() } }.keyboardShortcut("z")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func openSelection() {
        if store.showingReviews {
            if let pr = store.visibleReviews.first(where: { $0.id == store.selection }) { store.open(pr) }
        } else if let item = store.selectedItem {
            store.open(item)
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

// MARK: - Bars

struct FlashBar: View {
    let symbol: String
    let color: Color
    let text: String
    let action: (String, () -> Void)

    var body: some View {
        HStack(spacing: Spacing.item) {
            Image(systemName: symbol).foregroundStyle(color).glow(color, radius: 4)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Spacer()
            Button(action.0, action: action.1).buttonStyle(SecondaryButtonStyle(height: 24))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.45)))
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, 8)
    }
}

// MARK: - Rows

/// How a row presents its state: GitHub's state colours, a reason label, and whether the icon pulses.
struct RowStyle {
    let symbol: String
    let color: Color
    var line: Color = Theme.text
    let reason: String
    let reasonColor: Color
    var pulse = false

    static func of(_ item: InboxItem, detail: ThreadDetail?) -> RowStyle {
        let t = item.primary
        if t.isCI {
            if item.threads.contains(where: \.isCIFailure) {
                return RowStyle(symbol: "xmark.circle.fill", color: Theme.danger, line: Theme.danger,
                                reason: "CI failed", reasonColor: Theme.danger, pulse: true)
            }
            if CIRun(title: t.subject.title)?.outcome == "succeeded" {
                return RowStyle(symbol: "checkmark.circle.fill", color: Theme.open, line: Theme.open,
                                reason: "CI passed", reasonColor: Theme.open)
            }
            return RowStyle(symbol: "circle.dotted", color: Theme.attention, reason: "CI", reasonColor: Theme.attention)
        }
        let tags = detail?.tags ?? []
        let closed = tags.contains(.closed)
        let merged = closed && detail?.summary?.hasPrefix("Merged") == true
        let symbol: String
        let color: Color
        switch t.subject.type {
        case "PullRequest":
            symbol = merged ? "arrow.triangle.merge" : "arrow.triangle.pull"
            color = merged ? Theme.merged : (closed ? Theme.danger : Theme.open)
        case "Issue":
            symbol = closed ? "checkmark.circle" : "smallcircle.filled.circle"
            color = closed ? Theme.merged : Theme.open
        case "Release": symbol = "tag.fill"; color = Theme.open
        case "Discussion": symbol = "bubble.left.and.bubble.right.fill"; color = Theme.accent
        default: symbol = "bell.fill"; color = Theme.secondaryText
        }
        if t.reason == "review_requested" {
            return RowStyle(symbol: symbol, color: color, reason: "Review requested", reasonColor: Theme.accent, pulse: true)
        }
        if tags.contains(.changesRequested) {
            return RowStyle(symbol: symbol, color: color, reason: "Changes requested", reasonColor: Theme.attention)
        }
        if tags.contains(.approved) {
            return RowStyle(symbol: symbol, color: color, reason: "Approved", reasonColor: Theme.open)
        }
        if merged { return RowStyle(symbol: symbol, color: color, reason: "Merged", reasonColor: Theme.merged) }
        if closed { return RowStyle(symbol: symbol, color: color, reason: "Closed", reasonColor: Theme.danger) }
        if t.reason == "mention" || t.reason == "team_mention" {
            return RowStyle(symbol: symbol, color: color, reason: "Mentioned", reasonColor: Theme.attention)
        }
        if tags.contains(.comment) {
            return RowStyle(symbol: symbol, color: color, reason: "Comment", reasonColor: Theme.secondaryText)
        }
        return RowStyle(symbol: symbol, color: color, reason: t.reasonLabel, reasonColor: Theme.secondaryText)
    }
}

/// A state icon with a soft glow; it breathes when it wants attention (failed CI, review requested).
struct StateIcon: View {
    let style: RowStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: style.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(style.color)
            .glow(style.color, radius: 5)
            .symbolEffect(.pulse, options: .repeating, isActive: style.pulse && !reduceMotion)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 40) }
}

/// One repository: a glass box with a header and its rows.
struct RepoBox: View {
    @EnvironmentObject private var store: NotificationStore
    let repo: String
    let items: [InboxItem]
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                repoName
                Spacer(minLength: 8)
                Counter(count: items.count)
                Button { store.doneAll(inRepo: repo) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(IconButtonStyle(size: 24, tint: hovering ? Theme.text : Theme.tertiaryText))
                    .help("Mark everything in \(repo) done")
                    .accessibilityLabel("Mark everything in \(repo) done")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.white.opacity(0.03))
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ForEach(items) { item in
                ItemRow(item: item, selected: store.selection == item.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(x: 60)).combined(with: .scale(scale: 0.96, anchor: .trailing))))
                if item.id != items.last?.id { RowDivider() }
            }
        }
        .glass(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
    }

    private var repoName: some View {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        return (Text(parts.first.map { $0 + "/" } ?? "").foregroundStyle(Theme.secondaryText)
                + Text(parts.count > 1 ? parts[1] : repo).foregroundStyle(Theme.text).bold())
            .font(.system(size: 12.5))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct ItemRow: View {
    @EnvironmentObject private var store: NotificationStore
    let item: InboxItem
    let selected: Bool
    @State private var hovering = false

    private var detail: ThreadDetail? { store.detail(for: item.primary) }
    private var runs: [CIRun] { item.threads.compactMap { CIRun(title: $0.subject.title) } }

    /// CI rows are named after their workflows; everything else after its subject.
    private var title: String {
        guard item.primary.isCI, !runs.isEmpty else { return item.primary.displayTitle }
        let names = runs.map(\.workflow).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return names.prefix(3).joined(separator: " · ") + (names.count > 3 ? " …" : "")
    }

    private var summary: String? {
        guard item.primary.isCI, !runs.isEmpty else { return detail?.summary }
        let failed = item.threads.filter(\.isCIFailure).count
        if item.count == 1 { return runs[0].outcome == "failed" ? "Failed" : runs[0].outcome.capitalized }
        return failed > 0 ? "\(failed) of \(item.count) runs failed" : "\(item.count) runs passed"
    }

    /// The person behind the latest activity, from "@login …" in the summary.
    private var actor: String? {
        guard let summary, let range = summary.range(of: #"@[A-Za-z0-9-]+(\[bot\])?"#, options: .regularExpression)
        else { return nil }
        return String(summary[range].dropFirst())
    }

    var body: some View {
        let style = RowStyle.of(item, detail: detail)
        HStack(alignment: .top, spacing: 10) {
            StateIcon(style: style)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.trailing, 58)
                if let summary {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let actor { Identicon(login: actor, size: 15).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 } }
                        Text(summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(style.line.opacity(style.line == Theme.text ? 0.86 : 1))
                            .lineLimit(2)
                    }
                } else {
                    ShimmerBar(width: 190)
                }
                HStack(spacing: 6) {
                    LabelPill(text: style.reason, color: style.reasonColor)
                    if let number = detail?.number {
                        Text(verbatim: "#\(number)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let branch = runs.first?.branch, item.primary.isCI { BranchPill(name: branch) }
                    if item.count > 1 {
                        Text(verbatim: "\(item.count) runs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) { trailing }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                if selected {
                    Theme.accent.opacity(0.13)
                    Capsule().fill(Theme.aurora).frame(width: 3).padding(.vertical, 6).glow(Theme.accent, radius: 4)
                } else if hovering {
                    Color.white.opacity(0.045)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture { store.selection = item.id; store.open(item) }
        .onAppear { store.loadDetail(for: item.primary) }
        .contextMenu {
            Button("Open in Browser") { store.open(item) }
            Button("Copy Link") { store.copyLink(item) }
            Divider()
            Button("Mark Done") { withAnimation { store.markDone([item]) } }
            Button("Mute Thread") { withAnimation { store.mute([item]) } }
            Divider()
            Button("Mark Everything in \(item.repo) Done") { withAnimation { store.doneAll(inRepo: item.repo) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.reason). \(title). \(summary ?? ""). \(meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.open(item) }
        .accessibilityAction(named: "Mark done") { store.markDone([item]) }
        .accessibilityAction(named: "Mute") { store.mute([item]) }
    }

    private var meta: String {
        [detail?.number.map { "#\($0)" }, item.primary.reasonLabel].compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder
    private var trailing: some View {
        if hovering || selected {
            HStack(spacing: 4) {
                Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { store.markDone([item]) } } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(IconButtonStyle(size: 26, tint: Theme.open))
                .help("Mark done (E)")
                .accessibilityLabel("Mark done")
                Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { store.mute([item]) } } label: {
                    Image(systemName: "bell.slash")
                }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Mute this thread (M)")
                .accessibilityLabel("Mute")
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
        } else {
            Text(ItemRow.short(item.primary.updatedAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
        }
    }

    private static let parser = ISO8601DateFormatter()

    /// "now", "4m", "3h", "2d", then a date.
    static func short(_ iso: String) -> String {
        guard let date = parser.date(from: iso) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

struct ReviewRow: View {
    @EnvironmentObject private var store: NotificationStore
    let pr: ReviewRequest
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let requester = store.requesters[pr.id]
        HStack(alignment: .top, spacing: 10) {
            StateIcon(style: RowStyle(symbol: "arrow.triangle.pull", color: Theme.open, reason: "Review requested",
                                      reasonColor: Theme.accent, pulse: true))
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.trailing, 36)
                HStack(spacing: 6) {
                    if let who = requester ?? pr.user?.login { Identicon(login: who, size: 15) }
                    Text(requestLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text.opacity(0.86))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    LabelPill(text: "Review requested", color: Theme.accent)
                    Text("\(pr.repoFullName) #\(pr.number)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if pr.draft == true { LabelPill(text: "Draft", color: Theme.secondaryText) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Text(ItemRow.short(pr.updatedAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                if selected {
                    Theme.accent.opacity(0.13)
                    Capsule().fill(Theme.aurora).frame(width: 3).padding(.vertical, 6)
                } else if hovering {
                    Color.white.opacity(0.045)
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.selection = pr.id; store.open(pr) }
        .contextMenu {
            Button("Open in Browser") { store.open(pr) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.htmlURL, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.open(pr) }
    }

    private var requestLine: String {
        let who = store.requesters[pr.id]
        let author = pr.user?.login
        switch (who, author) {
        case let (who?, author?) where who != author: return "@\(who) asked for your review on @\(author)'s PR"
        case let (who?, _): return "@\(who) asked for your review"
        case let (nil, author?): return "Waiting for your review on @\(author)'s PR"
        default: return "Waiting for your review"
        }
    }
}

// MARK: - States

/// Inbox zero: a small planet with an orbiting moon.
struct OrbitView: View {
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0.8 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width * 0.22
                let angle = t * 0.8
                let moon = CGPoint(x: c.x + cos(angle) * r * 1.9, y: c.y + sin(angle) * r * 0.7)
                let ring = Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 0.7, width: r * 3.8, height: r * 1.4))
                ctx.stroke(ring, with: .color(.white.opacity(0.18)), lineWidth: 1)
                let moonBehind = sin(angle) < 0
                let moonPath = Path(ellipseIn: CGRect(x: moon.x - 3.5, y: moon.y - 3.5, width: 7, height: 7))
                if moonBehind { ctx.fill(moonPath, with: .color(Color(hex: "#39D0E6"))) }
                var glow = ctx
                glow.addFilter(.blur(radius: 10))
                glow.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(Color(hex: "#6E7BFF").opacity(0.8)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .linearGradient(Gradient(colors: [Color(hex: "#A371F7"), Color(hex: "#58A6FF"), Color(hex: "#39D0E6")]),
                                               startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
                if !moonBehind { ctx.fill(moonPath, with: .color(Color(hex: "#39D0E6"))) }
            }
        }
        .frame(width: size * 1.6, height: size)
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            OrbitView(size: 64)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

/// A placeholder bar with a light sweep, for text that is still loading.
struct ShimmerBar: View {
    var width: CGFloat
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.glassStrong)
                .overlay(
                    LinearGradient(colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.5)
                        .offset(x: (phase * 1.6 - 0.55) * width)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: width, height: height)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}

struct ShimmerRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.glassStrong).frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 5) {
                        ShimmerBar(width: 230, height: 11)
                        ShimmerBar(width: 300)
                        ShimmerBar(width: 120, height: 9)
                    }
                }
                .padding(12)
                if index < 2 { RowDivider() }
            }
        }
        .glass(cornerRadius: 12)
        .padding(Spacing.gutter)
        .accessibilityElement()
        .accessibilityLabel("Checking GitHub")
    }
}

/// A scroll view sized to its content up to a cap; a bare ScrollView has no height inside a menu-bar panel.
struct MeasuredScroll<Content: View>: View {
    var maxHeight: CGFloat = 480
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(max(height, 1), maxHeight))
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, height > maxHeight ? .clear : .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
            }
        )
    }
}

extension CIFilter {
    var shortLabel: String {
        switch self {
        case .all: return "CI: all"
        case .failuresOnly: return "CI: failures"
        case .none: return "CI: hidden"
        }
    }
}

/// Lays children out left to right and wraps onto new lines instead of truncating them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
