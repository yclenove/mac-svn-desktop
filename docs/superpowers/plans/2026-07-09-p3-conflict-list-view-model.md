# P3 Conflict List ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P3 冲突列表的非 UI 状态层，覆盖 FR-CF-01 的核心交互：加载工作副本全部冲突、按文本/树/属性分类统计、搜索过滤、选择当前冲突，为后续 SwiftUI `ConflictListView` 和 `MergeEditorView` 打开流程提供稳定绑定。

**架构：** 新增 `ConflictListViewModel`，保持现有 `@MainActor @Observable` ViewModel 风格，通过轻量 `ConflictListing` 协议依赖 `ConflictService`。ViewModel 不直接读取文件、不执行 resolve，只管理列表状态、摘要、过滤和选择；文本冲突进入 `MergeEditorViewModel`，整文件 resolve/tree conflict 操作留给后续切片。

**技术栈：** Swift 6.1、Observation、XCTest concurrency、已有 `ConflictService` / `ConflictInfo` 模型。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/ConflictListViewModel.swift`
  定义 `ConflictListing`、`ConflictListState`、`ConflictKindFilter`、`ConflictListSummary`、`ConflictListViewModel`，并让 `ConflictService` 遵循 `ConflictListing`。
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  让 `ConflictKind` 遵循 `Hashable`，支持 `ConflictKindFilter.kinds(Set<ConflictKind>)`。
- 创建：`Tests/MacSvnCoreTests/ConflictListViewModelTests.swift`
  覆盖加载成功、摘要计数、搜索/分类过滤、选择当前冲突、加载失败清空状态。
- 创建：`docs/superpowers/plans/2026-07-09-p3-conflict-list-view-model.md`
  记录此切片计划。

## 任务 1：加载冲突并生成摘要

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/ViewModels/ConflictListViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/ConflictListViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `ConflictListViewModelTests`，先覆盖加载和摘要：

```swift
import XCTest
@testable import MacSvnCore

final class ConflictListViewModelTests: XCTestCase {
    @MainActor
    func testLoadConflictsStoresEntriesSummaryAndSelectsFirstConflict() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let conflicts = [
            conflict(path: "README.txt", kind: .text),
            conflict(path: "src/main.swift", kind: .tree),
            conflict(path: "project.pbxproj", kind: .property)
        ]
        let provider = FakeConflictListProvider(result: .success(conflicts))
        let viewModel = ConflictListViewModel(workingCopy: wc, provider: provider)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.conflicts, conflicts)
        XCTAssertEqual(viewModel.visibleConflicts, conflicts)
        XCTAssertEqual(viewModel.summary, ConflictListSummary(total: 3, text: 1, tree: 1, property: 1, unknown: 0))
        XCTAssertEqual(viewModel.selectedConflict, conflicts[0])
        let workingCopies = await provider.recordedWorkingCopies()
        XCTAssertEqual(workingCopies, [wc])
    }
}

