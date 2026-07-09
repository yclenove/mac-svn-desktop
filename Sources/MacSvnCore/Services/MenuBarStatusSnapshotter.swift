import Foundation

public protocol MenuBarRemoteLogProviding: Sendable {
    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
}

public protocol MenuBarStatusSnapshotting: Sendable {
    func snapshot(records: [WorkingCopyRecord], now: Date) async throws -> MenuBarStatusSnapshot
}

public actor MenuBarStatusSnapshotter: MenuBarStatusSnapshotting {
    private let statusProvider: any StatusProviding
    private let remoteLogProvider: any MenuBarRemoteLogProviding
    private let configuration: MenuBarMonitorConfiguration

    public init(
        statusProvider: any StatusProviding,
        remoteLogProvider: any MenuBarRemoteLogProviding,
        configuration: MenuBarMonitorConfiguration = MenuBarMonitorConfiguration()
    ) {
        self.statusProvider = statusProvider
        self.remoteLogProvider = remoteLogProvider
        self.configuration = configuration
    }

    public func snapshot(records: [WorkingCopyRecord], now: Date = Date()) async throws -> MenuBarStatusSnapshot {
        var snapshots: [MenuBarWorkingCopySnapshot] = []

        for record in records {
            snapshots.append(await snapshot(record: record))
        }

        return MenuBarStatusSnapshot(checkedAt: now, workingCopies: snapshots)
    }

    private func snapshot(record: WorkingCopyRecord) async -> MenuBarWorkingCopySnapshot {
        guard record.isValid else {
            return Self.emptySnapshot(record: record, state: .invalidWorkingCopy)
        }

        do {
            let statuses = try await statusProvider.status(wc: URL(fileURLWithPath: record.localPath))
            let remoteEntries = try await remoteLogProvider.remoteLogFromHead(
                url: record.repoURL,
                batch: configuration.remoteLogBatchSize,
                verbose: false,
                auth: nil
            )
            let remoteNewEntries = Self.remoteNewEntries(remoteEntries, baseline: record.revision)

            return MenuBarWorkingCopySnapshot(
                recordID: record.id,
                name: record.name,
                localPath: record.localPath,
                repoURL: record.repoURL,
                state: .loaded,
                localChangeCount: Self.localChangeCount(statuses),
                conflictedCount: Self.conflictedCount(statuses),
                remoteNewCommitCount: remoteNewEntries.count,
                remoteLatestRevision: remoteEntries.map(\.revision).max { $0.value < $1.value },
                notificationSummary: Self.notificationSummary(recordName: record.name, newEntries: remoteNewEntries)
            )
        } catch {
            return Self.emptySnapshot(record: record, state: .error(String(describing: error)))
        }
    }

    private static func localChangeCount(_ statuses: [FileStatus]) -> Int {
        statuses.filter { status in
            switch status.itemStatus {
            case .normal, .ignored, .external, .none:
                return false
            default:
                return true
            }
        }.count
    }

    private static func conflictedCount(_ statuses: [FileStatus]) -> Int {
        statuses.filter { $0.itemStatus == .conflicted || $0.isTreeConflict }.count
    }

    private static func remoteNewEntries(_ entries: [LogEntry], baseline: Revision?) -> [LogEntry] {
        guard let baseline else {
            return []
        }

        return entries.filter { $0.revision.value > baseline.value }
    }

    private static func notificationSummary(recordName: String, newEntries: [LogEntry]) -> String? {
        guard let first = newEntries.first else {
            return nil
        }

        return "\(recordName) 有 \(newEntries.count) 个新提交（\(first.author): \(first.message)）"
    }

    private static func emptySnapshot(
        record: WorkingCopyRecord,
        state: MenuBarWorkingCopySnapshotState
    ) -> MenuBarWorkingCopySnapshot {
        MenuBarWorkingCopySnapshot(
            recordID: record.id,
            name: record.name,
            localPath: record.localPath,
            repoURL: record.repoURL,
            state: state,
            localChangeCount: 0,
            conflictedCount: 0,
            remoteNewCommitCount: 0,
            remoteLatestRevision: nil,
            notificationSummary: nil
        )
    }
}

extension SvnService: MenuBarRemoteLogProviding {}
