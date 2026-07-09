import Foundation
import Observation

public protocol RepoListProviding: Sendable {
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
}

public protocol RepoPreviewProviding: Sendable {
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
}

public protocol RepoLogProviding: Sendable {
    func remoteLog(url: String, from: Revision, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
}

public protocol RepoRemoteOperationProviding: Sendable {
    func mkdir(url: String, message: String, auth: Credential?) async throws -> Revision
    func delete(url: String, message: String, auth: Credential?) async throws -> Revision
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
    func move(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
}

public enum RepoBrowserState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public enum RepoPreviewState: Equatable, Sendable {
    case idle
    case loading
    case loaded(String)
    case tooLarge(limit: Int, actual: Int)
    case unsupported(String)
    case error(String)
}

public enum RepoBookmarkState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public enum RepoLogState: Equatable, Sendable {
    case idle
    case loading
    case loadingMore
    case loaded
    case error(String)
}

public enum RepoRemoteOperation: Equatable, Sendable {
    case mkdir
    case delete
    case copy
    case move
}

public enum RepoRemoteOperationState: Equatable, Sendable {
    case idle
    case running(RepoRemoteOperation)
    case completed(RepoRemoteOperation, revision: Revision)
    case error(String)
}

@MainActor
@Observable
public final class RepoBrowserViewModel {
    public static let defaultPreviewSizeLimit = 5 * 1024 * 1024

    private let listProvider: any RepoListProviding
    private let previewProvider: (any RepoPreviewProviding)?
    private let logProvider: (any RepoLogProviding)?
    private let remoteOperationProvider: (any RepoRemoteOperationProviding)?
    private let bookmarkManager: (any RepoBookmarkManaging)?
    private let logBatchSize: Int

    private var statesByURL: [String: RepoBrowserState] = [:]
    private var childrenByURL: [String: [RemoteEntry]] = [:]
    private var previewStatesByURL: [String: RepoPreviewState] = [:]
    private var logStatesByURL: [String: RepoLogState] = [:]
    private var logEntriesByURL: [String: [LogEntry]] = [:]
    private var nextLogRevisionByURL: [String: Revision] = [:]
    private var hasMoreLogByURL: [String: Bool] = [:]
    public private(set) var bookmarks: [RepoBookmark] = []
    public private(set) var bookmarkState: RepoBookmarkState = .idle
    public private(set) var remoteOperationState: RepoRemoteOperationState = .idle

    public init(
        listProvider: any RepoListProviding,
        previewProvider: (any RepoPreviewProviding)? = nil,
        bookmarkManager: (any RepoBookmarkManaging)? = nil,
        logProvider: (any RepoLogProviding)? = nil,
        remoteOperationProvider: (any RepoRemoteOperationProviding)? = nil,
        logBatchSize: Int = 100
    ) {
        self.listProvider = listProvider
        self.previewProvider = previewProvider ?? (listProvider as? any RepoPreviewProviding)
        self.logProvider = logProvider ?? (listProvider as? any RepoLogProviding)
        self.remoteOperationProvider = remoteOperationProvider ?? (listProvider as? any RepoRemoteOperationProviding)
        self.bookmarkManager = bookmarkManager
        self.logBatchSize = max(1, logBatchSize)
    }

    public func state(for url: String) -> RepoBrowserState {
        statesByURL[url, default: .idle]
    }

    public func children(of url: String) -> [RemoteEntry] {
        childrenByURL[url, default: []]
    }

    public func previewState(for url: String) -> RepoPreviewState {
        previewStatesByURL[url, default: .idle]
    }

    public func logState(for url: String) -> RepoLogState {
        logStatesByURL[url, default: .idle]
    }

    public func logEntries(for url: String) -> [LogEntry] {
        logEntriesByURL[url, default: []]
    }

    public func hasMoreLog(for url: String) -> Bool {
        hasMoreLogByURL[url, default: false]
    }

