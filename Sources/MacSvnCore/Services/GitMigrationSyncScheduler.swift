import Foundation

public protocol GitMigrationScheduledSyncProviding: Sendable {
    func loadRecords() async throws -> [GitMigrationSyncRecord]
    func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport
}

public actor GitMigrationSyncScheduler {
    private let provider: any GitMigrationScheduledSyncProviding

    public init(provider: any GitMigrationScheduledSyncProviding) {
        self.provider = provider
    }

    public func dueRecords(now: Date) async throws -> [GitMigrationSyncRecord] {
        let records = try await provider.loadRecords()
        return records.filter { record in
            guard record.isScheduledSyncEnabled,
                  let interval = record.syncIntervalMinutes,
                  interval > 0 else {
                return false
            }

            guard let lastSyncedAt = record.lastSyncedAt else {
                return true
            }

            return now.timeIntervalSince(lastSyncedAt) >= TimeInterval(interval * 60)
        }
    }

    public func runDueSyncs(now: Date = Date()) async throws -> GitMigrationScheduledSyncReport {
        let recordsToSync = try await dueRecords(now: now)
        var completedReports: [GitMigrationSyncReport] = []
        var failedRecordIDs: [UUID] = []

        for record in recordsToSync {
            do {
                let report = try await provider.sync(record: record)
                completedReports.append(report)
            } catch {
                failedRecordIDs.append(record.id)
            }
        }

        return GitMigrationScheduledSyncReport(
            attemptedRecordIDs: recordsToSync.map(\.id),
            completedReports: completedReports,
            failedRecordIDs: failedRecordIDs
        )
    }
}

extension GitMigrationSyncService: GitMigrationScheduledSyncProviding {}
