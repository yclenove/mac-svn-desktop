import Foundation
import Observation

public protocol BlameProviding: Sendable {
    func blame(wc: URL, target: String) async throws -> [BlameLine]
}

public enum BlameViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class BlameViewModel {
    private let workingCopy: URL
    private let target: String
    private let provider: any BlameProviding

    public private(set) var state: BlameViewState = .idle
    public private(set) var lines: [BlameLine] = []
    public private(set) var selectedRevision: Revision?

    public init(workingCopy: URL, target: String, provider: any BlameProviding) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
    }

    public func load() async {
        state = .loading
        lines = []
        selectedRevision = nil

        do {
            lines = try await provider.blame(wc: workingCopy, target: target)
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func selectLine(_ lineNumber: Int) {
        selectedRevision = lines.first { $0.lineNumber == lineNumber }?.revision
    }
}

extension SvnService: BlameProviding {}
