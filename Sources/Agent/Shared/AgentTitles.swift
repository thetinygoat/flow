import Foundation

/// One thing the user or the agent said, as `flw` keeps it for naming a session.
struct Excerpt: Codable, Equatable {
    enum Role: String, Codable {
        case user, assistant
    }

    var role: Role
    var text: String

    /// Reads the `role: text` form `flw event --excerpt` takes.
    init?(_ argument: String) {
        let parts = argument.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let role = Role(rawValue: parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(role: role, text: String(parts[1]))
    }

    init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// How to run an agent's CLI once, with nothing but its model, to name a
/// conversation. The prompt always goes on standard input.
struct Summarizer: Equatable {
    enum Output: Equatable {
        case standardOutput
        /// The reply is written to the file named after this option.
        case file(option: String)
    }

    /// Every run gets these from the agent's environment when they are set.
    static let basicVariables = ["PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER", "LOGNAME", "SHELL"]

    /// Those after the binary.
    var arguments: [String]
    var output: Output = .standardOutput
    /// Where the agent finds its configuration and credentials, passed
    /// through when set.
    var variables: [String] = []
    /// Options whose value a variable replaces when it is set, keyed by option.
    var overrides: [String: String] = [:]

    func arguments(replyFile: String, environment: [String: String]) -> [String] {
        var arguments = arguments
        for (option, variable) in overrides {
            guard let value = environment[variable], !value.isEmpty,
                  let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { continue }
            arguments[index + 1] = value
        }
        if case let .file(option) = output {
            arguments += [option, replyFile]
        }
        return arguments
    }

    /// Only what the agent needs to reach its model: nothing that tells it
    /// it runs in Flow, so the run reports nothing and loads none of Flow's hooks.
    func environment(from environment: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for key in Self.basicVariables + variables {
            result[key] = environment[key]
        }
        result["PATH"] = environment["PATH"].map(AgentShims.removingShims(from:))
        result[AgentEnvironment.disabledKey] = "1"
        return result
    }
}

/// What `flw` remembers of one session between hooks to name it once: the
/// start and the latest part of the conversation until it is named, and
/// afterwards only that it was.
struct TitleContext: Codable, Equatable {
    static let firstUserMessages = 2
    static let recentMessages = 4
    static let messageLimit = 240
    /// A naming run is given up on after a minute, so one marked longer ago than this has died.
    static let inFlightLimit: TimeInterval = 75

    struct Message: Codable, Equatable {
        var number: Int
        var role: Excerpt.Role
        var text: String
    }

    var first: [Message] = []
    var recent: [Message] = []
    var messageCount = 0
    var inFlightSince: Date?
    /// Set once naming ran, whatever came of it: a session is named only once.
    var named = false

    /// What is left once the session is named.
    static let finished = TitleContext(named: true)

    mutating func append(_ excerpt: Excerpt) {
        let text = String(excerpt.text.oneLine.prefix(Self.messageLimit))
        guard !named, !text.isEmpty else { return }
        messageCount += 1
        let message = Message(number: messageCount, role: excerpt.role, text: text)
        if excerpt.role == .user, first.count < Self.firstUserMessages {
            first.append(message)
        }
        recent = Array((recent + [message]).suffix(Self.recentMessages))
    }

    /// Oldest first, each message once.
    var messages: [Message] {
        let firstNumbers = Set(first.map(\.number))
        return first + recent.filter { !firstNumbers.contains($0.number) }
    }

    func shouldName(now: Date) -> Bool {
        guard !named, messages.contains(where: { $0.role == .user }), messages.contains(where: { $0.role == .assistant }) else { return false }
        guard let inFlightSince else { return true }
        return now.timeIntervalSince(inFlightSince) >= Self.inFlightLimit
    }

    var prompt: String {
        let conversation = messages.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        return """
            Below are the start and the latest part of a conversation between a user and a coding agent.

            <conversation>
            \(conversation)
            </conversation>

            Reply with only a title for this conversation, as a document heading of at most 8 words: a noun phrase, no leading "The conversation" or "Explaining", no trailing period, no quotes.
            """
    }
}

/// Turns what a model replied into a title.
enum TitleReply {
    /// The sidebar trims titles to fit, so this only stops a runaway reply.
    static let limit = 120
    private static let decoration = CharacterSet(charactersIn: "\"'`“”‘’*_#>-•").union(.whitespaces)

    /// Nil when the reply holds no title.
    static func clean(_ reply: String) -> String? {
        guard let line = reply.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: decoration) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        var title = line.oneLine
        if title.lowercased().hasPrefix("title:") {
            title = title.dropFirst("title:".count).trimmingCharacters(in: decoration)
        }
        title = title.trimmingCharacters(in: decoration.union(CharacterSet(charactersIn: ".")))
        if title.count > limit {
            let cut = title.prefix(limit + 1)
            title = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(title.prefix(limit))
            title = title.trimmingCharacters(in: decoration.union(.punctuationCharacters))
        }
        guard !title.isEmpty else { return nil }
        return title
    }
}

/// Where `flw` keeps each session's `TitleContext`, readable only by the user.
/// A file that cannot be read or written counts as nothing kept: a title is
/// never worth failing a hook over.
struct TitleStore {
    static let standard = TitleStore(directory: AgentEnvironment.socketURL.deletingLastPathComponent().appendingPathComponent("agent-titles", isDirectory: true))

