import Foundation
import XCTest
@testable import MacSvnCore

final class ExternalToolLaunchServiceTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testOpenMergeLaunchesTextConflictArtifactsUsingDefaultArguments() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let base = root.appendingPathComponent("base.swift")
        let mine = root.appendingPathComponent("mine.swift")
        let theirs = root.appendingPathComponent("theirs.swift")
        let result = wc.appendingPathComponent("Sources/App.swift")
        for file in [base, mine, theirs, result] {
            try write("content\n", to: file)
        }
        let conflict = ConflictInfo(
            path: "Sources/App.swift",
            kind: .text,
            baseFile: base.path,
            mineFile: mine.path,
            theirsFile: theirs.path,
            treeConflict: nil
        )
        let runner = RecordingExternalToolRunner()
        let service = ExternalToolLaunchService(runner: runner, timeout: 9)

        _ = try await service.openMerge(
            wc: wc,
            conflict: conflict,
            tool: tool(named: "Kaleidoscope", arguments: [])
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            .init(
                executable: "/Applications/Kaleidoscope.app/Contents/MacOS/tool",
                arguments: [base.path, mine.path, theirs.path, result.path],
                currentDirectory: wc.path,
                timeout: 9
            )
        ])
    }

    func testOpenBlameExpandsFilePlaceholderForWorkingCopyTarget() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let target = wc.appendingPathComponent("Sources/App.swift")
        try write("content\n", to: target)
        let runner = RecordingExternalToolRunner()
        let service = ExternalToolLaunchService(runner: runner)

        _ = try await service.openBlame(
            wc: wc,
            target: "Sources/App.swift",
            tool: tool(named: "Blame Tool", arguments: ["--blame", "{file}"])
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.first?.arguments, ["--blame", target.path])
    }

    func testOpenMergeRejectsMissingArtifactsWithoutStartingTool() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        try write("result\n", to: wc.appendingPathComponent("README.md"))
        let runner = RecordingExternalToolRunner()
        let service = ExternalToolLaunchService(runner: runner)
        let conflict = ConflictInfo(
            path: "README.md",
            kind: .text,
            baseFile: nil,
            mineFile: nil,
            theirsFile: nil,
            treeConflict: nil
        )

        do {
            _ = try await service.openMerge(wc: wc, conflict: conflict, tool: tool(named: "Merge", arguments: []))
            XCTFail("Expected merge artifacts error")
        } catch let error as ExternalToolLaunchError {
            XCTAssertEqual(error, .missingTextConflictArtifacts(path: "README.md"))
        }
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    func testOpenBlameRejectsTargetOutsideWorkingCopyWithoutStartingTool() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        try FileManager.default.createDirectory(at: wc, withIntermediateDirectories: true)
        try write("outside\n", to: root.appendingPathComponent("outside.swift"))
        let runner = RecordingExternalToolRunner()
        let service = ExternalToolLaunchService(runner: runner)

        do {
            _ = try await service.openBlame(
                wc: wc,
                target: "../outside.swift",
                tool: tool(named: "Blame Tool", arguments: ["{file}"])
            )
            XCTFail("Expected working copy boundary rejection")
        } catch let error as ExternalToolLaunchError {
            XCTAssertEqual(error, .targetOutsideWorkingCopy(path: "../outside.swift"))
        }
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    func testOpenBlamePropagatesNonZeroToolExit() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let target = wc.appendingPathComponent("Sources/App.swift")
        try write("content\n", to: target)
        let runner = RecordingExternalToolRunner(result: ProcessResult(
            exitCode: 6,
            stdout: Data(),
            stderr: "blame failed",
            duration: 0.01
        ))
        let service = ExternalToolLaunchService(runner: runner)

        do {
            _ = try await service.openBlame(
                wc: wc,
                target: "Sources/App.swift",
                tool: tool(named: "Blame Tool", arguments: ["{file}"])
            )
            XCTFail("Expected tool failure")
        } catch let error as ExternalToolLaunchError {
            XCTAssertEqual(error, .commandFailed(exitCode: 6, stderr: "blame failed"))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnExternalTool-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }

    private func tool(named name: String, arguments: [String]) -> ExternalDiffToolConfiguration {
        ExternalDiffToolConfiguration(
            name: name,
            executablePath: "/Applications/\(name).app/Contents/MacOS/tool",
            arguments: arguments
        )
    }
}

private actor RecordingExternalToolRunner: ProcessRunning {
    struct Call: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private var calls: [Call] = []
    private let result: ProcessResult

    init(result: ProcessResult = ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(.init(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            timeout: timeout
        ))
        return result
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
