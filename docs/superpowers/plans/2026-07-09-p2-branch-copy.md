# P2 Branch Copy 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-BR-02 的 Core 非 UI 部分：通过 `svn copy` 从 WC/远端 URL 创建分支或标签，并返回服务端提交 revision。

**架构：** 在现有 CLI 后端链路上新增 `copy(source:destination:message:auth:)`，复用 `CommitOutputParser` 解析 `Committed revision N.`；`SvnService` 负责提交说明校验和认证失败后一次重试；`BranchCopyViewModel` 负责按 `BranchLayout` 生成 branch/tag 目标 URL 与状态暴露。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `copy(source:destination:message:authArguments:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `copy(source:destination:message:auth:) -> Revision`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `svn copy --encoding UTF-8 -m ...`，认证 stdin 不进 argv，`currentDirectory: nil`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `copy(...)`，校验提交说明非空，认证失败后以 destination URL 为 scope 重试一次。
- 创建：`Sources/MacSvnCore/ViewModels/BranchCopyViewModel.swift`
  定义 `BranchCopyProviding`、`BranchCopyState`、`BranchCopyViewModel`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 copy 参数顺序、UTF-8 编码、auth 参数和 URL。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 copy backend stdin、`currentDirectory: nil`、revision 解析。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 copy 空说明阻断、认证重试与重试失败。
- 创建：`Tests/MacSvnCoreTests/BranchCopyViewModelTests.swift`
  覆盖 branch/tag URL 生成、空名称阻断、错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `svn copy` 创建分支后可被 `branches(...)` 列出。

## 任务 1：命令构造与 CLI backend copy

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testCopyUsesUtf8MessageAuthSourceAndDestination() {
    let command = SvnCommandBuilder.copy(
        source: "file:///repo/trunk",
        destination: "file:///repo/branches/feature-one",
        message: "创建分支：feature-one",
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "copy", "--encoding", "UTF-8", "--non-interactive",
        "-m", "创建分支：feature-one",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk", "file:///repo/branches/feature-one"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testCopyPassesAuthStdinRunsWithoutWorkingCopyAndParsesRevision() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("Committed revision 12.\n".utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let revision = try await backend.copy(
        source: "file:///repo/trunk",
        destination: "file:///repo/branches/feature-one",
        message: "创建分支：feature-one",
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(revision, Revision(12))
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
    XCTAssertEqual(runner.calls.single?.arguments, [
        "copy", "--encoding", "UTF-8", "--non-interactive",
        "-m", "创建分支：feature-one",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk", "file:///repo/branches/feature-one"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testCopy|SvnCliBackendTests/testCopy"`
预期：编译失败，提示 `copy` API 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnCommandBuilder.copy(source:destination:message:authArguments:)`。
- `SvnBackend.copy(source:destination:message:auth:)`。
- `SvnCliBackend.copy(...)`：用 `AuthArguments.build`，`currentDirectory: nil`，用 `CommitOutputParser.parseRevision` 解析 stdout。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testCopy|SvnCliBackendTests/testCopy"`
预期：目标测试 PASS。

## 任务 2：SvnService copy 校验与认证重试

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnServiceTests` 中新增：

```swift
func testCopyRejectsEmptyMessageBeforeBackendCall() async throws {
    let backend = MockSvnBackend()
    let service = SvnService(backend: backend)

    do {
        _ = try await service.copy(source: "file:///repo/trunk", destination: "file:///repo/branches/dev", message: "  ", auth: nil)
        XCTFail("Expected emptyCommitMessage")
    } catch let error as SvnServiceError {
        XCTAssertEqual(error, .emptyCommitMessage)
    }

    XCTAssertTrue(backend.calls.isEmpty)
}

func testCopyPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.copyErrors = [.authentication]
    backend.copyResult = Revision(12)
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let revision = try await service.copy(source: "file:///repo/trunk", destination: "file:///repo/branches/dev", message: "create dev", auth: nil)
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(revision, Revision(12))
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/dev")!])
    XCTAssertEqual(backend.calls.map(\.name), ["copy", "copy"])
    XCTAssertEqual(backend.copyCredentials, [nil, Credential(username: "u", password: "p")])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnServiceTests/testCopy"`
