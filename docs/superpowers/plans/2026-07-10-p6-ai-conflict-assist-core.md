# P6 AI Conflict Assist Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-03` 建立逐冲突块 AI 辅助 Core：把 base/mine/theirs 与上下文发送给可注入 LLM，返回建议合并结果、理由和置信度，并在 `MergeEditorViewModel` 中预填为手动合并结果，不直接写盘或 resolve。

**架构：** 在 `AIModels.swift` 中补充冲突辅助模型和错误类型。新增 `AIConflictAssistant` 服务，复用 `AIProviderManaging`、`LLMChatting` 与 `AIDataRedactor`，要求模型只返回 JSON，解析为结构化建议。扩展 `MergeEditorViewModel`，通过可选 `AIConflictAssisting` 依赖暴露 AI 建议状态；成功后调用现有 `.manual(lines:)` 路径预填当前冲突块，保持保存/落盘仍由用户触发。

**技术栈：** Swift 6、Foundation、Observation、XCTest、现有 `AIProviderManaging` / `LLMChatting` / `AIDataRedactor` / `MergeEngine`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  - 增加 `AIConflictConfidence`、`AIConflictAssistContext`、`AIConflictAssistSuggestion`、`AIConflictAssistError`。
- 创建：`Sources/MacSvnCore/Services/AIConflictAssistant.swift`
  - 提供 `AIConflictAssisting` 协议与默认服务实现。
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
  - 增加 AI 冲突建议状态、结果属性和 `requestAIResolutionForCurrentConflict` 方法。
- 创建测试：`Tests/MacSvnCoreTests/AIConflictAssistantTests.swift`
  - 覆盖 JSON 解析、脱敏、provider 选择、错误路径。
