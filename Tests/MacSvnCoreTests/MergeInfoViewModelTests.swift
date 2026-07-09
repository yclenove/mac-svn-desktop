import XCTest
@testable import MacSvnCore

final class MergeInfoViewModelTests: XCTestCase {
    @MainActor
    func testLoadMergeInfoStoresEntriesAndPassesTarget() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let entries = [
            MergeInfoEntry(
                sourcePath: "/branches/feature-a",
                ranges: [MergeInfoRevisionRange(start: Revision(2), end: Revision(4))]
            )
        ]
        let provider = FakeMergeInfoProvider(result: .success(entries))
        let viewModel = MergeInfoViewModel(workingCopy: wc, target: ".", provider: provider)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.entries, entries)
        XCTAssertEqual(viewModel.totalMergedRevisionCount, 3)
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            MergeInfoProviderCall(wc: wc, target: ".")
        ])
    }

    @MainActor
    func testLoadMergeInfoFailureClearsEntriesAndStoresError() async {
        let provider = FakeMergeInfoProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = MergeInfoViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            provider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.entries, [])
        XCTAssertEqual(viewModel.totalMergedRevisionCount, 0)
    }
}

private struct MergeInfoProviderCall: Equatable, Sendable {
    let wc: URL
    let target: String
}

private actor FakeMergeInfoProvider: MergeInfoProviding {
    private let result: Result<[MergeInfoEntry], Error>
    private var calls: [MergeInfoProviderCall] = []

    init(result: Result<[MergeInfoEntry], Error>) {
        self.result = result
    }

    func recordedCalls() -> [MergeInfoProviderCall] {
        calls
    }

    func mergeInfo(wc: URL, target: String) async throws -> [MergeInfoEntry] {
        calls.append(MergeInfoProviderCall(wc: wc, target: target))
        return try result.get()
    }
}