预期：编译失败或测试失败，提示 service/backend copy 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnService.copy(source:destination:message:auth:)`。
- 空 message 抛 `SvnServiceError.emptyCommitMessage`。
- 认证 retry scope 使用 `URL(string: destination) ?? URL(fileURLWithPath: destination)`。
- 更新 `MockSvnBackend` 的 copy 记录和错误序列。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnServiceTests/testCopy"`
预期：目标测试 PASS。

## 任务 3：BranchCopyViewModel

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/BranchCopyViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/BranchCopyViewModelTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `BranchCopyViewModelTests`：

```swift
@MainActor
func testCreateBranchBuildsDestinationFromLayoutAndStoresRevision() async {
    let provider = FakeBranchCopyProvider(result: .success(Revision(12)))
    let viewModel = BranchCopyViewModel(copyProvider: provider)
    let auth = Credential(username: "u", password: "p")

    await viewModel.create(
        kind: .branch,
        source: "file:///repo/trunk",
        repositoryRoot: "file:///repo",
        name: "feature-one",
        layout: BranchLayout(),
        message: "创建分支：feature-one",
        auth: auth
    )

    XCTAssertEqual(viewModel.state, .completed(Revision(12)))
    XCTAssertEqual(viewModel.createdRevision, Revision(12))
    XCTAssertEqual(await provider.recordedCalls(), [
        BranchCopyCall(source: "file:///repo/trunk", destination: "file:///repo/branches/feature-one", message: "创建分支：feature-one", auth: auth)
    ])
}

@MainActor
func testCreateTagUsesTagsLayout() async {
    let provider = FakeBranchCopyProvider(result: .success(Revision(13)))
    let viewModel = BranchCopyViewModel(copyProvider: provider)
    let layout = BranchLayout(trunk: "main", branches: "dev", tags: "releases")

    await viewModel.create(kind: .tag, source: "file:///repo/main", repositoryRoot: "file:///repo", name: "v1.0", layout: layout, message: "tag v1.0", auth: nil)

    XCTAssertEqual(await provider.recordedCalls(), [
        BranchCopyCall(source: "file:///repo/main", destination: "file:///repo/releases/v1.0", message: "tag v1.0", auth: nil)
    ])
}

@MainActor
func testCreateRejectsEmptyNameBeforeProviderCall() async {
    let provider = FakeBranchCopyProvider(result: .success(Revision(1)))
    let viewModel = BranchCopyViewModel(copyProvider: provider)

    await viewModel.create(kind: .branch, source: "file:///repo/trunk", repositoryRoot: "file:///repo", name: "  ", layout: BranchLayout(), message: "create", auth: nil)

    XCTAssertEqual(viewModel.state, .error("emptyBranchName"))
    XCTAssertTrue(await provider.recordedCalls().isEmpty)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter BranchCopyViewModelTests`
预期：编译失败，提示 `BranchCopyViewModel` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `BranchCopyProviding` 协议，`SvnService` 遵循。
- `BranchCopyState`: `.idle/.copying/.completed(Revision)/.error(String)`。
- `BranchCopyViewModel.create(kind:source:repositoryRoot:name:layout:message:auth:)`。
- kind 为 `.branch` 使用 `layout.branches`，kind 为 `.tag` 使用 `layout.tags`，kind 为 `.trunk` 置 `.error("unsupportedBranchCopyKind")`。
- name trim 后为空置 `.error("emptyBranchName")`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter BranchCopyViewModelTests`
预期：目标测试 PASS。

## 任务 4：真实 SVN copy 集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的集成测试**

新增：

```swift
func testServiceCopyCreatesRemoteBranch() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let destination = "\(fixture.repositoryURL)/branches/from-copy"

    let revision = try await service.copy(
        source: fixture.trunkURL,
        destination: destination,
        message: "创建分支：from-copy",
        auth: nil
    )
    let branchList = try await service.branches(repositoryRoot: fixture.repositoryURL, layout: BranchLayout(), auth: nil)

    XCTAssertNotNil(revision)
    XCTAssertTrue(branchList.branches.map(\.name).contains("from-copy"))
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testServiceCopyCreatesRemoteBranch`
预期：实现前编译失败；实现错误时断言失败。

- [ ] **步骤 3：运行目标和全量验证**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testCopy|SvnCliBackendTests/testCopy|SvnServiceTests/testCopy|BranchCopyViewModelTests|SvnCliBackendIntegrationTests/testServiceCopyCreatesRemoteBranch"
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 4：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p2-branch-copy.md
git commit -m "feat: add P2 branch copy support"
```
