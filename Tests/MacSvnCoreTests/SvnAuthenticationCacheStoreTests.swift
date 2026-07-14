import Foundation
import XCTest
@testable import MacSvnCore

final class SvnAuthenticationCacheStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testClearRemovesEveryAuthenticationRealmButPreservesAuthDirectory() async throws {
        let configurationDirectory = temporaryDirectory()
        let authDirectory = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        try write("simple credential", to: authDirectory.appendingPathComponent("simple/realm"))
        try write("server certificate", to: authDirectory.appendingPathComponent("svn.ssl.server/realm"))
        try write("username", to: authDirectory.appendingPathComponent(".hidden-realm"))
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            runner: RecordingAuthenticationCacheRunner()
        )

        let result = try await store.clearAll()

        XCTAssertEqual(result.authenticationDirectory, authDirectory)
        XCTAssertEqual(result.removedFileCacheItemCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: authDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: authDirectory.path), [])
    }

    func testClearMissingAuthenticationDirectoryIsSuccessfulWithoutCreatingIt() async throws {
        let configurationDirectory = temporaryDirectory()
        let authDirectory = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            runner: RecordingAuthenticationCacheRunner()
        )

        let result = try await store.clearAll()

        XCTAssertEqual(result.authenticationDirectory, authDirectory)
        XCTAssertEqual(result.removedFileCacheItemCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: authDirectory.path))
    }

    func testClearRejectsAuthenticationPathThatIsNotADirectory() async throws {
        let configurationDirectory = temporaryDirectory()
        let authPath = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        try write("not a directory", to: authPath)
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            runner: RecordingAuthenticationCacheRunner()
        )

        do {
            _ = try await store.clearAll()
            XCTFail("Expected non-directory authentication cache path to be rejected")
        } catch let error as SvnAuthenticationCacheError {
            XCTAssertEqual(error, .authenticationPathIsNotDirectory(authPath))
        }
    }

    func testClearUsesSvnAuthCommandForKeychainAndFileBackedCredentials() async throws {
        let configurationDirectory = temporaryDirectory()
        let authDirectory = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        try write("credential", to: authDirectory.appendingPathComponent("svn.simple/realm"))
        let runner = RecordingAuthenticationCacheRunner()
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            svnExecutable: "/usr/local/bin/svn",
            runner: runner
        )

        let result = try await store.clearAll()

        XCTAssertEqual(result.removedFileCacheItemCount, 1)
        let calls = await runner.recordedCalls()
        XCTAssertEqual(
            calls,
            [.init(
                executable: "/usr/local/bin/svn",
                arguments: ["--config-dir", configurationDirectory.path, "auth", "--remove", "*"],
                currentDirectory: nil
            )]
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: authDirectory.path), [])
    }

    func testClearTreatsNoMatchingCredentialsAsSuccessfulNoOp() async throws {
        let configurationDirectory = temporaryDirectory()
        let runner = RecordingAuthenticationCacheRunner(result: ProcessResult(
            exitCode: 1,
            stdout: Data(),
            stderr: "svn: E200009: Credentials cache contains no matching credentials",
            duration: 0.01
        ))
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            runner: runner
        )

        let result = try await store.clearAll()

        XCTAssertEqual(result.removedFileCacheItemCount, 0)
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 1)
    }

    func testClearPreservesFileCacheWhenSvnAuthCommandFails() async throws {
        let configurationDirectory = temporaryDirectory()
        let authDirectory = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        let realm = authDirectory.appendingPathComponent("svn.simple/realm")
        try write("credential", to: realm)
        let runner = RecordingAuthenticationCacheRunner(result: ProcessResult(
            exitCode: 1,
            stdout: Data(),
            stderr: "svn: E205000: Unknown subcommand: 'auth'",
            duration: 0.01
        ))
        let store = SvnAuthenticationCacheStore(
            configurationDirectory: configurationDirectory,
            runner: runner
        )

        do {
            _ = try await store.clearAll()
            XCTFail("Expected svn auth failure")
        } catch let error as SvnAuthenticationCacheError {
            XCTAssertEqual(error, .commandFailed(
                exitCode: 1,
                stderr: "svn: E205000: Unknown subcommand: 'auth'"
            ))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: realm.path))
    }

    private func temporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnAuthenticationCache-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }
}

private actor RecordingAuthenticationCacheRunner: ProcessRunning {
    struct Call: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let currentDirectory: String?
    }

    private var calls: [Call] = []
    private var result: ProcessResult

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
            currentDirectory: currentDirectory
        ))
        return result
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
