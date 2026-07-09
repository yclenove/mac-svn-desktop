# P6 AI Blame Evolution Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-06` 建立 Blame 演化解释 Core：根据 blame 视图选中的代码行，收集相关 revision 的 log/diff 证据链，脱敏后交给 LLM，解析结构化中文解释。

**架构：** 新增 `AIBlameEvolutionExplainer`，复用 `AIProviderManaging`、`LLMChatting`、`AIDataRedactor`、`DiffProviding` 与 `LogProviding`。调用方提供已加载的 `BlameLine` 与选中行范围；解释器只执行只读 `diff/log` 查询、证据组装、脱敏、LLM JSON 解析，不执行写操作、不落盘。

**技术栈：** Swift 6、Foundation、XCTest、现有 `BlameLine` / `LogEntry` / `DiffProviding` / `LogProviding` / AI Provider 与 LLM 抽象。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  - 增加 `AIBlameLineRange`、`AIBlameEvolutionChange`、`AIBlameEvolutionExplanation`、`AIBlameEvolutionError`。
- 创建：`Sources/MacSvnCore/Services/AIBlameEvolutionExplainer.swift`
  - 增加 `AIBlameEvolutionExplaining` 协议与解释器实现。
- 创建：`Tests/MacSvnCoreTests/AIBlameEvolutionExplainerTests.swift`
  - 覆盖证据链收集、prompt 脱敏、JSON 解析、错误路径。

---

## 任务 1：Blame 演化解释主路径

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIBlameEvolutionExplainer.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIBlameEvolutionExplainerTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `AIBlameEvolutionExplainerTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIBlameEvolutionExplainerTests: XCTestCase {
    func testExplainCollectsRevisionDiffChainParsesJSONAndRedactsSecrets() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let blameLines = [
            BlameLine(lineNumber: 1, revision: Revision(1200), author: "zhangsan", date: nil),
            BlameLine(lineNumber: 2, revision: Revision(1201), author: "lisi", date: nil),
            BlameLine(lineNumber: 3, revision: Revision(1201), author: "lisi", date: nil)
        ]
        let diffProvider = FakeBlameEvolutionDiffProvider(diffs: [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1199), r2: Revision(1200)):
                "- old validate\n+ new validate sk-1234567890abcdef",
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1200), r2: Revision(1201)):
                "- sync login\n+ async retry"
        ])
        let logProvider = FakeBlameEvolutionLogProvider(entries: [
            Revision(1200): [
                LogEntry(
                    revision: Revision(1200),
                    author: "zhangsan",
                    date: nil,
                    message: "增加登录校验",
                    changedPaths: []
                )
            ],
            Revision(1201): [
                LogEntry(
                    revision: Revision(1201),
                    author: "lisi",
                    date: nil,
                    message: "改为异步重试",
                    changedPaths: []
                )
            ]
        ])
        let llm = FakeBlameEvolutionLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "summary": "这段登录逻辑从同步校验演进为异步重试。",
                  "keyChanges": [
                    {"revision": 1200, "title": "增加登录校验", "explanation": "首次加入登录校验分支。"},
                    {"revision": 1201, "title": "改为异步重试", "explanation": "为了处理网络抖动改成异步重试。"}
                  ]
                }
                """,
                promptTokens: 220,
                completionTokens: 90
            )
        ])
        let explainer = AIBlameEvolutionExplainer(
            providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            logProvider: logProvider,
            llmClient: llm
        )

        let explanation = try await explainer.explain(
            wc: wc,
            target: "Sources/Login.swift",
            lineRange: 1...3,
            blameLines: blameLines,
            privacySettings: AIPrivacySettings()
        )
        let llmCalls = await llm.recordedCalls()
        let prompt = llmCalls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(explanation.target, "Sources/Login.swift")
        XCTAssertEqual(explanation.lineRange, AIBlameLineRange(startLine: 1, endLine: 3))
        XCTAssertEqual(explanation.summary, "这段登录逻辑从同步校验演进为异步重试。")
        XCTAssertEqual(explanation.keyChanges.map(\.revision), [Revision(1200), Revision(1201)])
        XCTAssertEqual(explanation.providerID, provider.id)
        XCTAssertEqual(explanation.evidenceRevisionCount, 2)
        XCTAssertEqual(explanation.promptCount, 1)
        XCTAssertEqual(explanation.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertTrue(prompt.contains("Sources/Login.swift"))
        XCTAssertTrue(prompt.contains("选中行：1-3"))
        XCTAssertTrue(prompt.contains("r1200"))
        XCTAssertTrue(prompt.contains("r1201"))
        XCTAssertTrue(prompt.contains("增加登录校验"))
        XCTAssertTrue(prompt.contains("***REDACTED***"))
        XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))

        XCTAssertEqual(await diffProvider.recordedCalls(), [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1199), r2: Revision(1200)),
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1200), r2: Revision(1201))
        ])
        XCTAssertEqual(await logProvider.recordedCalls(), [
            LogCall(wc: wc, target: "Sources/Login.swift", from: Revision(1200), batch: 1, verbose: true),
            LogCall(wc: wc, target: "Sources/Login.swift", from: Revision(1201), batch: 1, verbose: true)
        ])
    }
}

private struct DiffCall: Hashable, Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private struct LogCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let from: Revision
    let batch: Int
    let verbose: Bool
}

private struct BlameEvolutionLLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private actor FakeBlameEvolutionDiffProvider: DiffProviding {
    private let diffs: [DiffCall: String]
    private var calls: [DiffCall] = []

    init(diffs: [DiffCall: String]) {
        self.diffs = diffs
    }

    func recordedCalls() -> [DiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        let call = DiffCall(wc: wc, target: target, r1: r1, r2: r2)
        calls.append(call)
        return diffs[call] ?? ""
    }
}

private actor FakeBlameEvolutionLogProvider: LogProviding {
    private let entries: [Revision: [LogEntry]]
    private var calls: [LogCall] = []

    init(entries: [Revision: [LogEntry]]) {
        self.entries = entries
    }

    func recordedCalls() -> [LogCall] {
        calls
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        calls.append(LogCall(wc: wc, target: target, from: from, batch: batch, verbose: verbose))
        return entries[from] ?? []
    }
}

private actor FakeBlameEvolutionLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [BlameEvolutionLLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [BlameEvolutionLLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(BlameEvolutionLLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeBlameEvolutionProviderManager: AIProviderManaging {
    private let providers: [AIProvider]
    private let defaultID: UUID?

    init(providers: [AIProvider], defaultID: UUID? = nil) {
        self.providers = providers
        self.defaultID = defaultID
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

```bash
swift test --filter AIBlameEvolutionExplainerTests
```

预期：编译失败，提示 `AIBlameEvolutionExplainer`、`AIBlameLineRange` 或 `AIBlameEvolutionExplanation` 不存在。

- [x] **步骤 3：实现最少模型与解释器代码**

在 `AIModels.swift` 增加：

```swift
public struct AIBlameLineRange: Codable, Equatable, Sendable {
    public let startLine: Int
    public let endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct AIBlameEvolutionChange: Codable, Equatable, Sendable {
    public let revision: Revision
    public let title: String
    public let explanation: String

    public init(revision: Revision, title: String, explanation: String) {
        self.revision = revision
        self.title = title
        self.explanation = explanation
    }
}

public struct AIBlameEvolutionExplanation: Codable, Equatable, Sendable {
    public let target: String
    public let lineRange: AIBlameLineRange
    public let summary: String
    public let keyChanges: [AIBlameEvolutionChange]
    public let providerID: UUID
    public let evidenceRevisionCount: Int
    public let redactionMatches: [AIRedactionMatch]
    public let promptCount: Int

