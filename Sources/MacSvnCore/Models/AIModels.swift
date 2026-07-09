import Foundation

public struct AIRedactionMatch: Codable, Equatable, Sendable {
    public let ruleID: String
    public let matchCount: Int

    public init(ruleID: String, matchCount: Int) {
        self.ruleID = ruleID
        self.matchCount = matchCount
    }
}

public struct AIRedactionResult: Codable, Equatable, Sendable {
    public let redactedText: String
    public let matches: [AIRedactionMatch]

    public init(redactedText: String, matches: [AIRedactionMatch]) {
        self.redactedText = redactedText
        self.matches = matches
    }

    public var didRedact: Bool {
        !matches.isEmpty
    }
}

public enum AIRedactionError: Error, Equatable, Sendable {
    case invalidPattern(String)
}

public struct AIPrivacySettings: Codable, Equatable, Sendable {
    public var isRedactionEnabled: Bool
    public var sendsDiffOnly: Bool
    public var customRedactionPatterns: [String]

    public init(
        isRedactionEnabled: Bool = true,
        sendsDiffOnly: Bool = true,
        customRedactionPatterns: [String] = []
    ) {
        self.isRedactionEnabled = isRedactionEnabled
        self.sendsDiffOnly = sendsDiffOnly
        self.customRedactionPatterns = customRedactionPatterns
    }
}
