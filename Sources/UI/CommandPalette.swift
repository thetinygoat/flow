import Foundation

/// What the command palette lists: every terminal in a window, as a tab or as
/// a pane of a split tab, or only the terminals with agents. Choosing an item
/// goes to its terminal.
enum CommandPalette {
    /// Every tab and pane, most recently used first, or the agents in order
    /// of how long they have needed the user.
    enum Mode {
        case places, agents

        var placeholder: String {
            switch self {
            case .places: "Go to tab or pane"
            case .agents: "Go to agent"
            }
        }

        /// Shown when there is nothing to list before any search.
        var emptyMessage: String {
            switch self {
            case .places: "No terminals"
            case .agents: "No agents"
            }
        }

        /// Working agents are listed for completeness but don't need the user yet.
        var dimsWorkingAgents: Bool {
            self == .agents
        }
    }

    struct Item: Equatable {
        var terminal: UUID
        var title: String
        /// The terminal's directory, unless it is already the title.
        var detail: String
        /// Where the terminal is, as much as tells it apart: the workspace,
        /// the tab when the workspace has more than one, and the pane when the
        /// tab is split.
        var location: String
        /// The location in full, which is what a search matches, so "tab 1"
        /// finds a workspace's only tab too.
        var fullLocation: String
        var layout: PaneLayout
    }

    /// Each pane's frame in a unit square with y pointing down, in tree order,
    /// which of them is the item's own, and which one is zoomed.
    struct PaneLayout: Equatable {
        var frames: [CGRect]
        var highlighted: Int
        var zoomed: Int?

        var zoom: Zoom? {
            guard let zoomed else { return nil }
            return zoomed == highlighted ? .zoomed : .hidden
        }
    }

    /// Whether a pane fills its zoomed tab, or is hidden by another pane that
    /// does. Going to a hidden pane unzooms the tab.
    enum Zoom: Equatable {
        case zoomed, hidden
    }

    // MARK: Items

