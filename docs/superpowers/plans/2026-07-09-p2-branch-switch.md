# P2 Branch Switch 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-BR-03 的 Core 非 UI 部分：对工作副本执行 `svn switch`，切换前检测未提交变更并让上层进入确认状态。

**架构：** 沿用 ViewModel -> SvnService -> SvnBackend -> SvnCliBackend -> svn CLI 的现有链路。CLI 层新增 `switch` 命令并复用 `UpdateOutputParser` 解析输出；Service 层在写锁内先读取 `status`，默认阻断有本地变更的切换；ViewModel 层把阻断错误转换为确认状态，用户确认后带 `allowLocalChanges: true` 重试。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `switchTo(url:authArguments:)`，使用 `--accept postpone`、`--non-interactive`，认证参数不包含密码。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `switchTo(wc:url:auth:) -> UpdateSummary`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `switchTo`，在 WC 目录中运行 `svn switch`，用 `UpdateOutputParser` 解析 stdout。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `SvnServiceError.localChangesPreventSwitch(paths:)` 与 `switchTo(wc:url:auth:allowLocalChanges:)`。
- 创建：`Sources/MacSvnCore/ViewModels/BranchSwitchViewModel.swift`
  定义 `BranchSwitchProviding`、`BranchSwitchState`、`BranchSwitchViewModel`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 switch 参数顺序、认证参数和目标 URL。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 switch 的 stdin、工作目录、输出解析与密码不进 argv。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖有本地变更时默认阻断、允许后执行、认证失败重试。
- 创建：`Tests/MacSvnCoreTests/BranchSwitchViewModelTests.swift`
  覆盖成功状态、确认状态、确认后重试、错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 checkout trunk 后 switch 到 `branches/feature-one`，并用 `info` 验证 URL。

