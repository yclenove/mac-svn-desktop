# P4 Commit Guard Core ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P4 `FR-EX-01` 的核心数据链路：提交前本地规则引擎检查冲突标记残留、大文件、禁提交路径和疑似密钥，并让提交流程以“默认警告可跳过、可配置硬阻断”的方式接入。

**架构：** 新增纯文件系统 `CommitGuardService`，按选中提交路径扫描工作副本文件并返回结构化 `CommitGuardIssue`。`SvnService.commit` 在冲突状态校验后调用可选 guard，遇到 blocking issue 直接阻断，遇到 warning issue 默认抛出可确认错误；`CommitViewModel` 将该错误转换为确认状态，用户确认后以 `skipGuardWarnings` 重试提交。

**技术栈：** Swift 6.1、Foundation 文件属性与文本读取、Observation、XCTest concurrency、现有 `SvnService` / `CommitViewModel`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `CommitGuardRuleID`、`CommitGuardSeverity`、`CommitGuardIssue`、`CommitGuardConfiguration`。
- 创建：`Sources/MacSvnCore/Services/CommitGuardService.swift`
  定义 `CommitGuardChecking` 协议、默认规则、glob 匹配和文件扫描实现。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  初始化器接收可选 `commitGuard`，`commit` 增加 `skipGuardWarnings` 参数并抛出 guard warning/blocking 错误。
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
  `CommitProviding.commit` 增加 `skipGuardWarnings`，`CommitViewState` 增加 `.guardWarnings([CommitGuardIssue])`。
- 创建：`Tests/MacSvnCoreTests/CommitGuardServiceTests.swift`
  覆盖四类默认规则、硬阻断配置和不可读/缺失路径容错。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 service 默认警告阻断、确认跳过、blocking issue 不可跳过。
- 修改：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`
  覆盖 guard warning 状态和确认后重试提交。

## 任务 1：CommitGuard 模型与规则引擎

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/CommitGuardService.swift`
- 创建：`Tests/MacSvnCoreTests/CommitGuardServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `CommitGuardServiceTests`：

```swift
import XCTest
@testable import MacSvnCore

final class CommitGuardServiceTests: XCTestCase {
    func testDetectsConflictMarkersLargeFilesDeniedPathsAndSecrets() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "before\n<<<<<<< mine\n=======\n>>>>>>> theirs\n".write(
            to: root.appendingPathComponent("conflict.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 0x61, count: 11).write(to: root.appendingPathComponent("big.bin"))
        try "debug\n".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "token = ghp_123456789012345678901234567890123456\n".write(
            to: root.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = CommitGuardService(configuration: CommitGuardConfiguration(largeFileThresholdBytes: 10))

        let issues = try await service.evaluate(
            wc: root,
            paths: ["conflict.txt", "big.bin", "debug.log", "secret.txt"]
        )

        XCTAssertEqual(issues.map(\.ruleID), [
            .conflictMarker,
            .largeFile,
            .deniedPath,
            .suspectedSecret
        ])
        XCTAssertEqual(issues.map(\.severity), [.warning, .warning, .warning, .warning])
        XCTAssertEqual(issues.map(\.path), ["conflict.txt", "big.bin", "debug.log", "secret.txt"])
    }

    func testHardBlockedRulesProduceBlockingSeverity() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "token = sk-123456789012345678901234567890\n".write(
            to: root.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        let config = CommitGuardConfiguration(hardBlockedRules: [.suspectedSecret])
        let service = CommitGuardService(configuration: config)

        let issues = try await service.evaluate(wc: root, paths: ["secret.txt"])

        XCTAssertEqual(issues.first?.ruleID, .suspectedSecret)
        XCTAssertEqual(issues.first?.severity, .blocking)
    }

    func testMissingDirectoriesAndDeletedPathsAreIgnored() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        let service = CommitGuardService()

        let issues = try await service.evaluate(wc: root, paths: ["src", "deleted.txt"])

        XCTAssertEqual(issues, [])
    }
}
```

测试文件末尾添加临时目录 helper：

```swift
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter CommitGuardServiceTests
```

预期：编译失败，提示 `CommitGuardService` / `CommitGuardIssue` / `CommitGuardConfiguration` 未定义。

- [ ] **步骤 3：编写最少实现代码**

在 `SvnModels.swift` 中新增：

```swift
public enum CommitGuardRuleID: String, Codable, Equatable, Hashable, Sendable {
    case conflictMarker
    case largeFile
    case deniedPath
    case suspectedSecret
}

public enum CommitGuardSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocking
}

