import Foundation
import XCTest
@testable import MacSvnCore

final class SvnCliBackendIntegrationTests: SvnIntegrationTestCase {
    func testCheckoutThenStatusIsClean() async throws {
        let fixture = try makeFixture()

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)

        XCTAssertEqual(statuses, [])
    }

    func testCheckoutWithEmptyDepthCreatesWorkingCopyWithoutChildren() async throws {
        let fixture = try makeFixture()

        try await fixture.backend.checkout(
            url: fixture.trunkURL,
            to: fixture.workingCopy,
            depth: .empty,
            auth: nil
        )
        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)

        XCTAssertEqual(statuses, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("src").path))
    }

    func testUpdateSetDepthFilesFetchesRootFilesAfterEmptyCheckout() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy, depth: .empty, auth: nil)

        _ = try await fixture.backend.update(
            wc: fixture.workingCopy,
            paths: [],
            revision: nil,
            setDepth: .files,
            auth: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("src").path))
    }

    func testInfoReadsWorkingCopyUrlAndRevision() async throws {
        let fixture = try makeFixture()

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let info = try await fixture.backend.info(wc: fixture.workingCopy, target: ".")

        XCTAssertEqual(info.url, fixture.trunkURL)
        XCTAssertEqual(info.repositoryRoot, fixture.repositoryURL)
        XCTAssertEqual(info.revision, Revision(1))
        XCTAssertEqual(info.kind, "dir")
    }

    func testWorkspaceStoreImportsRealWorkingCopyMetadata() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let store = WorkspaceStore(fileURL: fixture.root.appendingPathComponent("workspaces.json"))

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let record = try await store.addExistingWorkingCopy(localPath: fixture.workingCopy, infoProvider: service)

        XCTAssertEqual(record.name, "wc")
        XCTAssertEqual(record.repoURL, fixture.trunkURL)
        XCTAssertEqual(record.revision, Revision(1))
        XCTAssertTrue(record.isValid)
    }

    func testStatusSeesModifiedAddedAndDeletedFiles() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

        try "changed\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: fixture.workingCopy.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await fixture.backend.add(wc: fixture.workingCopy, paths: ["new.txt"])
        try await fixture.backend.delete(wc: fixture.workingCopy, paths: ["src/main.txt"])

        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        let statusesByPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0.itemStatus) })

        XCTAssertEqual(statusesByPath["README.txt"], .modified)
        XCTAssertEqual(statusesByPath["new.txt"], .added)
        XCTAssertEqual(statusesByPath["src/main.txt"], .deleted)
    }

    func testCommitWithChineseMessageIsReadBackFromLog() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try "修复内容\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        let message = "修复：登录超时问题 🚀"
        let revision = try await fixture.backend.commit(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: message,
            auth: nil
        )
        let entries = try await fixture.backend.log(
            wc: fixture.workingCopy,
            target: ".",
            from: revision,
            batch: 1,
            verbose: true
        )

        XCTAssertEqual(entries.first?.revision, revision)
        XCTAssertEqual(entries.first?.message, message)
    }
}
