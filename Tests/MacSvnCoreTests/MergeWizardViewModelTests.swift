import Foundation
import XCTest
@testable import MacSvnCore

final class MergeWizardViewModelTests: XCTestCase {
    @MainActor
    func testPreviewTwoTreesUsesDryRunAndStoresSummary() async {
        let provider = FakeMergeProvider(twoTreeResults: [.success(MergeSummary(updated: 2))])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.previewTwoTrees(
            wc: wc,
            from: " file:///repo/branches/old ",
            to: " file:///repo/branches/new "
        )

        XCTAssertEqual(viewModel.state, .previewReady(MergeSummary(updated: 2)))
        let calls = await provider.recordedTwoTreeCalls()
        XCTAssertEqual(calls, [
            TwoTreeMergeCall(
                wc: wc,
                from: "file:///repo/branches/old",
                to: "file:///repo/branches/new",
                dryRun: true,
                auth: nil
            )
        ])
    }

    @MainActor
    func testUnifiedDiffPreviewUsesRangeSource() async {
        let provider = FakeMergeProvider(diffResults: [.success("--- old\n+++ new\n")])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.previewUnifiedDiff(
            wc: wc,
            source: "file:///repo/branches/feature-one",
            range: RevisionRange(start: Revision(2), end: Revision(5))
        )

        XCTAssertEqual(viewModel.state, .diffReady)
        XCTAssertEqual(viewModel.unifiedDiff, "--- old\n+++ new\n")
        let calls = await provider.recordedDiffCalls()
        XCTAssertEqual(calls, [
            MergeDiffCall(
                wc: wc,
                target: "file:///repo/branches/feature-one",
                r1: Revision(2),
                r2: Revision(5)
            )
        ])
    }

    @MainActor
    func testTwoTreeUnifiedDiffUsesOldAndNewUrls() async {
        let provider = FakeMergeProvider(diffResults: [.success("two-tree diff")])
        let viewModel = MergeWizardViewModel(provider: provider)

        await viewModel.previewTwoTreeUnifiedDiff(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            from: "file:///repo/branches/old",
            to: "file:///repo/branches/new"
        )

        XCTAssertEqual(viewModel.state, .diffReady)
        XCTAssertEqual(viewModel.unifiedDiff, "two-tree diff")
        let calls = await provider.recordedTwoTreeDiffCalls()
        XCTAssertEqual(
            calls,
            [TwoTreeDiffCall(oldPath: "file:///repo/branches/old", newPath: "file:///repo/branches/new")]
        )
    }

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
    func testReintegrateUsesCompleteMergeProviderOperation() async {
        let provider = FakeMergeProvider(results: [.success(MergeSummary(merged: 1))])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.previewReintegrate(wc: wc, source: " file:///repo/branches/feature-one ")

        XCTAssertEqual(viewModel.state, .previewReady(MergeSummary(merged: 1)))
        let calls = await provider.recordedReintegrateCalls()
        XCTAssertEqual(calls, [
            MergeSpecialCall(wc: wc, source: "file:///repo/branches/feature-one", revision: nil, dryRun: true)
        ])
    }

    @MainActor
    func testMergeRevisionToUsesSelectedRevisionProviderOperation() async {
        let provider = FakeMergeProvider(results: [.success(MergeSummary(updated: 1))])
        let viewModel = MergeWizardViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.mergeRevisionTo(
            wc: wc,
            source: "file:///repo/trunk",
            revision: Revision(12)
        )

        XCTAssertEqual(viewModel.state, .completed(MergeSummary(updated: 1)))
        let calls = await provider.recordedReintegrateCalls()
        XCTAssertEqual(calls, [
            MergeSpecialCall(wc: wc, source: "file:///repo/trunk", revision: Revision(12), dryRun: false)
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

private struct TwoTreeMergeCall: Equatable, Sendable {
    let wc: URL
    let from: String
    let to: String
    let dryRun: Bool
    let auth: Credential?
}

private struct MergeDiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private struct TwoTreeDiffCall: Equatable, Sendable {
    let oldPath: String
    let newPath: String
}

private struct MergeSpecialCall: Equatable, Sendable {
    let wc: URL
    let source: String
    let revision: Revision?
    let dryRun: Bool
}

private actor FakeMergeProvider: MergeProviding {
    private var results: [Result<MergeSummary, Error>]
    private var twoTreeResults: [Result<MergeSummary, Error>]
    private var diffResults: [Result<String, Error>]
    private var calls: [MergeCall] = []
    private var twoTreeCalls: [TwoTreeMergeCall] = []
    private var diffCalls: [MergeDiffCall] = []
    private var twoTreeDiffCalls: [TwoTreeDiffCall] = []
    private var reintegrateCalls: [MergeSpecialCall] = []

    init(
        results: [Result<MergeSummary, Error>] = [],
        twoTreeResults: [Result<MergeSummary, Error>] = [],
        diffResults: [Result<String, Error>] = []
    ) {
        self.results = results
        self.twoTreeResults = twoTreeResults
        self.diffResults = diffResults
    }

    func recordedCalls() -> [MergeCall] {
        calls
    }

    func recordedTwoTreeCalls() -> [TwoTreeMergeCall] { twoTreeCalls }
    func recordedDiffCalls() -> [MergeDiffCall] { diffCalls }
    func recordedTwoTreeDiffCalls() -> [TwoTreeDiffCall] { twoTreeDiffCalls }
    func recordedReintegrateCalls() -> [MergeSpecialCall] { reintegrateCalls }

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

    func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary {
        twoTreeCalls.append(TwoTreeMergeCall(wc: wc, from: from, to: to, dryRun: dryRun, auth: auth))
        guard !twoTreeResults.isEmpty else { throw SvnError.other(code: nil, stderr: "missing fake result") }
        return try twoTreeResults.removeFirst().get()
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        diffCalls.append(MergeDiffCall(wc: wc, target: target, r1: r1, r2: r2))
        guard !diffResults.isEmpty else { throw SvnError.other(code: nil, stderr: "missing fake diff") }
        return try diffResults.removeFirst().get()
    }

    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        twoTreeDiffCalls.append(TwoTreeDiffCall(oldPath: oldPath, newPath: newPath))
        guard !diffResults.isEmpty else { throw SvnError.other(code: nil, stderr: "missing fake diff") }
        return try diffResults.removeFirst().get()
    }

    func mergeReintegrate(wc: URL, source: String, dryRun: Bool, auth: Credential?) async throws -> MergeSummary {
        reintegrateCalls.append(MergeSpecialCall(wc: wc, source: source, revision: nil, dryRun: dryRun))
        guard !results.isEmpty else { throw SvnError.other(code: nil, stderr: "missing fake result") }
        return try results.removeFirst().get()
    }

    func mergeRevisionTo(wc: URL, source: String, revision: Revision, dryRun: Bool, auth: Credential?) async throws -> MergeSummary {
        reintegrateCalls.append(MergeSpecialCall(wc: wc, source: source, revision: revision, dryRun: dryRun))
        guard !results.isEmpty else { throw SvnError.other(code: nil, stderr: "missing fake result") }
        return try results.removeFirst().get()
    }
}
