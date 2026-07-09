# P6 AI Conflict Full Preview Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 `FR-AI-03` 的整文件级 AI 全量合并预览 Core：一次性为所有冲突块返回建议、理由和置信度；高/中置信建议可预填，低置信块保持未解决以强制人工处理。

**架构：** 扩展 `AIConflictAssisting` 增加批量预览方法，复用已有 provider、LLM、脱敏与 JSON 解析路径。新增 `AIConflictBlockSuggestion` 与 `AIConflictAssistPreview` 模型表示逐块建议。扩展 `MergeEditorViewModel`，批量构造所有冲突块上下文，保存整文件预览结果，只把非低置信建议转成 `.manual(lines:)`，低置信建议不改变 hunk resolution。

**技术栈：** Swift 6、Foundation、Observation、XCTest、现有 `AIConflictAssistant` / `MergeEngine` / `MergeEditorViewModel`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  - 增加 `AIConflictBlockSuggestion`、`AIConflictAssistPreview`。
- 修改：`Sources/MacSvnCore/Services/AIConflictAssistant.swift`
  - `AIConflictAssisting` 增加批量 `suggestResolutions` 方法；服务实现全文件 prompt 和 JSON 解析。
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
  - 增加 `aiConflictPreview` 与 `requestAIResolutionPreviewForAllConflicts`。
- 修改测试：`Tests/MacSvnCoreTests/AIConflictAssistantTests.swift`
  - 覆盖批量 JSON、脱敏、空上下文错误。
- 修改测试：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`
  - 覆盖高/中置信预填、低置信保持未解决、不保存不 resolve。
- 修改计划：`docs/superpowers/plans/2026-07-10-p6-ai-conflict-full-preview-core.md`

---

## 任务 1：AIConflictAssistant 批量预览

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 修改：`Sources/MacSvnCore/Services/AIConflictAssistant.swift`
- 修改测试：`Tests/MacSvnCoreTests/AIConflictAssistantTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `AIConflictAssistantTests` 增加：

```swift
func testSuggestResolutionsParsesBlockSuggestionsAndRedactsAllContexts() async throws {
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
              "suggestions": [
                {
                  "conflictIndex": 0,
                  "mergedText": "first merged",
                  "rationale": "第一块可自动合并。",
                  "confidence": "high"
                },
                {
                  "conflictIndex": 1,
                  "mergedText": "second merged",
                  "rationale": "第二块风险高，需要人工确认。",
                  "confidence": "low"
                }
              ]
            }
            """,
            promptTokens: 240,
            completionTokens: 80
        )
    ])
    let assistant = AIConflictAssistant(
        providerManager: FakeConflictProviderManager(providers: [provider]),
        llmClient: llm
    )
    let contexts = [
        AIConflictAssistContext(
            path: "Sources/Login.swift",
            conflictIndex: 0,
            baseLines: ["let token = \"sk-1234567890abcdef\""],
            mineLines: ["let token = credentialStore.token"],
            theirsLines: ["let token = \"sk-1234567890abcdef\"", "try auth.login()"],
            leadingContext: [],
            trailingContext: []
        ),
        AIConflictAssistContext(
            path: "Sources/Login.swift",
            conflictIndex: 1,
            baseLines: ["return false"],
            mineLines: ["return isValid"],
            theirsLines: ["return hasPermission"],
            leadingContext: [],
            trailingContext: []
        )
    ]

    let preview = try await assistant.suggestResolutions(
        contexts: contexts,
        privacySettings: AIPrivacySettings()
    )
    let prompt = await llm.recordedCalls()[0].messages.map(\.content).joined(separator: "\n")

    XCTAssertEqual(preview.providerID, provider.id)
    XCTAssertEqual(preview.promptCount, 1)
    XCTAssertEqual(preview.redactionMatches.map(\.ruleID), ["openai-api-key"])
    XCTAssertEqual(preview.suggestions.map(\.conflictIndex), [0, 1])
    XCTAssertEqual(preview.suggestions.map(\.mergedLines), [["first merged"], ["second merged"]])
    XCTAssertEqual(preview.suggestions.map(\.confidence), [.high, .low])
    XCTAssertTrue(prompt.contains("***REDACTED***"))
    XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
    XCTAssertTrue(prompt.contains("suggestions"))
}

func testSuggestResolutionsRejectsEmptyContextList() async throws {
    let provider = AIProvider(
        name: "Local",
        kind: .ollama,
        baseURL: "http://localhost:11434",
        model: "llama3",
        apiKeyRef: nil,
        maxTokens: 4096,
        temperature: 0.1
    )
    let assistant = AIConflictAssistant(
        providerManager: FakeConflictProviderManager(providers: [provider]),
        llmClient: FakeConflictLLMClient(responses: [])
    )

    do {
        _ = try await assistant.suggestResolutions(
            contexts: [],
            privacySettings: AIPrivacySettings()
        )
        XCTFail("Expected emptyConflict")
    } catch let error as AIConflictAssistError {
        XCTAssertEqual(error, .emptyConflict)
    } catch {
        XCTFail("Expected AIConflictAssistError, got \(error)")
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIConflictAssistantTests
```

预期：编译失败，提示 `suggestResolutions`、`AIConflictAssistPreview` 或 `AIConflictBlockSuggestion` 不存在。

- [ ] **步骤 3：实现最少模型与服务代码**

在 `AIModels.swift` 增加：

```swift
public struct AIConflictBlockSuggestion: Codable, Equatable, Sendable {
    public let conflictIndex: Int
    public let mergedLines: [String]
    public let rationale: String
    public let confidence: AIConflictConfidence
}

public struct AIConflictAssistPreview: Codable, Equatable, Sendable {
    public let suggestions: [AIConflictBlockSuggestion]
    public let providerID: UUID
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int
}
```

