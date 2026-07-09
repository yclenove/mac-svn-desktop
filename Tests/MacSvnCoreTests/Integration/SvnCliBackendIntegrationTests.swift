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

    func testServiceCopyCreatesRemoteBranch() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let destination = "\(fixture.repositoryURL)/branches/from-copy"

        let revision = try await service.copy(
            source: fixture.trunkURL,
            destination: destination,
            message: "创建分支：from-copy",
            auth: nil
        )
        let branchList = try await service.branches(
            repositoryRoot: fixture.repositoryURL,
            layout: BranchLayout(),
            auth: nil
        )

        XCTAssertGreaterThan(revision.value, 1)
        XCTAssertTrue(branchList.branches.map(\.name).contains("from-copy"))
    }

    func testServiceSwitchChangesWorkingCopyUrlToBranch() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let branchURL = "\(fixture.repositoryURL)/branches/switch-copy"

        _ = try await service.copy(
            source: fixture.trunkURL,
            destination: branchURL,
            message: "创建分支：switch-copy",
            auth: nil
        )
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        _ = try await service.switchTo(
            wc: fixture.workingCopy,
            url: branchURL,
            auth: nil
        )
        let info = try await fixture.backend.info(wc: fixture.workingCopy, target: ".")

        XCTAssertEqual(info.url, branchURL)
    }

    func testServicePreviewAndMergeBranchChangesIntoTrunk() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let branchURL = "\(fixture.repositoryURL)/branches/merge-source"

        _ = try await service.copy(
            source: fixture.trunkURL,
            destination: branchURL,
            message: "create merge branch",
            auth: nil
        )
        try await fixture.backend.checkout(url: branchURL, to: fixture.workingCopy)
        try "branch change\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await service.commit(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: "branch change",
            auth: nil
        )
        _ = try await service.switchTo(wc: fixture.workingCopy, url: fixture.trunkURL, auth: nil)

        let preview = try await service.merge(
            wc: fixture.workingCopy,
            source: branchURL,
            range: nil,
            dryRun: true,
            auth: nil
        )
        let summary = try await service.merge(
            wc: fixture.workingCopy,
            source: branchURL,
            range: nil,
            dryRun: false,
            auth: nil
        )

        XCTAssertTrue(preview.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertTrue(summary.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertEqual(
            try String(contentsOf: fixture.workingCopy.appendingPathComponent("README.txt"), encoding: .utf8),
            "branch change\n"
        )
    }

    func testConflictServiceListsTextConflictAndResolveMineFull() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let otherWC = fixture.root.appendingPathComponent("wc-other", isDirectory: true)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)
        try "mine change\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "theirs change\n".write(
            to: otherWC.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await service.commit(
            wc: otherWC,
            paths: ["README.txt"],
            message: "theirs change",
            auth: nil
        )

        _ = try await service.update(wc: fixture.workingCopy)
        let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
        let conflicts = try await conflictService.conflicts(wc: fixture.workingCopy)

        XCTAssertEqual(conflicts.first?.path, "README.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.baseFile ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.mineFile ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.theirsFile ?? ""))

        try await conflictService.resolveWholeFile(conflicts[0], wc: fixture.workingCopy, accept: .mineFull)
        let statuses = try await service.status(wc: fixture.workingCopy)
        XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
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
