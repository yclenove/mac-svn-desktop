import Foundation

public enum SvnServiceError: Error, Equatable, Sendable {
    case emptyCommitMessage
    case wcBusy(operation: String)
    case localChangesPreventSwitch(paths: [String])
}

public protocol CredentialProviding: Sendable {
    func credential(for wc: URL) async throws -> Credential?
}

public actor SvnService {
    private let backend: any SvnBackend
    private let credentialProvider: (any CredentialProviding)?
    private var activeWriteOperations: [URL: String] = [:]

    public init(backend: any SvnBackend, credentialProvider: (any CredentialProviding)? = nil) {
        self.backend = backend
        self.credentialProvider = credentialProvider
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

    public func remoteLog(
        url: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        auth: Credential? = nil
    ) async throws -> [LogEntry] {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.remoteLog(url: url, from: from, batch: batch, verbose: verbose, auth: auth)
        }
    }

    public func list(url: String, depth: SvnDepth, auth: Credential? = nil) async throws -> [RemoteEntry] {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.list(url: url, depth: depth, auth: auth)
        }
    }

    public func cat(
        url: String,
        revision: Revision? = nil,
        sizeLimit: Int,
        auth: Credential? = nil
    ) async throws -> Data {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.cat(url: url, revision: revision, sizeLimit: sizeLimit, auth: auth)
        }
    }

    public func info(wc: URL, target: String) async throws -> SvnInfo {
        try await backend.info(wc: wc, target: target)
    }

    public func update(
        wc: URL,
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil
    ) async throws -> UpdateSummary {
        try await withWriteLock(wc: wc, operation: "update") {
            try await retryingAuthentication(wc: wc, initialAuth: nil) { auth in
                try await backend.update(wc: wc, paths: paths, revision: revision, setDepth: setDepth, auth: auth)
            }
        }
    }

    public func switchTo(
        wc: URL,
        url: String,
        auth: Credential? = nil,
        allowLocalChanges: Bool = false
    ) async throws -> UpdateSummary {
        try await withWriteLock(wc: wc, operation: "switch") {
            let statuses = try await backend.status(wc: wc)
            let localChangePaths = localChangePaths(from: statuses)

            guard allowLocalChanges || localChangePaths.isEmpty else {
                throw SvnServiceError.localChangesPreventSwitch(paths: localChangePaths)
            }

            let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
            return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
                try await backend.switchTo(wc: wc, url: url, auth: auth)
            }
        }
    }

    public func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth = .infinity,
        auth: Credential? = nil
    ) async throws {
        try await withWriteLock(wc: destination, operation: "checkout") {
            try await retryingAuthentication(wc: destination, initialAuth: auth) { auth in
                try await backend.checkout(url: url, to: destination, depth: depth, auth: auth)
            }
        }
    }

    public func copy(
        source: String,
        destination: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SvnServiceError.emptyCommitMessage
        }

        let credentialScope = URL(string: destination) ?? URL(fileURLWithPath: destination)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.copy(source: source, destination: destination, message: message, auth: auth)
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

            return try await retryingAuthentication(wc: wc, initialAuth: auth) { auth in
                try await backend.commit(wc: wc, paths: paths, message: message, auth: auth)
            }
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

    private func localChangePaths(from statuses: [FileStatus]) -> [String] {
        statuses.compactMap { status in
            if status.isTreeConflict {
                return status.path
            }

            switch status.itemStatus {
            case .normal, .none, .ignored, .external:
                return nil
            case .unversioned, .modified, .added, .deleted, .missing, .conflicted, .replaced, .incomplete, .obstructed:
                return status.path
            }
        }
    }

    private func retryingAuthentication<T: Sendable>(
        wc: URL,
        initialAuth: Credential?,
        operation: (Credential?) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(initialAuth)
        } catch SvnError.authentication {
            guard let credential = try await credentialProvider?.credential(for: wc) else {
                throw SvnError.authentication
            }

            return try await operation(credential)
        }
    }
}

extension SvnService: WorkingCopyInfoProviding {}
