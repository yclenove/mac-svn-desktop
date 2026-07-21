import Foundation
import XCTest
@testable import MacSvnCore

final class UnversionedTreeExpanderTests: XCTestCase {
    func testExpansionAddsDescendantsAndSkipsSvnMetadataNestedWorkingCopiesAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnversionedTree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch/sub"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("scratch/a.txt"))
        try Data().write(to: root.appendingPathComponent("scratch/sub/b.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch/nested/.svn"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("scratch/nested/inside.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("scratch/link"),
            withDestinationURL: root.deletingLastPathComponent()
        )
        let parent = FileStatus(
            path: "scratch",
            itemStatus: .unversioned,
            revision: nil,
            isTreeConflict: false
        )

        let expanded = try UnversionedTreeExpander.expand(
            statuses: [parent],
            workingCopy: root,
            recurse: true
        )

        XCTAssertEqual(Set(expanded.map(\.path)), Set([
            "scratch", "scratch/a.txt", "scratch/sub", "scratch/sub/b.txt", "scratch/link",
        ]))
        XCTAssertTrue(expanded.allSatisfy { $0.itemStatus == .unversioned })
        XCTAssertEqual(
            try UnversionedTreeExpander.expand(statuses: [parent], workingCopy: root, recurse: false),
            [parent]
        )
    }

    func testExpansionDoesNotReAddKnownIgnoredSubtreesAsUnversioned() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnversionedIgnored-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scratch/build"),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("scratch/build/generated.o"))
        let statuses = [
            FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "scratch/build", itemStatus: .ignored, revision: nil, isTreeConflict: false),
        ]

        let expanded = try UnversionedTreeExpander.expand(
            statuses: statuses,
            workingCopy: root,
            recurse: true
        )

        XCTAssertEqual(Set(expanded.map(\.path)), Set(["scratch", "scratch/build"]))
        XCTAssertEqual(expanded.first { $0.path == "scratch/build" }?.itemStatus, .ignored)
    }

    func testExpansionThrowsInsteadOfSilentlyTruncatingAtSafetyLimit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnversionedLimit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("scratch/one.txt"))
        try Data().write(to: root.appendingPathComponent("scratch/two.txt"))
        let parent = FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false)

        XCTAssertThrowsError(try UnversionedTreeExpander.expand(
            statuses: [parent],
            workingCopy: root,
            recurse: true,
            maxDiscoveredEntries: 1
        )) { error in
            XCTAssertEqual(error as? UnversionedTreeExpansionError, .entryLimitExceeded(1))
        }
    }

    func testAsyncExpansionHonorsTaskCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnversionedCancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scratch"), withIntermediateDirectories: true)
        let parent = FileStatus(path: "scratch", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        let task = Task {
            try await UnversionedTreeExpander.expandAsync(
                statuses: [parent],
                workingCopy: root,
                recurse: true
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
