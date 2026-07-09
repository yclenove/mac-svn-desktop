# P3 Merge Editor Shortcuts Dirty State 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 P3 合并编辑器 ViewModel 的 FR-CF-05 与 FR-CF-08：整文件采用 Mine/Theirs 快捷 resolve、未保存编辑状态、离开警告判断与放弃编辑。

**架构：** 在现有 `MergeEditorViewModel` 上增量扩展，不改动 `MergeEngine` 和底层 SVN 命令。新增 `WholeFileConflictResolving` 协议，让 ViewModel 通过 provider 调用 `ConflictService.resolveWholeFile(_:wc:accept:)`；dirty 状态由 ViewModel 在加载、逐块处理、保存、整文件 resolve、放弃编辑时维护，供后续 SwiftUI/NSWindow 关闭拦截绑定。

**技术栈：** Swift 6.1、Observation、XCTest concurrency、已有 `ConflictService` / `MergeEditorViewModel` / `ResolveAccept`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
  - 新增 `WholeFileConflictResolving` 协议。
  - 将 provider 类型扩展为 `TextConflictLoading & ConflictResolutionSaving & WholeFileConflictResolving`。
  - 新增 `hasUnsavedChanges`、`shouldWarnBeforeClose`、`discardEdits()`。
  - 新增 `resolveWholeFile(accept:)` 及 Mine/Theirs 便捷包装方法。
- 修改：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`
  - Fake provider 记录 whole-file resolve 调用。
  - 添加 whole-file 快捷操作测试。
  - 添加 dirty/关闭警告/放弃编辑测试。
- 创建：`docs/superpowers/plans/2026-07-09-p3-merge-editor-shortcuts-dirty-state.md`
  - 记录此增量切片计划。

## 任务 1：整文件 Mine/Theirs 快捷 resolve

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEditorViewModelTests` 中新增：

```swift
@MainActor
func testResolveWholeFileMineForwardsMineFullAndMarksSaved() async {
    let conflict = textConflict()
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "base\n",
        mine: "mine\n",
        theirs: "theirs\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: conflict, wc: wc)
    viewModel.resolveCurrent(.takeMine)
    await viewModel.resolveWholeFileMine()

    XCTAssertEqual(viewModel.state, .saved)
    XCTAssertFalse(viewModel.hasUnsavedChanges)
    XCTAssertFalse(viewModel.shouldWarnBeforeClose)
    let calls = await provider.recordedWholeFileResolveCalls()
    XCTAssertEqual(calls, [
        MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: .mineFull)
    ])
}

@MainActor
func testResolveWholeFileTheirsForwardsTheirsFullAndMarksSaved() async {
    let conflict = textConflict()
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "base\n",
        mine: "mine\n",
        theirs: "theirs\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: conflict, wc: wc)
    await viewModel.resolveWholeFileTheirs()

    XCTAssertEqual(viewModel.state, .saved)
    let calls = await provider.recordedWholeFileResolveCalls()
    XCTAssertEqual(calls, [
        MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: .theirsFull)
    ])
}

@MainActor
func testResolveWholeFileFailureStoresErrorAndKeepsDirtyState() async {
    let provider = FakeMergeEditorProvider(
        loadResult: .success((base: "base\n", mine: "mine\n", theirs: "theirs\n")),
        wholeFileResolveError: SvnError.network(detail: "offline")
    )
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.resolveCurrent(.takeMine)
    XCTAssertTrue(viewModel.hasUnsavedChanges)

    await viewModel.resolveWholeFileMine()

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertTrue(viewModel.hasUnsavedChanges)
    XCTAssertTrue(viewModel.shouldWarnBeforeClose)
}
```

同时扩展测试辅助类型：

```swift
struct MergeEditorWholeFileResolveCall: Equatable {
    let conflict: ConflictInfo
    let wc: URL
    let accept: ResolveAccept
}

actor FakeMergeEditorProvider: TextConflictLoading, ConflictResolutionSaving, WholeFileConflictResolving {
    let wholeFileResolveError: Error?
    private var wholeFileResolveCalls: [MergeEditorWholeFileResolveCall] = []

    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws {
        if let wholeFileResolveError {
            throw wholeFileResolveError
        }
        wholeFileResolveCalls.append(MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: accept))
    }

    func recordedWholeFileResolveCalls() -> [MergeEditorWholeFileResolveCall] {
        wholeFileResolveCalls
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEditorViewModelTests/testResolveWholeFile"
```

预期：编译失败，提示 `WholeFileConflictResolving`、`resolveWholeFileMine()`、`resolveWholeFileTheirs()`、`hasUnsavedChanges` 或 `shouldWarnBeforeClose` 未定义。

- [ ] **步骤 3：实现最少代码**

在 `MergeEditorViewModel.swift` 中实现：

```swift
public protocol WholeFileConflictResolving: Sendable {
    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws
}
```

将 provider 类型改为：

```swift
private let provider: any TextConflictLoading & ConflictResolutionSaving & WholeFileConflictResolving

public init(provider: any TextConflictLoading & ConflictResolutionSaving & WholeFileConflictResolving) {
    self.provider = provider
}
```

新增状态属性：

```swift
public private(set) var hasUnsavedChanges = false

public var shouldWarnBeforeClose: Bool {
    hasUnsavedChanges
}
```

在 `load(conflict:wc:)` 开始与成功/失败路径确保 `hasUnsavedChanges = false`。

在 `resolveConflict(atConflictIndex:resolution:)` 成功替换 block 后设置 `hasUnsavedChanges = true`。

新增整文件方法：

