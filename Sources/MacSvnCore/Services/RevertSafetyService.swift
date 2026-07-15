import Foundation

public protocol RevertTrashStoring: Sendable {
    func moveToTrash(_ sourceURL: URL) throws -> URL
    func restoreFromTrash(_ trashURL: URL, to originalURL: URL) throws
}

public struct RevertTrashBackup: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let originalURL: URL
        public let trashURL: URL

        public init(originalURL: URL, trashURL: URL) {
            self.originalURL = originalURL
            self.trashURL = trashURL
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }
}

public enum RevertSafetyError: Error, Equatable, Sendable, CustomStringConvertible {
    case pathEscapesWorkingCopy(String)
    case stageFailed(operation: String, recovery: String)
    case restoreFailed(operation: String, recovery: String)

    public var description: String {
        switch self {
        case .pathEscapesWorkingCopy(let path):
            return "pathEscapesWorkingCopy(\(path))"
        case .stageFailed(let operation, let recovery):
            return "trash staging failed: \(operation); trash rollback failed: \(recovery)"
        case .restoreFailed(let operation, let recovery):
            return "revert failed: \(operation); trash restore failed: \(recovery)"
        }
    }
}

public struct RevertSafetyService: Sendable {
    private let store: any RevertTrashStoring

    public init(store: any RevertTrashStoring = MacOSRevertTrashStore()) {
        self.store = store
    }

    public func stage(
        workingCopy: URL,
        selectedPaths: [String],
        statuses: [FileStatus],
        recursive: Bool
    ) throws -> RevertTrashBackup {
        let root = workingCopy.standardizedFileURL
        let normalizedSelections = try selectedPaths.map(Self.normalizedRelativePath)
        for status in statuses where status.path.contains("..") || (status.path as NSString).isAbsolutePath {
            _ = try Self.normalizedRelativePath(status.path)
        }

        let candidates = statuses.filter { status in
            guard [.modified, .replaced, .conflicted].contains(status.itemStatus) else { return false }
            let path = status.path.replacingOccurrences(of: "\\", with: "/")
            return normalizedSelections.contains { selected in
                path == selected || (recursive && (selected == "." || path.hasPrefix(selected + "/")))
            }
        }

        var entries: [RevertTrashBackup.Entry] = []
        var seen = Set<String>()
        do {
            for status in candidates {
                let relative = try Self.normalizedRelativePath(status.path)
                guard seen.insert(relative).inserted else { continue }
                let source = root.appendingPathComponent(relative).standardizedFileURL
                guard Self.isDescendant(source, of: root) else {
                    throw RevertSafetyError.pathEscapesWorkingCopy(status.path)
                }
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
                let trashURL = try store.moveToTrash(source)
                entries.append(.init(originalURL: source, trashURL: trashURL))
            }
        } catch {
            var recoveryErrors: [String] = []
            for entry in entries.reversed() {
                do {
                    try store.restoreFromTrash(entry.trashURL, to: entry.originalURL)
                } catch {
                    recoveryErrors.append(String(describing: error))
                }
            }
            if !recoveryErrors.isEmpty {
                throw RevertSafetyError.stageFailed(
                    operation: String(describing: error),
                    recovery: recoveryErrors.joined(separator: "; ")
                )
            }
            throw error
        }
        return RevertTrashBackup(entries: entries)
    }

    public func restore(_ backup: RevertTrashBackup) throws {
        for entry in backup.entries.reversed() {
            if FileManager.default.fileExists(atPath: entry.originalURL.path) {
                try FileManager.default.removeItem(at: entry.originalURL)
            }
            try store.restoreFromTrash(entry.trashURL, to: entry.originalURL)
        }
    }

    public func errorAfterRestoring(
        _ backup: RevertTrashBackup,
        operationError: any Error
    ) -> any Error {
        guard !backup.entries.isEmpty else { return operationError }
        do {
            try restore(backup)
            return operationError
        } catch {
            return RevertSafetyError.restoreFailed(
                operation: String(describing: operationError),
                recovery: String(describing: error)
            )
        }
    }

    private static func normalizedRelativePath(_ value: String) throws -> String {
        let normalized = value
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !(normalized as NSString).isAbsolutePath else {
            throw RevertSafetyError.pathEscapesWorkingCopy(value)
        }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw RevertSafetyError.pathEscapesWorkingCopy(value)
        }
        let result = components.filter { $0 != "." }.joined(separator: "/")
        return result.isEmpty ? "." : result
    }

    private static func isDescendant(_ child: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return child.path == root.path || child.path.hasPrefix(rootPath)
    }
}

public struct MacOSRevertTrashStore: RevertTrashStoring, Sendable {
    public init() {}

    public func moveToTrash(_ sourceURL: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw CocoaError(.fileWriteUnknown)
        }
        return resultingURL as URL
    }

    public func restoreFromTrash(_ trashURL: URL, to originalURL: URL) throws {
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: trashURL, to: originalURL)
    }
}
