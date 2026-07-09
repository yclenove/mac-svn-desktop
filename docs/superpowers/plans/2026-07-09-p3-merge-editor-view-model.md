# P3 Merge Editor ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P3 三路合并编辑器的非 UI 状态层，覆盖 FR-CF-02/03/04/08 的核心交互：加载 base/mine/theirs，生成 `MergeBlock`，冲突块导航，逐块采用/手改，全部解决后保存并 `svn resolve --accept working`。

**架构：** 新增 `MergeEditorViewModel`，保持 `@MainActor @Observable` 的既有 ViewModel 风格，通过 `TextConflictLoading` 与 `ConflictResolutionSaving` 协议依赖 `ConflictService`，通过 `MergeEngine` 做纯算法。ViewModel 不直接接触 svn 后端或文件系统，UI 后续只绑定 `state`、`blocks`、`currentConflictIndex`、`canSaveResolved` 与操作方法。

**技术栈：** Swift 6.1、Observation、XCTest concurrency、已有 `ConflictService` / `MergeEngine`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
  定义 `TextConflictLoading`、`ConflictResolutionSaving`、`MergeEditorState`、`MergeEditorViewModel`，并让 `ConflictService` 遵循依赖协议。
- 创建：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`
  覆盖加载、冲突导航、采用 Mine/Theirs/Both/manual、未解决保存阻断、保存成功调用 provider。
- 创建：`docs/superpowers/plans/2026-07-09-p3-merge-editor-view-model.md`
  记录此切片计划。

## 任务 1：加载文本冲突并生成 blocks

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `MergeEditorViewModelTests`：

```swift
import XCTest
@testable import MacSvnCore

