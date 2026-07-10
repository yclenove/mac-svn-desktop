import XCTest
@testable import MacSvnApp

final class MacSvnAppRouteTests: XCTestCase {
    func testRouteCatalogCoversDocumentedPrimarySurfaces() {
        let routes = MacSvnAppRoute.allCases

        XCTAssertEqual(routes.first, .workspace)
        XCTAssertEqual(routes.last, .settings)
        XCTAssertEqual(Set(routes), [
            .workspace,
            .changes,
            .commit,
            .diff,
            .log,
            .repositoryBrowser,
            .branches,
            .merge,
            .blame,
            .properties,
            .locks,
            .shelve,
            .gitMigration,
            .teamActivity,
            .aiAssistant,
            .releaseNotes,
            .settings
        ])
        XCTAssertEqual(routes.map(\.title), [
            "工作副本",
            "变更",
            "提交",
            "Diff",
            "日志",
            "仓库浏览器",
            "分支与标签",
            "冲突合并",
            "Blame",
            "属性",
            "锁定",
            "本地搁置",
            "Git 迁移",
            "团队动态",
            "AI 助手",
            "Release Notes",
            "设置"
        ])
    }

    func testSidebarModelGroupsRoutesInWorkflowOrder() {
        let model = MacSvnSidebarModel(routes: MacSvnAppRoute.allCases)

        XCTAssertEqual(model.defaultSelection, .workspace)
        XCTAssertEqual(model.sections.map(\.section), [
            .dailyWork,
            .repository,
            .conflictResolution,
            .advancedSVN,
            .automation,
            .settings
        ])
        XCTAssertEqual(model.sections[0].routes, [.workspace, .changes, .commit, .diff, .log])
        XCTAssertEqual(model.sections[1].routes, [.repositoryBrowser, .branches])
        XCTAssertEqual(model.sections[2].routes, [.merge])
        XCTAssertEqual(model.sections[3].routes, [.blame, .properties, .locks, .shelve])
        XCTAssertEqual(model.sections[4].routes, [.gitMigration, .teamActivity, .aiAssistant, .releaseNotes])
        XCTAssertEqual(model.sections[5].routes, [.settings])
    }

    func testRoutesExposeStableCommandIDsAndSidebarSymbols() {
        XCTAssertEqual(MacSvnAppRoute.workspace.commandID, "workspace")
        XCTAssertEqual(MacSvnAppRoute.repositoryBrowser.commandID, "repository-browser")
        XCTAssertEqual(MacSvnAppRoute.gitMigration.commandID, "git-migration")
        XCTAssertEqual(MacSvnAppRoute.aiAssistant.commandID, "ai-assistant")
        XCTAssertEqual(MacSvnAppRoute.releaseNotes.commandID, "release-notes")
        for route in MacSvnAppRoute.allCases {
            XCTAssertFalse(route.systemImage.isEmpty, "\(route) should have an SF Symbol name")
            XCTAssertFalse(route.subtitle.isEmpty, "\(route) should have a placeholder subtitle")
        }
    }
}
