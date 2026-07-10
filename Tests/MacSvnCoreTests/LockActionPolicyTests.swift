import Foundation
import XCTest
@testable import MacSvnCore

final class LockActionPolicyTests: XCTestCase {
    func testReleasePrefersWorkingCopyOwnedLocks() {
        let locks = [
            lock("a.txt", owned: true, repo: true),
            lock("b.txt", owned: false, repo: true)
        ]
        XCTAssertEqual(
            LockActionPolicy.pathsEligibleForRelease(selected: ["a.txt", "b.txt"], locks: locks),
            ["a.txt"]
        )
    }

    func testReleaseReturnsEmptyWhenSelectionHasNoOwnedLocks() {
        let locks = [lock("b.txt", owned: false, repo: true)]
        XCTAssertEqual(
            LockActionPolicy.pathsEligibleForRelease(selected: ["b.txt"], locks: locks),
            []
        )
    }

    func testReleaseFallsBackToSelectedWhenNoLockInfo() {
        XCTAssertEqual(
            LockActionPolicy.pathsEligibleForRelease(selected: ["x.txt"], locks: []),
            ["x.txt"]
        )
    }

    func testBreakPrefersRepositoryLockedPaths() {
        let locks = [
            lock("a.txt", owned: true, repo: true),
            lock("b.txt", owned: false, repo: false)
        ]
        XCTAssertEqual(
            LockActionPolicy.pathsEligibleForBreak(selected: ["a.txt", "b.txt"], locks: locks),
            ["a.txt"]
        )
    }

    func testBreakReturnsEmptyWhenSelectionHasNoRepoLocks() {
        let locks = [lock("b.txt", owned: false, repo: false)]
        XCTAssertEqual(
            LockActionPolicy.pathsEligibleForBreak(selected: ["b.txt"], locks: locks),
            []
        )
    }

    func testConfirmationRules() {
        XCTAssertTrue(LockActionPolicy.requiresConfirmation(.breakLock))
        XCTAssertTrue(LockActionPolicy.requiresConfirmation(.getLock, steal: true))
        XCTAssertFalse(LockActionPolicy.requiresConfirmation(.getLock, steal: false))
        XCTAssertFalse(LockActionPolicy.requiresConfirmation(.releaseLock))
    }

    private func lock(_ path: String, owned: Bool, repo: Bool) -> SvnLock {
        SvnLock(
            target: path,
            token: "t",
            owner: "u",
            comment: nil,
            created: nil,
            isOwnedByWorkingCopy: owned,
            isRepositoryLocked: repo
        )
    }
}
