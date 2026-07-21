import Foundation
import XCTest
@testable import MacSvnCore

final class ClientHookServiceTests: XCTestCase {
    func testPreCommitUsesTortoiseArgumentsAndUTF8TemporaryFiles() async throws {
        let runner = RecordingHookProcessRunner()
        let wc = URL(fileURLWithPath: "/tmp/project")
        let service = ClientHookService(
            configurations: [ClientHookConfiguration(
                type: .preCommit,
                workingCopyPath: "/tmp",
                executablePath: "/usr/local/bin/check-hook",
                arguments: ["--strict"]
            )],
            runner: runner
        )

        try await service.runPreCommit(
            wc: wc,
            paths: ["Sources/中文.swift", "README.md"],
            message: "修复提交",
            depth: .infinity
        )

        let calls = await runner.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.executable, "/usr/local/bin/check-hook")
        XCTAssertEqual(call.arguments[0], "--strict")
        XCTAssertEqual(call.arguments[2], "3")
        XCTAssertEqual(call.arguments[4], wc.path)
        XCTAssertEqual(call.pathFile, "/tmp/project/Sources/中文.swift\n/tmp/project/README.md\n")
        XCTAssertEqual(call.messageFile, "修复提交")
    }

    func testHookScopeUsesPathBoundaryAndOnlyNearestAncestor() async throws {
        let runner = RecordingHookProcessRunner()
        let service = ClientHookService(
            configurations: [
                ClientHookConfiguration(
                    type: .preCommit,
                    workingCopyPath: "/tmp/project",
                    executablePath: "/bin/echo"
                ),
                ClientHookConfiguration(
                    type: .preCommit,
                    workingCopyPath: "/tmp/project-other",
                    executablePath: "/bin/false"
                ),
                ClientHookConfiguration(
                    type: .preCommit,
                    workingCopyPath: "/tmp",
                    executablePath: "/bin/false"
                )
            ],
            runner: runner
        )

        try await service.runPreCommit(
            wc: URL(fileURLWithPath: "/tmp/project/subdir"),
            paths: [],
            message: "message",
            depth: .empty
        )

        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.executable), ["/bin/echo"])
    }

    func testNonZeroPreCommitExitThrowsReadableFailure() async {
        let runner = RecordingHookProcessRunner(result: ProcessResult(
            exitCode: 7,
            stdout: Data(),
            stderr: "lint failed\n",
            duration: 0.1
        ))
        let service = ClientHookService(
            configurations: [ClientHookConfiguration(
                type: .preCommit,
                workingCopyPath: "/tmp/project",
                executablePath: "/bin/false"
            )],
            runner: runner
        )

        do {
            try await service.runPreCommit(
                wc: URL(fileURLWithPath: "/tmp/project"),
                paths: ["a.txt"],
                message: "message",
                depth: .infinity
            )
            XCTFail("Expected hook failure")
        } catch let error as ClientHookError {
            XCTAssertEqual(error, .failed(type: .preCommit, exitCode: 7, message: "lint failed"))
        } catch {
            XCTFail("Expected ClientHookError, got \(error)")
        }
    }

    func testPostUpdatePassesRevisionErrorAndResultFiles() async throws {
        let runner = RecordingHookProcessRunner()
        let wc = URL(fileURLWithPath: "/tmp/project")
        let service = ClientHookService(
            configurations: [ClientHookConfiguration(
                type: .postUpdate,
                workingCopyPath: wc.path,
                executablePath: "/usr/local/bin/after-update"
            )],
            runner: runner
        )

        try await service.runPostUpdate(
            wc: wc,
            paths: ["Sources"],
            depth: .files,
            revision: Revision(42),
            errorMessage: "",
            touchedPaths: ["Sources/App.swift"]
        )

        let calls = await runner.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.arguments[1], "1")
        XCTAssertEqual(call.arguments[2], "42")
        XCTAssertEqual(call.arguments[4], wc.path)
        XCTAssertEqual(call.errorFile, "")
        XCTAssertEqual(call.resultFile, "/tmp/project/Sources/App.swift\n")
    }
}

private actor RecordingHookProcessRunner: ProcessRunning {
    struct Call: Sendable {
        let executable: String
        let arguments: [String]
        let pathFile: String
        let messageFile: String?
        let errorFile: String?
        let resultFile: String?
    }

    private var recordedCalls: [Call] = []
    private let result: ProcessResult

    init(result: ProcessResult = ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.1)) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let type: ClientHookType = arguments.count >= 6 ? .postUpdate : .preCommit
        let offset = arguments.first == "--strict" ? 1 : 0
        let pathFile = try String(contentsOfFile: arguments[offset], encoding: .utf8)
        let messageFile = type == .preCommit
            ? try String(contentsOfFile: arguments[offset + 2], encoding: .utf8)
            : nil
        let errorFile = type == .postUpdate
            ? try String(contentsOfFile: arguments[offset + 3], encoding: .utf8)
            : nil
        let resultFile = type == .postUpdate
            ? try String(contentsOfFile: arguments[offset + 5], encoding: .utf8)
            : nil
        recordedCalls.append(Call(
            executable: executable,
            arguments: arguments,
            pathFile: pathFile,
            messageFile: messageFile,
            errorFile: errorFile,
            resultFile: resultFile
        ))
        return result
    }

    func calls() -> [Call] { recordedCalls }
}
