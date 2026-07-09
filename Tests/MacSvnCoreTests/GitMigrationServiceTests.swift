import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationServiceTests: XCTestCase {
    func testSnapshotMigrationExportsThenCreatesInitialGitCommitAndReturnsReport() async throws {
        let recorder = MigrationRecorder()
        let svn = FakeGitMigrationSvnExporter(recorder: recorder)
        let git = FakeGitMigrationGitBackend(recorder: recorder)
        let service = GitMigrationService(svnExporter: svn, gitBackend: git)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshot")
        let auth = Credential(username: "u", password: "p")

        let report = try await service.snapshotMigrate(
            sourceURL: "file:///repo/trunk",
            destination: destination,
            revision: Revision(12),
            commitMessage: "Initial SVN snapshot",
            auth: auth
        )
        let events = await recorder.recordedEvents()

        XCTAssertEqual(events, [
            .svnExport(url: "file:///repo/trunk", destination: destination, revision: Revision(12), auth: auth),
            .gitInit(repository: destination),
            .gitAdd(repository: destination),
            .gitCommit(repository: destination, message: "Initial SVN snapshot")
        ])
        XCTAssertEqual(report.mode, .snapshot)
        XCTAssertEqual(report.sourceURL, "file:///repo/trunk")
        XCTAssertEqual(report.destinationPath, destination.path)
        XCTAssertEqual(report.revision, Revision(12))
        XCTAssertEqual(report.commitMessage, "Initial SVN snapshot")
        XCTAssertEqual(report.completedSteps, [.svnExport, .gitInit, .gitAdd, .gitCommit])
    }

    func testSnapshotMigrationRejectsEmptySourceURLAndCommitMessageBeforeRunningCommands() async {
        let recorder = MigrationRecorder()
        let service = GitMigrationService(
            svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
            gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            _ = try await service.snapshotMigrate(
                sourceURL: "  ",
                destination: destination,
                commitMessage: "Initial SVN snapshot"
            )
            XCTFail("Expected emptySourceURL")
        } catch {
            XCTAssertEqual(error as? GitMigrationError, .emptySourceURL)
        }

        do {
            _ = try await service.snapshotMigrate(
                sourceURL: "file:///repo/trunk",
                destination: destination,
                commitMessage: "\n"
            )
            XCTFail("Expected emptyCommitMessage")
        } catch {
            XCTAssertEqual(error as? GitMigrationError, .emptyCommitMessage)
        }

        let events = await recorder.recordedEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testSnapshotMigrationRejectsExistingNonEmptyDestinationBeforeRunningCommands() async throws {
        let recorder = MigrationRecorder()
        let service = GitMigrationService(
            svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
            gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: destination.appendingPathComponent("existing.txt"))

        do {
            _ = try await service.snapshotMigrate(
                sourceURL: "file:///repo/trunk",
                destination: destination,
                commitMessage: "Initial SVN snapshot"
            )
            XCTFail("Expected destinationNotEmpty")
        } catch {
            XCTAssertEqual(error as? GitMigrationError, .destinationNotEmpty(path: destination.path))
        }

        let events = await recorder.recordedEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testHistoryMigrationWritesAuthorsFileThenRunsGitSvnCloneAndReturnsReport() async throws {
        let recorder = MigrationRecorder()
        let svn = FakeGitMigrationSvnExporter(recorder: recorder)
        let git = FakeGitMigrationGitBackend(recorder: recorder)
        let service = GitMigrationService(svnExporter: svn, gitBackend: git)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("history")
        let authorsFile = root.appendingPathComponent("history-authors.txt")
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )
        let mappings = [
            GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "杨超", gitEmail: "yangchao@example.com")
        ]
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let report = try await service.historyMigrate(
            sourceURL: "file:///repo",
            destination: destination,
            layout: layout,
            authorMappings: mappings,
            revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
            auth: Credential(username: "yangchao", password: "secret")
        )
        let events = await recorder.recordedEvents()

        XCTAssertEqual(events, [
            .gitSvnClone(
                sourceURL: "file:///repo",
                destination: destination,
                authorsFile: authorsFile,
                layout: layout,
                revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
                username: "yangchao"
            )
        ])
        XCTAssertEqual(
            try String(contentsOf: authorsFile, encoding: .utf8),
            "yangchao = 杨超 <yangchao@example.com>\n"
        )
        XCTAssertEqual(report.mode, .historyPreserving)
        XCTAssertEqual(report.sourceURL, "file:///repo")
        XCTAssertEqual(report.destinationPath, destination.path)
        XCTAssertEqual(report.completedSteps, [.authorsFile, .gitSvnClone])
        XCTAssertEqual(report.authorsFilePath, authorsFile.path)
        XCTAssertEqual(report.layout, layout)
        XCTAssertEqual(report.revisionRange, RevisionRange(start: Revision(1), end: Revision(42)))
    }

    func testHistoryMigrationRejectsIncompleteAuthorsBeforeClone() async throws {
        let recorder = MigrationRecorder()
        let service = GitMigrationService(
            svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
            gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )

        do {
            _ = try await service.historyMigrate(
                sourceURL: "file:///repo",
                destination: destination,
                layout: layout,
                authorMappings: [
                    GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "", gitEmail: "yangchao@example.com")
                ]
            )
            XCTFail("Expected incompleteAuthors")
        } catch {
            XCTAssertEqual(error as? GitMigrationAuthorMappingError, .incompleteAuthors(["yangchao"]))
        }

        let events = await recorder.recordedEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testHistoryMigrationRejectsExistingNonEmptyDestinationBeforeClone() async throws {
        let recorder = MigrationRecorder()
        let service = GitMigrationService(
            svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
            gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
        )
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "keep".write(to: destination.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: destination)
        }

        do {
            _ = try await service.historyMigrate(
                sourceURL: "file:///repo",
                destination: destination,
                layout: layout,
                authorMappings: [
                    GitMigrationAuthorMapping(
                        svnUsername: "yangchao",
                        gitName: "杨超",
                        gitEmail: "yangchao@example.com"
                    )
                ]
            )
            XCTFail("Expected destinationNotEmpty")
        } catch {
            XCTAssertEqual(error as? GitMigrationError, .destinationNotEmpty(path: destination.path))
        }

        let events = await recorder.recordedEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testReconcileHistoryMigrationReadsGitSvnRevisionsAndReturnsReport() async throws {
        let recorder = MigrationRecorder()
        let repository = URL(fileURLWithPath: "/tmp/history")
        let git = FakeGitMigrationGitBackend(
            recorder: recorder,
            gitSvnRevisions: [
                GitSvnRevisionMetadata(revision: Revision(1)),
                GitSvnRevisionMetadata(revision: Revision(3))
            ]
        )
        let service = GitMigrationService(
            svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
            gitBackend: git
        )

        let report = try await service.reconcileHistoryMigration(
            sourceRevisions: [Revision(1), Revision(2), Revision(3)],
            gitRepository: repository
        )

        XCTAssertEqual(report.missingRevisions, [Revision(2)])
        XCTAssertFalse(report.isConsistent)
        let events = await recorder.recordedEvents()
        XCTAssertEqual(events, [
            .gitSvnRevisions(repository: repository)
        ])
    }
}

