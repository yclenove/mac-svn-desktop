import Foundation
import Observation

public protocol LogProviding: Sendable {
    /// - Parameter stopOnCopy: 对应 `svn log --stop-on-copy`（L20）。
    func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry]
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
    /// 防止 stop-on-copy / 刷新并发重入导致分页游标错乱。
    private var loadGeneration = 0

    /// 是否在拷贝点停止（`--stop-on-copy`）。变更后需重新 `loadInitial`。
    public var stopOnCopy: Bool = false

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
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        entries = []
        hasMore = false
        nextFromRevision = nil

        do {
            let loadedEntries = try await fetchLog(from: revision, batch: batchSize)
            guard generation == loadGeneration else { return }
            entries = loadedEntries
            updatePagination(from: loadedEntries, pageSize: batchSize)
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            entries = []
            hasMore = false
            nextFromRevision = nil
            state = .error(String(describing: error))
        }
    }

    /// Tortoise「Next 100」：再拉一批。
    public func loadMore() async {
        guard hasMore, let nextFromRevision, !isLoading else {
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        state = .loadingMore

        do {
            let loadedEntries = try await fetchLog(from: nextFromRevision, batch: batchSize)
            guard generation == loadGeneration else { return }
            entries += loadedEntries
            updatePagination(from: loadedEntries, pageSize: batchSize)
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .error(String(describing: error))
        }
    }

    /// Tortoise「Show All」：循环拉取直至无更多；单次上限防止失控。
    public func loadAll(maxPages: Int = 500) async {
        guard !isLoading else { return }
        if state == .idle {
            return
        }
        var pages = 0
        while hasMore, pages < maxPages {
            pages += 1
            await loadMore()
            if case .error = state {
                return
            }
        }
    }

    private func fetchLog(from revision: Revision, batch: Int) async throws -> [LogEntry] {
        try await logProvider.log(
            wc: workingCopy,
            target: target,
            from: revision,
            batch: batch,
            verbose: true,
            stopOnCopy: stopOnCopy
        )
    }

    private func updatePagination(from loadedEntries: [LogEntry], pageSize: Int) {
        guard loadedEntries.count == pageSize,
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
