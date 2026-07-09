import Foundation
import XCTest
@testable import MacSvnCore

final class RepoBrowserViewModelTests: XCTestCase {
    @MainActor
    func testLoadChildrenStoresEntriesByUrlAndUsesImmediateDepth() async {
        let provider = FakeRepoListProvider(result: .success([
            RemoteEntry(
                name: "trunk",
                path: "trunk",
                kind: .directory,
                size: nil,
                revision: Revision(1),
                author: "a",
                date: nil
            )
        ]))
        let viewModel = RepoBrowserViewModel(listProvider: provider)

        await viewModel.loadChildren(of: "file:///repo")
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state(for: "file:///repo"), .loaded)
        XCTAssertEqual(viewModel.children(of: "file:///repo").map(\.name), ["trunk"])
        XCTAssertEqual(calls, [
            RepoListCall(url: "file:///repo", depth: .immediates, auth: nil)
        ])
    }

    @MainActor
    func testLoadChildrenFailureStoresError() async {
        let provider = FakeRepoListProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = RepoBrowserViewModel(listProvider: provider)

        await viewModel.loadChildren(of: "file:///repo")

        XCTAssertEqual(viewModel.state(for: "file:///repo"), .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.children(of: "file:///repo"), [])
    }
}

private struct RepoListCall: Equatable, Sendable {
    let url: String
    let depth: SvnDepth
    let auth: Credential?
}

private actor FakeRepoListProvider: RepoListProviding {
    private let result: Result<[RemoteEntry], Error>
    private var calls: [RepoListCall] = []

    init(result: Result<[RemoteEntry], Error>) {
        self.result = result
    }

    func recordedCalls() -> [RepoListCall] {
        calls
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        calls.append(RepoListCall(url: url, depth: depth, auth: auth))
        return try result.get()
    }
}
