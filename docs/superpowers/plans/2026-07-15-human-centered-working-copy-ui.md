# SVN Studio 真人高频变更工作区实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将日常“选择工作副本 → 浏览变更 → 查看 Diff → 选择提交文件 → 填写说明 → 提交”重构为稳定、可读、键盘友好且 AI 不抢主层级的 macOS 工作区。

**架构：** 保留 Working-Copy Centric 导航和现有业务 ViewModel；新增一个只管理工作区行选择、Diff 焦点和提交集合的 `@Observable` 状态对象，并由组合层注入 Changes、Diff、Commit。响应式行为与展示状态通过纯策略类型表达，SwiftUI 视图负责渲染；组合层继续使用固定 HStack/VStack，禁止 SplitView。

**技术栈：** Swift 6.1、SwiftUI、Observation、XCTest、Swift Package Manager、macOS 14+

---

## 文件结构

- 创建 `Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspacePresentation.swift`：共享选择状态、宽度等级、Diff 展示状态和提交禁用原因等纯 UI 策略。
- 创建 `Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`：共享选择、响应式策略、Diff 状态和提交状态的单元测试。
- 修改 `Sources/MacSvnApp/App/MacSvnRootView.swift`：侧栏列宽、稳定行布局、完整信息 tooltip 和 Finder 上下文操作。
- 修改 `Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift`：工作副本上下文优先的紧凑模式栏。
- 修改 `Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift`：持有并分发共享状态，管理提交检查器展开状态。
- 修改 `Sources/MacSvnApp/Features/MacSvnChangesView.swift`：两层工具栏、高频/更多动作分组、行选择与提交复选框分离。
- 修改 `Sources/MacSvnApp/Features/MacSvnDiffView.swift`：正确的空闲/加载/空 Diff/二进制/错误状态和紧凑工具栏。
- 修改 `Sources/MacSvnApp/Features/MacSvnCommitView.swift`：嵌入式提交检查器、共享提交集合、AI 辅助菜单和稳定反馈区。
- 修改 `Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`：增加组合层和 AI 主层级的源码门禁。
- 修改 `CHANGELOG.md`：记录 U5 工作区的人本体验变化。
- 修改 `docs/superpowers/specs/2026-07-15-human-centered-working-copy-ui-design.md`：回填真实窗口验收结果和偏差。

## 任务 1：工作区展示策略与共享状态

**文件：**
- 创建：`Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspacePresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`

- [x] **步骤 1：编写共享选择与展示状态的失败测试**

```swift
import XCTest
import MacSvnCore
@testable import MacSvnApp

@MainActor
final class HumanCenteredWorkingCopyWorkspaceTests: XCTestCase {
    func testRowSelectionChangesDiffWithoutChangingCommitSelection() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.reconcileCommitCandidates(
            available: ["a.swift", "b.swift"],
            defaultSelected: ["a.swift", "b.swift"]
        )

        state.selectRows(["a.swift"], focusedPath: "a.swift")

        XCTAssertEqual(state.selectedPaths, ["a.swift"])
        XCTAssertEqual(state.focusedPath, "a.swift")
        XCTAssertEqual(state.commitPaths, ["a.swift", "b.swift"])
    }

    func testEditedCommitSelectionDoesNotAutoSelectNewCandidates() {
        let state = MacSvnWorkingCopyWorkspaceState()
        state.reconcileCommitCandidates(
            available: ["a", "b"],
            defaultSelected: ["a", "b"]
        )
        state.setCommitSelected(false, path: "b", userInitiated: true)
        state.reconcileCommitCandidates(
            available: ["a", "b", "c"],
            defaultSelected: ["a", "b", "c"]
        )

        XCTAssertEqual(state.commitPaths, ["a"])
    }

    func testDiffPresentationTreatsIdleWithoutPathAsNoSelection() {
        XCTAssertEqual(
            MacSvnEmbeddedDiffPresentation.resolve(path: nil, state: .idle, diffText: ""),
            .noSelection
        )
        XCTAssertEqual(
            MacSvnEmbeddedDiffPresentation.resolve(path: "a", state: .loaded, diffText: ""),
            .noChanges(path: "a")
        )
    }

    func testWidthClassUsesCompactLayoutBelowBaseline() {
        XCTAssertEqual(MacSvnWorkspaceWidthClass.resolve(width: 1_179), .compact)
        XCTAssertEqual(MacSvnWorkspaceWidthClass.resolve(width: 1_180), .regular)
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func readRepoSource(at path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
```

