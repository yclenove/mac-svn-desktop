import Foundation

public protocol AIBlameEvolutionExplaining: Sendable {
    func explain(
        wc: URL,
        target: String,
        lineRange: ClosedRange<Int>,
        blameLines: [BlameLine],
        privacySettings: AIPrivacySettings
    ) async throws -> AIBlameEvolutionExplanation
}

public struct AIBlameEvolutionExplainer: AIBlameEvolutionExplaining, Sendable {
    private let providerManager: any AIProviderManaging
    private let diffProvider: any DiffProviding
    private let logProvider: any LogProviding
    private let llmClient: any LLMChatting
    private let redactor: AIDataRedactor

    public init(
        providerManager: any AIProviderManaging,
        diffProvider: any DiffProviding,
        logProvider: any LogProviding,
        llmClient: any LLMChatting,
        redactor: AIDataRedactor = AIDataRedactor()
    ) {
        self.providerManager = providerManager
        self.diffProvider = diffProvider
        self.logProvider = logProvider
        self.llmClient = llmClient
        self.redactor = redactor
    }

    public func explain(
        wc: URL,
        target: String,
        lineRange: ClosedRange<Int>,
        blameLines: [BlameLine],
        privacySettings: AIPrivacySettings
    ) async throws -> AIBlameEvolutionExplanation {
        let selectedLines = blameLines.filter { lineRange.contains($0.lineNumber) }
        let revisions = Self.uniqueRevisions(from: selectedLines)

        let provider = try await defaultProvider()
        let evidence = try await collectEvidence(
            wc: wc,
            target: target,
            selectedLines: selectedLines,
            revisions: revisions
        )
        let prompt = Self.prompt(target: target, lineRange: lineRange, evidence: evidence)
        let redactionResult: AIRedactionResult?
        let content: String

        if privacySettings.isRedactionEnabled {
            let result = try redactor.redact(prompt, customPatterns: privacySettings.customRedactionPatterns)
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
        let changes = payload.keyChanges.map {
            AIBlameEvolutionChange(revision: Revision($0.revision), title: $0.title, explanation: $0.explanation)
        }

        return AIBlameEvolutionExplanation(
            target: target,
            lineRange: AIBlameLineRange(startLine: lineRange.lowerBound, endLine: lineRange.upperBound),
            summary: payload.summary,
            keyChanges: changes,
            providerID: provider.id,
            evidenceRevisionCount: evidence.count,
            redactionMatches: redactionResult?.matches ?? [],
            promptCount: 1
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AIBlameEvolutionError.missingDefaultProvider
        }

        if let defaultID = await providerManager.defaultProviderID(),
           let provider = providers.first(where: { $0.id == defaultID }) {
            return provider
        }

        return providers[0]
    }

    private func collectEvidence(
        wc: URL,
        target: String,
        selectedLines: [BlameLine],
        revisions: [Revision]
    ) async throws -> [BlameEvolutionEvidence] {
        var evidence: [BlameEvolutionEvidence] = []

        for revision in revisions {
            let previousRevision = Revision(max(0, revision.value - 1))
            let diff = try await diffProvider.diff(wc: wc, target: target, r1: previousRevision, r2: revision)
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let logEntries = try await logProvider.log(wc: wc, target: target, from: revision, batch: 1, verbose: true)
            let logEntry = logEntries.first
            let lineNumbers = selectedLines
                .filter { $0.revision == revision }
                .map(\.lineNumber)

            evidence.append(BlameEvolutionEvidence(
                revision: revision,
                lineNumbers: lineNumbers,
                logEntry: logEntry,
                diff: diff
            ))
        }

        return evidence
    }

    private func decodePayload(_ response: AILLMResponse) throws -> BlameEvolutionPayload {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return try JSONDecoder().decode(BlameEvolutionPayload.self, from: Data(trimmed.utf8))
    }

    private func systemMessage() -> AILLMMessage {
        AILLMMessage(
            role: .system,
            content: "你是资深 SVN 代码演化分析助手。只输出请求的 JSON，不要执行或建议执行 SVN 命令。"
        )
    }

    private static func uniqueRevisions(from lines: [BlameLine]) -> [Revision] {
        var seen: Set<Revision> = []
        return lines.compactMap(\.revision)
            .sorted { $0.value < $1.value }
            .filter { seen.insert($0).inserted }
    }

    private static func prompt(
        target: String,
        lineRange: ClosedRange<Int>,
        evidence: [BlameEvolutionEvidence]
    ) -> String {
        """
        请解释以下 SVN blame 选中代码段的演化过程。
        要求：
        - 讲清楚这段代码为什么长成这样，以及关键改动在哪个版本。
        - 只基于提供的 log/diff 证据，不要编造。
        - 只输出 JSON，不要 Markdown，不要解释。
        - JSON 格式：
          {"summary":"一句中文总结","keyChanges":[{"revision":1200,"title":"关键改动","explanation":"中文解释"}]}

        文件：\(target)
        选中行：\(lineRange.lowerBound)-\(lineRange.upperBound)

        证据链：
        \(evidence.map(formatEvidence).joined(separator: "\n\n---\n\n"))
        """
    }

    private static func formatEvidence(_ evidence: BlameEvolutionEvidence) -> String {
        let lineNumbers = evidence.lineNumbers.map(String.init).joined(separator: ",")
        let log = evidence.logEntry.map { entry in
            """
            author: \(entry.author)
            message: \(entry.message)
            changedPaths:
            \(entry.changedPaths.map { "\($0.action.rawValue) \($0.path)" }.joined(separator: "\n"))
            """
        } ?? "log: unavailable"

        return """
        r\(evidence.revision.value)
        lines: \(lineNumbers)
        \(log)
        diff:
        \(evidence.diff)
        """
    }
}

private struct BlameEvolutionEvidence: Sendable {
    let revision: Revision
    let lineNumbers: [Int]
    let logEntry: LogEntry?
    let diff: String
}

private struct BlameEvolutionPayload: Decodable {
    let summary: String
    let keyChanges: [BlameEvolutionChangePayload]
}

private struct BlameEvolutionChangePayload: Decodable {
    let revision: Int
    let title: String
    let explanation: String
}
