import XCTest
@testable import MacSvnCore

final class StatusXMLParserTests: XCTestCase {
    func testParsesMixedStatusesAndTreeConflict() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <status>
          <target path=".">
            <entry path="Sources/App.swift">
              <wc-status item="modified" revision="12"/>
            </entry>
            <entry path="中文/新增.txt">
              <wc-status item="added" revision="0"/>
            </entry>
            <entry path="deleted.txt">
              <wc-status item="deleted" revision="10"/>
            </entry>
            <entry path="conflict.txt">
              <wc-status item="conflicted" revision="11" tree-conflicted="true"/>
            </entry>
            <entry path="ignored.log">
              <wc-status item="ignored"/>
            </entry>
          </target>
        </status>
        """

        let statuses = try StatusXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(statuses.map(\.path), [
            "Sources/App.swift",
            "中文/新增.txt",
            "deleted.txt",
            "conflict.txt",
            "ignored.log"
        ])
        XCTAssertEqual(statuses.map(\.itemStatus), [.modified, .added, .deleted, .conflicted, .ignored])
        XCTAssertEqual(statuses[0].revision, Revision(12))
        XCTAssertTrue(statuses[3].isTreeConflict)
    }

    func testInvalidXMLThrowsParseError() {
        XCTAssertThrowsError(try StatusXMLParser.parse(Data("<status>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
