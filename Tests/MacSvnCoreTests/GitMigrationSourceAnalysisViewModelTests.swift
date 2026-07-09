import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSourceAnalysisViewModelTests: XCTestCase {
    @MainActor
    func testAnalyzeStoresCompletedAnalysis() async {
        let analysis = sampleAnalysis(repositoryRoot: "file:///repo")
        let provider = FakeGitMigrationSourceAnalysisProvider(result: .success(analysis))
        let viewModel = GitMigrationSourceAnalysisViewModel(provider: provider)
        let auth = Credential(username: "u", password: "p")

        await viewModel.analyze(repositoryRoot: " file:///repo ", auth: auth)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(analysis))
        XCTAssertEqual(viewModel.analysis, analysis)
        XCTAssertEqual(calls, [
            GitMigrationSourceAnalysisCall(repositoryRoot: "file:///repo", auth: auth)
        ])
    }

    @MainActor
    func testAnalyzeStoresProviderError() async {
        let provider = FakeGitMigrationSourceAnalysisProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = GitMigrationSourceAnalysisViewModel(provider: provider)

        await viewModel.analyze(repositoryRoot: "file:///repo", auth: nil)

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.analysis)
    }

    @MainActor
    func testAnalyzeRejectsEmptyRepositoryRootBeforeProviderCall() async {
        let provider = FakeGitMigrationSourceAnalysisProvider(
            result: .failure(SvnError.other(code: nil, stderr: "unexpected"))
        )
        let viewModel = GitMigrationSourceAnalysisViewModel(provider: provider)

        await viewModel.analyze(repositoryRoot: " \n ", auth: nil)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationSourceAnalysisError.emptyRepositoryRoot)))
        XCTAssertNil(viewModel.analysis)
        XCTAssertTrue(calls.isEmpty)
    }
}

private struct GitMigrationSourceAnalysisCall: Equatable, Sendable {
    let repositoryRoot: String
    let auth: Credential?
}

private actor FakeGitMigrationSourceAnalysisProvider: GitMigrationSourceAnalyzing {
    private let result: Result<GitMigrationSourceAnalysis, Error>
    private var calls: [GitMigrationSourceAnalysisCall] = []

    init(result: Result<GitMigrationSourceAnalysis, Error>) {
        self.result = result
    }

    func recordedCalls() -> [GitMigrationSourceAnalysisCall] {
        calls
    }

    func analyze(repositoryRoot: String, auth: Credential?) async throws -> GitMigrationSourceAnalysis {
        calls.append(GitMigrationSourceAnalysisCall(repositoryRoot: repositoryRoot, auth: auth))
        return try result.get()
    }
}

private func sampleAnalysis(repositoryRoot: String) -> GitMigrationSourceAnalysis {
    GitMigrationSourceAnalysis(
        repositoryRoot: repositoryRoot,
        environment: GitMigrationEnvironmentStatus(
            git: GitMigrationToolStatus(isAvailable: true, versionOutput: "git version 2.45.0", errorSummary: nil),
            gitSvn: GitMigrationToolStatus(isAvailable: true, versionOutput: "git-svn version 2.45.0", errorSummary: nil)
        ),
        layout: GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1.0
        ),
        authors: [
            GitMigrationAuthor(svnUsername: "lisi"),
            GitMigrationAuthor(svnUsername: "zhangsan")
        ],
        latestRevision: Revision(9),
        oldestRevision: Revision(1),
        totalRevisionCount: 3
    )
}
