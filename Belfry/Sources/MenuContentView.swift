import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var store: NotificationStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
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
        } else if store.threads.isEmpty {
            Text(store.lastChecked == nil ? "Checking GitHub…" : "You're all caught up.")
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

    private var listHeight: CGFloat {
        let estimate = CGFloat(store.threads.count) * 52 + CGFloat(store.groupedByRepo.count) * 24
        return min(max(estimate, 80), 460)
    }

    private var footer: some View {
        HStack {
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
                Text(thread.subject.title).lineLimit(2)
                Text("\(thread.reasonLabel) · \(Self.relative(thread.updatedAt))")
                    .font(.caption).foregroundStyle(.secondary)
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
        .help("Open in browser")
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
