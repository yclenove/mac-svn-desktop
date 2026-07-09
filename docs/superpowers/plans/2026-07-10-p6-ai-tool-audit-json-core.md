# P6 AI Tool Audit JSON Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 `FR-AI-04` / `NFR-13` 的本地审计日志 Core：AI SVN tool-calling 的审计记录可写入本地 JSON，按会话查询，并可导出 JSON 数据。

**架构：** 新增 `AIToolAuditStore` actor，继续实现现有 `AIToolAuditing` 协议，使用 `PersistenceStore` 原子读写 `AISVNToolAuditRecord` 列表。`AISVNToolRegistry` 不需要了解文件存储细节，只通过协议注入；新测试用 file-backed store 验证 registry 的 completed / confirmation / failed 记录能持久化。

**技术栈：** Swift 6、Foundation Codable、XCTest concurrency、现有 `AISVNToolRegistry` / `AIModels` / `PersistenceStore`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/AIToolAuditStore.swift`
  - 定义私有 `AIToolAuditLogFile` 和公开 `AIToolAuditStore` actor。
  - 提供 `append(_:)`、`records()`、`records(sessionID:)`、`exportJSON(sessionID:)`。
- 创建测试：`Tests/MacSvnCoreTests/AIToolAuditStoreTests.swift`
  - 覆盖持久化、重载、按 session 查询、JSON 导出。
  - 覆盖 `AISVNToolRegistry` 注入 file-backed store 后能持久化成功、确认和失败审计。
- 修改：`docs/superpowers/plans/2026-07-10-p6-ai-tool-audit-json-core.md`
  - 随任务完成勾选步骤并提交验证记录。

---

## 任务 1：文件型审计 Store

**文件：**
- 创建：`Sources/MacSvnCore/Services/AIToolAuditStore.swift`
- 创建测试：`Tests/MacSvnCoreTests/AIToolAuditStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `AIToolAuditStoreTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class AIToolAuditStoreTests: XCTestCase {
    func testAppendPersistsRecordsAndReloadsBySession() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sessionID: "session-a",
            toolName: "svn_status",
            outcome: .completed,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sessionID: "session-b",
            toolName: "svn_revert",
            risk: .highRiskWrite,
            outcome: .confirmationRequired,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let store = AIToolAuditStore(fileURL: fileURL)

        await store.append(first)
        await store.append(second)
        let reloaded = AIToolAuditStore(fileURL: fileURL)

        let allRecords = try await reloaded.records()
        let sessionARecords = try await reloaded.records(sessionID: "session-a")

        XCTAssertEqual(allRecords, [first, second])
        XCTAssertEqual(sessionARecords, [first])
    }

    func testExportJSONCanFilterBySession() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
        let first = makeRecord(sessionID: "session-a", toolName: "svn_status", outcome: .completed)
        let second = makeRecord(sessionID: "session-b", toolName: "svn_info", outcome: .completed)
        let store = AIToolAuditStore(fileURL: fileURL)
        await store.append(first)
        await store.append(second)

        let data = try await store.exportJSON(sessionID: "session-b")
        let exported = try JSONDecoder.auditDecoder.decode([AISVNToolAuditRecord].self, from: data)

        XCTAssertEqual(exported, [second])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("svn_info"))
    }

    private func makeRecord(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        sessionID: String,
        toolName: String,
        risk: AISVNToolRisk? = .readOnly,
        outcome: AISVNToolAuditOutcome,
        createdAt: Date = Date(timeIntervalSince1970: 30)
    ) -> AISVNToolAuditRecord {
        AISVNToolAuditRecord(
            id: id,
            sessionID: sessionID,
            toolName: toolName,
            risk: risk,
            arguments: ["wc": "/tmp/wc"],
            outcome: outcome,
            summary: "summary",
            createdAt: createdAt
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension JSONDecoder {
    static var auditDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIToolAuditStoreTests
```

预期：编译失败，提示 `AIToolAuditStore` 不存在。

- [ ] **步骤 3：实现最少 Store**

创建 `AIToolAuditStore.swift`：

```swift
import Foundation

private struct AIToolAuditLogFile: Codable, Sendable {
    var version: Int
    var records: [AISVNToolAuditRecord]

    init(version: Int = 1, records: [AISVNToolAuditRecord] = []) {
        self.version = version
        self.records = records
    }
}

public actor AIToolAuditStore: AIToolAuditing {
    private let store: PersistenceStore<AIToolAuditLogFile>
    private let exportEncoder: JSONEncoder

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: AIToolAuditLogFile())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.exportEncoder = encoder
    }

    public func append(_ record: AISVNToolAuditRecord) {
        do {
            var file = try store.load()
            file.records.append(record)
            try store.save(file)
        } catch {
            // Audit failures must not interrupt SVN tool execution; callers can inspect exported records.
        }
    }

    public func records() async throws -> [AISVNToolAuditRecord] {
        try store.load().records
    }

    public func records(sessionID: String) async throws -> [AISVNToolAuditRecord] {
        try store.load().records.filter { $0.sessionID == sessionID }
    }

    public func exportJSON(sessionID: String? = nil) async throws -> Data {
        let allRecords = try store.load().records
        let exported = sessionID.map { sessionID in
            allRecords.filter { $0.sessionID == sessionID }
        } ?? allRecords
        return try exportEncoder.encode(exported)
    }
}
```

