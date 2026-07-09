import XCTest
@testable import MacSvnCore

final class MergeOutputParserTests: XCTestCase {
    func testParsesMergeActionsAndAffectedPaths() throws {
        let output = """
        --- Merging r2 into '.':
        U    README.txt
        A    Sources/New.swift
        D    old.txt
        C    conflict.txt
        G    merged.txt
        --- Recording mergeinfo for merge of r2 into '.':
         U   .
        """

        let summary = try MergeOutputParser.parse(output)

        XCTAssertEqual(summary.updated, 2)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(summary.conflicted, 1)
        XCTAssertEqual(summary.merged, 1)
        XCTAssertEqual(summary.affectedPaths.map(\.path), [
            "README.txt", "Sources/New.swift", "old.txt", "conflict.txt", "merged.txt", "."
        ])
        XCTAssertEqual(summary.affectedPaths.map(\.action), [
            .updated, .added, .deleted, .conflicted, .merged, .updated
        ])
    }

    func testIgnoresExplanatoryAndUnknownLines() throws {
        let output = """
        --- Merging r2 through r4 into '.':
        Skipped missing target: 'gone.txt'
        Random progress line
        U    known.txt
        """

        let summary = try MergeOutputParser.parse(output)

        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.affectedPaths, [
            MergeAffectedPath(action: .updated, path: "known.txt")
        ])
    }
}
