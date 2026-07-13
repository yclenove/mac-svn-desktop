import Foundation

public struct LogCachePolicy: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var retentionDays: Int
    public var maxEntriesPerTarget: Int

    public init(
        enabled: Bool = true,
        retentionDays: Int = 90,
        maxEntriesPerTarget: Int = 20_000
    ) {
        self.enabled = enabled
        self.retentionDays = max(1, retentionDays)
        self.maxEntriesPerTarget = max(1, maxEntriesPerTarget)
    }

    public var normalized: LogCachePolicy {
        LogCachePolicy(
            enabled: enabled,
            retentionDays: retentionDays,
            maxEntriesPerTarget: maxEntriesPerTarget
        )
    }
}

public struct LogCacheIdentity: Codable, Equatable, Hashable, Sendable {
    public let repositoryRoot: String
    public let target: String

    public init(repositoryRoot: String, target: String) {
        self.repositoryRoot = repositoryRoot
        self.target = target
    }

    public func key(stopOnCopy: Bool) -> LogCacheKey {
        LogCacheKey(
            repositoryRoot: repositoryRoot,
            target: target,
            stopOnCopy: stopOnCopy
        )
    }
}

public struct LogCacheKey: Codable, Equatable, Hashable, Sendable {
    public let repositoryRoot: String
    public let target: String
    public let stopOnCopy: Bool

    public init(repositoryRoot: String, target: String, stopOnCopy: Bool) {
        self.repositoryRoot = repositoryRoot
        self.target = target
        self.stopOnCopy = stopOnCopy
    }
}

public struct LogCacheSnapshot: Codable, Equatable, Sendable {
    public let key: LogCacheKey
    public let updatedAt: Date
    public let entries: [LogEntry]

    public init(key: LogCacheKey, updatedAt: Date, entries: [LogEntry]) {
        self.key = key
        self.updatedAt = updatedAt
        self.entries = entries
    }
}

public struct LogCacheOverview: Equatable, Sendable {
    public let targetCount: Int
    public let entryCount: Int
    public let oldestUpdate: Date?
    public let newestUpdate: Date?

    public init(targetCount: Int, entryCount: Int, oldestUpdate: Date?, newestUpdate: Date?) {
        self.targetCount = targetCount
        self.entryCount = entryCount
        self.oldestUpdate = oldestUpdate
        self.newestUpdate = newestUpdate
    }

    public static let empty = LogCacheOverview(
        targetCount: 0,
        entryCount: 0,
        oldestUpdate: nil,
        newestUpdate: nil
    )
}

struct LogCacheFile: Codable, Equatable, Sendable {
    var version: Int
    var snapshots: [LogCacheSnapshot]

    init(version: Int = 1, snapshots: [LogCacheSnapshot] = []) {
        self.version = version
        self.snapshots = snapshots
    }
}
