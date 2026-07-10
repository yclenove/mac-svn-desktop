import Foundation
import XCTest
@testable import MacSvnCore

final class AIBlameEvolutionViewModelTests: XCTestCase {
    @MainActor
    func testExplainStoresCompletedExplanation() async {
        let expected = AIBlameEvolutionExplanation(
            target: "a.swift",
            lineRange: AIBlameLineRange(startLine: 2, endLine: 3),
            summary: "登录重试",
            keyChanges: [
                AIBlameEvolutionChange(revision: Revision(10), title: "retry", explanation: "加了重试")
            ],
            providerID: UUID(),
            evidenceRevisionCount: 1,
            redactionMatches: [],
            promptCount: 1
        )
        let explainer = FakeBlameEvolutionExplainer(result: .success(expected))
        let viewModel = AIBlameEvolutionViewModel(explainer: explainer)
        viewModel.setRange(start: 2, end: 3)

        await viewModel.explain(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            target: "a.swift",
            blameLines: [
                BlameLine(lineNumber: 2, revision: Revision(10), author: "a", date: nil),
                BlameLine(lineNumber: 3, revision: Revision(10), author: "a", date: nil)
            ],
            privacySettings: AIPrivacySettings()
        )
        let calls = await explainer.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(expected))
        XCTAssertEqual(viewModel.explanation, expected)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].lineRange, 2...3)
    }

    @MainActor
    func testInvalidRangeStoresEmptySelectionError() async {
        let viewModel = AIBlameEvolutionViewModel(
            explainer: FakeBlameEvolutionExplainer(result: .success(
                AIBlameEvolutionExplanation(
                    target: "x",
                    lineRange: AIBlameLineRange(startLine: 1, endLine: 1),
                    summary: "",
                    keyChanges: [],
                    providerID: UUID(),
                    evidenceRevisionCount: 0,
                    redactionMatches: [],
                    promptCount: 0
                )
            ))
        )
        viewModel.rangeStart = 5
        viewModel.rangeEnd = 2

        await viewModel.explain(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            target: "a.swift",
            blameLines: [],
            privacySettings: AIPrivacySettings()
        )

        XCTAssertEqual(
            viewModel.state,
            .error(String(describing: AIBlameEvolutionError.emptyLineSelection))
        )
    }
}

private struct BlameEvolutionCall: Equatable, Sendable {
    let lineRange: ClosedRange<Int>
}

private actor FakeBlameEvolutionExplainer: AIBlameEvolutionExplaining {
    private let result: Result<AIBlameEvolutionExplanation, Error>
    private var calls: [BlameEvolutionCall] = []

    init(result: Result<AIBlameEvolutionExplanation, Error>) {
        self.result = result
    }

    func recordedCalls() -> [BlameEvolutionCall] { calls }

    func explain(
        wc: URL,
        target: String,
        lineRange: ClosedRange<Int>,
        blameLines: [BlameLine],
        privacySettings: AIPrivacySettings
    ) async throws -> AIBlameEvolutionExplanation {
        calls.append(BlameEvolutionCall(lineRange: lineRange))
        return try result.get()
    }
}
