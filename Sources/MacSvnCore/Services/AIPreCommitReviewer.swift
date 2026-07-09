import Foundation

public protocol AIPreCommitReviewing: Sendable {
    func review(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> AIPreCommitReviewResult
}

public struct AIPreCommitReviewer: AIPreCommitReviewing, Sendable {
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

    public func review(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> AIPreCommitReviewResult {
        guard !paths.isEmpty else {
            throw AIPreCommitReviewError.emptySelection
        }

        let provider = try await defaultProvider()
        let collection = try await collectDiffs(wc: wc, paths: paths, privacySettings: privacySettings)
        guard !collection.fileDiffs.isEmpty else {
            throw AIPreCommitReviewError.emptyDiff
        }

        let combinedDiff = Self.combinedDiff(collection.fileDiffs)
        let reviewPayload: ReviewPayload
        let promptCount: Int
        let usedMapReduce: Bool

        if combinedDiff.count <= maxPromptCharacters {
            reviewPayload = try await requestReview(provider: provider, content: combinedDiff)
            promptCount = 1
            usedMapReduce = false
        } else {
            var summaries: [String] = []
            for fileDiff in collection.fileDiffs {
                summaries.append(try await requestFileSummary(provider: provider, fileDiff: fileDiff))
            }
            reviewPayload = try await requestReview(provider: provider, content: summaries.joined(separator: "\n"))
            promptCount = summaries.count + 1
            usedMapReduce = true
        }

        let findings = reviewPayload.findings + secretFindings(from: collection.redactionMatches)
        return AIPreCommitReviewResult(
            summary: reviewPayload.summary,
            findings: findings,
            providerID: provider.id,
            sourceFileCount: collection.fileDiffs.count,
            redactionMatches: collection.redactionMatches,
            promptCount: promptCount,
            usedMapReduce: usedMapReduce
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AIPreCommitReviewError.missingDefaultProvider
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
    ) async throws -> ReviewDiffCollection {
        var fileDiffs: [AIPreCommitFileDiff] = []
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

            fileDiffs.append(AIPreCommitFileDiff(path: path, diff: text))
        }

        return ReviewDiffCollection(
            fileDiffs: fileDiffs,
            redactionMatches: Self.mergeRedactionMatches(redactionMatches)
        )
    }

    private func requestFileSummary(provider: AIProvider, fileDiff: AIPreCommitFileDiff) async throws -> String {
        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(
                    role: .user,
                    content: """
                    请摘要这个文件 diff，输出一行中文摘要，包含文件路径和潜在风险。
                    文件：\(fileDiff.path)

                    Diff:
                    \(Self.limited(fileDiff.diff, to: maxPromptCharacters))
                    """
                )
            ]
        )

        return try trimmedText(response)
    }

    private func requestReview(provider: AIProvider, content: String) async throws -> ReviewPayload {
        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                systemMessage(),
                AILLMMessage(
                    role: .user,
                    content: """
                    请对以下提交前 diff 或文件摘要做 AI 预检，输出阻断建议、一般建议和提示。
                    要求：
                    - 结果仅用于展示，不要说禁止提交。
                    - 只输出 JSON，不要 Markdown，不要解释。
                    - JSON 格式：
                      {"summary":"一句中文总结","findings":[{"severity":"blockingSuggestion|generalSuggestion|tip","category":"correctness|security|maintainability|testing|style","path":"可选路径","line":可选数字或 null,"message":"中文建议","rationale":"可选理由"}]}

                    内容：
                    \(content)
                    """
                )
            ]
        )

        return try decodePayload(response)
    }

    private func decodePayload(_ response: AILLMResponse) throws -> ReviewPayload {
        let trimmed = try trimmedText(response)
        do {
            let data = Data(trimmed.utf8)
            return try JSONDecoder().decode(ReviewPayload.self, from: data)
        } catch {
            throw AIPreCommitReviewError.invalidModelResponse(trimmed)
        }
    }

    private func trimmedText(_ response: AILLMResponse) throws -> String {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIPreCommitReviewError.emptyModelResponse
        }
        return trimmed
    }

    private func systemMessage() -> AILLMMessage {
        AILLMMessage(
            role: .system,
            content: "你是资深代码评审助手。只输出请求的内容，不要执行或建议执行 SVN 命令。"
        )
    }

    private func secretFindings(from matches: [AIRedactionMatch]) -> [AIPreCommitReviewFinding] {
        guard !matches.isEmpty else {
            return []
        }

        let rules = matches.map(\.ruleID).joined(separator: ", ")
        return [
            AIPreCommitReviewFinding(
                severity: .blockingSuggestion,
                category: .suspectedSecret,
                path: nil,
                line: nil,
                message: "疑似密钥或敏感凭据已被脱敏，请提交前人工确认。",
                rationale: "命中脱敏规则：\(rules)"
            )
        ]
    }

    private static func combinedDiff(_ fileDiffs: [AIPreCommitFileDiff]) -> String {
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

private struct AIPreCommitFileDiff: Sendable {
    let path: String
    let diff: String
}

private struct ReviewDiffCollection: Sendable {
    let fileDiffs: [AIPreCommitFileDiff]
    let redactionMatches: [AIRedactionMatch]
}

private struct ReviewPayload: Codable, Sendable {
    let summary: String
    let findings: [AIPreCommitReviewFinding]
}
