import Foundation
import Observation

public enum AIBlameEvolutionViewState: Equatable, Sendable {
    case idle
    case explaining
    case completed(AIBlameEvolutionExplanation)
    case error(String)
}

/// Blame 行选区演化解释 UI 状态（FR-AI-06）。
@MainActor
@Observable
public final class AIBlameEvolutionViewModel {
    private let explainer: any AIBlameEvolutionExplaining

    public private(set) var state: AIBlameEvolutionViewState = .idle
    public private(set) var explanation: AIBlameEvolutionExplanation?

    public var rangeStart: Int = 1
    public var rangeEnd: Int = 1

    public init(explainer: any AIBlameEvolutionExplaining) {
        self.explainer = explainer
    }

    public var selectedLineRange: ClosedRange<Int>? {
        guard rangeStart > 0, rangeEnd >= rangeStart else { return nil }
        return rangeStart...rangeEnd
    }

    public func setRange(start: Int, end: Int) {
        rangeStart = max(1, start)
        rangeEnd = max(rangeStart, end)
    }

    public func explain(
        wc: URL,
        target: String,
        blameLines: [BlameLine],
        privacySettings: AIPrivacySettings
    ) async {
        guard let lineRange = selectedLineRange else {
            state = .error(String(describing: AIBlameEvolutionError.emptyLineSelection))
            return
        }

        state = .explaining
        explanation = nil
        do {
            let result = try await explainer.explain(
                wc: wc,
                target: target,
                lineRange: lineRange,
                blameLines: blameLines,
                privacySettings: privacySettings
            )
            explanation = result
            state = .completed(result)
        } catch {
            explanation = nil
            state = .error(String(describing: error))
        }
    }
}
