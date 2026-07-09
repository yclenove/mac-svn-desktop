import Foundation
import XCTest
@testable import MacSvnCore

final class SvnCliBackendWorkingCopyTests: XCTestCase {
    func testAddDeleteRevertAndCleanupRunInWorkingCopy() async throws {
        let runner = MultiResultProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
        ])
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        try await backend.add(wc: wc, paths: ["a.txt"])
        try await backend.delete(wc: wc, paths: ["old.txt"])
        try await backend.revert(wc: wc, paths: ["dir"], recursive: true)
        try await backend.cleanup(wc: wc)

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["add", "--non-interactive", "a.txt"],
            ["delete", "--non-interactive", "old.txt"],
            ["revert", "--non-interactive", "--recursive", "dir"],
            ["cleanup", "--non-interactive"]
        ])
        XCTAssertEqual(runner.calls.map(\.currentDirectory), Array(repeating: "/tmp/wc", count: 4))
    }

    func testDiffReturnsUtf8Text() async throws {
        let runner = MultiResultProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data("@@ -1 +1 @@\n-old\n+new\n".utf8), stderr: "", duration: 0.01)
        ])
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let diff = try await backend.diff(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            target: "a.txt",
            r1: Revision(1),
            r2: Revision(3)
        )

        XCTAssertEqual(diff, "@@ -1 +1 @@\n-old\n+new\n")
        XCTAssertEqual(runner.calls.first?.arguments, ["diff", "--non-interactive", "-r", "1:3", "a.txt"])
    }

    func testLogRunsXmlVerboseAndParsesEntries() async throws {
        let xml = """
        <log><logentry revision="5"><author>a</author><date>2026-07-09T02:10:00.000000Z</date><msg>msg</msg><paths><path action="M">/trunk/a.txt</path></paths></logentry></log>
        """
        let runner = MultiResultProcessRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01)
        ])
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let entries = try await backend.log(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            target: "trunk",
            from: Revision(20),
            batch: 100,
            verbose: true
        )

        XCTAssertEqual(entries.map(\.revision), [Revision(5)])
        XCTAssertEqual(entries.first?.changedPaths.first?.path, "/trunk/a.txt")
        XCTAssertEqual(runner.calls.first?.arguments, ["log", "--xml", "-v", "--non-interactive", "-r", "20:0", "-l", "100", "trunk"])
    }
}

private final class MultiResultProcessRunner: ProcessRunning, @unchecked Sendable {
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
        return results.removeFirst()
    }
}
