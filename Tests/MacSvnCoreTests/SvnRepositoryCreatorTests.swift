import Foundation
import XCTest
@testable import MacSvnCore

final class SvnRepositoryCreatorTests: XCTestCase {
    func testCreateRunsSvnadminWithFSFSAndDestination() async throws {
        let runner = RepositoryRecordingRunner(result: ProcessResult(
            exitCode: 0,
            stdout: Data(),
            stderr: "",
            duration: 0.01
        ))
        let creator = SvnRepositoryCreator(
            svnadminExecutable: "/usr/local/bin/svnadmin",
            runner: runner,
            timeout: 45
        )
        let destination = URL(fileURLWithPath: "/tmp/new-repository")

        try await creator.create(at: destination)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            RepositoryProcessCall(
                executable: "/usr/local/bin/svnadmin",
                arguments: ["create", "--fs-type", "fsfs", destination.path],
                currentDirectory: nil,
                timeout: 45
            )
        ])
    }

    func testCreateMapsSvnadminFailureAndRejectsFilesystemRoot() async throws {
        let runner = RepositoryRecordingRunner(result: ProcessResult(
            exitCode: 1,
            stdout: Data(),
            stderr: "svnadmin: E000017: File exists",
            duration: 0.01
        ))
        let creator = SvnRepositoryCreator(svnadminExecutable: "svnadmin", runner: runner)

        do {
            try await creator.create(at: URL(fileURLWithPath: "/tmp/existing"))
            XCTFail("Expected svnadmin failure")
        } catch {
            XCTAssertEqual(
                error as? SvnError,
                .other(code: 17, stderr: "svnadmin: E000017: File exists")
            )
        }

        do {
            try await creator.create(at: URL(fileURLWithPath: "/"))
            XCTFail("Expected root rejection")
        } catch {
            XCTAssertEqual(error as? SvnRepositoryCreationError, .unsafeDestination)
        }
    }
}

final class CreateRepositoryViewModelTests: XCTestCase {
    @MainActor
    func testCreateValidatesPathAndStoresCompletedDestination() async {
        let provider = FakeRepositoryCreator()
        let viewModel = CreateRepositoryViewModel(provider: provider)

        await viewModel.create(path: "  ")
        XCTAssertEqual(viewModel.state, .error("emptyRepositoryPath"))

        await viewModel.create(path: " /tmp/repository ")
        XCTAssertEqual(viewModel.state, .completed(URL(fileURLWithPath: "/tmp/repository")))
        let destinations = await provider.recordedDestinations()
        XCTAssertEqual(destinations, [URL(fileURLWithPath: "/tmp/repository")])
    }
}

private struct RepositoryProcessCall: Equatable, Sendable {
    let executable: String
    let arguments: [String]
    let currentDirectory: String?
    let timeout: TimeInterval
}

private actor RepositoryRecordingRunner: ProcessRunning {
    private let result: ProcessResult
    private var calls: [RepositoryProcessCall] = []

    init(result: ProcessResult) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(RepositoryProcessCall(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            timeout: timeout
        ))
        return result
    }

    func recordedCalls() -> [RepositoryProcessCall] {
        calls
    }
}

private actor FakeRepositoryCreator: RepositoryCreating {
    private var destinations: [URL] = []

    func create(at destination: URL) async throws {
        destinations.append(destination)
    }

    func recordedDestinations() -> [URL] {
        destinations
    }
}
