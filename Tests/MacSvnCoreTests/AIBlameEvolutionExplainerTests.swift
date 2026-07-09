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

        let diffCalls = await diffProvider.recordedCalls()
        let logCalls = await logProvider.recordedCalls()
        XCTAssertEqual(diffCalls, [
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1199), r2: Revision(1200)),
            DiffCall(wc: wc, target: "Sources/Login.swift", r1: Revision(1200), r2: Revision(1201))
        ])
        XCTAssertEqual(logCalls, [
            LogCall(wc: wc, target: "Sources/Login.swift", from: Revision(1200), batch: 1, verbose: true),
            LogCall(wc: wc, target: "Sources/Login.swift", from: Revision(1201), batch: 1, verbose: true)
        ])
    }

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
