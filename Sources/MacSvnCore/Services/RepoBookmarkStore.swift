import Foundation

public enum RepoBookmarkStoreError: Error, Equatable, Sendable {
    case emptyURL
}

public protocol RepoBookmarkManaging: Sendable {
    func loadBookmarks() async throws -> [RepoBookmark]
    func addBookmark(url: String, name: String?, username: String?) async throws -> RepoBookmark
    func removeBookmark(id: UUID) async throws
}

public actor RepoBookmarkStore: RepoBookmarkManaging {
    private let store: PersistenceStore<RepoBookmarkListFile>
    private var cachedBookmarks: [RepoBookmark] = []

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: RepoBookmarkListFile())
    }

    public func load() throws -> [RepoBookmark] {
        let file = try store.load()
        cachedBookmarks = file.bookmarks
        return cachedBookmarks
    }

    public func loadBookmarks() async throws -> [RepoBookmark] {
        try load()
    }

    public func bookmarks() -> [RepoBookmark] {
        cachedBookmarks
    }

    @discardableResult
    public func addBookmark(url: String, name: String? = nil, username: String? = nil) async throws -> RepoBookmark {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw RepoBookmarkStoreError.emptyURL
        }

        var bookmarks = try load()
        let now = Self.currentPersistableDate()

        if let index = bookmarks.firstIndex(where: { $0.url == trimmedURL }) {
            bookmarks[index].name = resolvedName(name: name, url: trimmedURL)
            bookmarks[index].username = username
            bookmarks[index].lastOpenedAt = now
            cachedBookmarks = bookmarks
            try store.save(RepoBookmarkListFile(bookmarks: bookmarks))
            return bookmarks[index]
        }

        let bookmark = RepoBookmark(
            id: UUID(),
            name: resolvedName(name: name, url: trimmedURL),
            url: trimmedURL,
            username: username,
            addedAt: now,
            lastOpenedAt: now
        )
        bookmarks.append(bookmark)
        cachedBookmarks = bookmarks
        try store.save(RepoBookmarkListFile(bookmarks: bookmarks))
        return bookmark
    }

    public func removeBookmark(id: UUID) async throws {
        var bookmarks = try load()
        bookmarks.removeAll { $0.id == id }
        cachedBookmarks = bookmarks
        try store.save(RepoBookmarkListFile(bookmarks: bookmarks))
    }

    private func resolvedName(name: String?, url: String) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        if let lastPathComponent = URL(string: url)?.lastPathComponent, !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        return url
    }

    private static func currentPersistableDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}
