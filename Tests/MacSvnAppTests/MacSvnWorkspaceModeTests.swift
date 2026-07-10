import XCTest
@testable import MacSvnApp

final class MacSvnWorkspaceModeTests: XCTestCase {
    func testPrimaryModesAreDailyPath() {
        XCTAssertEqual(
            MacSvnWorkspaceMode.primaryModes,
            [.changes, .history, .browser, .branches, .conflicts]
        )
    }

    func testRouteMappingCollapsesDailySurfacesIntoChanges() {
        XCTAssertEqual(MacSvnWorkspaceMode(route: .workspace), .changes)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .changes), .changes)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .commit), .changes)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .diff), .changes)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .log), .history)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .merge), .conflicts)
        XCTAssertEqual(MacSvnWorkspaceMode(route: .repositoryBrowser), .browser)
    }

    func testPrimaryRouteRoundTripForPrimaryModes() {
        for mode in MacSvnWorkspaceMode.primaryModes {
            let mapped = MacSvnWorkspaceMode(route: mode.primaryRoute)
            XCTAssertEqual(mapped, mode, "\(mode) should round-trip via primaryRoute")
        }
    }

    func testAdvancedAndToolModesCoverRemainingRoutes() {
        let covered = Set(
            MacSvnWorkspaceMode.primaryModes
                + MacSvnWorkspaceMode.advancedModes
                + MacSvnWorkspaceMode.toolModes
        )
        XCTAssertEqual(covered, Set(MacSvnWorkspaceMode.allCases))
    }
}
