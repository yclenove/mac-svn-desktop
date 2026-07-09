import XCTest
@testable import MacSvnCore

final class TreeConflictViewModelTests: XCTestCase {
    @MainActor
    func testTreeConflictDetailsExposePathAndReasonParts() {
        let conflict = treeConflict()
        let provider = FakeTreeConflictResolver()
        let viewModel = TreeConflictViewModel(
            conflict: conflict,
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            resolver: provider
        )

        XCTAssertEqual(viewModel.path, "tree.txt")
        XCTAssertEqual(viewModel.operation, "update")
        XCTAssertEqual(viewModel.action, "delete")
        XCTAssertEqual(viewModel.reason, "edited")
    }

    @MainActor
    func testKeepLocalAndAcceptRemoteCallResolverAndStoreState() async {
        let conflict = treeConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeTreeConflictResolver()
        let viewModel = TreeConflictViewModel(conflict: conflict, workingCopy: wc, resolver: provider)

        await viewModel.resolve(.keepLocal)
        await viewModel.resolve(.acceptRemote)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .resolved(.acceptRemote))
        XCTAssertEqual(calls, [
            TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: .keepLocal),
            TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: .acceptRemote)
        ])
    }

    @MainActor
    func testResolveFailureStoresError() async {
        let provider = FakeTreeConflictResolver(error: SvnError.network(detail: "offline"))
        let viewModel = TreeConflictViewModel(
            conflict: treeConflict(),
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            resolver: provider
        )

        await viewModel.resolve(.keepLocal)

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    }
}

private func treeConflict() -> ConflictInfo {
    ConflictInfo(
        path: "tree.txt",
        kind: .tree,
        baseFile: nil,
        mineFile: nil,
        theirsFile: nil,
        treeConflict: TreeConflictDetails(operation: "update", action: "delete", reason: "edited")
    )
}

private struct TreeConflictResolveCall: Equatable, Sendable {
    let conflict: ConflictInfo
    let wc: URL
    let resolution: TreeConflictResolution
}

private actor FakeTreeConflictResolver: TreeConflictResolving {
    let error: Error?
    private var calls: [TreeConflictResolveCall] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func resolveTreeConflict(_ conflict: ConflictInfo, wc: URL, resolution: TreeConflictResolution) async throws {
        if let error {
            throw error
        }

        calls.append(TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: resolution))
    }

    func recordedCalls() -> [TreeConflictResolveCall] {
        calls
    }
}
