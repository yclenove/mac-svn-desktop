import Foundation

/// AI 批量推断 SVN→Git authors 映射（结果必须人工复核，对应 FR-GM-03）。
public protocol AIAuthorMappingInferring: Sendable {
    func inferMappings(
        authors: [GitMigrationAuthor],
        emailDomain: String,
        privacySettings: AIPrivacySettings
    ) async throws -> AIAuthorMappingInferenceDraft
}

public struct AIAuthorMappingSuggestion: Equatable, Sendable {
    public let svnUsername: String
    public let gitName: String
    public let gitEmail: String

    public init(svnUsername: String, gitName: String, gitEmail: String) {
        self.svnUsername = svnUsername
        self.gitName = gitName
        self.gitEmail = gitEmail
    }
}

public struct AIAuthorMappingInferenceDraft: Equatable, Sendable {
    public let suggestions: [AIAuthorMappingSuggestion]
    public let providerID: UUID
    public let promptCount: Int

    public init(suggestions: [AIAuthorMappingSuggestion], providerID: UUID, promptCount: Int) {
        self.suggestions = suggestions
        self.providerID = providerID
        self.promptCount = promptCount
    }
}

public enum AIAuthorMappingInferenceError: Error, Equatable, Sendable {
    case emptyAuthorList
    case missingDefaultProvider
    case emptyModelResponse
    case invalidModelResponse(String)
}

public struct AIAuthorMappingInferrer: AIAuthorMappingInferring, Sendable {
    private let providerManager: any AIProviderManaging
    private let llmClient: any LLMChatting

    public init(providerManager: any AIProviderManaging, llmClient: any LLMChatting) {
        self.providerManager = providerManager
        self.llmClient = llmClient
    }

    public func inferMappings(
        authors: [GitMigrationAuthor],
        emailDomain: String,
        privacySettings: AIPrivacySettings
    ) async throws -> AIAuthorMappingInferenceDraft {
        let usernames = authors.map(\.svnUsername).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usernames.isEmpty else {
            throw AIAuthorMappingInferenceError.emptyAuthorList
        }
        // 预留：后续可按 privacySettings 对用户名做脱敏；当前用户名本身非密钥
        _ = privacySettings

        let provider = try await defaultProvider()
        let domain = emailDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveDomain = domain.isEmpty ? "example.com" : domain

        let response = try await llmClient.chat(
            provider: provider,
            messages: [
                AILLMMessage(
                    role: .system,
                    content: "你是 SVN→Git authors 映射助手。只输出请求的 JSON，不要执行命令。"
                ),
                AILLMMessage(
                    role: .user,
                    content: Self.prompt(usernames: usernames, emailDomain: effectiveDomain)
                )
            ]
        )

        let payload = try decodePayload(response)
        let allowed = Set(usernames)
        let suggestions = payload.mappings.compactMap { item -> AIAuthorMappingSuggestion? in
            guard allowed.contains(item.svnUsername) else { return nil }
            let name = item.gitName.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = item.gitEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !email.isEmpty else { return nil }
            return AIAuthorMappingSuggestion(
                svnUsername: item.svnUsername,
                gitName: name,
                gitEmail: email
            )
        }

        return AIAuthorMappingInferenceDraft(
            suggestions: suggestions,
            providerID: provider.id,
            promptCount: 1
        )
    }

    private func defaultProvider() async throws -> AIProvider {
        let providers = try await providerManager.loadProviders()
        guard !providers.isEmpty else {
            throw AIAuthorMappingInferenceError.missingDefaultProvider
        }

        if let defaultID = await providerManager.defaultProviderID(),
           let provider = providers.first(where: { $0.id == defaultID }) {
            return provider
        }

        return providers[0]
    }

    private func decodePayload(_ response: AILLMResponse) throws -> AuthorMappingPayload {
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIAuthorMappingInferenceError.emptyModelResponse
        }

        do {
            return try JSONDecoder().decode(AuthorMappingPayload.self, from: Data(trimmed.utf8))
        } catch {
            throw AIAuthorMappingInferenceError.invalidModelResponse(trimmed)
        }
    }

    private static func prompt(usernames: [String], emailDomain: String) -> String {
        """
        请根据 SVN 用户名批量推断 Git 姓名与邮箱。
        规则：
        - 邮箱域名使用：\(emailDomain)
        - 邮箱优先形如 username@\(emailDomain)
        - 中文姓名可按拼音用户名合理推断；不确定时仍给出最佳猜测
        - 只输出 JSON，不要 Markdown，不要解释
        - JSON 格式：
          {"mappings":[{"svnUsername":"zhangsan","gitName":"张三","gitEmail":"zhangsan@\(emailDomain)"}]}

        SVN 用户名列表：
        \(usernames.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}

private struct AuthorMappingPayload: Decodable {
    let mappings: [AuthorMappingItemPayload]
}

private struct AuthorMappingItemPayload: Decodable {
    let svnUsername: String
    let gitName: String
    let gitEmail: String
}
