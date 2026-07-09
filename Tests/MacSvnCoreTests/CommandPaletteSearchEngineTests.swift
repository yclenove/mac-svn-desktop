import Foundation
import XCTest
@testable import MacSvnCore

final class CommandPaletteSearchEngineTests: XCTestCase {
    func testSearchRanksActionsFilesAndLogs() {
        let engine = CommandPaletteSearchEngine(
            actions: [
                CommandPaletteAction(id: .commit, title: "提交更改", keywords: ["commit", "ci"]),
                CommandPaletteAction(id: .update, title: "更新工作副本", keywords: ["update", "pull"]),
                CommandPaletteAction(id: .switchBranch, title: "切换分支", keywords: ["branch", "switch"])
            ],
            files: [
                CommandPaletteFileItem(path: "Sources/LoginView.swift"),
                CommandPaletteFileItem(path: "Tests/LoginViewTests.swift")
            ],
            logs: [
                LogEntry(revision: Revision(1200), author: "alice", date: nil, message: "修复登录失败", changedPaths: []),
                LogEntry(revision: Revision(1199), author: "bob", date: nil, message: "调整支付回调", changedPaths: [])
            ]
        )

        let actionResults = engine.search("commit")
        let fileResults = engine.search("login view")
        let revisionResults = engine.search("r1200")
        let keywordResults = engine.search("支付")

        XCTAssertEqual(actionResults.first?.kind, .action(.commit))
        XCTAssertEqual(actionResults.first?.title, "提交更改")
        XCTAssertEqual(fileResults.first?.kind, .file(path: "Sources/LoginView.swift"))
        XCTAssertEqual(revisionResults.first?.kind, .log(revision: Revision(1200)))
        XCTAssertEqual(keywordResults.first?.kind, .log(revision: Revision(1199)))
        XCTAssertGreaterThan(actionResults.first?.score ?? 0, 0)
    }
}
