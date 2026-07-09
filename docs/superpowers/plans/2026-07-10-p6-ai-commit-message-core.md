# P6 AI Commit Message Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-01` 建立 AI 生成提交说明 Core：基于提交对话框勾选文件的 unified diff，经过脱敏后调用可注入 LLM，生成中文提交说明并填入提交说明输入状态，不自动提交。

**架构：** 在 `AIModels.swift` 中补充 LLM 消息、响应、提交说明格式、草稿和错误模型。新增 `AICommitMessageGenerator` 服务，依赖 `AIProviderManaging`、现有 `DiffProviding`、`AIDataRedactor` 和可注入 `LLMChatting` 协议完成 provider 解析、diff 收集、脱敏、prompt 构造与长 diff map-reduce。扩展 `CommitViewModel`，通过可选 `AICommitMessageGenerating` 依赖暴露生成状态，成功后只设置 `message`。

**技术栈：** Swift Package、Foundation、Observation、XCTest concurrency、TDD。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  增加 LLM chat 抽象、提交说明格式、草稿和错误模型。
- 创建：`Sources/MacSvnCore/Services/AICommitMessageGenerator.swift`
  收集 selected paths 的 diff，脱敏，构造 prompt，调用 LLM；长 diff 按文件摘要后再汇总。
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
  增加 AI 生成状态与 `generateAICommitMessage` 方法，成功后填入 `message`，不调用 commit provider。
