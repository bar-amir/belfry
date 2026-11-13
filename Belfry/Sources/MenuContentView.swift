import SwiftUI

let panelWidth: CGFloat = 480
private let footerClearance: CGFloat = 70

struct MenuContentView: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Namespace private var tabs
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("panelAppearance") private var panelAppearance: PanelAppearance = .system

    private var inList: Bool { store.hasToken && store.problem != .badToken }

    var body: some View {
        ZStack(alignment: .bottom) {
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
                }
            }
            if inList {
                // Content fades into the sky as it slides under the floating footer.
                LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 86)
                    .allowsHitTesting(false)
                footer.padding(.horizontal, Spacing.gutter).padding(.bottom, 12)
            }
        }
        .frame(width: panelWidth)
        .background(SpaceBackground())
        .environment(\.colorScheme, panelAppearance == .night ? .dark : systemScheme)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            store.refreshBannerPermission()
        }
        .onKeyPress(.upArrow) { withAnimation(.snappy(duration: 0.18)) { store.moveSelection(by: -1) }; return .handled }
        .onKeyPress(.downArrow) { withAnimation(.snappy(duration: 0.18)) { store.moveSelection(by: 1) }; return .handled }
        .onKeyPress(.return) { openSelection(); return .handled }
        .onKeyPress(.escape) {
            if !store.search.isEmpty { store.search = ""; return .handled }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "emEM/")) { press in
            guard !searchFocused else { return .ignored }
            switch press.characters.lowercased() {
            case "e": if let item = store.selectedItem { store.requestExit(.done, [item], animated: !reduceMotion) }
            case "m": if let item = store.selectedItem { store.requestExit(.mute, [item], animated: !reduceMotion) }
            default: searchFocused = true
            }
            return .handled
        }
        .background(shortcuts)
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.84) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            BelfryMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Inbox")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.starlight)
                    if store.hasToken && store.unreadCount > 0 { Counter(count: store.unreadCount, lit: true) }
                }
                Text(statusLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .contentTransition(.opacity)
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
        .padding(.top, 14)
        .padding(.bottom, 12)
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
                .liquidGlass(Circle(), interactive: true)
                .contentShape(Circle())
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
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .offset(y: -6)))
                if store.prSubTab == .review {
                    Label("Every open PR waiting on your review, from GitHub search, including ones with no unread notification.",
                          systemImage: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
        }
        .animation(spring, value: store.selectedTab)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.secondaryText)
                .symbolEffect(.bounce, value: searchFocused)
            TextField("", text: $store.search, prompt: Text("Filter by title, repo or #number").foregroundStyle(Theme.tertiaryText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onSubmit { listFocused = true; store.moveSelection(by: 1) }
            if store.search.isEmpty {
                Kbd("⌘F")
            } else {
                Button { withAnimation(spring) { store.search = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .liquidGlass(Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(searchFocused ? 0.7 : 0), lineWidth: 1.25))
        .animation(.easeOut(duration: 0.2), value: searchFocused)
        .animation(spring, value: store.search.isEmpty)
    }

    /// Underline tabs; the lit bar glides to the selected tab.
    private var underlineNav: some View {
        HStack(spacing: 2) {
            ForEach(ThreadTab.allCases) { tab in
                let n = store.count(for: tab)
                if tab != .other || n > 0 || store.selectedTab == .other {
                    let selected = store.selectedTab == tab
                    Button {
                        withAnimation(spring) {
                            store.selectedTab = tab
                            store.selection = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.label)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                            if n > 0 { Counter(count: n, lit: selected) }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(Theme.accent)
                                    .frame(height: 2)
                                    .glow(Theme.accent, radius: 4)
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
        .padding(.leading, Spacing.gutter - 8)
        .padding(.trailing, Spacing.gutter)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var prFilters: some View {
        HStack(spacing: 6) {
            ForEach(PRSubTab.allCases.filter {
                $0 == .all || $0 == .review || $0 == store.prSubTab || store.count(for: $0) > 0
            }) { sub in
                let n = sub == .all ? store.count(for: .pullRequests) : store.count(for: sub)
                let selected = store.prSubTab == sub
                Button {
                    withAnimation(spring) {
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
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule().fill(Theme.accent.opacity(0.14))
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.45)))
                                .matchedGeometryEffect(id: "prpill", in: tabs)
                        } else {
                            Capsule().fill(Theme.glass).overlay(Capsule().stroke(Theme.hairline))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(sub == .closed ? "Merged or closed"
                      : sub == .review ? "Every open pull request waiting on your review, from GitHub search. It can include PRs with no unread notification." : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
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
            .padding(.horizontal, 11)
            .frame(height: 28)
            .liquidGlass(Capsule(), tint: store.ciFilter == .all ? nil : Theme.accent.opacity(0.3), interactive: true)
            .contentShape(Capsule())
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
        Group {
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
                        .card()
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, 14)
                        .padding(.bottom, footerClearance)
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
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, 14)
                    .padding(.bottom, footerClearance)
                    .animation(spring, value: store.flatVisibleItems.map(\.id))
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = store.search.trimmingCharacters(in: .whitespaces)
        Group {
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
        .padding(.bottom, footerClearance - 10)
    }

    // MARK: Floating footer

    private var footer: some View {
        FooterBar(pending: store.pending, showingReviews: store.showingReviews,
                  total: store.flatVisibleItems.count,
                  doneAll: { store.requestExit(.done, store.flatVisibleItems,
                                               label: "Marked \(store.flatVisibleItems.count) done", animated: !reduceMotion) },
                  undo: { withAnimation(.bouncy(duration: 0.45, extraBounce: 0.12)) { store.undo() } })
            .animation(spring, value: store.pending)
    }

    /// Invisible buttons that carry the panel's keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { searchFocused = true }.keyboardShortcut("f")
            Button("") { store.refreshNow() }.keyboardShortcut("r")
            Button("") { withAnimation(.bouncy(duration: 0.45, extraBounce: 0.12)) { store.undo() } }.keyboardShortcut("z")
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

/// The glass bar that floats over the bottom of the list: key hints and Done with N, or the Undo toast.
struct FooterBar: View {
    let pending: PendingAction?
    let showingReviews: Bool
    let total: Int
    let doneAll: () -> Void
    let undo: () -> Void
    var toastProgress: Double = 1

    var body: some View {
        ZStack {
            if let pending {
                HStack(spacing: Spacing.item) {
                    ActionMark(kind: pending.kind == .mute ? .mute : .done, progress: toastProgress, size: 18)
                    Text(pending.message)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: undo) {
                        HStack(spacing: 6) { Text("Undo"); Kbd("⌘Z") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.asymmetric(insertion: .offset(y: 16).combined(with: .opacity),
                                        removal: .offset(y: -10).combined(with: .opacity)))
            } else {
                HStack(spacing: 10) {
                    KeyHint(keys: ["↑", "↓"], label: "move")
                    KeyHint(keys: ["↵"], label: "open")
                    if !showingReviews {
                        KeyHint(keys: ["E"], label: "done")
                        KeyHint(keys: ["M"], label: "mute")
                    }
                    Spacer()
                    if !showingReviews {
                        Button(action: doneAll) {
                            Label(total > 0 ? "Done with \(total)" : "Done", systemImage: "checkmark")
                                .contentTransition(.numericText(value: Double(total)))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(total == 0)
                        .help("Mark everything in this view done (⌘⌫). You can undo for a few seconds.")
                        .keyboardShortcut(.delete, modifiers: .command)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .liquidGlass(RoundedRectangle(cornerRadius: 18), tint: pending == nil ? nil : Theme.open.opacity(0.25))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

// MARK: - Action animations

/// The mark that plays when a row is acted on: a check that draws itself, or a bell that swings and is struck through.
struct ActionMark: View {
    let kind: ExitKind
    let progress: Double
    var size: CGFloat = 22

    var body: some View {
        let p = max(0, min(1, progress))
        let pop = 1 + 0.18 * sin(min(1, p * 1.4) * .pi)
        ZStack {
            switch kind {
            case .done:
                Circle()
                    .trim(from: 0, to: min(1, p * 1.6))
                    .stroke(Theme.open, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(Theme.open.opacity(0.16 * min(1, p * 2)))
                CheckShape()
                    .trim(from: 0, to: max(0, (p - 0.35) / 0.65))
                    .stroke(Theme.open, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.28)
            case .mute:
                Image(systemName: "bell.fill")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .rotationEffect(.degrees(sin(p * .pi * 5) * 24 * (1 - p)), anchor: .top)
                Path { path in
                    path.move(to: CGPoint(x: size * 0.18, y: size * 0.18))
                    path.addLine(to: CGPoint(x: size * 0.82, y: size * 0.82))
                }
                .trim(from: 0, to: max(0, (p - 0.45) / 0.55))
                .stroke(Theme.text, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(pop)
        .glow(kind == .done ? Theme.open : .white, radius: 4 * p)
        .accessibilityHidden(true)
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return path
    }
}

/// Done and Mute: a tinted wash sweeps across, the mark plays, then the row glides out to the right.
struct ExitEffect: ViewModifier, Animatable {
    var phase: Double
    let kind: ExitKind

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let mark = min(1, phase / 0.45)
        let leave = max(0, (phase - 0.45) / 0.55)
        let tint = kind == .done ? Theme.open : Theme.secondaryText
        content
            .background(alignment: .leading) {
                GeometryReader { geo in
                    LinearGradient(colors: [tint.opacity(0.02), tint.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * (1 - pow(1 - mark, 3)))
                }
                .opacity(phase > 0 ? 1 - leave * 0.6 : 0)
            }
            .overlay(alignment: .trailing) {
                if phase > 0 {
                    ActionMark(kind: kind, progress: mark).padding(.trailing, Spacing.cardInset + 6).opacity(1 - leave)
                }
            }
            .offset(x: 80 * leave * leave)
            .opacity(1 - leave)
    }
}

/// Opening a row: it presses in, brightens, and a small arrow flies out toward the browser.
struct OpenEffect: ViewModifier, Animatable {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let bump = phase > 0 && phase < 1 ? sin(phase * .pi) : 0
        content
            .scaleEffect(1 - 0.012 * bump)
            .background(Theme.accent.opacity(0.10 * bump))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .glow(Theme.accent, radius: 4)
                    .offset(x: -14 + phase * 26, y: 14 - phase * 20)
                    .opacity(bump)
            }
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
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Spacer()
            Button(action.0, action: action.1).buttonStyle(SecondaryButtonStyle(height: 24))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(RoundedRectangle(cornerRadius: 14), tint: color.opacity(0.22))
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Rows

/// How a row presents its state: muted GitHub state colours, a reason label, and whether the icon breathes.
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

struct StateIcon: View {
    let style: RowStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        Image(systemName: style.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(style.color)
            .symbolEffect(.pulse, options: .repeat(3), isActive: style.pulse && !reduceMotion && !snapshotMode)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, Spacing.cardInset + 32) }
}

/// One repository: a quiet card with a header and its rows.
struct RepoBox: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let repo: String
    let items: [InboxItem]
    var demo: [String: (exit: (ExitKind, Double)?, open: Double?)] = [:]
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
                Button { store.requestExit(.done, items, label: "Marked \(repo) done", animated: !reduceMotion) } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(IconButtonStyle(size: 28, tint: hovering ? Theme.text : Theme.secondaryText))
                .help("Mark everything in \(repo) done")
                .accessibilityLabel("Mark everything in \(repo) done")
            }
            .padding(.horizontal, Spacing.cardInset)
            .frame(height: 40)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ForEach(items) { item in
                ItemRow(item: item, selected: store.selection == item.id,
                        demoExit: demo[item.id]?.exit ?? nil, demoOpen: demo[item.id]?.open ?? nil)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .offset(y: -8)),
                        removal: .opacity))
                if item.id != items.last?.id { RowDivider() }
            }
        }
        .card()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: InboxItem
    let selected: Bool
    var demoExit: (ExitKind, Double)?
    var demoOpen: Double?
    @State private var hovering = false
    @State private var exitPhase: Double = 0
    @State private var openPhase: Double = 0

    private var detail: ThreadDetail? { store.detail(for: item.primary) }
    private var runs: [CIRun] { item.threads.compactMap { CIRun(title: $0.subject.title) } }
    private var exitKind: ExitKind? { demoExit?.0 ?? store.exiting[item.id] }
    private var isExiting: Bool { (demoExit?.1 ?? exitPhase) > 0 }

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

    private var actor: String? {
        guard let summary, let range = summary.range(of: #"@[A-Za-z0-9-]+(\[bot\])?"#, options: .regularExpression)
        else { return nil }
        return String(summary[range].dropFirst())
    }

    var body: some View {
        let style = RowStyle.of(item, detail: detail)
        HStack(alignment: .top, spacing: 12) {
            StateIcon(style: style)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let summary {
                    HStack(alignment: .center, spacing: 6) {
                        if let actor { Identicon(login: actor, size: 15) }
                        Text(summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(style.line == Theme.text ? Theme.text.opacity(0.84) : style.line)
                            .lineLimit(2)
                    }
                    .transition(.opacity)
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
            .padding(.trailing, 66)
        }
        .overlay(alignment: .topTrailing) { if !isExiting { trailing } }
        .padding(.horizontal, Spacing.cardInset)
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .leading) {
                if selected {
                    Theme.accent.opacity(0.09)
                    Capsule().fill(Theme.accent).frame(width: 2.5).padding(.vertical, 10).glow(Theme.accent, radius: 3)
                        .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity))
                } else if hovering {
                    Theme.hover
                }
            }
        )
        .modifier(OpenEffect(phase: demoOpen ?? openPhase))
        .modifier(ExitEffect(phase: demoExit?.1 ?? exitPhase, kind: exitKind ?? .done))
        .contentShape(Rectangle())
        .linkPointer()
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture { openRow() }
        .onAppear { store.loadDetail(for: item.primary) }
        .onChange(of: store.exiting[item.id]) { _, kind in
            guard kind != nil else { return }
            let delay = store.exitDelay[item.id] ?? 0
            withAnimation(.easeInOut(duration: 0.6).delay(delay)) { exitPhase = 1 }
        }
        .contextMenu {
            Button("Open in Browser") { openRow() }
            Button("Copy Link") { store.copyLink(item) }
            Divider()
            Button("Mark Done") { store.requestExit(.done, [item], animated: !reduceMotion) }
            Button("Mute Thread") { store.requestExit(.mute, [item], animated: !reduceMotion) }
            Divider()
            Button("Mark Everything in \(item.repo) Done") {
                store.requestExit(.done, store.flatVisibleItems.filter { $0.repo == item.repo },
                                  label: "Marked \(item.repo) done", animated: !reduceMotion)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.reason). \(title). \(summary ?? ""). \(meta)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { openRow() }
        .accessibilityAction(named: "Mark done") { store.requestExit(.done, [item], animated: !reduceMotion) }
        .accessibilityAction(named: "Mute") { store.requestExit(.mute, [item], animated: !reduceMotion) }
    }

    private func openRow() {
        store.selection = item.id
        if !reduceMotion {
            openPhase = 0
            withAnimation(.easeOut(duration: 0.5)) { openPhase = 1 }
        }
        store.open(item)
    }

    private var meta: String {
        [detail?.number.map { "#\($0)" }, item.primary.reasonLabel].compactMap { $0 }.joined(separator: ", ")
    }

    /// Time on top, then the actions. Done is always there, quietly, so rows show they can be acted on;
    /// Mute joins it on hover or selection. The column has a fixed width, so text never moves.
    private var trailing: some View {
        let active = hovering || selected
        return VStack(alignment: .trailing, spacing: 6) {
            Text(ItemRow.short(item.primary.updatedAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
            HStack(spacing: 5) {
                if active {
                    Button { store.requestExit(.mute, [item], animated: !reduceMotion) } label: {
                        Image(systemName: "bell.slash")
                    }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help("Mute this thread (M)")
                    .accessibilityLabel("Mute")
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                }
                Button { store.requestExit(.done, [item], animated: !reduceMotion) } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(IconButtonStyle(size: 28, tint: active ? Theme.open : Theme.secondaryText, quiet: !active))
                .help("Mark done (E)")
                .accessibilityLabel("Mark done")
            }
        }
        .frame(width: 61, alignment: .trailing)
    }

    private static let parser = ISO8601DateFormatter()

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
    @State private var openPhase: Double = 0

    var body: some View {
        let requester = store.requesters[pr.id]
        HStack(alignment: .top, spacing: 12) {
            StateIcon(style: RowStyle(symbol: "arrow.triangle.pull", color: Theme.open, reason: "Review requested",
                                      reasonColor: Theme.accent, pulse: true))
            VStack(alignment: .leading, spacing: 5) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.trailing, 36)
                HStack(spacing: 6) {
                    if let who = requester ?? pr.user?.login { Identicon(login: who, size: 15) }
                    Text(requestLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text.opacity(0.84))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    LabelPill(text: "Review requested", color: Theme.accent)
                    Text(verbatim: "\(pr.repoFullName) #\(pr.number)")
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
        .padding(.horizontal, Spacing.cardInset)
        .padding(.vertical, 12)
        .background(
            ZStack(alignment: .leading) {
                if selected {
                    Theme.accent.opacity(0.09)
                    Capsule().fill(Theme.accent).frame(width: 2.5).padding(.vertical, 10)
                } else if hovering {
                    Theme.hover
                }
            }
        )
        .modifier(OpenEffect(phase: openPhase))
        .contentShape(Rectangle())
        .linkPointer()
        .onHover { hovering = $0 }
        .onTapGesture {
            store.selection = pr.id
            openPhase = 0
            withAnimation(.easeOut(duration: 0.5)) { openPhase = 1 }
            store.open(pr)
        }
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

/// Inbox zero: a small moonlit planet with an orbiting moon.
struct OrbitView: View {
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.frozenTime) private var frozenTime

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || frozenTime != nil)) { context in
            let t = frozenTime ?? (reduceMotion ? 0.8 : context.date.timeIntervalSinceReferenceDate)
            Canvas { ctx, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width * 0.2
                let angle = t * 0.8
                let moon = CGPoint(x: c.x + cos(angle) * r * 1.95, y: c.y + sin(angle) * r * 0.62)
                let ring = Path(ellipseIn: CGRect(x: c.x - r * 1.95, y: c.y - r * 0.62, width: r * 3.9, height: r * 1.24))
                ctx.stroke(ring, with: .color(Theme.ring), lineWidth: 1)
                let behind = sin(angle) < 0
                let moonPath = Path(ellipseIn: CGRect(x: moon.x - 3, y: moon.y - 3, width: 6, height: 6))
                if behind { ctx.fill(moonPath, with: .color(Color(hex: "#DCE7FF").opacity(0.6))) }
                var glow = ctx
                glow.addFilter(.blur(radius: 12))
                glow.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(Color(hex: "#9CC3FF").opacity(0.45)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .linearGradient(Gradient(colors: [Color(hex: "#E8F0FF"), Color(hex: "#7F9CC9"), Color(hex: "#2B3A55")]),
                                               startPoint: CGPoint(x: c.x - r * 0.7, y: c.y - r * 0.8),
                                               endPoint: CGPoint(x: c.x + r * 0.8, y: c.y + r)))
                if !behind { ctx.fill(moonPath, with: .color(Color(hex: "#DCE7FF"))) }
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
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

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
                    LinearGradient(colors: [.clear, Theme.glassStrong, .clear], startPoint: .leading, endPoint: .trailing)
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
                        ShimmerBar(width: 240, height: 11)
                        ShimmerBar(width: 320)
                        ShimmerBar(width: 120, height: 9)
                    }
                }
                .padding(.horizontal, Spacing.cardInset)
                .padding(.vertical, 12)
                if index < 2 { RowDivider() }
            }
        }
        .card()
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 14)
        .padding(.bottom, footerClearance)
        .accessibilityElement()
        .accessibilityLabel("Checking GitHub")
    }
}

/// A scroll view sized to its content up to a cap; a bare ScrollView has no height inside a menu-bar panel.
struct MeasuredScroll<Content: View>: View {
    var maxHeight: CGFloat = 500
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollIndicators(.never)
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

/// The bell on a night tile; drawn rather than read from the app icon, which macOS caches.
struct BelfryMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.white, Color(hex: "#9CC3FF")], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(hex: "#C9DDFF").opacity(0.7), radius: 5)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26)
                    .fill(LinearGradient(colors: [Color(hex: "#1E2B47"), Color(hex: "#090D16")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).stroke(Theme.hairlineStrong))
            .accessibilityHidden(true)
    }
}

extension View {
    /// The pointing-hand cursor over things that open a page (macOS 15 and later).
    @ViewBuilder
    func linkPointer() -> some View {
        if #available(macOS 15, *) { pointerStyle(.link) } else { self }
    }
}
