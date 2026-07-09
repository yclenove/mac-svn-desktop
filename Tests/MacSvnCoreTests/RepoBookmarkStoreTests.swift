import Foundation
import XCTest
@testable import MacSvnCore

final class RepoBookmarkStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testLoadMissingFileReturnsEmptyBookmarks() async throws {
        let store = makeStore()

        let bookmarks = try await store.load()

        XCTAssertEqual(bookmarks, [])
    }

    func testAddBookmarkPersistsAndReloads() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)

        let bookmark = try await store.addBookmark(
            url: "https://svn.example.com/repo/trunk",
            name: "Main Repo",
            username: "yangchao"
        )

        XCTAssertEqual(bookmark.name, "Main Repo")
        XCTAssertEqual(bookmark.url, "https://svn.example.com/repo/trunk")
        XCTAssertEqual(bookmark.username, "yangchao")

        let reloadedStore = makeStore(root: root)
        let reloaded = try await reloadedStore.load()
        XCTAssertEqual(reloaded, [bookmark])
    }

    func testAddBookmarkWithExistingURLUpdatesRecordInsteadOfDuplicating() async throws {
        let store = makeStore()

        let first = try await store.addBookmark(url: "file:///repo", name: "Old", username: nil)
        let second = try await store.addBookmark(url: "file:///repo", name: "New", username: "u")
        let bookmarks = await store.bookmarks()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.name, "New")
        XCTAssertEqual(bookmarks.first?.username, "u")
    }

    func testRemoveBookmarkDeletesOnlyMatchingRecord() async throws {
        let store = makeStore()
        let first = try await store.addBookmark(url: "file:///one", name: nil, username: nil)
        let second = try await store.addBookmark(url: "file:///two", name: nil, username: nil)

        try await store.removeBookmark(id: first.id)
        let bookmarks = await store.bookmarks()

        XCTAssertEqual(bookmarks, [second])
    }

    func testAddBookmarkRejectsEmptyURL() async {
        let store = makeStore()

        do {
            _ = try await store.addBookmark(url: "  ", name: nil, username: nil)
            XCTFail("Expected empty URL error")
        } catch let error as RepoBookmarkStoreError {
            XCTAssertEqual(error, .emptyURL)
        } catch {
            XCTFail("Expected RepoBookmarkStoreError, got \(error)")
        }
    }

    private func makeStore(root: URL? = nil) -> RepoBookmarkStore {
        let root = root ?? temporaryRoot()
        return RepoBookmarkStore(fileURL: root.appendingPathComponent("bookmarks.json"))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreRepoBookmarks-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