## 任务 1：命令构造与 CLI backend switch

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testSwitchUsesPostponeNonInteractiveAuthAndUrl() {
    let command = SvnCommandBuilder.switchTo(
        url: "file:///repo/branches/feature-one",
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "switch", "--accept", "postpone", "--non-interactive",
        "--username", "u", "--password-from-stdin",
        "file:///repo/branches/feature-one"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testSwitchPassesAuthStdinRunsInWorkingCopyAndParsesSummary() async throws {
    let output = """
    U    README.txt
    Updated to revision 9.
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let summary = try await backend.switchTo(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        url: "file:///repo/branches/feature-one",
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    XCTAssertEqual(runner.calls.single?.arguments, [
        "switch", "--accept", "postpone", "--non-interactive",
        "--username", "u", "--password-from-stdin",
        "file:///repo/branches/feature-one"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testSwitch|SvnCliBackendTests/testSwitch"`
预期：编译失败，提示 `switchTo` API 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnCommandBuilder.switchTo(url:authArguments:)`。
- `SvnBackend.switchTo(wc:url:auth:) -> UpdateSummary`。
- `SvnCliBackend.switchTo(...)`：构建 auth 参数，`currentDirectory` 使用 `wc.path`，stdout 交给 `UpdateOutputParser.parse`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testSwitch|SvnCliBackendTests/testSwitch"`
预期：目标测试 PASS。

## 任务 2：SvnService 本地变更保护与认证重试

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnServiceTests` 中新增：

```swift
func testSwitchBlocksLocalChangesBeforeBackendSwitchByDefault() async {
    let backend = MockSvnBackend()
    backend.statusResult = [
        FileStatus(path: "README.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
        FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
    ]
    let service = SvnService(backend: backend)

    do {
        _ = try await service.switchTo(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            url: "file:///repo/branches/feature-one",
            auth: nil
        )
        XCTFail("Expected localChangesPreventSwitch")
    } catch let error as SvnServiceError {
        XCTAssertEqual(error, .localChangesPreventSwitch(paths: ["README.txt", "new.txt"]))
    } catch {
        XCTFail("Expected SvnServiceError, got \(error)")
    }

    XCTAssertEqual(backend.calls.map(\.name), ["status"])
}

func testSwitchAllowsLocalChangesWhenConfirmed() async throws {
    let backend = MockSvnBackend()
    backend.statusResult = [
        FileStatus(path: "README.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
    ]
    backend.switchResult = UpdateSummary(updated: 1, revision: Revision(9))
    let service = SvnService(backend: backend)

    let summary = try await service.switchTo(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        url: "file:///repo/branches/feature-one",
        auth: nil,
        allowLocalChanges: true
    )

    XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
    XCTAssertEqual(backend.calls.map(\.name), ["status", "switch"])
}

func testSwitchPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.switchErrors = [.authentication]
    backend.switchResult = UpdateSummary(revision: Revision(10))
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let summary = try await service.switchTo(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        url: "file:///repo/branches/feature-one",
        auth: nil
    )
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(summary, UpdateSummary(revision: Revision(10)))
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/feature-one")!])
    XCTAssertEqual(backend.calls.map(\.name), ["status", "switch", "switch"])
    XCTAssertEqual(backend.switchCredentials, [nil, Credential(username: "u", password: "p")])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnServiceTests/testSwitch"`
预期：编译失败，提示 `switchTo` API、service error 或 mock 字段未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnServiceError.localChangesPreventSwitch(paths:)`。
- `SvnService.switchTo(wc:url:auth:allowLocalChanges:)`，默认 `allowLocalChanges = false`。
- 在写锁内先调用 `backend.status(wc:)`；若存在本地变更且未确认，抛出阻断错误。
- 认证 retry scope 使用目标 URL，后端调用失败一次 `.authentication` 后用凭据重试。
- 更新 `MockSvnBackend` 记录 switch 调用、凭据、错误序列和返回结果。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnServiceTests/testSwitch"`
预期：目标测试 PASS。

## 任务 3：BranchSwitchViewModel 确认流

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/BranchSwitchViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/BranchSwitchViewModelTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `BranchSwitchViewModelTests`，覆盖：

```swift
@MainActor
func testSwitchStoresCompletedSummary() async {
    let provider = FakeBranchSwitchProvider(result: .success(UpdateSummary(updated: 1, revision: Revision(9))))
    let viewModel = BranchSwitchViewModel(provider: provider)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    await viewModel.switchTo(wc: wc, url: "file:///repo/branches/feature-one", auth: nil)

    XCTAssertEqual(viewModel.state, .completed(UpdateSummary(updated: 1, revision: Revision(9))))
    XCTAssertEqual(await provider.recordedCalls(), [
        BranchSwitchCall(wc: wc, url: "file:///repo/branches/feature-one", auth: nil, allowLocalChanges: false)
    ])
}

@MainActor
func testSwitchWithLocalChangesStoresConfirmationAndConfirmRetriesAllowed() async {
    let provider = FakeBranchSwitchProvider(results: [
        .failure(SvnServiceError.localChangesPreventSwitch(paths: ["README.txt"])),
        .success(UpdateSummary(revision: Revision(10)))
    ])
    let viewModel = BranchSwitchViewModel(provider: provider)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    await viewModel.switchTo(wc: wc, url: "file:///repo/branches/feature-one", auth: nil)
    XCTAssertEqual(viewModel.state, .confirmationRequired(paths: ["README.txt"]))

    await viewModel.confirmSwitchWithLocalChanges()

    XCTAssertEqual(viewModel.state, .completed(UpdateSummary(revision: Revision(10))))
    XCTAssertEqual(await provider.recordedCalls(), [
        BranchSwitchCall(wc: wc, url: "file:///repo/branches/feature-one", auth: nil, allowLocalChanges: false),
        BranchSwitchCall(wc: wc, url: "file:///repo/branches/feature-one", auth: nil, allowLocalChanges: true)
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter BranchSwitchViewModelTests`
预期：编译失败，提示 `BranchSwitchViewModel` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `BranchSwitchProviding` 协议，签名与 `SvnService.switchTo` 一致。
- `BranchSwitchState`：`idle`、`switching`、`confirmationRequired(paths:)`、`completed(UpdateSummary)`、`error(String)`。
- `BranchSwitchViewModel.switchTo(...)` 和 `confirmSwitchWithLocalChanges()`。
- `extension SvnService: BranchSwitchProviding {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter BranchSwitchViewModelTests`
预期：目标测试 PASS。

## 任务 4：真实 SVN 集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的测试**

新增：

```swift
func testServiceSwitchChangesWorkingCopyUrlToBranch() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    _ = try await service.switchTo(
        wc: fixture.workingCopy,
        url: "\(fixture.repositoryURL)/branches/feature-one",
        auth: nil
    )
    let info = try await fixture.backend.info(wc: fixture.workingCopy, target: ".")

    XCTAssertEqual(info.url, "\(fixture.repositoryURL)/branches/feature-one")
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testServiceSwitchChangesWorkingCopyUrlToBranch`
预期：实现前编译失败或调用缺失。

- [ ] **步骤 3：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testSwitch|SvnCliBackendTests/testSwitch|SvnServiceTests/testSwitch|BranchSwitchViewModelTests|SvnCliBackendIntegrationTests/testServiceSwitchChangesWorkingCopyUrlToBranch"`
预期：目标测试 PASS。

- [ ] **步骤 4：全量验证与提交**

运行：
- `swift test`
- `git diff --check`
- `git add docs/superpowers/plans/2026-07-09-p2-branch-switch.md Sources/MacSvnCore Tests/MacSvnCoreTests`
- `git diff --cached --check`
- `git commit -m "feat: add P2 branch switch support"`
- `git diff HEAD^ HEAD --check`
- `git status --short --branch`

预期：测试 0 failures，空白检查无输出，提交后工作区干净。
