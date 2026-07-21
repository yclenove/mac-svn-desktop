import XCTest
@testable import MacSvnCore

final class RepairMoveCopyPairingTests: XCTestCase {
    func testResolveMoveRequiresMissingAndUnversioned() {
        let statuses = [
            FileStatus(path: "old.txt", itemStatus: .missing, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let result = RepairMoveCopyPairing.resolve(
            kind: .move,
            selectedPaths: ["old.txt", "new.txt"],
            statuses: statuses
        )

        switch result {
        case .success(let pair):
            XCTAssertEqual(pair.kind, .move)
            XCTAssertEqual(pair.sourcePath, "old.txt")
            XCTAssertEqual(pair.destinationPath, "new.txt")
        case .failure(let error):
            XCTFail("unexpected failure: \(error)")
        }
    }

    func testResolveCopyRequiresVersionedAndUnversioned() {
        let statuses = [
            FileStatus(path: "src.txt", itemStatus: .normal, revision: Revision(3), isTreeConflict: false),
            FileStatus(path: "dst.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let result = RepairMoveCopyPairing.resolve(
            kind: .copy,
            selectedPaths: ["dst.txt", "src.txt"],
            statuses: statuses
        )

        switch result {
        case .success(let pair):
            XCTAssertEqual(pair.sourcePath, "src.txt")
            XCTAssertEqual(pair.destinationPath, "dst.txt")
        case .failure(let error):
            XCTFail("unexpected failure: \(error)")
        }
    }

    func testRejectsWrongSelectionCount() {
        let result = RepairMoveCopyPairing.resolve(
            kind: .move,
            selectedPaths: ["only.txt"],
            statuses: [
                FileStatus(path: "only.txt", itemStatus: .missing, revision: nil, isTreeConflict: false)
            ]
        )
        XCTAssertEqual(result, .failure(.needExactlyTwoSelections(count: 1)))
        XCTAssertFalse(RepairMoveCopyPairing.canRepair(
            kind: .move,
            selectedPaths: ["only.txt"],
            statuses: [
                FileStatus(path: "only.txt", itemStatus: .missing, revision: nil, isTreeConflict: false)
            ]
        ))
    }

    func testRejectsMoveWhenBothUnversioned() {
        let statuses = [
            FileStatus(path: "a.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "b.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        let result = RepairMoveCopyPairing.resolve(
            kind: .move,
            selectedPaths: ["a.txt", "b.txt"],
            statuses: statuses
        )
        XCTAssertEqual(result, .failure(.invalidMovePair))
    }

    func testCanRepairCopyTrueForModifiedPlusUnversioned() {
        let statuses = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "b.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        XCTAssertTrue(RepairMoveCopyPairing.canRepair(
            kind: .copy,
            selectedPaths: ["a.txt", "b.txt"],
            statuses: statuses
        ))
        XCTAssertFalse(RepairMoveCopyPairing.canRepair(
            kind: .move,
            selectedPaths: ["a.txt", "b.txt"],
            statuses: statuses
        ))
    }
}
