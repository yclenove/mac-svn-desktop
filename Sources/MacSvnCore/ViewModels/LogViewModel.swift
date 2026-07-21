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

public enum LogDataSource: Equatable, Sendable {
    case live
    case offlineCache(updatedAt: Date)
    case fallbackCache(updatedAt: Date, reason: String)
}

@MainActor
@Observable
public final class LogViewModel {
    private let workingCopy: URL
    private let target: String
    private let batchSize: Int
    private let logProvider: any LogProviding
    private let logCache: (any LogCaching)?
    private let cacheIdentity: LogCacheIdentity?
    private let cachePolicy: LogCachePolicy
    private var nextFromRevision: Revision?
    /// 防止 stop-on-copy / 刷新并发重入导致分页游标错乱。
    private var loadGeneration = 0

    /// 是否在拷贝点停止（`--stop-on-copy`）。变更后需重新 `loadInitial`。
    public var stopOnCopy: Bool = false
    /// 强制只读持久化日志，不触发 SVN 网络请求。
    public var offlineMode: Bool = false

    public private(set) var state: LogViewState = .idle
    public private(set) var entries: [LogEntry] = []
    public private(set) var hasMore = false
    public private(set) var dataSource: LogDataSource = .live

    public init(
        workingCopy: URL,
        target: String,
        batchSize: Int,
        logProvider: any LogProviding,
        logCache: (any LogCaching)? = nil,
        cacheIdentity: LogCacheIdentity? = nil,
        cachePolicy: LogCachePolicy = LogCachePolicy()
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.batchSize = max(1, batchSize)
        self.logProvider = logProvider
        self.logCache = logCache
        self.cacheIdentity = cacheIdentity
        self.cachePolicy = cachePolicy.normalized
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
        dataSource = .live

        if offlineMode {
            await loadFromCache(generation: generation)
            return
        }

        do {
            let loadedEntries = try await fetchLog(from: revision, batch: batchSize)
            guard generation == loadGeneration else { return }
            entries = loadedEntries
            updatePagination(from: loadedEntries, pageSize: batchSize)
            dataSource = .live
            state = .loaded
            await saveToCache(loadedEntries)
        } catch {
            guard generation == loadGeneration else { return }
            if await loadFallbackCache(generation: generation, reason: error) {
                return
            }
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
            dataSource = .live
            state = .loaded
            await saveToCache(loadedEntries)
        } catch {
            guard generation == loadGeneration else { return }
            if await loadFallbackCache(generation: generation, reason: error, preserveEntries: true) {
                return
            }
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

    private var currentCacheKey: LogCacheKey? {
        cacheIdentity?.key(stopOnCopy: stopOnCopy)
    }

    private func loadFromCache(generation: Int) async {
        guard let logCache, let key = currentCacheKey, cachePolicy.enabled else {
            state = .error("offlineCacheUnavailable")
            return
        }
        do {
            guard let snapshot = try await logCache.snapshot(
                for: key,
                policy: cachePolicy,
                now: Date()
            ), !snapshot.entries.isEmpty else {
                state = .error("offlineCacheEmpty")
                return
            }
            guard generation == loadGeneration else { return }
            entries = snapshot.entries
            hasMore = false
            nextFromRevision = nil
            dataSource = .offlineCache(updatedAt: snapshot.updatedAt)
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .error(String(describing: error))
        }
    }

    private func loadFallbackCache(
        generation: Int,
        reason: Error,
        preserveEntries: Bool = false
    ) async -> Bool {
        guard isCacheFallbackError(reason),
              let logCache,
              let key = currentCacheKey,
              cachePolicy.enabled else {
            return false
        }
        do {
            guard let snapshot = try await logCache.snapshot(
                for: key,
                policy: cachePolicy,
                now: Date()
            ), !snapshot.entries.isEmpty else {
                return false
            }
            guard generation == loadGeneration else { return true }
            if preserveEntries {
                var byRevision = Dictionary(uniqueKeysWithValues: entries.map { ($0.revision.value, $0) })
                for entry in snapshot.entries { byRevision[entry.revision.value] = entry }
                entries = byRevision.values.sorted { $0.revision.value > $1.revision.value }
            } else {
                entries = snapshot.entries
            }
            hasMore = false
            nextFromRevision = nil
            dataSource = .fallbackCache(
                updatedAt: snapshot.updatedAt,
                reason: String(describing: reason)
            )
            state = .loaded
            return true
        } catch {
            return false
        }
    }

    private func saveToCache(_ loadedEntries: [LogEntry]) async {
        guard let logCache, let key = currentCacheKey, cachePolicy.enabled else { return }
        try? await logCache.merge(
            entries: loadedEntries,
            for: key,
            policy: cachePolicy,
            now: Date()
        )
    }

    private func isCacheFallbackError(_ error: Error) -> Bool {
        guard let svnError = error as? SvnError else { return false }
        switch svnError {
        case .network, .authentication, .environment:
            return true
        case .outOfDate, .wcLocked, .conflict, .fileTooLarge, .binaryFile,
             .parse, .cancelled, .other:
            return false
        }
    }
}

extension SvnService: LogProviding {}
