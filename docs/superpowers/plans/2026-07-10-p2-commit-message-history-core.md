# P2 Commit Message History Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 `FR-CM-03` 的 Core 支撑：按工作副本保存最近 10 条提交说明，提交对话框可加载并复用历史说明。

**架构：** 新增 `CommitMessageHistoryStore` actor，基于现有 `PersistenceStore` 持久化 JSON，按 working copy key 分组保存、去重、最近优先和最多 10 条。扩展 `CommitViewModel` 通过可注入 provider 加载历史、复用说明，并在提交成功后保存当前提交说明。

**技术栈：** Swift 6、Foundation、Observation、XCTest、现有 `PersistenceStore` / `CommitViewModel`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/CommitMessageHistoryStore.swift`
  - 增加 `CommitMessageHistoryProviding` 协议、`CommitMessageHistoryStore` actor、持久化文件模型和错误类型。
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
  - 注入可选 history provider，暴露 `recentMessages` / `messageHistoryState`，提供 `loadRecentMessages()` 与 `reuseRecentMessage(_:)`，提交成功后保存说明并刷新最近列表。
- 创建测试：`Tests/MacSvnCoreTests/CommitMessageHistoryStoreTests.swift`
  - 覆盖按 WC 分组、最近优先、去重、上限 10、空白说明拒绝。
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`
  - 覆盖加载历史、复用历史、提交成功保存历史、保存失败不影响提交成功。

---

## 任务 1：提交说明历史 Store

