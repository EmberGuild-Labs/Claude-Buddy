import AppKit
import SwiftUI

// MARK: - Windows

/// Opens (or re-focuses) the Today and Canvas Settings windows.
final class SchoolWindows {
    private let store: SchoolStore
    private var today: NSWindow?
    private var settings: NSWindow?

    init(store: SchoolStore) { self.store = store }

    func showToday() {
        store.refreshIfStale()
        today = show(today, title: "Today", size: NSSize(width: 420, height: 580), resizable: true) {
            TodayView(store: store, hover: HoverState(), connect: { [weak self] in self?.showSettings() })
        }
    }

    func showSettings() {
        settings = show(settings, title: "Canvas", size: NSSize(width: 460, height: 420), resizable: false) {
            CanvasSettingsView(store: store, form: CanvasForm())
        }
    }

    private func show<V: View>(_ existing: NSWindow?, title: String, size: NSSize, resizable: Bool,
                               @ViewBuilder content: () -> V) -> NSWindow {
        NSApp.activate(ignoringOtherApps: true)
        if let existing {
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

// MARK: - Canvas settings

/// Form state for the settings window. (A plain ObservableObject rather than @State, which
/// needs a SwiftUI macro plugin that only ships with the full Xcode app.)
final class CanvasForm: ObservableObject {
    @Published var address = ""
    @Published var token = ""
    @Published var working = false
    @Published var message: String?
    @Published var failed = false
}

/// Which Today row the pointer is over.
final class HoverState: ObservableObject {
    @Published var id: String?
}

struct CanvasSettingsView: View {
    @ObservedObject var store: SchoolStore
    @ObservedObject var form: CanvasForm

    var body: some View {
        Form {
            if store.isConnected {
                Section {
                    LabeledContent("Connected to", value: store.canvasHost?.host ?? "")
                    if let name = store.snapshot?.userName { LabeledContent("Signed in as", value: name) }
                    Button("Disconnect", role: .destructive) { store.disconnect() }
                }
            } else {
                Section {
                    TextField("Canvas address", text: $form.address, prompt: Text("yourschool.instructure.com"))
                        .textContentType(.URL)
                    SecureField("Access token", text: $form.token, prompt: Text("Paste your token"))
                } header: {
                    Text("Connect your school's Canvas")
                } footer: {
                    Text("To get a token, open Canvas in your browser, go to **Account → Settings**, and click **+ New Access Token**. Name it “Claude Buddy”, generate it, and copy the token shown. It's stored in your Mac's Keychain and only ever sent to your school's Canvas.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    HStack {
                        Button("Connect") { connect() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(form.working || form.address.isEmpty || form.token.isEmpty)
                        if form.working { ProgressView().controlSize(.small) }
                        if let message = form.message {
                            Text(message)
                                .foregroundStyle(form.failed ? .red : .green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Section {
                Toggle("Buddy reminds me before things are due", isOn: Binding(
                    get: { store.remindersEnabled }, set: { store.remindersEnabled = $0 }))
            } footer: {
                Text("A day, 3 hours, and 1 hour before each due date, plus a daily heads-up about missing work.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private func connect() {
        form.working = true
        form.message = nil
        Task { @MainActor in
            let result = await store.connect(address: form.address, token: form.token)
            form.working = false
            switch result {
            case .success(let name):
                form.failed = false
                form.message = "Connected — hi, \(name)!"
            case .failure(let error):
                form.failed = true
                form.message = error.localizedDescription
            }
            form.token = ""  // Don't keep the token around in memory longer than needed.
        }
    }
}

// MARK: - Today

struct TodayView: View {
    @ObservedObject var store: SchoolStore
    @ObservedObject var hover: HoverState
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !store.isConnected {
                ContentUnavailableView {
                    Label("Connect Canvas", systemImage: "graduationcap")
                } description: {
                    Text("See what's due and get reminders from your buddy.")
                } actions: {
                    Button("Connect Canvas…", action: connect).buttonStyle(.borderedProminent)
                }
            } else if let snapshot = store.snapshot {
                content(snapshot)
            } else if let error = store.lastError {
                ContentUnavailableView("Couldn't reach Canvas", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView("Loading Canvas…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 360, minHeight: 400)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.bold())
                if let snapshot = store.snapshot {
                    Text("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isConnected {
                Button { store.refresh() } label: {
                    if store.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.borderless)
                .help("Refresh from Canvas")
                .disabled(store.isRefreshing)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func content(_ snapshot: SchoolSnapshot) -> some View {
        let groups = Self.group(snapshot.upcoming, now: Date())
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if !snapshot.missing.isEmpty {
                    section("Missing", tint: .red, items: Array(snapshot.missing.prefix(8)))
                }
                ForEach(groups, id: \.title) { g in section(g.title, tint: .primary, items: g.items) }
                if groups.isEmpty && snapshot.missing.isEmpty {
                    Label("Nothing due in the next two weeks", systemImage: "party.popper")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                if snapshot.grades.contains(where: { $0.score != nil || $0.grade != nil }) {
                    grades(snapshot.grades)
                }
            }
            .padding(16)
        }
    }

    private struct Group { let title: String; let items: [SchoolItem] }

    /// Today / Tomorrow / This week / Later, skipping anything already past.
    private static func group(_ items: [SchoolItem], now: Date) -> [Group] {
        let cal = Calendar.current
        var today: [SchoolItem] = [], tomorrow: [SchoolItem] = [], week: [SchoolItem] = [], later: [SchoolItem] = []
        for item in items {
            guard let due = item.due else { later.append(item); continue }
            if due < now && !cal.isDateInToday(due) { continue }
            if cal.isDateInToday(due) { today.append(item) }
            else if cal.isDateInTomorrow(due) { tomorrow.append(item) }
            else if due < now.addingTimeInterval(7 * 86_400) { week.append(item) }
            else { later.append(item) }
        }
        return [Group(title: "Today", items: today), Group(title: "Tomorrow", items: tomorrow),
                Group(title: "This Week", items: week), Group(title: "Later", items: later)]
            .filter { !$0.items.isEmpty }
    }

    private func section(_ title: String, tint: Color, items: [SchoolItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint == .primary ? .secondary : tint)
            VStack(spacing: 2) {
                ForEach(items) { ItemRow(item: $0, hover: hover) }
            }
        }
    }

    private func grades(_ grades: [CourseGrade]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GRADES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(grades) { g in
                HStack {
                    Text(ReminderPlanner.shortCourse(g.name)).lineLimit(1)
                    Spacer()
                    let text = [g.grade, g.score.map { String(format: "%.1f%%", $0) }].compactMap { $0 }.joined(separator: " · ")
                    Text(text.isEmpty ? "—" : text)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ItemRow: View {
    let item: SchoolItem
    @ObservedObject var hover: HoverState
    private var hovering: Bool { hover.id == item.id }

    var body: some View {
        Button {
            if let url = item.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .lineLimit(2)
                    if !item.course.isEmpty {
                        Text(item.course).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let due = item.due {
                        Text(dueText(due)).font(.callout).monospacedDigit()
                            .foregroundStyle(item.missing ? .red : .secondary)
                    }
                    if let status { Text(status).font(.caption2.weight(.semibold)).foregroundStyle(color) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hover.id = item.id } else if hover.id == item.id { hover.id = nil }
        }
        .help(item.url == nil ? "" : "Open in Canvas")
    }

    private var icon: String {
        if item.isDone { return "checkmark.circle.fill" }
        if item.missing { return "exclamationmark.circle.fill" }
        switch item.kind {
        case "quiz": return "questionmark.circle"
        case "discussion_topic": return "bubble.left.and.bubble.right"
        case "calendar_event": return "calendar"
        default: return "circle"
        }
    }

    private var color: Color {
        if item.isDone { return .green }
        if item.missing { return .red }
        if item.late { return .orange }
        return .secondary
    }

    private var status: String? {
        if item.missing { return "Missing" }
        if item.markedDone && !item.submitted { return "Done" }
        if item.submitted { return item.late ? "Submitted late" : "Submitted" }
        return nil
    }

    private func dueText(_ due: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(due) || cal.isDateInTomorrow(due) { return due.formatted(date: .omitted, time: .shortened) }
        return due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