private enum MigrationEvent: Equatable, Sendable {
    case svnExport(url: String, destination: URL, revision: Revision?, auth: Credential?)
    case gitInit(repository: URL)
    case gitAdd(repository: URL)
    case gitCommit(repository: URL, message: String)
    case gitSvnRevisions(repository: URL)
    case gitSvnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    )
}

private actor MigrationRecorder {
    private var events: [MigrationEvent] = []

    func append(_ event: MigrationEvent) {
        events.append(event)
    }

    func recordedEvents() -> [MigrationEvent] {
        events
    }
}

private struct FakeGitMigrationSvnExporter: GitMigrationSvnExporting {
    let recorder: MigrationRecorder

    func export(url: String, to destination: URL, revision: Revision?, auth: Credential?) async throws {
        await recorder.append(.svnExport(url: url, destination: destination, revision: revision, auth: auth))
    }
}

private struct FakeGitMigrationGitBackend: GitBackend {
    let recorder: MigrationRecorder
    var gitSvnRevisions: [GitSvnRevisionMetadata] = []

    func initRepository(at repository: URL) async throws {
        await recorder.append(.gitInit(repository: repository))
    }

    func addAll(repository: URL) async throws {
        await recorder.append(.gitAdd(repository: repository))
    }

    func commit(repository: URL, message: String) async throws {
        await recorder.append(.gitCommit(repository: repository, message: message))
    }

    func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata] {
        await recorder.append(.gitSvnRevisions(repository: repository))
        return gitSvnRevisions
    }

    func svnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    ) async throws {
        await recorder.append(.gitSvnClone(
            sourceURL: sourceURL,
            destination: destination,
            authorsFile: authorsFile,
            layout: layout,
            revisionRange: revisionRange,
            username: username
        ))
    }
}