**文件：**
- 创建：`Sources/MacSvnCore/Services/CommitMessageHistoryStore.swift`
- 创建测试：`Tests/MacSvnCoreTests/CommitMessageHistoryStoreTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `CommitMessageHistoryStoreTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class CommitMessageHistoryStoreTests: XCTestCase {
    func testRecordMessageStoresRecentUniqueMessagesPerWorkingCopyWithLimitTen() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("commit-history.json")
        let store = CommitMessageHistoryStore(fileURL: fileURL)
        let wcA = URL(fileURLWithPath: "/tmp/project-a")
        let wcB = URL(fileURLWithPath: "/tmp/project-b")

        for index in 1...11 {
            try await store.record(message: "message \(index)", workingCopy: wcA)
        }
        try await store.record(message: "message 8", workingCopy: wcA)
        try await store.record(message: "other", workingCopy: wcB)

        let messagesA = try await store.recentMessages(workingCopy: wcA)
        let messagesB = try await store.recentMessages(workingCopy: wcB)

        XCTAssertEqual(messagesA, [
            "message 8",
            "message 11",
            "message 10",
            "message 9",
            "message 7",
            "message 6",
            "message 5",
            "message 4",
            "message 3",
            "message 2"
        ])
        XCTAssertEqual(messagesB, ["other"])
    }

    func testRecordRejectsBlankMessagesAndPersistsToDisk() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("commit-history.json")
        let store = CommitMessageHistoryStore(fileURL: fileURL)
        let wc = URL(fileURLWithPath: "/tmp/project")

        try await store.record(message: "  修复登录  \n", workingCopy: wc)
        do {
            try await store.record(message: "   ", workingCopy: wc)
            XCTFail("Expected blank message rejection")
        } catch let error as CommitMessageHistoryStoreError {
            XCTAssertEqual(error, .emptyMessage)
        }

        let reloaded = CommitMessageHistoryStore(fileURL: fileURL)
        let messages = try await reloaded.recentMessages(workingCopy: wc)

        XCTAssertEqual(messages, ["修复登录"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommitMessageHistoryStoreTests
```

预期：编译失败，提示 `CommitMessageHistoryStore` 或 `CommitMessageHistoryStoreError` 不存在。

- [x] **步骤 3：实现最少 Store**

创建 `CommitMessageHistoryStore.swift`：

```swift
import Foundation

public enum CommitMessageHistoryStoreError: Error, Equatable, Sendable {
    case emptyMessage
}

public protocol CommitMessageHistoryProviding: Sendable {
    func recentMessages(workingCopy: URL) async throws -> [String]
    func record(message: String, workingCopy: URL) async throws
}

private struct CommitMessageHistoryFile: Codable {
    var histories: [String: [String]]

    init(histories: [String: [String]] = [:]) {
        self.histories = histories
    }
}

public actor CommitMessageHistoryStore: CommitMessageHistoryProviding {
    private let store: PersistenceStore<CommitMessageHistoryFile>
    private let limit: Int

    public init(fileURL: URL, limit: Int = 10) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: CommitMessageHistoryFile())
        self.limit = max(1, limit)
    }

    public func recentMessages(workingCopy: URL) async throws -> [String] {
        let file = try store.load()
        return file.histories[Self.key(for: workingCopy)] ?? []
    }

    public func record(message: String, workingCopy: URL) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommitMessageHistoryStoreError.emptyMessage
        }

        var file = try store.load()
        let key = Self.key(for: workingCopy)
        var messages = file.histories[key] ?? []
        messages.removeAll { $0 == trimmed }
        messages.insert(trimmed, at: 0)
        if messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
        file.histories[key] = messages
        try store.save(file)
    }

    private static func key(for workingCopy: URL) -> String {
        workingCopy.standardizedFileURL.path
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter CommitMessageHistoryStoreTests
```

预期：Store 目标测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/CommitMessageHistoryStore.swift Tests/MacSvnCoreTests/CommitMessageHistoryStoreTests.swift docs/superpowers/plans/2026-07-10-p2-commit-message-history-core.md
git commit -m "feat: add P2 commit message history store"
```

---

## 任务 2：CommitViewModel 历史加载、复用与提交成功保存

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 修改测试：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `CommitViewModelTests` 中追加测试：

```swift
@MainActor
func testLoadAndReuseRecentCommitMessages() async {
    let historyProvider = FakeCommitMessageHistoryProvider(
        recentMessagesResult: .success(["修复登录", "调整支付"])
    )
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([])),
        commitMessageHistoryProvider: historyProvider
    )

    await viewModel.loadRecentMessages()
    viewModel.reuseRecentMessage("调整支付")

    XCTAssertEqual(viewModel.messageHistoryState, .loaded)
    XCTAssertEqual(viewModel.recentMessages, ["修复登录", "调整支付"])
    XCTAssertEqual(viewModel.message, "调整支付")
}

@MainActor
func testCommitSuccessRecordsMessageHistoryAndRefreshesRecentMessages() async {
    let historyProvider = FakeCommitMessageHistoryProvider(
        recentMessagesResults: [
            .success([]),
            .success(["修复：登录超时"])
        ]
    )
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([])),
        commitMessageHistoryProvider: historyProvider
    )
    viewModel.message = " 修复：登录超时 "

    await viewModel.commit(auth: nil)
    let recorded = await historyProvider.recordedMessages()

    XCTAssertEqual(viewModel.state, .committed(Revision(42)))
    XCTAssertEqual(recorded, [CommitMessageHistoryRecord(wc: URL(fileURLWithPath: "/tmp/wc"), message: " 修复：登录超时 ")])
    XCTAssertEqual(viewModel.recentMessages, ["修复：登录超时"])
    XCTAssertEqual(viewModel.messageHistoryState, .loaded)
}

@MainActor
func testCommitHistoryFailureDoesNotOverrideCommittedState() async {
    let historyProvider = FakeCommitMessageHistoryProvider(
        recentMessagesResult: .failure(SvnError.parse(detail: "bad history")),
        recordResult: .failure(SvnError.parse(detail: "disk full"))
    )
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: FakeCommitProvider(result: .success(Revision(42))),
        statusProvider: FakeStatusProvider(result: .success([])),
        commitMessageHistoryProvider: historyProvider
    )
    viewModel.message = "fix"

    await viewModel.commit(auth: nil)

    XCTAssertEqual(viewModel.state, .committed(Revision(42)))
    XCTAssertEqual(viewModel.messageHistoryState, .error(String(describing: SvnError.parse(detail: "disk full"))))
}
```

在测试文件底部增加 fake：

```swift
private struct CommitMessageHistoryRecord: Equatable, Sendable {
    let wc: URL
    let message: String
}

private actor FakeCommitMessageHistoryProvider: CommitMessageHistoryProviding {
    private var recentMessagesResults: [Result<[String], Error>]
    private let recordResult: Result<Void, Error>
    private var records: [CommitMessageHistoryRecord] = []

    init(
        recentMessagesResult: Result<[String], Error> = .success([]),
        recordResult: Result<Void, Error> = .success(())
    ) {
        self.recentMessagesResults = [recentMessagesResult]
        self.recordResult = recordResult
    }

    init(
        recentMessagesResults: [Result<[String], Error>],
        recordResult: Result<Void, Error> = .success(())
    ) {
        self.recentMessagesResults = recentMessagesResults
        self.recordResult = recordResult
    }

    func recordedMessages() -> [CommitMessageHistoryRecord] {
        records
    }

    func recentMessages(workingCopy: URL) async throws -> [String] {
        if recentMessagesResults.count > 1 {
            return try recentMessagesResults.removeFirst().get()
        }
        return try (recentMessagesResults.first ?? .success([])).get()
    }

    func record(message: String, workingCopy: URL) async throws {
        records.append(CommitMessageHistoryRecord(wc: workingCopy, message: message))
        try recordResult.get()
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommitViewModelTests/testLoadAndReuseRecentCommitMessages
swift test --filter CommitViewModelTests/testCommitSuccessRecordsMessageHistoryAndRefreshesRecentMessages
swift test --filter CommitViewModelTests/testCommitHistoryFailureDoesNotOverrideCommittedState
```

预期：编译失败，提示 `commitMessageHistoryProvider` 参数、`messageHistoryState`、`recentMessages` 或方法不存在。

- [x] **步骤 3：实现 ViewModel 接入**

在 `CommitViewModel.swift` 中增加：

```swift
public enum CommitMessageHistoryViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}
```

给 `CommitViewModel` 新增属性：

```swift
private let commitMessageHistoryProvider: (any CommitMessageHistoryProviding)?
public private(set) var messageHistoryState: CommitMessageHistoryViewState = .idle
public private(set) var recentMessages: [String] = []
```

扩展 initializer 参数：

```swift
commitMessageHistoryProvider: (any CommitMessageHistoryProviding)? = nil
```

新增方法：

```swift
public func loadRecentMessages() async {
    guard let commitMessageHistoryProvider else {
        recentMessages = []
        messageHistoryState = .loaded
        return
    }

    messageHistoryState = .loading
    do {
        recentMessages = try await commitMessageHistoryProvider.recentMessages(workingCopy: workingCopy)
        messageHistoryState = .loaded
    } catch {
        recentMessages = []
        messageHistoryState = .error(String(describing: error))
    }
}

public func reuseRecentMessage(_ recentMessage: String) {
    message = recentMessage
}
```

在 commit 成功后、刷新状态后记录历史：

```swift
await recordSuccessfulMessage(message)
```

新增私有方法：

```swift
private func recordSuccessfulMessage(_ message: String) async {
    guard let commitMessageHistoryProvider else {
        return
    }

    do {
        try await commitMessageHistoryProvider.record(message: message, workingCopy: workingCopy)
        recentMessages = try await commitMessageHistoryProvider.recentMessages(workingCopy: workingCopy)
        messageHistoryState = .loaded
    } catch {
        messageHistoryState = .error(String(describing: error))
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter CommitMessageHistoryStoreTests
swift test --filter CommitViewModelTests
```

预期：提交历史 store 和 CommitViewModel 目标测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CommitViewModel.swift Tests/MacSvnCoreTests/CommitViewModelTests.swift docs/superpowers/plans/2026-07-10-p2-commit-message-history-core.md
git commit -m "feat: connect P2 commit message history to commit view model"
```

---

## 任务 3：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p2-commit-message-history-core.md`

- [x] **步骤 1：运行 FR-CM-03 目标集合**

```bash
swift test --filter CommitMessageHistoryStoreTests
swift test --filter CommitViewModelTests
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
git add docs/superpowers/plans/2026-07-10-p2-commit-message-history-core.md
git commit -m "docs: complete P2 commit message history verification"
```

## 自检

- 覆盖 `FR-CM-03` 的 Core 支撑：最近 10 条本地提交说明、按 WC 分组、可快速复用。
- 复用 `PersistenceStore`，不引入数据库。
- 保存历史发生在提交成功之后；保存失败不推翻已提交状态，避免辅助功能影响核心提交路径。
