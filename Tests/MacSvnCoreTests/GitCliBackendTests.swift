import Foundation
import XCTest
@testable import MacSvnCore

final class GitCliBackendTests: XCTestCase {
    func testGitBackendRunsInitAddAndCommitInRepositoryDirectory() async throws {
        let runner = RecordingGitProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
        ])
        let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)
        let repository = URL(fileURLWithPath: "/tmp/export")

        try await backend.initRepository(at: repository)
        try await backend.addAll(repository: repository)
        try await backend.commit(repository: repository, message: "Initial SVN snapshot")

        XCTAssertEqual(runner.calls.map(\.executable), ["/usr/bin/git", "/usr/bin/git", "/usr/bin/git"])
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["init"],
            ["add", "."],
            ["commit", "-m", "Initial SVN snapshot"]
        ])
        XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/export", "/tmp/export", "/tmp/export"])
        XCTAssertEqual(runner.calls.map(\.stdin), [nil, nil, nil])
    }

    func testGitBackendMapsNonZeroExitToSvnErrorOther() async {
        let runner = RecordingGitProcessRunner(results: [
            ProcessResult(exitCode: 128, stdout: Data(), stderr: "fatal: not a git repository", duration: 0.01)
        ])
        let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)

        do {
            try await backend.initRepository(at: URL(fileURLWithPath: "/tmp/export"))
            XCTFail("Expected SvnError.other")
        } catch let error as SvnError {
            XCTAssertEqual(error, .other(code: 128, stderr: "fatal: not a git repository"))
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }
    }

    func testGitBackendRunsSvnCloneWithoutPasswordInArguments() async throws {
        let runner = RecordingGitProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
        ])
        let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )

        try await backend.svnClone(
            sourceURL: "file:///repo",
            destination: URL(fileURLWithPath: "/tmp/git-repo"),
            authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
            layout: layout,
            revisionRange: nil,
            username: "u"
        )

        XCTAssertEqual(runner.calls.map(\.executable), ["/usr/bin/git"])
        XCTAssertEqual(runner.calls.first?.arguments, [
            "svn", "clone",
            "--authors-file", "/tmp/authors.txt",
            "--stdlayout",
            "--username", "u",
            "file:///repo",
            "/tmp/git-repo"
        ])
        XCTAssertNil(runner.calls.first?.stdin)
        XCTAssertNil(runner.calls.first?.currentDirectory)
    }
}

private final class RecordingGitProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let stdin: Data?
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            stdin: stdin,
            currentDirectory: currentDirectory,
            timeout: timeout
        ))

        guard !results.isEmpty else {
            return ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0)
        }

        return results.removeFirst()
    }
}
