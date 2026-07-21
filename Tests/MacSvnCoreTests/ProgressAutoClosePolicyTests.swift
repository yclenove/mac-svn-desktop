import XCTest
@testable import MacSvnCore

final class ProgressAutoClosePolicyTests: XCTestCase {
    func testManualModeNeverCloses() {
        XCTAssertFalse(ProgressAutoClosePolicy.shouldClose(
            mode: .manual,
            outcome: .successful,
            isLocalOperation: true
        ))
    }

    func testNoErrorsModeClosesSuccessfulAndConflictOperations() {
        XCTAssertTrue(ProgressAutoClosePolicy.shouldClose(
            mode: .noErrors,
            outcome: .successful,
            isLocalOperation: false
        ))
        XCTAssertTrue(ProgressAutoClosePolicy.shouldClose(
            mode: .noErrors,
            outcome: .conflicted,
            isLocalOperation: false
        ))
        XCTAssertFalse(ProgressAutoClosePolicy.shouldClose(
            mode: .noErrors,
            outcome: .failed,
            isLocalOperation: false
        ))
    }

    func testNoConflictsModeKeepsConflictedProgressOpen() {
        XCTAssertTrue(ProgressAutoClosePolicy.shouldClose(
            mode: .noConflicts,
            outcome: .successful,
            isLocalOperation: false
        ))
        XCTAssertFalse(ProgressAutoClosePolicy.shouldClose(
            mode: .noConflicts,
            outcome: .conflicted,
            isLocalOperation: false
        ))
    }

    func testNoMergesModeKeepsMergeAddsAndDeletesOpen() {
        XCTAssertFalse(ProgressAutoClosePolicy.shouldClose(
            mode: .noMerges,
            outcome: .merged,
            isLocalOperation: false
        ))
        XCTAssertTrue(ProgressAutoClosePolicy.shouldClose(
            mode: .noMerges,
            outcome: .successful,
            isLocalOperation: true
        ))
        XCTAssertTrue(ProgressAutoClosePolicy.shouldClose(
            mode: .noMerges,
            outcome: .merged,
            isLocalOperation: true
        ))
    }

    func testProgressAutoCloseModePersistsInAppSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnProgressSettings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        var settings = await store.settings()
        XCTAssertEqual(settings.progressAutoCloseMode, .noConflicts)
        settings.progressAutoCloseMode = .noMerges
        try await store.update(settings)

        let reloaded = try await SettingsStore(fileURL: root.appendingPathComponent("settings.json")).load()
        XCTAssertEqual(reloaded.progressAutoCloseMode, .noMerges)
    }
}
