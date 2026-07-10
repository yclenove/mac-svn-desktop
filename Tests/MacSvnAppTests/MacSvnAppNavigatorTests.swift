import XCTest
@testable import MacSvnApp
import MacSvnCore

@MainActor
final class MacSvnAppNavigatorTests: XCTestCase {
    func testDeepLinkOpenSetsWorkspaceAndPendingPath() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        navigator.handle(deepLink: .open(path: "/tmp/wc"))

        XCTAssertEqual(navigator.selectedRoute, .workspace)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertEqual(navigator.consumePendingOpenPath(), "/tmp/wc")
        XCTAssertNil(navigator.pendingOpenPath)
    }

    func testDeepLinkLogAndDiffSwitchRoutes() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(deepLink: .log(target: .path("/repo"), revision: nil))
        XCTAssertEqual(navigator.selectedRoute, .log)
        XCTAssertEqual(navigator.pendingOpenPath, "/repo")

        navigator.handle(deepLink: .diff(target: .repositoryURL("https://svn.example/r"), range: nil))
        XCTAssertEqual(navigator.selectedRoute, .diff)
    }

    func testCLICommitUICarriesMessage() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(cli: .commitUI(path: "/wc", initialMessage: "fix: demo"))

        XCTAssertEqual(navigator.selectedRoute, .commit)
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
}
