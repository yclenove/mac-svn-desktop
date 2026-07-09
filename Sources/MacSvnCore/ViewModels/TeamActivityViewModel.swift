import Foundation
import Observation

public protocol TeamActivityLogProviding: Sendable {
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
}

public protocol TeamActivityLockProviding: Sendable {
    func locks(wc: URL, targets: [String]) async throws -> [SvnLock]
}

public enum TeamActivityViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class TeamActivityViewModel {
    private let workingCopy: URL
    private let target: String
    private let logProvider: any TeamActivityLogProviding
    private let lockProvider: any TeamActivityLockProviding
    private let aggregator: TeamActivityAggregator

    public private(set) var state: TeamActivityViewState = .idle
    public private(set) var summary: TeamActivitySummary?

    public init(
        workingCopy: URL,
        target: String,
        logProvider: any TeamActivityLogProviding,
        lockProvider: any TeamActivityLockProviding,
        aggregator: TeamActivityAggregator = TeamActivityAggregator()
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.logProvider = logProvider
        self.lockProvider = lockProvider
        self.aggregator = aggregator
    }

    public func load(from revision: Revision, batch: Int, lockTargets: [String]) async {
        state = .loading
        summary = nil

        do {
            let entries = try await logProvider.log(
                wc: workingCopy,
                target: target,
                from: revision,
                batch: max(1, batch),
                verbose: true
            )
            let locks = try await lockProvider.locks(wc: workingCopy, targets: lockTargets)
            summary = aggregator.summarize(entries: entries, locks: locks)
            state = .loaded
        } catch {
            summary = nil
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: TeamActivityLogProviding {}
extension SvnService: TeamActivityLockProviding {}