在 `AIConflictAssisting` 和 `AIConflictAssistant` 增加：

```swift
func suggestResolutions(
    contexts: [AIConflictAssistContext],
    privacySettings: AIPrivacySettings
) async throws -> AIConflictAssistPreview
```

实现要求：
- `contexts.isEmpty` 抛 `.emptyConflict`；
- prompt 要求模型输出 `{"suggestions":[...]}` JSON；
- 每个 payload suggestion 的 `mergedText` 转为 `mergedLines`；
- redaction matches 来自整个批量 prompt；
- `promptCount` 为 1。

- [ ] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIConflictAssistantTests
```

预期：`AIConflictAssistantTests` 全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AIConflictAssistant.swift \
  Tests/MacSvnCoreTests/AIConflictAssistantTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-conflict-full-preview-core.md
git diff --cached --check
git commit -m "feat: add P6 AI conflict full preview core"
```

---

## 任务 2：MergeEditorViewModel 全量预览接入

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改测试：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEditorViewModelTests` 增加：

```swift
@MainActor
func testAIConflictPreviewPrefillsNonLowConfidenceAndKeepsLowConfidenceUnresolved() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "one\nsame\ntwo\n",
        mine: "mine-one\nsame\nmine-two\n",
        theirs: "theirs-one\nsame\ntheirs-two\n"
    )))
    let preview = AIConflictAssistPreview(
        suggestions: [
            AIConflictBlockSuggestion(
                conflictIndex: 0,
                mergedLines: ["ai-one"],
                rationale: "第一块可合并。",
                confidence: .high
            ),
            AIConflictBlockSuggestion(
                conflictIndex: 1,
                mergedLines: ["ai-two"],
                rationale: "第二块低置信。",
                confidence: .low
            )
        ],
        providerID: UUID(),
        redactionMatches: [],
        promptCount: 1
    )
    let assistant = FakeAIConflictAssistant(previewResult: .success(preview))
    let viewModel = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)

    await viewModel.load(conflict: textConflict(path: "Sources/Login.swift"), wc: URL(fileURLWithPath: "/tmp/wc"))
    await viewModel.requestAIResolutionPreviewForAllConflicts()

    XCTAssertEqual(viewModel.aiConflictPreview, preview)
    XCTAssertEqual(viewModel.aiConflictAssistState, .previewed(preview))
    XCTAssertEqual(viewModel.unresolvedConflictCount, 1)
    XCTAssertNil(viewModel.mergedText())
    XCTAssertTrue(viewModel.hasUnsavedChanges)
    let calls = await assistant.recordedPreviewCalls()
    XCTAssertEqual(calls[0].contexts.map(\.conflictIndex), [0, 1])
    XCTAssertTrue((await provider.recordedSaveCalls()).isEmpty)
    XCTAssertTrue((await provider.recordedWholeFileResolveCalls()).isEmpty)
}
```

更新 `AIConflictAssistViewState` 期望支持 `.previewed(AIConflictAssistPreview)`。更新 `FakeAIConflictAssistant`，为单块和批量分别记录调用：

```swift
private struct AIConflictPreviewCall: Equatable, Sendable {
    let contexts: [AIConflictAssistContext]
    let privacySettings: AIPrivacySettings
}
```

- [ ] **步骤 2：运行测试验证失败**

```bash
swift test --filter MergeEditorViewModelTests
```

预期：编译失败，提示 `requestAIResolutionPreviewForAllConflicts`、`aiConflictPreview` 或 `.previewed` 不存在。

- [ ] **步骤 3：实现最少 ViewModel 接入**

`MergeEditorViewModel` 增加：

- `public private(set) var aiConflictPreview: AIConflictAssistPreview?`
- `AIConflictAssistViewState.previewed(AIConflictAssistPreview)`
- `requestAIResolutionPreviewForAllConflicts(privacySettings:)`

行为：
1. 无 assistant 报 `aiConflictAssistantUnavailable`；
2. 无冲突块报 `missingConflict`；
3. 批量构造所有 conflict block 的 `AIConflictAssistContext`；
4. 成功保存 `aiConflictPreview`；
5. 对 `.high` / `.medium` 建议调用 `resolveConflict(atConflictIndex:resolution:)`；
6. `.low` 建议保持 unresolved；
7. 不调用 `saveResolution` 或 `resolveWholeFile`。

- [ ] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter "AIConflictAssistantTests|MergeEditorViewModelTests"
```

预期：批量预览与合并编辑器测试全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift \
  Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-conflict-full-preview-core.md
git diff --cached --check
git commit -m "feat: connect P6 AI conflict full preview to merge editor"
```

---

## 任务 3：全量验证与计划收尾

- [ ] **步骤 1：运行 FR-AI-03 目标集合**

```bash
swift test --filter "AIConflictAssistantTests|MergeEditorViewModelTests|MergeEngineTests"
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
git add docs/superpowers/plans/2026-07-10-p6-ai-conflict-full-preview-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI conflict full preview verification"
```

---

## 自检

- 覆盖 `FR-AI-03` 的整文件级预览底座：一次 LLM 调用返回逐块建议、理由和置信度。
- 低置信建议不自动变更 hunk resolution，保留人工处理门槛。
- 所有 AI 预览仍只改内存状态，不写盘、不 resolve、不执行 SVN 命令。
- 本计划不实现 SwiftUI 视图、真实网络客户端、token 计量、审计日志或结果持久化。
