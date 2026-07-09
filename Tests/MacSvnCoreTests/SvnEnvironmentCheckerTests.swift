import Foundation
import XCTest
@testable import MacSvnCore

final class SvnEnvironmentCheckerTests: XCTestCase {
    private let candidatePaths = [
        "/opt/homebrew/bin/svn",
        "/usr/local/bin/svn",
        "/usr/bin/svn"
    ]

    func testManualPathExistsAndSupportedVersionReturnsAvailable() async {
        let factory = RecordingBackendFactory(versions: [
            "/custom/svn": SvnVersion(major: 1, minor: 14, patch: 5)
        ])
        let checker = makeChecker(
            executablePaths: ["/custom/svn"],
            factory: factory
        )

        let status = await checker.check(configuredPath: "/custom/svn")

        XCTAssertEqual(status, .available(path: "/custom/svn", version: SvnVersion(major: 1, minor: 14, patch: 5)))
        XCTAssertEqual(factory.requestedPaths, ["/custom/svn"])
    }

    func testMissingManualPathFallsBackToCandidatePaths() async {
        let factory = RecordingBackendFactory(versions: [
            "/usr/local/bin/svn": SvnVersion(major: 1, minor: 14, patch: 5)
        ])
        let checker = makeChecker(
            executablePaths: ["/usr/local/bin/svn"],
            factory: factory
        )

        let status = await checker.check(configuredPath: "/missing/svn")

        XCTAssertEqual(status, .available(path: "/usr/local/bin/svn", version: SvnVersion(major: 1, minor: 14, patch: 5)))
        XCTAssertEqual(factory.requestedPaths, ["/usr/local/bin/svn"])
    }

    func testExecutableVersionBelowMinimumReturnsUnsupportedVersion() async {
        let factory = RecordingBackendFactory(versions: [
            "/opt/homebrew/bin/svn": SvnVersion(major: 1, minor: 13, patch: 0),
            "/usr/local/bin/svn": SvnVersion(major: 1, minor: 14, patch: 5)
        ])
        let checker = makeChecker(
            executablePaths: ["/opt/homebrew/bin/svn", "/usr/local/bin/svn"],
            factory: factory
        )

        let status = await checker.check(configuredPath: nil)

        XCTAssertEqual(status, .unsupportedVersion(
            path: "/opt/homebrew/bin/svn",
            version: SvnVersion(major: 1, minor: 13, patch: 0),
            minimum: SvnVersion(major: 1, minor: 14, patch: 0)
        ))
        XCTAssertEqual(factory.requestedPaths, ["/opt/homebrew/bin/svn"])
    }

    func testAllPathsMissingReturnsCheckedPaths() async {
        let factory = RecordingBackendFactory(versions: [:])
        let checker = makeChecker(
            executablePaths: [],
            factory: factory
        )

        let status = await checker.check(configuredPath: "/missing/svn")

        XCTAssertEqual(status, .missing(checkedPaths: ["/missing/svn"] + candidatePaths))
        XCTAssertTrue(factory.requestedPaths.isEmpty)
    }

    private func makeChecker(
        executablePaths: Set<String>,
        factory: RecordingBackendFactory
    ) -> SvnEnvironmentChecker {
        SvnEnvironmentChecker(
            fileChecker: FakeFileChecker(executablePaths: executablePaths),
            backendFactory: factory,
            candidatePaths: candidatePaths
        )
    }
}

private struct FakeFileChecker: FileChecking {
    let executablePaths: Set<String>

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }
}

private final class RecordingBackendFactory: SvnBackendFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private let versions: [String: SvnVersion]

    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    init(versions: [String: SvnVersion]) {
        self.versions = versions
    }

    func makeBackend(svnExecutable: String) -> any SvnBackend {
        lock.lock()
        paths.append(svnExecutable)
        lock.unlock()

        return SvnCliBackend(
            svnExecutable: svnExecutable,
            runner: VersionProcessRunner(version: versions[svnExecutable] ?? SvnVersion(major: 0, minor: 0, patch: 0))
        )
    }
}

private struct VersionProcessRunner: ProcessRunning {
    let version: SvnVersion

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let output = "\(version.major).\(version.minor).\(version.patch)\n"
        return ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", duration: 0.01)
    }
}
