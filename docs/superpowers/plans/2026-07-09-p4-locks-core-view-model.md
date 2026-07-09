# P4 Locks Core ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P4 `FR-LK-01` 的核心数据链路：展示 SVN 锁状态、获取锁、释放锁、强制夺锁/破锁，并提供可绑定的 `LockViewModel`。

**架构：** 使用 `svn status --xml --show-updates` 解析 `<wc-status><lock>` 与 `<repos-status><lock>`，用 `SvnLock` 同时表达“仓库是否被锁”和“当前 WC 是否持锁”。`SvnCommandBuilder` 新增 `lock` / `unlock` / `lockStatus` 参数构造；`SvnCliBackend` 在 WC 目录执行；`SvnService` 对 lock/unlock 写操作复用每 WC 写锁；`LockViewModel` 负责加载、加锁、解锁、强制确认门控与错误状态。

**技术栈：** Swift 6.1、Foundation XMLParser、Observation、XCTest concurrency、现有 `SvnBackend` / `SvnService` / `ProcessRunner` / 本地 `svnadmin` 集成测试夹具。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  - 新增 `SvnLock`。
- 创建：`Sources/MacSvnCore/Parsers/LockStatusXMLParser.swift`
  - 解析 `svn status --xml --show-updates` 中的 `wc-status` / `repos-status` 锁节点。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  - 新增 `lockStatus(targets:)`、`lock(paths:message:force:)`、`unlock(paths:force:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  - 新增 `locks`、`lock`、`unlock`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  - 接入锁命令与 parser。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  - 新增锁查询和写操作，写操作走 `withWriteLock`。
- 创建：`Sources/MacSvnCore/ViewModels/LockViewModel.swift`
  - 提供 P4 锁管理状态层。
- 创建：`Tests/MacSvnCoreTests/LockStatusXMLParserTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 创建：`Tests/MacSvnCoreTests/LockViewModelTests.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：锁模型与 status XML Parser

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Parsers/LockStatusXMLParser.swift`
- 创建：`Tests/MacSvnCoreTests/LockStatusXMLParserTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `LockStatusXMLParserTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class LockStatusXMLParserTests: XCTestCase {
    func testParsesWorkingCopyOwnedAndRepositoryLocks() throws {
        let xml = """
        <status><target path=".">
          <entry path="mine.txt">
            <wc-status item="normal" revision="1">
              <lock><token>opaquelocktoken:mine</token><owner>yangchao</owner><comment>mine note</comment><created>2026-07-09T11:02:50.061286Z</created></lock>
            </wc-status>
            <repos-status item="none">
              <lock><token>opaquelocktoken:mine</token><owner>yangchao</owner><comment>mine note</comment><created>2026-07-09T11:02:50.061286Z</created></lock>
            </repos-status>
          </entry>
          <entry path="other.txt">
            <wc-status item="normal" revision="1"/>
            <repos-status item="none">
              <lock><token>opaquelocktoken:other</token><owner>alice</owner><comment>other note</comment><created>2026-07-09T11:03:14.059595Z</created></lock>
            </repos-status>
          </entry>
        </target></status>
        """

        let locks = try LockStatusXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(locks, [
            SvnLock(
                target: "mine.txt",
                token: "opaquelocktoken:mine",
                owner: "yangchao",
                comment: "mine note",
                created: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T11:02:50.061286Z"),
                isOwnedByWorkingCopy: true,
                isRepositoryLocked: true
            ),
            SvnLock(
                target: "other.txt",
                token: "opaquelocktoken:other",
                owner: "alice",
                comment: "other note",
                created: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T11:03:14.059595Z"),
                isOwnedByWorkingCopy: false,
                isRepositoryLocked: true
            )
        ])
    }

    func testIgnoresEntriesWithoutLocks() throws {
        let xml = """
        <status><target path="."><entry path="clean.txt"><wc-status item="normal" revision="1"/></entry></target></status>
        """

        XCTAssertEqual(try LockStatusXMLParser.parse(Data(xml.utf8)), [])
    }

    func testInvalidLockStatusXMLThrowsParseError() {
        XCTAssertThrowsError(try LockStatusXMLParser.parse(Data("<status>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \\(error)")
            }
        }
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter LockStatusXMLParserTests
```

预期：编译失败，提示 `LockStatusXMLParser` / `SvnLock` 未定义。

- [ ] **步骤 3：实现最少代码**

在 `SvnModels.swift` 新增：

```swift
public struct SvnLock: Equatable, Sendable {
    public let target: String
    public let token: String?
    public let owner: String?
    public let comment: String?
    public let created: Date?
    public let isOwnedByWorkingCopy: Bool
    public let isRepositoryLocked: Bool

    public init(
        target: String,
        token: String?,
        owner: String?,
        comment: String?,
        created: Date?,
        isOwnedByWorkingCopy: Bool,
        isRepositoryLocked: Bool
    ) {
        self.target = target
        self.token = token
        self.owner = owner
        self.comment = comment
        self.created = created
        self.isOwnedByWorkingCopy = isOwnedByWorkingCopy
        self.isRepositoryLocked = isRepositoryLocked
    }
}
```

创建 `LockStatusXMLParser`：
- 在 `entry@path` 记录当前 target。
- 进入 `wc-status` / `repos-status` 时记录当前状态 scope。
- 在对应 scope 的 `<lock>` 内收集 `token`、`owner`、`comment`、`created`。
- 一个 entry 有 `wc-status` lock 时 `isOwnedByWorkingCopy=true`；有 `repos-status` lock 时 `isRepositoryLocked=true`。
- 若两边都有 lock，合并成一个 `SvnLock`，锁元数据优先使用 `repos-status`，没有时用 `wc-status`。
- XML 解析失败抛 `SvnError.parse`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter LockStatusXMLParserTests
```

预期：3 个 parser 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Parsers/LockStatusXMLParser.swift Tests/MacSvnCoreTests/LockStatusXMLParserTests.swift docs/superpowers/plans/2026-07-09-p4-locks-core-view-model.md
git commit -m "feat: add P4 lock status XML parser"
```

## 任务 2：锁命令、Backend、Service

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCommandBuilderTests` 新增：

```swift
func testLockCommandsUseNonInteractiveUtf8MessageForceAndTargets() {
    XCTAssertEqual(
        SvnCommandBuilder.lockStatus(targets: ["README.txt"]).arguments,
        ["status", "--xml", "--show-updates", "--non-interactive", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.lock(paths: ["README.txt"], message: "锁定：编辑中", force: true).arguments,
        ["lock", "--encoding", "UTF-8", "--non-interactive", "--force", "-m", "锁定：编辑中", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.lock(paths: ["README.txt"], message: nil, force: false).arguments,
        ["lock", "--encoding", "UTF-8", "--non-interactive", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.unlock(paths: ["README.txt"], force: true).arguments,
        ["unlock", "--non-interactive", "--force", "README.txt"]
    )
}
```

在 `SvnCliBackendTests` 新增：

```swift
func testLockStatusRunsInWorkingCopyAndParsesXml() async throws {
    let xml = """
    <status><target path="."><entry path="README.txt"><wc-status item="normal" revision="1"/><repos-status item="none"><lock><token>t</token><owner>u</owner></lock></repos-status></entry></target></status>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let locks = try await backend.locks(wc: URL(fileURLWithPath: "/tmp/wc"), targets: ["README.txt"])

    XCTAssertEqual(locks.map(\\.target), ["README.txt"])
    XCTAssertEqual(locks.first?.owner, "u")
    XCTAssertEqual(runner.calls.single?.arguments, ["status", "--xml", "--show-updates", "--non-interactive", "README.txt"])
    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
}

func testLockAndUnlockRunInWorkingCopy() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    try await backend.lock(wc: wc, paths: ["README.txt"], message: "锁定：编辑中", force: true)
    try await backend.unlock(wc: wc, paths: ["README.txt"], force: true)

    XCTAssertEqual(runner.calls.map(\\.arguments), [
        ["lock", "--encoding", "UTF-8", "--non-interactive", "--force", "-m", "锁定：编辑中", "README.txt"],
        ["unlock", "--non-interactive", "--force", "README.txt"]
    ])
    XCTAssertEqual(runner.calls.map(\\.currentDirectory), ["/tmp/wc", "/tmp/wc"])
}
```

在 `SvnServiceTests` 的 `MockSvnBackend` 加锁结果与调用记录，新增：

```swift
func testLockMethodsForwardToBackendAndWritesUseLocks() async throws {
    let backend = MockSvnBackend()
    backend.locksResult = [
        SvnLock(target: "README.txt", token: "t", owner: "u", comment: nil, created: nil, isOwnedByWorkingCopy: true, isRepositoryLocked: true)
    ]
    let service = SvnService(backend: backend)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let locks = try await service.locks(wc: wc, targets: ["README.txt"])
    try await service.lock(wc: wc, paths: ["README.txt"], message: "note", force: true)
    try await service.unlock(wc: wc, paths: ["README.txt"], force: true)

    XCTAssertEqual(locks, backend.locksResult)
    XCTAssertEqual(backend.calls.map(\\.name), ["locks", "lock", "unlock"])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testLock|SvnCliBackendTests/testLock|SvnServiceTests/testLock"
```

预期：编译失败，提示锁 command/backend/service API 未定义。

- [ ] **步骤 3：实现最少代码**

实现：
- `SvnCommandBuilder.lockStatus(targets:)`。
- `SvnCommandBuilder.lock(paths:message:force:)`。
- `SvnCommandBuilder.unlock(paths:force:)`。
- `SvnBackend` 新增 `locks`、`lock`、`unlock`。
- `SvnCliBackend.locks` 调用 `lockStatus` 并用 `LockStatusXMLParser.parse`。
- `SvnCliBackend.lock` / `unlock` 在 WC 目录执行命令。
- `SvnService.locks` 直接查询。
- `SvnService.lock` / `unlock` 走 `withWriteLock(wc:operation:)`。
- 更新 `MockSvnBackend`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testLock|SvnCliBackendTests/testLock|SvnServiceTests/testLock"
```

预期：锁链路测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Backend Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift
git commit -m "feat: add P4 lock backend service"
```

## 任务 3：LockViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/LockViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/LockViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `LockViewModelTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class LockViewModelTests: XCTestCase {
    @MainActor
    func testLoadLockUnlockAndRefreshesLocks() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeLockProvider(results: [
            .success([]),
            .success([SvnLock(target: "README.txt", token: "t", owner: "u", comment: "note", created: nil, isOwnedByWorkingCopy: true, isRepositoryLocked: true)]),
            .success([])
        ])
        let viewModel = LockViewModel(workingCopy: wc, provider: provider)

        await viewModel.load(targets: ["README.txt"])
        await viewModel.lock(paths: ["README.txt"], message: "note", force: false)
        await viewModel.unlock(paths: ["README.txt"], force: false)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.locks, [])
        XCTAssertEqual(await provider.recordedCalls(), [
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "lock", wc: wc, paths: ["README.txt"], message: "note", force: false),
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "unlock", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false)
        ])
    }

    @MainActor
    func testForceLockRequiresConfirmationBeforeProviderCall() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await viewModel.lock(paths: ["README.txt"], message: nil, force: true, confirmed: false)

        XCTAssertEqual(viewModel.state, .confirmationRequired(.lock, ["README.txt"]))
        XCTAssertEqual(await provider.recordedCalls(), [])
    }

    @MainActor
    func testRejectsEmptyPathsBeforeProviderCall() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await viewModel.unlock(paths: [], force: false)

        XCTAssertEqual(viewModel.state, .error("emptyLockPaths"))
        XCTAssertEqual(await provider.recordedCalls(), [])
    }
}
```

测试辅助：

```swift
private struct LockProviderCall: Equatable {
    let operation: String
    let wc: URL
    let paths: [String]
    let message: String?
    let force: Bool
}

