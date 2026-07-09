import Foundation

public struct CommandPaletteSearchEngine: Sendable {
    private let actions: [CommandPaletteAction]
    private let files: [CommandPaletteFileItem]
    private let logs: [LogEntry]

    public init(actions: [CommandPaletteAction], files: [CommandPaletteFileItem], logs: [LogEntry]) {
        self.actions = actions
        self.files = files
        self.logs = logs
    }

    public func search(_ rawQuery: String, limit: Int = 20) -> [CommandPaletteResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        let results = actionResults(query: query) + fileResults(query: query) + logResults(query: query)
        return Array(results.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }.prefix(max(1, limit)))
    }

    private func actionResults(query: String) -> [CommandPaletteResult] {
        actions.compactMap { action in
            let haystack = ([action.title] + action.keywords).joined(separator: " ")
            guard let score = Self.score(query: query, text: haystack) else {
                return nil
            }
            return CommandPaletteResult(kind: .action(action.id), title: action.title, subtitle: nil, score: score + 10)
        }
    }

    private func fileResults(query: String) -> [CommandPaletteResult] {
        files.compactMap { file in
            guard let score = Self.score(query: query, text: file.path) else {
                return nil
            }
            return CommandPaletteResult(
                kind: .file(path: file.path),
                title: (file.path as NSString).lastPathComponent,
                subtitle: file.path,
                score: score
            )
        }
    }

    private func logResults(query: String) -> [CommandPaletteResult] {
        logs.compactMap { entry in
            let revisionToken = "r\(entry.revision.value)"
            let haystack = "\(revisionToken) \(entry.author) \(entry.message)"
            guard let score = Self.score(query: query, text: haystack) else {
                return nil
            }
            return CommandPaletteResult(
                kind: .log(revision: entry.revision),
                title: revisionToken,
                subtitle: "\(entry.author): \(entry.message)",
                score: score + 5
            )
        }
    }

    private static func score(query: String, text: String) -> Int? {
        let queryTokens = query.lowercased().split(separator: " ").map(String.init)
        let lowerText = text.lowercased()
        guard queryTokens.allSatisfy({ lowerText.contains($0) }) else {
            return nil
        }

        let exactBonus = lowerText == query.lowercased() ? 100 : 0
        let prefixBonus = lowerText.hasPrefix(query.lowercased()) ? 50 : 0
        return exactBonus + prefixBonus + queryTokens.reduce(0) { $0 + $1.count }
    }
}
