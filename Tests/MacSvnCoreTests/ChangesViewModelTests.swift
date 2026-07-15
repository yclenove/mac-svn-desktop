import Foundation
import XCTest
@testable import MacSvnCore

final class ChangesViewModelTests: XCTestCase {
    func testFlatFilteringSupportsStatusAndCaseInsensitiveSearch() {
        let filtered = FileStatusListBuilder.flatEntries(
            from: sampleStatuses(),
            filter: .items([.modified, .conflicted]),
            searchText: "view"
        )

        XCTAssertEqual(filtered.map(\.path), ["Sources/View.swift"])
    }

    func testConflictFilteringIncludesTreeConflicts() {
        let statuses = sampleStatuses() + [
            FileStatus(path: "Tree/Conflict.swift", itemStatus: .modified, revision: Revision(4), isTreeConflict: true)
        ]

        let filtered = FileStatusListBuilder.flatEntries(
            from: statuses,
            filter: .conflicts,
            searchText: ""
        )

        XCTAssertEqual(filtered.map(\.path), ["Sources/Model.swift", "Tree/Conflict.swift"])
    }

    func testTreeGroupsNestedPathsAndAggregatesConflictStatus() throws {
        let tree = FileStatusListBuilder.tree(from: sampleStatuses())

        XCTAssertEqual(Set(tree.map(\.name)), Set(["README.md", "Sources", "scratch.tmp"]))

        let sources = try XCTUnwrap(tree.first { $0.name == "Sources" })
        XCTAssertTrue(sources.isDirectory)
        XCTAssertEqual(sources.path, "Sources")
        XCTAssertEqual(sources.itemStatus, .conflicted)
        XCTAssertEqual(sources.children.map(\.name), ["Model.swift", "View.swift"])
        XCTAssertEqual(sources.children.map(\.itemStatus), [.conflicted, .modified])
    }

    func testChangelistGroupsKeepNamedListsAndUnassignedEntriesSeparate() {
        let statuses = [
            FileStatus(path: "b.swift", itemStatus: .modified, revision: 1, isTreeConflict: false, changelist: "release"),
            FileStatus(path: "a.swift", itemStatus: .modified, revision: 1, isTreeConflict: false, changelist: "release"),
            FileStatus(path: "scratch.swift", itemStatus: .modified, revision: 1, isTreeConflict: false)
        ]

        let groups = ChangelistPolicy.groups(from: statuses)

        XCTAssertEqual(groups.map(\.name), ["release", nil])
        XCTAssertEqual(groups[0].entries.map(\.path), ["a.swift", "b.swift"])
        XCTAssertEqual(groups[1].entries.map(\.path), ["scratch.swift"])
    }

    @MainActor
    func testRefreshLoadsStatusesAndExposesVisibleFlatEntries() async {
        let provider = FakeStatusProvider(result: .success(sampleStatuses()))
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: provider
        )
        viewModel.displayMode = .flat
        viewModel.filter = .items([.modified])

