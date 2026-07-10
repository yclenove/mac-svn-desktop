import XCTest
@testable import MacSvnCore

final class CFMChangeHighlightTests: XCTestCase {
    func testClassifiesLocalRemoteBothAndConflict() {
        XCTAssertEqual(
            CFMChangeHighlight.classify(FileStatus(
                path: "a", itemStatus: .modified, revision: nil, isTreeConflict: false, remoteItemStatus: nil
            )),
            .localOnly
        )
        XCTAssertEqual(
            CFMChangeHighlight.classify(FileStatus(
                path: "b", itemStatus: .normal, revision: nil, isTreeConflict: false, remoteItemStatus: .modified
            )),
            .remoteOnly
        )
        XCTAssertEqual(
            CFMChangeHighlight.classify(FileStatus(
                path: "c", itemStatus: .modified, revision: nil, isTreeConflict: false, remoteItemStatus: .deleted
            )),
            .both
        )
        XCTAssertEqual(
            CFMChangeHighlight.classify(FileStatus(
                path: "d", itemStatus: .conflicted, revision: nil, isTreeConflict: false, remoteItemStatus: .modified
            )),
            .conflicted
        )
        XCTAssertEqual(
            CFMChangeHighlight.classify(FileStatus(
                path: "e", itemStatus: .modified, revision: nil, isTreeConflict: true, remoteItemStatus: nil
            )),
            .conflicted
        )
    }
}

final class StatusXMLParserRemoteTests: XCTestCase {
    func testParsesReposStatusFromShowUpdatesXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <status>
          <target path=".">
            <entry path="local-only.txt">
              <wc-status item="modified" revision="3"/>
              <repos-status item="none"/>
            </entry>
            <entry path="remote-only.txt">
              <wc-status item="normal" revision="3"/>
              <repos-status item="modified"/>
            </entry>
            <entry path="both.txt">
              <wc-status item="modified" revision="3"/>
              <repos-status item="modified"/>
            </entry>
          </target>
        </status>
        """

        let statuses = try StatusXMLParser.parse(Data(xml.utf8))
        XCTAssertEqual(statuses.map(\.path), ["local-only.txt", "remote-only.txt", "both.txt"])
        XCTAssertEqual(statuses[0].remoteItemStatus, ItemStatus.none)
        XCTAssertEqual(statuses[1].remoteItemStatus, .modified)
        XCTAssertEqual(statuses[2].remoteItemStatus, .modified)
        XCTAssertEqual(CFMChangeHighlight.classify(statuses[0]), .localOnly)
        XCTAssertEqual(CFMChangeHighlight.classify(statuses[1]), .remoteOnly)
        XCTAssertEqual(CFMChangeHighlight.classify(statuses[2]), .both)
    }
}
