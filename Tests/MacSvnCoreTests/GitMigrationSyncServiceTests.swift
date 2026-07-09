import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncServiceTests: XCTestCase {
    func testRegisterMigrationPersistsRecord() async throws {
        let store = FakeGitMigrationSyncStore()
        let service = GitMigrationSyncService(store: store, gitBackend: FakeGitMigrationSyncBackend())
        let repository = URL(fileURLWithPath: "/tmp/history")

        let record = try await service.registerMigration(
            sourceURL: "file:///repo",
            repository: repository,
            targetRemote: "origin"
        )

        XCTAssertEqual(record.sourceURL, "file:///repo")
        XCTAssertEqual(record.repositoryPath, repository.path)
        XCTAssertEqual(record.targetRemote, "origin")
    }

    func testSyncFetchesReadsRevisionsUpdatesRecordAndPushesConfiguredRemote() async throws {
        let store = FakeGitMigrationSyncStore()
        let backend = FakeGitMigrationSyncBackend(revisions: [
            GitSvnRevisionMetadata(revision: Revision(1)),
            GitSvnRevisionMetadata(revision: Revision(3))
        ])
        let service = GitMigrationSyncService(store: store, gitBackend: backend)
        let record = makeRecord(targetRemote: "origin")

        let report = try await service.sync(record: record, syncedAt: Date(timeIntervalSince1970: 20))
        let events = await backend.events()

        XCTAssertEqual(events, [
            .svnFetch(URL(fileURLWithPath: "/tmp/history")),
            .gitSvnRevisions(URL(fileURLWithPath: "/tmp/history")),
            .pushAll(URL(fileURLWithPath: "/tmp/history"), "origin"),
            .pushTags(URL(fileURLWithPath: "/tmp/history"), "origin")
        ])
        XCTAssertEqual(report.completedSteps, [.gitSvnFetch, .revisionScan, .gitPushBranches, .gitPushTags])
        XCTAssertEqual(report.latestRevision, Revision(3))
        XCTAssertEqual(report.updatedRecord.lastSyncedRevision, Revision(3))
        XCTAssertEqual(report.updatedRecord.lastSyncedAt, Date(timeIntervalSince1970: 20))
    }

    func testSyncWithoutRemoteOnlyFetchesAndScansRevisions() async throws {
        let backend = FakeGitMigrationSyncBackend(revisions: [
            GitSvnRevisionMetadata(revision: Revision(5))
        ])
        let service = GitMigrationSyncService(store: FakeGitMigrationSyncStore(), gitBackend: backend)
        let record = makeRecord(targetRemote: nil)

        let report = try await service.sync(record: record, syncedAt: Date(timeIntervalSince1970: 20))
        let events = await backend.events()

        XCTAssertEqual(events, [
            .svnFetch(URL(fileURLWithPath: "/tmp/history")),
            .gitSvnRevisions(URL(fileURLWithPath: "/tmp/history"))
        ])
        XCTAssertEqual(report.completedSteps, [.gitSvnFetch, .revisionScan])
        XCTAssertEqual(report.latestRevision, Revision(5))
    }

    private func makeRecord(targetRemote: String?) -> GitMigrationSyncRecord {
        GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: targetRemote,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
    }
}

private enum GitMigrationSyncBackendEvent: Equatable, Sendable {
    case svnFetch(URL)
    case gitSvnRevisions(URL)
    case pushAll(URL, String)
    case pushTags(URL, String)
}

private actor FakeGitMigrationSyncBackend: GitBackend {
    private var recordedEvents: [GitMigrationSyncBackendEvent] = []
    private let revisions: [GitSvnRevisionMetadata]

    init(revisions: [GitSvnRevisionMetadata] = []) {
        self.revisions = revisions
    }

    func events() -> [GitMigrationSyncBackendEvent] {
        recordedEvents
    }

    func initRepository(at repository: URL) async throws {}

    func addAll(repository: URL) async throws {}

    func commit(repository: URL, message: String) async throws {}

    func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata] {
        recordedEvents.append(.gitSvnRevisions(repository))
        return revisions
    }

    func svnFetch(repository: URL) async throws {
        recordedEvents.append(.svnFetch(repository))
    }

    func pushAll(repository: URL, remote: String) async throws {
        recordedEvents.append(.pushAll(repository, remote))
    }

    func pushTags(repository: URL, remote: String) async throws {
        recordedEvents.append(.pushTags(repository, remote))
    }
}

private actor FakeGitMigrationSyncStore: GitMigrationSyncRecordStoring {
    private var savedRecords: [GitMigrationSyncRecord] = []

    func loadRecords() async throws -> [GitMigrationSyncRecord] {
        savedRecords
    }

    func addRecord(
        sourceURL: String,
        repository: URL,
        targetRemote: String?
    ) async throws -> GitMigrationSyncRecord {
        let record = GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: sourceURL,
            repositoryPath: repository.path,
            targetRemote: targetRemote,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
        savedRecords = [record]
        return record
    }

    func updateSyncMetadata(
        id: UUID,
        latestRevision: Revision?,
        syncedAt: Date
    ) async throws -> GitMigrationSyncRecord {
        let existing = savedRecords.first { $0.id == id } ?? GitMigrationSyncRecord(
            id: id,
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
        let updated = GitMigrationSyncRecord(
            id: existing.id,
            sourceURL: existing.sourceURL,
            repositoryPath: existing.repositoryPath,
            targetRemote: existing.targetRemote,
            createdAt: existing.createdAt,
            lastSyncedAt: syncedAt,
            lastSyncedRevision: latestRevision
        )
        savedRecords = [updated]
        return updated
    }

    func updateSchedule(
        id: UUID,
        isEnabled: Bool,
        intervalMinutes: Int?
    ) async throws -> GitMigrationSyncRecord {
        let existing = savedRecords.first { $0.id == id } ?? GitMigrationSyncRecord(
            id: id,
            sourceURL: "file:///repo",
            repositoryPath: "/tmp/history",
            targetRemote: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
        let updated = GitMigrationSyncRecord(
            id: existing.id,
            sourceURL: existing.sourceURL,
            repositoryPath: existing.repositoryPath,
            targetRemote: existing.targetRemote,
            createdAt: existing.createdAt,
            lastSyncedAt: existing.lastSyncedAt,
            lastSyncedRevision: existing.lastSyncedRevision,
            isScheduledSyncEnabled: isEnabled,
            syncIntervalMinutes: intervalMinutes
        )
        savedRecords = [updated]
        return updated
    }
}
