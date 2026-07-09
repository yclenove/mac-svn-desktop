# P6 AI Release Notes Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-05` 建立版本日志智能摘要 Core：把选定 revision/date 范围得到的 `LogEntry` 列表发送给 LLM，解析结构化分组，并生成可导出的 Markdown Release Notes。

**架构：** 新增 `AIReleaseNotesGenerator`，复用 `AIProviderManaging`、`LLMChatting` 与 `AIDataRedactor`。调用方负责选择 revision/date 范围并提供 `LogEntry`；生成器只做日志文本组装、脱敏、LLM JSON 解析与 Markdown 渲染，保证不执行 SVN 命令、不写文件。

**技术栈：** Swift 6、Foundation、XCTest、现有 `AIProviderManaging` / `LLMChatting` / `LogEntry`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  - 增加 `AIReleaseNotesTemplate`、`AIReleaseNotesSection`、`AIReleaseNotesDraft`、`AIReleaseNotesError`。
- 创建：`Sources/MacSvnCore/Services/AIReleaseNotesGenerator.swift`
  - 增加 `AIReleaseNotesGenerating` 协议与生成器实现。
- 创建：`Tests/MacSvnCoreTests/AIReleaseNotesGeneratorTests.swift`
  - 覆盖 JSON 解析、Markdown 渲染、脱敏、错误路径。

---

