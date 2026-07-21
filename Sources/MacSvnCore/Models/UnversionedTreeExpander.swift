import Foundation

public enum UnversionedTreeExpansionError: Error, Equatable, Sendable {
    case entryLimitExceeded(Int)
}

public enum UnversionedTreeExpander {
    public static let defaultMaxDiscoveredEntries = 100_000

    public static func expand(
        statuses: [FileStatus],
        workingCopy: URL,
        recurse: Bool,
        maxDiscoveredEntries: Int = defaultMaxDiscoveredEntries,
        fileManager: FileManager = .default
    ) throws -> [FileStatus] {
        guard recurse else { return statuses }
        try Task.checkCancellation()
        let root = workingCopy.resolvingSymlinksInPath().standardizedFileURL
        var result = statuses
        var knownPaths = Set(statuses.map(\.path))
        let ignoredRoots = statuses
            .filter { $0.itemStatus == .ignored }
            .map(\.path)
            .map { $0.replacingOccurrences(of: "\\", with: "/") }
        var discoveredCount = 0

        for status in statuses where status.itemStatus == .unversioned {
            let relativeRoot = try normalizedRelativePath(status.path)
            let directory = root.appendingPathComponent(relativeRoot).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !fileManager.fileExists(atPath: directory.appendingPathComponent(".svn").path),
                  isDescendant(directory, of: root) else { continue }

            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let item = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if item.lastPathComponent == ".svn" {
                    enumerator.skipDescendants()
                    continue
                }
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true,
                   fileManager.fileExists(atPath: item.appendingPathComponent(".svn").path) {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                let relative = try relativePath(item, under: root)
                if ignoredRoots.contains(where: { ignored in
                    relative == ignored || relative.hasPrefix(ignored + "/")
                }) {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard knownPaths.insert(relative).inserted else { continue }
                discoveredCount += 1
                guard discoveredCount <= maxDiscoveredEntries else {
                    throw UnversionedTreeExpansionError.entryLimitExceeded(maxDiscoveredEntries)
                }
                result.append(FileStatus(
                    path: relative,
                    itemStatus: .unversioned,
                    revision: nil,
                    isTreeConflict: false
                ))
            }
        }
        let originalCount = statuses.count
        if result.count > originalCount {
            result.replaceSubrange(
                originalCount..<result.count,
                with: result[originalCount...].sorted { $0.path < $1.path }
            )
        }
        return result
    }

    public static func expandAsync(
        statuses: [FileStatus],
        workingCopy: URL,
        recurse: Bool,
        maxDiscoveredEntries: Int = defaultMaxDiscoveredEntries
    ) async throws -> [FileStatus] {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            try expand(
                statuses: statuses,
                workingCopy: workingCopy,
                recurse: recurse,
                maxDiscoveredEntries: maxDiscoveredEntries,
                fileManager: FileManager()
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func normalizedRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !(normalized as NSString).isAbsolutePath,
              !normalized.split(separator: "/").contains("..") else {
            throw RevertSafetyError.pathEscapesWorkingCopy(path)
        }
        return normalized
    }

    private static func relativePath(_ item: URL, under root: URL) throws -> String {
        guard isDescendant(item, of: root) else {
            throw RevertSafetyError.pathEscapesWorkingCopy(item.path)
        }
        let rootPath = canonicalPath(root.path)
        let itemPath = canonicalPath(item.standardizedFileURL.path)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return String(itemPath.dropFirst(prefix.count))
    }

    private static func isDescendant(_ child: URL, of root: URL) -> Bool {
        let rootPath = canonicalPath(root.path)
        let childPath = canonicalPath(child.standardizedFileURL.path)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return childPath == rootPath || childPath.hasPrefix(prefix)
    }

    private static func canonicalPath(_ path: String) -> String {
        path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
    }
}
