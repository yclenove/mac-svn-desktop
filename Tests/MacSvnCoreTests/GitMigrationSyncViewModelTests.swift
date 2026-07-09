import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncViewModelTests: XCTestCase {
    @MainActor
    func testLoadRegisterAndSyncUpdateStateAndRecords() async {
        let record = makeRecord()
        let updated = GitMigrationSyncRecord(
            id: record.id,
            sourceURL: record.sourceURL,
            repositoryPath: record.repositoryPath,
            targetRemote: record.targetRemote,
            createdAt: record.createdAt,
            lastSyncedAt: Date(timeIntervalSince1970: 20),
            lastSyncedRevision: Revision(5)
        )
        let report = GitMigrationSyncReport(
            recordID: record.id,
            repositoryPath: record.repositoryPath,
            completedSteps: [.gitSvnFetch, .revisionScan],
            latestRevision: Revision(5),
            updatedRecord: updated
        )
        let provider = FakeGitMigrationSyncProvider(
            records: [record],
            registerResult: record,
            syncResult: report
        )
        let viewModel = GitMigrationSyncViewModel(provider: provider)

        await viewModel.loadRecords()
        XCTAssertEqual(viewModel.records, [record])

        await viewModel.registerMigration(
            sourceURL: "file:///repo",
            repository: URL(fileURLWithPath: "/tmp/history"),
            targetRemote: "origin"
        )
        XCTAssertEqual(viewModel.records, [record])

        await viewModel.sync(record)
        XCTAssertEqual(viewModel.state, .completed(report))
        XCTAssertEqual(viewModel.lastReport, report)
        XCTAssertEqual(viewModel.records, [updated])
    }

    @MainActor
    func testProviderFailureStoresError() async {
        let provider = FakeGitMigrationSyncProvider(error: SvnError.other(code: 1, stderr: "boom"))
        let viewModel = GitMigrationSyncViewModel(provider: provider)

        await viewModel.loadRecords()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.other(code: 1, stderr: "boom"))))
    }

    @MainActor
    func testConfigureScheduleUpdatesRecordState() async {
        let record = makeRecord()
        var scheduled = record
        scheduled.isScheduledSyncEnabled = true
        scheduled.syncIntervalMinutes = 30
        let provider = FakeGitMigrationSyncProvider(
            records: [record],
            scheduleResult: scheduled
        )
        let viewModel = GitMigrationSyncViewModel(provider: provider)

        await viewModel.loadRecords()
        await viewModel.configureSchedule(record, isEnabled: true, intervalMinutes: 30)

        XCTAssertEqual(viewModel.records, [scheduled])
        XCTAssertEqual(viewModel.state, .idle)
    }

    private func makeRecord() -> GitMigrationSyncRecord {
        GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: "origin",
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
    }
}

private actor FakeGitMigrationSyncProvider: GitMigrationSyncProviding {
    private let recordsResult: Result<[GitMigrationSyncRecord], Error>
    private let registerResult: Result<GitMigrationSyncRecord, Error>
    private let syncResult: Result<GitMigrationSyncReport, Error>
    private let scheduleResult: Result<GitMigrationSyncRecord, Error>

    init(
        records: [GitMigrationSyncRecord] = [],
        registerResult: GitMigrationSyncRecord? = nil,
        syncResult: GitMigrationSyncReport? = nil,
        scheduleResult: GitMigrationSyncRecord? = nil
    ) {
        self.recordsResult = .success(records)
        self.registerResult = .success(registerResult ?? records.first ?? GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        ))
        self.syncResult = .success(syncResult ?? GitMigrationSyncReport(
            recordID: UUID(),
            repositoryPath: "/tmp/history",
            completedSteps: [],
            latestRevision: nil,
            updatedRecord: GitMigrationSyncRecord(
                id: UUID(),
                sourceURL: "file:///repo",
                repositoryPath: "/tmp/history",
                targetRemote: nil,
                createdAt: Date(timeIntervalSince1970: 10),
                lastSyncedAt: nil,
                lastSyncedRevision: nil
            )
        ))
        self.scheduleResult = .success(scheduleResult ?? records.first ?? GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        ))
    }

    init(error: Error) {
        self.recordsResult = .failure(error)
        self.registerResult = .failure(error)
        self.syncResult = .failure(error)
        self.scheduleResult = .failure(error)
    }

    func loadRecords() async throws -> [GitMigrationSyncRecord] {
        try recordsResult.get()
    }

    func registerMigration(
        sourceURL: String,
        repository: URL,
        targetRemote: String?
    ) async throws -> GitMigrationSyncRecord {
        try registerResult.get()
    }

    func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport {
        try syncResult.get()
    }

    func updateSchedule(
        id: UUID,
        isEnabled: Bool,
        intervalMinutes: Int?
    ) async throws -> GitMigrationSyncRecord {
        try scheduleResult.get()
    }
}
