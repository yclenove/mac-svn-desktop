import XCTest
@testable import MacSvnCore

final class GitCommandBuilderTests: XCTestCase {
    func testInitRepositoryUsesInit() {
        XCTAssertEqual(GitCommandBuilder.initRepository().arguments, ["init"])
    }

    func testAddAllUsesAddDot() {
        XCTAssertEqual(GitCommandBuilder.addAll().arguments, ["add", "."])
    }

    func testCommitUsesMessage() {
        XCTAssertEqual(
            GitCommandBuilder.commit(message: "Initial SVN snapshot").arguments,
            ["commit", "-m", "Initial SVN snapshot"]
        )
    }
}
