import Foundation
import Observation

public enum MergeInfoViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class MergeInfoViewModel {
    private let workingCopy: URL
    private let target: String
    private let provider: any MergeInfoProviding

    public private(set) var state: MergeInfoViewState = .idle
    public private(set) var entries: [MergeInfoEntry] = []

    public init(workingCopy: URL, target: String, provider: any MergeInfoProviding) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
    }

    public var totalMergedRevisionCount: Int {
        entries.reduce(0) { partial, entry in
            partial + entry.revisionCount
        }
    }

    public func load() async {
        state = .loading

        do {
            entries = try await provider.mergeInfo(wc: workingCopy, target: target)
            state = .loaded
        } catch {
            entries = []
            state = .error(String(describing: error))
        }
    }
}
