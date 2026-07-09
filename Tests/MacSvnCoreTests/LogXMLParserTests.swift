import XCTest
@testable import MacSvnCore

final class LogXMLParserTests: XCTestCase {
    func testParsesVerboseLogEntries() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <log>
          <logentry revision="42">
            <author>yangchao</author>
            <date>2026-07-09T02:10:00.000000Z</date>
            <msg>修复：登录超时</msg>
            <paths>
              <path action="M" kind="file">/trunk/a.txt</path>
              <path action="A" kind="file" copyfrom-path="/trunk/old.txt" copyfrom-rev="41">/trunk/b.txt</path>
            </paths>
          </logentry>
        </log>
        """

        let entries = try LogXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].revision, Revision(42))
        XCTAssertEqual(entries[0].author, "yangchao")
        XCTAssertEqual(entries[0].message, "修复：登录超时")
        XCTAssertEqual(entries[0].changedPaths, [
            ChangedPath(path: "/trunk/a.txt", action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil),
            ChangedPath(path: "/trunk/b.txt", action: .added, kind: "file", copyFromPath: "/trunk/old.txt", copyFromRevision: Revision(41))
        ])
    }

    func testInvalidXMLThrowsParseError() {
        XCTAssertThrowsError(try LogXMLParser.parse(Data("<log>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
