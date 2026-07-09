# P6 AI SVN Agent Tool Registry Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-AI-04` 建立自然语言 SVN Agent 的安全工具注册表 Core：只读工具自动执行，写工具只生成确认请求，所有工具调用写入审计记录。

**架构：** 新增 `AISVNToolRegistry`，接收 LLM tool-call 风格的 `AISVNToolCall(name, arguments)`，按 `AISVNToolName` 分级。只读工具通过可注入 `AISVNToolServicing` 调用既有 `SvnService` 查询方法；低危/高危写工具不执行 SVN，只返回 `AISVNToolConfirmation`。审计通过 `AIToolAuditing` 协议写入，首个实现为 `InMemoryAIToolAuditStore`，本地 JSON store 另行拆分。

**技术栈：** Swift 6、Foundation、XCTest、现有 `SvnService` / `SvnBackend` / `SvnModels`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
  - 增加 `AISVNToolRisk`、`AISVNToolName`、`AISVNToolCall`、`AISVNToolResult`、`AISVNToolConfirmation`、`AISVNToolDecision`、`AISVNToolAuditRecord`、`AISVNToolError`。
- 创建：`Sources/MacSvnCore/Services/AISVNToolRegistry.swift`
  - 增加 `AISVNToolServicing`、`AIToolAuditing`、`InMemoryAIToolAuditStore`、`AISVNToolRegistry`，并让 `SvnService` 符合 `AISVNToolServicing`。
- 创建：`Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift`
  - 覆盖工具分级、只读自动执行、写工具确认门、未知工具禁止与审计。

---

## 任务 1：模型与工具分级

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建测试：`Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AISVNToolRegistryTests` 增加：

```swift
func testToolNamesClassifyReadOnlyLowRiskAndHighRiskTools() {
    XCTAssertEqual(AISVNToolName.svnStatus.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnLog.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnDiff.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnInfo.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnList.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnBlame.risk, .readOnly)
    XCTAssertEqual(AISVNToolName.svnCat.risk, .readOnly)

    XCTAssertEqual(AISVNToolName.svnUpdate.risk, .lowRiskWrite)
    XCTAssertEqual(AISVNToolName.svnAdd.risk, .lowRiskWrite)
    XCTAssertEqual(AISVNToolName.svnCleanup.risk, .lowRiskWrite)

    XCTAssertEqual(AISVNToolName.svnCommit.risk, .highRiskWrite)
    XCTAssertEqual(AISVNToolName.svnRevert.risk, .highRiskWrite)
    XCTAssertEqual(AISVNToolName.svnMerge.risk, .highRiskWrite)
    XCTAssertEqual(AISVNToolName.svnSwitch.risk, .highRiskWrite)
    XCTAssertEqual(AISVNToolName.svnDelete.risk, .highRiskWrite)
    XCTAssertEqual(AISVNToolName.svnCopy.risk, .highRiskWrite)
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：编译失败，提示 `AISVNToolName` 或 `AISVNToolRisk` 不存在。

- [x] **步骤 3：实现最少模型代码**

在 `AIModels.swift` 增加：

```swift
public enum AISVNToolRisk: String, Codable, Equatable, Sendable {
    case readOnly
    case lowRiskWrite
    case highRiskWrite
}

public enum AISVNToolName: String, Codable, CaseIterable, Equatable, Sendable {
    case svnStatus = "svn_status"
    case svnLog = "svn_log"
    case svnDiff = "svn_diff"
    case svnInfo = "svn_info"
    case svnList = "svn_list"
    case svnBlame = "svn_blame"
    case svnCat = "svn_cat"
    case svnUpdate = "svn_update"
    case svnAdd = "svn_add"
    case svnCleanup = "svn_cleanup"
    case svnCommit = "svn_commit"
    case svnRevert = "svn_revert"
    case svnMerge = "svn_merge"
    case svnSwitch = "svn_switch"
    case svnDelete = "svn_delete"
    case svnCopy = "svn_copy"