public struct CommitGuardIssue: Equatable, Sendable {
    public let ruleID: CommitGuardRuleID
    public let severity: CommitGuardSeverity
    public let path: String
    public let message: String
    public let detail: String?
}

public struct CommitGuardConfiguration: Equatable, Sendable {
    public var largeFileThresholdBytes: Int
    public var deniedPathPatterns: [String]
    public var hardBlockedRules: Set<CommitGuardRuleID>
}
```

在 `CommitGuardService.swift` 中实现：

- `CommitGuardChecking.evaluate(wc:paths:) async throws -> [CommitGuardIssue]`。
- 默认阈值 `10 * 1024 * 1024`。
- 默认禁提交模式：`*.log`、`node_modules/**`、`.DS_Store`。
- conflict marker 检测：文本中包含 `<<<<<<<`、`=======`、`>>>>>>>` 任一组标记时报告 `.conflictMarker`。
- secret 检测：匹配 `AKIA[0-9A-Z]{16}`、`ghp_[A-Za-z0-9_]{20,}`、`sk-[A-Za-z0-9_-]{20,}` 或 `BEGIN PRIVATE KEY`。
- 文件不存在或目录直接跳过；二进制/不可 UTF-8 解码文件只参与大小和路径规则。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter CommitGuardServiceTests
```

预期：全部 `CommitGuardServiceTests` PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Services/CommitGuardService.swift Tests/MacSvnCoreTests/CommitGuardServiceTests.swift docs/superpowers/plans/2026-07-09-p4-commit-guard-core-view-model.md
git commit -m "feat: add P4 commit guard engine"
```

## 任务 2：SvnService commit guard 接入

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnServiceTests` 中新增：

```swift
func testCommitGuardWarningsStopCommitUntilCallerSkipsWarnings() async throws {
    let backend = MockSvnBackend()
    backend.statusResult = [
        FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
    ]
    backend.commitResult = Revision(42)
    let issue = CommitGuardIssue(
        ruleID: .conflictMarker,
        severity: .warning,
        path: "a.txt",
        message: "Conflict marker remains.",
        detail: nil
    )
    let guardProvider = FakeCommitGuardProvider(result: .success([issue]))
    let service = SvnService(backend: backend, commitGuard: guardProvider)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    do {
        _ = try await service.commit(wc: wc, paths: ["a.txt"], message: "fix", auth: nil)
        XCTFail("Expected commit guard warnings")
    } catch let error as SvnServiceError {
        XCTAssertEqual(error, .commitGuardWarnings([issue]))
    }

    let revision = try await service.commit(
        wc: wc,
        paths: ["a.txt"],
        message: "fix",
        auth: nil,
        skipGuardWarnings: true
    )

    XCTAssertEqual(revision, Revision(42))
    XCTAssertEqual(backend.calls.map(\.name), ["status", "status", "commit"])
    XCTAssertEqual(await guardProvider.recordedCalls(), [
        CommitGuardCall(wc: wc, paths: ["a.txt"]),
        CommitGuardCall(wc: wc, paths: ["a.txt"])
    ])
}

func testCommitGuardBlockingIssuesCannotBeSkipped() async {
    let backend = MockSvnBackend()
    backend.statusResult = [
        FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
    ]
    let issue = CommitGuardIssue(
        ruleID: .suspectedSecret,
        severity: .blocking,
        path: "a.txt",
        message: "Secret detected.",
        detail: nil
    )
    let guardProvider = FakeCommitGuardProvider(result: .success([issue]))
    let service = SvnService(backend: backend, commitGuard: guardProvider)

    do {
        _ = try await service.commit(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["a.txt"],
            message: "fix",
            auth: nil,
            skipGuardWarnings: true
        )
        XCTFail("Expected commit guard block")
    } catch let error as SvnServiceError {
        XCTAssertEqual(error, .commitGuardBlocked([issue]))
    } catch {
        XCTFail("Expected SvnServiceError, got \(error)")
    }
}
```

新增测试辅助：

```swift
private struct CommitGuardCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
}

private actor FakeCommitGuardProvider: CommitGuardChecking {
    private let result: Result<[CommitGuardIssue], Error>
    private var calls: [CommitGuardCall] = []

    init(result: Result<[CommitGuardIssue], Error>) {
        self.result = result
    }

    func evaluate(wc: URL, paths: [String]) async throws -> [CommitGuardIssue] {
        calls.append(CommitGuardCall(wc: wc, paths: paths))
        return try result.get()
    }

    func recordedCalls() -> [CommitGuardCall] {
        calls
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnServiceTests/testCommitGuard"
```

预期：编译失败，提示 `commitGuard` 初始化参数、`skipGuardWarnings` 或 service error case 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `SvnServiceError.commitGuardWarnings([CommitGuardIssue])`。
- `SvnServiceError.commitGuardBlocked([CommitGuardIssue])`。
- `SvnService` 初始化器增加 `commitGuard: (any CommitGuardChecking)? = nil`。
- `commit(wc:paths:message:auth:skipGuardWarnings:)` 默认 `skipGuardWarnings = false`。
- commit 流程：空说明校验 → 写锁 → status 冲突校验 → guard evaluate → blocking 直接抛 `.commitGuardBlocked` → warning 且未 skip 抛 `.commitGuardWarnings` → backend commit。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnServiceTests/testCommitGuard|SvnServiceTests/testCommit"
```

预期：commit 相关 service 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnServiceTests.swift
git commit -m "feat: add P4 commit guard service flow"
```

## 任务 3：CommitViewModel guard warning 确认流

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `CommitViewModelTests` 中新增：

```swift
@MainActor
func testCommitGuardWarningsStoreConfirmationStateBeforeRetry() async {
    let issue = CommitGuardIssue(
        ruleID: .largeFile,
        severity: .warning,
        path: "big.bin",
        message: "Large file.",
        detail: nil
    )
    let commitProvider = FakeCommitProvider(results: [
        .failure(SvnServiceError.commitGuardWarnings([issue])),
        .success(Revision(42))
    ])
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: commitProvider,
        statusProvider: statusProvider
    )
    viewModel.message = "fix"

    await viewModel.commit(auth: nil)
    XCTAssertEqual(viewModel.state, .guardWarnings([issue]))
    XCTAssertEqual(viewModel.guardIssues, [issue])

    await viewModel.commit(auth: nil, skipGuardWarnings: true)

    XCTAssertEqual(viewModel.state, .committed(Revision(42)))
    XCTAssertEqual(await commitProvider.recordedCalls().map(\.skipGuardWarnings), [false, true])
}
```

更新 `CommitCall` 增加 `skipGuardWarnings`，更新 `FakeCommitProvider` 支持队列式 results。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "CommitViewModelTests/testCommitGuardWarnings"
```

预期：编译失败或测试失败，提示 `guardWarnings` 状态、`guardIssues` 或 `skipGuardWarnings` 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `CommitProviding.commit(wc:paths:message:auth:skipGuardWarnings:)`。
- `CommitViewState.guardWarnings([CommitGuardIssue])`。
- `CommitViewModel.guardIssues`。
- `commit(auth:skipGuardWarnings:)` 默认 `false`，调用 provider 透传。
- catch `SvnServiceError.commitGuardWarnings(let issues)` 时保存 `guardIssues` 并置 `.guardWarnings(issues)`，不刷新 status。
- 成功提交后清空 `guardIssues`。
- `extension SvnService: CommitProviding {}` 继续由 `SvnService.commit` 满足协议。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "CommitViewModelTests"
```

预期：全部 `CommitViewModelTests` PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CommitViewModel.swift Tests/MacSvnCoreTests/CommitViewModelTests.swift
git commit -m "feat: add P4 commit guard view model flow"
```

## 任务 4：全量验证

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行目标测试**

运行：

```bash
swift test --filter "CommitGuardServiceTests|SvnServiceTests/testCommitGuard|CommitViewModelTests"
```

预期：目标测试全部 PASS。

- [ ] **步骤 2：运行全量测试**

运行：

```bash
swift test
git diff --check
```

预期：全量测试 PASS，空白检查无输出。

- [ ] **步骤 3：确认工作区**

运行：

```bash
git status --short --branch
```

预期：工作区干净。

## 自检

- 覆盖 `FR-EX-01` 的确定性本地规则：冲突标记、大文件、禁提交路径、疑似密钥。
- 默认所有规则为 warning，ViewModel 暴露确认状态；`CommitGuardConfiguration.hardBlockedRules` 支持硬阻断。
- 不实现团队级配置 UI、AI 评审或提交守护设置页；这些属于后续 P4/P6 切片。
