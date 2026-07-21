import XCTest
@testable import MacSvnCore

final class ConflictListViewModelTests: XCTestCase {
    @MainActor
    func testLoadConflictsStoresEntriesSummaryAndSelectsFirstConflict() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let conflicts = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "src/main.swift", kind: .tree),
            conflict(path: "project.pbxproj", kind: .property)
        ]
        let provider = FakeConflictListProvider(result: .success(conflicts))
        let viewModel = ConflictListViewModel(workingCopy: wc, provider: provider)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.conflicts, conflicts)
        XCTAssertEqual(viewModel.visibleConflicts, conflicts)
        XCTAssertEqual(viewModel.summary, ConflictListSummary(
            total: 3,
            text: 1,
            tree: 1,
            property: 1,
            unknown: 0
        ))
        XCTAssertEqual(viewModel.selectedConflict, conflicts[0])
        let workingCopies = await provider.recordedWorkingCopies()
        XCTAssertEqual(workingCopies, [wc])
    }

    @MainActor
    func testKindFilterAndCaseInsensitiveSearchProduceVisibleConflicts() async {
        let provider = FakeConflictListProvider(result: .success([
            conflict(path: "README.txt", kind: .text),
            conflict(path: "Sources/Login.swift", kind: .text),
            conflict(path: "Sources/Tree.swift", kind: .tree)
        ]))
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider
        )

        await viewModel.refresh()
        viewModel.kindFilter = .kinds([.text])
        viewModel.searchText = "login"

        XCTAssertEqual(viewModel.visibleConflicts, [
            conflict(path: "Sources/Login.swift", kind: .text)
        ])
    }

    @MainActor
    func testSelectConflictByPathUpdatesSelectionAndIgnoresMissingPath() async {
        let conflicts = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "Sources/Tree.swift", kind: .tree)
        ]
        let provider = FakeConflictListProvider(result: .success(conflicts))
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider
        )

        await viewModel.refresh()
        viewModel.selectConflict(path: "Sources/Tree.swift")
        XCTAssertEqual(viewModel.selectedConflict, conflicts[1])

        viewModel.selectConflict(path: "missing.txt")
        XCTAssertEqual(viewModel.selectedConflict, conflicts[1])
    }

    @MainActor
    func testRefreshFailureClearsConflictsSelectionAndStoresError() async {
        let provider = FakeConflictListProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.conflicts, [])
        XCTAssertEqual(viewModel.summary, ConflictListSummary())
        XCTAssertNil(viewModel.selectedConflict)
    }

    @MainActor
    func testRefreshPreservesSelectionWhenPathStillExists() async {
        let first = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "Sources/Tree.swift", kind: .tree)
        ]
        let second = [
            conflict(path: "Other.txt", kind: .text),
            conflict(path: "Sources/Tree.swift", kind: .tree)
        ]
        let provider = FakeConflictListProvider(results: [
            .success(first),
            .success(second)
        ])
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider
        )

        await viewModel.refresh()
        viewModel.selectConflict(path: "Sources/Tree.swift")
        await viewModel.refresh()

        XCTAssertEqual(viewModel.selectedConflict, second[1])
    }

    @MainActor
    func testRefreshFallsBackToFirstConflictWhenSelectionDisappears() async {
        let first = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "Sources/Tree.swift", kind: .tree)
        ]
        let second = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "Other.txt", kind: .text)
        ]
        let provider = FakeConflictListProvider(results: [
            .success(first),
            .success(second)
        ])
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider
        )

        await viewModel.refresh()
        viewModel.selectConflict(path: "Sources/Tree.swift")
        await viewModel.refresh()

        XCTAssertEqual(viewModel.selectedConflict, second[0])
    }
    @MainActor
    func testMarkCheckedAsResolvedCallsBatchResolverAndRefreshes() async {
        let conflicts = [
            conflict(path: "a.txt", kind: .text),
            conflict(path: "tree", kind: .tree),
            conflict(path: "b.prop", kind: .property),
        ]
        let provider = FakeConflictListProvider(results: [
            .success(conflicts),
            .success([conflict(path: "tree", kind: .tree)])
        ])
        let resolver = FakeConflictBatchResolver()
        let viewModel = ConflictListViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            batchResolver: resolver
        )

        await viewModel.refresh()
        viewModel.checkAllVisibleEligible()
        XCTAssertEqual(Set(viewModel.checkedPathsEligibleForMarkResolved), ["a.txt", "b.prop"])

        let count = await viewModel.markCheckedAsResolved()
        let calls = await resolver.recordedCalls()

        XCTAssertEqual(count, 2)
        XCTAssertEqual(calls.first?.paths, ["a.txt", "b.prop"])
        XCTAssertEqual(calls.first?.accept, .working)
        XCTAssertEqual(viewModel.conflicts.map(\.path), ["tree"])
    }
}

private func conflict(path: String, kind: ConflictKind) -> ConflictInfo {
    ConflictInfo(
        path: path,
        kind: kind,
        baseFile: nil,
        mineFile: nil,
        theirsFile: nil,
        treeConflict: nil
    )
}

private actor FakeConflictListProvider: ConflictListing {
    private var results: [Result<[ConflictInfo], Error>]
    private var workingCopies: [URL] = []

    init(result: Result<[ConflictInfo], Error>) {
        self.results = [result]
    }

    init(results: [Result<[ConflictInfo], Error>]) {
        self.results = results
    }

    func conflicts(wc: URL) async throws -> [ConflictInfo] {
        workingCopies.append(wc)
        guard !results.isEmpty else {
            return []
        }

        return try results.removeFirst().get()
    }

    func recordedWorkingCopies() -> [URL] {
        workingCopies
    }
}

private actor FakeConflictBatchResolver: ConflictBatchResolving {
    struct Call: Equatable, Sendable {
        let wc: URL
        let paths: [String]
        let accept: ResolveAccept
    }

    private var calls: [Call] = []

    func resolve(wc: URL, paths: [String], accept: ResolveAccept) async throws -> ConflictBatchResolveOutcome {
        calls.append(Call(wc: wc, paths: paths, accept: accept))
        return ConflictBatchResolveOutcome(succeededPaths: paths)
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
