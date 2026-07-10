import XCTest
@testable import MacSvnCore

final class PropertyConflictViewModelTests: XCTestCase {
    @MainActor
    func testLoadReadsMineTheirsBaseSideFiles() async {
        let conflict = propertyConflict(
            mine: "a.mine",
            theirs: "a.theirs",
            base: "a.base"
        )
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let files: [String: String] = [
            "/tmp/wc/a.mine": "mine-prop",
            "/tmp/wc/a.theirs": "theirs-prop",
            "/tmp/wc/a.base": "base-prop"
        ]
        let viewModel = PropertyConflictViewModel(
            conflict: conflict,
            workingCopy: wc,
            resolver: FakePropertyConflictResolver(),
            fileReader: { url in
                guard let value = files[url.path] else {
                    throw NSError(domain: "test", code: 1)
                }
                return value
            }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.path, "props.txt")
        XCTAssertEqual(viewModel.mineValue, "mine-prop")
        XCTAssertEqual(viewModel.theirsValue, "theirs-prop")
        XCTAssertEqual(viewModel.baseValue, "base-prop")
    }

    @MainActor
    func testResolveKeepMineUsesMineFullAccept() async {
        let conflict = propertyConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let resolver = FakePropertyConflictResolver()
        let viewModel = PropertyConflictViewModel(
            conflict: conflict,
            workingCopy: wc,
            resolver: resolver,
            fileReader: { _ in "" }
        )

        await viewModel.resolve(.keepMine)
        let calls = await resolver.recordedCalls()

        XCTAssertEqual(viewModel.state, .resolved(.keepMine))
        XCTAssertEqual(calls, [
            PropertyConflictResolveCall(conflict: conflict, wc: wc, accept: .mineFull)
        ])
    }

    @MainActor
    func testResolveKeepTheirsUsesTheirsFullAccept() async {
        let conflict = propertyConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let resolver = FakePropertyConflictResolver()
        let viewModel = PropertyConflictViewModel(
            conflict: conflict,
            workingCopy: wc,
            resolver: resolver,
            fileReader: { _ in "" }
        )

        await viewModel.resolve(.keepTheirs)
        let calls = await resolver.recordedCalls()

        XCTAssertEqual(viewModel.state, .resolved(.keepTheirs))
        XCTAssertEqual(calls, [
            PropertyConflictResolveCall(conflict: conflict, wc: wc, accept: .theirsFull)
        ])
    }

    @MainActor
    func testResolveFailureStoresError() async {
        let conflict = propertyConflict()
        let resolver = FakePropertyConflictResolver(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = PropertyConflictViewModel(
            conflict: conflict,
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            resolver: resolver,
            fileReader: { _ in "" }
        )

        await viewModel.resolve(.keepMine)

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    }
}

private func propertyConflict(
    mine: String? = "a.mine",
    theirs: String? = "a.theirs",
    base: String? = "a.base"
) -> ConflictInfo {
    ConflictInfo(
        path: "props.txt",
        kind: .property,
        baseFile: base,
        mineFile: mine,
        theirsFile: theirs,
        treeConflict: nil
    )
}

private struct PropertyConflictResolveCall: Equatable, Sendable {
    let conflict: ConflictInfo
    let wc: URL
    let accept: ResolveAccept
}

private actor FakePropertyConflictResolver: PropertyConflictResolving {
    private let result: Result<Void, Error>
    private var calls: [PropertyConflictResolveCall] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func recordedCalls() -> [PropertyConflictResolveCall] {
        calls
    }

    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws {
        calls.append(PropertyConflictResolveCall(conflict: conflict, wc: wc, accept: accept))
        try result.get()
    }
}
