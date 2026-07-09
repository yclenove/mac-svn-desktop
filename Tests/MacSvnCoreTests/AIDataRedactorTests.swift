import XCTest
@testable import MacSvnCore

final class AIDataRedactorTests: XCTestCase {
    func testRedactsDefaultSecretPatternsAndReportsMatches() throws {
        let redactor = AIDataRedactor()
        let input = """
        token=sk-1234567890abcdef
        github=ghp_abcdefghijklmnopqrstuvwxyz123456
        aws=AKIAABCDEFGHIJKLMNOP
        -----BEGIN PRIVATE KEY-----
        secret
        -----END PRIVATE KEY-----
        """

        let result = try redactor.redact(input)

        XCTAssertFalse(result.redactedText.contains("sk-1234567890abcdef"))
        XCTAssertFalse(result.redactedText.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(result.redactedText.contains("AKIAABCDEFGHIJKLMNOP"))
        XCTAssertFalse(result.redactedText.contains("BEGIN PRIVATE KEY"))
        XCTAssertEqual(result.matches.map(\.ruleID), [
            "openai-api-key",
            "github-token",
            "aws-access-key-id",
            "private-key-block"
        ])
        XCTAssertTrue(result.didRedact)
    }

    func testRedactsCustomPatternsAfterDefaultRules() throws {
        let redactor = AIDataRedactor()

        let result = try redactor.redact(
            "server=10.0.1.8 employee=YC123",
            customPatterns: ["\\b10\\.0\\.\\d+\\.\\d+\\b", "YC\\d+"]
        )

        XCTAssertEqual(result.redactedText, "server=***REDACTED*** employee=***REDACTED***")
        XCTAssertEqual(result.matches.map(\.ruleID), ["custom:0", "custom:1"])
    }

    func testInvalidCustomPatternThrows() {
        let redactor = AIDataRedactor()

        XCTAssertThrowsError(try redactor.redact("text", customPatterns: ["["])) { error in
            XCTAssertEqual(error as? AIRedactionError, .invalidPattern("["))
        }
    }

    func testAIPrivacySettingsDefaultsToDiffOnlyAndRedactionEnabled() {
        let settings = AIPrivacySettings()

        XCTAssertTrue(settings.isRedactionEnabled)
        XCTAssertTrue(settings.sendsDiffOnly)
        XCTAssertEqual(settings.customRedactionPatterns, [])
    }
}
