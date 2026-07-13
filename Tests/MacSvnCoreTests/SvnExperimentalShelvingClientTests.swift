import Foundation
import XCTest
@testable import MacSvnCore

final class SvnExperimentalShelvingClientTests: XCTestCase {
    func testParsesVerboseShelfListWithMessagesAndPathCounts() throws {
        let output = """
        demo                           version 2, 4 minutes ago, 3 paths changed
         second checkpoint
        release work                   version 1, 1 hour ago, 1 path changed
         first line
        """

        XCTAssertEqual(try SvnShelfListParser.parse(output), [
            SvnShelf(
                name: "demo",
                latestVersion: 2,
                pathCount: 3,
                ageSummary: "4 minutes ago",
                message: "second checkpoint"
            ),
            SvnShelf(
                name: "release work",
                latestVersion: 1,
                pathCount: 1,
                ageSummary: "1 hour ago",
                message: "first line"
            )
        ])
    }

    func testCapabilityAndListInjectSelectedExperimentalEnvironment() async throws {
        let listOutput = "demo                           version 1, 0 minutes ago, 1 path changed\n message\n"
        let runner = ShelvingRecordingRunner(results: [
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            ProcessResult(exitCode: 0, stdout: Data(listOutput.utf8), stderr: "", duration: 0.01)
        ])
        let client = SvnExperimentalShelvingClient(
            svnExecutable: "/custom/svn",
            runner: runner,
            timeout: 42,
            version: .v3
        )
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let availability = await client.availability(wc: wc)
        let shelves = try await client.list(wc: wc)
        XCTAssertEqual(availability, .available(.v3))
        XCTAssertEqual(shelves.map(\.name), ["demo"])
        XCTAssertEqual(runner.calls.map(\.executable), ["/usr/bin/env", "/usr/bin/env"])
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["SVN_EXPERIMENTAL_COMMANDS=shelf3", "/custom/svn", "help", "x-shelve"],
            ["SVN_EXPERIMENTAL_COMMANDS=shelf3", "/custom/svn", "x-shelf-list", "--verbose", "."]
        ])
        XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/wc", "/tmp/wc"])
        XCTAssertEqual(runner.calls.map(\.timeout), [42, 42])
    }

    func testOfficialOperationsRunSelectedVersionAndMapFailures() async throws {
        let runner = ShelvingRecordingRunner(results: Array(repeating:
            ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
            count: 5
        ) + [ProcessResult(exitCode: 1, stdout: Data(), stderr: "svn: E200007: no shelf", duration: 0.01)])
        let client = SvnExperimentalShelvingClient(
            svnExecutable: "/custom/svn",
            runner: runner,
            version: .v2
        )
        let wc = URL(fileURLWithPath: "/tmp/wc")

        try await client.shelve(wc: wc, name: "demo", paths: ["file.txt"], message: "msg", keepLocal: false)
        _ = try await client.diff(wc: wc, name: "demo", version: 2)
        _ = try await client.log(wc: wc, name: "demo")
        try await client.unshelve(wc: wc, name: "demo", version: 2, drop: false)
        try await client.drop(wc: wc, name: "demo")
        do {
            _ = try await client.list(wc: wc)
            XCTFail("Expected list failure")
        } catch {
            XCTAssertEqual(error as? SvnError, .other(code: 200007, stderr: "svn: E200007: no shelf"))
        }

        XCTAssertTrue(runner.calls.allSatisfy {
            $0.arguments.prefix(2) == ["SVN_EXPERIMENTAL_COMMANDS=shelf2", "/custom/svn"]
        })
    }
}

private final class ShelvingRecordingRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private var results: [ProcessResult]
    private(set) var calls: [Call] = []

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
            currentDirectory: currentDirectory,
            timeout: timeout
        ))
        return results.removeFirst()
    }
}
