import Foundation
import XCTest
@testable import MacSvnCore

final class CFMColumnConfigurationTests: XCTestCase {
    func testDefaultIncludesAllColumnsWithPathFirst() {
        let config = CFMColumnConfiguration.default
        XCTAssertEqual(config.visibleOrderedIDs.first, .path)
        XCTAssertEqual(Set(config.visibleOrderedIDs), Set(CFMColumnID.allCases))
    }

    func testPathCannotBeHidden() {
        var config = CFMColumnConfiguration.default
        config.setVisible(.path, visible: false)
        XCTAssertTrue(config.isVisible(.path))
    }

    func testToggleOptionalColumns() {
        var config = CFMColumnConfiguration(visibleOrderedIDs: [.path, .textStatus])
        config.setVisible(.revision, visible: true)
        XCTAssertTrue(config.isVisible(.revision))
        config.setVisible(.textStatus, visible: false)
        XCTAssertFalse(config.isVisible(.textStatus))
        XCTAssertEqual(config.visibleOrderedIDs, [.path, .revision])
    }

    func testInitInsertsPathWhenMissing() {
        let config = CFMColumnConfiguration(visibleOrderedIDs: [.revision])
        XCTAssertEqual(config.visibleOrderedIDs.first, .path)
        XCTAssertTrue(config.isVisible(.revision))
    }
}