    public func loadChildren(of url: String, auth: Credential? = nil) async {
        statesByURL[url] = .loading

        do {
            childrenByURL[url] = try await listProvider.list(url: url, depth: .immediates, auth: auth)
            statesByURL[url] = .loaded
        } catch {
            childrenByURL[url] = []
            statesByURL[url] = .error(String(describing: error))
        }
    }

    public func preview(entry: RemoteEntry, baseURL: String, auth: Credential? = nil) async {
        let url = remoteURL(baseURL: baseURL, entryPath: entry.path)

        guard entry.kind == .file else {
            previewStatesByURL[url] = .unsupported("directory")
            return
        }

        if let size = entry.size, size > Self.defaultPreviewSizeLimit {
            previewStatesByURL[url] = .tooLarge(limit: Self.defaultPreviewSizeLimit, actual: size)
            return
        }

        guard let previewProvider else {
            previewStatesByURL[url] = .error("previewUnavailable")
            return
        }

        previewStatesByURL[url] = .loading

        do {
            let data = try await previewProvider.cat(
                url: url,
                revision: nil,
                sizeLimit: Self.defaultPreviewSizeLimit,
                auth: auth
            )

            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                previewStatesByURL[url] = .unsupported("binary")
                return
            }

            previewStatesByURL[url] = .loaded(text)
        } catch SvnError.fileTooLarge(let limit, let actual) {
            previewStatesByURL[url] = .tooLarge(limit: limit, actual: actual)
        } catch SvnError.binaryFile {
            previewStatesByURL[url] = .unsupported("binary")
        } catch {
            previewStatesByURL[url] = .error(String(describing: error))
        }
    }

    public func loadLog(entry: RemoteEntry, baseURL: String, from revision: Revision, auth: Credential? = nil) async {
        let url = remoteURL(baseURL: baseURL, entryPath: entry.path)

        guard let logProvider else {
            logStatesByURL[url] = .error("logUnavailable")
            return
        }

        logStatesByURL[url] = .loading
        logEntriesByURL[url] = []
        nextLogRevisionByURL[url] = nil
        hasMoreLogByURL[url] = false

        do {
            let entries = try await logProvider.remoteLog(
                url: url,
                from: revision,
                batch: logBatchSize,
                verbose: true,
                auth: auth
            )
            logEntriesByURL[url] = entries
            updateLogPagination(for: url, loadedEntries: entries)
            logStatesByURL[url] = .loaded
        } catch {
            logEntriesByURL[url] = []
            nextLogRevisionByURL[url] = nil
            hasMoreLogByURL[url] = false
            logStatesByURL[url] = .error(String(describing: error))
        }
    }

    public func loadMoreLog(entry: RemoteEntry, baseURL: String, auth: Credential? = nil) async {
        let url = remoteURL(baseURL: baseURL, entryPath: entry.path)

        guard hasMoreLogByURL[url, default: false],
              let nextRevision = nextLogRevisionByURL[url],
              !isLoadingLog(url: url)
        else {
            return
        }

        guard let logProvider else {
            logStatesByURL[url] = .error("logUnavailable")
            return
        }

        logStatesByURL[url] = .loadingMore

        do {
            let entries = try await logProvider.remoteLog(
                url: url,
                from: nextRevision,
                batch: logBatchSize,
                verbose: true,
                auth: auth
            )
            logEntriesByURL[url, default: []] += entries
            updateLogPagination(for: url, loadedEntries: entries)
            logStatesByURL[url] = .loaded
        } catch {
            logStatesByURL[url] = .error(String(describing: error))
        }
    }

    public func createDirectory(
        named name: String,
        in parentURL: String,
        message: String,
        auth: Credential? = nil
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            remoteOperationState = .error("emptyRemoteEntryName")
            return
        }

        let url = remoteURL(baseURL: parentURL, entryPath: trimmedName)
        await performRemoteOperation(.mkdir, refreshURL: parentURL, auth: auth) { provider in
            try await provider.mkdir(url: url, message: message, auth: auth)
        }
    }

    public func delete(
        entry: RemoteEntry,
        baseURL: String,
        message: String,
        auth: Credential? = nil
    ) async {
        let url = remoteURL(baseURL: baseURL, entryPath: entry.path)
        await performRemoteOperation(.delete, refreshURL: baseURL, auth: auth) { provider in
            try await provider.delete(url: url, message: message, auth: auth)
        }
    }