        await viewModel.refresh()
        let requestedWorkingCopies = await provider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.visibleFlatEntries.map(\.path), ["Sources/View.swift"])
        XCTAssertNotNil(viewModel.lastRefreshedAt)
        XCTAssertEqual(requestedWorkingCopies, [URL(fileURLWithPath: "/tmp/wc")])
    }

    @MainActor
    func testRefreshCanExpandUnversionedDirectoryChildren() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChangesUnversioned-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch/sub"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("scratch/sub/file.txt"))
        let parent = FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        let viewModel = ChangesViewModel(
            workingCopy: root,
            statusProvider: FakeStatusProvider(result: .success([parent])),
            recurseIntoUnversionedFolders: true
        )

        await viewModel.refresh()

        XCTAssertEqual(Set(viewModel.entries.map(\.path)), Set(["scratch", "scratch/sub", "scratch/sub/file.txt"]))
    }

    @MainActor
    func testRecursiveUnversionedSettingCanUpdateWithoutRecreatingViewModel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChangesSettings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("scratch/file.txt"))
        let parent = FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        let viewModel = ChangesViewModel(
            workingCopy: root,
            statusProvider: FakeStatusProvider(result: .success([parent])),
            recurseIntoUnversionedFolders: false
        )

        await viewModel.refresh()
        XCTAssertEqual(viewModel.entries.map(\.path), ["scratch"])

        viewModel.updateSettings(recurseIntoUnversionedFolders: true)
        await viewModel.refresh()
        XCTAssertEqual(Set(viewModel.entries.map(\.path)), Set(["scratch", "scratch/file.txt"]))
    }

    @MainActor
    func testNewRefreshResultWinsWhenOlderRecursiveRefreshFinishesLate() async throws {
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: RacingStatusProvider(),
            recurseIntoUnversionedFolders: true
        )

        let olderRefresh = Task { await viewModel.refresh() }
        try await Task.sleep(for: .milliseconds(10))
        viewModel.updateSettings(recurseIntoUnversionedFolders: false)
        await viewModel.refresh()
        await olderRefresh.value

        XCTAssertEqual(viewModel.entries.map(\.path), ["new.swift"])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testColumnVisibilityUpdatesConfiguration() async {
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: FakeStatusProvider(result: .success([])),
            columnConfiguration: CFMColumnConfiguration(visibleOrderedIDs: [.path, .textStatus, .revision])
        )
        viewModel.setColumnVisible(.revision, visible: false)
        XCTAssertEqual(viewModel.visibleColumns, [.path, .textStatus])
        viewModel.setColumnVisible(.treeConflict, visible: true)
        XCTAssertEqual(viewModel.visibleColumns, [.path, .textStatus, .treeConflict])
    }

    @MainActor
    func testCheckRepositoryLoadsRemoteStatusesAndSetsFlag() async {
        let remoteAware = [
            FileStatus(
                path: "a.swift",
                itemStatus: .modified,
                revision: Revision(1),
                isTreeConflict: false,
                remoteItemStatus: .modified
            )
        ]
        let provider = FakeStatusProvider(result: .success(remoteAware))
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: provider
        )

        await viewModel.checkRepository()
        let repoCalls = await provider.requestedRepositoryChecks()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertTrue(viewModel.includesRepositoryCheck)
        XCTAssertEqual(viewModel.highlight(for: remoteAware[0]), .both)
        XCTAssertEqual(repoCalls, [URL(fileURLWithPath: "/tmp/wc")])
    }

    @MainActor
    func testRefreshClearsRepositoryCheckFlag() async {
        let provider = FakeStatusProvider(result: .success(sampleStatuses()))
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: provider
        )
        await viewModel.checkRepository()
        XCTAssertTrue(viewModel.includesRepositoryCheck)
        await viewModel.refresh()
        XCTAssertFalse(viewModel.includesRepositoryCheck)
    }

    @MainActor
    func testRefreshStoresErrorStateWhenStatusProviderFails() async {
        let provider = FakeStatusProvider(result: .failure(SvnError.authentication))
        let viewModel = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statusProvider: provider
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .error("authentication"))
        XCTAssertTrue(viewModel.visibleFlatEntries.isEmpty)
    }

    private func sampleStatuses() -> [FileStatus] {
        [
            FileStatus(path: "Sources/View.swift", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "Sources/Model.swift", itemStatus: .conflicted, revision: Revision(2), isTreeConflict: false),
            FileStatus(path: "README.md", itemStatus: .added, revision: Revision(3), isTreeConflict: false),
            FileStatus(path: "scratch.tmp", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
    }
}

private actor RacingStatusProvider: StatusProviding {
    func status(wc: URL) async throws -> [FileStatus] {
        [FileStatus(
            path: "new.swift",
            itemStatus: .modified,
            revision: Revision(2),
            isTreeConflict: false
        )]
    }

    func statusIncludingIgnored(wc: URL) async throws -> [FileStatus] {
        try await Task.sleep(for: .milliseconds(80))
        return [FileStatus(
            path: "old.swift",
            itemStatus: .modified,
            revision: Revision(1),
            isTreeConflict: false
        )]
    }
}

private actor FakeStatusProvider: StatusProviding {
    private let result: Result<[FileStatus], Error>
    private var requests: [URL] = []
    private var repositoryRequests: [URL] = []

    init(result: Result<[FileStatus], Error>) {
        self.result = result
    }

    func requestedWorkingCopies() -> [URL] {
        requests
    }

    func requestedRepositoryChecks() -> [URL] {
        repositoryRequests
    }

    func status(wc: URL) async throws -> [FileStatus] {
        requests.append(wc)
        return try result.get()
    }

    func statusAgainstRepository(wc: URL) async throws -> [FileStatus] {
        repositoryRequests.append(wc)
        return try result.get()
    }
}
