import XCTest
@testable import MacSvnApp
import MacSvnCore

@MainActor
final class MacSvnAppNavigatorTests: XCTestCase {
    func testDeepLinkOpenSetsChangesAndPendingPath() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        navigator.handle(deepLink: .open(path: "/tmp/wc"))

        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.selectedMode, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertEqual(navigator.consumePendingOpenPath(), "/tmp/wc")
        XCTAssertNil(navigator.pendingOpenPath)
    }

    func testDeepLinkLogAndDiffSwitchModes() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(deepLink: .log(target: .path("/repo"), revision: nil))
        XCTAssertEqual(navigator.selectedRoute, .log)
        XCTAssertEqual(navigator.selectedMode, .history)
        XCTAssertEqual(navigator.pendingOpenPath, "/repo")

        navigator.handle(deepLink: .diff(target: .repositoryURL("https://svn.example/r"), range: nil))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.selectedMode, .changes)
    }

    func testCLICommitUICarriesMessage() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(cli: .commitUI(path: "/wc", initialMessage: "fix: demo"))

        XCTAssertEqual(navigator.selectedRoute, .commit)
        XCTAssertEqual(navigator.selectedMode, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/wc")
        XCTAssertEqual(navigator.consumePendingCommitMessage(), "fix: demo")
        XCTAssertNil(navigator.pendingCommitMessage)
    }

    func testCLIStatusOpensChanges() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(cli: .status(path: "/wc"))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/wc")
    }

    func testNavigateToModeUpdatesRoute() {
        let navigator = MacSvnAppNavigator()
        navigator.selectMode(.conflicts)
        XCTAssertEqual(navigator.selectedRoute, .merge)
        navigator.selectMode(.history)
        XCTAssertEqual(navigator.selectedRoute, .log)
    }

    func testCommandPaletteHandoffCarriesQueryToAIChat() {
        let navigator = MacSvnAppNavigator(selectedRoute: .log)
        navigator.handoffCommandPaletteQueryToAIChat("  帮我总结未提交变更  ")

        XCTAssertEqual(navigator.selectedRoute, .aiAssistant)
        XCTAssertEqual(navigator.pendingAIChatQuery, "帮我总结未提交变更")
        XCTAssertEqual(navigator.consumePendingAIChatQuery(), "帮我总结未提交变更")
        XCTAssertNil(navigator.pendingAIChatQuery)
        XCTAssertTrue(navigator.lastAutomationMessage?.contains("⌘K 转 AI") == true)
    }

    func testCommandPaletteHandoffIgnoresBlankQuery() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)
        navigator.handoffCommandPaletteQueryToAIChat("   ")
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertNil(navigator.pendingAIChatQuery)
    }

    func testDismissAutomationBanner() {
        let navigator = MacSvnAppNavigator()
        navigator.lastAutomationMessage = "hello"
        navigator.dismissAutomationBanner()
        XCTAssertNil(navigator.lastAutomationMessage)
    }

    func testPerformCommitNavigatesAndCarriesOptions() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        let result = navigator.perform(
            command: .commit,
            paths: ["/tmp/wc"],
            options: SvnCommandOptions(message: "feat: x")
        )

        XCTAssertEqual(result, .navigated(to: .commit))
        XCTAssertEqual(navigator.lastCommandResult, .navigated(to: .commit))
        XCTAssertEqual(navigator.selectedRoute, .commit)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertEqual(navigator.pendingCommitMessage, "feat: x")
        XCTAssertTrue(navigator.lastAutomationMessage?.contains("提交") == true)
    }

    func testPerformUnimplementedCommandDoesNotPretendSuccess() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)
        let result = navigator.perform(command: .revisionGraph, paths: ["/tmp/wc"])

        XCTAssertEqual(result, .unimplemented(.revisionGraph))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertTrue(navigator.lastAutomationMessage?.hasPrefix("未实现：") == true)
    }

    func testPerformCheckForModificationsDoesNotSetDiffPath() {
        let navigator = MacSvnAppNavigator()
        _ = navigator.perform(command: .checkForModifications, paths: ["/tmp/wc/file.swift"])
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc/file.swift")
        XCTAssertNil(navigator.pendingDiffPath)
    }

    func testPerformDiffSetsPendingDiffPath() {
        let navigator = MacSvnAppNavigator()
        _ = navigator.perform(command: .diff, paths: ["/tmp/wc/a.swift"])
        XCTAssertEqual(navigator.pendingDiffPath, "/tmp/wc/a.swift")
    }

    func testPerformCoversEveryCatalogIDWithoutCrash() {
        let navigator = MacSvnAppNavigator()
        for id in SvnCommandID.allCases {
            let result = navigator.perform(command: id)
            switch result {
            case .navigated:
                XCTAssertNotNil(MacSvnAppNavigator.route(for: id))
            case .unimplemented(let command):
                XCTAssertEqual(command, id)
                XCTAssertNil(MacSvnAppNavigator.route(for: id))
            }
        }
    }
}
