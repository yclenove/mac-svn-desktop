import Foundation
import XCTest
@testable import MacSvnCore

final class BlameXMLParserTests: XCTestCase {
    func testParsesBlameLinesWithCommitMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <blame>
          <target path="README.txt">
            <entry line-number="1">
              <commit revision="7">
                <author>yangchao</author>
                <date>2026-07-09T06:00:00.000000Z</date>
              </commit>
            </entry>
            <entry line-number="2">
              <commit revision="8">
                <author>alice</author>
                <date>2026-07-09T07:00:00.000000Z</date>
              </commit>
            </entry>
          </target>
        </blame>
        """

        let lines = try BlameXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(lines, [
            BlameLine(
                lineNumber: 1,
                revision: Revision(7),
                author: "yangchao",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T06:00:00.000000Z")
            ),
            BlameLine(
                lineNumber: 2,
                revision: Revision(8),
                author: "alice",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T07:00:00.000000Z")
            )
        ])
    }

    func testParsesLineWithMissingCommitMetadata() throws {
        let xml = """
        <blame><target path="README.txt"><entry line-number="1"/></target></blame>
        """

        let lines = try BlameXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(lines, [
            BlameLine(lineNumber: 1, revision: nil, author: nil, date: nil)
        ])
    }

    func testInvalidBlameXMLThrowsParseError() {
        XCTAssertThrowsError(try BlameXMLParser.parse(Data("<blame>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
