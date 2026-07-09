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
}

private enum MigrationEvent: Equatable, Sendable {
    case svnExport(url: String, destination: URL, revision: Revision?, auth: Credential?)
    case gitInit(repository: URL)
    case gitAdd(repository: URL)
    case gitCommit(repository: URL, message: String)
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

    func initRepository(at repository: URL) async throws {
        await recorder.append(.gitInit(repository: repository))
    }

    func addAll(repository: URL) async throws {
        await recorder.append(.gitAdd(repository: repository))
    }

    func commit(repository: URL, message: String) async throws {
        await recorder.append(.gitCommit(repository: repository, message: message))
    }
}