    /// Sessions whose agent was killed never end, so their contexts are
    /// removed once untouched for this long.
    static let staleAge: TimeInterval = 7 * 24 * 60 * 60

    let directory: URL

    func url(agent: String, session: String) -> URL? {
        guard agent.isSafeFileName, session.isSafeFileName else { return nil }
        return directory.appendingPathComponent(agent, isDirectory: true).appendingPathComponent("\(session).json")
    }

    /// Keeps what an event adds to its session's context, and tells whether
    /// the session should be named now, in which case it is marked as being named.
    func record(_ event: AgentEvent, excerpts: [Excerpt], now: Date) -> Bool {
        guard event.surfaceID != nil else { return false }
        switch event.kind {
        case .sessionEnded:
            remove(agent: event.agent, session: event.sessionID)
            return false
        // A new conversation, or a resumed one that starts without a title
        // in Flow, so it is named at the end of its next turn.
        case .sessionStarted:
            remove(agent: event.agent, session: event.sessionID)
            return false
        default:
            guard !excerpts.isEmpty || event.kind == .turnEnded else { return false }
            return update(agent: event.agent, session: event.sessionID) { context in
                excerpts.forEach { context.append($0) }
                guard event.kind == .turnEnded, context.shouldName(now: now) else { return false }
                context.inFlightSince = now
                return true
            } ?? false
        }
    }

    /// Runs `body` on the session's context while no other `flw` can, and
    /// saves what it leaves. Nil when the file cannot be used, or does not
    /// exist and `create` is false.
    @discardableResult
    func update<T>(agent: String, session: String, create: Bool = true, _ body: (inout TitleContext) -> T) -> T? {
        guard let url = url(agent: agent, session: session) else { return nil }
        if create, !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            removeStale(from: url.deletingLastPathComponent(), now: Date())
        }
        let fd = open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | (create ? O_CREAT : 0), 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard Self.lock(fd) else { return nil }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let stored = (try? file.readToEnd()) ?? nil
        var context = stored.flatMap { try? JSONDecoder().decode(TitleContext.self, from: $0) } ?? TitleContext()
        let before = context
        let result = body(&context)
        if context != before || stored == nil, let data = try? JSONEncoder().encode(context) {
            guard ftruncate(fd, 0) == 0, (try? file.seek(toOffset: 0)) != nil, (try? file.write(contentsOf: data)) != nil else { return nil }
        }
        return result
    }

    func remove(agent: String, session: String) {
        guard let url = url(agent: agent, session: session) else { return }
        unlink(url.path)
    }

    func removeStale(from directory: URL, now: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "json" {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > Self.staleAge else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Other holders are `flw` processes that let go within milliseconds,
    /// so one that holds on longer is waited out for a second at most.
    private static func lock(_ fd: Int32) -> Bool {
        for _ in 0..<20 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return true }
            usleep(50_000)
        }
        return false
    }
}

extension String {
    /// On one line, with runs of whitespace as one space and control characters gone.
    var oneLine: String {
        let visible = String(String.UnicodeScalarView(unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }))
        return visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    fileprivate var isSafeFileName: Bool {
        !isEmpty && !hasPrefix(".") && count <= 128 && allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}
