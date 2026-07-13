import Foundation
import XCTest
@testable import MacSvnCore

final class RemoteInfoXMLParserTests: XCTestCase {
    func testParsesImmediateChildrenAndRepositoryLockDetails() throws {
        let xml = """
        <info>
          <entry path="trunk" revision="8" kind="dir">
            <url>file:///repo/trunk</url>
            <commit revision="8"><author>yangchao</author><date>2026-07-13T04:00:00.000000Z</date></commit>
          </entry>
          <entry path="docs" revision="7" kind="dir">
            <url>file:///repo/trunk/docs</url>
            <commit revision="7"><author>alice</author><date>2026-07-13T03:00:00.000000Z</date></commit>
          </entry>
          <entry path="locked.txt" revision="8" kind="file" size="12">
            <url>file:///repo/trunk/locked.txt</url>
            <commit revision="8"><author>yangchao</author><date>2026-07-13T04:00:00.000000Z</date></commit>
            <lock>
              <token>opaquelocktoken:locked</token>
              <owner>yangchao</owner>
              <comment>editing note</comment>
              <created>2026-07-13T04:02:50.061286Z</created>
            </lock>
          </entry>
        </info>
        """

        let entries = try RemoteInfoXMLParser.parseDirectoryEntries(
            Data(xml.utf8),
            targetURL: "file:///repo/trunk"
        )

        XCTAssertEqual(entries, [
            RemoteEntry(
                name: "docs",
                path: "docs",
                kind: .directory,
                size: nil,
                revision: Revision(7),
                author: "alice",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-13T03:00:00.000000Z")
            ),
            RemoteEntry(
                name: "locked.txt",
                path: "locked.txt",
                kind: .file,
                size: 12,
                revision: Revision(8),
                author: "yangchao",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-13T04:00:00.000000Z"),
                lock: RemoteLockInfo(
                    token: "opaquelocktoken:locked",
                    owner: "yangchao",
                    comment: "editing note",
                    created: ISO8601DateFormatter.svnXML.date(from: "2026-07-13T04:02:50.061286Z")
                )
            )
        ])
    }

    func testInvalidRemoteInfoXMLThrowsParseError() {
        XCTAssertThrowsError(
            try RemoteInfoXMLParser.parseDirectoryEntries(
                Data("<info>".utf8),
                targetURL: "file:///repo/trunk"
            )
        ) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
