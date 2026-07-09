# P6 AI Pre-commit Review Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-02` 建立提交前 AI 评审 Core：基于提交对话框勾选文件 diff，经过脱敏后调用可注入 LLM，输出阻断建议/一般建议/提示和疑似密钥醒目警示；结果仅展示，不阻断提交。

**架构：** 在 `AIModels.swift` 中补充 AI 评审 severity/category/finding/result/error 模型。新增 `AIPreCommitReviewer` 服务，复用 `AIProviderManaging`、`DiffProviding`、`AIDataRedactor` 和 `LLMChatting`，收集 selected paths 的 diff，脱敏后要求模型返回 JSON，解析成结构化评审结果；红色疑似密钥警示由脱敏命中记录确定性追加。扩展 `CommitViewModel`，通过可选 `AIPreCommitReviewing` 依赖暴露评审状态，评审成功仅保存展示结果，不改变 `canCommit` 与提交流程。

**技术栈：** Swift Package、Foundation Codable、Observation、XCTest concurrency、TDD。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  增加 AI 评审 severity/category/finding/result/error 模型。
- 创建：`Sources/MacSvnCore/Services/AIPreCommitReviewer.swift`
  收集 diff，脱敏，构造评审 prompt，解析 JSON 响应，支持长 diff map-reduce。
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
  增加 AI 评审状态与 `runAIPreCommitReview` 方法，结果仅展示不阻断。
