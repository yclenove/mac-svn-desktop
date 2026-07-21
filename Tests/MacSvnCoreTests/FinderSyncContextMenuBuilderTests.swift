import XCTest
@testable import MacSvnCore

final class FinderSyncContextMenuBuilderTests: XCTestCase {
    private let builder = FinderSyncContextMenuBuilder()

    func testCustomPromotedCommandsSplitTopLevelAndSubmenuWithoutDuplicates() {
        let settings = FinderSyncContextMenuSettings(
            promotedCommandIDs: [.commit, .copyMove, .commit]
        )

        let plan = builder.plan(
            targets: [FinderSyncMenuTargetState(path: "/wc/file.swift", itemStatus: .modified)],
            settings: settings
        )

        XCTAssertFalse(plan.isHidden)
        XCTAssertEqual(plan.promotedCommandIDs, [.commit, .copyMove])
        XCTAssertFalse(plan.submenuCommandIDs.contains(.commit))
        XCTAssertFalse(plan.submenuCommandIDs.contains(.copyMove))
        XCTAssertEqual(
            Set(plan.promotedCommandIDs + plan.submenuCommandIDs).count,
            plan.promotedCommandIDs.count + plan.submenuCommandIDs.count
        )
    }

    func testNeedsLockReadOnlyTargetPromotesGetLock() {
        let target = FinderSyncMenuTargetState(
            path: "/wc/design.psd",
            itemStatus: .normal,
            hasNeedsLock: true,
            isReadOnly: true,
            isRepositoryLocked: false
        )

        let plan = builder.plan(targets: [target], settings: FinderSyncContextMenuSettings())

        XCTAssertTrue(plan.promotedCommandIDs.contains(.getLock))
        XCTAssertFalse(plan.submenuCommandIDs.contains(.getLock))
    }

    func testNeedsLockDoesNotPromoteGetLockWhenAlreadyRepositoryLocked() {
        let target = FinderSyncMenuTargetState(
            path: "/wc/design.psd",
            itemStatus: .normal,
            hasNeedsLock: true,
            isReadOnly: true,
            isRepositoryLocked: true
        )

        let plan = builder.plan(targets: [target], settings: FinderSyncContextMenuSettings())

        XCTAssertFalse(plan.promotedCommandIDs.contains(.getLock))
        XCTAssertTrue(plan.submenuCommandIDs.contains(.getLock))
    }

    func testHideUnversionedMenusRequiresEveryTargetToBeKnownAndUnversioned() {
        let settings = FinderSyncContextMenuSettings(hideMenusForUnversionedItems: true)

        let hidden = builder.plan(
            targets: [
                FinderSyncMenuTargetState(path: "/wc/a.tmp", itemStatus: .unversioned),
                FinderSyncMenuTargetState(path: "/wc/b.tmp", itemStatus: .ignored),
            ],
            settings: settings
        )
        let unknown = builder.plan(
            targets: [FinderSyncMenuTargetState(path: "/wc/not-cached-yet", itemStatus: nil)],
            settings: settings
        )
        let mixed = builder.plan(
            targets: [
                FinderSyncMenuTargetState(path: "/wc/a.tmp", itemStatus: .unversioned),
                FinderSyncMenuTargetState(path: "/wc/tracked.swift", itemStatus: .normal),
            ],
            settings: settings
        )

        XCTAssertTrue(hidden.isHidden)
        XCTAssertFalse(unknown.isHidden)
        XCTAssertFalse(mixed.isHidden)
    }

    func testExcludedTargetHidesMenuAndCopyMoveIsAlwaysReachableOtherwise() {
        let settings = FinderSyncContextMenuSettings(excludedPaths: ["/wc/vendor"])

        let hidden = builder.plan(
            targets: [FinderSyncMenuTargetState(path: "/wc/vendor/lib.c", itemStatus: .normal)],
            settings: settings
        )
        let visible = builder.plan(
            targets: [FinderSyncMenuTargetState(path: "/wc/src/App.swift", itemStatus: .normal)],
            settings: settings
        )

        XCTAssertTrue(hidden.isHidden)
        XCTAssertTrue((visible.promotedCommandIDs + visible.submenuCommandIDs).contains(.copyMove))
    }
}