- [x] **步骤 2：运行测试并确认类型尚不存在**

运行：

```bash
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
```

预期：编译失败，报告 `cannot find 'MacSvnWorkingCopyWorkspaceState' in scope`。

- [x] **步骤 3：实现最小纯状态与策略类型**

```swift
import Foundation
import MacSvnCore
import Observation

@MainActor
@Observable
final class MacSvnWorkingCopyWorkspaceState {
    private(set) var selectedPaths: Set<String> = []
    private(set) var focusedPath: String?
    private(set) var commitPaths: Set<String> = []
    private(set) var commitSelectionWasEdited = false

    func selectRows(_ paths: Set<String>, focusedPath: String?) {
        selectedPaths = paths
        self.focusedPath = focusedPath ?? paths.sorted().first
    }

    func seedFocusedPath(_ path: String) {
        selectedPaths = [path]
        focusedPath = path
    }

    func setCommitSelected(_ selected: Bool, path: String, userInitiated: Bool) {
        if selected { commitPaths.insert(path) } else { commitPaths.remove(path) }
        commitSelectionWasEdited = commitSelectionWasEdited || userInitiated
    }

    func replaceCommitPaths(_ paths: Set<String>, userInitiated: Bool) {
        commitPaths = paths
        commitSelectionWasEdited = commitSelectionWasEdited || userInitiated
    }

    func reconcileCommitCandidates(available: Set<String>, defaultSelected: Set<String>) {
        commitPaths.formIntersection(available)
        if !commitSelectionWasEdited { commitPaths = defaultSelected.intersection(available) }
        selectedPaths.formIntersection(available)
        if focusedPath.map({ !available.contains($0) }) == true { focusedPath = nil }
    }
}

enum MacSvnWorkspaceWidthClass: Equatable {
    case compact
    case regular

    static func resolve(width: CGFloat) -> Self { width < 1_180 ? .compact : .regular }
}

enum MacSvnCommitInspectorMetrics {
    static let collapsedHeight: CGFloat = 44
    static let minimumExpandedHeight: CGFloat = 190
    static let idealExpandedHeight: CGFloat = 220
    static let maximumExpandedHeight: CGFloat = 260
}

enum MacSvnEmbeddedDiffPresentation: Equatable {
    case noSelection
    case loading(path: String)
    case loaded(path: String)
    case noChanges(path: String)
    case binary(path: String, details: BinaryFileDetails?)
    case error(path: String, message: String)

    static func resolve(path: String?, state: DiffViewState, diffText: String) -> Self {
        guard let path else { return .noSelection }
        switch state {
        case .idle, .loading: return .loading(path: path)
        case .loaded: return diffText.isEmpty ? .noChanges(path: path) : .loaded(path: path)
        case .binaryUnsupported(let details): return .binary(path: path, details: details)
        case .error(let message): return .error(path: path, message: message)
        }
    }
}
```

- [x] **步骤 4：运行定向测试并确认通过**

运行：`swift test --filter HumanCenteredWorkingCopyWorkspaceTests`

预期：4 个测试全部通过。

- [x] **步骤 5：提交策略切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspacePresentation.swift \
  Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift
git commit -m "feat(UI): 建立工作区共享交互状态"
```

## 任务 2：重排壳层与工作副本侧栏

**文件：**
- 修改：`Sources/MacSvnApp/App/MacSvnRootView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift`
- 测试：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`

- [x] **步骤 1：增加侧栏和上下文栏源码门禁测试**

