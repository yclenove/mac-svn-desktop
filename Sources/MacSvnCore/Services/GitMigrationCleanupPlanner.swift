import Foundation

public struct GitMigrationCleanupPlanner: Sendable {
    public static let defaultLargeFileThresholdBytes = 10 * 1024 * 1024

    public init() {}

    public func plan(
        entries: [RemoteEntry],
        svnIgnoreProperties: [SvnProperty] = [],
        excludedPaths: [String] = [],
        largeFileThresholdBytes: Int = Self.defaultLargeFileThresholdBytes
    ) throws -> GitMigrationCleanupPlan {
        guard largeFileThresholdBytes > 0 else {
            throw GitMigrationCleanupError.invalidLargeFileThreshold(largeFileThresholdBytes)
        }

        let largeFiles = entries.compactMap { entry -> GitMigrationLargeFileFinding? in
            guard entry.kind == .file,
                  let sizeBytes = entry.size,
                  sizeBytes > largeFileThresholdBytes,
                  let path = normalizedPath(entry.path) else {
                return nil
            }

            return GitMigrationLargeFileFinding(
                path: path,
                sizeBytes: sizeBytes,
                thresholdBytes: largeFileThresholdBytes
            )
        }
        .sorted { $0.path < $1.path }

        let normalizedExcludedPaths = Set(excludedPaths.compactMap(normalizedPath(_:))).sorted()

        return GitMigrationCleanupPlan(
            largeFiles: largeFiles,
            excludedPaths: normalizedExcludedPaths,
            gitIgnoreContents: gitIgnoreContents(from: svnIgnoreProperties)
        )
    }

    private func gitIgnoreContents(from properties: [SvnProperty]) -> String {
        var rules: [String] = []
        var seenRules: Set<String> = []

        for property in properties where property.name == "svn:ignore" {
            let targetPrefix = normalizedTargetPrefix(property.target)
            for rawPattern in property.value.components(separatedBy: .newlines) {
                let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pattern.isEmpty else {
                    continue
                }

                let rule = targetPrefix.map { "\($0)/\(pattern)" } ?? pattern
                guard seenRules.insert(rule).inserted else {
                    continue
                }
                rules.append(rule)
            }
        }

        guard !rules.isEmpty else {
            return ""
        }
        return rules.joined(separator: "\n") + "\n"
    }

    private func normalizedPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedTargetPrefix(_ target: String) -> String? {
        guard let normalized = normalizedPath(target), normalized != "." else {
            return nil
        }
        return normalized
    }
}
