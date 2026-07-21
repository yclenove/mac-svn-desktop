import Foundation
import XCTest
@testable import MacSvnCore

final class ProjectPropertyPolicyTests: XCTestCase {
    func testParsesCommitAndLockConstraintsAndCommitTemplate() {
        let policy = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "12"),
            property("tsvn:logwidthmarker", "72"),
            property("tsvn:logtemplate", "Summary:\n\nDetails:"),
            property("tsvn:logtemplatecommit", "Commit summary:\n\nDetails:"),
            property("tsvn:projectlanguage", "0x0409"),
            property("tsvn:lockmsgminsize", "8")
        ])

        XCTAssertEqual(policy.commit.minimumMessageLength, 12)
        XCTAssertEqual(policy.commit.widthMarker, 72)
        XCTAssertEqual(policy.commit.initialMessage, "Commit summary:\n\nDetails:")
        XCTAssertEqual(policy.projectLanguage, "0x0409")
        XCTAssertEqual(policy.lock.minimumMessageLength, 8)
    }

    func testInvalidNumericValuesSafelyDisableConstraintsAndProduceDiagnostics() {
        let policy = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "not-a-number"),
            property("tsvn:logwidthmarker", "-80"),
            property("tsvn:lockmsgminsize", "-1")
        ])

        XCTAssertNil(policy.commit.minimumMessageLength)
        XCTAssertNil(policy.commit.widthMarker)
        XCTAssertNil(policy.lock.minimumMessageLength)
        XCTAssertEqual(policy.diagnostics.count, 3)
    }

    func testDuplicatePropertiesUseLastValueInsteadOfTrapping() {
        let policy = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "8"),
            property("tsvn:logminsize", "20")
        ])

        XCTAssertEqual(policy.commit.minimumMessageLength, 20)
    }

    func testSimpleBugtraqRegexExtractsIssuesAndBuildsEncodedURLs() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:url", "https://issues.example/browse/%BUGID%"),
            property("bugtraq:logregex", "[Ii]ssue(?:s)? #?(\\d+)")
        ])

        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "Fixes Issue #42 and issue 7"),
            [
                BugtraqIssueReference(identifier: "42", url: "https://issues.example/browse/42"),
                BugtraqIssueReference(identifier: "7", url: "https://issues.example/browse/7")
            ]
        )
    }

    func testBugtraqURLPercentEncodesNonNumericIssueIdentifiers() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:url", "https://issues.example/?id=%BUGID%"),
            property("bugtraq:number", "false"),
            property("bugtraq:logregex", "(ABC&state=closed)")
        ])

        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "Fix ABC&state=closed"),
            [
                BugtraqIssueReference(
                    identifier: "ABC&state=closed",
                    url: "https://issues.example/?id=ABC%26state%3Dclosed"
                )
            ]
        )
    }

    func testTwoStageBugtraqRegexExtractsEveryBareIssueID() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:url", "https://issues.example/%BUGID%"),
            property("bugtraq:logregex", "[Ii]ssues?:?(\\s*(,|and)?\\s*#\\d+)+\n(\\d+)")
        ])

        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "This change resolves issues #23, #24 and #25."),
            [
                BugtraqIssueReference(identifier: "23", url: "https://issues.example/23"),
                BugtraqIssueReference(identifier: "24", url: "https://issues.example/24"),
                BugtraqIssueReference(identifier: "25", url: "https://issues.example/25")
            ]
        )
    }

    func testBugtraqInputModeValidatesNumericIssueIDsAndPrependsOrAppendsMessage() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:message", "Issues: %BUGID%"),
            property("bugtraq:number", "true"),
            property("bugtraq:append", "false")
        ])

        XCTAssertEqual(policy.bugtraq.applyingIssueInput("12, 34", to: "Describe change"), "Issues: 12, 34\nDescribe change")
        XCTAssertNil(policy.bugtraq.applyingIssueInput("ABC-12", to: "Describe change"))
    }

    func testBugtraqInputModeDefaultsToNumericAndCanAppendMessage() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:message", "Refs: %BUGID%"),
            property("bugtraq:append", "true")
        ])

        XCTAssertEqual(policy.bugtraq.applyingIssueInput("99", to: "Describe change"), "Describe change\nRefs: 99")
        XCTAssertNil(policy.bugtraq.applyingIssueInput("ABC-99", to: "Describe change"))
    }

    func testBugtraqMessageMissingPlaceholderDisablesInputMode() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:message", "Related issue")
        ])

        XCTAssertFalse(policy.bugtraq.usesInputMode)
        XCTAssertNil(policy.bugtraq.applyingIssueInput("42", to: "Describe change"))
        XCTAssertEqual(policy.diagnostics, [.bugtraqMessageMissingPlaceholder])
    }

    func testInvalidBugtraqRegexProducesDiagnosticAndDisablesExtraction() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:logregex", "([")
        ])

        XCTAssertEqual(policy.bugtraq.issueReferences(in: "Issue 42"), [])
        XCTAssertEqual(policy.diagnostics, [.invalidBugtraqRegex(value: "([")])
    }

    func testRepositoryRootRelativeBugtraqURLPreservesSchemeSlashes() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:url", "^/issues/%BUGID%"),
            property("bugtraq:logregex", "#(\\d+)")
        ], repositoryRoot: "file:///repo/")

        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "Fix #42"),
            [BugtraqIssueReference(identifier: "42", url: "file:///repo/issues/42")]
        )
    }

    func testRepositoryRootRelativeBugtraqURLWithoutRootIsDisabledAndDiagnosed() {
        let policy = ProjectPropertyPolicy(properties: [
            property("bugtraq:url", "^/issues/%BUGID%"),
            property("bugtraq:logregex", "#(\\d+)")
        ])

        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "Fix #42"),
            [BugtraqIssueReference(identifier: "42", url: nil)]
        )
        XCTAssertTrue(policy.diagnostics.contains(.bugtraqRepositoryRootUnavailable))
    }

    func testParsesAllOperationSpecificLogTemplates() {
        let policy = ProjectPropertyPolicy(properties: [
            property("tsvn:logtemplate", "Generic"),
            property("tsvn:logtemplatebranch", "Branch"),
            property("tsvn:logtemplateimport", "Import"),
            property("tsvn:logtemplatedelete", "Delete"),
            property("tsvn:logtemplatemove", "Move"),
            property("tsvn:logtemplatemkdir", "Mkdir"),
            property("tsvn:logtemplatepropset", "Property"),
            property("tsvn:logtemplatelock", "Lock")
        ])

        XCTAssertEqual(policy.initialMessage(for: .branch), "Branch")
        XCTAssertEqual(policy.initialMessage(for: .import), "Import")
        XCTAssertEqual(policy.initialMessage(for: .delete), "Delete")
        XCTAssertEqual(policy.initialMessage(for: .move), "Move")
        XCTAssertEqual(policy.initialMessage(for: .mkdir), "Mkdir")
        XCTAssertEqual(policy.initialMessage(for: .propset), "Property")
        XCTAssertEqual(policy.initialMessage(for: .lock), "Lock")
        XCTAssertEqual(policy.initialMessage(for: .commit), "Generic")
    }

    func testProjectLanguageMapsWindowsLocaleIdentifierToSpellcheckLanguage() {
        XCTAssertEqual(ProjectSpellcheckLanguage.resolve("0x0409"), "en_US")
        XCTAssertEqual(ProjectSpellcheckLanguage.resolve("zh_Hans"), "zh_Hans")
        XCTAssertNil(ProjectSpellcheckLanguage.resolve(nil))
    }

    func testAncestorPropertySetsMergeWithNearerDirectoryTakingPrecedence() {
        let policy = ProjectPropertyPolicy(propertySets: [
            [
                property("tsvn:logminsize", "10"),
                property("tsvn:logtemplate", "Root template"),
                property("bugtraq:url", "https://root.example/%BUGID%")
            ],
            [
                property("tsvn:logminsize", "20"),
                property("bugtraq:logregex", "#(\\d+)")
            ]
        ])

        XCTAssertEqual(policy.commit.minimumMessageLength, 20)
        XCTAssertEqual(policy.commit.initialMessage, "Root template")
        XCTAssertEqual(
            policy.bugtraq.issueReferences(in: "Fix #7"),
            [BugtraqIssueReference(identifier: "7", url: "https://root.example/7")]
        )
    }

    func testCombiningMultiplePathPoliciesUsesStrictestConstraints() {
        let policyA = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "20"),
            property("tsvn:logwidthmarker", "72"),
            property("tsvn:lockmsgminsize", "12"),
            property("bugtraq:message", "Issue: %BUGID%")
        ])
        let policyB = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "8"),
            property("tsvn:logwidthmarker", "100"),
            property("tsvn:lockmsgminsize", "4")
        ])

        let combined = ProjectPropertyPolicy.combining([policyA, policyB])

        XCTAssertEqual(combined.commit.minimumMessageLength, 20)
        XCTAssertEqual(combined.commit.widthMarker, 72)
        XCTAssertEqual(combined.lock.minimumMessageLength, 12)
        XCTAssertFalse(combined.bugtraq.usesInputMode)
        XCTAssertTrue(combined.diagnostics.contains(.conflictingProjectProperty("bugtraq:*")))
    }

    func testCommitAndLockPoliciesBlockShortMessagesButOnlyWarnForWidth() {
        let properties = ProjectPropertyPolicy(properties: [
            property("tsvn:logminsize", "10"),
            property("tsvn:logwidthmarker", "8"),
            property("tsvn:lockmsgminsize", "6")
        ])

        XCTAssertEqual(CommitMessagePolicy.validationError(for: "short", properties: properties), .belowMinimumLength(required: 10, actual: 5))
        XCTAssertEqual(CommitMessagePolicy.overlongLineNumbers(in: "123456789\nok", properties: properties), [1])
        XCTAssertEqual(LockMessagePolicy.validationError(for: "note", properties: properties), .belowMinimumLength(required: 6, actual: 4))
    }

    private func property(_ name: String, _ value: String) -> SvnProperty {
        SvnProperty(target: ".", name: name, value: value)
    }
}
