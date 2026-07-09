import Foundation
import XCTest
@testable import MacSvnCore

final class WorkspaceStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testAddWorkingCopyRejectsDirectoryWithoutSvnMetadata() async throws {
        let root = temporaryRoot()
        let directory = root.appendingPathComponent("not-wc", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = makeStore(root: root)

        do {
            _ = try await store.addWorkingCopy(localPath: directory, repoURL: "file:///repo/trunk")
            XCTFail("Expected invalid working copy error")
        } catch let error as WorkspaceStoreError {
            XCTAssertEqual(error, .invalidWorkingCopy(path: directory.path))
        } catch {
            XCTFail("Expected WorkspaceStoreError, got \(error)")
        }

        let records = await store.records()
        XCTAssertEqual(records, [])
    }

    func testAddWorkingCopyPersistsDefaultNameAndMetadata() async throws {
        let root = temporaryRoot()
        let workingCopy = try makeWorkingCopy(root: root, name: "ProjectA")
        let store = makeStore(root: root)

        let record = try await store.addWorkingCopy(
            localPath: workingCopy,
            repoURL: "https://svn.example.com/repo/trunk",
            revision: Revision(12),
            username: "yangchao"
        )

        XCTAssertEqual(record.name, "ProjectA")
        XCTAssertEqual(record.localPath, workingCopy.resolvingSymlinksInPath().path)
        XCTAssertEqual(record.repoURL, "https://svn.example.com/repo/trunk")
        XCTAssertEqual(record.revision, Revision(12))
        XCTAssertEqual(record.username, "yangchao")
        XCTAssertTrue(record.isValid)

        let reloadedStore = makeStore(root: root)
        let reloaded = try await reloadedStore.load()
        XCTAssertEqual(reloaded, [record])
    }

    func testRemoveWorkingCopyOnlyRemovesRecord() async throws {
        let root = temporaryRoot()
        let workingCopy = try makeWorkingCopy(root: root, name: "ProjectA")
        let store = makeStore(root: root)
        let record = try await store.addWorkingCopy(localPath: workingCopy, repoURL: "file:///repo/trunk")

        try await store.removeWorkingCopy(id: record.id)

        let records = await store.records()
        XCTAssertEqual(records, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workingCopy.path))
    }

    func testLoadMarksMissingWorkingCopyInvalid() async throws {
        let root = temporaryRoot()
        let workingCopy = try makeWorkingCopy(root: root, name: "ProjectA")
        let store = makeStore(root: root)
        let record = try await store.addWorkingCopy(localPath: workingCopy, repoURL: "file:///repo/trunk")
        try FileManager.default.removeItem(at: workingCopy)

        let reloadedStore = makeStore(root: root)
        let reloaded = try await reloadedStore.load()

        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.id, record.id)
        XCTAssertFalse(reloaded.first?.isValid ?? true)
    }

    private func makeStore(root: URL) -> WorkspaceStore {
        WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json"))
    }

    private func makeWorkingCopy(root: URL, name: String) throws -> URL {
        let workingCopy = root.appendingPathComponent(name, isDirectory: true)
        let metadata = workingCopy.appendingPathComponent(".svn", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        return workingCopy
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreWorkspace-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
