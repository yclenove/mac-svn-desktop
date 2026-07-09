# P1 Working Copy Actions View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 工作副本操作状态层，覆盖 FR-ST-04、FR-UP-01、FR-WC-07 的非 UI 部分：update、add、delete、revert、cleanup 的执行状态、结果摘要、二次确认门控与状态刷新。

**架构：** 新增 `WorkingCopyActionsViewModel` 作为 `@MainActor @Observable` 状态对象，依赖新的 `WorkingCopyActionProviding` 协议和既有 `StatusProviding` 协议。`SvnService` 继续负责写操作互斥、认证重试和 CLI 调用；ViewModel 只负责 UI 可观察状态、参数校验、revert 确认门控和成功后的 status 刷新。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
  定义 `WorkingCopyActionProviding`、`WorkingCopyOperation`、`WorkingCopyActionState`、`WorkingCopyActionsViewModel`，并让 `SvnService` 遵循 `WorkingCopyActionProviding`。
- 创建：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`
  覆盖 update 摘要与刷新、add/delete/revert/cleanup 调用、空路径阻断、revert 二次确认、错误状态。
- 创建：`docs/superpowers/plans/2026-07-09-p1-working-copy-actions-view-model.md`
  记录此切片计划。

## 任务 1：update 与 cleanup 状态流

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增 `WorkingCopyActionsViewModelTests`，先覆盖不依赖路径选择的操作：

```swift
@MainActor
func testUpdateStoresSummaryAndRefreshesStatuses() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    actionProvider.updateResult = UpdateSummary(updated: 2, conflicted: 1, revision: Revision(8))
    let statusProvider = FakeStatusProvider(result: .success([
        FileStatus(path: "conflict.swift", itemStatus: .conflicted, revision: Revision(8), isTreeConflict: false)
    ]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.update(paths: ["Sources"], revision: Revision(7))

    XCTAssertEqual(viewModel.state, .updateCompleted(UpdateSummary(updated: 2, conflicted: 1, revision: Revision(8))))
    XCTAssertEqual(viewModel.lastUpdateSummary, UpdateSummary(updated: 2, conflicted: 1, revision: Revision(8)))
    XCTAssertEqual(viewModel.refreshedStatuses.map(\.path), ["conflict.swift"])
    XCTAssertEqual(await actionProvider.recordedCalls(), [
        ActionCall(operation: .update, wc: URL(fileURLWithPath: "/tmp/wc"), paths: ["Sources"], revision: Revision(7), recursive: false)
    ])
}

@MainActor
func testCleanupRunsWithoutPathsAndRefreshesStatuses() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.cleanup()

    XCTAssertEqual(viewModel.state, .completed(.cleanup))
    XCTAssertEqual(await actionProvider.recordedCalls(), [
        ActionCall(operation: .cleanup, wc: URL(fileURLWithPath: "/tmp/wc"), paths: [], revision: nil, recursive: false)
    ])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter WorkingCopyActionsViewModelTests`
预期：编译失败，提示 `WorkingCopyActionsViewModel`、`WorkingCopyActionState` 或 `WorkingCopyOperation` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `WorkingCopyOperation`：`.update/.add/.delete/.revert/.cleanup`。
- `WorkingCopyActionState`：`.idle`、`.running(WorkingCopyOperation)`、`.updateCompleted(UpdateSummary)`、`.completed(WorkingCopyOperation)`、`.confirmationRequired(WorkingCopyOperation, [String])`、`.error(String)`。
- `WorkingCopyActionProviding` 协议：封装 `update/add/delete/revert/cleanup`。
- `WorkingCopyActionsViewModel.update(paths:revision:)`：置 `.running(.update)`，调用 provider，保存 `lastUpdateSummary`，刷新 status，置 `.updateCompleted(summary)`。
- `WorkingCopyActionsViewModel.cleanup()`：置 `.running(.cleanup)`，调用 provider，刷新 status，置 `.completed(.cleanup)`。
- `extension SvnService: WorkingCopyActionProviding {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter WorkingCopyActionsViewModelTests`
预期：update/cleanup 测试 PASS。

## 任务 2：add/delete/revert 路径操作与确认门控

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增路径操作测试：

```swift
@MainActor
func testAddDeleteAndConfirmedRevertUsePathsAndRefreshStatuses() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.add(paths: ["new.swift"])
    await viewModel.delete(paths: ["old.swift"])
    await viewModel.revert(paths: ["changed.swift"], recursive: true, confirmed: true)

    XCTAssertEqual(viewModel.state, .completed(.revert))
    XCTAssertEqual(await actionProvider.recordedCalls(), [
        ActionCall(operation: .add, wc: URL(fileURLWithPath: "/tmp/wc"), paths: ["new.swift"], revision: nil, recursive: false),
        ActionCall(operation: .delete, wc: URL(fileURLWithPath: "/tmp/wc"), paths: ["old.swift"], revision: nil, recursive: false),
        ActionCall(operation: .revert, wc: URL(fileURLWithPath: "/tmp/wc"), paths: ["changed.swift"], revision: nil, recursive: true)
    ])
}

@MainActor
func testRevertRequiresConfirmationBeforeCallingProvider() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.revert(paths: ["changed.swift"], recursive: false, confirmed: false)

    XCTAssertEqual(viewModel.state, .confirmationRequired(.revert, ["changed.swift"]))
    XCTAssertTrue(await actionProvider.recordedCalls().isEmpty)
}

@MainActor
func testPathActionsRejectEmptyPathsBeforeCallingProvider() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.add(paths: [])
    XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))

    await viewModel.delete(paths: [])
    XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))

    await viewModel.revert(paths: [], recursive: false, confirmed: true)
    XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))
    XCTAssertTrue(await actionProvider.recordedCalls().isEmpty)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter WorkingCopyActionsViewModelTests`
预期：编译失败或测试失败，提示路径操作方法缺失或行为不符。

- [x] **步骤 3：编写最少实现代码**

实现：

- `add(paths:)`、`delete(paths:)`、`revert(paths:recursive:confirmed:)`。
- 路径操作若 `paths.isEmpty`，置 `.error("noSelectedPaths")` 并返回。
- `revert` 若 `confirmed == false`，置 `.confirmationRequired(.revert, paths)` 并返回。
- 操作成功后调用 `statusProvider.status(wc:)` 并保存 `refreshedStatuses`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter WorkingCopyActionsViewModelTests`
预期：全部目标测试 PASS。

## 任务 3：错误状态、全量验证与提交

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增错误路径测试：

```swift
@MainActor
func testActionFailureStoresErrorAndDoesNotRefreshStatuses() async {
    let actionProvider = FakeWorkingCopyActionProvider()
    actionProvider.addError = SvnError.workingCopyLocked
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = WorkingCopyActionsViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        actionProvider: actionProvider,
        statusProvider: statusProvider
    )

    await viewModel.add(paths: ["new.swift"])

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.workingCopyLocked)))
    XCTAssertTrue(await statusProvider.requestedWorkingCopies().isEmpty)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter WorkingCopyActionsViewModelTests`
预期：测试失败，说明错误路径没有按要求处理。

- [x] **步骤 3：编写最少实现代码**

确保所有 action 方法在 provider 或刷新失败时置 `.error(String(describing: error))`；provider 失败时不刷新 status。

- [x] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/WorkingCopyActionsViewModel.swift Tests/MacSvnCoreTests/WorkingCopyActionsViewModelTests.swift docs/superpowers/plans/2026-07-09-p1-working-copy-actions-view-model.md
git commit -m "feat: add P1 working copy actions view model"
```
