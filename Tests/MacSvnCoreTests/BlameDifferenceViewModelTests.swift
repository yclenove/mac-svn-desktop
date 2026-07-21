import Foundation
import XCTest
@testable import MacSvnCore

final class BlameDifferenceBuilderTests: XCTestCase {
    func testBuildAlignsContentAndBlameMetadataAndClassifiesAttributionChanges() {
        let oldLines = [
            BlameLine(lineNumber: 1, revision: 1, author: "alice", date: nil),
            BlameLine(lineNumber: 2, revision: 1, author: "alice", date: nil)
        ]
        let newLines = [
            BlameLine(lineNumber: 1, revision: 3, author: "bob", date: nil),
            BlameLine(lineNumber: 2, revision: 3, author: "bob", date: nil),
            BlameLine(lineNumber: 3, revision: 3, author: "bob", date: nil)
        ]
        let diff = """
        @@ -1,2 +1,3 @@
         retained
        -old value
        +new value
        +added value
        """

        let rows = BlameDifferenceBuilder.build(
            diffText: diff,
            oldBlame: oldLines,
            newBlame: newLines
        )

        XCTAssertEqual(rows.map(\.kind), [
            .hunk, .attributionChanged, .contentModified, .added
        ])
        XCTAssertEqual(rows[1].left?.revision, Revision(1))
        XCTAssertEqual(rows[1].right?.revision, Revision(3))
        XCTAssertEqual(rows[2].left?.text, "old value")
        XCTAssertEqual(rows[2].right?.text, "new value")
        XCTAssertEqual(rows[3].right?.lineNumber, 3)
        XCTAssertEqual(rows[3].right?.author, "bob")
    }
}

final class BlameDifferenceViewModelTests: XCTestCase {
    @MainActor
    func testLoadFetchesBothBlamesAndDiffAndBuildsSummary() async {
        let provider = FakeBlameDifferenceProvider(
            blameResults: [
                [BlameLine(lineNumber: 1, revision: 2, author: "alice", date: nil)],
                [BlameLine(lineNumber: 1, revision: 5, author: "bob", date: nil)]
            ],
            diffText: "@@ -1 +1 @@\n-old\n+new\n"
        )
        let viewModel = BlameDifferenceViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load(from: Revision(2), to: Revision(5))

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.summary.contentModified, 1)
        XCTAssertEqual(viewModel.changedRows.count, 1)
        let blameEnds = await provider.recordedBlameEnds()
        let diffRanges = await provider.recordedDiffRanges()
        XCTAssertEqual(blameEnds, [Revision(2), Revision(5)])
        XCTAssertEqual(diffRanges, [RevisionRange(start: 2, end: 5)])
    }

    @MainActor
    func testLoadRejectsNonAscendingRevisionRangeBeforeProviderCalls() async {
        let provider = FakeBlameDifferenceProvider(blameResults: [], diffText: "")
        let viewModel = BlameDifferenceViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load(from: Revision(5), to: Revision(5))

        XCTAssertEqual(viewModel.state, .error("旧修订必须小于新修订"))
        let blameEnds = await provider.recordedBlameEnds()
        let diffRanges = await provider.recordedDiffRanges()
        XCTAssertTrue(blameEnds.isEmpty)
        XCTAssertTrue(diffRanges.isEmpty)
    }

    @MainActor
    func testLoadRejectsNonPositiveRevisionsBeforeProviderCalls() async {
        let provider = FakeBlameDifferenceProvider(blameResults: [], diffText: "")
        let viewModel = BlameDifferenceViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load(from: Revision(0), to: Revision(5))

        XCTAssertEqual(viewModel.state, .error("修订号必须是正整数"))
        let blameEnds = await provider.recordedBlameEnds()
        XCTAssertTrue(blameEnds.isEmpty)
    }
}

private actor FakeBlameDifferenceProvider: BlameDifferenceProviding {
    private var blameResults: [[BlameLine]]
    private let diffText: String
    private var blameEnds: [Revision] = []
    private var diffRanges: [RevisionRange] = []

    init(blameResults: [[BlameLine]], diffText: String) {
        self.blameResults = blameResults
        self.diffText = diffText
    }

    func recordedBlameEnds() -> [Revision] { blameEnds }
    func recordedDiffRanges() -> [RevisionRange] { diffRanges }

    func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine] {
        _ = (wc, target, startRevision)
        blameEnds.append(try XCTUnwrap(endRevision))
        return blameResults.removeFirst()
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        _ = (wc, target)
        diffRanges.append(RevisionRange(
            start: try XCTUnwrap(r1),
            end: try XCTUnwrap(r2)
        ))
        return diffText
    }
}
