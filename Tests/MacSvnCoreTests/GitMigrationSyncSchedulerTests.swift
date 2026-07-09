import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncSchedulerTests: XCTestCase {
    func testRunDueSyncsOnlySyncsEnabledDueRecords() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let due = makeRecord(
            id: UUID(),
            path: "/tmp/due",
            enabled: true,
            interval: 30,
            lastSyncedAt: Date(timeIntervalSince1970: 1_000 - 31 * 60)
        )
        let fresh = makeRecord(
            id: UUID(),
            path: "/tmp/fresh",
            enabled: true,
            interval: 30,
            lastSyncedAt: Date(timeIntervalSince1970: 1_000 - 10 * 60)
        )
        let disabled = makeRecord(
            id: UUID(),
            path: "/tmp/disabled",
            enabled: false,
            interval: 30,
            lastSyncedAt: nil
        )
        let provider = FakeScheduledSyncProvider(records: [due, fresh, disabled])
        let scheduler = GitMigrationSyncScheduler(provider: provider)

        let report = try await scheduler.runDueSyncs(now: now)
        let syncedIDs = await provider.syncedRecordIDs()

        XCTAssertEqual(syncedIDs, [due.id])
        XCTAssertEqual(report.attemptedRecordIDs, [due.id])
        XCTAssertEqual(report.completedReports.count, 1)
        XCTAssertEqual(report.failedRecordIDs, [])
    }

    func testRunDueSyncsRecordsFailuresAndContinues() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let first = makeRecord(
            id: UUID(),
            path: "/tmp/first",
            enabled: true,
            interval: 10,
            lastSyncedAt: nil
        )
        let second = makeRecord(
            id: UUID(),
            path: "/tmp/second",
            enabled: true,
            interval: 10,
            lastSyncedAt: nil
        )
        let provider = FakeScheduledSyncProvider(records: [first, second], failingIDs: [first.id])
        let scheduler = GitMigrationSyncScheduler(provider: provider)

        let report = try await scheduler.runDueSyncs(now: now)

        XCTAssertEqual(report.attemptedRecordIDs, [first.id, second.id])
        XCTAssertEqual(report.failedRecordIDs, [first.id])
        XCTAssertEqual(report.completedReports.map(\.recordID), [second.id])
    }

    private func makeRecord(
        id: UUID,
        path: String,
        enabled: Bool,
        interval: Int?,
        lastSyncedAt: Date?
    ) -> GitMigrationSyncRecord {
        GitMigrationSyncRecord(
            id: id,
            sourceURL: "file:///repo",
            repositoryPath: path,
            targetRemote: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: lastSyncedAt,
            lastSyncedRevision: nil,
            isScheduledSyncEnabled: enabled,
            syncIntervalMinutes: interval
        )
    }
}

private actor FakeScheduledSyncProvider: GitMigrationScheduledSyncProviding {
    private let records: [GitMigrationSyncRecord]
    private let failingIDs: Set<UUID>
    private var syncedIDs: [UUID] = []

    init(records: [GitMigrationSyncRecord], failingIDs: Set<UUID> = []) {
        self.records = records
        self.failingIDs = failingIDs
    }

    func syncedRecordIDs() -> [UUID] {
        syncedIDs
    }

    func loadRecords() async throws -> [GitMigrationSyncRecord] {
        records
    }

    func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport {
        syncedIDs.append(record.id)
        if failingIDs.contains(record.id) {
            throw SvnError.other(code: nil, stderr: "scheduled sync failed")
        }

        return GitMigrationSyncReport(
            recordID: record.id,
            repositoryPath: record.repositoryPath,
            completedSteps: [.gitSvnFetch, .revisionScan],
            latestRevision: Revision(1),
            updatedRecord: record
        )
    }
}
