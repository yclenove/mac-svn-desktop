import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationEnvironmentCheckerTests: XCTestCase {
    func testCheckRecordsGitAndGitSvnVersionOutputsWhenAvailable() async throws {
        let runner = RecordingEnvironmentProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data("git version 2.45.0\n".utf8), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data("git-svn version 2.45.0\n".utf8), stderr: "", duration: 0.01)
        ])
        let checker = GitMigrationEnvironmentChecker(
            gitExecutable: "/usr/bin/git",
            runner: runner,
            timeout: 9
        )

        let status = try await checker.check()

        XCTAssertEqual(status.git, GitMigrationToolStatus(
            isAvailable: true,
            versionOutput: "git version 2.45.0",
            errorSummary: nil
        ))
        XCTAssertEqual(status.gitSvn, GitMigrationToolStatus(
            isAvailable: true,
            versionOutput: "git-svn version 2.45.0",
            errorSummary: nil
        ))
        XCTAssertTrue(status.isReadyForHistoryMigration)
        XCTAssertEqual(runner.calls, [
            EnvironmentProcessCall(
                executable: "/usr/bin/git",
                arguments: ["--version"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 9
            ),
            EnvironmentProcessCall(
                executable: "/usr/bin/git",
                arguments: ["svn", "--version"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 9
            )
        ])
    }

    func testCheckMarksGitUnavailableWhenCommandExitsNonZero() async throws {
        let runner = RecordingEnvironmentProcessRunner(results: [
            ProcessResult(exitCode: 127, stdout: Data(), stderr: "git: command not found", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data("git-svn version 2.45.0\n".utf8), stderr: "", duration: 0.01)
        ])
        let checker = GitMigrationEnvironmentChecker(runner: runner)

        let status = try await checker.check()

        XCTAssertEqual(status.git, GitMigrationToolStatus(
            isAvailable: false,
            versionOutput: nil,
            errorSummary: "git: command not found"
        ))
        XCTAssertEqual(status.gitSvn.isAvailable, true)
        XCTAssertFalse(status.isReadyForHistoryMigration)
    }

    func testCheckMarksGitSvnUnavailableWhenCommandExitsNonZero() async throws {
        let runner = RecordingEnvironmentProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data("git version 2.45.0\n".utf8), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 1, stdout: Data(), stderr: "git: 'svn' is not a git command", duration: 0.01)
        ])
        let checker = GitMigrationEnvironmentChecker(runner: runner)

        let status = try await checker.check()

        XCTAssertEqual(status.git.isAvailable, true)
        XCTAssertEqual(status.gitSvn, GitMigrationToolStatus(
            isAvailable: false,
            versionOutput: nil,
            errorSummary: "git: 'svn' is not a git command"
        ))
        XCTAssertFalse(status.isReadyForHistoryMigration)
    }
}

private struct EnvironmentProcessCall: Equatable {
    let executable: String
    let arguments: [String]
    let stdin: Data?
    let currentDirectory: String?
    let timeout: TimeInterval
}

private final class RecordingEnvironmentProcessRunner: ProcessRunning, @unchecked Sendable {
    private(set) var calls: [EnvironmentProcessCall] = []
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
        calls.append(EnvironmentProcessCall(
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