- [ ] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIToolAuditStoreTests
```

预期：`AIToolAuditStoreTests` 2 个测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AIToolAuditStore.swift Tests/MacSvnCoreTests/AIToolAuditStoreTests.swift docs/superpowers/plans/2026-07-10-p6-ai-tool-audit-json-core.md
git diff --cached --check
git commit -m "feat: add P6 AI tool audit JSON store"
```

---

## 任务 2：Registry 持久化审计路径

**文件：**
- 修改测试：`Tests/MacSvnCoreTests/AIToolAuditStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `AIToolAuditStoreTests` 追加：

```swift
func testRegistryPersistsCompletedConfirmationAndFailedAuditRecords() async throws {
    let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
    let auditStore = AIToolAuditStore(fileURL: fileURL)
    let service = FakeAuditToolService(statusResult: [
        FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(7), isTreeConflict: false)
    ])
    let registry = AISVNToolRegistry(service: service, auditStore: auditStore)

    _ = try await registry.handle(
        AISVNToolCall(name: "svn_status", arguments: ["wc": "/tmp/wc"]),
        sessionID: "session-registry"
    )
    _ = try await registry.handle(
        AISVNToolCall(name: "svn_revert", arguments: ["wc": "/tmp/wc", "paths": "README.md"]),
        sessionID: "session-registry"
    )
    do {
        _ = try await registry.handle(
            AISVNToolCall(name: "shell_exec", arguments: ["command": "whoami"]),
            sessionID: "session-registry"
        )
        XCTFail("Expected forbidden tool")
    } catch let error as AISVNToolError {
        XCTAssertEqual(error, .forbiddenTool("shell_exec"))
    }

    let reloaded = AIToolAuditStore(fileURL: fileURL)
    let records = try await reloaded.records(sessionID: "session-registry")

    XCTAssertEqual(records.map(\.toolName), ["svn_status", "svn_revert", "shell_exec"])
    XCTAssertEqual(records.map(\.outcome), [.completed, .confirmationRequired, .failed])
    XCTAssertEqual(records.map(\.risk), [.readOnly, .highRiskWrite, nil])
}
```

在测试文件底部增加 fake service：

```swift
private actor FakeAuditToolService: AISVNToolServicing {
    var statusResult: [FileStatus]

    init(statusResult: [FileStatus] = []) {
        self.statusResult = statusResult
    }

    func status(wc: URL) async throws -> [FileStatus] { statusResult }
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String { "" }
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] { [] }
    func info(wc: URL, target: String) async throws -> SvnInfo {
        SvnInfo(path: target, url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    }
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] { [] }
    func blame(wc: URL, target: String) async throws -> [BlameLine] { [] }
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data { Data() }
}
```

- [ ] **步骤 2：运行测试验证失败**

```bash
swift test --filter AIToolAuditStoreTests/testRegistryPersistsCompletedConfirmationAndFailedAuditRecords
```

预期：若任务 1 已实现，测试应通过；如果 store 没有正确持久化 registry 写入，则 FAIL。

- [ ] **步骤 3：实现最少接入修正**

通常无需修改生产代码，因为 `AIToolAuditStore` 已符合 `AIToolAuditing`。如果测试失败，只修正 `AIToolAuditStore.append(_:)` 的读写流程，不修改 `AISVNToolRegistry` 的安全分级行为。

- [ ] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AIToolAuditStoreTests
swift test --filter AISVNToolRegistryTests
```

预期：JSON store 与原 registry 测试均 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Tests/MacSvnCoreTests/AIToolAuditStoreTests.swift docs/superpowers/plans/2026-07-10-p6-ai-tool-audit-json-core.md
git diff --cached --check
git commit -m "test: cover P6 AI tool audit registry persistence"
```

---

## 任务 3：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p6-ai-tool-audit-json-core.md`

- [ ] **步骤 1：运行 P6 AI 审计目标集合**

```bash
swift test --filter "AIToolAuditStoreTests|AISVNToolRegistryTests"
```

预期：目标集合 PASS。

- [ ] **步骤 2：运行全量验证**

```bash
swift test
```

预期：全部 XCTest PASS。

- [ ] **步骤 3：运行空白检查**

```bash
git diff --check
```

预期：无输出、退出码 0。

- [ ] **步骤 4：更新计划勾选并提交验证记录**

将本计划完成步骤勾选为 `[x]`，提交：

```bash
git add docs/superpowers/plans/2026-07-10-p6-ai-tool-audit-json-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI tool audit JSON verification"
```

## 自检

- 覆盖 `FR-AI-04` / `NFR-13` 的后续 Core：所有 `AISVNToolRegistry` 工具调用记录可以落到本地 JSON，并可按 session 导出。
- 保持故障隔离：审计写入仍不改变 tool registry 的只读执行/写操作确认门行为。
- 不实现 SwiftUI Chat 面板、审计查看器 UI、真实 LLM tool loop、确认后写操作执行或审计文件选择器；这些继续拆为后续 P6 UI/Agent 切片。