```swift
func testSidebarAndContextBarKeepStableHumanReadableLayout() throws {
    let root = try Self.readRepoSource(at: "Sources/MacSvnApp/App/MacSvnRootView.swift")
    let shell = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift")

    XCTAssertTrue(root.contains("navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 320)"))
    XCTAssertTrue(root.contains("showInFinder"))
    XCTAssertTrue(root.contains("accessibilityLabel(\"添加工作副本\")"))
    XCTAssertTrue(shell.contains("repositoryContext"))
    XCTAssertTrue(shell.contains("Label(\"更多功能\", systemImage:"))
    XCTAssertTrue(shell.contains("Label(\"工具\", systemImage:"))
}
```

- [x] **步骤 2：运行定向测试并确认失败**

运行：`swift test --filter HumanCenteredWorkingCopyWorkspaceTests/testSidebarAndContextBarKeepStableHumanReadableLayout`

预期：断言失败，因为稳定列宽和新上下文栏尚未实现。

- [x] **步骤 3：实现侧栏稳定尺寸与上下文操作**

在 `MacSvnRootView`：

```swift
workingCopySidebar
    .navigationTitle(ProductBranding.displayName)
    .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 320)

private func showInFinder(_ record: WorkingCopyRecord) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.localPath)])
}
```

为添加/移除图标补齐 `frame(width: 28, height: 28)`、tooltip 和 accessibility label；侧栏行对名称、路径和仓库摘要使用单行布局、完整 tooltip 与固定最小行高；上下文菜单增加“在 Finder 中显示”。

- [x] **步骤 4：实现工作副本上下文优先的模式栏**

在 `MacSvnWorkingCopyShellView` 将 `modeToolbar` 拆为 `repositoryContext`、主模式 Picker 和两个图标菜单：

```swift
private var repositoryContext: some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(workspaceController.selectedRecord?.name ?? "未选择工作副本")
            .font(.callout.weight(.semibold))
            .lineLimit(1)
        Text(repositorySubtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
```

紧凑宽度只隐藏 `repositorySubtitle`，不隐藏工作副本名称、主模式或菜单能力。

- [x] **步骤 5：运行定向与导航测试**

运行：

```bash
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
swift test --filter MacSvnWorkspaceModeTests
swift test --filter BrandingExperienceTests
```

预期：全部通过。

- [x] **步骤 6：提交壳层切片**

```bash
git add Sources/MacSvnApp/App/MacSvnRootView.swift \
  Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift \
  Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift
git commit -m "feat(UI): 重排工作副本壳层与侧栏"
```

## 任务 3：重构变更面板并接入共享提交选择

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnChangesView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`

- [x] **步骤 1：增加动作层级与提交复选框失败测试**

```swift
func testEmbeddedChangesUsesTwoToolRowsAndSharedCommitCheckboxes() throws {
    let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnChangesView.swift")
    let primary = try Self.sourceSection(
        source,
        from: "private var primaryActions",
        to: "private var moreActionsMenu"
    )

    XCTAssertTrue(source.contains("primaryStatusBar"))
    XCTAssertTrue(source.contains("filterAndViewBar"))
    XCTAssertTrue(source.contains("Label(\"更多操作\", systemImage: \"ellipsis.circle\")"))
    XCTAssertTrue(source.contains("commitSelectionToggle"))
    XCTAssertTrue(source.contains("workspaceState?.setCommitSelected"))
    XCTAssertFalse(primary.contains("修复大小写"))
    XCTAssertFalse(primary.contains("复制/移动"))
    XCTAssertTrue(source.contains("Button(\"修复大小写…\")"))
}

func testWorkspaceCompositionOwnsOneSharedInteractionState() throws {
    let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift")
    XCTAssertTrue(source.contains("@State private var workspaceState"))
    XCTAssertTrue(source.contains("workspaceState: workspaceState"))
}
```

- [x] **步骤 2：运行测试并确认失败**

运行：`swift test --filter HumanCenteredWorkingCopyWorkspaceTests`

预期：新源码门禁失败。

- [x] **步骤 3：让组合层持有共享状态**

```swift
@State private var workspaceState = MacSvnWorkingCopyWorkspaceState()