    /// In sidebar order: each workspace's tabs, a split tab as its panes.
    static func items<Leaf>(in store: WorkspaceStoreModel<Leaf>) -> [Item] {
        store.workspaces.flatMap { workspace in
            workspace.tabs.enumerated().flatMap { index, tab in
                let tabName = "Tab \(index + 1)"
                let fullLocation = "\(workspace.name) › \(tabName)"
                let location = workspace.tabs.count > 1 ? fullLocation : workspace.name
                let panes = tab.panes.leaves
                let frames = frames(of: tab.panes.root, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                guard panes.count > 1 else {
                    return [Item(terminal: tab.focusedLeaf.id, title: tab.title, detail: directory(of: tab.focusedLeaf),
                                 location: location, fullLocation: fullLocation, layout: PaneLayout(frames: frames, highlighted: 0))]
                }
                let zoomed = panes.firstIndex { $0 === tab.panes.zoomed }
                return zip(panes.indices, zip(panes, positions(in: tab.panes.root))).map { index, pane in
                    let (leaf, position) = pane
                    return Item(terminal: leaf.id, title: leaf.displayTitle, detail: directory(of: leaf),
                                location: "\(location) › \(position)", fullLocation: "\(fullLocation) › \(position)",
                                layout: PaneLayout(frames: frames, highlighted: index, zoomed: zoomed))
                }
            }
        }
    }

    private static func directory(of leaf: some PaneLeaf) -> String {
        guard let directory = leaf.workingDirectory?.abbreviatingHome, directory != leaf.displayTitle else { return "" }
        return directory
    }

    private static func frames<Leaf>(of node: PaneNode<Leaf>, in rect: CGRect) -> [CGRect] {
        guard let first = node.first, let second = node.second else { return [rect] }
        let (a, b) = node.axis == .horizontal
            ? rect.divided(atDistance: rect.width * node.ratio, from: .minXEdge)
            : rect.divided(atDistance: rect.height * node.ratio, from: .minYEdge)
        return frames(of: first, in: a) + frames(of: second, in: b)
    }

    /// Each pane named for its side of the outermost split along each axis,
    /// such as "Left" or "Top right". When that leaves two panes with the
    /// same name, the panes are numbered instead.
    static func positions<Leaf>(in root: PaneNode<Leaf>) -> [String] {
        var names: [String] = []
        func visit(_ node: PaneNode<Leaf>, vertical: String?, horizontal: String?) {
            guard let first = node.first, let second = node.second else {
                let name = [vertical, horizontal].compactMap { $0 }.joined(separator: " ")
                return names.append(name.prefix(1).uppercased() + name.dropFirst())
            }
            if node.axis == .horizontal {
                visit(first, vertical: vertical, horizontal: horizontal ?? "left")
                visit(second, vertical: vertical, horizontal: horizontal ?? "right")
            } else {
                visit(first, vertical: vertical ?? "top", horizontal: horizontal)
                visit(second, vertical: vertical ?? "bottom", horizontal: horizontal)
            }
        }
        visit(root, vertical: nil, horizontal: nil)
        guard Set(names).count < names.count else { return names }
        return names.indices.map { "Pane \($0 + 1)" }
    }

    // MARK: Order

    /// Most recently focused first, so the place in view leads and the one
    /// before it follows. Terminals not focused yet keep their order.
    static func recentFirst(_ items: [Item], recentlyFocused: [UUID]) -> [Item] {
        let rank = Dictionary(recentlyFocused.enumerated().map { ($1, $0) }) { first, _ in first }
        return items.enumerated()
            .sorted { (rank[$0.element.terminal] ?? .max, $0.offset) < (rank[$1.element.terminal] ?? .max, $1.offset) }
            .map(\.element)
    }

    /// The agent in view, then the ones waiting for input, the finished ones
    /// and the working ones, each longest first. Terminals without an agent
    /// to show are left out.
    static func agents(_ items: [Item], current: UUID?, statuses: [UUID: AgentStatus]) -> [Item] {
        // A finished turn needs the user sooner than one still running.
        let rank: [AgentIndicator: Int] = [.waiting: 0, .done: 1, .working: 2]
        return items.enumerated()
            .compactMap { index, item -> (item: Item, key: (Int, Int, Date, Int))? in
                guard let status = statuses[item.terminal] else { return nil }
                return (item, (item.terminal == current ? 0 : 1, rank[status.indicator]!, status.since, index))
            }
            .sorted { $0.key < $1.key }
            .map(\.item)
    }

    // MARK: Search

    /// The items matching the query, best first. Ties keep their listed order.
    static func filter(_ items: [Item], query: String) -> [Item] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in score(words, in: item).map { (item: item, score: $0, index: index) } }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.item)
    }

    /// A query found in the title alone outranks one that needs the location
    /// or directory too.
    private static func score(_ words: [String], in item: Item) -> Int? {
        if let score = score(words, in: item.title) { return score + 1000 }
        return score(words, in: "\(item.fullLocation) \(item.title) \(item.detail)")
    }

    /// Nil unless every word of the query is found in the text, in any order,
    /// ignoring case. A word counts for most as a whole word of the text, then
    /// as the start of one, then anywhere in the text, and least as its letters
    /// in order. A number has to be a whole word, so "2" finds "Tab 2" but not
    /// "any2any" or "Tab 12".
    static func score(_ words: [String], in text: String) -> Int? {
        let text = text.lowercased()
        let textWords = text.split { !$0.isLetter && !$0.isNumber }
        var total = 0
        for word in words {
            if textWords.contains(where: { $0 == word }) {
                total += 40
            } else if word.allSatisfy(\.isNumber) {
                return nil
            } else if textWords.contains(where: { $0.hasPrefix(word) }) {
                total += 30
            } else if text.contains(word) {
                total += 20
            } else if isSubsequence(word, of: text) {
                total += 10
            } else {
                return nil
            }
        }
        return total
    }

    private static func isSubsequence(_ word: String, of text: String) -> Bool {
        var remaining = text[...]
        for character in word {
            guard let match = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: match)...]
        }
        return true
    }
}
