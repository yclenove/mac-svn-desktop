# P6 AI LLM Keychain Clients Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 `FR-AI-00` / `NFR-11` 的真实接入 Core：API Key 可存入 macOS Keychain，OpenAI 兼容 / Anthropic / Ollama Provider 可通过真实 HTTP client 执行 `LLMChatting.chat`，并提供可复用的真实连通性测试器。

**架构：** 新增 Keychain 薄封装和 HTTP LLM client，测试中通过协议注入 fake keychain / fake transport，生产路径使用 `Security` 与 `URLSession`。现有 AI 功能继续依赖 `LLMChatting`，因此接入真实客户端不改变提交说明、评审、冲突辅助等业务层逻辑。

**技术栈：** Swift 6、Foundation URLSession、Security Keychain Services、Codable JSON、XCTest concurrency、现有 `AIProvider` / `LLMChatting` / `AIProviderConnectivityTesting`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/AIKeychainStore.swift`
  - 定义 `AIAPIKeyStoring`、`AIKeychainError`、`KeychainAccessing`、`SystemKeychainAccessor`、`AIKeychainStore`。
  - `AIKeychainStore.saveAPIKey(_:for:)` 返回稳定 `apiKeyRef`，Provider 配置只保存 ref，不保存明文。
- 创建：`Sources/MacSvnCore/Services/LLMHTTPClient.swift`
  - 定义 `AIHTTPTransport`、`AIHTTPRequest`、`AIHTTPResponse`、`URLSessionAIHTTPTransport`、`LLMClientError`、`LLMHTTPClient`。
  - 按 `AIProvider.kind` 拼装 OpenAI 兼容 / Anthropic / Ollama 请求并解析响应。
- 创建：`Sources/MacSvnCore/Services/AIProviderConnectivityTester.swift`
  - 定义 `AIProviderConnectivityTester`，通过 `LLMChatting` 发起 ping prompt，输出 `AIProviderConnectionTestResult`。
- 创建测试：
  - `Tests/MacSvnCoreTests/AIKeychainStoreTests.swift`
  - `Tests/MacSvnCoreTests/LLMHTTPClientTests.swift`
  - `Tests/MacSvnCoreTests/AIProviderConnectivityTesterTests.swift`
- 修改：`docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md`
  - 随任务完成勾选步骤并提交验证记录。

---

## 任务 1：Keychain API Key Store

**文件：**
- 创建：`Sources/MacSvnCore/Services/AIKeychainStore.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIKeychainStoreTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `AIKeychainStoreTests.swift`，先用 fake keychain 验证 ref 稳定、明文不出 ref、保存/读取/删除闭环：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIKeychainStoreTests: XCTestCase {
    func testSaveReadAndDeleteAPIKeyUsesStableReferenceWithoutLeakingSecret() async throws {
        let providerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let keychain = FakeKeychainAccessor()
        let store = AIKeychainStore(keychain: keychain)

        let ref = try await store.saveAPIKey("sk-secret-value", for: providerID)
        let loaded = try await store.apiKey(ref: ref)
        try await store.deleteAPIKey(ref: ref)
        let deleted = try await store.apiKey(ref: ref)

        XCTAssertEqual(ref, "macsvn.ai-provider.10000000-0000-0000-0000-000000000001")
        XCTAssertFalse(ref.contains("sk-secret-value"))
        XCTAssertEqual(loaded, "sk-secret-value")
        XCTAssertNil(deleted)
        XCTAssertEqual(keychain.savedAccounts, ["10000000-0000-0000-0000-000000000001"])
        XCTAssertEqual(keychain.deletedAccounts, ["10000000-0000-0000-0000-000000000001"])
    }

    func testRejectsInvalidKeyReference() async {
        let store = AIKeychainStore(keychain: FakeKeychainAccessor())

        do {
            _ = try await store.apiKey(ref: "plain-secret")
            XCTFail("Expected invalid ref")
        } catch let error as AIKeychainError {
            XCTAssertEqual(error, .invalidReference("plain-secret"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor FakeKeychainAccessor: KeychainAccessing {
    private var storage: [String: String] = [:]
    private(set) var savedAccounts: [String] = []
    private(set) var deletedAccounts: [String] = []

    func saveGenericPassword(service: String, account: String, password: String) throws {
        storage["\(service):\(account)"] = password
        savedAccounts.append(account)
    }

    func genericPassword(service: String, account: String) throws -> String? {
        storage["\(service):\(account)"]
    }

    func deleteGenericPassword(service: String, account: String) throws {
        storage.removeValue(forKey: "\(service):\(account)")
        deletedAccounts.append(account)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIKeychainStoreTests
```

预期：编译失败，提示 `AIKeychainStore` / `KeychainAccessing` / `AIKeychainError` 不存在。

- [x] **步骤 3：实现最少 Keychain Store**

创建 `AIKeychainStore.swift`，公共接口如下，`SystemKeychainAccessor` 按本步骤列出的规则补齐真实 `SecItem` 调用：

```swift
import Foundation
import Security

public protocol AIAPIKeyStoring: Sendable {
    func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String
    func apiKey(ref: String) async throws -> String?
    func deleteAPIKey(ref: String) async throws
}

public enum AIKeychainError: Error, Equatable, Sendable {
    case invalidReference(String)
    case unhandledStatus(Int32)
    case invalidPasswordData
}

public protocol KeychainAccessing: Sendable {
    func saveGenericPassword(service: String, account: String, password: String) throws
    func genericPassword(service: String, account: String) throws -> String?
    func deleteGenericPassword(service: String, account: String) throws
}

public struct SystemKeychainAccessor: KeychainAccessing, Sendable {
    public init() {}
    public func saveGenericPassword(service: String, account: String, password: String) throws
    public func genericPassword(service: String, account: String) throws -> String?
    public func deleteGenericPassword(service: String, account: String) throws
}

public actor AIKeychainStore: AIAPIKeyStoring {
    private static let refPrefix = "macsvn.ai-provider."
    private let service = "MacSVN.AIProvider"
    private let keychain: any KeychainAccessing

    public init(keychain: any KeychainAccessing = SystemKeychainAccessor()) {
        self.keychain = keychain
    }

    public func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String {
        let account = providerID.uuidString.lowercased()
        try keychain.saveGenericPassword(service: service, account: account, password: apiKey)
        return Self.refPrefix + account
    }

    public func apiKey(ref: String) async throws -> String? {
        let account = try account(from: ref)
        return try keychain.genericPassword(service: service, account: account)
    }

    public func deleteAPIKey(ref: String) async throws {
        let account = try account(from: ref)
        try keychain.deleteGenericPassword(service: service, account: account)
    }

    private func account(from ref: String) throws -> String {
        guard ref.hasPrefix(Self.refPrefix) else {
            throw AIKeychainError.invalidReference(ref)
        }
        let account = String(ref.dropFirst(Self.refPrefix.count))
        guard UUID(uuidString: account) != nil else {
            throw AIKeychainError.invalidReference(ref)
        }
        return account.lowercased()
    }
}
```

实现 `SystemKeychainAccessor` 时使用这些精确规则：
- `saveGenericPassword` 先 `SecItemAdd`，遇到 `errSecDuplicateItem` 后 `SecItemUpdate`。
- `genericPassword` 对 `errSecItemNotFound` 返回 `nil`，其他非 `errSecSuccess` 抛 `.unhandledStatus(status)`。
- 密码 Data 使用 UTF-8；解码失败抛 `.invalidPasswordData`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIKeychainStoreTests
```

预期：`AIKeychainStoreTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AIKeychainStore.swift Tests/MacSvnCoreTests/AIKeychainStoreTests.swift docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md
git diff --cached --check
git commit -m "feat: add P6 AI keychain API key store"
```

---

## 任务 2：HTTP LLM Client

**文件：**
- 创建：`Sources/MacSvnCore/Services/LLMHTTPClient.swift`
- 创建测试：`Tests/MacSvnCoreTests/LLMHTTPClientTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `LLMHTTPClientTests.swift`，覆盖三类 Provider 的请求路径、鉴权头和响应解析：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class LLMHTTPClientTests: XCTestCase {
    func testOpenAICompatibleRequestUsesChatCompletionsAndBearerToken() async throws {
        let provider = makeProvider(kind: .openAICompatible, baseURL: "https://api.example.com/v1", apiKeyRef: "key-ref")
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"choices":[{"message":{"content":"提交说明"}}],"usage":{"prompt_tokens":12,"completion_tokens":3}}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"]))

        let response = try await client.chat(provider: provider, messages: [.init(role: .user, content: "ping")])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"model\":\"gpt-test\""))
        XCTAssertEqual(response, AILLMResponse(content: "提交说明", promptTokens: 12, completionTokens: 3))
    }

    func testAnthropicRequestUsesMessagesEndpointAndAPIKeyHeader() async throws {
        let provider = makeProvider(kind: .anthropic, baseURL: "https://api.anthropic.com", apiKeyRef: "anthropic-ref")
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"content":[{"type":"text","text":"评审结果"}],"usage":{"input_tokens":8,"output_tokens":5}}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: ["anthropic-ref": "sk-ant"]))

        let response = try await client.chat(provider: provider, messages: [
            .init(role: .system, content: "system prompt"),
            .init(role: .user, content: "user prompt")
        ])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "sk-ant")
        XCTAssertEqual(request.headers["anthropic-version"], "2023-06-01")
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"system\":\"system prompt\""))
        XCTAssertEqual(response, AILLMResponse(content: "评审结果", promptTokens: 8, completionTokens: 5))
    }

    func testOllamaRequestDoesNotRequireAPIKeyAndParsesCounts() async throws {
        let provider = makeProvider(kind: .ollama, baseURL: "http://localhost:11434", apiKeyRef: nil)
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"message":{"role":"assistant","content":"本地结果"},"prompt_eval_count":4,"eval_count":7}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: [:]))

        let response = try await client.chat(provider: provider, messages: [.init(role: .user, content: "ping")])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"stream\":false"))
        XCTAssertEqual(response, AILLMResponse(content: "本地结果", promptTokens: 4, completionTokens: 7))
    }

    func testThrowsForMissingKeyBadURLHTTPErrorAndInvalidResponse() async throws {
        let keyedProvider = makeProvider(kind: .openAICompatible, baseURL: "https://api.example.com/v1", apiKeyRef: "missing")
        let missingKeyClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 200, data: Data())),
            apiKeyStore: FakeAPIKeyStore(keys: [:])
        )
        await XCTAssertThrowsAsyncError(try await missingKeyClient.chat(provider: keyedProvider, messages: [])) { error in
            XCTAssertEqual(error as? LLMClientError, .missingAPIKey("missing"))
        }

        let badURLProvider = makeProvider(kind: .ollama, baseURL: "not a url", apiKeyRef: nil)
        await XCTAssertThrowsAsyncError(try await missingKeyClient.chat(provider: badURLProvider, messages: [])) { error in
            XCTAssertEqual(error as? LLMClientError, .invalidBaseURL("not a url"))
        }

        let httpClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 429, data: Data("rate limited".utf8))),
            apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"])
        )
        await XCTAssertThrowsAsyncError(try await httpClient.chat(provider: keyedProvider, messages: [])) { error in
            XCTAssertEqual(error as? LLMClientError, .httpError(statusCode: 429, body: "rate limited"))
        }

        let invalidClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 200, data: Data("{}".utf8))),
            apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"])
        )
        await XCTAssertThrowsAsyncError(try await invalidClient.chat(provider: keyedProvider, messages: [])) { error in
            XCTAssertEqual(error as? LLMClientError, .invalidResponse("Missing assistant content."))
        }
    }

    private func makeProvider(kind: AIProviderKind, baseURL: String, apiKeyRef: String?) -> AIProvider {
        AIProvider(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            name: "Provider",
            kind: kind,
            baseURL: baseURL,
            model: "gpt-test",
            apiKeyRef: apiKeyRef,
            maxTokens: 512,
            temperature: 0.2
        )
    }
}
```

测试文件底部添加 fake：

```swift
private actor FakeAIHTTPTransport: AIHTTPTransport {
    private let response: AIHTTPResponse
    private var requests: [AIHTTPRequest] = []

    init(response: AIHTTPResponse) {
        self.response = response
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        requests.append(request)
        return response
    }

    func onlyRequest() throws -> AIHTTPRequest {
        guard requests.count == 1, let request = requests.first else {
            throw LLMClientError.invalidResponse("Expected exactly one request.")
        }
        return request
    }
}

private actor FakeAPIKeyStore: AIAPIKeyStoring {
    let keys: [String: String]
    init(keys: [String: String]) { self.keys = keys }
    func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String { "unused" }
    func apiKey(ref: String) async throws -> String? { keys[ref] }
    func deleteAPIKey(ref: String) async throws {}
}
```

`XCTAssertThrowsAsyncError` 辅助如项目中不存在，则在测试文件内定义：

```swift
private func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter LLMHTTPClientTests
```

预期：编译失败，提示 `LLMHTTPClient` / `AIHTTPTransport` / `AIHTTPRequest` / `AIHTTPResponse` / `LLMClientError` 不存在。

- [x] **步骤 3：实现最少 HTTP Client**

创建 `LLMHTTPClient.swift`，实现以下公开 API：

```swift
public struct AIHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data
}

public struct AIHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data
}

public protocol AIHTTPTransport: Sendable {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse
}

public struct URLSessionAIHTTPTransport: AIHTTPTransport, Sendable {
    public init() {}
    public func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse("Missing HTTPURLResponse.")
        }
        return AIHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

public enum LLMClientError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case missingAPIKey(String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)
}

public actor LLMHTTPClient: LLMChatting {
    public init(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport(),
        apiKeyStore: any AIAPIKeyStoring = AIKeychainStore()
    )
}
```

实现规则：
- endpoint 拼接使用 `URL.appendingPathComponent`，避免字符串手拼双斜杠。
- OpenAI 兼容 endpoint：`chat/completions`；Anthropic endpoint：`v1/messages`；Ollama endpoint：`api/chat`。
- 非 2xx 返回 `.httpError(statusCode:body:)`，body 用 UTF-8 lossy 解码。
- OpenAI usage 映射 `prompt_tokens` / `completion_tokens`。
- Anthropic usage 映射 `input_tokens` / `output_tokens`。
- Ollama usage 映射 `prompt_eval_count` / `eval_count`。
- assistant content 为空或缺失时抛 `.invalidResponse("Missing assistant content.")`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter LLMHTTPClientTests
```

预期：`LLMHTTPClientTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/LLMHTTPClient.swift Tests/MacSvnCoreTests/LLMHTTPClientTests.swift docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md
git diff --cached --check
git commit -m "feat: add P6 AI HTTP LLM client"
```

---

## 任务 3：真实连通性测试器

**文件：**
- 创建：`Sources/MacSvnCore/Services/AIProviderConnectivityTester.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIProviderConnectivityTesterTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `AIProviderConnectivityTesterTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIProviderConnectivityTesterTests: XCTestCase {
    func testConnectionTesterSendsPingAndMapsUsage() async throws {
        let provider = AIProvider(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            name: "Ollama",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "qwen",
            apiKeyRef: nil,
            maxTokens: 128,
            temperature: 0
        )
        let llm = FakePingLLM(response: AILLMResponse(content: "pong", promptTokens: 2, completionTokens: 1))
        let tester = AIProviderConnectivityTester(llmClient: llm, latencyMeasurer: { operation in
            (try await operation(), 42)
        })

        let result = try await tester.testConnection(provider: provider)

        let call = await llm.onlyCall()
        XCTAssertEqual(call.provider, provider)
        XCTAssertEqual(call.messages.last?.role, .user)
        XCTAssertTrue(call.messages.last?.content.contains("ping") == true)
        XCTAssertEqual(result, AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: 42,
            promptTokens: 2,
            completionTokens: 1
        ))
    }

    func testConnectionTesterRejectsEmptyPongAndMapsFailure() async {
        let provider = AIProvider(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            name: "Broken",
            kind: .openAICompatible,
            baseURL: "https://api.example.com/v1",
            model: "gpt",
            apiKeyRef: "key",
            maxTokens: 128,
            temperature: 0
        )
        let tester = AIProviderConnectivityTester(
            llmClient: FakePingLLM(response: AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)),
            latencyMeasurer: { operation in
                (try await operation(), 1)
            }
        )

        do {
            _ = try await tester.testConnection(provider: provider)
            XCTFail("Expected ping failure")
        } catch let error as AIProviderConnectivityError {
            XCTAssertEqual(error, .pingFailed("Empty ping response."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor FakePingLLM: LLMChatting {
    struct Call: Equatable {
        let provider: AIProvider
        let messages: [AILLMMessage]
    }

    private let response: AILLMResponse
    private var calls: [Call] = []

    init(response: AILLMResponse) {
        self.response = response
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(Call(provider: provider, messages: messages))
        return response
    }

    func onlyCall() -> Call {
        calls[0]
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIProviderConnectivityTesterTests
```

预期：编译失败，提示 `AIProviderConnectivityTester` 不存在。

- [x] **步骤 3：实现最少连通性测试器**

创建 `AIProviderConnectivityTester.swift`：

```swift
import Foundation

public struct AIProviderConnectivityTester: AIProviderConnectivityTesting, Sendable {
    public typealias LatencyMeasurer = @Sendable ((@Sendable () async throws -> AILLMResponse) async throws -> (AILLMResponse, Int))

    private let llmClient: any LLMChatting
    private let latencyMeasurer: LatencyMeasurer

    public init(
        llmClient: any LLMChatting = LLMHTTPClient(),
        latencyMeasurer: @escaping LatencyMeasurer = AIProviderConnectivityTester.defaultLatencyMeasurer
    ) {
        self.llmClient = llmClient
        self.latencyMeasurer = latencyMeasurer
    }

    public func testConnection(provider: AIProvider) async throws -> AIProviderConnectionTestResult {
        let messages = [
            AILLMMessage(role: .system, content: "You are a connection test endpoint. Reply with pong only."),
            AILLMMessage(role: .user, content: "ping")
        ]
        let (response, latency) = try await latencyMeasurer {
            try await llmClient.chat(provider: provider, messages: messages)
        }
        guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderConnectivityError.pingFailed("Empty ping response.")
        }
        return AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: latency,
            promptTokens: response.promptTokens ?? 0,
            completionTokens: response.completionTokens ?? 0
        )
    }

    private static func defaultLatencyMeasurer(
        operation: @Sendable () async throws -> AILLMResponse
    ) async throws -> (AILLMResponse, Int) {
        let start = ContinuousClock.now
        let response = try await operation()
        let duration = start.duration(to: ContinuousClock.now)
        let milliseconds = Int(Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        return (response, milliseconds)
    }
}
```

测试中的 `latencyMeasurer` 使用完整形式：`{ operation in (try await operation(), 42) }`，保证 ping 只发一次。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIProviderConnectivityTesterTests
```

预期：`AIProviderConnectivityTesterTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AIProviderConnectivityTester.swift Tests/MacSvnCoreTests/AIProviderConnectivityTesterTests.swift docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md
git diff --cached --check
git commit -m "feat: add P6 AI provider connectivity tester"
```

---

## 任务 4：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md`

- [x] **步骤 1：运行 P6 LLM Keychain 目标集合**

```bash
swift test --filter "AIKeychainStoreTests|LLMHTTPClientTests|AIProviderConnectivityTesterTests|AIProviderSettingsViewModelTests|AICommitMessageGeneratorTests|AIPreCommitReviewerTests|AIConflictAssistantTests|AIReleaseNotesGeneratorTests|AIBlameEvolutionExplainerTests"
```

预期：目标集合 PASS。

- [x] **步骤 2：运行全量验证**

```bash
swift test
```

预期：全部 XCTest PASS。

- [x] **步骤 3：运行空白检查**

```bash
git diff --check
```

预期：无输出、退出码 0。

- [x] **步骤 4：更新计划勾选并提交验证记录**

将本计划完成步骤勾选为 `[x]`，提交：

```bash
git add docs/superpowers/plans/2026-07-10-p6-ai-llm-keychain-clients-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI LLM keychain clients verification"
```

## 自检

- 覆盖 `FR-AI-00` 的真实 Core 接入缺口：Provider 配置中的 `apiKeyRef` 可对应 Keychain 密钥，OpenAI 兼容 / Anthropic / Ollama 都有真实 HTTP 请求适配。
- 覆盖 `NFR-11` 的基础安全要求：API Key 不进入 JSON 配置，Ollama 可无 key 运行，真实 AI 功能继续经既有脱敏管道发送 prompt。
- 保持故障隔离：HTTP/Keychain 错误通过 `LLMClientError` / `AIKeychainError` / `AIProviderConnectivityError` 返回，不影响基础 SVN 功能。
- 不实现 SwiftUI 设置页控件、真实用户账号配置迁移、SSE 流式输出、每日 token 计量落盘、AI Chat 面板或真实 tool loop；这些继续拆为 P6 UI/Agent 切片。
