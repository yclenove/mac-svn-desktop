# P6 AI Provider Config Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 P6 `FR-AI-00` 建立多 Provider 配置 Core：保存 OpenAI 兼容 / Anthropic / Ollama 配置、默认 Provider、API Key 引用、token/每日调用限制，并提供可注入的连通性测试状态层。

**架构：** 在 `AIModels.swift` 中扩展 `AIProvider`、`AIProviderKind`、`AIProviderConfigurationFile`、`AIProviderError` 与连通性测试结果模型。新增 `AIProviderStore` actor 复用 `PersistenceStore` 持久化 provider 列表，只保存 `apiKeyRef`，不保存明文 key。新增 `AIProviderSettingsViewModel` 作为设置页绑定底座，通过 `AIProviderManaging` 与 `AIProviderConnectivityTesting` 协议加载、保存、设默认、删除和测试连接。

**技术栈：** Swift Package、Foundation Codable、Observation、XCTest concurrency、TDD。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  扩展 AI Provider 配置、错误和连通性结果模型。
- 创建：`Sources/MacSvnCore/Services/AIProviderStore.swift`
  持久化 Provider 配置，负责 trim、唯一 ID upsert、默认 Provider 维护和限额校验。
- 创建：`Sources/MacSvnCore/ViewModels/AIProviderSettingsViewModel.swift`
  设置页状态层，依赖协议而非真实网络/Keychain。
- 创建测试：`Tests/MacSvnCoreTests/AIProviderStoreTests.swift`
  覆盖默认空列表、保存重载、默认 Provider、删除默认回退、非法配置。
- 创建测试：`Tests/MacSvnCoreTests/AIProviderSettingsViewModelTests.swift`
  覆盖加载、保存、删除、设默认、连接测试成功/失败状态。

## 任务 1：Provider 模型与持久化 Store

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIProviderStore.swift`
- 测试：`Tests/MacSvnCoreTests/AIProviderStoreTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AIProviderStoreTests` 新增：

```swift
func testLoadMissingFileReturnsEmptyProviders() async throws {
    let store = makeStore()

    let providers = try await store.loadProviders()

    XCTAssertEqual(providers, [])
    XCTAssertNil(await store.defaultProviderID())
}

func testSaveProviderPersistsApiKeyReferenceWithoutSecretValue() async throws {
    let root = temporaryRoot()
    let store = makeStore(root: root)
    let provider = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: " DeepSeek ",
        kind: .openAICompatible,
        baseURL: " https://api.deepseek.com/v1 ",
        model: " deepseek-chat ",
        apiKeyRef: " keychain://deepseek ",
        maxTokens: 32_000,
        temperature: 0.2,
        dailyRequestLimit: 100
    )

    let saved = try await store.saveProvider(provider, makeDefault: true)

    XCTAssertEqual(saved.name, "DeepSeek")
    XCTAssertEqual(saved.baseURL, "https://api.deepseek.com/v1")
    XCTAssertEqual(saved.model, "deepseek-chat")
    XCTAssertEqual(saved.apiKeyRef, "keychain://deepseek")
    XCTAssertEqual(saved.dailyRequestLimit, 100)
    XCTAssertEqual(await store.defaultProviderID(), saved.id)

    let data = try Data(contentsOf: root.appendingPathComponent("ai-providers.json"))
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("keychain://deepseek"))
    XCTAssertFalse(json.contains("sk-secret"))

    let reloaded = try await makeStore(root: root).loadProviders()
    XCTAssertEqual(reloaded, [saved])
}

