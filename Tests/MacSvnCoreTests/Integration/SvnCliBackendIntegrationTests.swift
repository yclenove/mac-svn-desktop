import Foundation
import XCTest
@testable import MacSvnCore

final class SvnCliBackendIntegrationTests: SvnIntegrationTestCase {
    func testExperimentalShelvingV2AndV3RoundTripThroughRealWorkingCopy() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let file = fixture.workingCopy.appendingPathComponent("README.txt")

        for version in SvnShelvingVersion.allCases {
            let marker = "shelved-\(version.rawValue)\n"
            try ("hello\n" + marker).write(to: file, atomically: true, encoding: .utf8)
            let client = SvnExperimentalShelvingClient(
                svnExecutable: fixture.svnExecutable,
                runner: ProcessRunner(),
                timeout: 30,
                version: version
            )
            let name = "roundtrip-\(version.rawValue)"

            let availability = await client.availability(wc: fixture.workingCopy)
            XCTAssertEqual(availability, .available(version))
            try await client.shelve(
                wc: fixture.workingCopy,
                name: name,
                paths: ["README.txt"],
                message: "real \(version.displayName)",
                keepLocal: false
            )
            XCTAssertEqual(try String(contentsOf: file), "hello\n")

            let shelves = try await client.list(wc: fixture.workingCopy)
            XCTAssertEqual(shelves.first(where: { $0.name == name })?.latestVersion, 1)
            let diff = try await client.diff(
                wc: fixture.workingCopy,
                name: name,
                version: 1
            )
            XCTAssertTrue(diff.contains(marker.trimmingCharacters(in: .newlines)))

            try await client.unshelve(
                wc: fixture.workingCopy,
                name: name,
                version: 1,
                drop: true
            )
            XCTAssertEqual(try String(contentsOf: file), "hello\n" + marker)
            let remaining = try await client.list(wc: fixture.workingCopy)
            XCTAssertFalse(remaining.contains { $0.name == name })
            try await fixture.backend.revert(wc: fixture.workingCopy, paths: ["README.txt"], recursive: false)
        }
    }

    func testDirectoryAndFileExternalsRoundTripAndMaterializeOnUpdate() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let value = SvnExternalsDocument(definitions: [
            SvnExternalDefinition(
                revision: Revision(1),
                url: "^/branches/feature-one",
                pegRevision: Revision(1),
                localPath: "external-feature"
            ),
            SvnExternalDefinition(
                revision: Revision(1),
                url: "^/trunk/README.txt",
                pegRevision: Revision(1),
                localPath: "external-readme.txt"
            )
        ]).render()

        try await service.setProperty(
            wc: fixture.workingCopy,
            target: ".",
            name: "svn:externals",
            value: value
        )
        let property = try await fixture.backend.propertyValue(
            wc: fixture.workingCopy,
            target: ".",
            name: "svn:externals"
        )
        let document = try SvnExternalsDocument(text: try XCTUnwrap(property?.value))
        XCTAssertEqual(document.definitions.map(\.localPath), [
            "external-feature", "external-readme.txt"
        ])

        _ = try await service.update(wc: fixture.workingCopy, paths: ["."], ignoreExternals: false)
        XCTAssertEqual(
            try String(contentsOf: fixture.workingCopy.appendingPathComponent("external-feature/README.txt")),
            "branch seed\n"
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.workingCopy.appendingPathComponent("external-readme.txt")),
            "hello\n"
        )
    }

    func testChangelistAssignmentAndRemovalRoundTripThroughStatusXML() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

        try await service.assignChangelist(
            wc: fixture.workingCopy,
            name: "release",
            paths: ["README.txt"]
        )
        var statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        XCTAssertEqual(
            statuses.first(where: { $0.path == "README.txt" })?.changelist,
            "release"
        )

        try await service.removeFromChangelists(
            wc: fixture.workingCopy,
            paths: ["README.txt"]
        )
        statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        XCTAssertNil(statuses.first(where: { $0.path == "README.txt" })?.changelist)
    }

    @MainActor
    func testRevisionGraphBuildsCopyEdgeAndLoadsNodeDiffFromRealRepository() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        _ = try await service.copy(
            source: fixture.trunkURL,
            destination: "\(fixture.repositoryURL)/branches/graph-copy",
            message: "create graph branch"
        )
        let viewModel = RevisionGraphViewModel(
            workingCopy: fixture.workingCopy,
            batchSize: 50,
            settings: RevisionGraphSettings(),
            provider: service
        )

        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.state, .loaded)
        let branchNode = try XCTUnwrap(
            viewModel.snapshot.nodes.first(where: { $0.path == "/branches/graph-copy" })
        )
        XCTAssertEqual(branchNode.sourcePath, "/trunk")
        XCTAssertTrue(viewModel.snapshot.edges.contains {
            $0.kind == .copy && $0.targetID == branchNode.id
        })

        await viewModel.loadDiff(for: branchNode.id)
        XCTAssertEqual(viewModel.diffState, .loaded)
        XCTAssertNotNil(viewModel.diffText)
    }

    @MainActor
    func testDiffWithURLComparesWorkingCopyAgainstBranchURLAtRevision() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let viewModel = DiffViewModel(
            workingCopy: fixture.workingCopy,
            diffProvider: service
        )

        await viewModel.loadWithURL(
            target: "README.txt",
            url: "\(fixture.repositoryURL)/branches/feature-one/README.txt",
            revisionText: "1"
        )

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(viewModel.diffText.contains("-branch seed"), viewModel.diffText)
        XCTAssertTrue(viewModel.diffText.contains("+hello"), viewModel.diffText)
        XCTAssertTrue(viewModel.diffText.contains("branches/feature-one/README.txt"), viewModel.diffText)
    }

    func testCreateAndApplyPatchRoundTripSelectedWorkingCopyChange() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let readme = fixture.workingCopy.appendingPathComponent("README.txt")
        try "hello\npatched\n".write(to: readme, atomically: true, encoding: .utf8)
        let patchFile = fixture.root.appendingPathComponent("changes.patch")

        try await service.createPatch(wc: fixture.workingCopy, paths: ["README.txt"], to: patchFile)
        try await fixture.backend.revert(wc: fixture.workingCopy, paths: ["README.txt"], recursive: false)
        XCTAssertEqual(try String(contentsOf: readme), "hello\n")

        try await service.applyPatch(wc: fixture.workingCopy, patchFile: patchFile)
        XCTAssertEqual(try String(contentsOf: readme), "hello\npatched\n")
        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        XCTAssertTrue(statuses.contains { $0.path == "README.txt" && $0.itemStatus == .modified })
    }

    func testImportProjectAndImportInPlaceProduceUsableRepositoryContent() async throws {
        let fixture = try makeFixture()
        let source = fixture.root.appendingPathComponent("new-project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "imported\n".write(to: source.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let revision = try await fixture.backend.importProject(
            path: source,
            url: "\(fixture.repositoryURL)/imported",
            message: "import project",
            auth: nil
        )
        XCTAssertGreaterThan(revision.value, 0)

        let inPlace = fixture.root.appendingPathComponent("in-place", isDirectory: true)
        try FileManager.default.createDirectory(at: inPlace, withIntermediateDirectories: true)
        try "in place\n".write(to: inPlace.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let service = SvnService(backend: fixture.backend)
        _ = try await service.importInPlace(
            path: inPlace,
            url: "\(fixture.repositoryURL)/in-place",
            message: "import in place",
            auth: nil
        )

        let statuses = try await fixture.backend.status(wc: inPlace)
        XCTAssertTrue(statuses.allSatisfy { $0.itemStatus == .normal })
        XCTAssertEqual(try String(contentsOf: inPlace.appendingPathComponent("README.txt")), "in place\n")
    }

    func testRelocateKeepsWorkingCopyUsable() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await fixture.backend.relocate(
            wc: fixture.workingCopy,
            from: fixture.repositoryURL,
            to: fixture.repositoryURL,
            auth: nil
        )
        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        XCTAssertTrue(statuses.allSatisfy { $0.itemStatus == .normal })
    }

    func testCheckoutThenStatusIsClean() async throws {
        let fixture = try makeFixture()

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)

        // status -v 会列出全部正常项；「干净」= 无本地变更/冲突
        XCTAssertFalse(statuses.isEmpty)
        XCTAssertTrue(statuses.allSatisfy { $0.itemStatus == .normal && !$0.isTreeConflict })
    }

    func testSnapshotGitMigrationExportsAndCommitsRepository() async throws {
        let fixture = try makeFixture()
        let gitExecutable = try requireGitExecutable()
        let destination = fixture.root.appendingPathComponent("git-snapshot", isDirectory: true)
        let svnService = SvnService(backend: fixture.backend)
        let gitBackend = ConfiguringGitBackend(
            gitExecutable: gitExecutable,
            runner: ProcessRunner(),
            timeout: 30
        )
        let migrationService = GitMigrationService(svnExporter: svnService, gitBackend: gitBackend)

        let report = try await migrationService.snapshotMigrate(
            sourceURL: fixture.trunkURL,
            destination: destination,
            commitMessage: "Initial SVN snapshot"
        )
        let logResult = try await ProcessRunner().run(
            executable: gitExecutable,
            arguments: ["log", "--oneline", "-1", "--pretty=%s"],
            stdin: nil,
            currentDirectory: destination.path,
            timeout: 30
        )

        XCTAssertEqual(report.completedSteps, [.svnExport, .gitInit, .gitAdd, .gitCommit])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
        XCTAssertEqual(logResult.exitCode, 0)
        XCTAssertEqual(
            String(data: logResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Initial SVN snapshot"
        )
    }

    func testHistoryGitSvnMigrationClonesFixtureRepositoryWithAuthorsMapping() async throws {
        let fixture = try makeFixture()
        let gitExecutable = try requireGitExecutable()
        try await requireGitSvn(gitExecutable: gitExecutable)
        let destination = fixture.root.appendingPathComponent("git-history", isDirectory: true)
        let service = GitMigrationService(
            svnExporter: SvnService(backend: fixture.backend),
            gitBackend: GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
        )
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )

        let report = try await service.historyMigrate(
            sourceURL: fixture.repositoryURL,
            destination: destination,
            layout: layout,
            authorMappings: [
                GitMigrationAuthorMapping(
                    svnUsername: NSUserName(),
                    gitName: "MacSVN Test",
                    gitEmail: "macsvn@example.invalid"
                )
            ]
        )
        let logResult = try await ProcessRunner().run(
            executable: gitExecutable,
            arguments: ["log", "--all", "-1", "--pretty=%an <%ae>"],
            stdin: nil,
            currentDirectory: destination.path,
            timeout: 30
        )

        XCTAssertEqual(report.completedSteps, [.authorsFile, .gitSvnClone])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
        XCTAssertEqual(logResult.exitCode, 0)
        XCTAssertEqual(
            String(data: logResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            "MacSVN Test <macsvn@example.invalid>"
        )
    }

    func testHistoryGitSvnMigrationProducesConsistentRevisionReconciliation() async throws {
        let fixture = try makeFixture()
        let gitExecutable = try requireGitExecutable()
        try await requireGitSvn(gitExecutable: gitExecutable)
        let destination = fixture.root.appendingPathComponent("git-history-reconcile", isDirectory: true)
        let svnService = SvnService(backend: fixture.backend)
        let migrationService = GitMigrationService(
            svnExporter: svnService,
            gitBackend: GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
        )
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )
        let sourceLogEntries = try await fixture.backend.remoteLogFromHead(
            url: fixture.repositoryURL,
            batch: 100,
            verbose: false,
            auth: nil
        )
        let sourceRevisions = sourceLogEntries.map(\.revision)

        _ = try await migrationService.historyMigrate(
            sourceURL: fixture.repositoryURL,
            destination: destination,
            layout: layout,
            authorMappings: [
                GitMigrationAuthorMapping(
                    svnUsername: NSUserName(),
                    gitName: "MacSVN Test",
                    gitEmail: "macsvn@example.invalid"
                )
            ]
        )
        let report = try await migrationService.reconcileHistoryMigration(
            sourceRevisions: sourceRevisions,
            gitRepository: destination
        )

        XCTAssertTrue(report.isConsistent)
        XCTAssertEqual(report.sourceRevisionCount, Set(sourceRevisions).count)
        XCTAssertEqual(report.missingRevisions, [])
        XCTAssertEqual(report.unexpectedRevisions, [])
    }

    func testIncrementalGitSvnSyncFetchesNewSvnRevision() async throws {
        let fixture = try makeFixture()
        let gitExecutable = try requireGitExecutable()
        try await requireGitSvn(gitExecutable: gitExecutable)
        let destination = fixture.root.appendingPathComponent("git-history-sync", isDirectory: true)
        let svnService = SvnService(backend: fixture.backend)
        let gitBackend = GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
        let migrationService = GitMigrationService(svnExporter: svnService, gitBackend: gitBackend)
        let syncStore = GitMigrationSyncStore(fileURL: fixture.root.appendingPathComponent("migrations.json"))
        let syncService = GitMigrationSyncService(store: syncStore, gitBackend: gitBackend)
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )

        _ = try await migrationService.historyMigrate(
            sourceURL: fixture.repositoryURL,
            destination: destination,
            layout: layout,
            authorMappings: [
                GitMigrationAuthorMapping(
                    svnUsername: NSUserName(),
                    gitName: "MacSVN Test",
                    gitEmail: "macsvn@example.invalid"
                )
            ]
        )
        let newRevision = try await svnService.mkdir(
            url: "\(fixture.trunkURL)/post-migration",
            message: "add post migration directory",
            auth: nil
        )
        let record = try await syncService.registerMigration(
            sourceURL: fixture.repositoryURL,
            repository: destination,
            targetRemote: nil
        )

        let report = try await syncService.sync(record: record)

        XCTAssertEqual(report.latestRevision, newRevision)
        XCTAssertEqual(report.updatedRecord.lastSyncedRevision, newRevision)
        XCTAssertTrue(report.completedSteps.contains(.gitSvnFetch))
    }

    func testBlameReadsLineRevisionAuthorFromWorkingCopy() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let lines = try await service.blame(wc: fixture.workingCopy, target: "README.txt")

        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(lines.first?.lineNumber, 1)
        XCTAssertNotNil(lines.first?.revision)
        XCTAssertNotNil(lines.first?.author)
    }

    @MainActor
    func testBlameHoverLoadsExactRevisionLogFromWorkingCopy() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let viewModel = BlameViewModel(
            workingCopy: fixture.workingCopy,
            target: "README.txt",
            provider: service,
            logProvider: service,
            rangeProvider: service
        )

        await viewModel.load(startRevision: Revision(1), endRevision: Revision(1))
        let line = try XCTUnwrap(viewModel.lines.first)
        await viewModel.loadRevisionDetails(for: line.lineNumber)

        XCTAssertEqual(viewModel.hoveredLineNumber, line.lineNumber)
        XCTAssertEqual(viewModel.hoveredLog?.revision, line.revision)
        XCTAssertEqual(viewModel.hoveredLog?.message, "initial import")
    }

    func testPropertiesSetListGetDeleteOnWorkingCopyFile() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await service.setProperty(
            wc: fixture.workingCopy,
            target: "README.txt",
            name: "custom:reviewer",
            value: "杨超"
        )

        let listed = try await service.properties(wc: fixture.workingCopy, target: "README.txt")
        let value = try await service.propertyValue(
            wc: fixture.workingCopy,
            target: "README.txt",
            name: "custom:reviewer"
        )

        XCTAssertTrue(listed.contains(SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")))
        XCTAssertEqual(value?.name, "custom:reviewer")
        XCTAssertEqual(value?.value, "杨超")

        try await service.deleteProperty(
            wc: fixture.workingCopy,
            target: "README.txt",
            name: "custom:reviewer"
        )
        let afterDelete = try await service.properties(wc: fixture.workingCopy, target: "README.txt")

        XCTAssertFalse(afterDelete.contains { $0.name == "custom:reviewer" })
    }

    func testLocksListLockUnlockAndDetectRepositoryLockFromAnotherWorkingCopy() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let otherWC = fixture.root.appendingPathComponent("wc-lock-other", isDirectory: true)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)

        try await service.lock(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: "锁定：编辑中",
            force: false
        )
        let mineLocks = try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"])

        XCTAssertEqual(mineLocks.first?.target, "README.txt")
        XCTAssertEqual(mineLocks.first?.owner, NSUserName())
        XCTAssertEqual(mineLocks.first?.comment, "锁定：编辑中")
        XCTAssertTrue(mineLocks.first?.isOwnedByWorkingCopy ?? false)
        XCTAssertTrue(mineLocks.first?.isRepositoryLocked ?? false)

        try await service.unlock(wc: fixture.workingCopy, paths: ["README.txt"], force: false)
        let afterUnlock = try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"])
        XCTAssertEqual(afterUnlock, [])

        try await service.lock(wc: otherWC, paths: ["README.txt"], message: "other", force: false)
        let otherLocks = try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"])

        XCTAssertFalse(otherLocks.first?.isOwnedByWorkingCopy ?? true)
        XCTAssertTrue(otherLocks.first?.isRepositoryLocked ?? false)
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

        // empty depth 仍有 WC 根；status -v 返回根节点为 normal
        XCTAssertTrue(statuses.allSatisfy { $0.itemStatus == .normal && !$0.isTreeConflict })
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

    func testListWithLocksReturnsRemoteLockOwnerAndComment() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await service.lock(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: "Repo Browser lock",
            force: false
        )

        let entries = try await service.listWithLocks(
            url: fixture.trunkURL,
            depth: .immediates,
            auth: nil
        )
        let locked = try XCTUnwrap(entries.first { $0.name == "README.txt" })

        XCTAssertEqual(locked.lock?.owner, NSUserName())
        XCTAssertEqual(locked.lock?.comment, "Repo Browser lock")
        XCTAssertNotNil(locked.lock?.created)
        XCTAssertNil(entries.first { $0.name == "src" }?.lock)
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

    func testRemoteLogFromHeadReadsLatestHistory() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let mkdirRevision = try await service.mkdir(
            url: "\(fixture.trunkURL)/latest-history",
            message: "add latest history directory",
            auth: nil
        )

        let entries = try await fixture.backend.remoteLogFromHead(
            url: fixture.repositoryURL,
            batch: 10,
            verbose: true,
            auth: nil
        )

        XCTAssertEqual(entries.first?.revision, mkdirRevision)
        XCTAssertFalse(entries.first?.changedPaths.isEmpty ?? true)
        XCTAssertTrue(entries.contains { $0.revision == Revision(1) })
    }

    func testGitMigrationSourceAnalyzerReadsFixtureRepository() async throws {
        let fixture = try makeFixture()
        let gitExecutable = try requireGitExecutable()
        let service = SvnService(backend: fixture.backend)
        let analyzer = GitMigrationSourceAnalyzer(
            environmentChecker: GitMigrationEnvironmentChecker(
                gitExecutable: gitExecutable,
                runner: ProcessRunner(),
                timeout: 30
            ),
            listProvider: service,
            logProvider: service
        )

        let analysis = try await analyzer.analyze(repositoryRoot: fixture.repositoryURL, auth: nil)

        XCTAssertEqual(analysis.repositoryRoot, fixture.repositoryURL)
        XCTAssertEqual(analysis.layout.kind, .standard)
        XCTAssertEqual(analysis.layout.trunkPath, "trunk")
        XCTAssertEqual(analysis.layout.branchesPath, "branches")
        XCTAssertEqual(analysis.layout.tagsPath, "tags")
        XCTAssertEqual(analysis.layout.confidence, 1.0)
        XCTAssertTrue(analysis.authors.map(\.svnUsername).contains(NSUserName()))
        XCTAssertGreaterThanOrEqual(analysis.totalRevisionCount, 1)
        XCTAssertGreaterThanOrEqual(analysis.latestRevision?.value ?? 0, analysis.oldestRevision?.value ?? 0)
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

    func testServiceRemoteRepositoryWritesCreateCopyMoveAndDeleteUrls() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let docsURL = "\(fixture.trunkURL)/docs"
        let copiedURL = "\(docsURL)/copied.txt"
        let movedURL = "\(docsURL)/moved.txt"

        let mkdirRevision = try await service.mkdir(
            url: docsURL,
            message: "创建远端目录 docs",
            auth: nil
        )
        let trunkAfterMkdir = try await service.list(url: fixture.trunkURL, depth: .immediates, auth: nil)

        let copyRevision = try await service.copy(
            source: "\(fixture.trunkURL)/README.txt",
            destination: copiedURL,
            message: "复制 README 到 docs",
            auth: nil
        )
        let docsAfterCopy = try await service.list(url: docsURL, depth: .immediates, auth: nil)

        let moveRevision = try await service.move(
            source: copiedURL,
            destination: movedURL,
            message: "移动 docs 文件",
            auth: nil
        )
        let docsAfterMove = try await service.list(url: docsURL, depth: .immediates, auth: nil)

        let deleteFileRevision = try await service.delete(
            url: movedURL,
            message: "删除 docs 文件",
            auth: nil
        )
        let docsAfterFileDelete = try await service.list(url: docsURL, depth: .immediates, auth: nil)

        let deleteDirectoryRevision = try await service.delete(
            url: docsURL,
            message: "删除 docs 目录",
            auth: nil
        )
        let trunkAfterDelete = try await service.list(url: fixture.trunkURL, depth: .immediates, auth: nil)

        XCTAssertGreaterThan(mkdirRevision.value, 1)
        XCTAssertGreaterThan(copyRevision.value, mkdirRevision.value)
        XCTAssertGreaterThan(moveRevision.value, copyRevision.value)
        XCTAssertGreaterThan(deleteFileRevision.value, moveRevision.value)
        XCTAssertGreaterThan(deleteDirectoryRevision.value, deleteFileRevision.value)
        XCTAssertTrue(trunkAfterMkdir.map(\.name).contains("docs"))
        XCTAssertTrue(docsAfterCopy.map(\.name).contains("copied.txt"))
        XCTAssertFalse(docsAfterMove.map(\.name).contains("copied.txt"))
        XCTAssertTrue(docsAfterMove.map(\.name).contains("moved.txt"))
        XCTAssertFalse(docsAfterFileDelete.map(\.name).contains("moved.txt"))
        XCTAssertFalse(trunkAfterDelete.map(\.name).contains("docs"))
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

    func testServiceTwoTreeMergePreviewAndExecutionIntoWorkingCopy() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let branchURL = "\(fixture.repositoryURL)/branches/two-tree-source"

        _ = try await service.copy(
            source: fixture.trunkURL,
            destination: branchURL,
            message: "create two-tree branch",
            auth: nil
        )
        try await fixture.backend.checkout(url: branchURL, to: fixture.workingCopy)
        try "two-tree change\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        let branchChangeRevision = try await service.commit(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: "two-tree change",
            auth: nil
        )
        _ = try await service.switchTo(wc: fixture.workingCopy, url: fixture.trunkURL, auth: nil)

        let rangeDiff = try await service.diff(
            wc: fixture.workingCopy,
            target: branchURL,
            r1: Revision(max(0, branchChangeRevision.value - 1)),
            r2: branchChangeRevision
        )
        let twoTreeDiff = try await service.diffBetweenPaths(
            wc: fixture.workingCopy,
            oldPath: fixture.trunkURL,
            newPath: branchURL
        )

        let preview = try await service.mergeTwoTrees(
            wc: fixture.workingCopy,
            from: fixture.trunkURL,
            to: branchURL,
            dryRun: true,
            auth: nil
        )
        let summary = try await service.mergeTwoTrees(
            wc: fixture.workingCopy,
            from: fixture.trunkURL,
            to: branchURL,
            dryRun: false,
            auth: nil
        )

        XCTAssertTrue(preview.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertTrue(summary.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertTrue(rangeDiff.contains("two-tree change"))
        XCTAssertTrue(twoTreeDiff.contains("two-tree change"))
        XCTAssertEqual(
            try String(contentsOf: fixture.workingCopy.appendingPathComponent("README.txt"), encoding: .utf8),
            "two-tree change\n"
        )
    }

    func testReintegrateAndMergeRevisionToUseModernCompleteAndSingleRevisionMerges() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let branchURL = "\(fixture.repositoryURL)/branches/reintegrate-source"

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        _ = try await service.copy(
            source: fixture.trunkURL,
            destination: branchURL,
            message: "create reintegrate branch",
            auth: nil
        )
        let branchWC = fixture.root.appendingPathComponent("reintegrate-wc", isDirectory: true)
        try await fixture.backend.checkout(url: branchURL, to: branchWC)
        try "branch change\n".write(
            to: branchWC.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        let branchRevision = try await service.commit(
            wc: branchWC,
            paths: ["README.txt"],
            message: "branch change",
            auth: nil
        )

        let revisionPreview = try await service.mergeRevisionTo(
            wc: fixture.workingCopy,
            source: branchURL,
            revision: branchRevision,
            dryRun: true,
            auth: nil
        )
        let revisionMerged = try await service.mergeRevisionTo(
            wc: fixture.workingCopy,
            source: branchURL,
            revision: branchRevision,
            dryRun: false,
            auth: nil
        )
        XCTAssertTrue(revisionPreview.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertTrue(revisionMerged.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertEqual(
            try String(contentsOf: fixture.workingCopy.appendingPathComponent("README.txt"), encoding: .utf8),
            "branch change\n"
        )

        let reintegrateWC = fixture.root.appendingPathComponent("trunk-reintegrate-wc", isDirectory: true)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: reintegrateWC)
        let preview = try await service.mergeReintegrate(
            wc: reintegrateWC,
            source: branchURL,
            dryRun: true,
            auth: nil
        )
        let merged = try await service.mergeReintegrate(
            wc: reintegrateWC,
            source: branchURL,
            dryRun: false,
            auth: nil
        )
        XCTAssertTrue(preview.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertTrue(merged.affectedPaths.map(\.path).contains("README.txt"))
        XCTAssertEqual(
            try String(contentsOf: reintegrateWC.appendingPathComponent("README.txt"), encoding: .utf8),
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

    func testMergeEngineResolvesTextConflictAndCommitSucceeds() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
        let otherWC = fixture.root.appendingPathComponent("wc-other-merge-engine", isDirectory: true)

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

        let conflicts = try await conflictService.conflicts(wc: fixture.workingCopy)
        let conflict = try XCTUnwrap(conflicts.first)
        let text = try await conflictService.loadTextConflict(conflict)
        let blocks = MergeEngine.merge3(
            base: lines(text.base),
            mine: lines(text.mine),
            theirs: lines(text.theirs)
        )
        let resolvedBlocks = blocks.map { block -> MergeBlock in
            guard case .conflict(let hunk) = block else {
                return block
            }

            return .conflict(ConflictHunk(
                baseLines: hunk.baseLines,
                mineLines: hunk.mineLines,
                theirsLines: hunk.theirsLines,
                resolution: .takeBoth(mineFirst: true)
            ))
        }
        let merged = try XCTUnwrap(MergeEngine.mergedLines(from: resolvedBlocks))

        try await conflictService.saveResolution(
            conflict,
            wc: fixture.workingCopy,
            mergedText: merged.joined(separator: "\n") + "\n"
        )
        let statuses = try await service.status(wc: fixture.workingCopy)
        XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
        let revision = try await service.commit(
            wc: fixture.workingCopy,
            paths: ["README.txt"],
            message: "resolve conflict with merge engine",
            auth: nil
        )

        XCTAssertGreaterThan(revision.value, 1)
    }

    func testTreeConflictKeepLocalResolvesAndKeepsWorkingFile() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
        let conflict = try await makeLocalEditRemoteDeleteTreeConflict(fixture: fixture, service: service)

        try await conflictService.resolveTreeConflict(
            conflict,
            wc: fixture.workingCopy,
            resolution: .keepLocal
        )

        let statuses = try await service.status(wc: fixture.workingCopy)
        XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
    }

    func testTreeConflictAcceptRemoteResolvesAndRemovesWorkingFile() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
        let conflict = try await makeLocalEditRemoteDeleteTreeConflict(fixture: fixture, service: service)

        try await conflictService.resolveTreeConflict(
            conflict,
            wc: fixture.workingCopy,
            resolution: .acceptRemote
        )

        let statuses = try await service.status(wc: fixture.workingCopy)
        XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
    }

    func testShelveRevertsWorkingCopyAndRestoreAppliesPatch() async throws {
        let fixture = try makeFixture()
        let service = SvnService(backend: fixture.backend)
        let store = ShelveStore(rootDirectory: fixture.root.appendingPathComponent("shelves", isDirectory: true))
        let shelve = ShelveService(store: store, svn: service)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        let readme = fixture.workingCopy.appendingPathComponent("README.txt")
        try "changed through shelve\n".write(to: readme, atomically: true, encoding: .utf8)

        let snapshot = try await shelve.shelve(
            wc: fixture.workingCopy,
            name: "readme change",
            paths: ["README.txt"]
        )
        let revertedText = try String(contentsOf: readme, encoding: .utf8)
        XCTAssertFalse(revertedText.contains("changed through shelve"))

        try await shelve.restore(snapshot, deleteAfterRestore: false)

        let restoredText = try String(contentsOf: readme, encoding: .utf8)
        XCTAssertTrue(restoredText.contains("changed through shelve"))
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

    func testRepairMoveAfterExternalRenameSchedulesHistoryPreservingMove() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

        let oldURL = fixture.workingCopy.appendingPathComponent("README.txt")
        let newURL = fixture.workingCopy.appendingPathComponent("README-renamed.txt")
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let before = try await fixture.backend.status(wc: fixture.workingCopy)
        let beforeByPath = Dictionary(uniqueKeysWithValues: before.map { ($0.path, $0.itemStatus) })
        XCTAssertEqual(beforeByPath["README.txt"], .missing)
        XCTAssertEqual(beforeByPath["README-renamed.txt"], .unversioned)

        try await fixture.backend.moveInWorkingCopy(
            wc: fixture.workingCopy,
            source: "README.txt",
            destination: "README-renamed.txt"
        )

        let after = try await fixture.backend.status(wc: fixture.workingCopy)
        let afterByPath = Dictionary(uniqueKeysWithValues: after.map { ($0.path, $0.itemStatus) })
        // svn move 后源路径通常为 deleted（调度删除），目标为 added（带 copy-from 历史）
        XCTAssertTrue(
            afterByPath["README.txt"] == nil || afterByPath["README.txt"] == .deleted,
            "source should be gone or deleted, got \(String(describing: afterByPath["README.txt"]))"
        )
        XCTAssertEqual(afterByPath["README-renamed.txt"], .added)
    }

    func testRepairCopyAfterExternalCopySchedulesHistoryPreservingCopy() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

        let sourceURL = fixture.workingCopy.appendingPathComponent("README.txt")
        let copyURL = fixture.workingCopy.appendingPathComponent("README-copy.txt")
        try FileManager.default.copyItem(at: sourceURL, to: copyURL)

        let before = try await fixture.backend.status(wc: fixture.workingCopy)
        let beforeByPath = Dictionary(uniqueKeysWithValues: before.map { ($0.path, $0.itemStatus) })
        XCTAssertEqual(beforeByPath["README-copy.txt"], .unversioned)

        try await fixture.backend.copyInWorkingCopy(
            wc: fixture.workingCopy,
            source: "README.txt",
            destination: "README-copy.txt"
        )

        let after = try await fixture.backend.status(wc: fixture.workingCopy)
        let afterByPath = Dictionary(uniqueKeysWithValues: after.map { ($0.path, $0.itemStatus) })
        XCTAssertEqual(afterByPath["README-copy.txt"], .added)
    }

    func testFilenameCaseConflictRepairSchedulesCaseOnlyRenameAndCommits() async throws {
        let fixture = try makeFixture()
        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

        try await fixture.backend.repairFilenameCaseConflict(
            wc: fixture.workingCopy,
            source: "README.txt",
            destination: "readme.txt"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("readme.txt").path))

        let statuses = try await fixture.backend.status(wc: fixture.workingCopy)
        let statusByPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0.itemStatus) })
        XCTAssertEqual(statusByPath["readme.txt"], .added)
        XCTAssertTrue(statusByPath["README.txt"] == nil || statusByPath["README.txt"] == .deleted)

        _ = try await fixture.backend.commit(
            wc: fixture.workingCopy,
            paths: ["README.txt", "readme.txt"],
            message: "修复文件名大小写",
            auth: nil
        )
        let entries = try await fixture.backend.list(url: fixture.trunkURL, depth: .immediates, auth: nil)
        XCTAssertTrue(entries.contains { $0.name == "readme.txt" })
        XCTAssertFalse(entries.contains { $0.name == "README.txt" })
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

    private func lines(_ text: String) -> [Substring] {
        let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return text.hasSuffix("\n") ? Array(splitLines.dropLast()) : splitLines
    }

    private func requireGitExecutable() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]

        guard let git = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("git executable is not available.")
        }

        return git
    }

    private func requireGitSvn(gitExecutable: String) async throws {
        let result = try await ProcessRunner().run(
            executable: gitExecutable,
            arguments: ["svn", "--version"],
            stdin: nil,
            currentDirectory: nil,
            timeout: 30
        )

        guard result.exitCode == 0 else {
            throw XCTSkip("git svn is not available.")
        }
    }

    private func makeLocalEditRemoteDeleteTreeConflict(
        fixture: SvnIntegrationFixture,
        service: SvnService
    ) async throws -> ConflictInfo {
        let otherWC = fixture.root.appendingPathComponent("wc-tree-other-\(UUID().uuidString)", isDirectory: true)

        try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
        try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)
        try "local edit before remote delete\n".write(
            to: fixture.workingCopy.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await fixture.backend.delete(wc: otherWC, paths: ["README.txt"])
        _ = try await service.commit(
            wc: otherWC,
            paths: ["README.txt"],
            message: "delete readme remotely",
            auth: nil
        )
        _ = try await service.update(wc: fixture.workingCopy)

        let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
        let conflicts = try await conflictService.conflicts(wc: fixture.workingCopy)
        return try XCTUnwrap(conflicts.first { $0.kind == .tree && $0.path == "README.txt" })
    }
}

private struct ConfiguringGitBackend: GitBackend {
    let gitExecutable: String
    let runner: any ProcessRunning
    let timeout: TimeInterval

    func initRepository(at repository: URL) async throws {
        try await base.initRepository(at: repository)
        try await runGit(["config", "user.name", "MacSVN Test"], repository: repository)
        try await runGit(["config", "user.email", "macsvn@example.invalid"], repository: repository)
    }

    func addAll(repository: URL) async throws {
        try await base.addAll(repository: repository)
    }

    func commit(repository: URL, message: String) async throws {
        try await base.commit(repository: repository, message: message)
    }

    private var base: GitCliBackend {
        GitCliBackend(gitExecutable: gitExecutable, runner: runner, timeout: timeout)
    }

    private func runGit(_ arguments: [String], repository: URL) async throws {
        let result = try await runner.run(
            executable: gitExecutable,
            arguments: arguments,
            stdin: nil,
            currentDirectory: repository.path,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw SvnError.other(code: Int(result.exitCode), stderr: result.stderr)
        }
    }
}
