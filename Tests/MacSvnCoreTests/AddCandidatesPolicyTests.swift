import XCTest
@testable import MacSvnCore

final class AddCandidatesPolicyTests: XCTestCase {
    func testCandidatesOnlyUnversioned() {
        let statuses = [
            FileStatus(path: "a.swift", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "scratch.tmp", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        XCTAssertEqual(AddCandidatesPolicy.candidates(from: statuses).map(\.path), ["new.txt", "scratch.tmp"])
    }

    func testDefaultSelectionUsesPreselectedIntersectionOrAll() {
        let statuses = [
            FileStatus(path: "a.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "b.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        XCTAssertEqual(
            AddCandidatesPolicy.defaultSelectedPaths(from: statuses, preselected: ["a.txt"]),
            Set(["a.txt"])
        )
        XCTAssertEqual(
            AddCandidatesPolicy.defaultSelectedPaths(from: statuses, preselected: []),
            Set(["a.txt", "b.txt"])
        )
    }
}
