import Foundation

public protocol AIReleaseNotesGenerating: Sendable {
    func generate(
        entries: [LogEntry],
        title: String,
        template: AIReleaseNotesTemplate,
        privacySettings: AIPrivacySettings
    ) async throws -> AIReleaseNotesDraft
}

public struct AIReleaseNotesGenerator: AIReleaseNotesGenerating, Sendable {
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

    public func generate(
        entries: [LogEntry],
        title: String,
        template: AIReleaseNotesTemplate,
        privacySettings: AIPrivacySettings
    ) async throws -> AIReleaseNotesDraft {
        guard !entries.isEmpty else {
            throw AIReleaseNotesError.emptyLogSelection
        }

        let provider = try await defaultProvider()
        let prompt = Self.prompt(title: title, template: template, entries: entries)
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
        let sections = payload.sections.map {
            AIReleaseNotesSection(title: $0.title, items: $0.items)
        }

        return AIReleaseNotesDraft(
            title: payload.title,
            markdown: Self.markdown(title: payload.title, sections: sections),
            sections: sections,
            providerID: provider.id,
            entryCount: entries.count,
            redactionMatches: redactionResult?.matches ?? [],
            promptCount: 1
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AIReleaseNotesError.missingDefaultProvider
        }

        if let defaultID = await providerManager.defaultProviderID(),
           let provider = providers.first(where: { $0.id == defaultID }) {
            return provider
        }

        return providers[0]
    }

    private func systemMessage() -> AILLMMessage {
        AILLMMessage(
            role: .system,
            content: "你是资深发布说明助手。只输出请求的 JSON，不要执行或建议执行 SVN 命令。"
        )
    }

    private func decodePayload(_ response: AILLMResponse) throws -> ReleaseNotesPayload {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIReleaseNotesError.emptyModelResponse
        }

        do {
            return try JSONDecoder().decode(ReleaseNotesPayload.self, from: Data(trimmed.utf8))
        } catch {
            throw AIReleaseNotesError.invalidModelResponse(trimmed)
        }
    }

    private static func prompt(
        title: String,
        template: AIReleaseNotesTemplate,
        entries: [LogEntry]
    ) -> String {
        """
        请根据以下 SVN 日志生成结构化 Release Notes。
        要求：
        - 标题使用：\(title)
        - 模板：\(template.instruction)
        - 按新功能、修复、重构等分组。
        - 只输出 JSON，不要 Markdown，不要解释。
        - JSON 格式：
          {"title":"v1.2.0","sections":[{"title":"新功能","items":["支持支付回调"]}]}

        日志：
        \(entries.map(formatEntry).joined(separator: "\n\n"))
        """
    }

    private static func formatEntry(_ entry: LogEntry) -> String {
        let changedPaths = entry.changedPaths
            .map { "\($0.action.rawValue) \($0.path)" }
            .joined(separator: "\n")

        return """
        r\(entry.revision.value)
        author: \(entry.author)
        message: \(entry.message)
        changedPaths:
        \(changedPaths)
        """
    }

    private static func markdown(title: String, sections: [AIReleaseNotesSection]) -> String {
        var lines = ["# \(title)"]

        for section in sections {
            lines.append("")
            lines.append("## \(section.title)")
            lines.append(contentsOf: section.items.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}

private extension AIReleaseNotesTemplate {
    var instruction: String {
        switch self {
        case .standardMarkdown:
            return "标准 Markdown 发布说明"
        case .companyTemplate:
            return "公司发布模板，保留清晰分组和中文条目"
        }
    }
}

private struct ReleaseNotesPayload: Decodable {
    let title: String
    let sections: [ReleaseNotesSectionPayload]
}

private struct ReleaseNotesSectionPayload: Decodable {
    let title: String
    let items: [String]
}
