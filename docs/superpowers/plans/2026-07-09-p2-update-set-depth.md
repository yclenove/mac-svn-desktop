# P2 Update Set Depth 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-WC-06 中“已有 WC 可调整深度”的 Core 非 UI 部分：`svn update --set-depth <depth>` 命令构造、backend/service 透传、WorkingCopyActionsViewModel 状态层透传。

**架构：** 复用已存在的 `SvnDepth`。扩展 `update` 相关协议和方法增加可选 `setDepth` 参数，默认 nil 保持 P1 update 行为；ViewModel 在 update 状态流中透传该参数并继续刷新 status。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  `update` 协议增加 `setDepth: SvnDepth?`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  `update` 命令增加可选 `--set-depth`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  `update` backend 透传 `setDepth`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  `update` service 透传 `setDepth` 并保留认证重试。
- 修改：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
  `WorkingCopyActionProviding.update` 与 ViewModel update 增加 `setDepth`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 `update --set-depth files`。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 backend update depth/auth 参数。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 service update depth 重试保留。
- 修改：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`
  覆盖 ViewModel update 透传 setDepth。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖 empty checkout 后 set-depth files 拉取根文件。
- 创建：`docs/superpowers/plans/2026-07-09-p2-update-set-depth.md`
  记录此切片计划。

## 任务 1：命令和 backend set-depth

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testUpdateCanSetDepth() {
    let command = SvnCommandBuilder.update(paths: [], revision: nil, setDepth: .files)

    XCTAssertEqual(command.arguments, [
        "update", "--accept", "postpone", "--non-interactive",
        "--set-depth", "files"
    ])
}
```

在 `SvnCliBackendTests.testUpdatePassesAuthStdinWithoutLeakingPasswordInArguments` 中把调用改为 `setDepth: .immediates`，并期望 argv 包含 `--set-depth immediates`。

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testUpdateCanSetDepth|SvnCliBackendTests/testUpdatePassesAuthStdinWithoutLeakingPasswordInArguments"`
预期：编译失败或测试失败，提示 update 缺 `setDepth`。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnCommandBuilder.update(paths:revision:setDepth:authArguments:)`。
- `SvnBackend.update(wc:paths:revision:setDepth:auth:)`。
- `SvnCliBackend.update(wc:paths:revision:setDepth:auth:)`。
- 默认参数：`setDepth: nil`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testUpdateCanSetDepth|SvnCliBackendTests/testUpdatePassesAuthStdinWithoutLeakingPasswordInArguments"`
预期：目标测试 PASS。

## 任务 2：service 与 action ViewModel 透传

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 修改：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `SvnServiceTests.testUpdatePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure` 中调用：

```swift
let summary = try await service.update(wc: wc, paths: ["src"], revision: Revision(9), setDepth: .files)
```

并断言：

```swift
XCTAssertEqual(backend.updateSetDepths, [.files, .files])
```

在 `WorkingCopyActionsViewModelTests.testUpdateStoresSummaryAndRefreshesStatuses` 中调用：

```swift
await viewModel.update(paths: ["Sources"], revision: Revision(7), setDepth: .immediates)
```

并让 `ActionCall` 增加 `setDepth` 字段，断言 `.immediates` 被传入。

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnServiceTests/testUpdatePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure|WorkingCopyActionsViewModelTests/testUpdateStoresSummaryAndRefreshesStatuses"`
预期：编译失败或测试失败。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnService.update(... setDepth: SvnDepth? = nil)` 透传 backend。
- `WorkingCopyActionProviding.update(... setDepth: SvnDepth?)`。
- `WorkingCopyActionsViewModel.update(... setDepth: SvnDepth? = nil)` 透传 provider。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnServiceTests/testUpdatePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure|WorkingCopyActionsViewModelTests/testUpdateStoresSummaryAndRefreshesStatuses"`
预期：目标测试 PASS。

## 任务 3：真实 svn set-depth 集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写失败的测试**

新增集成测试：

```swift
func testUpdateSetDepthFilesFetchesRootFilesAfterEmptyCheckout() async throws {
    let fixture = try makeFixture()
    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy, depth: .empty, auth: nil)

    _ = try await fixture.backend.update(
        wc: fixture.workingCopy,
        paths: [],
        revision: nil,
        setDepth: .files,
        auth: nil
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("src").path))
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testUpdateSetDepthFilesFetchesRootFilesAfterEmptyCheckout`
预期：实现前编译失败；实现错误时断言失败。

- [x] **步骤 3：编写最少实现代码**

若前两任务实现正确，此任务通常无需额外生产代码。

- [x] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Backend/SvnBackend.swift Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Sources/MacSvnCore/Backend/SvnCliBackend.swift Sources/MacSvnCore/Services/SvnService.swift Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p2-update-set-depth.md
git commit -m "feat: add P2 update set-depth support"
```