## 任务 1：Release Notes 生成器主路径

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIReleaseNotesGenerator.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIReleaseNotesGeneratorTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AIReleaseNotesGeneratorTests` 增加：

```swift
func testGenerateReleaseNotesParsesJSONBuildsMarkdownAndRedactsSecrets() async throws {
    let provider = AIProvider(
        name: "DeepSeek",
        kind: .openAICompatible,
        baseURL: "https://api.deepseek.com/v1",
        model: "deepseek-chat",
        apiKeyRef: "keychain://deepseek",
        maxTokens: 32_000,
        temperature: 0.2
    )
    let llm = FakeReleaseNotesLLMClient(responses: [
        AILLMResponse(
            content: """
            {
              "title": "v1.2.0",
              "sections": [
                {"title": "新功能", "items": ["支持支付回调"]},
                {"title": "修复", "items": ["修复登录失败提示"]}
              ]
            }
            """,
            promptTokens: 160,
            completionTokens: 60
        )
    ])
    let generator = AIReleaseNotesGenerator(
        providerManager: FakeReleaseNotesProviderManager(providers: [provider]),
        llmClient: llm
    )
    let entries = [
        LogEntry(
            revision: Revision(1200),
            author: "zhangsan",
            date: nil,
            message: "新增支付回调 sk-1234567890abcdef",
            changedPaths: [
                ChangedPath(path: "/trunk/payment/callback.swift", action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
            ]
        ),
        LogEntry(
            revision: Revision(1201),
            author: "lisi",
            date: nil,
            message: "修复登录失败提示",
            changedPaths: [
                ChangedPath(path: "/trunk/login/view.swift", action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
            ]
        )
    ]

    let draft = try await generator.generate(
        entries: entries,
        title: "v1.2.0",
        template: .standardMarkdown,
        privacySettings: AIPrivacySettings()
    )
    let calls = await llm.recordedCalls()
    let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

    XCTAssertEqual(draft.title, "v1.2.0")
    XCTAssertEqual(draft.providerID, provider.id)
    XCTAssertEqual(draft.entryCount, 2)
    XCTAssertEqual(draft.promptCount, 1)
    XCTAssertEqual(draft.redactionMatches.map(\.ruleID), ["openai-api-key"])
    XCTAssertTrue(draft.markdown.contains("# v1.2.0"))
    XCTAssertTrue(draft.markdown.contains("## 新功能"))
    XCTAssertTrue(draft.markdown.contains("- 支持支付回调"))
    XCTAssertTrue(prompt.contains("r1200"))
    XCTAssertTrue(prompt.contains("/trunk/payment/callback.swift"))
    XCTAssertTrue(prompt.contains("***REDACTED***"))
    XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIReleaseNotesGeneratorTests
```

预期：编译失败，提示 `AIReleaseNotesGenerator`、`AIReleaseNotesTemplate` 或 `AIReleaseNotesDraft` 不存在。

- [x] **步骤 3：实现最少模型与生成器代码**

实现要求：
- 空 entries 在任务 2 前可先返回空错误占位，任务 2 补完整错误；
- `generate(entries:title:template:privacySettings:)` 选择默认 provider；
- prompt 包含 revision、author、message、changedPaths；
- prompt 经 `AIDataRedactor` 处理；
- LLM 只允许返回 JSON：`{"title":"v1.2.0","sections":[{"title":"新功能","items":["支持支付回调"]}]}`；
- 解析后渲染 Markdown：`# title`、`## section.title`、`- item`；
- 返回 providerID、entryCount、redactionMatches、promptCount。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIReleaseNotesGeneratorTests
```

预期：主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift Sources/MacSvnCore/Services/AIReleaseNotesGenerator.swift Tests/MacSvnCoreTests/AIReleaseNotesGeneratorTests.swift docs/superpowers/plans/2026-07-10-p6-ai-release-notes-core.md
git diff --cached --check
git commit -m "feat: add P6 AI release notes generator core"
```

---

## 任务 2：错误路径

**文件：**
- 修改：`Sources/MacSvnCore/Services/AIReleaseNotesGenerator.swift`
- 修改测试：`Tests/MacSvnCoreTests/AIReleaseNotesGeneratorTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AIReleaseNotesGeneratorTests` 增加：

```swift
func testThrowsForMissingInputsAndInvalidModelResponse() async throws {
    let provider = AIProvider(
        name: "Local",
        kind: .ollama,
        baseURL: "http://localhost:11434",
        model: "llama3",
        apiKeyRef: nil,
        maxTokens: 4096,
        temperature: 0.1
    )
    let entry = LogEntry(revision: Revision(1), author: "a", date: nil, message: "m", changedPaths: [])

    try await assertGenerateThrows(
        providerManager: FakeReleaseNotesProviderManager(providers: []),
        llmClient: FakeReleaseNotesLLMClient(responses: []),
        entries: [entry],
        expected: .missingDefaultProvider
    )
    try await assertGenerateThrows(
        providerManager: FakeReleaseNotesProviderManager(providers: [provider]),
        llmClient: FakeReleaseNotesLLMClient(responses: []),
        entries: [],
        expected: .emptyLogSelection
    )
    try await assertGenerateThrows(
        providerManager: FakeReleaseNotesProviderManager(providers: [provider]),
        llmClient: FakeReleaseNotesLLMClient(responses: [
            AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)
        ]),
        entries: [entry],
        expected: .emptyModelResponse
    )
    try await assertGenerateThrows(
        providerManager: FakeReleaseNotesProviderManager(providers: [provider]),
        llmClient: FakeReleaseNotesLLMClient(responses: [
            AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
        ]),
        entries: [entry],
        expected: .invalidModelResponse("not json")
    )
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIReleaseNotesGeneratorTests
```

预期：错误路径测试失败或编译失败。

- [x] **步骤 3：实现最少错误处理**

实现要求：
- provider 列表为空抛 `.missingDefaultProvider`；
- entries 为空抛 `.emptyLogSelection`；
- 空 LLM 响应抛 `.emptyModelResponse`；
- 非 JSON 或 schema 不匹配抛 `.invalidModelResponse(trimmed)`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIReleaseNotesGeneratorTests
```

预期：全部 `AIReleaseNotesGeneratorTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AIReleaseNotesGenerator.swift Tests/MacSvnCoreTests/AIReleaseNotesGeneratorTests.swift docs/superpowers/plans/2026-07-10-p6-ai-release-notes-core.md
git diff --cached --check
git commit -m "feat: handle P6 AI release notes errors"
```

---

## 任务 3：目标验证与计划收尾

- [x] **步骤 1：运行 P6 Release Notes 目标集合**

```bash
swift test --filter "AIReleaseNotesGeneratorTests|LogXMLParserTests|LogViewModelTests"
```

预期：0 failures。

- [x] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：全量测试 0 failures，空白检查无输出。

- [x] **步骤 3：Commit**

```bash
git add docs/superpowers/plans/2026-07-10-p6-ai-release-notes-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI release notes verification"
```

---

## 自检

- 覆盖 `FR-AI-05` 的 Core：选定日志条目、结构化分组、Markdown Release Notes、模板参数入口。
- 复用 `FR-AI-00` provider 配置、`LLMChatting` 和 `NFR-11` 脱敏管道。
- 本计划不实现 SwiftUI 入口、Log 视图中的范围选择、Markdown 文件导出按钮、模板编辑 UI 或真实网络客户端；这些另行拆分。
