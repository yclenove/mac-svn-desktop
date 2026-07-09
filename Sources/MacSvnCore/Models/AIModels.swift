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

public enum AISVNToolRisk: String, Codable, Equatable, Sendable {
    case readOnly
    case lowRiskWrite
    case highRiskWrite
}

public enum AISVNToolName: String, Codable, CaseIterable, Equatable, Sendable {
    case svnStatus = "svn_status"
    case svnLog = "svn_log"
    case svnDiff = "svn_diff"
    case svnInfo = "svn_info"
    case svnList = "svn_list"
    case svnBlame = "svn_blame"
    case svnCat = "svn_cat"
    case svnUpdate = "svn_update"
    case svnAdd = "svn_add"
    case svnCleanup = "svn_cleanup"
    case svnCommit = "svn_commit"
    case svnRevert = "svn_revert"
    case svnMerge = "svn_merge"
    case svnSwitch = "svn_switch"
    case svnDelete = "svn_delete"
    case svnCopy = "svn_copy"

    public var risk: AISVNToolRisk {
        switch self {
        case .svnStatus, .svnLog, .svnDiff, .svnInfo, .svnList, .svnBlame, .svnCat:
            return .readOnly
        case .svnUpdate, .svnAdd, .svnCleanup:
            return .lowRiskWrite
        case .svnCommit, .svnRevert, .svnMerge, .svnSwitch, .svnDelete, .svnCopy:
            return .highRiskWrite
        }
    }
}

public struct AISVNToolCall: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct AISVNToolResult: Codable, Equatable, Sendable {
    public let content: String
    public let metadata: [String: String]

    public init(content: String, metadata: [String: String] = [:]) {
        self.content = content
        self.metadata = metadata
    }
}

public struct AISVNToolConfirmation: Codable, Equatable, Sendable {
    public let id: UUID
    public let toolName: String
    public let risk: AISVNToolRisk
    public let commandPreview: String
    public let impactPaths: [String]
    public let warning: String

    public init(
        id: UUID = UUID(),
        toolName: String,
        risk: AISVNToolRisk,
        commandPreview: String,
        impactPaths: [String],
        warning: String
    ) {
        self.id = id
        self.toolName = toolName
        self.risk = risk
        self.commandPreview = commandPreview
        self.impactPaths = impactPaths
        self.warning = warning
    }
}

public enum AISVNToolDecision: Equatable, Sendable {
    case completed(AISVNToolResult)
    case confirmationRequired(AISVNToolConfirmation)
}

public enum AISVNToolAuditOutcome: String, Codable, Equatable, Sendable {
    case completed
    case confirmationRequired
    case failed
}

public struct AISVNToolAuditRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let toolName: String
    public let risk: AISVNToolRisk?
    public let arguments: [String: String]
    public let outcome: AISVNToolAuditOutcome
    public let summary: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        toolName: String,
        risk: AISVNToolRisk?,
        arguments: [String: String],
        outcome: AISVNToolAuditOutcome,
        summary: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.risk = risk
        self.arguments = arguments
        self.outcome = outcome
        self.summary = summary
        self.createdAt = createdAt
    }
}

public enum AISVNToolError: Error, Equatable, Sendable {
    case forbiddenTool(String)
    case missingArgument(String)
    case invalidArgument(name: String, value: String)
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

public enum AIReleaseNotesTemplate: String, Codable, Equatable, Sendable {
    case standardMarkdown
    case companyTemplate
}

public struct AIReleaseNotesSection: Codable, Equatable, Sendable {
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct AIReleaseNotesDraft: Codable, Equatable, Sendable {
    public let title: String
    public let markdown: String
    public let sections: [AIReleaseNotesSection]
    public let providerID: UUID
    public let entryCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int

    public init(
        title: String,
        markdown: String,
        sections: [AIReleaseNotesSection],
        providerID: UUID,
        entryCount: Int,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int
    ) {
        self.title = title
        self.markdown = markdown
        self.sections = sections
        self.providerID = providerID
        self.entryCount = entryCount
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
    }
}

public enum AIReleaseNotesError: Error, Equatable, Sendable {
    case emptyLogSelection
    case missingDefaultProvider
    case emptyModelResponse
    case invalidModelResponse(String)
}

public struct AIBlameLineRange: Codable, Equatable, Sendable {
    public let startLine: Int
    public let endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct AIBlameEvolutionChange: Codable, Equatable, Sendable {
    public let revision: Revision
    public let title: String
    public let explanation: String

    public init(revision: Revision, title: String, explanation: String) {
        self.revision = revision
        self.title = title
        self.explanation = explanation
    }
}

public struct AIBlameEvolutionExplanation: Codable, Equatable, Sendable {
    public let target: String
    public let lineRange: AIBlameLineRange
    public let summary: String
    public let keyChanges: [AIBlameEvolutionChange]
    public let providerID: UUID
    public let evidenceRevisionCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int

    public init(
        target: String,
        lineRange: AIBlameLineRange,
        summary: String,
        keyChanges: [AIBlameEvolutionChange],
        providerID: UUID,
        evidenceRevisionCount: Int,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int
    ) {
        self.target = target
        self.lineRange = lineRange
        self.summary = summary
        self.keyChanges = keyChanges
        self.providerID = providerID
        self.evidenceRevisionCount = evidenceRevisionCount
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
    }
}

public enum AIBlameEvolutionError: Error, Equatable, Sendable {
    case emptyLineSelection
    case missingDefaultProvider
    case noRevisionEvidence
    case emptyDiffChain
    case emptyModelResponse
    case invalidModelResponse(String)
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