- 修改测试：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`
  - 覆盖 AI 建议预填当前冲突块、不保存、不整文件 resolve、错误状态。
- 修改计划：`docs/superpowers/plans/2026-07-10-p6-ai-conflict-assist-core.md`
  - 每完成步骤同步 checkbox。

---

## 任务 1：AI Conflict Assistant 服务

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIConflictAssistant.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIConflictAssistantTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `Tests/MacSvnCoreTests/AIConflictAssistantTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIConflictAssistantTests: XCTestCase {
    func testSuggestResolutionParsesJSONRedactsSecretsAndRecordsMetadata() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let llm = FakeConflictLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "mergedText": "let token = credentialStore.token\\ntry auth.login()",
                  "rationale": "保留安全 token 读取并保留登录调用。",
                  "confidence": "high"
                }
                """,
                promptTokens: 140,
                completionTokens: 42
            )
        ])
        let assistant = AIConflictAssistant(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: llm
        )
        let context = AIConflictAssistContext(
            path: "Sources/Login.swift",
            conflictIndex: 2,
            baseLines: ["let token = \"sk-1234567890abcdef\""],
            mineLines: ["let token = credentialStore.token"],
            theirsLines: ["let token = \"sk-1234567890abcdef\"", "try auth.login()"],
            leadingContext: ["func login() {"],
            trailingContext: ["}"]
        )

        let suggestion = try await assistant.suggestResolution(
            context: context,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(suggestion.providerID, provider.id)
        XCTAssertEqual(suggestion.mergedLines, [
            "let token = credentialStore.token",
            "try auth.login()"
        ])
        XCTAssertEqual(suggestion.rationale, "保留安全 token 读取并保留登录调用。")
        XCTAssertEqual(suggestion.confidence, .high)
        XCTAssertEqual(suggestion.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(suggestion.promptCount, 1)
        XCTAssertTrue(prompt.contains("***REDACTED***"))
        XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
        XCTAssertTrue(prompt.contains("只输出 JSON"))
        XCTAssertTrue(prompt.contains("Sources/Login.swift"))
    }

    func testThrowsForMissingProviderEmptyContextEmptyResponseAndInvalidJSON() async throws {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )

        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: []),
            llmClient: FakeConflictLLMClient(responses: []),
            context: validContext(),
            expected: .missingDefaultProvider
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: []),
            context: AIConflictAssistContext(
                path: "a.swift",
                conflictIndex: 0,
                baseLines: [],
                mineLines: [],
                theirsLines: [],
                leadingContext: [],
                trailingContext: []
            ),
            expected: .emptyConflict
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: [
                AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)
            ]),
            context: validContext(),
            expected: .emptyModelResponse
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: [
                AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
            ]),
            context: validContext(),
            expected: .invalidModelResponse("not json")
        )
    }

    private func assertSuggestThrows(
        providerManager: FakeConflictProviderManager,
        llmClient: FakeConflictLLMClient,
        context: AIConflictAssistContext,
        expected: AIConflictAssistError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let assistant = AIConflictAssistant(providerManager: providerManager, llmClient: llmClient)

        do {
            _ = try await assistant.suggestResolution(
                context: context,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AIConflictAssistError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIConflictAssistError, got \(error)", file: file, line: line)
        }
    }
}

private func validContext() -> AIConflictAssistContext {
    AIConflictAssistContext(
        path: "a.swift",
        conflictIndex: 0,
        baseLines: ["base"],
        mineLines: ["mine"],
        theirsLines: ["theirs"],
        leadingContext: ["before"],
        trailingContext: ["after"]
    )
}

private struct ConflictLLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private actor FakeConflictLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [ConflictLLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [ConflictLLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(ConflictLLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeConflictProviderManager: AIProviderManaging {
    private let providers: [AIProvider]
    private let defaultID: UUID?

    init(providers: [AIProvider]) {
        self.providers = providers
        self.defaultID = providers.first?.id
    }

    func loadProviders() async throws -> [AIProvider] {
        providers
    }

    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider {
        provider
    }

    func deleteProvider(id: UUID) async throws {}

    func setDefaultProvider(id: UUID) async throws -> AIProvider {
        guard let provider = providers.first(where: { $0.id == id }) else {
            throw AIProviderError.providerNotFound(id)
        }
        return provider
    }

    func defaultProviderID() async -> UUID? {
        defaultID
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter AIConflictAssistantTests
```

预期：编译失败，提示 `AIConflictAssistant`、`AIConflictAssistContext`、`AIConflictAssistSuggestion` 或 `AIConflictAssistError` 未定义。

- [x] **步骤 3：实现最少模型与服务代码**

在 `Sources/MacSvnCore/Models/AIModels.swift` 追加：

```swift
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
}

public struct AIConflictAssistSuggestion: Codable, Equatable, Sendable {
    public let mergedLines: [String]
    public let rationale: String
    public let confidence: AIConflictConfidence
    public let providerID: UUID
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int
}

public enum AIConflictAssistError: Error, Equatable, Sendable {
    case missingDefaultProvider
    case emptyConflict
    case emptyModelResponse
    case invalidModelResponse(String)
}
```

创建 `Sources/MacSvnCore/Services/AIConflictAssistant.swift`，实现：

- `public protocol AIConflictAssisting: Sendable`
- `public struct AIConflictAssistant: AIConflictAssisting, Sendable`
- 默认 provider 选择逻辑与 `AICommitMessageGenerator` / `AIPreCommitReviewer` 保持一致；
- prompt 包含 path、conflictIndex、上下文、base/mine/theirs；
- 脱敏对完整 prompt 输入执行，命中记录合并进 `redactionMatches`；
- 模型返回 JSON：

```json
{"mergedText":"合并后的文本","rationale":"一句理由","confidence":"low|medium|high"}
```

`mergedText` 使用换行拆成 `mergedLines`，空响应抛 `.emptyModelResponse`，JSON 解析失败抛 `.invalidModelResponse(rawText)`。

- [x] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter AIConflictAssistantTests
```

预期：`AIConflictAssistantTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AIConflictAssistant.swift \
  Tests/MacSvnCoreTests/AIConflictAssistantTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-conflict-assist-core.md
git diff --cached --check
git commit -m "feat: add P6 AI conflict assistant core"
```

---

## 任务 2：MergeEditorViewModel 接入 AI 建议

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改测试：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEditorViewModelTests` 增加：

```swift
@MainActor
func testAIConflictSuggestionPrefillsCurrentConflictAsManualResolutionWithoutSaving() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "a\nbase\nz\n",
        mine: "a\nmine\nz\n",
        theirs: "a\ntheirs\nz\n"
    )))
    let suggestion = AIConflictAssistSuggestion(
        mergedLines: ["ai merged"],
        rationale: "保留双方语义。",
        confidence: .medium,
        providerID: UUID(),
        redactionMatches: [],
        promptCount: 1
    )
    let assistant = FakeAIConflictAssistant(result: .success(suggestion))
    let viewModel = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
    let conflict = textConflict(path: "Sources/Login.swift")
    let wc = URL(fileURLWithPath: "/tmp/wc")

    await viewModel.load(conflict: conflict, wc: wc)
    await viewModel.requestAIResolutionForCurrentConflict()

    XCTAssertEqual(viewModel.aiConflictAssistState, .suggested(suggestion))
    XCTAssertEqual(viewModel.aiConflictSuggestion, suggestion)
    XCTAssertEqual(viewModel.unresolvedConflictCount, 0)
    XCTAssertEqual(viewModel.mergedText(), "a\nai merged\nz\n")
    XCTAssertTrue(viewModel.hasUnsavedChanges)
    XCTAssertTrue(viewModel.canSaveResolved)
    let calls = await assistant.recordedCalls()
    XCTAssertEqual(calls.map(\.context.path), ["Sources/Login.swift"])
    XCTAssertEqual(calls[0].context.baseLines, ["base"])
    XCTAssertEqual(calls[0].context.mineLines, ["mine"])
    XCTAssertEqual(calls[0].context.theirsLines, ["theirs"])
    XCTAssertTrue((await provider.recordedSaveCalls()).isEmpty)
    XCTAssertTrue((await provider.recordedWholeFileResolveCalls()).isEmpty)
}

@MainActor
func testAIConflictSuggestionUnavailableMissingConflictAndProviderErrors() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "base\n",
        mine: "mine\n",
        theirs: "theirs\n"
    )))
    let noAssistant = MergeEditorViewModel(provider: provider)

    await noAssistant.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    await noAssistant.requestAIResolutionForCurrentConflict()
    XCTAssertEqual(noAssistant.aiConflictAssistState, .error("aiConflictAssistantUnavailable"))

    let assistant = FakeAIConflictAssistant(result: .failure(AIConflictAssistError.emptyConflict))
    let noConflictLoaded = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
    await noConflictLoaded.requestAIResolutionForCurrentConflict()
    XCTAssertEqual(noConflictLoaded.aiConflictAssistState, .error("missingConflict"))

    let loaded = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
    await loaded.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    await loaded.requestAIResolutionForCurrentConflict()
    XCTAssertEqual(
        loaded.aiConflictAssistState,
        .error(String(describing: AIConflictAssistError.emptyConflict))
    )
}
```

在测试文件底部增加：

```swift
private struct AIConflictAssistCall: Equatable, Sendable {
    let context: AIConflictAssistContext
    let privacySettings: AIPrivacySettings
}

private actor FakeAIConflictAssistant: AIConflictAssisting {
    private let result: Result<AIConflictAssistSuggestion, Error>
    private var calls: [AIConflictAssistCall] = []

    init(result: Result<AIConflictAssistSuggestion, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AIConflictAssistCall] {
        calls
    }

    func suggestResolution(
        context: AIConflictAssistContext,
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistSuggestion {
        calls.append(AIConflictAssistCall(context: context, privacySettings: privacySettings))
        return try result.get()
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter MergeEditorViewModelTests
```

预期：编译失败，提示 `MergeEditorViewModel` 初始化参数、`requestAIResolutionForCurrentConflict` 或 `AIConflictAssistViewState` 不存在。

- [ ] **步骤 3：实现最少 ViewModel 接入**

在 `MergeEditorViewModel.swift` 增加：

```swift
public enum AIConflictAssistViewState: Equatable, Sendable {
    case idle
    case suggesting
    case suggested(AIConflictAssistSuggestion)
    case error(String)
}
```

扩展 `MergeEditorViewModel`：

- 新增 `private let aiConflictAssistant: (any AIConflictAssisting)?`；
- `init` 新增可选参数 `aiConflictAssistant: (any AIConflictAssisting)? = nil`；
- 新增 `public private(set) var aiConflictAssistState: AIConflictAssistViewState = .idle`；
- 新增 `public private(set) var aiConflictSuggestion: AIConflictAssistSuggestion?`；
- `load` 与 `discardEdits` 不清空历史建议结果，`load` 开始时重置 AI 状态；
- 新增 `requestAIResolutionForCurrentConflict(privacySettings:)`：

```swift
public func requestAIResolutionForCurrentConflict(
    privacySettings: AIPrivacySettings = AIPrivacySettings()
) async
```

行为：

1. 无 assistant：`aiConflictAssistState = .error("aiConflictAssistantUnavailable")`；
2. 无当前冲突块：`aiConflictAssistState = .error("missingConflict")`；
3. 从当前 `ConflictHunk` 构造 `AIConflictAssistContext`；
4. 调用 assistant；
5. 成功后通过 `resolveConflict(atConflictIndex: currentConflictIndex, resolution: .manual(lines: suggestion.mergedLines))` 预填；
6. 记录 `aiConflictSuggestion` 与 `.suggested(suggestion)`；
7. 失败时记录 `.error(String(describing: error))`，不改变已有块。

上下文构造：`leadingContext` 取当前 conflict block 前一个 `.stable` block 的最后 3 行，`trailingContext` 取后一个 `.stable` block 的前 3 行。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "AIConflictAssistantTests|MergeEditorViewModelTests"
```

预期：AI 冲突服务与 MergeEditorViewModel 测试全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift \
  Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-conflict-assist-core.md
git diff --cached --check
git commit -m "feat: connect P6 AI conflict assistant to merge editor"
```

---

## 任务 3：全量验证与计划收尾

- [ ] **步骤 1：运行 P6 AI + P3 Merge 目标集合**

```bash
swift test --filter "AIDataRedactorTests|AIProviderStoreTests|AIProviderSettingsViewModelTests|AICommitMessageGeneratorTests|AIPreCommitReviewerTests|AIConflictAssistantTests|MergeEditorViewModelTests|MergeEngineTests"
```

预期：0 failures。

- [ ] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：全量测试 0 failures，空白检查无输出。

- [ ] **步骤 3：Commit**

```bash
git add docs/superpowers/plans/2026-07-10-p6-ai-conflict-assist-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI conflict assist verification"
```

---

## 自检

- 覆盖 `FR-AI-03` 的逐冲突块 Core：base/mine/theirs + 上下文发送给模型，返回建议合并结果、理由和置信度。
- 建议通过 `.manual(lines:)` 预填当前冲突块，只改变 ViewModel 内存状态；不调用 `saveResolution`、`resolveWholeFile` 或任何 SVN 写操作。
- 复用 `FR-AI-00` provider 配置与 `NFR-11` 脱敏设置。
- 本计划不实现真实 OpenAI/Anthropic/Ollama 网络客户端、SwiftUI 按钮/渲染、整文件级全量合并预览、token 计量、审计日志或结果持久化。
