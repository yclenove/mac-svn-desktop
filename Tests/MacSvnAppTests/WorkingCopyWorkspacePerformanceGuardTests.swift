import Foundation
import XCTest

/// 源码级门禁：变更工作区不得再引入嵌套 Split（AttributeGraph 卡死根因）。
final class WorkingCopyWorkspacePerformanceGuardTests: XCTestCase {
    func testWorkingCopyWorkspaceViewAvoidsSplitViews() throws {
        let source = try Self.readFeatureSource(named: "MacSvnWorkingCopyWorkspaceView.swift")
        // 注释里可以点名禁令；禁止的是实际 SwiftUI 用法（`XxxSplitView {`）
        XCTAssertFalse(
            source.contains("VSplitView {"),
            "变更工作区禁止 VSplitView，避免与子视图嵌套触发 AttributeGraph 死循环"
        )
        XCTAssertFalse(
            source.contains("HSplitView {"),
            "变更工作区禁止 HSplitView，应使用固定 HStack/VStack + frame"
        )
        XCTAssertTrue(
            source.contains("AttributeGraph") || source.contains("嵌套"),
            "须保留性能风险中文注释，防止后续误改"
        )
    }

    func testEmbeddedDiffPathUsesPerformanceLimitsAPI() throws {
        let source = try Self.readFeatureSource(named: "MacSvnDiffView.swift")
        XCTAssertTrue(
            source.contains("DiffPerformanceLimits"),
            "Diff 视图必须走 DiffPerformanceLimits，禁止散落魔法数字阈值"
        )
        XCTAssertTrue(
            source.contains("truncatedDisplayText"),
            "超大 Diff 必须经 truncatedDisplayText 截断展示"
        )
    }

    func testMergeUnifiedDiffUsesPerformanceLimitsAPI() throws {
        let source = try Self.readFeatureSource(named: "MacSvnMergeWizardView.swift")
        XCTAssertTrue(source.contains("DiffPerformanceLimits"))
        XCTAssertTrue(
            source.contains("truncatedDisplayText"),
            "Merge Unified Diff 必须截断超大文本，避免 SwiftUI 一次渲染全部内容"
        )
    }

    func testEmbeddedCommitViewAvoidsSplitViewInEmbeddedBranch() throws {
        let source = try Self.readFeatureSource(named: "MacSvnCommitView.swift")
        // 嵌入分支须用 HStack；独立页仍可用 HSplitView
        XCTAssertTrue(
            source.contains("if embedded"),
            "Commit 须区分 embedded 布局"
        )
        XCTAssertTrue(
            source.contains("嵌入变更工作区禁止 HSplitView") || source.contains("AttributeGraph"),
            "须保留嵌入禁止 Split 的说明"
        )
    }

    private static func readFeatureSource(named fileName: String) throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        // Tests/MacSvnAppTests/... → 仓库根
        let repoRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
            .appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
