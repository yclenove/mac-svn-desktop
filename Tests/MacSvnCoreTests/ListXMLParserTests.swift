import Foundation
import XCTest
@testable import MacSvnCore

final class ListXMLParserTests: XCTestCase {
    func testParsesRemoteEntriesWithMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <lists>
          <list path="file:///repo/trunk">
            <entry kind="dir">
              <name>src</name>
              <commit revision="7">
                <author>yangchao</author>
                <date>2026-07-09T04:00:00.000000Z</date>
              </commit>
            </entry>
            <entry kind="file">
              <name>README.txt</name>
              <size>12</size>
              <commit revision="8">
                <author>alice</author>
                <date>2026-07-09T05:00:00.000000Z</date>
              </commit>
            </entry>
          </list>
        </lists>
        """

        let entries = try ListXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(entries, [
            RemoteEntry(
                name: "src",
                path: "src",
                kind: .directory,
                size: nil,
                revision: Revision(7),
                author: "yangchao",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T04:00:00.000000Z")
            ),
            RemoteEntry(
                name: "README.txt",
                path: "README.txt",
                kind: .file,
                size: 12,
                revision: Revision(8),
                author: "alice",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T05:00:00.000000Z")
            )
        ])
    }

    func testInvalidListXMLThrowsParseError() {
        XCTAssertThrowsError(try ListXMLParser.parse(Data("<lists>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
