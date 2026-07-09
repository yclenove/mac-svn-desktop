import Foundation
import XCTest
@testable import MacSvnCore

final class InfoXMLParserTests: XCTestCase {
    func testParsesWorkingCopyInfo() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <info>
          <entry path="." revision="3" kind="dir">
            <url>file:///tmp/repo/trunk</url>
            <relative-url>^/trunk</relative-url>
            <repository>
              <root>file:///tmp/repo</root>
              <uuid>abc-123</uuid>
            </repository>
            <wc-info>
              <wcroot-abspath>/tmp/wc</wcroot-abspath>
            </wc-info>
            <commit revision="3">
              <author>yangchao</author>
            </commit>
          </entry>
        </info>
        """

        let info = try InfoXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(info.path, ".")
        XCTAssertEqual(info.url, "file:///tmp/repo/trunk")
        XCTAssertEqual(info.repositoryRoot, "file:///tmp/repo")
        XCTAssertEqual(info.revision, Revision(3))
        XCTAssertEqual(info.kind, "dir")
    }

    func testInvalidXMLThrowsParseError() {
        XCTAssertThrowsError(try InfoXMLParser.parse(Data("<info>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
