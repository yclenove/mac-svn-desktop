import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationRevisionReconciliationViewModelTests: XCTestCase {
    @MainActor
    func testReconcileStoresCompletedReport() async {
        let report = GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: 1,
            migratedRevisionCount: 1,
            missingRevisions: [],
            unexpectedRevisions: []
        )
        let provider = FakeGitMigrationRevisionReconciliationProvider(result: .success(report))
        let viewModel = GitMigrationRevisionReconciliationViewModel(provider: provider)
        let repository = URL(fileURLWithPath: "/tmp/history")

        await viewModel.reconcile(
            sourceRevisions: [Revision(1)],
            gitRepository: repository
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(report))
        XCTAssertEqual(viewModel.report, report)
        XCTAssertEqual(calls, [
            GitMigrationRevisionReconciliationCall(
                sourceRevisions: [Revision(1)],
                gitRepository: repository
            )
        ])
    }

    @MainActor
    func testReconcileFailureClearsReportAndStoresError() async {
        let provider = FakeGitMigrationRevisionReconciliationProvider(
            result: .failure(SvnError.parse(detail: "bad log"))
        )
        let viewModel = GitMigrationRevisionReconciliationViewModel(provider: provider)

        await viewModel.reconcile(
            sourceRevisions: [Revision(1)],
            gitRepository: URL(fileURLWithPath: "/tmp/history")
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.parse(detail: "bad log"))))
        XCTAssertNil(viewModel.report)
    }
}

private struct GitMigrationRevisionReconciliationCall: Equatable, Sendable {
    let sourceRevisions: [Revision]
    let gitRepository: URL
}

private actor FakeGitMigrationRevisionReconciliationProvider: GitMigrationRevisionReconciliationProviding {
    private let result: Result<GitMigrationRevisionReconciliationReport, Error>
    private var calls: [GitMigrationRevisionReconciliationCall] = []

    init(result: Result<GitMigrationRevisionReconciliationReport, Error>) {
        self.result = result
    }

    func recordedCalls() -> [GitMigrationRevisionReconciliationCall] {
        calls
    }

    func reconcileHistoryMigration(
        sourceRevisions: [Revision],
        gitRepository: URL
    ) async throws -> GitMigrationRevisionReconciliationReport {
        calls.append(GitMigrationRevisionReconciliationCall(
            sourceRevisions: sourceRevisions,
            gitRepository: gitRepository
        ))
        return try result.get()
    }
}