private func conflict(path: String, kind: ConflictKind) -> ConflictInfo {
    ConflictInfo(path: path, kind: kind, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)
}
```

测试文件同时提供 fake provider：

```swift
private actor FakeConflictListProvider: ConflictListing {
    let result: Result<[ConflictInfo], Error>
    private var workingCopies: [URL] = []

    init(result: Result<[ConflictInfo], Error>) {
        self.result = result
    }

    func conflicts(wc: URL) async throws -> [ConflictInfo] {
        workingCopies.append(wc)
        return try result.get()
    }

    func recordedWorkingCopies() -> [URL] {
        workingCopies
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter ConflictListViewModelTests/testLoadConflictsStoresEntriesSummaryAndSelectsFirstConflict
```

预期：编译失败，提示 `ConflictListViewModel`、`ConflictListing` 或 `ConflictListSummary` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

```swift
public protocol ConflictListing: Sendable {
    func conflicts(wc: URL) async throws -> [ConflictInfo]
}

public enum ConflictListState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public enum ConflictKindFilter: Equatable, Sendable {
    case all
    case kinds(Set<ConflictKind>)
}

public struct ConflictListSummary: Equatable, Sendable {
    public let total: Int
    public let text: Int
    public let tree: Int
    public let property: Int
    public let unknown: Int
}
```

`ConflictListViewModel.refresh()` 行为：
- 修改 `ConflictKind` 为 `Hashable`；
- 置 `.loading`；
- 调用 `provider.conflicts(wc:)`；
- 成功后保存 `conflicts`，若当前没有有效选择则选中第一条冲突，置 `.loaded`；
- `summary` 按 `ConflictInfo.kind` 统计；
- `visibleConflicts` 初始等于全部冲突；
- 让 `ConflictService` 遵循 `ConflictListing`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter ConflictListViewModelTests/testLoadConflictsStoresEntriesSummaryAndSelectsFirstConflict
```

预期：目标测试 PASS。

## 任务 2：搜索、分类过滤与选择

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/ConflictListViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/ConflictListViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `ConflictListViewModelTests` 中新增：

```swift
@MainActor
func testKindFilterAndCaseInsensitiveSearchProduceVisibleConflicts() async {
    let provider = FakeConflictListProvider(result: .success([
        conflict(path: "README.txt", kind: .text),
        conflict(path: "Sources/Login.swift", kind: .text),
        conflict(path: "Sources/Tree.swift", kind: .tree)
    ]))
    let viewModel = ConflictListViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        provider: provider
    )

    await viewModel.refresh()
    viewModel.kindFilter = .kinds([.text])
    viewModel.searchText = "login"

    XCTAssertEqual(viewModel.visibleConflicts, [
        conflict(path: "Sources/Login.swift", kind: .text)
    ])
}

@MainActor
func testSelectConflictByPathUpdatesSelectionAndIgnoresMissingPath() async {
    let conflicts = [
        conflict(path: "README.txt", kind: .text),
        conflict(path: "Sources/Tree.swift", kind: .tree)
    ]
    let provider = FakeConflictListProvider(result: .success(conflicts))
    let viewModel = ConflictListViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        provider: provider
    )

    await viewModel.refresh()
    viewModel.selectConflict(path: "Sources/Tree.swift")
    XCTAssertEqual(viewModel.selectedConflict, conflicts[1])

    viewModel.selectConflict(path: "missing.txt")
    XCTAssertEqual(viewModel.selectedConflict, conflicts[1])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "ConflictListViewModelTests/testKindFilter|ConflictListViewModelTests/testSelect"
```

预期：新增过滤或选择 API 未实现导致失败。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `public var kindFilter: ConflictKindFilter = .all`
- `public var searchText = ""`
- `public private(set) var selectedConflictPath: String?`
- `public var selectedConflict: ConflictInfo?`
- `public var visibleConflicts: [ConflictInfo]`
- `public func selectConflict(path: String)`

过滤规则：
- `.all` 保留所有冲突；
- `.kinds(set)` 只保留 `set.contains(conflict.kind)` 的冲突；
- 搜索文本 trim 后转小写，匹配完整 `path.lowercased()`，不是只匹配最后路径组件；
- `selectConflict(path:)` 只接受当前 `conflicts` 中存在的 path，缺失时保留原选择。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter ConflictListViewModelTests
```

预期：当前全部 `ConflictListViewModelTests` PASS。

## 任务 3：错误状态与选择保留

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/ConflictListViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/ConflictListViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

新增：

```swift
@MainActor
func testRefreshFailureClearsConflictsSelectionAndStoresError() async {
    let provider = FakeConflictListProvider(result: .failure(SvnError.network(detail: "offline")))
    let viewModel = ConflictListViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        provider: provider
    )

    await viewModel.refresh()

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.conflicts, [])
    XCTAssertEqual(viewModel.summary, ConflictListSummary())
    XCTAssertNil(viewModel.selectedConflict)
}

@MainActor
func testRefreshPreservesSelectionWhenPathStillExistsAndFallsBackWhenMissing() async {
    let first = [
        conflict(path: "README.txt", kind: .text),
        conflict(path: "Sources/Tree.swift", kind: .tree)
    ]
    let second = [
        conflict(path: "README.txt", kind: .text),
        conflict(path: "Other.txt", kind: .text)
    ]
    let provider = FakeConflictListProvider(results: [
        .success(first),
        .success(second)
    ])
    let viewModel = ConflictListViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        provider: provider
    )

    await viewModel.refresh()
    viewModel.selectConflict(path: "Sources/Tree.swift")
    await viewModel.refresh()

    XCTAssertEqual(viewModel.selectedConflict, second[0])
}
```

为支持第二个测试，将 fake provider 改为队列式：

```swift
private actor FakeConflictListProvider: ConflictListing {
    private var results: [Result<[ConflictInfo], Error>]
    private var workingCopies: [URL] = []

    init(result: Result<[ConflictInfo], Error>) {
        self.results = [result]
    }

    init(results: [Result<[ConflictInfo], Error>]) {
        self.results = results
    }

    func conflicts(wc: URL) async throws -> [ConflictInfo] {
        workingCopies.append(wc)
        guard !results.isEmpty else {
            return []
        }
        return try results.removeFirst().get()
    }

    func recordedWorkingCopies() -> [URL] {
        workingCopies
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "ConflictListViewModelTests/testRefresh"
```

预期：错误状态或选择保留行为失败。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `ConflictListSummary()` 默认初始化为全 0；
- refresh 成功后，如果 `selectedConflictPath` 仍存在则保留，否则选择第一条冲突；
- refresh 失败时清空 `conflicts` 与 `selectedConflictPath`，置 `.error(String(describing: error))`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter ConflictListViewModelTests
```

预期：全部 `ConflictListViewModelTests` PASS。

## 任务 4：全量验证与提交

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行验证**

运行：

```bash
swift test --filter ConflictListViewModelTests
swift test
git diff --check
```

预期：目标测试与全量测试全部 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

运行：

```bash
git add Sources/MacSvnCore/ViewModels/ConflictListViewModel.swift Tests/MacSvnCoreTests/ConflictListViewModelTests.swift docs/superpowers/plans/2026-07-09-p3-conflict-list-view-model.md
git diff --cached --check
git commit -m "feat: add P3 conflict list view model"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：暂存区检查无输出，提交后补丁检查无输出，工作区干净。
