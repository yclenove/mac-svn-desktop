import Foundation
import Observation

public protocol RevisionGraphProviding: Sendable {
    func info(wc: URL, target: String) async throws -> SvnInfo
    func remoteLogFromHead(
        url: String,
        batch: Int,
        verbose: Bool,
        auth: Credential?
    ) async throws -> [LogEntry]
    func remoteLog(
        url: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        auth: Credential?
    ) async throws -> [LogEntry]
    func repositoryDiff(
        wc: URL,
        oldURL: String,
        oldRevision: Revision,
        newURL: String,
        newRevision: Revision,
        auth: Credential?
    ) async throws -> String
}

extension SvnService: RevisionGraphProviding {}

public enum RevisionGraphViewState: Equatable, Sendable {
    case idle
    case loading
    case loadingMore
    case loaded
    case error(String)
}

public enum RevisionGraphDiffState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class RevisionGraphViewModel {
    private let workingCopy: URL
    private let batchSize: Int
    private let provider: any RevisionGraphProviding
    public private(set) var settings: RevisionGraphSettings
    private var nextFromRevision: Revision?
    private var loadGeneration = 0
    private var diffGeneration = 0

    public private(set) var state: RevisionGraphViewState = .idle
    public private(set) var repositoryRoot = ""
    public private(set) var entries: [LogEntry] = []
    public private(set) var snapshot = RevisionGraphSnapshot()
    public private(set) var visibleSnapshot = RevisionGraphSnapshot()
    public private(set) var hasMore = false
    public private(set) var diffState: RevisionGraphDiffState = .idle
    public private(set) var diffText: String?
    public var pruning = RevisionGraphPruning() {
        didSet { visibleSnapshot = snapshot.pruned(by: pruning) }
    }
    public var viewMode: RevisionGraphViewMode = .topology

    public init(
        workingCopy: URL,
        batchSize: Int,
        settings: RevisionGraphSettings,
        provider: any RevisionGraphProviding
    ) {
        self.workingCopy = workingCopy
        self.batchSize = max(1, batchSize)
        self.settings = settings
        self.provider = provider
    }

    public var isLoading: Bool {
        state == .loading || state == .loadingMore
    }

    public func loadInitial() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        entries = []
        snapshot = RevisionGraphSnapshot()
        visibleSnapshot = RevisionGraphSnapshot()
        hasMore = false
        nextFromRevision = nil

        do {
            let info = try await provider.info(wc: workingCopy, target: "")
            let root = info.repositoryRoot ?? info.url
            let loaded = try await provider.remoteLogFromHead(
                url: root,
                batch: batchSize,
                verbose: true,
                auth: nil
            )
            guard generation == loadGeneration else { return }
            repositoryRoot = root
            entries = loaded
            updatePagination(from: loaded)
            rebuild()
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .error(String(describing: error))
        }
    }

    public func loadMore() async {
        guard let nextFromRevision, hasMore, !isLoading, !repositoryRoot.isEmpty else { return }
        loadGeneration += 1
        let generation = loadGeneration
        state = .loadingMore
        do {
            let loaded = try await provider.remoteLog(
                url: repositoryRoot,
                from: nextFromRevision,
                batch: batchSize,
                verbose: true,
                auth: nil
            )
            guard generation == loadGeneration else { return }
            let existingRevisions = Set(entries.map(\.revision))
            entries += loaded.filter { !existingRevisions.contains($0.revision) }
            updatePagination(from: loaded)
            rebuild()
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .error(String(describing: error))
        }
    }

    public func loadAll(maxPages: Int = 200) async {
        var page = 0
        while hasMore, page < maxPages {
            page += 1
            await loadMore()
            if case .error = state { return }
        }
    }

    public func apply(settings: RevisionGraphSettings) {
        self.settings = settings
        rebuild()
    }

    public func loadDiff(for nodeID: String) async {
        diffGeneration += 1
        let generation = diffGeneration
        guard let node = snapshot.nodes.first(where: { $0.id == nodeID }) else {
            diffState = .error("找不到选中的修订图节点")
            diffText = nil
            return
        }
        let source: RevisionGraphNode?
        if let sourcePath = node.sourcePath, let sourceRevision = node.sourceRevision {
            source = snapshot.nodes.first {
                $0.path == sourcePath && $0.revision == sourceRevision
            } ?? RevisionGraphNode(
                path: sourcePath,
                revision: sourceRevision,
                category: node.sourceCategory ?? .unclassified,
                author: "",
                date: nil,
                message: "",
                changedPaths: [],
                isSynthetic: true
            )
        } else {
            source = snapshot.nodes
                .filter { $0.path == node.path && $0.revision.value < node.revision.value }
                .max(by: { $0.revision.value < $1.revision.value })
        }
        guard let source,
              let oldURL = RevisionGraphNodeActionPolicy.repositoryURL(
                root: repositoryRoot,
                path: source.path
              ),
              let newURL = RevisionGraphNodeActionPolicy.repositoryURL(
                root: repositoryRoot,
                path: node.path
              ) else {
            diffState = .error("该节点没有可比较的前置修订")
            diffText = nil
            return
        }

        diffState = .loading
        diffText = nil
        do {
            let diff = try await provider.repositoryDiff(
                wc: workingCopy,
                oldURL: oldURL,
                oldRevision: source.revision,
                newURL: newURL,
                newRevision: node.revision,
                auth: nil
            )
            guard generation == diffGeneration else { return }
            diffText = DiffPerformanceLimits.truncatedDisplayText(diff)
            diffState = .loaded
        } catch {
            guard generation == diffGeneration else { return }
            diffState = .error(String(describing: error))
        }
    }

    private func updatePagination(from loaded: [LogEntry]) {
        guard loaded.count == batchSize,
              let minimum = loaded.map(\.revision.value).min(),
              minimum > 0 else {
            hasMore = false
            nextFromRevision = nil
            return
        }
        hasMore = true
        nextFromRevision = Revision(minimum - 1)
    }

    private func rebuild() {
        snapshot = RevisionGraphBuilder.build(entries: entries, settings: settings)
        visibleSnapshot = snapshot.pruned(by: pruning)
    }
}
