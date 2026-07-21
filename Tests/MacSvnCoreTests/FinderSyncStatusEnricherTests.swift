import XCTest
@testable import MacSvnCore

final class FinderSyncStatusEnricherTests: XCTestCase {
    func testEnrichesNeedsLockDepthNestedAndReadOnlyMetadata() {
        let statuses = [
            FileStatus(path: "locked.txt", itemStatus: .normal, revision: Revision(4), isTreeConflict: false),
            FileStatus(path: "sparse", itemStatus: .normal, revision: Revision(4), isTreeConflict: false),
            FileStatus(path: "nested", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        let metadata = [
            FinderSyncPathMetadata(path: "locked.txt", isReadOnly: true),
            FinderSyncPathMetadata(path: "sparse", depth: .immediates),
            FinderSyncPathMetadata(path: "nested", isNestedWorkingCopy: true)
        ]

        let enriched = FinderSyncStatusEnricher.enrich(
            statuses: statuses,
            currentProperties: [SvnProperty(target: "locked.txt", name: "svn:needs-lock", value: "*")],
            baseProperties: [],
            pathMetadata: metadata
        )

        XCTAssertTrue(enriched[0].overlay.hasNeedsLock)
        XCTAssertTrue(enriched[0].overlay.isReadOnly)
        XCTAssertEqual(enriched[1].overlay.depth, .immediates)
        XCTAssertTrue(enriched[2].overlay.isNestedWorkingCopy)
    }

    func testMarksMergeInfoOnlyWhenItIsTheOnlyPropertyDifference() {
        let status = FileStatus(
            path: "branch",
            itemStatus: .normal,
            revision: Revision(4),
            isTreeConflict: false,
            overlay: FileStatusOverlayMetadata(propertyStatus: .modified)
        )

        let enriched = FinderSyncStatusEnricher.enrich(
            statuses: [status],
            currentProperties: [
                SvnProperty(target: "branch", name: "svn:mergeinfo", value: "/trunk:1-4"),
                SvnProperty(target: "branch", name: "custom:stable", value: "yes")
            ],
            baseProperties: [
                SvnProperty(target: "branch", name: "svn:mergeinfo", value: "/trunk:1-3"),
                SvnProperty(target: "branch", name: "custom:stable", value: "yes")
            ],
            pathMetadata: []
        )

        XCTAssertTrue(enriched[0].overlay.isMergeInfoOnly)
    }

    func testDoesNotMarkMergeInfoOnlyWhenAnotherPropertyAlsoChanged() {
        let status = FileStatus(
            path: "branch",
            itemStatus: .normal,
            revision: Revision(4),
            isTreeConflict: false,
            overlay: FileStatusOverlayMetadata(propertyStatus: .modified)
        )

        let enriched = FinderSyncStatusEnricher.enrich(
            statuses: [status],
            currentProperties: [
                SvnProperty(target: "branch", name: "svn:mergeinfo", value: "/trunk:1-4"),
                SvnProperty(target: "branch", name: "custom:review", value: "new")
            ],
            baseProperties: [
                SvnProperty(target: "branch", name: "svn:mergeinfo", value: "/trunk:1-3"),
                SvnProperty(target: "branch", name: "custom:review", value: "old")
            ],
            pathMetadata: []
        )

        XCTAssertFalse(enriched[0].overlay.isMergeInfoOnly)
    }
}
