import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationCleanupPlannerTests: XCTestCase {
    func testPlanFlagsLargeFilesAndNormalizesExcludedPaths() throws {
        let planner = GitMigrationCleanupPlanner()
        let entries = [
            remoteFile("trunk/build/app.zip", size: 12 * 1024 * 1024),
            remoteFile("trunk/README.md", size: 1024),
            RemoteEntry(
                name: "build",
                path: "trunk/build",
                kind: .directory,
                size: nil,
                revision: nil,
                author: nil,
                date: nil
            )
        ]

        let plan = try planner.plan(
            entries: entries,
            svnIgnoreProperties: [],
            excludedPaths: [" /trunk/build/ ", "trunk/tmp", "trunk/build"],
            largeFileThresholdBytes: 10 * 1024 * 1024
        )

        XCTAssertEqual(plan.largeFiles, [
            GitMigrationLargeFileFinding(
                path: "trunk/build/app.zip",
                sizeBytes: 12 * 1024 * 1024,
                thresholdBytes: 10 * 1024 * 1024
            )
        ])
        XCTAssertEqual(plan.excludedPaths, ["trunk/build", "trunk/tmp"])
        XCTAssertTrue(plan.hasLargeFileWarnings)
    }

    func testPlanConvertsSvnIgnorePropertiesToGitIgnoreContents() throws {
        let planner = GitMigrationCleanupPlanner()
        let plan = try planner.plan(
            entries: [],
            svnIgnoreProperties: [
                SvnProperty(target: ".", name: "svn:ignore", value: "*.log\nbuild\n\n"),
                SvnProperty(target: "src", name: "svn:ignore", value: "DerivedData\n*.tmp"),
                SvnProperty(target: "docs", name: "svn:eol-style", value: "native")
            ],
            excludedPaths: []
        )

        XCTAssertEqual(plan.gitIgnoreContents, "*.log\nbuild\nsrc/DerivedData\nsrc/*.tmp\n")
    }

    func testPlanRejectsNonPositiveLargeFileThreshold() {
        let planner = GitMigrationCleanupPlanner()

        XCTAssertThrowsError(try planner.plan(entries: [], largeFileThresholdBytes: 0)) { error in
            XCTAssertEqual(error as? GitMigrationCleanupError, .invalidLargeFileThreshold(0))
        }
    }
}

private func remoteFile(_ path: String, size: Int) -> RemoteEntry {
    RemoteEntry(
        name: URL(fileURLWithPath: path).lastPathComponent,
        path: path,
        kind: .file,
        size: size,
        revision: nil,
        author: nil,
        date: nil
    )
}
