import XCTest
@testable import MacSvnCore

@MainActor
final class AIAssistantChatViewModelTests: XCTestCase {
    func testInferToolCallMapsStatusAndCommit() {
        let status = AIAssistantChatViewModel.inferToolCall(
            from: "查看状态",
            workingCopyPath: "/tmp/wc"
        )
        XCTAssertEqual(status?.name, AISVNToolName.svnStatus.rawValue)
        XCTAssertEqual(status?.arguments["wc"], "/tmp/wc")

        let commit = AIAssistantChatViewModel.inferToolCall(
            from: "执行提交",
            workingCopyPath: "/tmp/wc"
        )
        XCTAssertEqual(commit?.name, AISVNToolName.svnCommit.rawValue)

        XCTAssertNil(AIAssistantChatViewModel.inferToolCall(from: "你好", workingCopyPath: "/tmp/wc"))
        XCTAssertNil(AIAssistantChatViewModel.inferToolCall(from: "查看状态", workingCopyPath: nil))
    }

    func testConfirmPendingToolActuallyExecutesWriteViaRegistry() async {
        let service = FakeChatToolService()
        let auditURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-audit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: auditURL) }
        let auditStore = AIToolAuditStore(fileURL: auditURL)
        let registry = AISVNToolRegistry(service: service, auditStore: auditStore)
        let viewModel = AIAssistantChatViewModel(
            llmClient: FakeChatLLM(),
            providerManager: FakeChatProviderManager(),
            toolRegistry: registry,
            auditStore: auditStore,
            sessionID: "chat-1"
        )

        await viewModel.sendDraft(workingCopyPath: "/tmp/wc")
        // 直接注入确认态
        viewModel.draft = "更新工作副本"
        await viewModel.sendDraft(workingCopyPath: "/tmp/wc")

        XCTAssertNotNil(viewModel.pendingConfirmation)
        await viewModel.confirmPendingTool()

        let calls = await service.recordedCalls()
        XCTAssertTrue(calls.contains(where: { $0.hasPrefix("update:") }))
        XCTAssertNil(viewModel.pendingConfirmation)
        XCTAssertTrue(viewModel.messages.last?.content.contains("已确认并执行") == true)
    }
}

private struct FakeChatLLM: LLMChatting {
    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        AILLMResponse(content: "ok", promptTokens: 1, completionTokens: 1)
    }
}

private struct FakeChatProviderManager: AIProviderManaging {
    func loadProviders() async throws -> [AIProvider] { [] }
    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider { provider }
    func deleteProvider(id: UUID) async throws {}
    func setDefaultProvider(id: UUID) async throws -> AIProvider {
        AIProvider(name: "x", kind: .ollama, baseURL: "http://localhost", model: "m", apiKeyRef: nil, maxTokens: 1, temperature: 0)
    }
    func defaultProviderID() async -> UUID? { nil }
}

private actor FakeChatToolService: AISVNToolServicing {
    private var calls: [String] = []
    func recordedCalls() -> [String] { calls }

    func status(wc: URL) async throws -> [FileStatus] { [] }
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String { "" }
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] { [] }
    func info(wc: URL, target: String) async throws -> SvnInfo {
        SvnInfo(path: ".", url: "file:///r", repositoryRoot: "file:///r", revision: Revision(1), kind: "dir")
    }
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] { [] }
    func blame(wc: URL, target: String) async throws -> [BlameLine] { [] }
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data { Data() }
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, ignoreExternals: Bool) async throws -> UpdateSummary {
        calls.append("update:\(wc.path)")
        return UpdateSummary(updated: 1)
    }
    func add(wc: URL, paths: [String]) async throws { calls.append("add") }
    func cleanup(wc: URL) async throws { calls.append("cleanup") }
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision {
        calls.append("commit"); return Revision(1)
    }
    func revert(wc: URL, paths: [String], recursive: Bool) async throws { calls.append("revert") }
    func merge(wc: URL, source: String, range: RevisionRange?, dryRun: Bool, auth: Credential?) async throws -> MergeSummary {
        calls.append("merge"); return MergeSummary()
    }
    func switchTo(wc: URL, url: String, auth: Credential?, allowLocalChanges: Bool) async throws -> UpdateSummary {
        calls.append("switch"); return UpdateSummary()
    }
    func delete(wc: URL, paths: [String]) async throws { calls.append("delete-wc") }
    func delete(url: String, message: String, auth: Credential?) async throws -> Revision {
        calls.append("delete-url"); return Revision(1)
    }
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        calls.append("copy"); return Revision(1)
    }
}
