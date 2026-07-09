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
