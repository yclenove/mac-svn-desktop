import Foundation

public enum AIProviderKind: String, Codable, Equatable, Sendable {
    case openAICompatible
    case anthropic
    case ollama
}

public struct AIProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var model: String
    public var apiKeyRef: String?
    public var maxTokens: Int
    public var temperature: Double
    public var dailyRequestLimit: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        model: String,
        apiKeyRef: String?,
        maxTokens: Int,
        temperature: Double,
        dailyRequestLimit: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKeyRef = apiKeyRef
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.dailyRequestLimit = dailyRequestLimit
    }
}

public struct AIProviderConfigurationFile: Codable, Equatable, Sendable {
    public var version: Int
    public var providers: [AIProvider]
    public var defaultProviderID: UUID?

    public init(
        version: Int = 1,
        providers: [AIProvider] = [],
        defaultProviderID: UUID? = nil
    ) {
        self.version = version
        self.providers = providers
        self.defaultProviderID = defaultProviderID
    }
}

public enum AIProviderError: Error, Equatable, Sendable {
    case emptyName
    case emptyBaseURL
    case emptyModel
    case invalidMaxTokens(Int)
    case invalidTemperature(Double)
    case invalidDailyRequestLimit(Int)
    case providerNotFound(UUID)
}

public struct AIProviderConnectionTestResult: Codable, Equatable, Sendable {
    public let providerID: UUID
    public let latencyMilliseconds: Int
    public let promptTokens: Int
    public let completionTokens: Int

    public init(
        providerID: UUID,
        latencyMilliseconds: Int,
        promptTokens: Int,
        completionTokens: Int
    ) {
        self.providerID = providerID
        self.latencyMilliseconds = latencyMilliseconds
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum AIProviderConnectivityError: Error, Equatable, Sendable {
    case pingFailed(String)
}

public enum AILLMRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct AILLMMessage: Codable, Equatable, Sendable {
    public let role: AILLMRole
    public let content: String

    public init(role: AILLMRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AILLMResponse: Codable, Equatable, Sendable {
    public let content: String
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(content: String, promptTokens: Int?, completionTokens: Int?) {
        self.content = content
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum AICommitMessageFormat: String, Codable, Equatable, Sendable {
    case oneLineChinese
    case conventionalChinese
    case companyTemplate
}

public struct AICommitMessageDraft: Codable, Equatable, Sendable {
    public let message: String
    public let providerID: UUID
    public let sourceFileCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int
    public let usedMapReduce: Bool

    public init(
        message: String,
        providerID: UUID,
        sourceFileCount: Int,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int,
        usedMapReduce: Bool
    ) {
        self.message = message
        self.providerID = providerID
        self.sourceFileCount = sourceFileCount
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
        self.usedMapReduce = usedMapReduce
    }
}

public enum AICommitMessageError: Error, Equatable, Sendable {
    case emptySelection
    case missingDefaultProvider
    case emptyDiff
    case emptyModelResponse
}

public enum AIPreCommitReviewSeverity: String, Codable, Equatable, Sendable {
    case blockingSuggestion
    case generalSuggestion
    case tip
}

public enum AIPreCommitReviewCategory: String, Codable, Equatable, Sendable {
    case correctness
    case security
    case maintainability
    case testing
    case style
    case suspectedSecret
}

public struct AIPreCommitReviewFinding: Codable, Equatable, Sendable {
    public let severity: AIPreCommitReviewSeverity
    public let category: AIPreCommitReviewCategory
    public let path: String?
    public let line: Int?
    public let message: String
    public let rationale: String?

    public init(
        severity: AIPreCommitReviewSeverity,
        category: AIPreCommitReviewCategory,
        path: String?,
        line: Int?,
        message: String,
        rationale: String?
    ) {
        self.severity = severity
        self.category = category
        self.path = path
        self.line = line
        self.message = message
        self.rationale = rationale
    }
}

public struct AIPreCommitReviewResult: Codable, Equatable, Sendable {
    public let summary: String
    public let findings: [AIPreCommitReviewFinding]
    public let providerID: UUID
    public let sourceFileCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int
    public let usedMapReduce: Bool

    public init(
        summary: String,
        findings: [AIPreCommitReviewFinding],
        providerID: UUID,
        sourceFileCount: Int,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int,
        usedMapReduce: Bool
    ) {
        self.summary = summary
        self.findings = findings
        self.providerID = providerID
        self.sourceFileCount = sourceFileCount
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
        self.usedMapReduce = usedMapReduce
    }

    public var hasSuspectedSecretWarning: Bool {
        findings.contains { $0.category == .suspectedSecret }
    }
}

public enum AIPreCommitReviewError: Error, Equatable, Sendable {
    case emptySelection
    case missingDefaultProvider
    case emptyDiff
    case emptyModelResponse
    case invalidModelResponse(String)
}

public enum AIConflictConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct AIConflictAssistContext: Codable, Equatable, Sendable {
    public let path: String
    public let conflictIndex: Int
    public let baseLines: [String]
    public let mineLines: [String]
    public let theirsLines: [String]
    public let leadingContext: [String]
    public let trailingContext: [String]

    public init(
        path: String,
        conflictIndex: Int,
        baseLines: [String],
        mineLines: [String],
        theirsLines: [String],
        leadingContext: [String],
        trailingContext: [String]
    ) {
        self.path = path
        self.conflictIndex = conflictIndex
        self.baseLines = baseLines
        self.mineLines = mineLines
        self.theirsLines = theirsLines
        self.leadingContext = leadingContext
        self.trailingContext = trailingContext
    }
}

public struct AIConflictAssistSuggestion: Codable, Equatable, Sendable {
    public let mergedLines: [String]
    public let rationale: String
    public let confidence: AIConflictConfidence
    public let providerID: UUID
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int

    public init(
        mergedLines: [String],
        rationale: String,
        confidence: AIConflictConfidence,
        providerID: UUID,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int
    ) {
        self.mergedLines = mergedLines
        self.rationale = rationale
        self.confidence = confidence
        self.providerID = providerID
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
    }
}

public struct AIConflictBlockSuggestion: Codable, Equatable, Sendable {
    public let conflictIndex: Int
    public let mergedLines: [String]
    public let rationale: String
    public let confidence: AIConflictConfidence

    public init(
        conflictIndex: Int,
        mergedLines: [String],
        rationale: String,
        confidence: AIConflictConfidence
    ) {
        self.conflictIndex = conflictIndex
        self.mergedLines = mergedLines
        self.rationale = rationale
        self.confidence = confidence
    }
}

public struct AIConflictAssistPreview: Codable, Equatable, Sendable {
    public let suggestions: [AIConflictBlockSuggestion]
    public let providerID: UUID
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int

    public init(
        suggestions: [AIConflictBlockSuggestion],
        providerID: UUID,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int
    ) {
        self.suggestions = suggestions
        self.providerID = providerID
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
    }
}

public enum AIConflictAssistError: Error, Equatable, Sendable {
    case missingDefaultProvider
    case emptyConflict
    case emptyModelResponse
    case invalidModelResponse(String)
}

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
