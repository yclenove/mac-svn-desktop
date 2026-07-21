import XCTest
@testable import MacSvnCore

final class FinderSyncInfoXMLParserTests: XCTestCase {
    func testParsesSparseDepthForEachWorkingCopyEntry() throws {
        let xml = """
        <info>
          <entry path="." revision="4" kind="dir"><wc-info><depth>infinity</depth></wc-info></entry>
          <entry path="docs" revision="4" kind="dir"><wc-info><depth>files</depth></wc-info></entry>
          <entry path="src" revision="4" kind="dir"><wc-info><depth>immediates</depth></wc-info></entry>
        </info>
        """

        let depths = try FinderSyncInfoXMLParser.parseDepths(Data(xml.utf8))

        XCTAssertEqual(depths, [".": .infinity, "docs": .files, "src": .immediates])
    }

    func testInvalidInfoXMLThrowsParseError() {
        XCTAssertThrowsError(try FinderSyncInfoXMLParser.parseDepths(Data("<info>".utf8)))
    }
}
