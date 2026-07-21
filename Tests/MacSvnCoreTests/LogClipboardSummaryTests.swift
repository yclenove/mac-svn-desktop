import XCTest
@testable import MacSvnCore

final class LogClipboardSummaryTests: XCTestCase {
    func testFormatsSingleEntryWithChangedPaths() {
        let entry = LogEntry(
            revision: Revision(42),
            author: "yangchao",
            date: nil,
            message: "fix bug",
            changedPaths: [
                ChangedPath(path: "/trunk/a.swift", action: .modified, kind: nil, copyFromPath: nil, copyFromRevision: nil),
                ChangedPath(path: "/trunk/b.swift", action: .added, kind: nil, copyFromPath: nil, copyFromRevision: nil),
            ]
        )
        let text = LogClipboardSummary.text(for: entry)
        XCTAssertTrue(text.contains("Revision: 42"))
        XCTAssertTrue(text.contains("Author: yangchao"))
        XCTAssertTrue(text.contains("Date: (unknown)"))
        XCTAssertTrue(text.contains("fix bug"))
        XCTAssertTrue(text.contains("   M /trunk/a.swift"))
        XCTAssertTrue(text.contains("   A /trunk/b.swift"))
    }

    func testJoinsMultipleEntries() {
        let a = LogEntry(revision: Revision(1), author: "a", date: nil, message: "one", changedPaths: [])
        let b = LogEntry(revision: Revision(2), author: "b", date: nil, message: "two", changedPaths: [])
        let text = LogClipboardSummary.text(for: [a, b])
        XCTAssertTrue(text.contains("Revision: 1"))
        XCTAssertTrue(text.contains("Revision: 2"))
        XCTAssertTrue(text.contains("\n\n"))
    }
}
