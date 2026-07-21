import XCTest
@testable import MacSvnCore

final class ConflictResolveBatchPolicyTests: XCTestCase {
    func testTextAndPropertyAreEligibleTreeIsNot() {
        XCTAssertTrue(ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict("a.txt", .text)))
        XCTAssertTrue(ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict("p", .property)))
        XCTAssertFalse(ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict("t", .tree)))
        XCTAssertFalse(ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict("u", .unknown)))

        XCTAssertTrue(ConflictResolveBatchPolicy.isEligibleForMarkResolved(itemStatus: .conflicted, isTreeConflict: false))
        XCTAssertFalse(ConflictResolveBatchPolicy.isEligibleForMarkResolved(itemStatus: .conflicted, isTreeConflict: true))
        XCTAssertFalse(ConflictResolveBatchPolicy.isEligibleForMarkResolved(itemStatus: .modified, isTreeConflict: false))
    }

    func testFilterCheckedPreservesConflictOrder() {
        let conflicts = [
            conflict("a.txt", .text),
            conflict("tree", .tree),
            conflict("b.txt", .property),
        ]
        let paths = ConflictResolveBatchPolicy.filterCheckedPaths(
            checked: ["b.txt", "tree", "a.txt"],
            conflicts: conflicts
        )
        XCTAssertEqual(paths, ["a.txt", "b.txt"])
    }

    private func conflict(_ path: String, _ kind: ConflictKind) -> ConflictInfo {
        ConflictInfo(path: path, kind: kind, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)
    }
}
