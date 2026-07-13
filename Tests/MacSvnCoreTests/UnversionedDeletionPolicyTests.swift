import Foundation
import XCTest
@testable import MacSvnCore

final class UnversionedDeletionPolicyTests: XCTestCase {
    private let wc = URL(fileURLWithPath: "/tmp/wc")

    func testCandidatesOnlyContainDeduplicatedSortedUnversionedPaths() throws {
        let statuses = [
            FileStatus(path: "z.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "tracked.txt", itemStatus: .modified, revision: 1, isTreeConflict: false),
            FileStatus(path: "a.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "z.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let candidates = try UnversionedDeletionPolicy.candidates(from: statuses, workingCopy: wc)

        XCTAssertEqual(candidates.map(\.path), ["a.txt", "z.txt"])
    }

    func testValidationRejectsVersionedPath() {
        let statuses = [
            FileStatus(path: "tracked.txt", itemStatus: .modified, revision: 1, isTreeConflict: false)
        ]

        XCTAssertThrowsError(try UnversionedDeletionPolicy.validatedPaths(
            ["tracked.txt"], from: statuses, workingCopy: wc
        )) { error in
            XCTAssertEqual(error as? UnversionedDeletionPolicyError, .notUnversioned("tracked.txt"))
        }
    }

    func testValidationRejectsAbsoluteAndEscapingPaths() {
        let statuses = [
            FileStatus(path: "safe.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        for path in ["/tmp/outside.txt", "../outside.txt"] {
            XCTAssertThrowsError(try UnversionedDeletionPolicy.validatedPaths(
                [path], from: statuses, workingCopy: wc
            )) { error in
                XCTAssertEqual(error as? UnversionedDeletionPolicyError, .invalidPath(path))
            }
        }
    }

    func testValidationCollapsesDescendantsWhenParentIsSelected() throws {
        let statuses = [
            FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "scratch/nested.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let paths = try UnversionedDeletionPolicy.validatedPaths(
            ["scratch/nested.txt", "scratch"],
            from: statuses,
            workingCopy: wc
        )

        XCTAssertEqual(paths, ["scratch"])
    }
}
