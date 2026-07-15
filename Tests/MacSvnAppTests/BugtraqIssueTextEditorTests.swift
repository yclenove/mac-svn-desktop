import AppKit
import XCTest
@testable import MacSvnApp

final class BugtraqIssueTextEditorTests: XCTestCase {
    func testCompletionCandidatesIncludePathsBasenamesStemsAndHistoryTermsWithoutDuplicates() {
        let candidates = CommitMessageCompletionCandidates.build(
            paths: [
                "Sources/Auth/LoginController.swift",
                "README.md",
                "Sources/Auth/LoginController.swift"
            ],
            recentMessages: [
                "fix login timeout",
                "更新登录流程"
            ],
            timeout: 5,
            now: { 0 }
        )

        XCTAssertEqual(candidates, [
            "Sources/Auth/LoginController.swift",
            "LoginController.swift",
            "LoginController",
            "README.md",
            "README",
            "fix",
            "login",
            "timeout",
            "更新登录流程"
        ])
    }

    func testCompletionCandidateBuildStopsWhenTimeoutExpires() {
        var timestamp = -0.25

        let candidates = CommitMessageCompletionCandidates.build(
            paths: ["First.swift", "Second.swift"],
            recentMessages: ["third fourth"],
            timeout: 0.5,
            now: {
                timestamp += 0.25
                return timestamp
            }
        )

        XCTAssertEqual(candidates, ["First.swift", "First"])
    }

    func testCompletionCandidateBuildStopsInsideSingleHistoryMessage() {
        var timestamps = [0.0, 0.1, 0.2, 0.6]

        let candidates = CommitMessageCompletionCandidates.build(
            paths: [],
            recentMessages: ["first second third"],
            timeout: 0.5,
            now: { timestamps.removeFirst() }
        )

        XCTAssertEqual(candidates, ["first"])
    }

    func testCompletionMatchesAreCaseInsensitivePrefixMatchesAndExcludeExactPartial() {
        let matches = CommitMessageCompletionCandidates.matches(
            candidates: ["LoginController", "login", "logout", "timeout"],
            partial: "log"
        )

        XCTAssertEqual(matches, ["LoginController", "login", "logout"])
        XCTAssertEqual(
            CommitMessageCompletionCandidates.matches(candidates: ["login"], partial: "login"),
            []
        )
    }

    func testCompletionBuildAndMatchesHaveExplicitCandidateLimits() {
        let candidates = CommitMessageCompletionCandidates.build(
            paths: (0..<20).map { "Sources/File\($0).swift" },
            recentMessages: [],
            timeout: 5,
            maxCandidates: 7,
            now: { 0 }
        )
        let index = CommitMessageCompletionIndex(candidates: (0..<50).map { "feature-\($0)" })

        XCTAssertEqual(candidates.count, 7)
        XCTAssertEqual(index.matches(partial: "fea", maxResults: 5).count, 5)
        XCTAssertEqual(index.matches(partial: "zzz", maxResults: 5), [])
    }

    func testSingleRegexHighlightsCaptureGroupsOnly() {
        let text = "Fixes issue #42 and issue #7"

        let ranges = BugtraqIssueHighlighting.ranges(
            for: ["[Ii]ssue #?(\\d+)"],
            in: text
        )

        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["42", "7"])
    }

    func testTwoStageRegexHighlightsInnerCaptureGroups() {
        let text = "Refs: #23, #24"

        let ranges = BugtraqIssueHighlighting.ranges(
            for: ["Refs:.*", "#(\\d+)"],
            in: text
        )

        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["23", "24"])
    }
}
