import XCTest
@testable import MacSvnCore

final class LogFilterPolicyTests: XCTestCase {
    func testEmptyQueriesMatchAll() {
        let entry = sample(author: "alice", message: "fix", path: "/trunk/a.swift")
        XCTAssertTrue(LogFilterPolicy.matches(entry, authorQuery: "", messageQuery: "", pathQuery: ""))
    }

    func testPathFilterRequiresChangedPathHit() {
        let entry = sample(author: "alice", message: "fix", path: "/trunk/a.swift")
        XCTAssertTrue(LogFilterPolicy.matches(entry, authorQuery: "", messageQuery: "", pathQuery: "a.swift"))
        XCTAssertFalse(LogFilterPolicy.matches(entry, authorQuery: "", messageQuery: "", pathQuery: "missing"))
    }

    private func sample(author: String, message: String, path: String) -> LogEntry {
        LogEntry(
            revision: Revision(1),
            author: author,
            date: nil,
            message: message,
            changedPaths: [
                ChangedPath(path: path, action: .modified, kind: nil, copyFromPath: nil, copyFromRevision: nil)
            ]
        )
    }
}
