import XCTest
@testable import MacSvnCore

final class MergeEngineTests: XCTestCase {
    func testDiffProducesEqualDeleteAndInsertEdits() {
        let edits = MergeEngine.diff(lines("a\nb\nc"), lines("a\nB\nc\nnew"))

        XCTAssertEqual(edits, [
            .equal("a"),
            .delete("b"),
            .insert("B"),
            .equal("c"),
            .insert("new")
        ])
    }

    func testMerge3AutoAcceptsMineOnlyChange() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("a\nB\nc"),
            theirs: lines("a\nb\nc")
        )

        XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
    }

    func testMerge3AutoAcceptsTheirsOnlyChange() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("a\nb\nc"),
            theirs: lines("a\nB\nc")
        )

        XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
    }

    func testMerge3AutoAcceptsDifferentRegionsFromBothSides() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc\nd"),
            mine: lines("a\nB\nc\nd"),
            theirs: lines("a\nb\nc\nD")
        )

        XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c", "D"])])
    }

    func testMerge3CreatesConflictForDifferentChangesOnSameLine() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("a\nmine\nc"),
            theirs: lines("a\ntheirs\nc")
        )

        XCTAssertEqual(blocks, [
            .stable(lines: ["a"]),
            .conflict(ConflictHunk(baseLines: ["b"], mineLines: ["mine"], theirsLines: ["theirs"])),
            .stable(lines: ["c"])
        ])
    }

    func testMerge3AutoAcceptsIdenticalChangesFromBothSides() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("a\nB\nc"),
            theirs: lines("a\nB\nc")
        )

        XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
    }

    func testMerge3CreatesConflictForDeleteVersusModify() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("a\nc"),
            theirs: lines("a\nB\nc")
        )

        XCTAssertEqual(blocks, [
            .stable(lines: ["a"]),
            .conflict(ConflictHunk(baseLines: ["b"], mineLines: [], theirsLines: ["B"])),
            .stable(lines: ["c"])
        ])
    }

    func testMerge3MergesAdjacentOppositeSideEditsIntoSingleConflict() {
        let blocks = MergeEngine.merge3(
            base: lines("a\nb\nc"),
            mine: lines("A\nb\nc"),
            theirs: lines("a\nB\nc")
        )

        XCTAssertEqual(blocks, [
            .conflict(ConflictHunk(baseLines: ["a", "b"], mineLines: ["A", "b"], theirsLines: ["a", "B"])),
            .stable(lines: ["c"])
        ])
    }

    func testMerge3HandlesEmptySingleLineAndInsertionOnlyInputs() {
        XCTAssertEqual(MergeEngine.merge3(base: [], mine: [], theirs: []), [])

        XCTAssertEqual(
            MergeEngine.merge3(base: [], mine: lines("mine"), theirs: []),
            [.stable(lines: ["mine"])]
        )

        XCTAssertEqual(
            MergeEngine.merge3(base: lines("base"), mine: lines("mine"), theirs: lines("theirs")),
            [.conflict(ConflictHunk(baseLines: ["base"], mineLines: ["mine"], theirsLines: ["theirs"]))]
        )
    }

    func testConflictResolutionProducesMergedLinesAndRequiresAllConflictsResolved() {
        let unresolved = ConflictHunk(baseLines: ["base"], mineLines: ["mine"], theirsLines: ["theirs"])
        XCTAssertNil(MergeEngine.mergedLines(from: [.conflict(unresolved)]))

        let blocks: [MergeBlock] = [
            .stable(lines: ["start"]),
            .conflict(ConflictHunk(
                baseLines: ["base"],
                mineLines: ["mine"],
                theirsLines: ["theirs"],
                resolution: .takeBoth(mineFirst: false)
            )),
            .conflict(ConflictHunk(
                baseLines: ["old"],
                mineLines: ["mine-only"],
                theirsLines: ["theirs-only"],
                resolution: .manual(lines: ["manual"])
            )),
            .stable(lines: ["end"])
        ]

        XCTAssertEqual(MergeEngine.mergedLines(from: blocks), [
            "start", "theirs", "mine", "manual", "end"
        ])
    }

    private func lines(_ text: String) -> [Substring] {
        let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return text.hasSuffix("\n") ? Array(splitLines.dropLast()) : splitLines
    }
}
