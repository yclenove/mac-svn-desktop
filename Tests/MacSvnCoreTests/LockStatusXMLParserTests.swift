import Foundation
import XCTest
@testable import MacSvnCore

final class LockStatusXMLParserTests: XCTestCase {
    func testParsesWorkingCopyOwnedAndRepositoryLocks() throws {
        let xml = """
        <status><target path=".">
          <entry path="mine.txt">
            <wc-status item="normal" revision="1">
              <lock><token>opaquelocktoken:mine</token><owner>yangchao</owner><comment>mine note</comment><created>2026-07-09T11:02:50.061286Z</created></lock>
            </wc-status>
            <repos-status item="none">
              <lock><token>opaquelocktoken:mine</token><owner>yangchao</owner><comment>mine note</comment><created>2026-07-09T11:02:50.061286Z</created></lock>
            </repos-status>
          </entry>
          <entry path="other.txt">
            <wc-status item="normal" revision="1"/>
            <repos-status item="none">
              <lock><token>opaquelocktoken:other</token><owner>alice</owner><comment>other note</comment><created>2026-07-09T11:03:14.059595Z</created></lock>
            </repos-status>
          </entry>
        </target></status>
        """

        let locks = try LockStatusXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(locks, [
            SvnLock(
                target: "mine.txt",
                token: "opaquelocktoken:mine",
                owner: "yangchao",
                comment: "mine note",
                created: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T11:02:50.061286Z"),
                isOwnedByWorkingCopy: true,
                isRepositoryLocked: true
            ),
            SvnLock(
                target: "other.txt",
                token: "opaquelocktoken:other",
                owner: "alice",
                comment: "other note",
                created: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T11:03:14.059595Z"),
                isOwnedByWorkingCopy: false,
                isRepositoryLocked: true
            )
        ])
    }

    func testIgnoresEntriesWithoutLocks() throws {
        let xml = """
        <status><target path="."><entry path="clean.txt"><wc-status item="normal" revision="1"/></entry></target></status>
        """

        XCTAssertEqual(try LockStatusXMLParser.parse(Data(xml.utf8)), [])
    }

    func testInvalidLockStatusXMLThrowsParseError() {
        XCTAssertThrowsError(try LockStatusXMLParser.parse(Data("<status>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
