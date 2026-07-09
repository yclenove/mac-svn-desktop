# P1 Log View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 日志视图核心状态层，覆盖 FR-LG-01/02 的非 UI 部分：按 WC/路径加载提交历史、展示 verbose 变更路径、按批次加载更多。

**架构：** 新增 `LogViewModel` 作为 `@MainActor @Observable` 状态对象，依赖新的 `LogProviding` 协议。`SvnService.log` 与 `LogXMLParser` 已存在，ViewModel 只负责首屏加载、分页游标、错误状态和 hasMore 管理。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/LogViewModel.swift`
  定义 `LogProviding`、`LogViewState`、`LogViewModel`，并让 `SvnService` 遵循 `LogProviding`。
- 创建：`Tests/MacSvnCoreTests/LogViewModelTests.swift`
  覆盖首屏加载、加载更多游标、短页结束、错误状态与未初始化加载保护。
- 创建：`docs/superpowers/plans/2026-07-09-p1-log-view-model.md`
  记录此切片计划。

## 任务 1：首屏日志加载

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/LogViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/LogViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `LogViewModelTests`，先覆盖首屏加载：

```swift
@MainActor
func testInitialLoadUsesTargetStartRevisionBatchAndVerboseFlag() async {
    let entries = [logEntry(Revision(9)), logEntry(Revision(8))]
    let provider = FakeLogProvider(results: [.success(entries)])
    let viewModel = LogViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        target: "Sources",
        batchSize: 2,
        logProvider: provider
    )

    await viewModel.loadInitial(from: Revision(9))

    XCTAssertEqual(viewModel.state, .loaded)
    XCTAssertEqual(viewModel.entries.map(\.revision), [Revision(9), Revision(8)])
    XCTAssertTrue(viewModel.hasMore)
    XCTAssertEqual(await provider.recordedCalls(), [
        LogCall(wc: URL(fileURLWithPath: "/tmp/wc"), target: "Sources", from: Revision(9), batch: 2, verbose: true)
    ])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter LogViewModelTests`
预期：编译失败，提示 `LogViewModel`、`LogViewState` 或 `LogProviding` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `LogProviding` 协议：`log(wc:target:from:batch:verbose:)`。
- `LogViewState`：`.idle/.loading/.loadingMore/.loaded/.error(String)`。
- `LogViewModel.loadInitial(from:)`：清空旧 entries，置 `.loading`，调用 provider（verbose 固定为 true），保存 entries，基于最小 revision 设置下一页游标，置 `.loaded`。
- `extension SvnService: LogProviding {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter LogViewModelTests`
预期：首屏加载测试 PASS。

## 任务 2：加载更多与结束判定

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/LogViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/LogViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增分页测试：

```swift
@MainActor
func testLoadMoreStartsBeforeLowestLoadedRevisionAndStopsOnShortPage() async {
    let provider = FakeLogProvider(results: [
        .success([logEntry(Revision(10)), logEntry(Revision(9))]),
        .success([logEntry(Revision(8))])
    ])
    let viewModel = LogViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        target: ".",
        batchSize: 2,
        logProvider: provider
    )

    await viewModel.loadInitial(from: Revision(10))
    await viewModel.loadMore()

    XCTAssertEqual(viewModel.entries.map(\.revision), [Revision(10), Revision(9), Revision(8)])
    XCTAssertFalse(viewModel.hasMore)
    XCTAssertEqual(await provider.recordedCalls().map(\.from), [Revision(10), Revision(8)])
}

@MainActor
func testLoadMoreDoesNothingBeforeInitialLoadOrAfterEndReached() async {
    let provider = FakeLogProvider(results: [])
    let viewModel = LogViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        target: ".",
        batchSize: 2,
        logProvider: provider
    )

    await viewModel.loadMore()

    XCTAssertEqual(viewModel.state, .idle)
    XCTAssertTrue(await provider.recordedCalls().isEmpty)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter LogViewModelTests`
预期：编译失败或测试失败，提示 `loadMore` 行为缺失。

- [x] **步骤 3：编写最少实现代码**

实现：

- `hasMore` 与 `nextFromRevision`。
- `loadMore()`：若无下一页或 `hasMore == false` 直接返回；否则置 `.loadingMore`，从 `nextFromRevision` 拉取并追加。
- 若返回数量小于 `batchSize` 或下一页 revision 小于 0，`hasMore = false`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter LogViewModelTests`
预期：分页测试 PASS。

## 任务 3：错误状态、全量验证与提交

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/LogViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/LogViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增错误路径测试：

```swift
@MainActor
func testInitialLoadFailureStoresErrorAndClearsEntries() async {
    let provider = FakeLogProvider(results: [.failure(SvnError.network(detail: "offline"))])
    let viewModel = LogViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        target: ".",
        batchSize: 2,
        logProvider: provider
    )

    await viewModel.loadInitial(from: Revision(10))

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.entries, [])
    XCTAssertFalse(viewModel.hasMore)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter LogViewModelTests`
预期：错误路径测试失败或编译失败。

- [x] **步骤 3：编写最少实现代码**

确保初始加载失败时清空 entries、`hasMore = false`，并将 state 置为 `.error(String(describing: error))`；加载更多失败时保留已有 entries，并置错误状态。

- [x] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/LogViewModel.swift Tests/MacSvnCoreTests/LogViewModelTests.swift docs/superpowers/plans/2026-07-09-p1-log-view-model.md
git commit -m "feat: add P1 log view model"
```
