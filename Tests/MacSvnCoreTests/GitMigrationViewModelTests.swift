import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationViewModelTests: XCTestCase {
    @MainActor
    func testSnapshotMigrationStoresCompletedReport() async {
        let destination = URL(fileURLWithPath: "/tmp/snapshot")
        let report = GitMigrationReport(
            mode: .snapshot,
            sourceURL: "file:///repo/trunk",
            destinationPath: destination.path,
            revision: Revision(5),
            commitMessage: "Initial SVN snapshot",
            completedSteps: [.svnExport, .gitInit, .gitAdd, .gitCommit]
        )
        let provider = FakeGitMigrationProvider(result: .success(report))
        let viewModel = GitMigrationViewModel(provider: provider)
        let auth = Credential(username: "u", password: "p")

        await viewModel.snapshotMigrate(
            sourceURL: "file:///repo/trunk",
            destination: destination,
            revision: Revision(5),
            commitMessage: "Initial SVN snapshot",
            auth: auth
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(report))
        XCTAssertEqual(viewModel.report, report)
        XCTAssertEqual(calls, [
            GitMigrationCall(
                sourceURL: "file:///repo/trunk",
                destination: destination,
                revision: Revision(5),
                commitMessage: "Initial SVN snapshot",
                auth: auth
            )
        ])
    }

    @MainActor
    func testSnapshotMigrationStoresProviderError() async {
        let provider = FakeGitMigrationProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = GitMigrationViewModel(provider: provider)

        await viewModel.snapshotMigrate(
            sourceURL: "file:///repo/trunk",
            destination: URL(fileURLWithPath: "/tmp/snapshot"),
            commitMessage: "Initial SVN snapshot"
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.report)
    }

    @MainActor
    func testSnapshotMigrationRejectsEmptyInputsBeforeProviderCall() async {
        let provider = FakeGitMigrationProvider(result: .failure(SvnError.other(code: nil, stderr: "unexpected")))
        let viewModel = GitMigrationViewModel(provider: provider)
        let destination = URL(fileURLWithPath: "/tmp/snapshot")

        await viewModel.snapshotMigrate(
            sourceURL: " ",
            destination: destination,
            commitMessage: "Initial SVN snapshot"
        )
        XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationError.emptySourceURL)))

        await viewModel.snapshotMigrate(
            sourceURL: "file:///repo/trunk",
            destination: destination,
            commitMessage: "\n"
        )
        XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationError.emptyCommitMessage)))

        let calls = await provider.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }
}

private struct GitMigrationCall: Equatable, Sendable {
    let sourceURL: String
    let destination: URL
    let revision: Revision?
    let commitMessage: String
    let auth: Credential?
}

private actor FakeGitMigrationProvider: GitMigrationProviding {
    private let result: Result<GitMigrationReport, Error>
    private var calls: [GitMigrationCall] = []

    init(result: Result<GitMigrationReport, Error>) {
        self.result = result
    }

    func recordedCalls() -> [GitMigrationCall] {
        calls
    }

    func snapshotMigrate(
        sourceURL: String,
        destination: URL,
        revision: Revision?,
        commitMessage: String,
        auth: Credential?
    ) async throws -> GitMigrationReport {
        calls.append(GitMigrationCall(
            sourceURL: sourceURL,
            destination: destination,
            revision: revision,
            commitMessage: commitMessage,
            auth: auth
        ))
        return try result.get()
    }
}
