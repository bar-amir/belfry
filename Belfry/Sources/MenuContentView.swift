import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.bannersAllowed == false && store.hasToken { permissionStrip }
            if !store.hasToken {
                Divider().overlay(Theme.border)
                TokenEntryView(kind: .welcome)
            } else if store.problem == .badToken {
                Divider().overlay(Theme.border)
                TokenEntryView(kind: .repair)
            } else {
                controls
                Divider().overlay(Theme.border)
                if let problem = store.problem { problemStrip(problem) }
                content
                Divider().overlay(Theme.border)
                footer
            }
        }
        .frame(width: 440)
        .background(Theme.surface)
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
            case "e": if let item = store.selectedItem { store.markDone([item]) }
            case "m": if let item = store.selectedItem { store.mute([item]) }
            default: searchFocused = true
            }
            return .handled
        }
        .background(shortcuts)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.item) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Inbox")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(statusLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if store.hasToken {
                Button { store.refreshNow() } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(IconButtonStyle())
                .help("Check GitHub now (⌘R)")
                .accessibilityLabel("Check GitHub now")
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.controlText)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    private var permissionStrip: some View {
        HStack(spacing: Spacing.item) {
            Image(systemName: "bell.slash.fill").foregroundStyle(Theme.warnText)
            Text("Banners are off for Belfry in macOS.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.warnText)
            Spacer()
            Button("Turn on…") { store.openNotificationSettings() }
                .buttonStyle(SecondaryButtonStyle(height: 24))
                .help("Opens System Settings › Notifications › Belfry")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, 8)
        .background(Theme.warnFill)
    }

    private func problemStrip(_ problem: FetchProblem) -> some View {
        HStack(spacing: Spacing.item) {
            Image(systemName: problem == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warnText)
            Text(problemText(problem))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.warnText)
                .lineLimit(2)
            Spacer()
            Button("Try again") { store.refreshNow() }
                .buttonStyle(SecondaryButtonStyle(height: 24))
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, 8)
        .background(Theme.warnFill)
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

    // MARK: Search, tabs, filter

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            searchField
            HStack(spacing: 6) {
                ForEach(ThreadTab.allCases) { tab in
                    let n = store.count(for: tab)
                    if tab != .other || n > 0 || store.selectedTab == .other {
                        tabChip(tab.label, count: n, selected: store.selectedTab == tab) {
                            store.selectedTab = tab
                            store.selection = nil
                        }
                    }
                }
                Spacer(minLength: 0)
                ciFilterMenu
            }
            if store.selectedTab == .pullRequests { prSubTabs }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.bottom, Spacing.bar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            TextField("Filter by title, repo or #number", text: $store.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { listFocused = true; store.moveSelection(by: 1) }
            if store.search.isEmpty {
                Kbd("⌘F")
            } else {
                Button { store.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.strip))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocused ? Theme.accent : Theme.border,
                                                          lineWidth: searchFocused ? 1.5 : 1))
    }

    private func tabChip(_ label: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                if count > 0 { CountBadge(count: count, selected: selected) }
            }
        }
        .buttonStyle(ChipButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var prSubTabs: some View {
        FlowLayout(spacing: 6) {
            ForEach(PRSubTab.allCases.filter {
                $0 == .all || $0 == .review || $0 == store.prSubTab || store.count(for: $0) > 0
            }) { sub in
                let n = sub == .all ? store.count(for: .pullRequests) : store.count(for: sub)
                Button {
                    store.prSubTab = sub
                    store.selection = nil
                } label: {
                    HStack(spacing: 4) {
                        Text(sub.label)
                        if n > 0 {
                            Text("\(n)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .buttonStyle(ChipButtonStyle(selected: store.prSubTab == sub, height: 24))
                .fixedSize()
                .accessibilityAddTraits(store.prSubTab == sub ? .isSelected : [])
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
            .font(.system(size: 12, weight: store.ciFilter == .all ? .regular : .semibold))
            .foregroundStyle(store.ciFilter == .all ? Theme.controlText : Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(store.ciFilter == .all ? Theme.surface : Theme.accentSoft))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(store.ciFilter == .all ? Theme.controlBorder : Theme.accent))
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
            loadingRows
        } else if store.showingReviews {
            if store.visibleReviews.isEmpty {
                EmptyStateView(symbol: "eye", title: "Nothing waiting on your review",
                               message: "Pull requests where someone asks for your review show up here.")
            } else {
                MeasuredScroll {
                    VStack(spacing: 2) {
                        ForEach(store.visibleReviews) { pr in
                            ReviewRow(pr: pr, selected: store.selection == pr.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        } else if store.groupedByRepo.isEmpty {
            emptyState
        } else {
            MeasuredScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.groupedByRepo, id: \.repo) { group in
                        RepoHeader(repo: group.repo, count: group.items.count)
                        ForEach(group.items) { item in
                            ItemRow(item: item, selected: store.selection == item.id)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = store.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            EmptyStateView(symbol: "magnifyingglass", title: "No notifications match “\(query)”",
                           message: "Try fewer words, a repo name or a #number.",
                           action: ("Clear filter", { store.search = "" }))
        } else if store.selectedTab != .all && !store.threads.isEmpty {
            EmptyStateView(symbol: "tray", title: "Nothing in \(store.selectedTab.label)",
                           message: "Other tabs still have notifications.",
                           action: ("Show all", { store.selectedTab = .all }))
        } else if store.hiddenByFilter > 0 {
            EmptyStateView(symbol: "checkmark.circle", title: "You're all caught up",
                           message: "\(store.hiddenByFilter) CI runs are hidden by your filter.",
                           action: ("Show all CI runs", { store.ciFilter = .all }))
        } else {
            EmptyStateView(symbol: "checkmark.circle", title: "You're all caught up",
                           message: "New activity shows up here and as a banner.")
        }
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 7).fill(Theme.strip).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.strip).frame(width: 240, height: 11)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.strip).frame(width: 300, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.strip).frame(width: 140, height: 9)
                    }
                }
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Checking GitHub")
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if let pending = store.pending {
            HStack(spacing: Spacing.item) {
                Image(systemName: pending.kind == .mute ? "bell.slash.fill" : "checkmark.circle.fill")
                    .foregroundStyle(Theme.goodText)
                Text(pending.message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button { store.undo() } label: {
                    HStack(spacing: 6) { Text("Undo"); Kbd("⌘Z") }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, Spacing.gutter)
            .frame(height: 52)
            .background(Theme.goodFill.opacity(0.6))
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
                    Button { store.doneAllVisible() } label: {
                        Text(total > 0 ? "Done with \(total)" : "Done")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(total == 0)
                    .help("Mark everything in this view done (⌘⌫). You can undo for a few seconds.")
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .frame(height: 52)
        }
    }

    /// Invisible buttons that carry the panel's keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { searchFocused = true }.keyboardShortcut("f")
            Button("") { store.refreshNow() }.keyboardShortcut("r")
            Button("") { store.undo() }.keyboardShortcut("z")
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

// MARK: - Rows

/// What a row looks like for its state: icon, chip colours, and the colour of its "what happened" line.
struct RowStyle {
    let symbol: String
    let fill: Color
    let tint: Color
    var line: Color = Theme.text
    let label: String

    static func of(_ item: InboxItem, detail: ThreadDetail?) -> RowStyle {
        let t = item.primary
        if t.isCI {
            if t.isCIFailure {
                return RowStyle(symbol: "xmark", fill: Theme.badFill, tint: Theme.badText, line: Theme.badText, label: "CI failed")
            }
            if CIRun(title: t.subject.title)?.outcome == "succeeded" {
                return RowStyle(symbol: "checkmark", fill: Theme.goodFill, tint: Theme.goodText, line: Theme.goodText, label: "CI passed")
            }
            return RowStyle(symbol: "gearshape", fill: Theme.strip, tint: Theme.controlText, label: "CI run")
        }
        let tags = detail?.tags ?? []
        if t.reason == "review_requested" {
            return RowStyle(symbol: "eye.fill", fill: Theme.accent, tint: Theme.onAccent, label: "Review requested")
        }
        if tags.contains(.closed) {
            if detail?.summary?.hasPrefix("Merged") == true {
                return RowStyle(symbol: "arrow.triangle.merge", fill: Theme.mergedFill, tint: Theme.mergedText, label: "Merged")
            }
            return RowStyle(symbol: "xmark.circle", fill: Theme.strip, tint: Theme.secondaryText, label: "Closed")
        }
        if tags.contains(.changesRequested) {
            return RowStyle(symbol: "exclamationmark", fill: Theme.warnFill, tint: Theme.warnText, label: "Changes requested")
        }
        if tags.contains(.approved) {
            return RowStyle(symbol: "checkmark", fill: Theme.goodFill, tint: Theme.goodText, label: "Approved")
        }
        if t.reason == "mention" || t.reason == "team_mention" {
            return RowStyle(symbol: "at", fill: Theme.warnFill, tint: Theme.warnText, label: "Mentioned")
        }
        if tags.contains(.comment) {
            return RowStyle(symbol: "text.bubble", fill: Theme.strip, tint: Theme.controlText, label: "Comment")
        }
        switch t.subject.type {
        case "Issue": return RowStyle(symbol: "circle.dotted", fill: Theme.strip, tint: Theme.controlText, label: "Issue")
        case "Release": return RowStyle(symbol: "tag", fill: Theme.strip, tint: Theme.controlText, label: "Release")
        case "Discussion": return RowStyle(symbol: "bubble.left.and.bubble.right", fill: Theme.strip, tint: Theme.controlText, label: "Discussion")
        default: return RowStyle(symbol: "arrow.triangle.pull", fill: Theme.strip, tint: Theme.controlText, label: "Pull request")
        }
    }
}

struct StatusChip: View {
    let style: RowStyle
    var body: some View {
        Image(systemName: style.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(style.tint)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(style.fill))
            .accessibilityHidden(true)
    }
}

struct RepoHeader: View {
    @EnvironmentObject private var store: NotificationStore
    let repo: String
    let count: Int
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            SectionLabel(repo)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Mark \(count) done") { store.doneAll(inRepo: repo) }
                .buttonStyle(SecondaryButtonStyle(height: 22))
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel("Mark everything in \(repo) done")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var store: NotificationStore
    let item: InboxItem
    let selected: Bool
    @State private var hovering = false

    private var detail: ThreadDetail? { store.detail(for: item.primary) }

    private var runs: [CIRun] { item.threads.compactMap { CIRun(title: $0.subject.title) } }

    /// A collapsed CI row is named after its branch; a single row after its subject.
    private var title: String {
        if item.count > 1, let branch = runs.first?.branch { return branch }
        return item.primary.displayTitle
    }

    private var summary: String? {
        guard item.count > 1, !runs.isEmpty else { return detail?.summary }
        let workflows = runs.map(\.workflow).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let failed = item.threads.filter(\.isCIFailure).count
        let names = workflows.prefix(3).joined(separator: ", ") + (workflows.count > 3 ? "…" : "")
        return failed > 0 ? "✗ \(failed) of \(item.count) runs failed · \(names)" : "✓ \(item.count) runs passed · \(names)"
    }

    var body: some View {
        let style = RowStyle.of(item, detail: detail)
        HStack(alignment: .top, spacing: 10) {
            StatusChip(style: style)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.trailing, 60)
                if let summary {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(style.line)
                        .lineLimit(2)
                } else {
                    // Holds the line's height while the detail loads, so rows don't jump.
                    RoundedRectangle(cornerRadius: 3).fill(Theme.strip)
                        .frame(width: 200, height: 10)
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 6) {
                    Text(meta)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    if item.count > 1 {
                        Text("\(item.count) runs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Capsule().fill(Theme.kbdFill))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) { trailing }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Theme.accentSoft : (hovering ? Theme.hover : .clear)))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.selection = item.id; store.open(item) }
        .onAppear { store.loadDetail(for: item.primary) }
        .contextMenu {
            Button("Open in Browser") { store.open(item) }
            Button("Copy Link") { store.copyLink(item) }
            Divider()
            Button("Mark Done") { store.markDone([item]) }
            Button("Mute Thread") { store.mute([item]) }
            Divider()
            Button("Mark Everything in \(item.repo) Done") { store.doneAll(inRepo: item.repo) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.label). \(title). \(summary ?? ""). \(meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.open(item) }
        .accessibilityAction(named: "Mark done") { store.markDone([item]) }
        .accessibilityAction(named: "Mute") { store.mute([item]) }
    }

    @ViewBuilder
    private var trailing: some View {
        if hovering || selected {
            HStack(spacing: 4) {
                Button { store.markDone([item]) } label: { Image(systemName: "checkmark") }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help("Mark done (E)")
                    .accessibilityLabel("Mark done")
                Button { store.mute([item]) } label: { Image(systemName: "bell.slash") }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help("Mute this thread (M)")
                    .accessibilityLabel("Mute")
            }
        } else {
            Text(ItemRow.short(item.primary.updatedAt))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 1)
        }
    }

    private var meta: String {
        let number = detail?.number.map { "#\($0) · " } ?? ""
        return "\(number)\(item.primary.reasonLabel)"
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
        HStack(alignment: .top, spacing: 10) {
            StatusChip(style: RowStyle(symbol: "eye.fill", fill: Theme.accent, tint: Theme.onAccent, label: "Review requested"))
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.trailing, 40)
                Text(requestLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(pr.repoFullName) #\(pr.number)\(pr.draft == true ? " · draft" : "")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            Text(ItemRow.short(pr.updatedAt))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Theme.accentSoft : (hovering ? Theme.hover : .clear)))
        .padding(.horizontal, 8)
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

// MARK: - Shared pieces

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.controlText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.strip))
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
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
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// A scroll view sized to its content up to a cap; a bare ScrollView has no height inside a menu-bar panel.
struct MeasuredScroll<Content: View>: View {
    var maxHeight: CGFloat = 470
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(height: min(max(height, 1), maxHeight))
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