private actor FakeLockProvider: LockProviding {
    private var results: [Result<[SvnLock], Error>]
    private var calls: [LockProviderCall] = []

    init(results: [Result<[SvnLock], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [LockProviderCall] {
        calls
    }

    func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        calls.append(LockProviderCall(operation: "locks", wc: wc, paths: targets, message: nil, force: false))
        return try results.removeFirst().get()
    }

    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws {
        calls.append(LockProviderCall(operation: "lock", wc: wc, paths: paths, message: message, force: force))
    }

    func unlock(wc: URL, paths: [String], force: Bool) async throws {
        calls.append(LockProviderCall(operation: "unlock", wc: wc, paths: paths, message: nil, force: force))
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter LockViewModelTests
```

预期：编译失败，提示 `LockViewModel` / `LockProviding` 未定义。

- [ ] **步骤 3：实现最少代码**

创建 `LockViewModel`：
- `LockProviding` 协议：`locks`、`lock`、`unlock`。
- `LockOperation`: `.lock`、`.unlock`。
- `LockViewState`: `.idle`、`.loading`、`.locking`、`.unlocking`、`.loaded`、`.confirmationRequired(LockOperation, [String])`、`.error(String)`。
- `load(targets:)` 查询锁。
- `lock(paths:message:force:confirmed:)`：空 paths 报 `emptyLockPaths`；force 且未确认时进入 confirmation；成功后刷新 `paths`。
- `unlock(paths:force:confirmed:)` 同上。
- `extension SvnService: LockProviding {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter LockViewModelTests
```

预期：3 个 ViewModel 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/LockViewModel.swift Tests/MacSvnCoreTests/LockViewModelTests.swift
git commit -m "feat: add P4 lock view model"
```

## 任务 4：真实 SVN 集成与全量验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写集成测试**

在 `SvnCliBackendIntegrationTests` 新增：

```swift
func testLocksListLockUnlockAndDetectRepositoryLockFromAnotherWorkingCopy() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let otherWC = fixture.root.appendingPathComponent("wc-lock-other", isDirectory: true)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)

    try await service.lock(wc: fixture.workingCopy, paths: ["README.txt"], message: "锁定：编辑中", force: false)
    let mineLocks = try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"])

    XCTAssertEqual(mineLocks.first?.target, "README.txt")
    XCTAssertEqual(mineLocks.first?.owner, NSUserName())
    XCTAssertEqual(mineLocks.first?.comment, "锁定：编辑中")
    XCTAssertTrue(mineLocks.first?.isOwnedByWorkingCopy ?? false)
    XCTAssertTrue(mineLocks.first?.isRepositoryLocked ?? false)

    try await service.unlock(wc: fixture.workingCopy, paths: ["README.txt"], force: false)
    XCTAssertEqual(try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"]), [])

    try await service.lock(wc: otherWC, paths: ["README.txt"], message: "other", force: false)
    let otherLocks = try await service.locks(wc: fixture.workingCopy, targets: ["README.txt"])
    XCTAssertFalse(otherLocks.first?.isOwnedByWorkingCopy ?? true)
    XCTAssertTrue(otherLocks.first?.isRepositoryLocked ?? false)
}
```

- [ ] **步骤 2：运行集成测试**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testLocksListLockUnlockAndDetectRepositoryLockFromAnotherWorkingCopy
```

预期：PASS。

- [ ] **步骤 3：运行锁目标集**

运行：

```bash
swift test --filter "LockStatusXMLParserTests|LockViewModelTests|SvnCommandBuilderTests/testLock|SvnCliBackendTests/testLock|SvnServiceTests/testLock|SvnCliBackendIntegrationTests/testLocksListLockUnlockAndDetectRepositoryLockFromAnotherWorkingCopy"
```

预期：全部 PASS。

- [ ] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全量测试 PASS，空白检查无输出。

- [ ] **步骤 5：Commit**

```bash
git add Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift
git commit -m "test: cover P4 lock integration"
```

## 自检

- 覆盖 `FR-LK-01` 的核心锁定管理：获取锁、释放锁、强制参数、锁列表状态与持有者。
- 覆盖当前 WC 持锁与他人/其他 WC 持锁的状态区分。
- 不覆盖远端 URL 直接 lock/unlock、批量 targets 文件、团队锁定看板；这些属于 P4/P6 后续子切片。
- 不引入外部依赖，不改变现有 status/log/diff/blame/props 行为。