- 创建测试：`Tests/MacSvnCoreTests/AICommitMessageGeneratorTests.swift`
  覆盖默认 provider、diff 收集、脱敏、格式 prompt、长 diff map-reduce 与缺省错误。
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`
  覆盖生成成功填入 message、不自动提交、无生成器/空选择错误。

## 任务 1：AI Commit Message Generator 服务

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AICommitMessageGenerator.swift`
- 测试：`Tests/MacSvnCoreTests/AICommitMessageGeneratorTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `Tests/MacSvnCoreTests/AICommitMessageGeneratorTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AICommitMessageGeneratorTests: XCTestCase {
    func testGenerateUsesDefaultProviderSelectedDiffsAndRedactsSecrets() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let providerManager = FakeAIProviderManager(providers: [provider])
        let diffProvider = FakeCommitDiffProvider(diffs: [
            "Sources/Login.swift": """
            Index: Sources/Login.swift
            @@ -1,1 +1,1 @@
            -let token = "sk-1234567890abcdef"
            +let token = credentialStore.token
            """,
            "Tests/LoginTests.swift": """
            Index: Tests/LoginTests.swift
            @@ -1,1 +1,1 @@
            +func testCredentialStoreToken() {}
            """
        ])
        let llm = FakeLLMClient(responses: [
            AILLMResponse(content: "fix: 修复登录令牌读取", promptTokens: 120, completionTokens: 9)
        ])
        let generator = AICommitMessageGenerator(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: llm
        )

        let draft = try await generator.generateCommitMessage(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["Sources/Login.swift", "Tests/LoginTests.swift"],
            format: .conventionalChinese,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let diffCalls = await diffProvider.recordedCalls()

        XCTAssertEqual(draft.message, "fix: 修复登录令牌读取")
        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.sourceFileCount, 2)
        XCTAssertFalse(draft.usedMapReduce)
        XCTAssertEqual(draft.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(diffCalls.map(\.target), ["Sources/Login.swift", "Tests/LoginTests.swift"])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].provider, provider)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("Conventional Commits 中文式"))
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("***REDACTED***"))
        XCTAssertFalse(calls[0].messages.map(\.content).joined().contains("sk-1234567890abcdef"))
    }

    func testLongDiffsAreSummarizedPerFileBeforeFinalMessage() async throws {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )
        let longLine = String(repeating: "+changed\n", count: 40)
        let diffProvider = FakeCommitDiffProvider(diffs: [
            "A.swift": "Index: A.swift\n\(longLine)",
            "B.swift": "Index: B.swift\n\(longLine)"
        ])
        let llm = FakeLLMClient(responses: [
            AILLMResponse(content: "A.swift: 调整登录流程", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "B.swift: 补充测试覆盖", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "完善登录流程并补充测试", promptTokens: 40, completionTokens: 10)
        ])
        let generator = AICommitMessageGenerator(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm,
            maxPromptCharacters: 120
        )

        let draft = try await generator.generateCommitMessage(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["A.swift", "B.swift"],
            format: .oneLineChinese,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()

        XCTAssertEqual(draft.message, "完善登录流程并补充测试")
        XCTAssertTrue(draft.usedMapReduce)
        XCTAssertEqual(draft.promptCount, 3)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("请摘要这个文件 diff"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("A.swift: 调整登录流程"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("B.swift: 补充测试覆盖"))
    }

    func testThrowsWhenNoDefaultProviderOrSelectionOrDiffContent() async throws {
        let provider = AIProvider(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude",
            apiKeyRef: "keychain://claude",
            maxTokens: 4096,
            temperature: 0.2
        )

        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: []),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "+a"]),
            paths: ["a.swift"],
            expected: .missingDefaultProvider
        )
        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "+a"]),
            paths: [],
            expected: .emptySelection
        )
        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "   "]),
            paths: ["a.swift"],
            expected: .emptyDiff
        )
    }

    private func assertGenerateThrows(
        providerManager: FakeAIProviderManager,
        diffProvider: FakeCommitDiffProvider,
        paths: [String],
        expected: AICommitMessageError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let generator = AICommitMessageGenerator(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: FakeLLMClient(responses: [])
        )

        do {
            _ = try await generator.generateCommitMessage(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: paths,
                format: .oneLineChinese,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AICommitMessageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AICommitMessageError, got \(error)", file: file, line: line)
        }
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AICommitMessageGeneratorTests
```

预期：编译失败，提示 `AICommitMessageGenerator` / `AILLMResponse` / `LLMChatting` / `AICommitMessageError` 未定义。

- [x] **步骤 3：实现最少模型与服务代码**

在 `AIModels.swift` 增加：

```swift
public enum AILLMRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct AILLMMessage: Codable, Equatable, Sendable {
    public let role: AILLMRole
    public let content: String
}

public struct AILLMResponse: Codable, Equatable, Sendable {
    public let content: String
    public let promptTokens: Int?
    public let completionTokens: Int?
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
}

public enum AICommitMessageError: Error, Equatable, Sendable {
    case emptySelection
    case missingDefaultProvider
    case emptyDiff
    case emptyModelResponse
}
```

创建 `AICommitMessageGenerator.swift`：

```swift
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
```

实现要求：
- `paths` 为空时抛 `.emptySelection`；
- 从 `AIProviderManaging` 读取 provider 列表与 `defaultProviderID()`，找不到时抛 `.missingDefaultProvider`；
- 对每个 path 调用 `diffProvider.diff(wc:target:r1:nil:r2:nil)`，保留调用顺序；
- 空白 diff 全部过滤后为空时抛 `.emptyDiff`；
- `privacySettings.isRedactionEnabled == true` 时使用 `AIDataRedactor.redact(_, customPatterns:)`，否则原文进入 prompt；
- prompt 需明确“生成中文提交说明”“不要自动提交”“只返回提交说明文本”；
- `format` 分别映射一行式、Conventional Commits 中文式、公司模板；
- 合并 diff 字符数不超过 `maxPromptCharacters` 时发送一次；
- 超过时先逐文件发送“请摘要这个文件 diff”，再用摘要发送最终 prompt；
- LLM 返回内容 trim 后为空时抛 `.emptyModelResponse`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AICommitMessageGeneratorTests
```

预期：新增 generator 测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AICommitMessageGenerator.swift \
  Tests/MacSvnCoreTests/AICommitMessageGeneratorTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-commit-message-core.md
git diff --cached --check
git commit -m "feat: add P6 AI commit message generator core"
```

## 任务 2：CommitViewModel 接入 AI 生成说明

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `CommitViewModelTests` 新增：

```swift
@MainActor
func testGenerateAICommitMessageFillsMessageWithoutCommitting() async {
    let draft = AICommitMessageDraft(
        message: "feat: 增加登录校验",
        providerID: UUID(),
        sourceFileCount: 1,
        redactionMatches: [],
        promptCount: 1,
        usedMapReduce: false
    )
    let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
    let generator = FakeAICommitMessageGenerator(result: .success(draft))
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: commitProvider,
        statusProvider: FakeStatusProvider(result: .success([])),
        aiCommitMessageGenerator: generator
    )
    viewModel.setSelected(false, for: "deleted.swift")

    await viewModel.generateAICommitMessage(format: .conventionalChinese)
    let calls = await generator.recordedCalls()
    let commitCalls = await commitProvider.recordedCalls()

    XCTAssertEqual(viewModel.message, "feat: 增加登录校验")
    XCTAssertEqual(viewModel.aiCommitMessageDraft, draft)
    XCTAssertEqual(viewModel.aiCommitMessageState, .generated(draft))
    XCTAssertEqual(calls.map(\.paths), [["modified.swift", "added.swift", "replaced.swift"]])
    XCTAssertTrue(commitCalls.isEmpty)
}

@MainActor
func testGenerateAICommitMessageStoresUnavailableAndSelectionErrors() async {
    let noGeneratorViewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([]))
    )

    await noGeneratorViewModel.generateAICommitMessage()
    XCTAssertEqual(noGeneratorViewModel.aiCommitMessageState, .error("aiCommitMessageGeneratorUnavailable"))

    let generator = FakeAICommitMessageGenerator(result: .failure(AICommitMessageError.emptySelection))
    let emptySelectionViewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([])),
        aiCommitMessageGenerator: generator
    )
    emptySelectionViewModel.selectedPaths.removeAll()

    await emptySelectionViewModel.generateAICommitMessage()

    XCTAssertEqual(emptySelectionViewModel.aiCommitMessageState, .error(String(describing: AICommitMessageError.emptySelection)))
}
```

并在测试文件底部增加 fake：

```swift
private struct AICommitMessageCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let format: AICommitMessageFormat
    let privacySettings: AIPrivacySettings
}

