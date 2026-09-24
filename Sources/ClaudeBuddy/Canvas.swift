import Foundation

/// Something on your Canvas plate: an assignment, quiz, discussion, or calendar event.
struct SchoolItem: Identifiable, Hashable {
    let id: String
    let title: String
    let course: String
    let due: Date?
    let url: URL?
    /// Canvas's plannable type: assignment, quiz, discussion_topic, calendar_event, planner_note…
    let kind: String
    var submitted = false
    var missing = false
    var late = false
    /// Checked off in the Canvas planner.
    var markedDone = false

    var isDone: Bool { submitted || markedDone }
    var isEvent: Bool { kind == "calendar_event" || kind == "planner_note" }
}

struct CourseGrade: Identifiable, Hashable {
    let id: Int
    let name: String
    let score: Double?
    let grade: String?
}

/// Everything fetched from Canvas in one refresh.
struct SchoolSnapshot {
    var userName: String?
    /// Upcoming work and events (from the planner), soonest first.
    var upcoming: [SchoolItem] = []
    /// Past-due work that wasn't turned in, most recent first.
    var missing: [SchoolItem] = []
    var grades: [CourseGrade] = []
    var fetchedAt = Date()
}

/// A tiny client for the Canvas REST API, authenticated with a personal access token.
/// Docs: https://canvas.instructure.com/doc/api/
struct CanvasClient {
    enum Failure: LocalizedError {
        case badAddress, unauthorized, forbidden, http(Int), unreadable

        var errorDescription: String? {
            switch self {
            case .badAddress: "That doesn't look like a Canvas address. Try something like yourschool.instructure.com."
            case .unauthorized: "Canvas didn't accept that access token. Check it was copied completely, or make a new one."
            case .forbidden: "Canvas refused the request. Your school may limit what access tokens can do."
            case .http(let code): "Canvas answered with an error (\(code))."
            case .unreadable: "Canvas sent something unexpected back."
            }
        }
    }

    let base: URL
    let token: String