- 创建测试：`Tests/MacSvnCoreTests/AIPreCommitReviewerTests.swift`
  覆盖默认 provider、diff 收集、脱敏、JSON 解析、疑似密钥警示、长 diff map-reduce 与错误。
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`
  覆盖评审成功保存结果、不自动提交、不阻断后续提交、无 reviewer/空选择错误。

## 任务 1：AI Pre-commit Reviewer 服务

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIPreCommitReviewer.swift`
- 测试：`Tests/MacSvnCoreTests/AIPreCommitReviewerTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `Tests/MacSvnCoreTests/AIPreCommitReviewerTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIPreCommitReviewerTests: XCTestCase {
    func testReviewParsesFindingsRedactsSecretsAndAddsSecretWarning() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let diffProvider = FakeReviewDiffProvider(diffs: [
            "Sources/Login.swift": """
            Index: Sources/Login.swift
            @@ -1,2 +1,2 @@
            -let token = "sk-1234567890abcdef"
            +let token = credentialStore.token
            +try! auth.login()
            """
        ])
        let llm = FakeReviewLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "summary": "发现 2 条建议",
                  "findings": [
                    {
                      "severity": "blockingSuggestion",
                      "category": "correctness",
                      "path": "Sources/Login.swift",
                      "line": 3,
                      "message": "避免在登录流程中使用 try!",
                      "rationale": "认证失败会导致崩溃。"
                    },
                    {
                      "severity": "tip",
                      "category": "testing",
                      "path": "Sources/Login.swift",
                      "line": null,
                      "message": "补充失败路径测试。",
                      "rationale": null
                    }
                  ]
                }
                """,
                promptTokens: 160,
                completionTokens: 80
            )
        ])
        let reviewer = AIPreCommitReviewer(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm
        )

        let result = try await reviewer.review(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["Sources/Login.swift"],
            privacySettings: AIPrivacySettings()
        )
        let llmCalls = await llm.recordedCalls()
        let diffCalls = await diffProvider.recordedCalls()

        XCTAssertEqual(result.providerID, provider.id)
        XCTAssertEqual(result.summary, "发现 2 条建议")
        XCTAssertEqual(result.sourceFileCount, 1)
        XCTAssertFalse(result.usedMapReduce)
        XCTAssertEqual(result.promptCount, 1)
        XCTAssertTrue(result.hasSuspectedSecretWarning)
        XCTAssertEqual(result.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(result.findings.map(\.severity), [.blockingSuggestion, .tip, .blockingSuggestion])
        XCTAssertEqual(result.findings.last?.category, .suspectedSecret)
        XCTAssertEqual(diffCalls.map(\.target), ["Sources/Login.swift"])
        XCTAssertTrue(llmCalls[0].messages.map(\.content).joined().contains("***REDACTED***"))
        XCTAssertFalse(llmCalls[0].messages.map(\.content).joined().contains("sk-1234567890abcdef"))
        XCTAssertTrue(llmCalls[0].messages.map(\.content).joined().contains("只输出 JSON"))
    }

    func testLongDiffsAreSummarizedBeforeFinalReview() async throws {
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
        let diffProvider = FakeReviewDiffProvider(diffs: [
            "A.swift": "Index: A.swift\n\(longLine)",
            "B.swift": "Index: B.swift\n\(longLine)"
        ])
        let llm = FakeReviewLLMClient(responses: [
            AILLMResponse(content: "A.swift: 登录流程变化", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "B.swift: 测试覆盖变化", promptTokens: 30, completionTokens: 8),
            AILLMResponse(
                content: """
                {
                  "summary": "长 diff 评审完成",
                  "findings": [
                    {
                      "severity": "generalSuggestion",
                      "category": "maintainability",
                      "path": "A.swift",
                      "line": null,
                      "message": "拆分登录流程改动。",
                      "rationale": "便于审查。"
                    }
                  ]
                }
                """,
                promptTokens: 60,
                completionTokens: 20
            )
        ])
        let reviewer = AIPreCommitReviewer(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm,
            maxPromptCharacters: 120
        )

        let result = try await reviewer.review(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["A.swift", "B.swift"],
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()

        XCTAssertEqual(result.summary, "长 diff 评审完成")
        XCTAssertTrue(result.usedMapReduce)
        XCTAssertEqual(result.promptCount, 3)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("请摘要这个文件 diff"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("A.swift: 登录流程变化"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("B.swift: 测试覆盖变化"))
    }

    func testThrowsForMissingInputsAndInvalidModelResponse() async throws {
        let provider = AIProvider(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude",
            apiKeyRef: "keychain://claude",
            maxTokens: 4096,
            temperature: 0.2
        )

        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: []),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: ["a.swift"],
            expected: .missingDefaultProvider
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: [],
            expected: .emptySelection
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "   "]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: ["a.swift"],
            expected: .emptyDiff
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: [
                AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
            ]),
            paths: ["a.swift"],
            expected: .invalidModelResponse("not json")
        )
    }

    private func assertReviewThrows(
        providerManager: FakeReviewProviderManager,
        diffProvider: FakeReviewDiffProvider,
        llmClient: FakeReviewLLMClient,
        paths: [String],
        expected: AIPreCommitReviewError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let reviewer = AIPreCommitReviewer(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: llmClient
        )

        do {
            _ = try await reviewer.review(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: paths,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AIPreCommitReviewError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIPreCommitReviewError, got \(error)", file: file, line: line)
        }
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIPreCommitReviewerTests
```

预期：编译失败，提示 `AIPreCommitReviewer` / `AIPreCommitReviewResult` / `AIPreCommitReviewError` 等类型未定义。

- [x] **步骤 3：实现最少模型与服务代码**

在 `AIModels.swift` 增加：

```swift
public enum AIPreCommitReviewSeverity: String, Codable, Equatable, Sendable {
    case blockingSuggestion
    case generalSuggestion
    case tip
}

public enum AIPreCommitReviewCategory: String, Codable, Equatable, Sendable {
    case correctness
    case security
    case maintainability
    case testing
    case style
    case suspectedSecret
}

public struct AIPreCommitReviewFinding: Codable, Equatable, Sendable {
    public let severity: AIPreCommitReviewSeverity
    public let category: AIPreCommitReviewCategory
    public let path: String?
    public let line: Int?
    public let message: String
    public let rationale: String?
}

public struct AIPreCommitReviewResult: Codable, Equatable, Sendable {
    public let summary: String
    public let findings: [AIPreCommitReviewFinding]
    public let providerID: UUID
    public let sourceFileCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int
    public let usedMapReduce: Bool

    public var hasSuspectedSecretWarning: Bool {
        findings.contains { $0.category == .suspectedSecret }
    }
}

public enum AIPreCommitReviewError: Error, Equatable, Sendable {
    case emptySelection
    case missingDefaultProvider
    case emptyDiff
    case emptyModelResponse
    case invalidModelResponse(String)
}
```

创建 `AIPreCommitReviewer.swift`：

```swift
public protocol AIPreCommitReviewing: Sendable {
    func review(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> AIPreCommitReviewResult
}
```

实现要求：
- `paths` 为空抛 `.emptySelection`；
- 从 `AIProviderManaging` 读取默认 provider；没有 provider 时抛 `.missingDefaultProvider`；
- 对每个 selected path 调 `diffProvider.diff(wc:target:r1:nil:r2:nil)`；
- 空白 diff 全部过滤后抛 `.emptyDiff`；
- 按 `AIPrivacySettings` 脱敏，prompt 不包含明文 secret；
- prompt 明确“只输出 JSON”，JSON shape 为 `summary/findings`；
- 模型返回空白抛 `.emptyModelResponse`，JSON 解码失败抛 `.invalidModelResponse(trimmedContent)`；
- `redactionMatches` 非空时，追加一个 `category == .suspectedSecret`、`severity == .blockingSuggestion` 的 finding；
- 合并 diff 超过 `maxPromptCharacters` 时先逐文件摘要，再对摘要做最终评审。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIPreCommitReviewerTests
```

预期：新增 reviewer 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AIPreCommitReviewer.swift \
  Tests/MacSvnCoreTests/AIPreCommitReviewerTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-precommit-review-core.md
git diff --cached --check
git commit -m "feat: add P6 AI precommit review core"
```

## 任务 2：CommitViewModel 接入 AI 预检

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `CommitViewModelTests` 新增：

```swift
@MainActor
func testRunAIPreCommitReviewStoresResultWithoutCommittingOrBlocking() async {
    let result = AIPreCommitReviewResult(
        summary: "发现 1 条阻断建议",
        findings: [
            AIPreCommitReviewFinding(
                severity: .blockingSuggestion,
                category: .correctness,
                path: "modified.swift",
                line: 12,
                message: "可能空指针。",
                rationale: "AI 建议人工检查。"
            )
        ],
        providerID: UUID(),
        sourceFileCount: 1,
        redactionMatches: [],
        promptCount: 1,
        usedMapReduce: false
    )
    let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
    let reviewer = FakeAIPreCommitReviewer(result: .success(result))
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: commitProvider,
        statusProvider: FakeStatusProvider(result: .success([])),
        aiPreCommitReviewer: reviewer
    )
    viewModel.message = "fix"
    viewModel.setSelected(false, for: "deleted.swift")

    await viewModel.runAIPreCommitReview()
    let reviewCalls = await reviewer.recordedCalls()
    let commitCallsBeforeCommit = await commitProvider.recordedCalls()

    XCTAssertEqual(viewModel.aiPreCommitReviewResult, result)
    XCTAssertEqual(viewModel.aiPreCommitReviewState, .reviewed(result))
    XCTAssertEqual(reviewCalls.map(\.paths), [["modified.swift", "added.swift", "replaced.swift"]])
    XCTAssertTrue(commitCallsBeforeCommit.isEmpty)
    XCTAssertTrue(viewModel.canCommit)

    await viewModel.commit(auth: nil)
    let commitCallsAfterCommit = await commitProvider.recordedCalls()

    XCTAssertEqual(commitCallsAfterCommit.count, 1)
}

@MainActor
func testRunAIPreCommitReviewStoresUnavailableAndSelectionErrors() async {
    let noReviewerViewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([]))
    )

    await noReviewerViewModel.runAIPreCommitReview()

    XCTAssertEqual(noReviewerViewModel.aiPreCommitReviewState, .error("aiPreCommitReviewerUnavailable"))

    let reviewer = FakeAIPreCommitReviewer(result: .failure(AIPreCommitReviewError.emptySelection))
    let emptySelectionViewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([])),
        aiPreCommitReviewer: reviewer
    )
    emptySelectionViewModel.selectedPaths.removeAll()

    await emptySelectionViewModel.runAIPreCommitReview()

    XCTAssertEqual(
        emptySelectionViewModel.aiPreCommitReviewState,
        .error(String(describing: AIPreCommitReviewError.emptySelection))
    )
}
```

并增加 fake：

```swift
private struct AIPreCommitReviewCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let privacySettings: AIPrivacySettings
}

private actor FakeAIPreCommitReviewer: AIPreCommitReviewing {
    private let result: Result<AIPreCommitReviewResult, Error>
    private var calls: [AIPreCommitReviewCall] = []

    init(result: Result<AIPreCommitReviewResult, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AIPreCommitReviewCall] {
        calls
    }

    func review(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> AIPreCommitReviewResult {
        calls.append(AIPreCommitReviewCall(wc: wc, paths: paths, privacySettings: privacySettings))
        return try result.get()
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommitViewModelTests
```

预期：编译失败，提示 `CommitViewModel` 初始化参数、`runAIPreCommitReview` 或 AI 评审状态属性不存在。

- [ ] **步骤 3：实现最少 ViewModel 接入**

在 `CommitViewModel.swift` 增加：

```swift
public enum AIPreCommitReviewViewState: Equatable, Sendable {
    case idle
    case reviewing
    case reviewed(AIPreCommitReviewResult)
    case error(String)
}
```

并修改 `CommitViewModel`：
- 新增 `private let aiPreCommitReviewer: (any AIPreCommitReviewing)?`；
- `init` 新增可选参数 `aiPreCommitReviewer: (any AIPreCommitReviewing)? = nil`；
- 新增 `public private(set) var aiPreCommitReviewState: AIPreCommitReviewViewState = .idle`；
- 新增 `public private(set) var aiPreCommitReviewResult: AIPreCommitReviewResult?`；
- 新增方法：

```swift
public func runAIPreCommitReview(
    privacySettings: AIPrivacySettings = AIPrivacySettings()
) async
```

方法行为：
- 无 reviewer 时设置 `.error("aiPreCommitReviewerUnavailable")`；
- 进入 `.reviewing`；
- 调 reviewer，传 `workingCopy` 与 `orderedSelectedPaths`；
- 成功后设置 `aiPreCommitReviewResult`、状态 `.reviewed(result)`；
- 失败时清空 result，状态 `.error(String(describing: error))`；
- 不调用 `commitProvider.commit`，不改变 `message`、`guardIssues` 或 `canCommit` 逻辑。

- [ ] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter "AIPreCommitReviewerTests|CommitViewModelTests"
```

预期：AI reviewer 与 CommitViewModel 测试全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CommitViewModel.swift \
  Tests/MacSvnCoreTests/CommitViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-precommit-review-core.md
git diff --cached --check
git commit -m "feat: connect P6 AI precommit review to commit view model"
```

## 任务 3：全量验证与计划收尾

- [ ] **步骤 1：运行 P6 AI 目标集合**

```bash
swift test --filter "AIDataRedactorTests|AIProviderStoreTests|AIProviderSettingsViewModelTests|AICommitMessageGeneratorTests|AIPreCommitReviewerTests|CommitViewModelTests"
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
git add docs/superpowers/plans/2026-07-10-p6-ai-precommit-review-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI precommit review verification"
```

## 自检

- 覆盖 `FR-AI-02` 的 Core：基于勾选 diff、脱敏后发送、结构化分级意见、疑似密钥红色警示、仅展示不阻断。
- 复用 `FR-AI-00` provider 配置、`FR-AI-01` LLM 抽象与 `NFR-11` 脱敏设置。
- 与 `FR-EX-01` Commit Guard 边界清晰：Commit Guard 继续负责确定性阻断；AI 评审只给语义建议，不改变提交行为。
- 不覆盖真实 OpenAI/Anthropic/Ollama 网络客户端、UI 视图渲染、真实 token 计费、评审结果持久化；这些继续拆为后续 P6 切片。
