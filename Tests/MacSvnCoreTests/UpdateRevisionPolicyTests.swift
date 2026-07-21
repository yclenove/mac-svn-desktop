import XCTest
@testable import MacSvnCore

final class UpdateRevisionPolicyTests: XCTestCase {
    func testPinsHeadOnlyForMultiPathWithoutExplicitRevision() {
        XCTAssertTrue(UpdateRevisionPolicy.shouldPinRepositoryHead(
            paths: ["a.txt", "b.txt"],
            revision: nil
        ))
        XCTAssertFalse(UpdateRevisionPolicy.shouldPinRepositoryHead(
            paths: ["a.txt"],
            revision: nil
        ))
        XCTAssertFalse(UpdateRevisionPolicy.shouldPinRepositoryHead(
            paths: [],
            revision: nil
        ))
        XCTAssertFalse(UpdateRevisionPolicy.shouldPinRepositoryHead(
            paths: ["a.txt", "b.txt"],
            revision: Revision(10)
        ))
    }

    func testHeadProbePrefersFirstConcretePath() {
        XCTAssertEqual(UpdateRevisionPolicy.headProbeTarget(paths: ["src", "docs"]), "src")
        XCTAssertEqual(UpdateRevisionPolicy.headProbeTarget(paths: []), ".")
    }
}