final class MergeEditorViewModelTests: XCTestCase {
    @MainActor
    func testLoadTextConflictBuildsMergeBlocksAndSelectsFirstConflict() async {
        let conflict = textConflict()
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.load(conflict: conflict, wc: wc)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.conflict, conflict)
        XCTAssertEqual(viewModel.workingCopy, wc)
        XCTAssertEqual(viewModel.conflictBlockIndices, [1])
        XCTAssertEqual(viewModel.currentConflictIndex, 0)
        XCTAssertEqual(viewModel.unresolvedConflictCount, 1)
        XCTAssertFalse(viewModel.canSaveResolved)
        XCTAssertEqual(await provider.recordedLoadCalls(), [conflict])
    }
}
```

测试文件同时提供：

```swift
private func textConflict(path: String = "README.txt") -> ConflictInfo {
    ConflictInfo(path: path, kind: .text, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter MergeEditorViewModelTests/testLoadTextConflictBuildsMergeBlocksAndSelectsFirstConflict
```

预期：编译失败，提示 `MergeEditorViewModel` 或依赖协议未定义。

- [ ] **步骤 3：实现最少代码**

实现：
- `TextConflictLoading.loadTextConflict(_:) async throws -> (base: String, mine: String, theirs: String)`。
- `ConflictResolutionSaving.saveResolution(_:wc:mergedText:) async throws`。
- `MergeEditorState`: `.idle`、`.loading`、`.loaded`、`.saving`、`.saved`、`.error(String)`。
- `MergeEditorViewModel.load(conflict:wc:)`：
  - 设置 `.loading`；
  - 调用 provider 加载三方文本；
  - 按 `\n` 切为行，保留是否有结尾换行；
  - 使用 `MergeEngine.merge3` 生成 blocks；
  - 记录 conflict block 下标，默认选择第一个冲突；
  - 成功置 `.loaded`，失败置 `.error(String(describing: error))`。
- `extension ConflictService: TextConflictLoading, ConflictResolutionSaving {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEditorViewModelTests/testLoadTextConflictBuildsMergeBlocksAndSelectsFirstConflict
```

预期：目标测试 PASS。

## 任务 2：冲突导航与 resolution 操作

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

新增：

```swift
@MainActor
func testNavigationMovesAcrossConflictBlocks() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "one\nsame\ntwo\n",
        mine: "mine-one\nsame\nmine-two\n",
        theirs: "theirs-one\nsame\ntheirs-two\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.nextConflict()
    XCTAssertEqual(viewModel.currentConflictIndex, 1)
    viewModel.nextConflict()
    XCTAssertEqual(viewModel.currentConflictIndex, 1)
    viewModel.previousConflict()
    XCTAssertEqual(viewModel.currentConflictIndex, 0)
}

@MainActor
func testResolveCurrentConflictUpdatesBlocksAndSaveReadiness() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "a\nbase\nz\n",
        mine: "a\nmine\nz\n",
        theirs: "a\ntheirs\nz\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.resolveCurrent(.takeMine)

    XCTAssertEqual(viewModel.unresolvedConflictCount, 0)
    XCTAssertTrue(viewModel.canSaveResolved)
    XCTAssertEqual(viewModel.mergedText(), "a\nmine\nz\n")
}

@MainActor
func testManualResolutionAndTakeBothAreAppliedToMergedText() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "a\nbase\nz\n",
        mine: "a\nmine\nz\n",
        theirs: "a\ntheirs\nz\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.resolveCurrent(.takeBoth(mineFirst: false))
    XCTAssertEqual(viewModel.mergedText(), "a\ntheirs\nmine\nz\n")

    viewModel.resolveConflict(atConflictIndex: 0, resolution: .manual(lines: ["manual"]))
    XCTAssertEqual(viewModel.mergedText(), "a\nmanual\nz\n")
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEditorViewModelTests/testNavigation|MergeEditorViewModelTests/testResolve|MergeEditorViewModelTests/testManual"
```

预期：新增方法或行为未实现导致失败。

- [ ] **步骤 3：实现最少代码**

实现：
- `currentConflictIndex`、`currentBlockIndex`、`conflictBlockIndices`。
- `nextConflict()`、`previousConflict()` 边界不越界。
- `resolveCurrent(_:)` 调用 `resolveConflict(atConflictIndex:resolution:)`。
- `resolveConflict(atConflictIndex:resolution:)` 替换对应 `.conflict` block 的 `ConflictHunk.resolution`。
- `unresolvedConflictCount`、`canSaveResolved`。
- `mergedText()`：全部冲突解决后用 `MergeEngine.mergedLines(from:)` 拼接文本，恢复原始结尾换行风格。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEditorViewModelTests
```

预期：当前 `MergeEditorViewModelTests` 全部 PASS。

## 任务 3：保存并 resolve

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

新增：

```swift
@MainActor
func testSaveBlocksWhenConflictsRemain() async {
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "base\n",
        mine: "mine\n",
        theirs: "theirs\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    await viewModel.saveResolved()

    XCTAssertEqual(viewModel.state, .error("unresolvedConflicts"))
    XCTAssertTrue(await provider.recordedSaveCalls().isEmpty)
}

@MainActor
func testSaveResolvedWritesMergedTextThroughProvider() async {
    let conflict = textConflict()
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeMergeEditorProvider(loadResult: .success((
        base: "base\n",
        mine: "mine\n",
        theirs: "theirs\n"
    )))
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: conflict, wc: wc)
    viewModel.resolveCurrent(.takeTheirs)
    await viewModel.saveResolved()

    XCTAssertEqual(viewModel.state, .saved)
    XCTAssertEqual(await provider.recordedSaveCalls(), [
        MergeEditorSaveCall(conflict: conflict, wc: wc, mergedText: "theirs\n")
    ])
}

@MainActor
func testSaveFailureStoresError() async {
    let provider = FakeMergeEditorProvider(
        loadResult: .success((base: "base\n", mine: "mine\n", theirs: "theirs\n")),
        saveError: SvnError.network(detail: "offline")
    )
    let viewModel = MergeEditorViewModel(provider: provider)

    await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
    viewModel.resolveCurrent(.takeMine)
    await viewModel.saveResolved()

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
}
```

并在测试文件中添加：

```swift
struct MergeEditorSaveCall: Equatable {
    let conflict: ConflictInfo
    let wc: URL
    let mergedText: String
}

actor FakeMergeEditorProvider: TextConflictLoading, ConflictResolutionSaving {
    let loadResult: Result<(base: String, mine: String, theirs: String), Error>
    let saveError: Error?
    private var loadCalls: [ConflictInfo] = []
    private var saveCalls: [MergeEditorSaveCall] = []

    init(
        loadResult: Result<(base: String, mine: String, theirs: String), Error>,
        saveError: Error? = nil
    ) {
        self.loadResult = loadResult
        self.saveError = saveError
    }

    func loadTextConflict(_ conflict: ConflictInfo) async throws -> (base: String, mine: String, theirs: String) {
        loadCalls.append(conflict)
        return try loadResult.get()
    }

    func saveResolution(_ conflict: ConflictInfo, wc: URL, mergedText: String) async throws {
        if let saveError {
            throw saveError
        }
        saveCalls.append(MergeEditorSaveCall(conflict: conflict, wc: wc, mergedText: mergedText))
    }

    func recordedLoadCalls() -> [ConflictInfo] {
        loadCalls
    }

    func recordedSaveCalls() -> [MergeEditorSaveCall] {
        saveCalls
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEditorViewModelTests/testSave"
```

预期：保存逻辑未实现或行为不符合测试导致失败。

- [ ] **步骤 3：实现最少代码**

实现 `saveResolved()`：
- 没有 loaded conflict 或 WC 时置 `.error("missingConflict")`。
- `canSaveResolved == false` 时置 `.error("unresolvedConflicts")`。
- `mergedText()` 返回 nil 时置 `.error("unresolvedConflicts")`。
- 否则置 `.saving`，调用 provider `saveResolution`，成功置 `.saved`，失败置 `.error(String(describing: error))`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEditorViewModelTests
```

预期：全部 `MergeEditorViewModelTests` PASS。

## 任务 4：全量验证与提交

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行验证**

运行：

```bash
swift test --filter MergeEditorViewModelTests
swift test
git diff --check
```

预期：目标测试与全量测试全部 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

运行：

```bash
git add Sources/MacSvnCore/ViewModels/MergeEditorViewModel.swift Tests/MacSvnCoreTests/MergeEditorViewModelTests.swift docs/superpowers/plans/2026-07-09-p3-merge-editor-view-model.md
git diff --cached --check
git commit -m "feat: add P3 merge editor view model"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：暂存区检查无输出，提交后补丁检查无输出，工作区干净。
