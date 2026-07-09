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

    func testListRemoteTrunkReturnsImmediateChildrenMetadata() async throws {
        let fixture = try makeFixture()

        let entries = try await fixture.backend.list(url: fixture.trunkURL, depth: .immediates, auth: nil)
        let names = Set(entries.map(\.name))

        XCTAssertTrue(names.contains("README.txt"))
        XCTAssertTrue(names.contains("src"))
        XCTAssertEqual(entries.first(where: { $0.name == "src" })?.kind, .directory)
        XCTAssertEqual(entries.first(where: { $0.name == "README.txt" })?.kind, .file)
        XCTAssertNotNil(entries.first(where: { $0.name == "README.txt" })?.revision)
    }

    func testCatRemoteFileReturnsUtf8Contents() async throws {
        let fixture = try makeFixture()

        let data = try await fixture.backend.cat(
            url: "\(fixture.trunkURL)/中文文件.txt",
            revision: nil,
            sizeLimit: 5 * 1024 * 1024,
            auth: nil
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "中文内容\n")
    }

    func testRemoteLogReadsTrunkHistoryWithoutCheckout() async throws {
        let fixture = try makeFixture()

        let entries = try await fixture.backend.remoteLog(
            url: fixture.trunkURL,
            from: Revision(1),
            batch: 10,
            verbose: true,
            auth: nil
        )

        XCTAssertEqual(entries.first?.revision, Revision(1))
        XCTAssertFalse(entries.first?.changedPaths.isEmpty ?? true)
    }

    func testServiceListsBranchesAndTagsFromRepositoryRoot() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)

        let branchList = try await service.branches(
            repositoryRoot: fixture.repositoryURL,
            layout: BranchLayout(),
            auth: nil
        )

        XCTAssertEqual(branchList.trunk?.url, fixture.trunkURL)
        XCTAssertEqual(branchList.branches.map(\.name), ["feature-one"])
        XCTAssertEqual(branchList.tags.map(\.name), ["v1.0"])
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
