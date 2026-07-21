import Foundation
import XCTest
@testable import MacSvnCore

final class RevertSafetyServiceTests: XCTestCase {
    func testStageMovesOnlySelectedModifiedFilesAndSupportsRestore() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Sources/App.swift", "Sources/Added.swift", "Other.swift"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        let store = RecordingTrashStore(root: root.appendingPathComponent("trash"))
        let service = RevertSafetyService(store: store)
        let statuses = [
            status("Sources/App.swift", .modified),
            status("Sources/Added.swift", .added),
            status("Other.swift", .modified),
        ]

        let backup = try service.stage(
            workingCopy: root,
            selectedPaths: ["Sources"],
            statuses: statuses,
            recursive: true
        )

        XCTAssertEqual(backup.entries.map { $0.originalURL.lastPathComponent }, ["App.swift"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/App.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Added.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Other.swift").path))

        try service.restore(backup)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("Sources/App.swift"), encoding: .utf8),
            "Sources/App.swift"
        )
    }

    func testStageRejectsEscapingPathAndRollsBackEarlierMovesOnFailure() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["one.txt", "two.txt"] {
            try Data(path.utf8).write(to: root.appendingPathComponent(path))
        }
        let store = RecordingTrashStore(root: root.appendingPathComponent("trash"), failOnMove: "two.txt")
        let service = RevertSafetyService(store: store)

        XCTAssertThrowsError(try service.stage(
            workingCopy: root,
            selectedPaths: ["."],
            statuses: [
                status("one.txt", .modified),
                status("two.txt", .conflicted),
            ],
            recursive: true
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("two.txt").path))

        XCTAssertThrowsError(try service.stage(
            workingCopy: root,
            selectedPaths: ["../outside"],
            statuses: [status("../outside", .modified)],
            recursive: false
        ))
    }

    func testNonRecursiveDirectorySelectionDoesNotTrashModifiedDescendants() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: child.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("local changes".utf8).write(to: child)
        let store = RecordingTrashStore(root: root.appendingPathComponent("trash"))
        let service = RevertSafetyService(store: store)
        let statuses = [status("Sources/App.swift", .modified)]

        let nonRecursive = try service.stage(
            workingCopy: root,
            selectedPaths: ["Sources"],
            statuses: statuses,
            recursive: false
        )

        XCTAssertTrue(nonRecursive.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))

        let recursive = try service.stage(
            workingCopy: root,
            selectedPaths: ["Sources"],
            statuses: statuses,
            recursive: true
        )
        XCTAssertEqual(recursive.entries.map(\.originalURL), [child])
    }

    func testStageReportsMoveAndRollbackFailuresTogether() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["one.txt", "two.txt"] {
            try Data(path.utf8).write(to: root.appendingPathComponent(path))
        }
        let service = RevertSafetyService(store: RecordingTrashStore(
            root: root.appendingPathComponent("trash"),
            failOnMove: "two.txt",
            failOnRestore: true
        ))

        XCTAssertThrowsError(try service.stage(
            workingCopy: root,
            selectedPaths: ["."],
            statuses: [status("one.txt", .modified), status("two.txt", .modified)],
            recursive: true
        )) { error in
            guard case RevertSafetyError.stageFailed(let operation, let recovery) = error else {
                return XCTFail("Expected combined stage recovery failure, got \(error)")
            }
            XCTAssertFalse(operation.isEmpty)
            XCTAssertTrue(recovery.contains("restore failed"))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RevertSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func status(_ path: String, _ itemStatus: ItemStatus) -> FileStatus {
        FileStatus(path: path, itemStatus: itemStatus, revision: nil, isTreeConflict: false)
    }
}

private final class RecordingTrashStore: RevertTrashStoring, @unchecked Sendable {
    private let root: URL
    private let failOnMove: String?
    private let failOnRestore: Bool

    init(root: URL, failOnMove: String? = nil, failOnRestore: Bool = false) {
        self.root = root
        self.failOnMove = failOnMove
        self.failOnRestore = failOnRestore
    }

    func moveToTrash(_ sourceURL: URL) throws -> URL {
        if sourceURL.lastPathComponent == failOnMove {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString + "-" + sourceURL.lastPathComponent)
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    func restoreFromTrash(_ trashURL: URL, to originalURL: URL) throws {
        if failOnRestore {
            throw SvnError.parse(detail: "restore failed")
        }
        try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: trashURL, to: originalURL)
    }
}