func testSaveProviderRejectsInvalidLimitsAndMissingRequiredFields() async throws {
    let store = makeStore()

    try await assertSaveThrows(
        AIProvider(name: " ", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", apiKeyRef: "key", maxTokens: 1, temperature: 0.5),
        expected: .emptyName,
        store: store
    )
    try await assertSaveThrows(
        AIProvider(name: "Claude", kind: .anthropic, baseURL: " ", model: "claude", apiKeyRef: "key", maxTokens: 1, temperature: 0.5),
        expected: .emptyBaseURL,
        store: store
    )
    try await assertSaveThrows(
        AIProvider(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", model: " ", apiKeyRef: "key", maxTokens: 1, temperature: 0.5),
        expected: .emptyModel,
        store: store
    )
    try await assertSaveThrows(
        AIProvider(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", apiKeyRef: "key", maxTokens: 0, temperature: 0.5),
        expected: .invalidMaxTokens(0),
        store: store
    )
    try await assertSaveThrows(
        AIProvider(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", apiKeyRef: "key", maxTokens: 1, temperature: 3),
        expected: .invalidTemperature(3),
        store: store
    )
    try await assertSaveThrows(
        AIProvider(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", apiKeyRef: "key", maxTokens: 1, temperature: 0.5, dailyRequestLimit: 0),
        expected: .invalidDailyRequestLimit(0),
        store: store
    )
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIProviderStoreTests
```

预期：编译失败，提示 `AIProvider` / `AIProviderStore` / `AIProviderError` 未定义。

- [x] **步骤 3：实现最少代码**

在 `AIModels.swift` 增加：

```swift
public enum AIProviderKind: String, Codable, Equatable, Sendable {
    case openAICompatible
    case anthropic
    case ollama
}

public struct AIProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var model: String
    public var apiKeyRef: String?
    public var maxTokens: Int
    public var temperature: Double
    public var dailyRequestLimit: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        model: String,
        apiKeyRef: String?,
        maxTokens: Int,
        temperature: Double,
        dailyRequestLimit: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKeyRef = apiKeyRef
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.dailyRequestLimit = dailyRequestLimit
    }
}

public struct AIProviderConfigurationFile: Codable, Equatable, Sendable {
    public var version: Int
    public var providers: [AIProvider]
    public var defaultProviderID: UUID?
}

public enum AIProviderError: Error, Equatable, Sendable {
    case emptyName
    case emptyBaseURL
    case emptyModel
    case invalidMaxTokens(Int)
    case invalidTemperature(Double)
    case invalidDailyRequestLimit(Int)
    case providerNotFound(UUID)
}
```

创建 `AIProviderStore`：

```swift
public protocol AIProviderManaging: Sendable {
    func loadProviders() async throws -> [AIProvider]
    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider
    func deleteProvider(id: UUID) async throws
    func setDefaultProvider(id: UUID) async throws -> AIProvider
    func defaultProviderID() async -> UUID?
}
```

实现 actor 时：
- `loadProviders()` 读取 `AIProviderConfigurationFile` 并缓存 `providers/defaultProviderID`；
- `saveProvider` trim `name/baseURL/model/apiKeyRef`，校验 `maxTokens > 0`、`0...2` 温度、`dailyRequestLimit > 0`；
- 相同 `id` 更新，否则 append；
- `makeDefault == true` 或之前没有默认 provider 时设置默认；
- `deleteProvider` 删除后如果默认被删，则设置为剩余第一个 provider 的 id 或 nil；
- 绝不接收或保存明文 API key，只保存 `apiKeyRef` 字符串。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIProviderStoreTests
```

预期：新增 store 测试 PASS。

## 任务 2：Provider 设置 ViewModel 与连通性测试接口

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/ViewModels/AIProviderSettingsViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/AIProviderSettingsViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AIProviderSettingsViewModelTests` 新增：

```swift
@MainActor
func testLoadSaveDefaultDeleteAndConnectionTestUpdateState() async {
    let provider = AIProvider(name: "Local", kind: .ollama, baseURL: "http://localhost:11434", model: "llama3", apiKeyRef: nil, maxTokens: 4096, temperature: 0.1)
    let testResult = AIProviderConnectionTestResult(providerID: provider.id, latencyMilliseconds: 42, promptTokens: 3, completionTokens: 2)
    let manager = FakeAIProviderManager(providers: [provider], savedProvider: provider, defaultProvider: provider)
    let tester = FakeAIProviderConnectivityTester(result: .success(testResult))
    let viewModel = AIProviderSettingsViewModel(manager: manager, connectivityTester: tester)

    await viewModel.loadProviders()
    XCTAssertEqual(viewModel.providers, [provider])

    await viewModel.saveProvider(provider, makeDefault: true)
    XCTAssertEqual(viewModel.providers, [provider])

    await viewModel.setDefaultProvider(provider.id)
    XCTAssertEqual(viewModel.defaultProviderID, provider.id)

    await viewModel.testConnection(provider)
    XCTAssertEqual(viewModel.connectionTestResult, testResult)
    XCTAssertEqual(viewModel.state, .idle)

    await viewModel.deleteProvider(provider.id)
    XCTAssertEqual(viewModel.providers, [])
}

@MainActor
func testProviderFailureStoresError() async {
    let manager = FakeAIProviderManager(error: AIProviderError.emptyName)
    let viewModel = AIProviderSettingsViewModel(manager: manager, connectivityTester: FakeAIProviderConnectivityTester())

    await viewModel.loadProviders()

    XCTAssertEqual(viewModel.state, .error(String(describing: AIProviderError.emptyName)))
}

@MainActor
func testConnectionFailureStoresErrorAndClearsPreviousResult() async {
    let provider = AIProvider(name: "Claude", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude", apiKeyRef: "key", maxTokens: 4096, temperature: 0.5)
    let viewModel = AIProviderSettingsViewModel(
        manager: FakeAIProviderManager(providers: [provider]),
        connectivityTester: FakeAIProviderConnectivityTester(result: .failure(AIProviderConnectivityError.pingFailed("offline")))
    )

    await viewModel.loadProviders()
    await viewModel.testConnection(provider)

    XCTAssertNil(viewModel.connectionTestResult)
    XCTAssertEqual(viewModel.state, .error(String(describing: AIProviderConnectivityError.pingFailed("offline"))))
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIProviderSettingsViewModelTests
```

预期：编译失败，提示 `AIProviderSettingsViewModel` / `AIProviderConnectionTestResult` / `AIProviderConnectivityTesting` 未定义。

- [x] **步骤 3：实现最少代码**

在 `AIModels.swift` 增加：

```swift
public struct AIProviderConnectionTestResult: Equatable, Sendable {
    public let providerID: UUID
    public let latencyMilliseconds: Int
    public let promptTokens: Int
    public let completionTokens: Int
}

public enum AIProviderConnectivityError: Error, Equatable, Sendable {
    case pingFailed(String)
}
```

创建 ViewModel：

```swift
public protocol AIProviderConnectivityTesting: Sendable {
    func testConnection(provider: AIProvider) async throws -> AIProviderConnectionTestResult
}

public enum AIProviderSettingsState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case testing
    case error(String)
}
```

`AIProviderSettingsViewModel` 使用 `@MainActor @Observable`：
- `providers`、`defaultProviderID`、`connectionTestResult`、`state`；
- `loadProviders()` 调 manager 并读取默认 id；
- `saveProvider(_:makeDefault:)` 成功后 upsert；
- `deleteProvider(_:)` 成功后移除本地记录并刷新默认 id；
- `setDefaultProvider(_:)` 成功后更新默认 id；
- `testConnection(_:)` 成功写 result，失败清空 result 并写 error。

扩展 `AIProviderStore: AIProviderManaging`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter "AIProviderStoreTests|AIProviderSettingsViewModelTests"
```

预期：Provider store 与 ViewModel 测试全部 PASS。

## 任务 3：全量验证与提交

- [x] **步骤 1：运行 P6 AI 目标集合**

```bash
swift test --filter "AIDataRedactorTests|AIProviderStoreTests|AIProviderSettingsViewModelTests"
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
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AIProviderStore.swift \
  Sources/MacSvnCore/ViewModels/AIProviderSettingsViewModel.swift \
  Tests/MacSvnCoreTests/AIProviderStoreTests.swift \
  Tests/MacSvnCoreTests/AIProviderSettingsViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-provider-config-core.md
git diff --cached --check
git commit -m "feat: add P6 AI provider config core"
```

## 自检

- 覆盖 `FR-AI-00` 的 Core 配置底座：多 Provider 类型、模型参数、默认 Provider、API Key 引用、token 上限、每日调用上限与连通性测试状态。
- 覆盖 `NFR-11` 的本地模型选项配置入口：`AIProviderKind.ollama` 可保存为无需 key 的 Provider。
- 不覆盖真实 Keychain 读写、真实 OpenAI/Anthropic/Ollama 网络请求、SSE 流式输出、真实 token 计费统计、设置页 UI；这些继续拆为后续 P6 切片。
