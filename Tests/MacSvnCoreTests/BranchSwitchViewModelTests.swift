import Foundation
import XCTest
@testable import MacSvnCore

final class BranchSwitchViewModelTests: XCTestCase {
    @MainActor
    func testSwitchStoresCompletedSummary() async {
        let provider = FakeBranchSwitchProvider(
            results: [.success(UpdateSummary(updated: 1, revision: Revision(9)))]
        )
        let viewModel = BranchSwitchViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.switchTo(wc: wc, url: "file:///repo/branches/feature-one", auth: nil)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(UpdateSummary(updated: 1, revision: Revision(9))))
        XCTAssertEqual(calls, [
            BranchSwitchCall(
                wc: wc,
                url: "file:///repo/branches/feature-one",
                auth: nil,
                allowLocalChanges: false
            )
        ])
    }

    @MainActor
    func testSwitchWithLocalChangesStoresConfirmationAndConfirmRetriesAllowed() async {
        let provider = FakeBranchSwitchProvider(results: [
            .failure(SvnServiceError.localChangesPreventSwitch(paths: ["README.txt"])),
            .success(UpdateSummary(revision: Revision(10)))
        ])
        let viewModel = BranchSwitchViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.switchTo(wc: wc, url: "file:///repo/branches/feature-one", auth: nil)
        XCTAssertEqual(viewModel.state, .confirmationRequired(paths: ["README.txt"]))

        await viewModel.confirmSwitchWithLocalChanges()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(UpdateSummary(revision: Revision(10))))
        XCTAssertEqual(calls, [
            BranchSwitchCall(
                wc: wc,
                url: "file:///repo/branches/feature-one",
                auth: nil,
                allowLocalChanges: false
            ),
            BranchSwitchCall(
                wc: wc,
                url: "file:///repo/branches/feature-one",
                auth: nil,
                allowLocalChanges: true
            )
        ])
    }

    @MainActor
    func testSwitchFailureStoresErrorAndClearsSummary() async {
        let provider = FakeBranchSwitchProvider(results: [
            .failure(SvnError.network(detail: "offline"))
        ])
        let viewModel = BranchSwitchViewModel(provider: provider)

        await viewModel.switchTo(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            url: "file:///repo/branches/feature-one",
            auth: nil
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.lastSummary)
    }

    @MainActor
    func testConfirmWithoutPendingRequestLeavesStateIdle() async {
        let provider = FakeBranchSwitchProvider(results: [
            .success(UpdateSummary(revision: Revision(10)))
        ])
        let viewModel = BranchSwitchViewModel(provider: provider)

        await viewModel.confirmSwitchWithLocalChanges()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(calls, [])
    }
}

private struct BranchSwitchCall: Equatable, Sendable {
    let wc: URL
    let url: String
    let auth: Credential?
    let allowLocalChanges: Bool
}

private actor FakeBranchSwitchProvider: BranchSwitchProviding {
    private var results: [Result<UpdateSummary, Error>]
    private var calls: [BranchSwitchCall] = []

    init(results: [Result<UpdateSummary, Error>]) {
        self.results = results
    }

    func recordedCalls() -> [BranchSwitchCall] {
        calls
    }

    func switchTo(
        wc: URL,
        url: String,
        auth: Credential?,
        allowLocalChanges: Bool
    ) async throws -> UpdateSummary {
        calls.append(BranchSwitchCall(
            wc: wc,
            url: url,
            auth: auth,
            allowLocalChanges: allowLocalChanges
        ))

        guard !results.isEmpty else {
            throw SvnError.other(code: nil, stderr: "missing fake result")
        }

        return try results.removeFirst().get()
    }
}
