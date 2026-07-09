import XCTest
@testable import MacSvnCore

final class BranchBrowserViewModelTests: XCTestCase {
    @MainActor
    func testLoadBranchesStoresBranchListAndPassesLayoutAuth() async {
        let branchList = BranchList(
            trunk: BranchReference(
                name: "trunk",
                url: "file:///repo/main",
                kind: .trunk,
                revision: Revision(1),
                author: nil,
                date: nil
            ),
            branches: [
                BranchReference(
                    name: "dev",
                    url: "file:///repo/dev/dev",
                    kind: .branch,
                    revision: Revision(2),
                    author: "a",
                    date: nil
                )
            ],
            tags: []
        )
        let provider = FakeBranchListProvider(result: .success(branchList))
        let viewModel = BranchBrowserViewModel(provider: provider)
        let layout = BranchLayout(trunk: "main", branches: "dev", tags: "releases")
        let auth = Credential(username: "u", password: "p")

        await viewModel.load(repositoryRoot: "file:///repo", layout: layout, auth: auth)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.branchList, branchList)
        XCTAssertEqual(calls, [
            BranchListCall(repositoryRoot: "file:///repo", layout: layout, auth: auth)
        ])
    }

    @MainActor
    func testLoadBranchesFailureClearsListAndStoresError() async {
        let provider = FakeBranchListProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = BranchBrowserViewModel(provider: provider)

        await viewModel.load(repositoryRoot: "file:///repo", layout: BranchLayout(), auth: nil)

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.branchList, BranchList())
    }
}

private struct BranchListCall: Equatable, Sendable {
    let repositoryRoot: String
    let layout: BranchLayout
    let auth: Credential?
}

private actor FakeBranchListProvider: BranchListProviding {
    private let result: Result<BranchList, Error>
    private var calls: [BranchListCall] = []

    init(result: Result<BranchList, Error>) {
        self.result = result
    }

    func recordedCalls() -> [BranchListCall] {
        calls
    }

    func branches(repositoryRoot: String, layout: BranchLayout, auth: Credential?) async throws -> BranchList {
        calls.append(BranchListCall(repositoryRoot: repositoryRoot, layout: layout, auth: auth))
        return try result.get()
    }
}