    public var risk: AISVNToolRisk {
        switch self {
        case .svnStatus, .svnLog, .svnDiff, .svnInfo, .svnList, .svnBlame, .svnCat:
            return .readOnly
        case .svnUpdate, .svnAdd, .svnCleanup:
            return .lowRiskWrite
        case .svnCommit, .svnRevert, .svnMerge, .svnSwitch, .svnDelete, .svnCopy:
            return .highRiskWrite
        }
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：工具分级测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift docs/superpowers/plans/2026-07-10-p6-ai-svn-agent-tool-registry-core.md
git diff --cached --check
git commit -m "feat: add P6 AI SVN tool risk models"
```

---

## 任务 2：只读工具自动执行与审计

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建/修改：`Sources/MacSvnCore/Services/AISVNToolRegistry.swift`
- 修改测试：`Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AISVNToolRegistryTests` 增加：

```swift
func testReadOnlyStatusExecutesThroughServiceAndWritesAuditRecord() async throws {
    let service = FakeAISVNToolService()
    service.statusResult = [
        FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(7), isTreeConflict: false)
    ]
    let audit = InMemoryAIToolAuditStore()
    let registry = AISVNToolRegistry(service: service, auditStore: audit)

    let decision = try await registry.handle(
        AISVNToolCall(name: "svn_status", arguments: ["wc": "/tmp/wc"]),
        sessionID: "session-1"
    )

    guard case .completed(let result) = decision else {
        return XCTFail("Expected completed result")
    }
    XCTAssertTrue(result.content.contains("README.md"))
    XCTAssertEqual(await service.recordedCalls(), ["status:/tmp/wc"])
    let records = await audit.records(sessionID: "session-1")
    XCTAssertEqual(records.map(\.toolName), ["svn_status"])
    XCTAssertEqual(records.map(\.risk), [.readOnly])
    XCTAssertEqual(records.map(\.outcome), [.completed])
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：编译失败，提示 `AISVNToolRegistry`、`AISVNToolCall` 或 `InMemoryAIToolAuditStore` 不存在。

- [x] **步骤 3：实现最少服务代码**

实现要求：
- `AISVNToolCall` 保存原始 tool 名和字符串参数；
- `AISVNToolRegistry.handle(_:sessionID:)` 解析 tool 名；
- 对 `.readOnly` 工具自动调用 service；
- 首批实现 `svn_status`、`svn_diff`、`svn_log`、`svn_info`、`svn_list`、`svn_blame`、`svn_cat`；
- `AISVNToolResult.content` 使用可读文本，供 Chat 面板直接展示；
- 成功时写入 `AISVNToolAuditRecord(outcome: .completed)`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：模型分级和只读执行测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift Sources/MacSvnCore/Services/AISVNToolRegistry.swift Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift docs/superpowers/plans/2026-07-10-p6-ai-svn-agent-tool-registry-core.md
git diff --cached --check
git commit -m "feat: add P6 AI SVN read-only tool registry"
```

---

## 任务 3：写工具确认门

**文件：**
- 修改：`Sources/MacSvnCore/Services/AISVNToolRegistry.swift`
- 修改测试：`Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AISVNToolRegistryTests` 增加：

```swift
func testWriteToolsReturnConfirmationWithoutExecutingService() async throws {
    let service = FakeAISVNToolService()
    let audit = InMemoryAIToolAuditStore()
    let registry = AISVNToolRegistry(service: service, auditStore: audit)

    let lowRisk = try await registry.handle(
        AISVNToolCall(name: "svn_update", arguments: ["wc": "/tmp/wc", "paths": "README.md,Sources/App.swift"]),
        sessionID: "session-2"
    )
    let highRisk = try await registry.handle(
        AISVNToolCall(name: "svn_revert", arguments: ["wc": "/tmp/wc", "paths": "README.md"]),
        sessionID: "session-2"
    )

    guard case .confirmationRequired(let updateConfirmation) = lowRisk,
          case .confirmationRequired(let revertConfirmation) = highRisk else {
        return XCTFail("Expected confirmation requests")
    }
    XCTAssertEqual(updateConfirmation.risk, .lowRiskWrite)
    XCTAssertEqual(updateConfirmation.impactPaths, ["README.md", "Sources/App.swift"])
    XCTAssertTrue(updateConfirmation.commandPreview.contains("svn update"))
    XCTAssertEqual(revertConfirmation.risk, .highRiskWrite)
    XCTAssertEqual(revertConfirmation.impactPaths, ["README.md"])
    XCTAssertTrue(revertConfirmation.warning.contains("高危"))
    XCTAssertEqual(await service.recordedCalls(), [])
    let records = await audit.records(sessionID: "session-2")
    XCTAssertEqual(records.map(\.outcome), [.confirmationRequired, .confirmationRequired])
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：测试失败或编译失败，提示写工具没有返回 confirmation。

- [x] **步骤 3：实现最少确认逻辑**

实现要求：
- `.lowRiskWrite` 与 `.highRiskWrite` 都不调用 service；
- 返回 `AISVNToolConfirmation(toolName:risk:commandPreview:impactPaths:warning:)`；
- `paths` 参数按逗号分割并去除空白；
- 高危工具 warning 包含中文「高危」；
- 审计 outcome 为 `.confirmationRequired`。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：写工具确认门测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AISVNToolRegistry.swift Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift docs/superpowers/plans/2026-07-10-p6-ai-svn-agent-tool-registry-core.md
git diff --cached --check
git commit -m "feat: add P6 AI SVN write confirmation gate"
```

---

## 任务 4：禁止未知工具与失败审计

**文件：**
- 修改：`Sources/MacSvnCore/Services/AISVNToolRegistry.swift`
- 修改测试：`Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift`

- [x] **步骤 1：编写失败测试**

在 `AISVNToolRegistryTests` 增加：

```swift
func testUnknownToolIsRejectedAndAuditedAsForbidden() async throws {
    let audit = InMemoryAIToolAuditStore()
    let registry = AISVNToolRegistry(service: FakeAISVNToolService(), auditStore: audit)

    do {
        _ = try await registry.handle(
            AISVNToolCall(name: "shell_exec", arguments: ["command": "rm -rf /"]),
            sessionID: "session-3"
        )
        XCTFail("Expected forbidden tool")
    } catch let error as AISVNToolError {
        XCTAssertEqual(error, .forbiddenTool("shell_exec"))
    } catch {
        XCTFail("Expected AISVNToolError, got \(error)")
    }

    let records = await audit.records(sessionID: "session-3")
    XCTAssertEqual(records.map(\.toolName), ["shell_exec"])
    XCTAssertEqual(records.map(\.outcome), [.failed])
    XCTAssertEqual(await registry.availableToolNames().contains("shell_exec"), false)
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：测试失败，未知工具未被审计或 `availableToolNames` 不存在。

- [x] **步骤 3：实现最少错误路径**

实现要求：
- 未知 tool name 抛 `.forbiddenTool(name)`；
- 失败时写入 `AISVNToolAuditRecord(outcome: .failed, summary: String(describing: error))`；
- `availableToolNames()` 只返回 `AISVNToolName.allCases.map(\.rawValue)`，不包含 shell 或文件系统直接写工具。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter AISVNToolRegistryTests
```

预期：全部 `AISVNToolRegistryTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/AISVNToolRegistry.swift Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift docs/superpowers/plans/2026-07-10-p6-ai-svn-agent-tool-registry-core.md
git diff --cached --check
git commit -m "feat: reject forbidden P6 AI SVN tools"
```

---

## 任务 5：目标验证与计划收尾

- [ ] **步骤 1：运行 P6 AI SVN Agent 目标集合**

```bash
swift test --filter "AISVNToolRegistryTests|SvnServiceTests"
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
git add docs/superpowers/plans/2026-07-10-p6-ai-svn-agent-tool-registry-core.md
git diff --cached --check
git commit -m "docs: complete P6 AI SVN tool registry verification"
```

---

## 自检

- 覆盖 `FR-AI-04` 的首个安全底座：tool-calling 工具表、只读自动执行、写工具确认门、禁止 shell/直接文件系统工具、审计记录。
- 覆盖 `NFR-13` 的 Core 起点：AI 发起写操作不会越过确认门，工具调用有本地审计记录模型。
- 本计划不实现 SwiftUI Chat 面板、真实 LLM 循环、多轮会话记忆、确认后的真实写操作执行、本地 JSON 审计持久化或导出；这些另行拆为 FR-AI-04 后续切片。
