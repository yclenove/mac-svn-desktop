import Foundation
import XCTest
@testable import MacSvnCore

final class ExternalDiffServiceTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testOpenWorkingCopyDiffMaterializesBaseRevisionAndLaunchesConfiguredTool() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let temp = root.appendingPathComponent("external-diff", isDirectory: true)
        let localFile = wc.appendingPathComponent("README.txt")
        try FileManager.default.createDirectory(at: wc, withIntermediateDirectories: true)
        try "working\n".write(to: localFile, atomically: true, encoding: .utf8)
        let credential = Credential(username: "u", password: "p")
        let provider = FakeExternalDiffContentProvider(
            info: SvnInfo(
                path: "README.txt",
                url: "file:///repo/trunk/README.txt",
                repositoryRoot: "file:///repo",
                revision: Revision(7),
                kind: "file"
            ),
            catResults: [.success(Data("base\n".utf8))]
        )
        let runner = RecordingExternalDiffRunner()
        let service = ExternalDiffService(
            contentProvider: provider,
            runner: runner,
            temporaryDirectory: temp,
            sizeLimit: 123,
            timeout: 9
        )
        let tool = ExternalDiffToolConfiguration(
            name: "Kaleidoscope",
            executablePath: "/usr/local/bin/ksdiff",
            arguments: ["--wait", "{left}", "{right}"]
        )

        let result = try await service.open(
            wc: wc,
            target: "README.txt",
            tool: tool,
            r1: nil,
            r2: nil,
            auth: credential
        )
        let infoCalls = await provider.recordedInfoCalls()
        let catCalls = await provider.recordedCatCalls()

        XCTAssertEqual(infoCalls, [ExternalDiffInfoCall(wc: wc, target: "README.txt")])
        XCTAssertEqual(catCalls, [
            ExternalDiffCatCall(
                url: "file:///repo/trunk/README.txt",
                revision: Revision(7),
                sizeLimit: 123,
                auth: credential
            )
        ])
        XCTAssertEqual(try String(contentsOf: result.leftFile, encoding: .utf8), "base\n")
        XCTAssertEqual(result.rightFile, localFile)
        XCTAssertEqual(runner.calls.single?.executable, "/usr/local/bin/ksdiff")
        XCTAssertEqual(runner.calls.single?.arguments, ["--wait", result.leftFile.path, localFile.path])
        XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
        XCTAssertEqual(runner.calls.single?.timeout, 9)
    }

    func testOpenRevisionRangeMaterializesBothSidesAndUsesDefaultArguments() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let temp = root.appendingPathComponent("external-diff", isDirectory: true)
        try FileManager.default.createDirectory(at: wc, withIntermediateDirectories: true)
        let provider = FakeExternalDiffContentProvider(
            info: SvnInfo(
                path: "src/main.txt",
                url: "file:///repo/trunk/src/main.txt",
                repositoryRoot: "file:///repo",
                revision: Revision(9),
                kind: "file"
            ),
            catResults: [
                .success(Data("r3\n".utf8)),
                .success(Data("r5\n".utf8))
            ]
        )
        let runner = RecordingExternalDiffRunner()
        let service = ExternalDiffService(
            contentProvider: provider,
            runner: runner,
            temporaryDirectory: temp,
            sizeLimit: 5,
            timeout: 4
        )
        let tool = ExternalDiffToolConfiguration(
            name: "Plain",
            executablePath: "/usr/local/bin/diff-tool",
            arguments: []
        )

        let result = try await service.open(
            wc: wc,
            target: "src/main.txt",
            tool: tool,
            r1: Revision(3),
            r2: Revision(5),
            auth: nil
        )
        let catCalls = await provider.recordedCatCalls()

        XCTAssertEqual(catCalls.map(\.revision), [Revision(3), Revision(5)])
        XCTAssertEqual(try String(contentsOf: result.leftFile, encoding: .utf8), "r3\n")
        XCTAssertEqual(try String(contentsOf: result.rightFile, encoding: .utf8), "r5\n")
        XCTAssertEqual(runner.calls.single?.arguments, [result.leftFile.path, result.rightFile.path])
    }

    func testOpenRejectsNonZeroExternalToolExit() async throws {
        let root = try temporaryRoot()
        let wc = root.appendingPathComponent("wc", isDirectory: true)
        let localFile = wc.appendingPathComponent("README.txt")
        try FileManager.default.createDirectory(at: wc, withIntermediateDirectories: true)
        try "working\n".write(to: localFile, atomically: true, encoding: .utf8)
        let provider = FakeExternalDiffContentProvider(
            info: SvnInfo(
                path: "README.txt",
                url: "file:///repo/trunk/README.txt",
                repositoryRoot: "file:///repo",
                revision: Revision(7),
                kind: "file"
            ),
            catResults: [.success(Data("base\n".utf8))]
        )
        let service = ExternalDiffService(
            contentProvider: provider,
            runner: NonZeroExternalDiffRunner(),
            temporaryDirectory: root.appendingPathComponent("external-diff", isDirectory: true)
        )

        do {
            _ = try await service.open(
                wc: wc,
                target: "README.txt",
                tool: ExternalDiffToolConfiguration(name: "Diff", executablePath: "/usr/bin/false"),
                r1: nil,
                r2: nil
            )
            XCTFail("Expected external tool failure")
        } catch let error as ExternalToolLaunchError {
            XCTAssertEqual(error, .commandFailed(exitCode: 4, stderr: "tool failed"))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreExternalDiff-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct ExternalDiffInfoCall: Equatable, Sendable {
    let wc: URL
    let target: String
}

private struct ExternalDiffCatCall: Equatable, Sendable {
    let url: String
    let revision: Revision?
    let sizeLimit: Int
    let auth: Credential?
}

private actor FakeExternalDiffContentProvider: ExternalDiffContentProviding {
    private let info: SvnInfo
    private var catResults: [Result<Data, Error>]
    private var infoCalls: [ExternalDiffInfoCall] = []
    private var catCalls: [ExternalDiffCatCall] = []

    init(info: SvnInfo, catResults: [Result<Data, Error>]) {
        self.info = info
        self.catResults = catResults
    }

    func recordedInfoCalls() -> [ExternalDiffInfoCall] {
        infoCalls
    }

    func recordedCatCalls() -> [ExternalDiffCatCall] {
        catCalls
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        infoCalls.append(ExternalDiffInfoCall(wc: wc, target: target))
        return info
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        catCalls.append(ExternalDiffCatCall(url: url, revision: revision, sizeLimit: sizeLimit, auth: auth))
        return try catResults.removeFirst().get()
    }
}

private final class RecordingExternalDiffRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let stdin: Data?
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []

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
        return ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
    }
}

private struct NonZeroExternalDiffRunner: ProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        ProcessResult(exitCode: 4, stdout: Data(), stderr: "tool failed", duration: 0.01)
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
