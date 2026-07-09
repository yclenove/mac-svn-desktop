# P1 Changes View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 变更列表核心状态层，覆盖 FR-ST-01/02/03 的非 UI 部分：从 `SvnService.status` 刷新变更，提供平铺/树形数据、状态筛选和文件名搜索。

**架构：** 新增 `ChangesViewModel` 作为 `@MainActor @Observable` 状态对象，依赖轻量 `StatusProviding` 协议以便测试和后续 SwiftUI 注入 `SvnService`。新增 `FileStatusNode`、`StatusFilter`、`ChangesDisplayMode` 与 `FileStatusListBuilder`，把纯数据转换逻辑和异步刷新分开测试。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  让 `ItemStatus` 支持 `Hashable`，方便状态过滤集合和 UI 选择状态。
- 创建：`Sources/MacSvnCore/ViewModels/ChangesViewModel.swift`
  定义 `StatusProviding`、`ChangesDisplayMode`、`StatusFilter`、`ChangesViewState`、`FileStatusNode`、`FileStatusListBuilder`、`ChangesViewModel`。
- 创建：`Tests/MacSvnCoreTests/ChangesViewModelTests.swift`
  覆盖平铺筛选、树形分组/聚合、异步刷新成功与失败。
- 创建：`docs/superpowers/plans/2026-07-09-p1-changes-view-model.md`
  记录此切片计划。

## 任务 1：状态树与筛选纯逻辑

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/ViewModels/ChangesViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/ChangesViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `ChangesViewModelTests`，先覆盖纯逻辑：

```swift
func testFlatFilteringSupportsStatusAndCaseInsensitiveSearch() {
    let statuses = sampleStatuses()

    let filtered = FileStatusListBuilder.flatEntries(
        from: statuses,
        filter: .items([.modified, .conflicted]),
        searchText: "view"
    )

    XCTAssertEqual(filtered.map(\.path), ["Sources/View.swift"])
}

func testTreeGroupsNestedPathsAndAggregatesConflictStatus() throws {
    let tree = FileStatusListBuilder.tree(from: sampleStatuses())

    XCTAssertEqual(Set(tree.map(\.name)), Set(["README.md", "Sources", "scratch.tmp"]))
    let sources = try XCTUnwrap(tree.first { $0.name == "Sources" })
    XCTAssertTrue(sources.isDirectory)
    XCTAssertEqual(sources.itemStatus, .conflicted)
    XCTAssertEqual(sources.children.map(\.name), ["Model.swift", "View.swift"])
}
```

`sampleStatuses()` 应包含：

```swift
[
    FileStatus(path: "Sources/View.swift", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
    FileStatus(path: "Sources/Model.swift", itemStatus: .conflicted, revision: Revision(2), isTreeConflict: false),
    FileStatus(path: "README.md", itemStatus: .added, revision: Revision(3), isTreeConflict: false),
    FileStatus(path: "scratch.tmp", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
]
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter ChangesViewModelTests`
预期：编译失败，提示 `FileStatusListBuilder`、`StatusFilter` 或 `FileStatusNode` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `ItemStatus: Hashable`
- `StatusFilter`：`.all`、`.items(Set<ItemStatus>)`、`.conflicts`
- `FileStatusNode`：`id/name/path/itemStatus/isDirectory/fileStatus/children`
- `FileStatusListBuilder.flatEntries(from:filter:searchText:)`
- `FileStatusListBuilder.tree(from:)`

树形构建按路径前缀分组，目录节点状态聚合规则：子级存在 `.conflicted` 或 `isTreeConflict` 时目录为 `.conflicted`；否则使用第一个优先级最高的子状态（modified/added/deleted/missing/replaced/unversioned/ignored/external/normal）。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter ChangesViewModelTests`
预期：纯逻辑测试 PASS。

## 任务 2：ChangesViewModel 异步刷新

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/ChangesViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/ChangesViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `ChangesViewModelTests` 中新增：

```swift
@MainActor
func testRefreshLoadsStatusesAndExposesVisibleFlatEntries() async {
    let provider = FakeStatusProvider(result: .success(sampleStatuses()))
    let viewModel = ChangesViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statusProvider: provider
    )
    viewModel.displayMode = .flat
    viewModel.filter = .items([.modified])

    await viewModel.refresh()

    XCTAssertEqual(viewModel.state, .loaded)
    XCTAssertEqual(viewModel.visibleFlatEntries.map(\.path), ["Sources/View.swift"])
    XCTAssertEqual(await provider.requestedWorkingCopies(), [URL(fileURLWithPath: "/tmp/wc")])
}

@MainActor
func testRefreshStoresErrorStateWhenStatusProviderFails() async {
    let provider = FakeStatusProvider(result: .failure(SvnError.authentication))
    let viewModel = ChangesViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        statusProvider: provider
    )

    await viewModel.refresh()

    XCTAssertEqual(viewModel.state, .error("authentication"))
    XCTAssertTrue(viewModel.visibleFlatEntries.isEmpty)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter ChangesViewModelTests`
预期：编译失败或测试失败，提示 `ChangesViewModel`/`StatusProviding`/`ChangesViewState` 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：

- `public protocol StatusProviding: Sendable { func status(wc: URL) async throws -> [FileStatus] }`
- `extension SvnService: StatusProviding {}`
- `@MainActor @Observable public final class ChangesViewModel`
- `state` 初始 `.idle`，`refresh()` 时先 `.loading`，成功后保存 `entries` 并置 `.loaded`，失败后清空 entries 并置 `.error(String(describing: error))`
- `visibleFlatEntries` 与 `visibleTreeEntries` 基于当前 `filter`、`searchText` 计算。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter ChangesViewModelTests`
预期：`ChangesViewModelTests` 全部 PASS。

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
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/ViewModels/ChangesViewModel.swift Tests/MacSvnCoreTests/ChangesViewModelTests.swift docs/superpowers/plans/2026-07-09-p1-changes-view-model.md
git commit -m "feat: add P1 changes view model"
```