    /// Accepts "school.instructure.com", "https://canvas.school.edu/", or a pasted page URL,
    /// and keeps just https://host.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text), let host = parts.host, host.contains(".") else { return nil }
        parts.scheme = "https"  // Never send the token over plain http.
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        parts.host = host.lowercased()
        return parts.url
    }

    // MARK: - Requests

    private func request(_ url: URL) async throws -> (Any, HTTPURLResponse) {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Failure.unreadable }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        default: throw Failure.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw Failure.unreadable }
        return (json, http)
    }

    private func url(_ path: String, _ query: [URLQueryItem]) throws -> URL {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw Failure.badAddress }
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw Failure.badAddress }
        return url
    }

    /// GETs a list, following Canvas's `Link: <…>; rel="next"` pagination (a few pages at most).
    private func list(_ path: String, _ query: [URLQueryItem], maxPages: Int = 5) async throws -> [[String: Any]] {
        var next: URL? = try url(path, query + [URLQueryItem(name: "per_page", value: "100")])
        var all: [[String: Any]] = []
        var pages = 0
        while let page = next, pages < maxPages {
            let (json, http) = try await request(page)
            guard let items = json as? [[String: Any]] else { throw Failure.unreadable }
            all += items
            pages += 1
            next = Self.nextLink(http.value(forHTTPHeaderField: "Link"))
            // Only follow pagination on the same (https) Canvas host.
            if let n = next, n.host != base.host || n.scheme != "https" { next = nil }
        }
        return all
    }

    static func nextLink(_ header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.components(separatedBy: ",") where part.contains("rel=\"next\"") {
            if let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end {
                return URL(string: String(part[part.index(after: start)..<end]))
            }
        }
        return nil
    }

    /// Checks the token and returns the student's name.
    func userName() async throws -> String {
        let (json, _) = try await request(try url("/api/v1/users/self", []))
        guard let d = json as? [String: Any] else { throw Failure.unreadable }
        return (d["short_name"] as? String) ?? (d["name"] as? String) ?? "you"
    }

    func snapshot(now: Date = Date()) async throws -> SchoolSnapshot {
        let iso = ISO8601DateFormatter()
        let start = Calendar.current.startOfDay(for: now)
        async let name = userName()
        async let courses = list("/api/v1/courses", [
            URLQueryItem(name: "enrollment_state", value: "active"),
            URLQueryItem(name: "include[]", value: "total_scores"),
        ])
        async let planner = list("/api/v1/planner/items", [
            URLQueryItem(name: "start_date", value: iso.string(from: start)),
            URLQueryItem(name: "end_date", value: iso.string(from: start.addingTimeInterval(15 * 86_400))),
        ])
        async let missing = list("/api/v1/users/self/missing_submissions", [
            URLQueryItem(name: "include[]", value: "course"),
            URLQueryItem(name: "include[]", value: "planner_overrides"),
            URLQueryItem(name: "filter[]", value: "submittable"),
        ])

        let courseJSON = try await courses
        var snap = SchoolSnapshot(fetchedAt: now)
        snap.grades = Self.parseGrades(courseJSON)
        let names = Dictionary(snap.grades.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        snap.upcoming = Self.parsePlanner(try await planner, base: base, courseNames: names)
        snap.missing = Self.parseMissing(try await missing, base: base, courseNames: names)
        snap.userName = try? await name
        return snap
    }

    // MARK: - Parsing (static so the self-test can feed it sample JSON)

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private static func link(_ value: Any?, base: URL) -> URL? {
        guard let s = value as? String else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: s, relativeTo: base)?.absoluteURL
    }

    private static func id(_ value: Any?) -> String {
        if let n = value as? NSNumber { return n.stringValue }
        return value as? String ?? UUID().uuidString
    }

    static func parseGrades(_ courses: [[String: Any]]) -> [CourseGrade] {
        courses.compactMap { c in
            guard let id = (c["id"] as? NSNumber)?.intValue, let name = c["name"] as? String else { return nil }
            let enrollment = (c["enrollments"] as? [[String: Any]])?.first { ($0["type"] as? String)?.contains("student") ?? false }
            return CourseGrade(id: id, name: name,
                               score: (enrollment?["computed_current_score"] as? NSNumber)?.doubleValue,
                               grade: enrollment?["computed_current_grade"] as? String)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parsePlanner(_ items: [[String: Any]], base: URL, courseNames: [Int: String]) -> [SchoolItem] {
        items.compactMap { item in
            let plannable = item["plannable"] as? [String: Any] ?? [:]
            let kind = item["plannable_type"] as? String ?? "item"
            guard let title = (plannable["title"] as? String) ?? (plannable["name"] as? String) else { return nil }
            let courseID = (item["course_id"] as? NSNumber)?.intValue
            let course = (item["context_name"] as? String) ?? courseID.flatMap { courseNames[$0] } ?? ""
            let due = date(plannable["due_at"]) ?? date(plannable["todo_date"]) ?? date(plannable["start_at"])
                ?? date(item["plannable_date"])
            var result = SchoolItem(id: "\(kind)-\(id(item["plannable_id"] ?? plannable["id"]))", title: title,
                                    course: course, due: due, url: link(item["html_url"], base: base), kind: kind)
            if let sub = item["submissions"] as? [String: Any] {
                result.submitted = sub["submitted"] as? Bool ?? false
                result.missing = sub["missing"] as? Bool ?? false
                result.late = sub["late"] as? Bool ?? false
                if sub["excused"] as? Bool == true { result.markedDone = true }
            }
            if let override = item["planner_override"] as? [String: Any], override["marked_complete"] as? Bool == true {
                result.markedDone = true
            }
            return result
        }
        .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    static func parseMissing(_ items: [[String: Any]], base: URL, courseNames: [Int: String]) -> [SchoolItem] {
        items.compactMap { a in
            guard let title = a["name"] as? String else { return nil }
            if let override = a["planner_override"] as? [String: Any], override["marked_complete"] as? Bool == true { return nil }
            let courseID = (a["course_id"] as? NSNumber)?.intValue
            let course = ((a["course"] as? [String: Any])?["name"] as? String) ?? courseID.flatMap { courseNames[$0] } ?? ""
            var item = SchoolItem(id: "assignment-\(id(a["id"]))", title: title, course: course,
                                  due: date(a["due_at"]), url: link(a["html_url"], base: base), kind: "assignment")
            item.missing = true
            return item
        }
        .sorted { ($0.due ?? .distantPast) > ($1.due ?? .distantPast) }
    }
}
