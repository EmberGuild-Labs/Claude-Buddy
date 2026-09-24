import AppKit
import SQLite3

/// Notices new incoming text messages (iMessage/SMS) so the buddy can say so. Opt-in.
///
/// macOS has no permission-free way to ask Messages for unread texts, so this reads the
/// Messages database (`~/Library/Messages/chat.db`), which needs **Full Disk Access** for Claude
/// Buddy (granted by you in System Settings). It opens the database read-only and only counts
/// incoming messages newer than the last one it saw. It never reads who sent them or what they
/// say, and never writes anything.
final class MessagesWatcher {
    enum Access: Equatable { case ok, needsFullDiskAccess, unavailable }

    let databaseURL: URL
    /// Called on the main thread with how many new texts arrived.
    var onNewTexts: ((Int) -> Void)?
    private(set) var access: Access = .unavailable
    private var lastSeen: Int64?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "claude-buddy.messages", qos: .utility)

    static let defaultDatabase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
    static let fullDiskAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    init(database: URL = MessagesWatcher.defaultDatabase) {
        databaseURL = database
    }

    var isRunning: Bool { timer != nil }

    func start(every seconds: TimeInterval = 10) {
        guard timer == nil else { return }
        queue.async { self.lastSeen = nil }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        queue.async { self.lastSeen = nil }
    }

    /// Checks once, off the main thread.
    func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.check()
            DispatchQueue.main.async {
                self.access = result.access
                if result.newCount > 0 { self.onNewTexts?(result.newCount) }
            }
        }
    }

    /// Reads the newest incoming message id; the first successful read just sets the baseline.
    func check() -> (access: Access, newCount: Int) {
        guard let latest = Self.newestIncoming(in: databaseURL) else {
            // Without Full Disk Access the file can't even be opened, though it exists.
            return (FileManager.default.fileExists(atPath: databaseURL.path) ? .needsFullDiskAccess : .unavailable, 0)
        }
        defer { lastSeen = max(lastSeen ?? latest, latest) }
        guard let seen = lastSeen, latest > seen else { return (.ok, 0) }
        return (.ok, Self.countIncoming(in: databaseURL, after: seen) ?? 1)
    }

    // MARK: - SQLite (read-only)

    private static func open(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        // mode=ro: never write. Messages keeps the database in WAL mode, which read-only
        // connections can still read while Messages is running.
        let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 500)
        return db
    }

    private static func queryInt(_ url: URL, _ sql: String, _ bind: Int64? = nil) -> Int64?? {
        guard let db = open(url) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        if let bind { sqlite3_bind_int64(stmt, 1, bind) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return .some(sqlite3_column_type(stmt, 0) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 0))
    }

    /// The newest incoming message's id (0 if there are none), or nil if the database can't be read.
    static func newestIncoming(in url: URL) -> Int64? {
        guard let result = queryInt(url, "SELECT MAX(ROWID) FROM message WHERE is_from_me = 0") else { return nil }
        return result ?? 0
    }

    static func countIncoming(in url: URL, after rowid: Int64) -> Int? {
        guard let result = queryInt(url, "SELECT COUNT(*) FROM message WHERE is_from_me = 0 AND ROWID > ?", rowid), let n = result else { return nil }
        return Int(n)
    }
}
