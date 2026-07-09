import Foundation

public protocol AIConflictAssisting: Sendable {
    func suggestResolution(
        context: AIConflictAssistContext,
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistSuggestion

    func suggestResolutions(
        contexts: [AIConflictAssistContext],
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistPreview
}

public struct AIConflictAssistant: AIConflictAssisting, Sendable {
    private let providerManager: any AIProviderManaging
    private let llmClient: any LLMChatting
    private let redactor: AIDataRedactor

    public init(
        providerManager: any AIProviderManaging,
        llmClient: any LLMChatting,
        redactor: AIDataRedactor = AIDataRedactor()
    ) {
        self.providerManager = providerManager
        self.llmClient = llmClient
        self.redactor = redactor
    }

    public func suggestResolution(
        context: AIConflictAssistContext,
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistSuggestion {
        guard !context.baseLines.isEmpty || !context.mineLines.isEmpty || !context.theirsLines.isEmpty else {
            throw AIConflictAssistError.emptyConflict
        }

        let provider = try await defaultProvider()
        let prompt = Self.prompt(for: context)
        let redactionResult: AIRedactionResult?
        let content: String

        if privacySettings.isRedactionEnabled {
            let result = try redactor.redact(
                prompt,
                customPatterns: privacySettings.customRedactionPatterns
            )
            redactionResult = result
            content = result.redactedText
        } else {
            redactionResult = nil
            content = prompt
        }

        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(role: .user, content: content)
            ]
        )
        let payload = try decodePayload(response)

        return AIConflictAssistSuggestion(
            mergedLines: Self.lines(payload.mergedText),
            rationale: payload.rationale,
            confidence: payload.confidence,
            providerID: provider.id,
            redactionMatches: redactionResult?.matches ?? [],
            promptCount: 1
        )
    }

    public func suggestResolutions(
        contexts: [AIConflictAssistContext],
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistPreview {
        guard !contexts.isEmpty else {
            throw AIConflictAssistError.emptyConflict
        }

        let provider = try await defaultProvider()
        let prompt = Self.prompt(for: contexts)
        let redactionResult: AIRedactionResult?
        let content: String

        if privacySettings.isRedactionEnabled {
            let result = try redactor.redact(
                prompt,
                customPatterns: privacySettings.customRedactionPatterns
            )
            redactionResult = result
            content = result.redactedText
        } else {
            redactionResult = nil
            content = prompt
        }

        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(role: .user, content: content)
            ]
        )
        let payload = try decodePreviewPayload(response)
        let suggestions = payload.suggestions.map { suggestion in
            AIConflictBlockSuggestion(
                conflictIndex: suggestion.conflictIndex,
                mergedLines: Self.lines(suggestion.mergedText),
                rationale: suggestion.rationale,
                confidence: suggestion.confidence
            )
        }

        return AIConflictAssistPreview(
            suggestions: suggestions,
            providerID: provider.id,
            redactionMatches: redactionResult?.matches ?? [],
            promptCount: 1
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AIConflictAssistError.missingDefaultProvider
        }

        if let defaultID = await providerManager.defaultProviderID(),
           let provider = providers.first(where: { $0.id == defaultID }) {
            return provider
        }

        return providers[0]
    }

    private func decodePayload(_ response: AILLMResponse) throws -> SuggestionPayload {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIConflictAssistError.emptyModelResponse
        }

        do {
            return try JSONDecoder().decode(SuggestionPayload.self, from: Data(trimmed.utf8))
        } catch {
            throw AIConflictAssistError.invalidModelResponse(trimmed)
        }
    }

    private func decodePreviewPayload(_ response: AILLMResponse) throws -> PreviewPayload {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIConflictAssistError.emptyModelResponse
        }

        do {
            return try JSONDecoder().decode(PreviewPayload.self, from: Data(trimmed.utf8))
        } catch {
            throw AIConflictAssistError.invalidModelResponse(trimmed)
        }
    }

    private func systemMessage() -> AILLMMessage {
        AILLMMessage(
            role: .system,
            content: "你是资深三路合并助手。只输出请求的 JSON，不要执行或建议执行 SVN 命令。"
        )
    }

    private static func prompt(for context: AIConflictAssistContext) -> String {
        """
        请为以下 SVN 三路合并冲突块生成建议合并结果。
        要求：
        - 结果只用于预填手动编辑区，不会直接写盘。
        - 保留双方有价值语义，无法判断时给低置信度。
        - 只输出 JSON，不要 Markdown，不要解释。
        - JSON 格式：
          {"mergedText":"合并后的文本","rationale":"一句中文理由","confidence":"low|medium|high"}

        文件：\(context.path)
        冲突块序号：\(context.conflictIndex)

        上文：
        \(context.leadingContext.joined(separator: "\n"))

        Base:
        \(context.baseLines.joined(separator: "\n"))

        Mine:
        \(context.mineLines.joined(separator: "\n"))

        Theirs:
        \(context.theirsLines.joined(separator: "\n"))

        下文：
        \(context.trailingContext.joined(separator: "\n"))
        """
    }

    private static func prompt(for contexts: [AIConflictAssistContext]) -> String {
        let blocks = contexts.map { context in
            """
            文件：\(context.path)
            冲突块序号：\(context.conflictIndex)

            上文：
            \(context.leadingContext.joined(separator: "\n"))

            Base:
            \(context.baseLines.joined(separator: "\n"))

            Mine:
            \(context.mineLines.joined(separator: "\n"))

            Theirs:
            \(context.theirsLines.joined(separator: "\n"))

            下文：
            \(context.trailingContext.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n---\n\n")

        return """
        请为以下 SVN 三路合并冲突块生成整文件级预览建议。
        要求：
        - 结果只用于预填手动编辑区，不会直接写盘。
        - 保留双方有价值语义，无法判断时给低置信度。
        - 每个输入冲突块最多输出一个对应建议，并保留原始 conflictIndex。
        - 只输出 JSON，不要 Markdown，不要解释。
        - JSON 格式：
          {"suggestions":[{"conflictIndex":0,"mergedText":"合并后的文本","rationale":"一句中文理由","confidence":"low|medium|high"}]}

        冲突块列表：

        \(blocks)
        """
    }

    private static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalized = text.hasSuffix("\n") ? Array(splitLines.dropLast()) : splitLines
        return normalized.map(String.init)
    }
}

private struct SuggestionPayload: Decodable {
    let mergedText: String
    let rationale: String
    let confidence: AIConflictConfidence
}

private struct PreviewPayload: Decodable {
    let suggestions: [BlockSuggestionPayload]
}

private struct BlockSuggestionPayload: Decodable {
    let conflictIndex: Int
    let mergedText: String
    let rationale: String
    let confidence: AIConflictConfidence
}