```swift
public func resolveWholeFileMine() async {
    await resolveWholeFile(accept: .mineFull)
}

public func resolveWholeFileTheirs() async {
    await resolveWholeFile(accept: .theirsFull)
}

public func resolveWholeFile(accept: ResolveAccept) async {
    guard let conflict, let workingCopy else {
        state = .error("missingConflict")
        return
    }

    state = .saving

    do {
        try await provider.resolveWholeFile(conflict, wc: workingCopy, accept: accept)
        hasUnsavedChanges = false
        state = .saved
    } catch {
        state = .error(String(describing: error))
    }
}
```

让 `ConflictService` 遵循新协议：

```swift
extension ConflictService: WholeFileConflictResolving {}
```

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "MergeEditorViewModelTests/testResolveWholeFile"
```

预期：3 个 whole-file 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift docs/superpowers/plans/2026-07-09-p3-merge-editor-shortcuts-dirty-state.md
git commit -m "feat: add P3 merge editor whole-file shortcuts"
```

## 任务 2：dirty 状态、关闭警告与放弃编辑

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEditorViewModelTests` 中新增：

```swift
@MainActor
func testDirtyStateTracksLoadResolveSaveAndDiscard() async {
    let conflict = textConflict()
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "a\nbase\nz\n",
        mine: "a\nmine\nz\n",
        theirs: "a\ntheirs\nz\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: conflict, wc: wc)
    XCTAssertFalse(viewModel.hasUnsavedChanges)
    XCTAssertFalse(viewModel.shouldWarnBeforeClose)

    viewModel.resolveCurrent(.manual(lines: ["manual"]))
    XCTAssertTrue(viewModel.hasUnsavedChanges)
    XCTAssertTrue(viewModel.shouldWarnBeforeClose)

    viewModel.discardEdits()
    XCTAssertFalse(viewModel.hasUnsavedChanges)
    XCTAssertFalse(viewModel.shouldWarnBeforeClose)
    XCTAssertEqual(viewModel.state, .loaded)
    XCTAssertEqual(viewModel.unresolvedConflictCount, 1)

    viewModel.resolveCurrent(.takeTheirs)
    await viewModel.saveResolved()

    XCTAssertEqual(viewModel.state, .saved)
    XCTAssertFalse(viewModel.hasUnsavedChanges)
    XCTAssertFalse(viewModel.shouldWarnBeforeClose)
}
```

新增保存失败的 dirty 覆盖：

```swift
@MainActor
func testSaveFailureKeepsUnsavedChanges() async {
    let provider = FakeMergeEditorProvider(
        loadResult: .success((base: "base\n", mine: "mine\n", theirs: "theirs\n")),
        saveError: SvnError.network(detail: "offline")
    )
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.resolveCurrent(.takeMine)
    await viewModel.saveResolved()

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertTrue(viewModel.hasUnsavedChanges)
    XCTAssertTrue(viewModel.shouldWarnBeforeClose)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEditorViewModelTests/testDirtyState|MergeEditorViewModelTests/testSaveFailureKeepsUnsavedChanges"
```

预期：编译失败或断言失败，提示 `discardEdits()` 未定义，或 dirty 状态未维护。

- [ ] **步骤 3：实现最少代码**

在 `MergeEditorViewModel` 中新增原始 block 快照：

```swift
private var loadedBlocksSnapshot: [MergeBlock] = []
```

在 load 成功后设置：

```swift
loadedBlocksSnapshot = blocks
hasUnsavedChanges = false
```

在 load 开始和失败时清空：

```swift
loadedBlocksSnapshot = []
hasUnsavedChanges = false
```

新增放弃编辑：

```swift
public func discardEdits() {
    blocks = loadedBlocksSnapshot
    currentConflictIndex = conflictBlockIndices.isEmpty ? 0 : min(currentConflictIndex, conflictBlockIndices.count - 1)
    hasUnsavedChanges = false
    if case .error = state {
        state = .loaded
    }
}
```

调整保存成功：

```swift
try await provider.saveResolution(conflict, wc: workingCopy, mergedText: mergedText)
hasUnsavedChanges = false
state = .saved
```

保存失败不清 dirty。`resolveConflict(atConflictIndex:resolution:)` 的无效 index 分支不改变 dirty。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEditorViewModelTests
```

预期：`MergeEditorViewModelTests` 全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift
git commit -m "feat: track P3 merge editor unsaved edits"
```

## 任务 3：回归验证

**文件：**
- 修改：无新代码，验证当前切片不会破坏已有 P1/P2/P3 能力。

- [ ] **步骤 1：运行 P3 相关目标测试**

运行：

```bash
swift test --filter "MergeEditorViewModelTests|ConflictServiceTests/testResolveWholeFile|SvnCliBackendIntegrationTests/testTextConflictResolveWholeFile"
```

预期：相关测试全部 PASS。

- [ ] **步骤 2：运行全量测试**

运行：

```bash
swift test
```

预期：全部测试 PASS。

- [ ] **步骤 3：运行空白字符检查**

运行：

```bash
git diff --check
git diff HEAD^ HEAD --check
```

预期：无输出。

- [ ] **步骤 4：确认工作区状态**

运行：

```bash
git status --short --branch
```

预期：在最新提交后工作区干净。

## 自检

- 覆盖 FR-CF-05：`resolveWholeFileMine()` 调用 `.mineFull`，`resolveWholeFileTheirs()` 调用 `.theirsFull`，成功后状态为 `.saved` 且不再提示未保存。
- 覆盖 FR-CF-08 的 ViewModel 层：加载后不脏，逐块处理/手动编辑后变脏，保存成功或放弃编辑后不脏，保存失败仍提醒。
- 不改变 `ConflictService.resolveWholeFile` 的 SVN 语义，不重复实现底层 resolve。
- 不触碰 SwiftUI UI；关闭拦截窗口和实际按钮绑定留给后续 UI shell 切片。
