import XCTest
@testable import MacSvnApp
import MacSvnCore

private actor StubInfoProvider: WorkingCopyInfoProviding {
    func info(wc: URL, target: String) async throws -> SvnInfo {
        SvnInfo(
            path: wc.path,
            url: "file:///tmp/repo/trunk",
            repositoryRoot: "file:///tmp/repo",
            revision: 12,
            kind: "dir"
        )
    }
}

final class MacSvnWorkspaceControllerTests: XCTestCase {
    @MainActor
    func testAddInvalidDirectorySetsErrorMessage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-wc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json"))
        let controller = MacSvnWorkspaceController(workspaceStore: store, infoProvider: StubInfoProvider())
        let notWC = root.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: notWC, withIntermediateDirectories: true)

        await controller.addWorkingCopy(at: notWC)

        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.records.isEmpty)
    }
}
