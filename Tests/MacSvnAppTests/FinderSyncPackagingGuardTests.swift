import Foundation
import XCTest

final class FinderSyncPackagingGuardTests: XCTestCase {
    func testExtensionRegistersEveryTortoiseParityBadge() throws {
        let source = try Self.readFinderSyncSource()
        let badges = [
            "normal", "modified", "conflicted", "added", "deleted", "missing", "replaced",
            "locked", "needsLock", "ignored", "unversioned", "shallow", "nested", "external",
            "switched", "mergeInfo", "incomplete", "obstructed"
        ]

        for badge in badges {
            XCTAssertTrue(source.contains("(.\(badge),"), "Finder Sync must register .\(badge)")
        }
        XCTAssertFalse(source.contains("presentation.badge == .normal ? \"\""))
    }

    func testExtensionCollectsVerboseIgnoredAndOverlayMetadata() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("\"--verbose\""))
        XCTAssertTrue(source.contains("\"--no-ignore\""))
        XCTAssertTrue(source.contains("FinderSyncInfoXMLParser.parseDepths"))
        XCTAssertTrue(source.contains("PropertyXMLParser.parse"))
        XCTAssertTrue(source.contains("FinderSyncStatusEnricher.enrich"))
    }

    func testExtensionCoalescesConcurrentStatusRefreshesPerWorkingCopy() throws {
        let source = try Self.readFinderSyncSource()

        XCTAssertTrue(source.contains("private var inFlight:"))
        XCTAssertTrue(source.contains("if let task = inFlight[key]"))
        XCTAssertTrue(source.contains("inFlight[key] = task"))
        XCTAssertTrue(source.contains("inFlight[key] = nil"))
    }

    private static func readFinderSyncSource() throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent("Packaging/FinderSync/MacSvnFinderSync.swift"),
            encoding: .utf8
        )
    }
}
