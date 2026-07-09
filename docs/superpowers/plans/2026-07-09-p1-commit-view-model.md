# P1 Commit View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 提交对话框核心状态层，覆盖 FR-CM-01/02/05 的非 UI 部分：候选文件勾选、提交说明校验、提交成功 revision 记录与状态自动刷新。

**架构：** 新增 `CommitViewModel` 作为 `@MainActor @Observable` 状态对象，依赖 `CommitProviding` 与既有 `StatusProviding` 协议。候选文件与默认选择由纯函数 `CommitSelectionPolicy` 处理；实际提交继续走 `SvnService.commit`，冲突阻断和认证重试仍由服务层负责。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
  定义 `CommitProviding`、`CommitViewState`、`CommitSelectionPolicy`、`CommitViewModel`，并让 `SvnService` 遵循 `CommitProviding`。
- 创建：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`
  覆盖默认候选/选中策略、空说明阻止提交、提交成功后刷新 status。
- 创建：`docs/superpowers/plans/2026-07-09-p1-commit-view-model.md`
  记录此切片计划。

## 任务 1：候选文件与默认选择策略

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `CommitViewModelTests`，先覆盖纯选择策略：

```swift
func testCommitCandidatesIncludeVersionedChangesAndConflictsOnly() {
    let candidates = CommitSelectionPolicy.candidates(from: sampleStatuses())

    XCTAssertEqual(candidates.map(\.path), [
        "modified.swift",
        "added.swift",
        "deleted.swift",
        "replaced.swift",
        "conflict.swift"
    ])
}

func testDefaultSelectionExcludesConflictsAndUnsupportedStatuses() {
    let selected = CommitSelectionPolicy.defaultSelectedPaths(from: sampleStatuses())

    XCTAssertEqual(selected, Set([
        "modified.swift",
        "added.swift",
        "deleted.swift",
        "replaced.swift"
    ]))
}
```

`sampleStatuses()` 应包含 `.modified`、`.added`、`.deleted`、`.replaced`、`.conflicted`、`.unversioned`、`.ignored`、`.missing`、`.normal`。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter CommitViewModelTests`
预期：编译失败，提示 `CommitSelectionPolicy` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `CommitSelectionPolicy.candidates(from:)`：返回 `.modified/.added/.deleted/.replaced/.conflicted` 或 `isTreeConflict == true` 的状态，保持原顺序。
- `CommitSelectionPolicy.defaultSelectedPaths(from:)`：返回 candidates 中非 `.conflicted` 且非 tree conflict 的路径集合。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter CommitViewModelTests`
预期：选择策略测试 PASS。

## 任务 2：CommitViewModel 提交与刷新

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CommitViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/CommitViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `CommitViewModelTests` 中新增：

```swift
@MainActor
func testCommitUsesSelectedPathsMessageAuthAndRefreshesStatuses() async {
    let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
    let statusProvider = FakeStatusProvider(result: .success([
        FileStatus(path: "remaining.swift", itemStatus: .modified, revision: Revision(42), isTreeConflict: false)
    ]))
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: commitProvider,
        statusProvider: statusProvider
    )
    viewModel.message = "修复：登录超时"
    viewModel.setSelected(false, for: "deleted.swift")

    await viewModel.commit(auth: Credential(username: "u", password: "p"))

    XCTAssertEqual(viewModel.state, .committed(Revision(42)))
    XCTAssertEqual(viewModel.committedRevision, Revision(42))
    XCTAssertEqual(viewModel.refreshedStatuses.map(\.path), ["remaining.swift"])
    XCTAssertEqual(await commitProvider.recordedCalls(), [
        CommitCall(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["modified.swift", "added.swift", "replaced.swift"],
            message: "修复：登录超时",
            auth: Credential(username: "u", password: "p")
        )
    ])
    XCTAssertEqual(await statusProvider.requestedWorkingCopies(), [URL(fileURLWithPath: "/tmp/wc")])
}

@MainActor
func testCommitRejectsEmptyMessageBeforeCallingProvider() async {
    let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
    let statusProvider = FakeStatusProvider(result: .success([]))
    let viewModel = CommitViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statuses: sampleStatuses(),
        commitProvider: commitProvider,
        statusProvider: statusProvider
    )
    viewModel.message = "   "

    await viewModel.commit(auth: nil)

    XCTAssertEqual(viewModel.state, .error("emptyCommitMessage"))
    XCTAssertTrue((await commitProvider.recordedCalls()).isEmpty)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter CommitViewModelTests`
预期：编译失败或测试失败，提示 `CommitViewModel`/`CommitProviding`/`CommitViewState` 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `public protocol CommitProviding: Sendable { func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision }`
- `extension SvnService: CommitProviding {}`
- `@MainActor @Observable public final class CommitViewModel`
- 初始 `candidateStatuses` 来自 `CommitSelectionPolicy.candidates`，`selectedPaths` 来自默认选择。
- `orderedSelectedPaths` 按 `candidateStatuses` 原顺序输出。
- `canCommit` 要求 message trim 后非空、selected 非空、state 非 `.committing`。
- `commit(auth:)`：空说明置 `.error("emptyCommitMessage")`；无选中文件置 `.error("noSelectedPaths")`；成功后保存 `committedRevision`，调用 `statusProvider.status(wc:)` 保存 `refreshedStatuses`，最后置 `.committed(revision)`；失败置 `.error(String(describing: error))`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter CommitViewModelTests`
预期：`CommitViewModelTests` 全部 PASS。

## 任务 3：全量验证与提交

- [ ] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CommitViewModel.swift Tests/MacSvnCoreTests/CommitViewModelTests.swift docs/superpowers/plans/2026-07-09-p1-commit-view-model.md
git commit -m "feat: add P1 commit view model"
```