private actor FakeAICommitMessageGenerator: AICommitMessageGenerating {
    private let result: Result<AICommitMessageDraft, Error>
    private var calls: [AICommitMessageCall] = []

    init(result: Result<AICommitMessageDraft, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AICommitMessageCall] {
        calls
    }

    func generateCommitMessage(
        wc: URL,
        paths: [String],
        format: AICommitMessageFormat,
        privacySettings: AIPrivacySettings
    ) async throws -> AICommitMessageDraft {
        calls.append(AICommitMessageCall(wc: wc, paths: paths, format: format, privacySettings: privacySettings))
        return try result.get()
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommitViewModelTests
```

预期：编译失败，提示 `CommitViewModel` 初始化参数、`generateAICommitMessage` 或 AI 状态属性不存在。

- [x] **步骤 3：实现最少 ViewModel 接入**

在 `CommitViewModel.swift` 增加：

```swift
public enum AICommitMessageViewState: Equatable, Sendable {
    case idle
    case generating
    case generated(AICommitMessageDraft)
    case error(String)
}
```

并修改 `CommitViewModel`：
- 新增 `private let aiCommitMessageGenerator: (any AICommitMessageGenerating)?`；
- `init` 新增可选参数 `aiCommitMessageGenerator: (any AICommitMessageGenerating)? = nil`；
- 新增 `public private(set) var aiCommitMessageState: AICommitMessageViewState = .idle`；
- 新增 `public private(set) var aiCommitMessageDraft: AICommitMessageDraft?`；
- 新增方法：

```swift
public func generateAICommitMessage(
    format: AICommitMessageFormat = .conventionalChinese,
    privacySettings: AIPrivacySettings = AIPrivacySettings()
) async
```

方法行为：
- 无 generator 时设置 `.error("aiCommitMessageGeneratorUnavailable")`；
- 进入 `.generating`；
- 调 generator，传 `workingCopy` 与 `orderedSelectedPaths`；
- 成功后设置 `message = draft.message`、`aiCommitMessageDraft = draft`、状态 `.generated(draft)`；
- 失败时清空 `aiCommitMessageDraft`，状态 `.error(String(describing: error))`；
- 不调用 `commitProvider.commit`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter "AICommitMessageGeneratorTests|CommitViewModelTests"
```

预期：AI generator 与 CommitViewModel 测试全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CommitViewModel.swift \
  Tests/MacSvnCoreTests/CommitViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-commit-message-core.md
git diff --cached --check
git commit -m "feat: connect P6 AI commit message generation to commit view model"
```

## 任务 3：全量验证与计划收尾

- [ ] **步骤 1：运行 P6 AI 目标集合**

```bash
swift test --filter "AIDataRedactorTests|AIProviderStoreTests|AIProviderSettingsViewModelTests|AICommitMessageGeneratorTests|CommitViewModelTests"
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
git add docs/superpowers/plans/2026-07-10-p6-ai-commit-message-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI commit message verification"
```

## 自检

- 覆盖 `FR-AI-01` 的 Core：勾选文件 diff、脱敏后发送、中文提交说明、多格式 prompt、填入提交说明、不自动提交。
- 覆盖长 diff map-reduce 底座：合并 diff 超过阈值时先逐文件摘要，再汇总提交说明。
- 复用 `FR-AI-00` provider 配置与 `NFR-11` 脱敏设置。
- 不覆盖真实 OpenAI/Anthropic/Ollama 网络客户端、真实 Keychain 读写、UI 按钮、真实 token 计费、用户自定义模板持久化；这些继续拆为后续 P6 切片。
