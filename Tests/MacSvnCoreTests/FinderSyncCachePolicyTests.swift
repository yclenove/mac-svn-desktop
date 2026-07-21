import XCTest
@testable import MacSvnCore

final class FinderSyncCachePolicyTests: XCTestCase {
    func testDefaultModeUsesRootSnapshotCache() {
        let policy = FinderSyncCachePolicy(mode: .defaultCache)

        XCTAssertEqual(policy.statusScope(requestedTarget: "src/App.swift"), ".")
        XCTAssertEqual(policy.cacheTTL, 8)
        XCTAssertTrue(policy.collectsBadges)
    }

    func testShellModeUsesRequestedTargetWithShortCache() {
        let policy = FinderSyncCachePolicy(mode: .shell)

        XCTAssertEqual(policy.statusScope(requestedTarget: "src/App.swift"), "src/App.swift")
        XCTAssertEqual(policy.cacheTTL, 2)
        XCTAssertTrue(policy.collectsBadges)
    }

    func testNoneModeDisablesStatusCollection() {
        let policy = FinderSyncCachePolicy(mode: .none)

        XCTAssertNil(policy.statusScope(requestedTarget: "src/App.swift"))
        XCTAssertEqual(policy.cacheTTL, 0)
        XCTAssertFalse(policy.collectsBadges)
    }
}
