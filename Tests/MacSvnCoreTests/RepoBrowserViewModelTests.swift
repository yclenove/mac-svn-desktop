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

        XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/%E4%B8%AD%E6%96%87%E6%96%87%E4%BB%B6.txt"), .loaded("中文内容\n"))
        XCTAssertEqual(calls, [
            RepoCatCall(
                url: "file:///repo/trunk/%E4%B8%AD%E6%96%87%E6%96%87%E4%BB%B6.txt",
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

    @MainActor
    func testLoadLogStoresEntriesAndUsesRemoteEntryUrl() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            logResults: [.success([logEntry(Revision(7)), logEntry(Revision(6))])]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            logProvider: provider,
            logBatchSize: 2
        )
        let entry = RemoteEntry(
            name: "README.txt",
            path: "README.txt",
            kind: .file,
            size: 10,
            revision: Revision(7),
            author: nil,
            date: nil
        )

        await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(7))
        let calls = await provider.recordedLogCalls()

        XCTAssertEqual(viewModel.logState(for: "file:///repo/trunk/README.txt"), .loaded)
        XCTAssertEqual(viewModel.logEntries(for: "file:///repo/trunk/README.txt").map(\.revision), [Revision(7), Revision(6)])
        XCTAssertTrue(viewModel.hasMoreLog(for: "file:///repo/trunk/README.txt"))
        XCTAssertEqual(calls, [
            RepoLogCall(url: "file:///repo/trunk/README.txt", from: Revision(7), batch: 2, verbose: true, auth: nil)
        ])
    }

    @MainActor
    func testLoadMoreLogStartsBeforeLowestLoadedRevisionAndStopsOnShortPage() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            logResults: [
                .success([logEntry(Revision(10)), logEntry(Revision(9))]),
                .success([logEntry(Revision(8))])
            ]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            logProvider: provider,
            logBatchSize: 2
        )
        let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

        await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(10))
        await viewModel.loadMoreLog(entry: entry, baseURL: "file:///repo/trunk")
        let url = "file:///repo/trunk/src"

        XCTAssertEqual(viewModel.logEntries(for: url).map(\.revision), [Revision(10), Revision(9), Revision(8)])
        XCTAssertFalse(viewModel.hasMoreLog(for: url))
    }

    @MainActor
    func testLoadLogFailureStoresErrorAndClearsEntries() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            logResults: [.failure(SvnError.network(detail: "offline"))]
        )
        let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, logProvider: provider)
        let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

        await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(10))

        XCTAssertEqual(
            viewModel.logState(for: "file:///repo/trunk/src"),
            .error(String(describing: SvnError.network(detail: "offline")))
        )
        XCTAssertEqual(viewModel.logEntries(for: "file:///repo/trunk/src"), [])
    }

    @MainActor
    func testRemoteOperationsCallProviderUpdateStateAndRefreshChildren() async throws {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([
                RemoteEntry(name: "docs", path: "docs", kind: .directory, size: nil, revision: Revision(5), author: nil, date: nil)
            ]),
            catResult: .success(Data()),
            remoteOperationResults: [
                .success(Revision(5)),
                .success(Revision(6)),
                .success(Revision(7)),
                .success(Revision(8))
            ]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            remoteOperationProvider: provider
        )
        let entry = RemoteEntry(
            name: "old.txt",
            path: "old.txt",
            kind: .file,
            size: 10,
            revision: Revision(4),
            author: nil,
            date: nil
        )

        await viewModel.createDirectory(named: " docs ", in: "file:///repo/trunk", message: "创建目录：docs")
        await viewModel.delete(entry: entry, baseURL: "file:///repo/trunk", message: "删除旧文件")
        let deleteConfirmation = try XCTUnwrap(viewModel.confirmation)
        await viewModel.confirmRemoteOperation(deleteConfirmation)
        await viewModel.copy(
            entry: entry,
            baseURL: "file:///repo/trunk",
            to: "file:///repo/branches/old.txt",
            message: "复制旧文件"
        )
        await viewModel.move(
            entry: entry,
            baseURL: "file:///repo/trunk",
            to: "file:///repo/trunk/new.txt",
            message: "移动旧文件"
        )
        let moveConfirmation = try XCTUnwrap(viewModel.confirmation)
        await viewModel.confirmRemoteOperation(moveConfirmation)
        let operationCalls = await provider.recordedRemoteOperationCalls()
        let listCalls = await provider.recordedListCalls()

        XCTAssertEqual(viewModel.remoteOperationState, .completed(.move, revision: Revision(8)))
        XCTAssertEqual(viewModel.state(for: "file:///repo/trunk"), .loaded)
        XCTAssertEqual(viewModel.children(of: "file:///repo/trunk").map(\.name), ["docs"])
        XCTAssertEqual(operationCalls, [
            RepoRemoteOperationCall(
                operation: .mkdir,
                source: nil,
                destination: "file:///repo/trunk/docs",
                message: "创建目录：docs",
                auth: nil
            ),
            RepoRemoteOperationCall(
                operation: .delete,
                source: "file:///repo/trunk/old.txt",
                destination: nil,
                message: "删除旧文件",
                auth: nil
            ),
            RepoRemoteOperationCall(
                operation: .copy,
                source: "file:///repo/trunk/old.txt",
                destination: "file:///repo/branches/old.txt",
                message: "复制旧文件",
                auth: nil
            ),
            RepoRemoteOperationCall(
                operation: .move,
                source: "file:///repo/trunk/old.txt",
                destination: "file:///repo/trunk/new.txt",
                message: "移动旧文件",
                auth: nil
            )
        ])
        XCTAssertEqual(
            listCalls,
            Array(repeating: RepoListCall(url: "file:///repo/trunk", depth: .immediates, auth: nil), count: 4)
        )
    }

    @MainActor
    func testRemoteOperationUnavailableAndInvalidDirectoryNameStoreErrors() async {
        let provider = FakeRepoListProvider(result: .success([]))
        let viewModel = RepoBrowserViewModel(listProvider: provider)

        await viewModel.createDirectory(named: "docs", in: "file:///repo/trunk", message: "创建目录")
        XCTAssertEqual(viewModel.remoteOperationState, .error("remoteOperationsUnavailable"))

        let remoteProvider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            remoteOperationResults: [.success(Revision(2))]
        )
        let remoteViewModel = RepoBrowserViewModel(
            listProvider: remoteProvider,
            previewProvider: remoteProvider,
            remoteOperationProvider: remoteProvider
        )

        await remoteViewModel.createDirectory(named: "  ", in: "file:///repo/trunk", message: "创建目录")
        XCTAssertEqual(remoteViewModel.remoteOperationState, .error("emptyRemoteEntryName"))
    }

    @MainActor
    func testDeleteRequiresConfirmationAndCancelDoesNotCallProvider() async {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            remoteOperationResults: [.success(Revision(2))]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            remoteOperationProvider: provider
        )
        let entry = RemoteEntry(
            name: "obsolete.txt",
            path: "obsolete.txt",
            kind: .file,
            size: 4,
            revision: Revision(1),
            author: nil,
            date: nil
        )

        await viewModel.delete(
            entry: entry,
            baseURL: "file:///repo/trunk",
            message: "删除旧文件"
        )

        XCTAssertEqual(
            viewModel.remoteOperationState,
            .confirmationRequired(RepoRemoteWriteConfirmation(
                operation: .delete,
                sourceURL: "file:///repo/trunk/obsolete.txt",
                destinationURL: nil
            ))
        )
        viewModel.cancelRemoteOperationConfirmation()
        let calls = await provider.recordedRemoteOperationCalls()
        XCTAssertEqual(viewModel.remoteOperationState, .idle)
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testRenameRequiresConfirmationThenUsesRemoteMove() async throws {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            remoteOperationResults: [.success(Revision(3))]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            remoteOperationProvider: provider
        )
        let entry = RemoteEntry(
            name: "old.txt",
            path: "old.txt",
            kind: .file,
            size: 4,
            revision: Revision(1),
            author: nil,
            date: nil
        )

        await viewModel.rename(
            entry: entry,
            baseURL: "file:///repo/trunk",
            to: "new.txt",
            message: "重命名"
        )
        XCTAssertEqual(
            viewModel.remoteOperationState,
            .confirmationRequired(RepoRemoteWriteConfirmation(
                operation: .rename,
                sourceURL: "file:///repo/trunk/old.txt",
                destinationURL: "file:///repo/trunk/new.txt"
            ))
        )

        let confirmation = try XCTUnwrap(viewModel.confirmation)
        await viewModel.confirmRemoteOperation(confirmation)

        let calls = await provider.recordedRemoteOperationCalls()
        XCTAssertEqual(viewModel.remoteOperationState, .completed(.rename, revision: Revision(3)))
        XCTAssertEqual(calls, [
            RepoRemoteOperationCall(
                operation: .move,
                source: "file:///repo/trunk/old.txt",
                destination: "file:///repo/trunk/new.txt",
                message: "重命名",
                auth: nil
            )
        ])
    }

    @MainActor
    func testStaleRemoteConfirmationCannotExecuteAfterPendingOperationChanges() async throws {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            remoteOperationResults: [.success(Revision(4))]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            remoteOperationProvider: provider
        )
        let first = RemoteEntry(name: "first.txt", path: "first.txt", kind: .file, size: 1, revision: nil, author: nil, date: nil)
        let second = RemoteEntry(name: "second.txt", path: "second.txt", kind: .file, size: 1, revision: nil, author: nil, date: nil)

        await viewModel.delete(entry: first, baseURL: "file:///repo/trunk", message: "删除 first")
        let stale = try XCTUnwrap(viewModel.confirmation)
        await viewModel.delete(entry: second, baseURL: "file:///repo/trunk", message: "删除 second")
        await viewModel.confirmRemoteOperation(stale)

        let calls = await provider.recordedRemoteOperationCalls()
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testRemoteEntryPathsEncodeSpecialCharactersForProviderURLs() async throws {
        let provider = FakeRepoBrowserProvider(
            listResult: .success([]),
            catResult: .success(Data()),
            remoteOperationResults: [.success(Revision(5))]
        )
        let viewModel = RepoBrowserViewModel(
            listProvider: provider,
            previewProvider: provider,
            remoteOperationProvider: provider
        )
        let entry = RemoteEntry(name: "a#b?.txt", path: "a#b?.txt", kind: .file, size: 1, revision: nil, author: nil, date: nil)

        await viewModel.copy(
            entry: entry,
            baseURL: "file:///repo/trunk",
            to: "file:///repo/branches/copy.txt",
            message: "复制特殊字符文件"
        )

        let calls = await provider.recordedRemoteOperationCalls()
        XCTAssertEqual(calls.first?.source, "file:///repo/trunk/a%23b%3F.txt")
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

    private func logEntry(_ revision: Revision) -> LogEntry {
        LogEntry(revision: revision, author: "a", date: nil, message: "m\(revision.value)", changedPaths: [])
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

private struct RepoLogCall: Equatable, Sendable {
    let url: String
    let from: Revision
    let batch: Int
    let verbose: Bool
    let auth: Credential?
}

private struct RepoRemoteOperationCall: Equatable, Sendable {
    let operation: RepoRemoteOperation
    let source: String?
    let destination: String?
    let message: String
    let auth: Credential?
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

private actor FakeRepoBrowserProvider: RepoListProviding, RepoPreviewProviding, RepoLogProviding, RepoRemoteOperationProviding {
    private let listResult: Result<[RemoteEntry], Error>
    private let catResult: Result<Data, Error>
    private var logResults: [Result<[LogEntry], Error>]
    private var remoteOperationResults: [Result<Revision, Error>]
    private var listCalls: [RepoListCall] = []
    private var catCalls: [RepoCatCall] = []
    private var logCalls: [RepoLogCall] = []
    private var remoteOperationCalls: [RepoRemoteOperationCall] = []

    init(
        listResult: Result<[RemoteEntry], Error>,
        catResult: Result<Data, Error>,
        logResults: [Result<[LogEntry], Error>] = [],
        remoteOperationResults: [Result<Revision, Error>] = []
    ) {
        self.listResult = listResult
        self.catResult = catResult
        self.logResults = logResults
        self.remoteOperationResults = remoteOperationResults
    }

    func recordedListCalls() -> [RepoListCall] {
        listCalls
    }

    func recordedCatCalls() -> [RepoCatCall] {
        catCalls
    }

    func recordedLogCalls() -> [RepoLogCall] {
        logCalls
    }

    func recordedRemoteOperationCalls() -> [RepoRemoteOperationCall] {
        remoteOperationCalls
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        listCalls.append(RepoListCall(url: url, depth: depth, auth: auth))
        return try listResult.get()
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        catCalls.append(RepoCatCall(url: url, revision: revision, sizeLimit: sizeLimit, auth: auth))
        return try catResult.get()
    }

    func remoteLog(url: String, from: Revision, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        logCalls.append(RepoLogCall(url: url, from: from, batch: batch, verbose: verbose, auth: auth))
        guard !logResults.isEmpty else {
            return []
        }
        return try logResults.removeFirst().get()
    }

    func mkdir(url: String, message: String, auth: Credential?) async throws -> Revision {
        remoteOperationCalls.append(RepoRemoteOperationCall(
            operation: .mkdir,
            source: nil,
            destination: url,
            message: message,
            auth: auth
        ))
        return try nextRemoteOperationResult()
    }

    func delete(url: String, message: String, auth: Credential?) async throws -> Revision {
        remoteOperationCalls.append(RepoRemoteOperationCall(
            operation: .delete,
            source: url,
            destination: nil,
            message: message,
            auth: auth
        ))
        return try nextRemoteOperationResult()
    }

    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        remoteOperationCalls.append(RepoRemoteOperationCall(
            operation: .copy,
            source: source,
            destination: destination,
            message: message,
            auth: auth
        ))
        return try nextRemoteOperationResult()
    }

    func move(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        remoteOperationCalls.append(RepoRemoteOperationCall(
            operation: .move,
            source: source,
            destination: destination,
            message: message,
            auth: auth
        ))
        return try nextRemoteOperationResult()
    }

    private func nextRemoteOperationResult() throws -> Revision {
        guard !remoteOperationResults.isEmpty else {
            return Revision(1)
        }
        return try remoteOperationResults.removeFirst().get()
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
