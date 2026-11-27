import Foundation

/// Counts active installs without identifying one. Each install works out for
/// itself whether it is the first activity of a day, week or month, so adding
/// up the events gives the active installs and nothing links one event to the
/// next.
final class Telemetry {
    private static let appKey = "A-EU-0714395921"
    private static let endpoint = URL(string: "https://eu.aptabase.com/api/v0/events")!
    private static let retryDelay: TimeInterval = 3600
    private static let installWeekKey = "TelemetryInstallWeek"

    var isEnabled = false {
        didSet {
            guard !isEnabled else { return }
            sending?.cancel()
            retryAfter = nil
        }
    }

    private let defaults: UserDefaults
    private let send: (URLRequest) async throws -> Void
    private let now: () -> Date
    private var sending: Task<Void, Never>?
    private var retryAfter: Date?

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { Date() },
         send: @escaping (URLRequest) async throws -> Void = Telemetry.post) {
        self.defaults = defaults
        self.now = now
        self.send = send
    }

    /// When an install that predates telemetry was first opened is unknown.
    func recordInstall(isNew: Bool) {
        guard defaults.string(forKey: Self.installWeekKey) == nil else { return }
        defaults.set(isNew ? Period.week.name(at: now()) : "earlier", forKey: Self.installWeekKey)
    }

    /// Returns the send it started, if any.
    @discardableResult
    func recordActivity() -> Task<Void, Never>? {
        let date = now()
        guard isEnabled, sending == nil, retryAfter.map({ date >= $0 }) ?? true else { return nil }
        let due = Period.allCases.filter { defaults.string(forKey: $0.defaultsKey) != $0.name(at: date) }
        guard !due.isEmpty, let request = request(for: due, at: date) else { return nil }
        let task = Task { @MainActor in
            do {
                try await send(request)
                due.forEach { defaults.set($0.name(at: date), forKey: $0.defaultsKey) }
            } catch {
                if isEnabled { retryAfter = now().addingTimeInterval(Self.retryDelay) }
                logger.notice("telemetry not sent: \(error, privacy: .public)")
            }
            sending = nil
        }
        sending = task
        return task
    }

    private func request(for periods: [Period], at date: Date) -> URLRequest? {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion)"
        let sessionID = UUID().uuidString
        let events = periods.map { period in
            Event(
                timestamp: date, sessionId: sessionID, eventName: period.eventName,
                systemProps: Event.SystemProps(
                    isDebug: AppFolder.isDebugBuild,
                    osName: "macOS", osVersion: osVersion,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    sdkVersion: "flow"),
                props: period == .week ? ["install_week": defaults.string(forKey: Self.installWeekKey) ?? "earlier"] : [:])
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(events) else { return nil }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.appKey, forHTTPHeaderField: "App-Key")
        request.setValue("macOS/\(osVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Right after the Mac wakes there is often no network yet, so a send
    /// waits for one rather than failing.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = retryDelay
        return URLSession(configuration: configuration)
    }()

    private static func post(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else {
            throw URLError(.badServerResponse)
        }
    }
}

extension Telemetry {
    enum Period: String, CaseIterable {
        case day, week, month

        var eventName: String { "active_\(rawValue)" }
        var defaultsKey: String { "TelemetryLast\(rawValue.capitalized)" }

        /// In UTC, as the dashboard's days are.
        func name(at date: Date) -> String {
            let parts = Self.calendar.dateComponents([.year, .month, .day, .yearForWeekOfYear, .weekOfYear], from: date)
            return switch self {
            case .day: String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            case .week: String(format: "%04d-W%02d", parts.yearForWeekOfYear!, parts.weekOfYear!)
            case .month: String(format: "%04d-%02d", parts.year!, parts.month!)
            }
        }

        private static let calendar: Calendar = {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = .gmt
            return calendar
        }()
    }

    /// An event in Aptabase's format.
    private struct Event: Encodable {
        struct SystemProps: Encodable {
            let isDebug: Bool
            let osName: String
            let osVersion: String
            let appVersion: String
            let sdkVersion: String
        }

        let timestamp: Date
        let sessionId: String
        let eventName: String
        let systemProps: SystemProps
        let props: [String: String]
    }
}
