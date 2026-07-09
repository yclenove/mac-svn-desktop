import Foundation
import XCTest
@testable import MacSvnCore

final class MergeWizardViewModelTests: XCTestCase {
    @MainActor
    func testPreviewUsesDryRunAndStoresSummary() async {
        let provider = FakeMergeProvider(results: [.success(MergeSummary(updated: 1))])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.preview(wc: wc, source: "file:///repo/branches/feature-one", range: nil, auth: nil)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .previewReady(MergeSummary(updated: 1)))
        XCTAssertEqual(viewModel.previewSummary, MergeSummary(updated: 1))
        XCTAssertEqual(calls, [
            MergeCall(
                wc: wc,
                source: "file:///repo/branches/feature-one",
                range: nil,
                dryRun: true,
                auth: nil
            )
        ])
    }

    @MainActor
    func testExecuteMergeUsesNonDryRunAndStoresSummary() async {
        let provider = FakeMergeProvider(results: [.success(MergeSummary(merged: 1))])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.merge(wc: wc, source: "file:///repo/branches/feature-one", range: nil, auth: nil)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(MergeSummary(merged: 1)))
        XCTAssertEqual(viewModel.mergeSummary, MergeSummary(merged: 1))
        XCTAssertEqual(calls, [
            MergeCall(
                wc: wc,
                source: "file:///repo/branches/feature-one",
                range: nil,
                dryRun: false,
                auth: nil
            )
        ])
    }

    @MainActor
    func testPreviewRejectsEmptySourceBeforeProviderCall() async {
        let provider = FakeMergeProvider(results: [.success(MergeSummary(updated: 1))])
        let viewModel = MergeWizardViewModel(provider: provider)

        await viewModel.preview(wc: URL(fileURLWithPath: "/tmp/wc"), source: "  ", range: nil, auth: nil)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("emptyMergeSource"))
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testMergeFailureStoresErrorAndClearsSummary() async {
        let provider = FakeMergeProvider(results: [.failure(SvnError.network(detail: "offline"))])
        let viewModel = MergeWizardViewModel(provider: provider)

        await viewModel.merge(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            source: "file:///repo/branches/feature-one",
            range: nil,
            auth: nil
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.mergeSummary)
    }
}

private struct MergeCall: Equatable, Sendable {
    let wc: URL
    let source: String
    let range: RevisionRange?
    let dryRun: Bool
    let auth: Credential?
}

private actor FakeMergeProvider: MergeProviding {
    private var results: [Result<MergeSummary, Error>]
    private var calls: [MergeCall] = []

    init(results: [Result<MergeSummary, Error>]) {
        self.results = results
    }

    func recordedCalls() -> [MergeCall] {
        calls
    }

    func merge(
        wc: URL,
        source: String,
        range: RevisionRange?,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary {
        calls.append(MergeCall(
            wc: wc,
            source: source,
            range: range,
            dryRun: dryRun,
            auth: auth
        ))

        guard !results.isEmpty else {
            throw SvnError.other(code: nil, stderr: "missing fake result")
        }

        return try results.removeFirst().get()
    }
}
