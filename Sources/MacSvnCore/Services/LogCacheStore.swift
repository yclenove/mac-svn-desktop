import Foundation

public protocol LogCaching: Sendable {
    func snapshot(
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date
    ) async throws -> LogCacheSnapshot?

    func merge(
        entries: [LogEntry],
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date
    ) async throws
}

public actor LogCacheStore: LogCaching {
    private let store: PersistenceStore<LogCacheFile>

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: LogCacheFile())
    }

    public func snapshot(
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date = Date()
    ) throws -> LogCacheSnapshot? {
        let policy = policy.normalized
        guard policy.enabled else { return nil }
        var file = try store.load()
        let original = file
        prune(&file, policy: policy, now: now)
        if file != original {
            try store.save(file)
        }
        return file.snapshots.first { $0.key == key }
    }

    public func merge(
        entries: [LogEntry],
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date = Date()
    ) throws {
        let policy = policy.normalized
        guard policy.enabled, !entries.isEmpty else { return }
        var file = try store.load()
        prune(&file, policy: policy, now: now)

        let existing = file.snapshots.first(where: { $0.key == key })?.entries ?? []
        var byRevision = Dictionary(uniqueKeysWithValues: existing.map { ($0.revision.value, $0) })
        for entry in entries {
            byRevision[entry.revision.value] = entry
        }
        let merged = byRevision.values
            .sorted { $0.revision.value > $1.revision.value }
            .prefix(policy.maxEntriesPerTarget)

        file.snapshots.removeAll { $0.key == key }
        file.snapshots.append(LogCacheSnapshot(
            key: key,
            updatedAt: now,
            entries: Array(merged)
        ))
        try store.save(file)
    }

    public func clear(_ key: LogCacheKey) throws {
        var file = try store.load()
        file.snapshots.removeAll { $0.key == key }
        try store.save(file)
    }

    public func clearAll() throws {
        try store.save(LogCacheFile())
    }

    public func overview(
        policy: LogCachePolicy,
        now: Date = Date()
    ) throws -> LogCacheOverview {
        let policy = policy.normalized
        guard policy.enabled else { return .empty }
        var file = try store.load()
        let original = file
        prune(&file, policy: policy, now: now)
        if file != original {
            try store.save(file)
        }
        guard !file.snapshots.isEmpty else { return .empty }
        let dates = file.snapshots.map(\.updatedAt)
        return LogCacheOverview(
            targetCount: file.snapshots.count,
            entryCount: file.snapshots.reduce(0) { $0 + $1.entries.count },
            oldestUpdate: dates.min(),
            newestUpdate: dates.max()
        )
    }

    private func prune(_ file: inout LogCacheFile, policy: LogCachePolicy, now: Date) {
        let cutoff = now.addingTimeInterval(-Double(policy.retentionDays) * 86_400)
        file.snapshots.removeAll { $0.updatedAt < cutoff }
        file.snapshots = file.snapshots.map { snapshot in
            let entries = snapshot.entries
                .sorted { $0.revision.value > $1.revision.value }
                .prefix(policy.maxEntriesPerTarget)
            return LogCacheSnapshot(
                key: snapshot.key,
                updatedAt: snapshot.updatedAt,
                entries: Array(entries)
            )
        }
    }
}
