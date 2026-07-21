import Foundation
import XCTest
@testable import MacSvnCore

final class DiffWithURLValidationPolicyTests: XCTestCase {
    func testValidatesURLAndUsesExplicitRevisionAsPegRevision() throws {
        let request = try DiffWithURLValidationPolicy.validate(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            url: "https://svn.example.com/repo/trunk/README.txt",
            revisionText: "42"
        )

        XCTAssertEqual(request.target, "README.txt")
        XCTAssertEqual(request.url, "https://svn.example.com/repo/trunk/README.txt@42")
        XCTAssertEqual(request.revision, Revision(42))
    }

    func testDerivesPegRevisionFromURLWithoutBreakingUserAtHost() throws {
        let request = try DiffWithURLValidationPolicy.validate(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            url: "svn+ssh://alice@svn.example.com/repo/trunk/README.txt@17",
            revisionText: ""
        )

        XCTAssertEqual(request.url, "svn+ssh://alice@svn.example.com/repo/trunk/README.txt@17")
        XCTAssertEqual(request.revision, Revision(17))
    }

    func testRejectsExplicitRevisionThatConflictsWithURLPegRevision() {
        XCTAssertThrowsError(try DiffWithURLValidationPolicy.validate(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            url: "file:///repo/trunk/README.txt@17",
            revisionText: "18"
        )) { error in
            XCTAssertEqual(error as? DiffWithURLValidationError, .conflictingRevisions)
        }
    }

    func testRejectsBlankTargetMalformedURLAndInvalidRevision() {
        for input in [
            (target: "", url: "file:///repo/trunk/README.txt", revision: ""),
            (target: "README.txt", url: "not a URL", revision: ""),
            (target: "README.txt", url: "file:///repo/trunk/README.txt", revision: "HEAD")
        ] {
            XCTAssertThrowsError(try DiffWithURLValidationPolicy.validate(
                workingCopy: URL(fileURLWithPath: "/tmp/wc"),
                target: input.target,
                url: input.url,
                revisionText: input.revision
            ))
        }
    }

    func testRejectsURLWithEmbeddedPasswordOrEmptyHost() {
        for url in [
            "https://alice:secret@svn.example.com/repo/trunk/README.txt",
            "https:///repo/trunk/README.txt"
        ] {
            XCTAssertThrowsError(try DiffWithURLValidationPolicy.validate(
                workingCopy: URL(fileURLWithPath: "/tmp/wc"),
                target: "README.txt",
                url: url,
                revisionText: ""
            )) { error in
                XCTAssertEqual(error as? DiffWithURLValidationError, .invalidURL)
            }
        }
    }
}

final class DiffWithURLCommandBuilderTests: XCTestCase {
    func testDiffWithURLUsesOldURLAndNewWorkingCopyTargetWithoutLeakingPassword() {
        let command = SvnCommandBuilder.diffWithURL(
            url: "https://svn.example.com/repo/trunk/README.txt@42",
            target: "README.txt",
            authArguments: ["--username", "alice", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "diff", "--non-interactive",
            "--username", "alice", "--password-from-stdin",
            "--old", "https://svn.example.com/repo/trunk/README.txt@42",
            "--new", "README.txt"
        ])
        XCTAssertFalse(command.arguments.contains("secret"))
    }

    func testDiffWithURLDisambiguatesLocalTargetContainingAtSign() {
        let command = SvnCommandBuilder.diffWithURL(
            url: "file:///repo/trunk/user%40host.txt@7",
            target: "user@host.txt"
        )

        XCTAssertEqual(Array(command.arguments.suffix(4)), [
            "--old", "file:///repo/trunk/user%40host.txt@7",
            "--new", "user@host.txt@"
        ])
    }
}

@MainActor
final class DiffWithURLViewModelTests: XCTestCase {
    func testLoadWithURLValidatesAndBuildsDiffDisplay() async {
        let provider = RecordingDiffWithURLProvider(result: .success("-old\n+new\n"))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.loadWithURL(
            target: "README.txt",
            url: "file:///repo/trunk/README.txt",
            revisionText: "7"
        )

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.diffText, "-old\n+new\n")
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            DiffWithURLCall(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                target: "README.txt",
                url: "file:///repo/trunk/README.txt@7",
                revision: Revision(7),
                auth: nil
            )
        ])
    }

    func testLoadWithURLValidationFailureClearsPreviousDisplay() async {
        let provider = RecordingDiffWithURLProvider(result: .success("old diff"))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )
        await viewModel.loadWithURL(
            target: "README.txt",
            url: "file:///repo/trunk/README.txt",
            revisionText: "7"
        )
        await viewModel.loadWithURL(target: "", url: "file:///repo/trunk/README.txt", revisionText: "")

        guard case .error = viewModel.state else {
            return XCTFail("Expected validation error")
        }
        XCTAssertEqual(viewModel.diffText, "")
        XCTAssertEqual(viewModel.lines, [])
        XCTAssertEqual(viewModel.sideBySideRows, [])
    }

    func testOlderRequestCannotOverwriteNewerDiffResult() async {
        let provider = RacingDiffProvider()
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        let older = Task { await viewModel.load(target: "slow.txt") }
        await provider.waitUntilSlowRequestStarts()
        await viewModel.load(target: "fast.txt")
        await older.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.diffText, "+fast\n")
    }

    func testClearDisplayInvalidatesRequestAlreadyInFlight() async {
        let provider = RacingDiffProvider()
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        let load = Task { await viewModel.load(target: "slow.txt") }
        await provider.waitUntilSlowRequestStarts()
        viewModel.clearDisplay()
        await load.value

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.diffText, "")
    }
}

private struct DiffWithURLCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let url: String
    let revision: Revision?
    let auth: Credential?
}

private actor RecordingDiffWithURLProvider: DiffProviding {
    let result: Result<String, Error>
    private(set) var calls: [DiffWithURLCall] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func recordedCalls() -> [DiffWithURLCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        ""
    }

    func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String {
        calls.append(DiffWithURLCall(wc: wc, target: target, url: url, revision: revision, auth: auth))
        return try result.get()
    }
}

private actor RacingDiffProvider: DiffProviding {
    private var slowStarted = false
    private var slowStartWaiter: CheckedContinuation<Void, Never>?

    func waitUntilSlowRequestStarts() async {
        if slowStarted { return }
        await withCheckedContinuation { continuation in
            slowStartWaiter = continuation
        }
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        if target == "slow.txt" {
            slowStarted = true
            slowStartWaiter?.resume()
            slowStartWaiter = nil
            try await Task.sleep(for: .milliseconds(50))
            return "+slow\n"
        }
        return "+fast\n"
    }
}
