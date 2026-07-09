import XCTest
@testable import MacSvnCore

final class FinderSyncPresentationBuilderTests: XCTestCase {
    func testPresentationUsesExactFileBadgeAndHighestPriorityDirectoryBadge() {
        let builder = FinderSyncPresentationBuilder()
        let statuses = [
            FileStatus(path: "Sources/App.swift", itemStatus: .modified, revision: Revision(10), isTreeConflict: false),
            FileStatus(path: "Sources/Conflict.swift", itemStatus: .modified, revision: Revision(11), isTreeConflict: true),
            FileStatus(path: "README.md", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let file = builder.presentation(for: "Sources/App.swift", statuses: statuses)
        let directory = builder.presentation(for: "Sources", statuses: statuses)
        let unknown = builder.presentation(for: "Sources/Unknown.swift", statuses: statuses)

        XCTAssertEqual(file.badge, .modified)
        XCTAssertEqual(directory.badge, .conflicted)
        XCTAssertEqual(unknown.badge, .normal)
        XCTAssertEqual(directory.targetPath, "Sources")
    }

    func testMenuActionsReflectModifiedVersionedFile() {
        let builder = FinderSyncPresentationBuilder()
        let presentation = builder.presentation(
            for: "Sources/App.swift",
            statuses: [
                FileStatus(path: "Sources/App.swift", itemStatus: .modified, revision: Revision(10), isTreeConflict: false)
            ]
        )

        XCTAssertEqual(enabledActionIDs(in: presentation), [.update, .commit, .log, .diff, .revert, .delete])
        XCTAssertFalse(isEnabled(.add, in: presentation))
        XCTAssertFalse(isEnabled(.resolve, in: presentation))
    }

    func testMenuActionsReflectUnversionedFile() {
        let builder = FinderSyncPresentationBuilder()
        let presentation = builder.presentation(
            for: "scratch.txt",
            statuses: [
                FileStatus(path: "scratch.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
            ]
        )

        XCTAssertEqual(enabledActionIDs(in: presentation), [.update, .add])
        XCTAssertFalse(isEnabled(.commit, in: presentation))
        XCTAssertFalse(isEnabled(.diff, in: presentation))
        XCTAssertFalse(isEnabled(.log, in: presentation))
    }

    func testMenuActionsDisableCommitAndEnableResolveForConflicts() {
        let builder = FinderSyncPresentationBuilder()
        let presentation = builder.presentation(
            for: "Sources/Conflict.swift",
            statuses: [
                FileStatus(path: "Sources/Conflict.swift", itemStatus: .modified, revision: Revision(11), isTreeConflict: true)
            ]
        )

        XCTAssertEqual(presentation.badge, .conflicted)
        XCTAssertTrue(isEnabled(.update, in: presentation))
        XCTAssertTrue(isEnabled(.log, in: presentation))
        XCTAssertTrue(isEnabled(.diff, in: presentation))
        XCTAssertTrue(isEnabled(.revert, in: presentation))
        XCTAssertTrue(isEnabled(.resolve, in: presentation))
        XCTAssertFalse(isEnabled(.commit, in: presentation))
    }

    private func enabledActionIDs(in presentation: FinderSyncPresentation) -> [FinderSyncMenuActionID] {
        presentation.menuActions.filter(\.isEnabled).map(\.id)
    }

    private func isEnabled(_ id: FinderSyncMenuActionID, in presentation: FinderSyncPresentation) -> Bool {
        presentation.menuActions.first { $0.id == id }?.isEnabled ?? false
    }
}
