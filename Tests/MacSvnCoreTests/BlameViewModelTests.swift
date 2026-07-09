import Foundation
import XCTest
@testable import MacSvnCore

final class BlameViewModelTests: XCTestCase {
    @MainActor
    func testLoadBlameStoresLinesAndSelectsRevision() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let lines = [
            BlameLine(lineNumber: 1, revision: Revision(7), author: "yangchao", date: nil),
            BlameLine(lineNumber: 2, revision: Revision(8), author: "alice", date: nil)
        ]
        let provider = FakeBlameProvider(result: .success(lines))
        let viewModel = BlameViewModel(workingCopy: wc, target: "README.txt", provider: provider)

        await viewModel.load()
        viewModel.selectLine(2)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.lines, lines)
        XCTAssertEqual(viewModel.selectedRevision, Revision(8))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [BlameProviderCall(wc: wc, target: "README.txt")])
    }

    @MainActor
    func testLoadBlameFailureClearsLinesAndStoresError() async {
        let provider = FakeBlameProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = BlameViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.lines, [])
        XCTAssertNil(viewModel.selectedRevision)
    }
}

private struct BlameProviderCall: Equatable {
    let wc: URL
    let target: String
}

private actor FakeBlameProvider: BlameProviding {
    private let result: Result<[BlameLine], Error>
    private var calls: [BlameProviderCall] = []

    init(result: Result<[BlameLine], Error>) {
        self.result = result
    }

    func recordedCalls() -> [BlameProviderCall] {
        calls
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        calls.append(BlameProviderCall(wc: wc, target: target))
        return try result.get()
    }
}
