import Foundation
import Observation

public protocol RepoListProviding: Sendable {
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
}

public protocol RepoPreviewProviding: Sendable {
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
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

@MainActor
@Observable
public final class RepoBrowserViewModel {
    public static let defaultPreviewSizeLimit = 5 * 1024 * 1024

    private let listProvider: any RepoListProviding
    private let previewProvider: (any RepoPreviewProviding)?
    private let bookmarkManager: (any RepoBookmarkManaging)?

    private var statesByURL: [String: RepoBrowserState] = [:]
    private var childrenByURL: [String: [RemoteEntry]] = [:]
    private var previewStatesByURL: [String: RepoPreviewState] = [:]
    public private(set) var bookmarks: [RepoBookmark] = []
    public private(set) var bookmarkState: RepoBookmarkState = .idle

    public init(
        listProvider: any RepoListProviding,
        previewProvider: (any RepoPreviewProviding)? = nil,
        bookmarkManager: (any RepoBookmarkManaging)? = nil
    ) {
        self.listProvider = listProvider
        self.previewProvider = previewProvider ?? (listProvider as? any RepoPreviewProviding)
        self.bookmarkManager = bookmarkManager
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

    private func remoteURL(baseURL: String, entryPath: String) -> String {
        if baseURL.hasSuffix("/") {
            return baseURL + entryPath
        }

        return baseURL + "/" + entryPath
    }
}

extension SvnService: RepoListProviding {}
extension SvnService: RepoPreviewProviding {}
