import Foundation

public struct AIDataRedactor: Sendable {
    public static let replacement = "***REDACTED***"

    private let defaultRules: [RedactionRule] = [
        RedactionRule(ruleID: "openai-api-key", pattern: "sk-[A-Za-z0-9_-]{8,}"),
        RedactionRule(ruleID: "github-token", pattern: "ghp_[A-Za-z0-9_]{20,}"),
        RedactionRule(ruleID: "aws-access-key-id", pattern: "AKIA[0-9A-Z]{16}"),
        RedactionRule(
            ruleID: "private-key-block",
            pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"
        )
    ]

    public init() {}

    public func redact(_ text: String, customPatterns: [String] = []) throws -> AIRedactionResult {
        var redactedText = text
        var matches: [AIRedactionMatch] = []

        let customRules = customPatterns.enumerated().map { index, pattern in
            RedactionRule(ruleID: "custom:\(index)", pattern: pattern)
        }

        for rule in defaultRules + customRules {
            let regex = try regularExpression(for: rule.pattern)
            let range = NSRange(redactedText.startIndex..<redactedText.endIndex, in: redactedText)
            let matchCount = regex.numberOfMatches(in: redactedText, range: range)
            guard matchCount > 0 else {
                continue
            }

            redactedText = regex.stringByReplacingMatches(
                in: redactedText,
                range: range,
                withTemplate: Self.replacement
            )
            matches.append(AIRedactionMatch(ruleID: rule.ruleID, matchCount: matchCount))
        }

        return AIRedactionResult(redactedText: redactedText, matches: matches)
    }

    private func regularExpression(for pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw AIRedactionError.invalidPattern(pattern)
        }
    }
}

private struct RedactionRule: Sendable {
    let ruleID: String
    let pattern: String
}
