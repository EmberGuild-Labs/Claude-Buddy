import AppKit
import Combine

/// Something the buddy should hold up a sign about.
struct Reminder: Equatable {
    let key: String
    let text: String
    let urgent: Bool
    let url: URL?
}

/// Decides which due-date reminders are due right now. Pure, so the self-test can check it.
///
/// - Unfinished work gets up to three nudges: a day before, 3 hours before, and 1 hour before
///   (only the latest applicable one fires, so a late start doesn't spam all three).
/// - Missing work: once a day, one "you have N missing" reminder; after that, each newly missing
///   assignment gets its own. A pile of old missing work never floods you.
enum ReminderPlanner {
    static let maxPerCheck = 3

    static func due(now: Date, snapshot: SchoolSnapshot, fired: Set<String>) -> [Reminder] {
        var out: [Reminder] = []

        let missing = snapshot.missing
        let dayKey = "missing-day-" + dayStamp(now)
        if !missing.isEmpty && !fired.contains(dayKey) {
            let text = missing.count == 1
                ? "Missing: \(missing[0].title)"
                : "You have \(missing.count) missing assignments"
            out.append(Reminder(key: dayKey, text: text, urgent: true, url: missing.count == 1 ? missing[0].url : nil))
            // Covers everything currently missing, so they don't each fire too.
            for m in missing { out.append(Reminder(key: "missing-\(m.id)", text: "", urgent: true, url: nil)) }
        } else {
            for m in missing where !fired.contains("missing-\(m.id)") {
                out.append(Reminder(key: "missing-\(m.id)", text: "Missing: \(m.title)", urgent: true, url: m.url))
            }
        }

        for item in snapshot.upcoming where !item.isDone && !item.isEvent {
            guard let due = item.due, due > now else { continue }
            let left = due.timeIntervalSince(now)
            let stage: String
            if left <= 3600 { stage = "1h" } else if left <= 3 * 3600 { stage = "3h" } else if left <= 24 * 3600 { stage = "24h" } else { continue }
            let key = "due-\(item.id)-\(stage)"
            guard !fired.contains(key) else { continue }
            out.append(Reminder(key: key, text: text(for: item, due: due, now: now), urgent: stage == "1h", url: item.url))
        }

        // Silent "covered" entries only mark things as handled; count only visible ones.
        var visible = 0
        return out.filter { r in
            if r.text.isEmpty { return true }
            visible += 1
            return visible <= maxPerCheck
        }
    }

    /// "AP Chemistry: Lab Report — due in 45 min"
    static func text(for item: SchoolItem, due: Date, now: Date) -> String {
        let label = item.course.isEmpty ? item.title : "\(shortCourse(item.course)): \(item.title)"
        return "\(label) — due \(relative(due, now: now))"
    }

    /// The soonest unfinished real assignment, for "Show Next Assignment".
    static func next(in snapshot: SchoolSnapshot, now: Date) -> Reminder? {
        guard let item = snapshot.upcoming.first(where: { !$0.isDone && !$0.isEvent && ($0.due ?? .distantPast) > now }),
              let due = item.due else { return nil }
        return Reminder(key: "next-\(item.id)-\(now.timeIntervalSince1970)", text: text(for: item, due: due, now: now),
                        urgent: due.timeIntervalSince(now) <= 3600, url: item.url)
    }

    static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    /// "AP Chemistry - Period 3 (Smith)" → "AP Chemistry"
    static func shortCourse(_ name: String) -> String {
        var s = name
        for sep in [" - ", " (", " | ", ": "] {
            if let r = s.range(of: sep), s.distance(from: s.startIndex, to: r.lowerBound) >= 4 { s = String(s[..<r.lowerBound]) }
        }
        return s.count > 24 ? String(s.prefix(23)) + "…" : s
    }

    /// "in 45 min", "at 11:59 PM", "tomorrow at 8:00 AM", "Fri at 3:00 PM"
    static func relative(_ due: Date, now: Date) -> String {
        let left = due.timeIntervalSince(now)
        if left < 3600 { return "in \(max(1, Int(left / 60))) min" }
        let cal = Calendar.current
        let time = due.formatted(date: .omitted, time: .shortened)
        if cal.isDate(due, inSameDayAs: now) { return "at \(time)" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(due, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "\(due.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }
}

/// Keeps the Canvas snapshot fresh and hands due reminders to the buddy.
final class SchoolStore: ObservableObject {
    static let tokenAccount = "canvas-token"

    @Published private(set) var snapshot: SchoolSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var canvasHost: URL?

    /// Called with reminders to show (the app routes them to the main buddy).
    var onReminder: ((Reminder) -> Void)?
    var remindersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "schoolReminders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "schoolReminders"); objectWillChange.send() }
    }

    private var refreshTimer: Timer?
    private var reminderTimer: Timer?

    init() {
        canvasHost = UserDefaults.standard.string(forKey: "canvasHost").flatMap(URL.init(string:))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkReminders() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    var isConnected: Bool { canvasHost != nil && Keychain.load(account: Self.tokenAccount) != nil }

    private var client: CanvasClient? {
        guard let host = canvasHost, let token = Keychain.load(account: Self.tokenAccount) else { return nil }
        return CanvasClient(base: host, token: token)
    }

    /// Tests the address and token, and saves them only if Canvas accepts them.
    @MainActor
    func connect(address: String, token: String) async -> Result<String, Error> {
        guard let host = CanvasClient.normalize(address) else { return .failure(CanvasClient.Failure.badAddress) }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let name = try await CanvasClient(base: host, token: trimmed).userName()
            guard Keychain.save(trimmed, account: Self.tokenAccount) else {
                return .failure(NSError(domain: "ClaudeBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the token to the Keychain."]))
            }
            UserDefaults.standard.set(host.absoluteString, forKey: "canvasHost")
            canvasHost = host
            refresh()
            return .success(name)
        } catch {
            return .failure(error)
        }
    }

    func disconnect() {
        Keychain.delete(account: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: "canvasHost")
        UserDefaults.standard.removeObject(forKey: "firedReminders")
        canvasHost = nil
        snapshot = nil
        lastError = nil
    }

    func refresh() {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            do {
                snapshot = try await client.snapshot()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            isRefreshing = false
            checkReminders()
        }
    }

    /// Refreshes if the data is more than a couple of minutes old (e.g. when opening Today).
    func refreshIfStale() {
        if snapshot.map({ Date().timeIntervalSince($0.fetchedAt) > 120 }) ?? true { refresh() }
    }

    // MARK: - Reminders

    private var fired: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "firedReminders") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(600)), forKey: "firedReminders") }
    }

    func checkReminders() {
        guard remindersEnabled, let snapshot else { return }
        let reminders = ReminderPlanner.due(now: Date(), snapshot: snapshot, fired: fired)
        guard !reminders.isEmpty else { return }
        fired = fired.union(reminders.map(\.key))
        for r in reminders where !r.text.isEmpty { onReminder?(r) }
    }

    // MARK: - Summary for the menu

    var summary: String? {
        guard isConnected else { return nil }
        if let lastError, snapshot == nil { return "Canvas: \(lastError)" }
        guard let snapshot else { return "Canvas: loading…" }
        let cal = Calendar.current
        let today = snapshot.upcoming.filter { !$0.isDone && !$0.isEvent && $0.due.map { cal.isDateInToday($0) && $0 > Date() } == true }.count
        var parts = ["\(today) due today"]
        if !snapshot.missing.isEmpty { parts.append("\(snapshot.missing.count) missing") }
        return "Canvas: " + parts.joined(separator: " · ")
    }
}

