import XCTest
@testable import MacSvnCore

final class FinderSyncPresentationBuilderTests: XCTestCase {
    func testPresentationUsesExactFileBadgeAndHighestPriorityDirectoryBadge() {
        let builder = FinderSyncPresentationBuilder()
        let statuses = [
            FileStatus(path: "Sources/App.swift", itemStatus: .modified, revision: Revision(10), isTreeConflict: false),
            FileStatus(path: "Sources/Conflict.swift", itemStatus: .modified, revision: Revision(11), isTreeConflict: true),
            FileStatus(path: "README.md", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let file = builder.presentation(for: "Sources/App.swift", statuses: statuses)
        let directory = builder.presentation(for: "Sources", statuses: statuses)
        let unknown = builder.presentation(for: "Sources/Unknown.swift", statuses: statuses)

        XCTAssertEqual(file.badge, .modified)
        XCTAssertEqual(directory.badge, .conflicted)
        XCTAssertEqual(unknown.badge, .normal)
        XCTAssertEqual(directory.targetPath, "Sources")
    }
}
