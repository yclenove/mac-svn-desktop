import Foundation
import Observation

public protocol LogProviding: Sendable {
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
}

public enum LogViewState: Equatable, Sendable {
    case idle
    case loading
    case loadingMore
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class LogViewModel {
    private let workingCopy: URL
    private let target: String
    private let batchSize: Int
    private let logProvider: any LogProviding
    private var nextFromRevision: Revision?

    public private(set) var state: LogViewState = .idle
    public private(set) var entries: [LogEntry] = []
    public private(set) var hasMore = false

    public init(
        workingCopy: URL,
        target: String,
        batchSize: Int,
        logProvider: any LogProviding
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.batchSize = max(1, batchSize)
        self.logProvider = logProvider
    }

    public var isLoading: Bool {
        state == .loading || state == .loadingMore
    }

    public func loadInitial(from revision: Revision) async {
        state = .loading
        entries = []
        hasMore = false
        nextFromRevision = nil

        do {
            let loadedEntries = try await logProvider.log(
                wc: workingCopy,
                target: target,
                from: revision,
                batch: batchSize,
                verbose: true
            )
            entries = loadedEntries
            updatePagination(from: loadedEntries)
            state = .loaded
        } catch {
            entries = []
            hasMore = false
            nextFromRevision = nil
            state = .error(String(describing: error))
        }
    }

    public func loadMore() async {
        guard hasMore, let nextFromRevision, !isLoading else {
            return
        }

        state = .loadingMore

        do {
            let loadedEntries = try await logProvider.log(
                wc: workingCopy,
                target: target,
                from: nextFromRevision,
                batch: batchSize,
                verbose: true
            )
            entries += loadedEntries
            updatePagination(from: loadedEntries)
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func updatePagination(from loadedEntries: [LogEntry]) {
        guard loadedEntries.count == batchSize,
              let lowestRevision = loadedEntries.map(\.revision.value).min(),
              lowestRevision > 0
        else {
            hasMore = false
            nextFromRevision = nil
            return
        }

        hasMore = true
        nextFromRevision = Revision(lowestRevision - 1)
    }
}

extension SvnService: LogProviding {}