MacSvnChangesView(
    workspaceController: workspaceController,
    statusProvider: session.svnService,
    navigator: navigator,
    session: session,
    embedded: true,
    initialSelectedPaths: seededSelection,
    workspaceState: workspaceState
)
```

深链种子改为调用 `workspaceState.seedFocusedPath(path)`，同时保留现有 pending intent 的消费顺序。

- [x] **步骤 4：拆分工具栏并压缩固定动作**

将现有 `header` 拆为 `primaryStatusBar` 和 `filterAndViewBar`。固定动作只保留更新、添加、还原、删除菜单、冲突入口；清理、重命名、大小写修复、复制/移动、Repair、更新到修订、忽略和变更列表进入分组的 `moreActionsMenu`。刷新和检查仓库改为图标按钮：

```swift
Button { Task { await changesVM?.refresh() } } label: {
    Image(systemName: "arrow.clockwise")
}
.help("刷新本地状态")
.accessibilityLabel("刷新本地状态")
```

- [x] **步骤 5：在可提交行加入独立复选框**

```swift
@ViewBuilder
private func commitSelectionToggle(_ status: FileStatus) -> some View {
    if embedded, CommitSelectionPolicy.candidates(from: [status]).isEmpty == false {
        Toggle("提交 \(status.path)", isOn: Binding(
            get: { workspaceState?.commitPaths.contains(status.path) == true },
            set: { workspaceState?.setCommitSelected($0, path: status.path, userInitiated: true) }
        ))
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(status.itemStatus == .conflicted || status.isTreeConflict)
    }
}
```

`List` 行选择继续绑定 `selectedPaths`，其 setter 只调用 `workspaceState.selectRows`，不得写 `commitPaths`。

- [x] **步骤 6：保留性能门禁并运行测试**

运行：

```bash
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter ChangesViewModelTests
```

预期：全部通过；源码仍不包含 `VSplitView {` 或 `HSplitView {`。

- [x] **步骤 7：提交变更面板切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift \
  Sources/MacSvnApp/Features/MacSvnChangesView.swift \
  Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 重构变更面板与提交选择"
```

## 任务 4：修正 Diff 工具栏与状态机

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnDiffView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`

- [x] **步骤 1：增加 Diff 空态和工具层级失败测试**

```swift
func testEmbeddedDiffShowsRealNoSelectionAndMovesRareActionsIntoMenu() throws {
    let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnDiffView.swift")

    XCTAssertTrue(source.contains("MacSvnEmbeddedDiffPresentation.resolve"))
    XCTAssertTrue(source.contains("选择一个文件查看差异"))
    XCTAssertTrue(source.contains("此文件没有可显示的文本差异"))
    XCTAssertTrue(source.contains("Label(\"更多 Diff 操作\", systemImage: \"ellipsis.circle\")"))
    XCTAssertFalse(source.contains("ProgressView(\"加载 diff…\")\n            case .binaryUnsupported"))
}
```

- [x] **步骤 2：运行测试并确认失败**

运行：`swift test --filter HumanCenteredWorkingCopyWorkspaceTests/testEmbeddedDiffShowsRealNoSelectionAndMovesRareActionsIntoMenu`

预期：源码断言失败。

- [x] **步骤 3：实现嵌入式 Diff 状态渲染**

```swift
@ViewBuilder
private var embeddedDiffContent: some View {
    let presentation = MacSvnEmbeddedDiffPresentation.resolve(
        path: selectedPath,
        state: viewModel?.state ?? .idle,
        diffText: viewModel?.diffText ?? ""
    )
    switch presentation {
    case .noSelection:
        ContentUnavailableView("选择一个文件查看差异", systemImage: "doc.text.magnifyingglass")
    case .loading(let path):
        loadingView(path: path)
    case .noChanges:
        ContentUnavailableView("此文件没有可显示的文本差异", systemImage: "checkmark.circle")
    case .loaded:
        loadedDiffContent
    case .binary(_, let details):
        binaryView(details)
    case .error(_, let message):
        diffErrorView(message)
    }
}
```

空闲无路径必须先命中 `.noSelection`。重试按钮重新加载当前 path，错误状态保留外部工具入口。

- [x] **步骤 4：压缩 Diff 工具栏**

固定展示模式 Picker、对比 BASE、外置查看和刷新；“与 URL 比较”移入 `moreDiffActionsMenu`。按钮使用 SF Symbols、tooltip、accessibility label，状态文本不再插入额外高度行。

- [x] **步骤 5：运行 Diff 与性能测试**

运行：

```bash
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
swift test --filter DiffViewModelTests
swift test --filter DiffPerformanceLimitsTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
```

预期：全部通过，超大 Diff 仍使用 `DiffPerformanceLimits`。

- [x] **步骤 6：提交 Diff 切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnDiffView.swift \
  Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 完善工作区 Diff 状态与操作层级"
```

## 任务 5：实现可收起的提交检查器

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnCommitView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`

- [ ] **步骤 1：增加检查器与 AI 层级失败测试**

```swift
func testEmbeddedCommitIsCollapsibleAndKeepsAIInAssistanceMenu() throws {
    let workspace = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift")
    let commit = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnCommitView.swift")

    XCTAssertTrue(workspace.contains("isCommitInspectorExpanded"))
    XCTAssertTrue(workspace.contains("collapsedHeight: 44"))
    XCTAssertTrue(commit.contains("Label(\"说明辅助\", systemImage: \"wand.and.stars\")"))
    XCTAssertFalse(commit.contains("Button(\"AI 生成说明\")"))
    XCTAssertFalse(commit.contains("Button(\"AI 预检\")"))
    XCTAssertTrue(commit.contains("workspaceState.reconcileCommitCandidates"))
}
```

- [ ] **步骤 2：运行测试并确认失败**

运行：`swift test --filter HumanCenteredWorkingCopyWorkspaceTests/testEmbeddedCommitIsCollapsibleAndKeepsAIInAssistanceMenu`

预期：源码断言失败。

- [ ] **步骤 3：组合层增加稳定检查器容器**

```swift
@State private var isCommitInspectorExpanded = false

MacSvnCommitView(
    workspaceController: workspaceController,
    session: session,
    navigator: navigator,
    embedded: true,
    isExpanded: $isCommitInspectorExpanded,
    workspaceState: workspaceState
)
.frame(
    minHeight: isCommitInspectorExpanded
        ? MacSvnCommitInspectorMetrics.minimumExpandedHeight
        : MacSvnCommitInspectorMetrics.collapsedHeight,
    idealHeight: isCommitInspectorExpanded
        ? MacSvnCommitInspectorMetrics.idealExpandedHeight
        : MacSvnCommitInspectorMetrics.collapsedHeight,
    maxHeight: isCommitInspectorExpanded
        ? MacSvnCommitInspectorMetrics.maximumExpandedHeight
        : MacSvnCommitInspectorMetrics.collapsedHeight
)
```

展开/折叠使用 `0.18 s` easeInOut，并在 Reduce Motion 下禁用动画。不得使用 VSplitView。

- [ ] **步骤 4：同步 CommitViewModel 与共享提交集合**

`reloadCandidates()` 创建 ViewModel 后调用：

```swift
let available = Set(nextViewModel.candidateStatuses.map(\.path))
let defaults = CommitSelectionPolicy.defaultSelectedPaths(from: nextViewModel.candidateStatuses)
workspaceState?.reconcileCommitCandidates(available: available, defaultSelected: defaults)
applyWorkspaceCommitSelection(to: nextViewModel)
```

候选 Toggle 的 setter 同时更新 ViewModel 和 `workspaceState.setCommitSelected(..., userInitiated: true)`；外部变化只在集合不同时回写 ViewModel，避免 onChange 循环。

- [ ] **步骤 5：实现折叠头和紧凑展开内容**

折叠头显示展开按钮、提交文件数、说明状态、提交按钮。展开态不再常驻完整候选列表，改为“文件（N）” popover 管理复选框；主体保留说明编辑器、历史说明菜单、校验摘要、Keep locks 和提交按钮。

AI 入口改为：

```swift
Menu {
    Button("生成提交说明") { Task { await runAICommitMessage() } }
    Button("运行 AI 预检") { Task { await runAIReview() } }
} label: {
    Label("说明辅助", systemImage: "wand.and.stars")
}
```

只有“提交”使用 `.borderedProminent`。AI 状态进入固定校验摘要/详情区，不新增主按钮。

- [ ] **步骤 6：运行提交、性能和源码门禁测试**

运行：

```bash
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
swift test --filter CommitViewModelTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter SettingsInformationArchitectureTests/testCommitEditorConsumesAutoCompletionAndRevertSafetySettings
```

预期：全部通过；提交说明补全、Guard、Bugtraq、历史和 Keep locks 保持可达。

- [ ] **步骤 7：提交检查器切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnWorkingCopyWorkspaceView.swift \
  Sources/MacSvnApp/Features/MacSvnCommitView.swift \
  Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 将提交区重构为人本检查器"
```

## 任务 6：全量验证、真实窗口修正与文档收口

**文件：**
- 修改：`CHANGELOG.md`
- 修改：`docs/superpowers/specs/2026-07-15-human-centered-working-copy-ui-design.md`
- 按真实窗口问题修改：任务 2–5 涉及的 SwiftUI 文件与对应测试

- [ ] **步骤 1：运行全量测试**

运行：

```bash
swift test
```

预期：全部测试通过，无失败和意外跳过。

- [ ] **步骤 2：构建并校验真实 App**

运行：

```bash
./scripts/build-macos-app.sh
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
```

预期：`dist/SVNStudio.app` 生成、结构校验通过并可启动。

- [ ] **步骤 3：在真实窗口完成尺寸与状态验收**

打开 `dist/SVNStudio.app`，分别检查 `980 x 640`、`1180 x 760`、`1440 x 900`：

- 模式、高频动作和提交按钮不显示为 `...`；
- 文字不重叠，筛选与视图不换行；
- 未选文件显示 Diff 空态，不显示假加载；
- 点击行只切换 Diff，复选框只切换提交集合；
- 提交折叠/展开平滑且 Diff 保留可读高度；
- AI 只在辅助菜单；
- 浅色和深色均有清晰选中、焦点、错误与禁用状态。

保存基线截图到 `artifacts/ui/u5-working-copy-980x640.png`、`artifacts/ui/u5-working-copy-1180x760.png` 和 `artifacts/ui/u5-working-copy-1440x900.png`。若仓库忽略 `artifacts/`，截图只作为本地验收证据，不强制提交。

- [ ] **步骤 4：修复截图和交互验收发现的问题**

每个问题先在 `HumanCenteredWorkingCopyWorkspaceTests` 或源码门禁中补回归测试，再修改对应 SwiftUI 文件。重复运行定向测试、构建和真实窗口检查，直到三种尺寸无重叠、错乱换行、按钮省略或主操作层级错误。

- [ ] **步骤 5：更新变更记录和规格验收结果**

在 `CHANGELOG.md` 的未发布区记录工作副本侧栏、变更/Diff/提交工作流、正确空态、共享提交复选框和 AI 降级为辅助入口。在规格第 13 节追加验收日期、测试结果、截图路径和仍属于 U6–U8 的后续范围。

- [ ] **步骤 6：最终验证**

运行：

```bash
git diff --check
swift test
./scripts/build-macos-app.sh
git status --short
```

预期：格式检查、全量测试和 App 校验通过；状态只包含本任务文档与实现文件。

- [ ] **步骤 7：提交 U5 收口**

```bash
git add CHANGELOG.md docs/superpowers/specs/2026-07-15-human-centered-working-copy-ui-design.md \
  Sources/MacSvnApp Tests/MacSvnAppTests
git commit -m "feat(UI): 完成真人高频变更工作区首轮迭代"
```

完成 U5 后继续为 U6 核心模式统一编写独立规格，不将本计划完成误报为整个 UI 长程目标完成。
