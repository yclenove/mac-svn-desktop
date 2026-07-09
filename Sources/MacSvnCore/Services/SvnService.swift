import Foundation

public enum SvnServiceError: Error, Equatable, Sendable {
    case emptyCommitMessage
    case wcBusy(operation: String)
}

public actor SvnService {
    private let backend: any SvnBackend
    private var activeWriteOperations: [URL: String] = [:]

    public init(backend: any SvnBackend) {
        self.backend = backend
    }

    public func status(wc: URL) async throws -> [FileStatus] {
        try await backend.status(wc: wc)
    }

    public func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        try await backend.diff(wc: wc, target: target, r1: r1, r2: r2)
    }

    public func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        try await backend.log(wc: wc, target: target, from: from, batch: batch, verbose: verbose)
    }

    public func update(wc: URL, paths: [String] = [], revision: Revision? = nil) async throws -> UpdateSummary {
        try await withWriteLock(wc: wc, operation: "update") {
            try await backend.update(wc: wc, paths: paths, revision: revision)
        }
    }

    public func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SvnServiceError.emptyCommitMessage
        }

        return try await withWriteLock(wc: wc, operation: "commit") {
            let statuses = try await backend.status(wc: wc)
            let conflicts = conflictingSelectedPaths(paths: paths, statuses: statuses)

            guard conflicts.isEmpty else {
                throw SvnError.conflict(paths: conflicts)
            }

            return try await backend.commit(wc: wc, paths: paths, message: message, auth: auth)
        }
    }

    public func add(wc: URL, paths: [String]) async throws {
        try await withWriteLock(wc: wc, operation: "add") {
            try await backend.add(wc: wc, paths: paths)
        }
    }

    public func delete(wc: URL, paths: [String]) async throws {
        try await withWriteLock(wc: wc, operation: "delete") {
            try await backend.delete(wc: wc, paths: paths)
        }
    }

    public func revert(wc: URL, paths: [String], recursive: Bool = false) async throws {
        try await withWriteLock(wc: wc, operation: "revert") {
            try await backend.revert(wc: wc, paths: paths, recursive: recursive)
        }
    }

    public func cleanup(wc: URL) async throws {
        try await withWriteLock(wc: wc, operation: "cleanup") {
            try await backend.cleanup(wc: wc)
        }
    }

    private func withWriteLock<T: Sendable>(
        wc: URL,
        operation: String,
        body: () async throws -> T
    ) async throws -> T {
        if let activeOperation = activeWriteOperations[wc] {
            throw SvnServiceError.wcBusy(operation: activeOperation)
        }

        activeWriteOperations[wc] = operation
        defer {
            activeWriteOperations.removeValue(forKey: wc)
        }

        return try await body()
    }

    private func conflictingSelectedPaths(paths: [String], statuses: [FileStatus]) -> [String] {
        let statusesByPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0) })

        return paths.filter { path in
            guard let status = statusesByPath[path] else {
                return false
            }

            return status.itemStatus == .conflicted || status.isTreeConflict
        }
    }
}
