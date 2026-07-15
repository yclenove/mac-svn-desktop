import Foundation

public enum CommitMessageHistoryStoreError: Error, Equatable, Sendable {
    case emptyMessage
}

public protocol CommitMessageHistoryProviding: Sendable {
    func recentMessages(workingCopy: URL) async throws -> [String]
    func record(message: String, workingCopy: URL) async throws
}

private struct CommitMessageHistoryFile: Codable {
    var histories: [String: [String]]

    init(histories: [String: [String]] = [:]) {
        self.histories = histories
    }
}

public actor CommitMessageHistoryStore: CommitMessageHistoryProviding {
    private let store: PersistenceStore<CommitMessageHistoryFile>
    private var limit: Int

    public init(fileURL: URL, limit: Int = 10) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: CommitMessageHistoryFile())
        self.limit = max(1, limit)
    }

    public func recentMessages(workingCopy: URL) async throws -> [String] {
        let file = try store.load()
        return file.histories[Self.key(for: workingCopy)] ?? []
    }

    public func record(message: String, workingCopy: URL) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommitMessageHistoryStoreError.emptyMessage
        }

        var file = try store.load()
        let key = Self.key(for: workingCopy)
        var messages = file.histories[key] ?? []
        messages.removeAll { $0 == trimmed }
        messages.insert(trimmed, at: 0)
        if messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        file.histories[key] = messages
        try store.save(file)
    }

    public func updateLimit(_ newLimit: Int) throws {
        let normalizedLimit = max(1, newLimit)
        var file = try store.load()
        for key in file.histories.keys {
            if let messages = file.histories[key], messages.count > normalizedLimit {
                file.histories[key] = Array(messages.prefix(normalizedLimit))
            }
        }
        try store.save(file)
        limit = normalizedLimit
    }

    private static func key(for workingCopy: URL) -> String {
        workingCopy.standardizedFileURL.path
    }
}
