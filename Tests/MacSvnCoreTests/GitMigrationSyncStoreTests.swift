import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testLoadMissingFileReturnsEmptyRecords() async throws {
        let store = makeStore()

        let records = try await store.loadRecords()

        XCTAssertEqual(records, [])
    }

    func testAddRecordPersistsAndReloads() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        let repository = URL(fileURLWithPath: "/tmp/history")

        let record = try await store.addRecord(
            sourceURL: " file:///repo ",
            repository: repository,
            targetRemote: "origin"
        )

        XCTAssertEqual(record.sourceURL, "file:///repo")
        XCTAssertEqual(record.repositoryPath, repository.path)
        XCTAssertEqual(record.targetRemote, "origin")

        let reloaded = try await makeStore(root: root).loadRecords()
        XCTAssertEqual(reloaded, [record])
    }

    func testAddRecordForSameRepositoryUpdatesExistingRecord() async throws {
        let store = makeStore()
        let repository = URL(fileURLWithPath: "/tmp/history")

        let first = try await store.addRecord(sourceURL: "file:///old", repository: repository, targetRemote: nil)
        let second = try await store.addRecord(sourceURL: "file:///new", repository: repository, targetRemote: "origin")
        let records = await store.records()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceURL, "file:///new")
        XCTAssertEqual(records.first?.targetRemote, "origin")
    }

    func testUpdateSyncMetadataPersistsLatestRevisionAndDate() async throws {
        let store = makeStore()
        let record = try await store.addRecord(
            sourceURL: "file:///repo",
            repository: URL(fileURLWithPath: "/tmp/history"),
            targetRemote: nil
        )

        let updated = try await store.updateSyncMetadata(
            id: record.id,
            latestRevision: Revision(42),
            syncedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(updated.lastSyncedRevision, Revision(42))
        XCTAssertEqual(updated.lastSyncedAt, Date(timeIntervalSince1970: 100))
        let records = try await store.loadRecords()
        XCTAssertEqual(records, [updated])
    }

    func testUpdateSyncMetadataRejectsMissingRecord() async throws {
        let store = makeStore()
        let id = UUID()

        do {
            _ = try await store.updateSyncMetadata(
                id: id,
                latestRevision: Revision(42),
                syncedAt: Date(timeIntervalSince1970: 100)
            )
            XCTFail("Expected missing record")
        } catch let error as GitMigrationSyncError {
            XCTAssertEqual(error, .recordNotFound(id))
        } catch {
            XCTFail("Expected GitMigrationSyncError, got \(error)")
        }
    }

    func testAddRecordRejectsEmptySourceURL() async {
        let store = makeStore()

        do {
            _ = try await store.addRecord(
                sourceURL: "  ",
                repository: URL(fileURLWithPath: "/tmp/history"),
                targetRemote: nil
            )
            XCTFail("Expected empty source URL")
        } catch let error as GitMigrationSyncError {
            XCTAssertEqual(error, .emptySourceURL)
        } catch {
            XCTFail("Expected GitMigrationSyncError, got \(error)")
        }
    }

    private func makeStore(root: URL? = nil) -> GitMigrationSyncStore {
        let root = root ?? temporaryRoot()
        return GitMigrationSyncStore(fileURL: root.appendingPathComponent("migrations.json"))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreMigrationSync-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
