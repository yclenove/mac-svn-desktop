import Foundation

public enum UnversionedDeletionPolicyError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath(String)
    case notUnversioned(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): return "路径不在工作副本内：\(path)"
        case .notUnversioned(let path): return "路径不是未版本项：\(path)"
        }
    }
}

/// 删除未版本项前的候选筛选与路径边界校验。
public enum UnversionedDeletionPolicy {
    public static func candidates(
        from statuses: [FileStatus],
        workingCopy: URL
    ) throws -> [FileStatus] {
        var result: [String: FileStatus] = [:]
        for status in statuses where status.itemStatus == .unversioned {
            let path = try normalizedPath(status.path, workingCopy: workingCopy)
            result[path] = FileStatus(
                path: path,
                itemStatus: status.itemStatus,
                revision: status.revision,
                isTreeConflict: status.isTreeConflict,
                remoteItemStatus: status.remoteItemStatus,
                changelist: status.changelist
            )
        }
        return result.values.sorted { $0.path < $1.path }
    }

    public static func validatedPaths(
        _ paths: [String],
        from statuses: [FileStatus],
        workingCopy: URL
    ) throws -> [String] {
        let candidates = try candidates(from: statuses, workingCopy: workingCopy)
        let allowed = Set(candidates.map(\.path))
        var normalized: Set<String> = []
        for rawPath in paths {
            let path = try normalizedPath(rawPath, workingCopy: workingCopy)
            guard allowed.contains(path) else {
                throw UnversionedDeletionPolicyError.notUnversioned(rawPath)
            }
            normalized.insert(path)
        }
        let shallowestFirst = normalized.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
        }
        var collapsed: [String] = []
        for path in shallowestFirst where !collapsed.contains(where: { path.hasPrefix($0 + "/") }) {
            collapsed.append(path)
        }
        return collapsed.sorted()
    }

    private static func normalizedPath(_ rawPath: String, workingCopy: URL) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("\\") else {
            throw UnversionedDeletionPolicyError.invalidPath(rawPath)
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." }) else {
            throw UnversionedDeletionPolicyError.invalidPath(rawPath)
        }
        let normalized = parts.filter { $0 != "." }.joined(separator: "/")
        guard !normalized.isEmpty else {
            throw UnversionedDeletionPolicyError.invalidPath(rawPath)
        }

        let root = workingCopy.standardizedFileURL.path
        let candidate = workingCopy.appendingPathComponent(normalized).standardizedFileURL.path
        guard candidate.hasPrefix(root + "/") else {
            throw UnversionedDeletionPolicyError.invalidPath(rawPath)
        }
        return normalized
    }
}