    public init(
        target: String,
        lineRange: AIBlameLineRange,
        summary: String,
        keyChanges: [AIBlameEvolutionChange],
        providerID: UUID,
        evidenceRevisionCount: Int,
        redactionMatches: [AIRedactionMatch],
        promptCount: Int
    ) {
        self.target = target
        self.lineRange = lineRange
        self.summary = summary
        self.keyChanges = keyChanges
        self.providerID = providerID
        self.evidenceRevisionCount = evidenceRevisionCount
        self.redactionMatches = redactionMatches
        self.promptCount = promptCount
    }
}

public enum AIBlameEvolutionError: Error, Equatable, Sendable {
    case emptyLineSelection
    case missingDefaultProvider
    case noRevisionEvidence
    case emptyDiffChain
    case emptyModelResponse
    case invalidModelResponse(String)
}
```

创建 `AIBlameEvolutionExplainer.swift`：

```swift
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
        let evidence = try await collectEvidence(wc: wc, target: target, selectedLines: selectedLines, revisions: revisions)
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
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIBlameEvolutionExplainerTests
```

预期：主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift Sources/MacSvnCore/Services/AIBlameEvolutionExplainer.swift Tests/MacSvnCoreTests/AIBlameEvolutionExplainerTests.swift docs/superpowers/plans/2026-07-10-p6-ai-blame-evolution-core.md
git diff --cached --check
git commit -m "feat: add P6 AI blame evolution explainer core"
```

---

## 任务 2：错误路径

**文件：**
- 修改：`Sources/MacSvnCore/Services/AIBlameEvolutionExplainer.swift`
- 修改测试：`Tests/MacSvnCoreTests/AIBlameEvolutionExplainerTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AIBlameEvolutionExplainerTests` 增加：

```swift
func testThrowsForMissingInputsEmptyDiffsAndInvalidModelResponse() async throws {
    let provider = AIProvider(
        name: "Local",
        kind: .ollama,
        baseURL: "http://localhost:11434",
        model: "llama3",
        apiKeyRef: nil,
        maxTokens: 4096,
        temperature: 0.1
    )
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let selectedLine = BlameLine(lineNumber: 2, revision: Revision(10), author: "a", date: nil)
    let noRevisionLine = BlameLine(lineNumber: 2, revision: nil, author: nil, date: nil)

    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: []),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [:]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: []),
        wc: wc,
        lineRange: 2...2,
        blameLines: [selectedLine],
        expected: .missingDefaultProvider
    )
    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [:]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: []),
        wc: wc,
        lineRange: 4...5,
        blameLines: [selectedLine],
        expected: .emptyLineSelection
    )
    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [:]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: []),
        wc: wc,
        lineRange: 2...2,
        blameLines: [noRevisionLine],
        expected: .noRevisionEvidence
    )
    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(9), r2: Revision(10)): "   "
        ]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: []),
        wc: wc,
        lineRange: 2...2,
        blameLines: [selectedLine],
        expected: .emptyDiffChain
    )
    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(9), r2: Revision(10)): "+ change"
        ]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: [
            AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)
        ]),
        wc: wc,
        lineRange: 2...2,
        blameLines: [selectedLine],
        expected: .emptyModelResponse
    )
    try await assertExplainThrows(
        providerManager: FakeBlameEvolutionProviderManager(providers: [provider]),
        diffProvider: FakeBlameEvolutionDiffProvider(diffs: [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(9), r2: Revision(10)): "+ change"
        ]),
        logProvider: FakeBlameEvolutionLogProvider(entries: [:]),
        llmClient: FakeBlameEvolutionLLMClient(responses: [
            AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
        ]),
        wc: wc,
        lineRange: 2...2,
        blameLines: [selectedLine],
        expected: .invalidModelResponse("not json")
    )
}

private func assertExplainThrows(
    providerManager: FakeBlameEvolutionProviderManager,
    diffProvider: FakeBlameEvolutionDiffProvider,
    logProvider: FakeBlameEvolutionLogProvider,
    llmClient: FakeBlameEvolutionLLMClient,
    wc: URL,
    lineRange: ClosedRange<Int>,
    blameLines: [BlameLine],
    expected: AIBlameEvolutionError,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let explainer = AIBlameEvolutionExplainer(
        providerManager: providerManager,
        diffProvider: diffProvider,
        logProvider: logProvider,
        llmClient: llmClient
    )

    do {
        _ = try await explainer.explain(
            wc: wc,
            target: "Sources/Login.swift",
            lineRange: lineRange,
            blameLines: blameLines,
            privacySettings: AIPrivacySettings()
        )
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as AIBlameEvolutionError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected AIBlameEvolutionError, got \(error)", file: file, line: line)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIBlameEvolutionExplainerTests
```

预期：错误路径测试失败或编译失败。

- [x] **步骤 3：实现最少错误处理**

实现要求：
- provider 列表为空抛 `.missingDefaultProvider`；
- 选中行范围没有匹配 blame 行抛 `.emptyLineSelection`；
- 匹配行都没有 revision 抛 `.noRevisionEvidence`；
- 所有关联 revision diff 都为空白时抛 `.emptyDiffChain`；
- 空 LLM 响应抛 `.emptyModelResponse`；
- 非 JSON 或 schema 不匹配抛 `.invalidModelResponse(trimmed)`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIBlameEvolutionExplainerTests
```

预期：全部 `AIBlameEvolutionExplainerTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AIBlameEvolutionExplainer.swift Tests/MacSvnCoreTests/AIBlameEvolutionExplainerTests.swift docs/superpowers/plans/2026-07-10-p6-ai-blame-evolution-core.md
git diff --cached --check
git commit -m "test: cover P6 AI blame evolution errors"
```

---

## 任务 3：目标验证与计划收尾

- [ ] **步骤 1：运行 P6 Blame Evolution 目标集合**

```bash
swift test --filter "AIBlameEvolutionExplainerTests|BlameXMLParserTests|BlameViewModelTests|DiffViewModelTests|LogViewModelTests"
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
git add docs/superpowers/plans/2026-07-10-p6-ai-blame-evolution-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI blame evolution verification"
```
