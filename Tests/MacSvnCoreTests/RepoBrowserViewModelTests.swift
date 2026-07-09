import Foundation
import XCTest
@testable import MacSvnCore

final class RepoBrowserViewModelTests: XCTestCase {
    @MainActor
    func testLoadChildrenStoresEntriesByUrlAndUsesImmediateDepth() async {
        let provider = FakeRepoListProvider(result: .success([
            RemoteEntry(
                name: "trunk",
                path: "trunk",
                kind: .directory,
                size: nil,
                revision: Revision(1),
                author: "a",
                date: nil
            )
        ]))
        let viewModel = RepoBrowserViewModel(listProvider: provider)

        await viewModel.loadChildren(of: "file:///repo")
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state(for: "file:///repo"), .loaded)
        XCTAssertEqual(viewModel.children(of: "file:///repo").map(\.name), ["trunk"])
        XCTAssertEqual(calls, [
            RepoListCall(url: "file:///repo", depth: .immediates, auth: nil)
        ])
    }

    @MainActor
    func testLoadChildrenFailureStoresError() async {
        let provider = FakeRepoListProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = RepoBrowserViewModel(listProvider: provider)

        await viewModel.loadChildren(of: "file:///repo")

        XCTAssertEqual(viewModel.state(for: "file:///repo"), .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.children(of: "file:///repo"), [])
    }

    @MainActor
    func testPreviewTextFileFetchesCatDataAndDecodesUtf8() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data("中文内容\n".utf8))
        )
        let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider)
        let entry = RemoteEntry(
            name: "中文文件.txt",
            path: "中文文件.txt",
            kind: .file,
            size: 13,
            revision: Revision(2),
            author: nil,
            date: nil
        )

        await viewModel.preview(entry: entry, baseURL: "file:///repo/trunk")
        let calls = await provider.recordedCatCalls()

        XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/中文文件.txt"), .loaded("中文内容\n"))
        XCTAssertEqual(calls, [
            RepoCatCall(
                url: "file:///repo/trunk/中文文件.txt",
                revision: nil,
                sizeLimit: RepoBrowserViewModel.defaultPreviewSizeLimit,
                auth: nil
            )
        ])
    }

    @MainActor
    func testPreviewRejectsDirectoriesAndKnownOversizedFilesBeforeCat() async {
        let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
        let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider)

        await viewModel.preview(
            entry: RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil),
            baseURL: "file:///repo/trunk"
        )
        await viewModel.preview(
            entry: RemoteEntry(
                name: "big.txt",
                path: "big.txt",
                kind: .file,
                size: RepoBrowserViewModel.defaultPreviewSizeLimit + 1,
                revision: nil,
                author: nil,
                date: nil
            ),
            baseURL: "file:///repo/trunk"
        )
        let calls = await provider.recordedCatCalls()

        XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/src"), .unsupported("directory"))
        XCTAssertEqual(
            viewModel.previewState(for: "file:///repo/trunk/big.txt"),
            .tooLarge(
                limit: RepoBrowserViewModel.defaultPreviewSizeLimit,
                actual: RepoBrowserViewModel.defaultPreviewSizeLimit + 1
            )
        )
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testPreviewRejectsBinaryDataFromCat() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data([0x68, 0x00, 0x69]))
        )
        let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider)
        let entry = RemoteEntry(name: "image.bin", path: "image.bin", kind: .file, size: 3, revision: nil, author: nil, date: nil)

        await viewModel.preview(entry: entry, baseURL: "file:///repo/trunk")

        XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/image.bin"), .unsupported("binary"))
    }

    @MainActor
    func testPreviewMapsProviderFileTooLargeAndOtherErrors() async {
        let tooLargeProvider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .failure(SvnError.fileTooLarge(limit: 5, actual: 6))
        )
        let errorProvider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .failure(SvnError.network(detail: "offline"))
        )
        let tooLargeViewModel = RepoBrowserViewModel(listProvider: tooLargeProvider, previewProvider: tooLargeProvider)
        let errorViewModel = RepoBrowserViewModel(listProvider: errorProvider, previewProvider: errorProvider)
        let entry = RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: nil, revision: nil, author: nil, date: nil)

        await tooLargeViewModel.preview(entry: entry, baseURL: "file:///repo/trunk")
        await errorViewModel.preview(entry: entry, baseURL: "file:///repo/trunk")

        XCTAssertEqual(tooLargeViewModel.previewState(for: "file:///repo/trunk/README.txt"), .tooLarge(limit: 5, actual: 6))
        XCTAssertEqual(
            errorViewModel.previewState(for: "file:///repo/trunk/README.txt"),
            .error(String(describing: SvnError.network(detail: "offline")))
        )
    }

    @MainActor
    func testLoadBookmarksStoresBookmarkList() async {
        let bookmark = repoBookmark(name: "Main", url: "file:///repo", username: "u")
        let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
        let manager = FakeRepoBookmarkManager(bookmarks: [bookmark])
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            bookmarkManager: manager
        )

        await viewModel.loadBookmarks()

        XCTAssertEqual(viewModel.bookmarks, [bookmark])
        XCTAssertEqual(viewModel.bookmarkState, .loaded)
    }

    @MainActor
    func testAddAndRemoveBookmarkRefreshesViewModelState() async {
        let bookmark = repoBookmark(name: "Main", url: "file:///repo", username: nil)
        let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
        let manager = FakeRepoBookmarkManager(bookmarks: [], addResult: bookmark)
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            bookmarkManager: manager
        )

        await viewModel.addBookmark(url: "file:///repo", name: "Main", username: nil)
        await viewModel.removeBookmark(id: bookmark.id)
        let addCalls = await manager.recordedAddCalls()
        let removeCalls = await manager.recordedRemoveCalls()

        XCTAssertEqual(addCalls, [RepoBookmarkAddCall(url: "file:///repo", name: "Main", username: nil)])
        XCTAssertEqual(removeCalls, [bookmark.id])
        XCTAssertEqual(viewModel.bookmarks, [])
        XCTAssertEqual(viewModel.bookmarkState, .loaded)
    }

    @MainActor
    func testBookmarkFailureStoresError() async {
        let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
        let manager = FakeRepoBookmarkManager(bookmarks: [], loadError: RepoBookmarkStoreError.emptyURL)
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            bookmarkManager: manager
        )

        await viewModel.loadBookmarks()

        XCTAssertEqual(viewModel.bookmarkState, .error(String(describing: RepoBookmarkStoreError.emptyURL)))
    }

    private func repoBookmark(name: String, url: String, username: String?) -> RepoBookmark {
        RepoBookmark(
            id: UUID(),
            name: name,
            url: url,
            username: username,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private struct RepoListCall: Equatable, Sendable {
    let url: String
    let depth: SvnDepth
    let auth: Credential?
}

private struct RepoCatCall: Equatable, Sendable {
    let url: String
    let revision: Revision?
    let sizeLimit: Int
    let auth: Credential?
}

private struct RepoBookmarkAddCall: Equatable, Sendable {
    let url: String
    let name: String?
    let username: String?
}

private actor FakeRepoListProvider: RepoListProviding {
    private let result: Result<[RemoteEntry], Error>
    private var calls: [RepoListCall] = []

    init(result: Result<[RemoteEntry], Error>) {
        self.result = result
    }

    func recordedCalls() -> [RepoListCall] {
        calls
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        calls.append(RepoListCall(url: url, depth: depth, auth: auth))
        return try result.get()
    }
}

private actor FakeRepoBrowserProvider: RepoListProviding, RepoPreviewProviding {
    private let listResult: Result<[RemoteEntry], Error>
    private let catResult: Result<Data, Error>
    private var listCalls: [RepoListCall] = []
    private var catCalls: [RepoCatCall] = []

    init(listResult: Result<[RemoteEntry], Error>, catResult: Result<Data, Error>) {
        self.listResult = listResult
        self.catResult = catResult
    }

    func recordedListCalls() -> [RepoListCall] {
        listCalls
    }

    func recordedCatCalls() -> [RepoCatCall] {
        catCalls
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        listCalls.append(RepoListCall(url: url, depth: depth, auth: auth))
        return try listResult.get()
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        catCalls.append(RepoCatCall(url: url, revision: revision, sizeLimit: sizeLimit, auth: auth))
        return try catResult.get()
    }
}

private actor FakeRepoBookmarkManager: RepoBookmarkManaging {
    private var storedBookmarks: [RepoBookmark]
    private let addResult: RepoBookmark?
    private let loadError: Error?
    private var addCalls: [RepoBookmarkAddCall] = []
    private var removeCalls: [UUID] = []

    init(bookmarks: [RepoBookmark], addResult: RepoBookmark? = nil, loadError: Error? = nil) {
        self.storedBookmarks = bookmarks
        self.addResult = addResult
        self.loadError = loadError
    }

    func recordedAddCalls() -> [RepoBookmarkAddCall] {
        addCalls
    }

    func recordedRemoveCalls() -> [UUID] {
        removeCalls
    }

    func loadBookmarks() async throws -> [RepoBookmark] {
        if let loadError {
            throw loadError
        }
        return storedBookmarks
    }

    func addBookmark(url: String, name: String?, username: String?) async throws -> RepoBookmark {
        addCalls.append(RepoBookmarkAddCall(url: url, name: name, username: username))
        let bookmark = addResult ?? RepoBookmark(
            id: UUID(),
            name: name ?? url,
            url: url,
            username: username,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
        storedBookmarks.append(bookmark)
        return bookmark
    }

    func removeBookmark(id: UUID) async throws {
        removeCalls.append(id)
        storedBookmarks.removeAll { $0.id == id }
    }
}
