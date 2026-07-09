import XCTest
@testable import MacSvnCore

final class AISVNToolRegistryTests: XCTestCase {
    func testToolNamesClassifyReadOnlyLowRiskAndHighRiskTools() {
        XCTAssertEqual(AISVNToolName.svnStatus.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnLog.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnDiff.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnInfo.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnList.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnBlame.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnCat.risk, .readOnly)

        XCTAssertEqual(AISVNToolName.svnUpdate.risk, .lowRiskWrite)
        XCTAssertEqual(AISVNToolName.svnAdd.risk, .lowRiskWrite)
        XCTAssertEqual(AISVNToolName.svnCleanup.risk, .lowRiskWrite)

        XCTAssertEqual(AISVNToolName.svnCommit.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnRevert.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnMerge.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnSwitch.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnDelete.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnCopy.risk, .highRiskWrite)
    }
}
