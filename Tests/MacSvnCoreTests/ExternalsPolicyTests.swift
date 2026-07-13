import XCTest
@testable import MacSvnCore

final class ExternalsPolicyTests: XCTestCase {
    func testParsesPinnedRelativeAndPeggedDefinitionsAndPreservesComments() throws {
        let document = try SvnExternalsDocument(text: """
        # shared tools
        -r25 ^/libs/tools@42 tools
        ../vendor/third-party third-party
        """)

        XCTAssertEqual(document.definitions, [
            SvnExternalDefinition(
                revision: Revision(25),
                url: "^/libs/tools",
                pegRevision: Revision(42),
                localPath: "tools"
            ),
            SvnExternalDefinition(
                revision: nil,
                url: "../vendor/third-party",
                pegRevision: nil,
                localPath: "third-party"
            )
        ])
        XCTAssertTrue(document.render().contains("# shared tools"))
    }

    func testReplacingDefinitionsKeepsCommentsAndRejectsUnsafeLocalPaths() throws {
        let document = try SvnExternalsDocument(text: "# keep\nold-url old\n")
        let replaced = document.replacing(definitions: [
            SvnExternalDefinition(revision: Revision(7), url: "https://svn.example/repo", localPath: "new")
        ])

        XCTAssertEqual(replaced.render(), "# keep\n-r 7 https://svn.example/repo new\n")
        XCTAssertThrowsError(try SvnExternalsPolicy.validateLocalPath("../outside"))
        XCTAssertThrowsError(try SvnExternalsDocument(text: "https://svn.example/repo /absolute"))
        XCTAssertEqual(
            try SvnExternalsDocument(text: "libs/shared local-copy").definitions.first?.url,
            "libs/shared"
        )
    }

    func testLegacyRevisionKeepsPegSemanticsWhenRenderedAsModernSyntax() throws {
        let document = try SvnExternalsDocument(text: "legacy-dir -r10 ^/project")

        XCTAssertEqual(document.definitions, [
            SvnExternalDefinition(
                revision: nil,
                url: "^/project",
                pegRevision: Revision(10),
                localPath: "legacy-dir"
            )
        ])
        XCTAssertEqual(document.render(), "^/project@10 legacy-dir")
    }

    func testRejectsIncompleteRevisionOptions() {
        XCTAssertThrowsError(try SvnExternalsDocument(text: "-r5 local-dir"))
        XCTAssertThrowsError(try SvnExternalsDocument(text: "-r 5"))
        XCTAssertThrowsError(try SvnExternalsDocument(text: "local-dir -r5"))
    }

    func testResolvesAbsoluteAndRelativeWorkingCopyTargets() {
        let workingCopy = URL(fileURLWithPath: "/tmp/wc", isDirectory: true)

        XCTAssertEqual(
            SvnExternalsPolicy.targetURL(workingCopy: workingCopy, path: "vendor").path,
            "/tmp/wc/vendor"
        )
        XCTAssertEqual(
            SvnExternalsPolicy.targetURL(workingCopy: workingCopy, path: "/tmp/wc/vendor").path,
            "/tmp/wc/vendor"
        )
    }

}