    public func copy(
        entry: RemoteEntry,
        baseURL: String,
        to destinationURL: String,
        message: String,
        auth: Credential? = nil
    ) async {
        let sourceURL = remoteURL(baseURL: baseURL, entryPath: entry.path)
        await performRemoteOperation(.copy, refreshURL: baseURL, auth: auth) { provider in
            try await provider.copy(source: sourceURL, destination: destinationURL, message: message, auth: auth)
        }
    }

    public func move(
        entry: RemoteEntry,
        baseURL: String,
        to destinationURL: String,
        message: String,
        auth: Credential? = nil
    ) async {
        let sourceURL = remoteURL(baseURL: baseURL, entryPath: entry.path)
        await performRemoteOperation(.move, refreshURL: baseURL, auth: auth) { provider in
            try await provider.move(source: sourceURL, destination: destinationURL, message: message, auth: auth)
        }
    }

    public func loadBookmarks() async {
        guard let bookmarkManager else {
            bookmarkState = .error("bookmarksUnavailable")
            return
        }

        bookmarkState = .loading

        do {
            bookmarks = try await bookmarkManager.loadBookmarks()
            bookmarkState = .loaded
        } catch {
            bookmarkState = .error(String(describing: error))
        }
    }

    public func addBookmark(url: String, name: String? = nil, username: String? = nil) async {
        guard let bookmarkManager else {
            bookmarkState = .error("bookmarksUnavailable")
            return
        }

        bookmarkState = .loading

        do {
            let bookmark = try await bookmarkManager.addBookmark(url: url, name: name, username: username)
            bookmarks.removeAll { $0.id == bookmark.id }
            bookmarks.append(bookmark)
            bookmarkState = .loaded
        } catch {
            bookmarkState = .error(String(describing: error))
        }
    }

    public func removeBookmark(id: UUID) async {
        guard let bookmarkManager else {
            bookmarkState = .error("bookmarksUnavailable")
            return
        }

        bookmarkState = .loading

        do {
            try await bookmarkManager.removeBookmark(id: id)
            bookmarks.removeAll { $0.id == id }
            bookmarkState = .loaded
        } catch {
            bookmarkState = .error(String(describing: error))
        }
    }

    private func performRemoteOperation(
        _ operation: RepoRemoteOperation,
        refreshURL: String,
        auth: Credential?,
        body: (any RepoRemoteOperationProviding) async throws -> Revision
    ) async {
        guard let remoteOperationProvider else {
            remoteOperationState = .error("remoteOperationsUnavailable")
            return
        }

        remoteOperationState = .running(operation)

        do {
            let revision = try await body(remoteOperationProvider)
            await loadChildren(of: refreshURL, auth: auth)
            remoteOperationState = .completed(operation, revision: revision)
        } catch {
            remoteOperationState = .error(String(describing: error))
        }
    }

    private func remoteURL(baseURL: String, entryPath: String) -> String {
        if baseURL.hasSuffix("/") {
            return baseURL + entryPath
        }

        return baseURL + "/" + entryPath
    }

    private func isLoadingLog(url: String) -> Bool {
        let state = logStatesByURL[url, default: .idle]
        return state == .loading || state == .loadingMore
    }

    private func updateLogPagination(for url: String, loadedEntries: [LogEntry]) {
        guard loadedEntries.count == logBatchSize,
              let lowestRevision = loadedEntries.map(\.revision.value).min(),
              lowestRevision > 0
        else {
            hasMoreLogByURL[url] = false
            nextLogRevisionByURL[url] = nil
            return
        }

        hasMoreLogByURL[url] = true
        nextLogRevisionByURL[url] = Revision(lowestRevision - 1)
    }
}

extension SvnService: RepoListProviding {}
extension SvnService: RepoPreviewProviding {}
extension SvnService: RepoLogProviding {}
extension SvnService: RepoRemoteOperationProviding {}
