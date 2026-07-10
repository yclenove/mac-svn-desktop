import Foundation
import Observation

/// AI 助手会话状态：自然语言问答 + SVN tool 确认门。
public enum AIAssistantChatState: Equatable, Sendable {
    case idle
    case thinking
    case awaitingConfirmation(AISVNToolConfirmation)
    case error(String)
}

public struct AIAssistantChatMessage: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: AILLMRole
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: AILLMRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
public final class AIAssistantChatViewModel {
    private let llmClient: any LLMChatting
    private let providerManager: any AIProviderManaging
    private let toolRegistry: AISVNToolRegistry
    private let auditStore: AIToolAuditStore
    private let sessionID: String

    public private(set) var state: AIAssistantChatState = .idle
    public private(set) var messages: [AIAssistantChatMessage] = []
    public private(set) var auditRecords: [AISVNToolAuditRecord] = []
    public private(set) var pendingConfirmation: AISVNToolConfirmation?
    public private(set) var pendingCallArguments: [String: String] = [:]
    public var draft = ""

    public init(
        llmClient: any LLMChatting,
        providerManager: any AIProviderManaging,
        toolRegistry: AISVNToolRegistry,
        auditStore: AIToolAuditStore,
        sessionID: String = UUID().uuidString
    ) {
        self.llmClient = llmClient
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.auditStore = auditStore
        self.sessionID = sessionID
    }

    public func refreshAudit() async {
        do {
            auditRecords = try await auditStore.records(sessionID: sessionID)
        } catch {
            // 审计读取失败不阻断对话
        }
    }

    public func sendDraft(workingCopyPath: String?) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(AIAssistantChatMessage(role: .user, content: text))
        await respond(to: text, workingCopyPath: workingCopyPath)
    }

    public func confirmPendingTool() async {
        guard let pending = pendingConfirmation else { return }
        let arguments = pendingCallArguments
        let toolName = pending.toolName
        pendingConfirmation = nil
        pendingCallArguments = [:]
        state = .thinking

        do {
            let result = try await toolRegistry.executeConfirmed(
                toolName: toolName,
                arguments: arguments,
                sessionID: sessionID
            )
            messages.append(AIAssistantChatMessage(
                role: .assistant,
                content: "已确认并执行「\(toolName)」：\n\(pending.commandPreview)\n\n结果：\n\(result.content)"
            ))
            state = .idle
        } catch {
            messages.append(AIAssistantChatMessage(
                role: .assistant,
                content: "已确认但执行失败「\(toolName)」：\(error.localizedDescription)"
            ))
            state = .error(String(describing: error))
        }
        await refreshAudit()
    }

    public func cancelPendingTool() async {
        guard let pending = pendingConfirmation else { return }
        let arguments = pendingCallArguments
        pendingConfirmation = nil
        pendingCallArguments = [:]
        await auditStore.append(AISVNToolAuditRecord(
            sessionID: sessionID,
            toolName: pending.toolName,
            risk: pending.risk,
            arguments: arguments,
            outcome: .failed,
            summary: "用户取消确认"
        ))
        messages.append(AIAssistantChatMessage(role: .assistant, content: "已取消工具确认。"))
        state = .idle
        await refreshAudit()
    }

    private func respond(to text: String, workingCopyPath: String?) async {
        state = .thinking

        if let toolCall = Self.inferToolCall(from: text, workingCopyPath: workingCopyPath) {
            do {
                let decision = try await toolRegistry.handle(toolCall, sessionID: sessionID)
                switch decision {
                case .completed(let result):
                    messages.append(AIAssistantChatMessage(role: .assistant, content: result.content))
                    state = .idle
                case .confirmationRequired(let confirmation):
                    pendingConfirmation = confirmation
                    pendingCallArguments = toolCall.arguments
                    state = .awaitingConfirmation(confirmation)
                    messages.append(AIAssistantChatMessage(
                        role: .assistant,
                        content: "需要确认写操作（\(confirmation.risk.rawValue)）：\n\(confirmation.commandPreview)\n警告：\(confirmation.warning)"
                    ))
                }
                await refreshAudit()
                return
            } catch {
                state = .error(String(describing: error))
                messages.append(AIAssistantChatMessage(
                    role: .assistant,
                    content: "工具调用失败：\(error.localizedDescription)"
                ))
                return
            }
        }

        do {
            let providers = try await providerManager.loadProviders()
            guard let providerID = await providerManager.defaultProviderID(),
                  let provider = providers.first(where: { $0.id == providerID })
            else {
                messages.append(AIAssistantChatMessage(
                    role: .assistant,
                    content: "尚未配置默认 AI Provider。请先在设置中添加并设为默认，或使用「status / diff / log」等本地 SVN 指令。"
                ))
                state = .idle
                return
            }

            let history = messages.suffix(12).map { AILLMMessage(role: $0.role, content: $0.content) }
            let system = AILLMMessage(
                role: .system,
                content: """
                你是 MacSVN 助手。回答简洁，优先中文。可建议用户使用 status/diff/log/blame 等本地指令。
                当前工作副本：\(workingCopyPath ?? "未选择")
                """
            )
            let response = try await llmClient.chat(provider: provider, messages: [system] + history)
            messages.append(AIAssistantChatMessage(role: .assistant, content: response.content))
            state = .idle
        } catch {
            state = .error(String(describing: error))
            messages.append(AIAssistantChatMessage(
                role: .assistant,
                content: "LLM 调用失败：\(error.localizedDescription)"
            ))
        }
    }

    /// 从自然语言中识别简单 SVN 只读/写意图，映射到 AISVNToolCall。
    public static func inferToolCall(from text: String, workingCopyPath: String?) -> AISVNToolCall? {
        let lower = text.lowercased()
        let wc = workingCopyPath ?? ""
        guard !wc.isEmpty else { return nil }

        if lower.contains("status") || text.contains("查看状态") {
            return AISVNToolCall(name: AISVNToolName.svnStatus.rawValue, arguments: ["wc": wc])
        }
        if lower.hasPrefix("diff ") || lower == "diff" || text.contains("查看差异") {
            let path = extractPathArgument(from: text) ?? "."
            return AISVNToolCall(name: AISVNToolName.svnDiff.rawValue, arguments: ["wc": wc, "target": path])
        }
        if lower.hasPrefix("log") || text.contains("查看日志") {
            return AISVNToolCall(
                name: AISVNToolName.svnLog.rawValue,
                arguments: ["wc": wc, "target": ".", "batch": "20"]
            )
        }
        if lower.contains("svn update") || text.contains("更新工作副本") {
            return AISVNToolCall(name: AISVNToolName.svnUpdate.rawValue, arguments: ["wc": wc])
        }
        if lower.contains("svn commit") || text.contains("执行提交") {
            return AISVNToolCall(
                name: AISVNToolName.svnCommit.rawValue,
                arguments: ["wc": wc, "message": "AI suggested commit"]
            )
        }
        return nil
    }

    private static func extractPathArgument(from text: String) -> String? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[1]
    }
}
