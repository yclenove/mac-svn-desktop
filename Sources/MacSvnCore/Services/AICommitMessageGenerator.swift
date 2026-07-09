import Foundation

public protocol LLMChatting: Sendable {
    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse
}

public protocol AICommitMessageGenerating: Sendable {
    func generateCommitMessage(
        wc: URL,
        paths: [String],
        format: AICommitMessageFormat,
        privacySettings: AIPrivacySettings
    ) async throws -> AICommitMessageDraft
}

public struct AICommitMessageGenerator: AICommitMessageGenerating, Sendable {
    private let providerManager: any AIProviderManaging
    private let diffProvider: any DiffProviding
    private let llmClient: any LLMChatting
    private let redactor: AIDataRedactor
    private let maxPromptCharacters: Int

    public init(
        providerManager: any AIProviderManaging,
        diffProvider: any DiffProviding,
        llmClient: any LLMChatting,
        redactor: AIDataRedactor = AIDataRedactor(),
        maxPromptCharacters: Int = 24_000
    ) {
        self.providerManager = providerManager
        self.diffProvider = diffProvider
        self.llmClient = llmClient
        self.redactor = redactor
        self.maxPromptCharacters = maxPromptCharacters
    }

    public func generateCommitMessage(
        wc: URL,
        paths: [String],
        format: AICommitMessageFormat,
        privacySettings: AIPrivacySettings
    ) async throws -> AICommitMessageDraft {
        guard !paths.isEmpty else {
            throw AICommitMessageError.emptySelection
        }

        let provider = try await defaultProvider()
        let collection = try await collectDiffs(wc: wc, paths: paths, privacySettings: privacySettings)
        guard !collection.fileDiffs.isEmpty else {
            throw AICommitMessageError.emptyDiff
        }

        let combinedDiff = Self.combinedDiff(collection.fileDiffs)
        if combinedDiff.count <= maxPromptCharacters {
            let response = try await requestCommitMessage(provider: provider, diffOrSummary: combinedDiff, format: format)
            return AICommitMessageDraft(
                message: response,
                providerID: provider.id,
                sourceFileCount: collection.fileDiffs.count,
                redactionMatches: collection.redactionMatches,
                promptCount: 1,
                usedMapReduce: false
            )
        }

        var summaries: [String] = []
        for fileDiff in collection.fileDiffs {
            summaries.append(try await requestFileSummary(provider: provider, fileDiff: fileDiff))
        }

        let response = try await requestCommitMessage(
            provider: provider,
            diffOrSummary: summaries.joined(separator: "\n"),
            format: format
        )

        return AICommitMessageDraft(
            message: response,
            providerID: provider.id,
            sourceFileCount: collection.fileDiffs.count,
            redactionMatches: collection.redactionMatches,
            promptCount: summaries.count + 1,
            usedMapReduce: true
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AICommitMessageError.missingDefaultProvider
        }

        if let defaultID = await providerManager.defaultProviderID(),
           let provider = providers.first(where: { $0.id == defaultID }) {
            return provider
        }

        return providers[0]
    }

    private func collectDiffs(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> DiffCollection {
        var fileDiffs: [AICommitFileDiff] = []
        var redactionMatches: [AIRedactionMatch] = []

        for path in paths {
            let rawDiff = try await diffProvider.diff(wc: wc, target: path, r1: nil, r2: nil)
            guard !rawDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let text: String
            if privacySettings.isRedactionEnabled {
                let result = try redactor.redact(
                    rawDiff,
                    customPatterns: privacySettings.customRedactionPatterns
                )
                text = result.redactedText
                redactionMatches.append(contentsOf: result.matches)
            } else {
                text = rawDiff
            }

            fileDiffs.append(AICommitFileDiff(path: path, diff: text))
        }

        return DiffCollection(
            fileDiffs: fileDiffs,
            redactionMatches: Self.mergeRedactionMatches(redactionMatches)
        )
    }

    private func requestFileSummary(provider: AIProvider, fileDiff: AICommitFileDiff) async throws -> String {
        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(
                    role: .user,
                    content: """
                    请摘要这个文件 diff，输出一行中文摘要，包含文件路径和主要变更。
                    文件：\(fileDiff.path)

                    Diff:
                    \(Self.limited(fileDiff.diff, to: maxPromptCharacters))
                    """
                )
            ]
        )

        return try trimmedResponse(response)
    }

    private func requestCommitMessage(
        provider: AIProvider,
        diffOrSummary: String,
        format: AICommitMessageFormat
    ) async throws -> String {
        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(
                    role: .user,
                    content: """
                    请根据以下 unified diff 或文件摘要生成中文提交说明。
                    要求：
                    - 不要自动提交，也不要输出命令。
                    - \(format.instruction)
                    - 只返回提交说明文本，不要解释。

                    内容：
                    \(diffOrSummary)
                    """
                )
            ]
        )

        return try trimmedResponse(response)
    }

    private func systemMessage() -> AILLMMessage {
        AILLMMessage(
            role: .system,
            content: "你是资深 SVN 提交说明助手。只返回提交说明文本，不要解释。"
        )
    }

    private func trimmedResponse(_ response: AILLMResponse) throws -> String {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AICommitMessageError.emptyModelResponse
        }
        return trimmed
    }

    private static func combinedDiff(_ fileDiffs: [AICommitFileDiff]) -> String {
        fileDiffs
            .map { "### \($0.path)\n\($0.diff)" }
            .joined(separator: "\n\n")
    }

    private static func limited(_ text: String, to maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        return String(text.prefix(maxCharacters))
    }

    private static func mergeRedactionMatches(_ matches: [AIRedactionMatch]) -> [AIRedactionMatch] {
        var order: [String] = []
        var counts: [String: Int] = [:]

        for match in matches {
            if counts[match.ruleID] == nil {
                order.append(match.ruleID)
            }
            counts[match.ruleID, default: 0] += match.matchCount
        }

        return order.map { ruleID in
            AIRedactionMatch(ruleID: ruleID, matchCount: counts[ruleID] ?? 0)
        }
    }
}

private struct AICommitFileDiff: Sendable {
    let path: String
    let diff: String
}

private struct DiffCollection: Sendable {
    let fileDiffs: [AICommitFileDiff]
    let redactionMatches: [AIRedactionMatch]
}

private extension AICommitMessageFormat {
    var instruction: String {
        switch self {
        case .oneLineChinese:
            return "输出一行式中文提交说明，不超过 50 个字。"
        case .conventionalChinese:
            return "输出 Conventional Commits 中文式，例如 `feat: 增加登录校验` 或 `fix: 修复登录超时`。"
        case .companyTemplate:
            return "输出公司模板：第一行摘要，随后列出【变更内容】和【测试建议】。"
        }
    }
}
