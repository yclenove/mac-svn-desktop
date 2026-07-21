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
              <date>2026-07-13T10:20:30.000000Z</date>
            </commit>
            <lock>
              <token>opaquelocktoken:abc</token>
              <owner>alice</owner>
              <comment>editing</comment>
              <created>2026-07-13T11:22:33.000000Z</created>
            </lock>
          </entry>
        </info>
        """

        let info = try InfoXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(info.path, ".")
        XCTAssertEqual(info.url, "file:///tmp/repo/trunk")
        XCTAssertEqual(info.repositoryRoot, "file:///tmp/repo")
        XCTAssertEqual(info.revision, Revision(3))
        XCTAssertEqual(info.kind, "dir")
        XCTAssertEqual(info.lastChangedRevision, Revision(3))
        XCTAssertEqual(info.lastChangedAuthor, "yangchao")
        XCTAssertNotNil(info.lastChangedDate)
        XCTAssertEqual(info.lock?.token, "opaquelocktoken:abc")
        XCTAssertEqual(info.lock?.owner, "alice")
        XCTAssertEqual(info.lock?.comment, "editing")
        XCTAssertNotNil(info.lock?.created)
    }

    func testParsesTextConflictFiles() throws {
        let xml = """
        <info>
          <entry path="README.txt" revision="3" kind="file">
            <url>file:///repo/trunk/README.txt</url>
            <conflict>
              <prev-base-file>README.txt.r1</prev-base-file>
              <prev-wc-file>README.txt.mine</prev-wc-file>
              <cur-base-file>README.txt.r3</cur-base-file>
            </conflict>
          </entry>
        </info>
        """

        let info = try InfoXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(info.conflicts, [
            ConflictInfo(
                path: "README.txt",
                kind: .text,
                baseFile: "README.txt.r1",
                mineFile: "README.txt.mine",
                theirsFile: "README.txt.r3",
                treeConflict: nil
            )
        ])
    }

    func testParsesTreeConflictDetails() throws {
        let xml = """
        <info>
          <entry path="src/main.txt" revision="3" kind="file">
            <url>file:///repo/trunk/src/main.txt</url>
            <tree-conflict victim="src/main.txt" kind="file" operation="update" action="delete" reason="edited"/>
          </entry>
        </info>
        """

        let info = try InfoXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(info.conflicts, [
            ConflictInfo(
                path: "src/main.txt",
                kind: .tree,
                baseFile: nil,
                mineFile: nil,
                theirsFile: nil,
                treeConflict: TreeConflictDetails(operation: "update", action: "delete", reason: "edited")
            )
        ])
    }

    func testInvalidXMLThrowsParseError() {
        XCTAssertThrowsError(try InfoXMLParser.parse(Data("<info>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
