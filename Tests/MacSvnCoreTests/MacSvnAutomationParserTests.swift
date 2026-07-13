import Foundation
import XCTest
@testable import MacSvnCore

final class MacSvnAutomationParserTests: XCTestCase {
    func testDeepLinkParserParsesOpenLogAndDiffActions() throws {
        let parser = MacSvnDeepLinkParser()

        let open = try parser.parse(URL(string: "svnstudio://open?path=/Users/me/repo")!)
        let log = try parser.parse(URL(string: "svnstudio://log?url=https%3A%2F%2Fsvn.example.com%2Frepo%2Ftrunk&rev=r1200")!)
        let diff = try parser.parse(URL(string: "svnstudio://diff?path=Sources%2FApp.swift&from=1199&to=1200")!)
        let command = try parser.parse(URL(string: "svnstudio://command?path=/Users/me/repo&command=cmd.15.deleteKeepLocal")!)

        XCTAssertEqual(open, .open(path: "/Users/me/repo"))
        XCTAssertEqual(log, .log(target: .repositoryURL("https://svn.example.com/repo/trunk"), revision: Revision(1200)))
        XCTAssertEqual(diff, .diff(target: .path("Sources/App.swift"), range: RevisionRange(start: Revision(1199), end: Revision(1200))))
        XCTAssertEqual(command, .command(command: .deleteKeepLocal, paths: ["/Users/me/repo"]))
    }

    func testDeepLinkParserPreservesRepeatedCommandPaths() throws {
        let parser = MacSvnDeepLinkParser()
        let command = try parser.parse(URL(string: "svnstudio://command?path=%2Frepo%2Ffirst&path=%2Frepo%2Fsecond&command=cmd.15.deleteKeepLocal")!)

        XCTAssertEqual(
            command,
            .command(command: .deleteKeepLocal, paths: ["/repo/first", "/repo/second"])
        )
    }

    func testDeepLinkParserRejectsInvalidSchemeUnknownRouteMissingTargetAndBadRevision() throws {
        let parser = MacSvnDeepLinkParser()

        XCTAssertThrowsError(try parser.parse(URL(string: "https://open?path=/repo")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .invalidScheme("https"))
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "svnstudio://blame?path=/repo/file.swift")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .unknownRoute("blame"))
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "svnstudio://log?rev=1")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .missingTarget)
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "svnstudio://log?path=/repo&rev=abc")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .invalidRevision("abc"))
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "svnstudio://command?path=/repo&command=cmd.999")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .unknownCommand("cmd.999"))
        }
    }

    func testCLICommandParserParsesOpenStatusAndCommitUICommands() throws {
        let parser = MacSvnCLICommandParser()

        XCTAssertEqual(try parser.parse(["open", "/Users/me/repo"]), .open(path: "/Users/me/repo"))
        XCTAssertEqual(try parser.parse(["status", "/Users/me/repo"]), .status(path: "/Users/me/repo"))
        XCTAssertEqual(
            try parser.parse(["commit-ui", "/Users/me/repo", "--message", "修复登录失败"]),
            .commitUI(path: "/Users/me/repo", initialMessage: "修复登录失败")
        )
    }

    func testCLICommandParserRejectsEmptyUnknownMissingAndUnexpectedArguments() {
        let parser = MacSvnCLICommandParser()

        XCTAssertThrowsError(try parser.parse([])) { error in
            XCTAssertEqual(error as? MacSvnCLICommandParserError, .emptyArguments)
        }
        XCTAssertThrowsError(try parser.parse(["blame", "/repo/file.swift"])) { error in
            XCTAssertEqual(error as? MacSvnCLICommandParserError, .unknownCommand("blame"))
        }
        XCTAssertThrowsError(try parser.parse(["open"])) { error in
            XCTAssertEqual(error as? MacSvnCLICommandParserError, .missingValue("path"))
        }
        XCTAssertThrowsError(try parser.parse(["status", "/repo", "--json"])) { error in
            XCTAssertEqual(error as? MacSvnCLICommandParserError, .unexpectedArgument("--json"))
        }
        XCTAssertThrowsError(try parser.parse(["commit-ui", "/repo", "--message"])) { error in
            XCTAssertEqual(error as? MacSvnCLICommandParserError, .missingValue("--message"))
        }
    }
}
