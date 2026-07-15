# SVN Studio 人本核心模式实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将历史、仓库浏览、分支和冲突/Merge 四个主模式统一为稳定、响应式、可读且不牺牲任何 SVN 能力的人本工作区。

**架构：** 保留现有业务 ViewModel、深链和 SVN 服务；新增只负责宽度、尺寸和过滤摘要的纯展示策略。四页组合层统一为确定尺寸的工具栏、筛选栏和主从 `HStack`，移除自由 `HSplitView`；紧凑宽度通过菜单、popover 和弹窗披露次级能力。

**技术栈：** Swift 6.1、SwiftUI、Observation/ObservableObject、XCTest、Swift Package Manager、macOS 14+

---

## 文件结构

- 创建 `Sources/MacSvnApp/Features/MacSvnCoreModePresentation.swift`：U6 宽度等级、稳定尺寸和日志活动筛选计数。
- 创建 `Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`：纯策略单测与四页源码契约门禁。
- 修改 `Sources/MacSvnApp/Features/MacSvnLogView.swift`：历史工具栏、组合筛选 popover、稳定主从布局和修订操作菜单。
- 修改 `Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift`：响应式目录/详情、收藏菜单、远端条目操作菜单和双击导航。
- 修改 `Sources/MacSvnApp/Features/MacSvnBranchesView.swift`：分支筛选、选择详情、创建弹窗、切换与 Merge 入口。
- 修改 `Sources/MacSvnApp/App/MacSvnAppNavigator.swift`：分支到 Merge 向导的原子 source URL handoff。
- 修改 `Sources/MacSvnApp/Features/MacSvnFeatureHostView.swift`：向分支页注入 Navigator。
- 修改 `Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift`：稳定冲突主从布局、批量操作菜单和紧凑工具栏。
- 修改 `Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift`：参数、预览和执行层级；消费 Merge source URL handoff。
- 修改 `Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift`：Merge handoff 单测。
- 修改 `Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`：禁止 U6 组合层重新引入 SplitView。
- 修改 `Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`：新增 U6 英文资源。
- 修改 `CHANGELOG.md`、本计划和 U6 规格：回填验收证据。

## 任务 1：建立核心模式展示策略

**文件：**
- 创建：`Sources/MacSvnApp/Features/MacSvnCoreModePresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`

- [ ] **步骤 1：编写宽度、尺寸和日志筛选失败测试**

```swift
import Foundation
import XCTest
@testable import MacSvnApp

@MainActor
final class HumanCenteredCoreModesTests: XCTestCase {
    func testCoreModeWidthClassChangesAtDailyBaseline() {
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_179), .compact)
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_180), .regular)
    }

    func testLogFilterSummaryCountsEveryCombinableFilter() {
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "alice",
                message: "fix",
                path: "Sources",
                stopOnCopy: true,
                offline: true
            ),
            5
        )
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "  ",
                message: "",
                path: "",
                stopOnCopy: false,
                offline: false
            ),
            0
        )
    }

    func testCoreModeMetricsKeepMasterAndInspectorReadable() {
        XCTAssertEqual(MacSvnCoreModeMetrics.toolbarHeight, 48)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.masterMinimumWidth, 320)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.inspectorMinimumWidth, 360)
    }
}
```

- [ ] **步骤 2：运行测试并确认正确失败**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests
```

预期：编译失败，提示 `MacSvnCoreModeWidthClass`、`MacSvnLogFilterSummary` 和 `MacSvnCoreModeMetrics` 不存在。

- [ ] **步骤 3：实现最小纯展示策略**

```swift
import Foundation

enum MacSvnCoreModeWidthClass: Equatable {
    case compact
    case regular

    static func resolve(width: CGFloat) -> Self {
        width < 1_180 ? .compact : .regular
    }
}

enum MacSvnCoreModeMetrics {
    static let toolbarHeight: CGFloat = 48
    static let masterMinimumWidth: CGFloat = 320
    static let masterIdealWidth: CGFloat = 360
    static let masterMaximumWidth: CGFloat = 400
    static let inspectorMinimumWidth: CGFloat = 360
}

enum MacSvnLogFilterSummary {
    static func activeCount(
        author: String,
        message: String,
        path: String,
        stopOnCopy: Bool,
        offline: Bool
    ) -> Int {
        [author, message, path]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count + (stopOnCopy ? 1 : 0) + (offline ? 1 : 0)
    }
}
```

- [ ] **步骤 4：运行定向测试并确认通过**

运行：`swift test --filter HumanCenteredCoreModesTests`

预期：3 个测试通过。

- [ ] **步骤 5：提交展示策略切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnCoreModePresentation.swift \
  Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift
git commit -m "feat(UI): 建立核心模式响应式展示策略（U6 任务 1/6）"
```

## 任务 2：统一历史模式

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnLogView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`

- [ ] **步骤 1：增加历史动作层级与组合筛选源码门禁**

在 `HumanCenteredCoreModesTests` 增加源码读取辅助方法和测试：

```swift
func testHistoryUsesCompactToolbarCombinableFiltersAndStableMasterDetail() throws {
    let source = try Self.readRepoSource(
        at: "Sources/MacSvnApp/Features/MacSvnLogView.swift"
    )
    let toolbar = try Self.sourceSection(
        source,
        from: "private var historyToolbar",
        to: "private var historyFilterBar"
    )
    let detailActions = try Self.sourceSection(
        source,
        from: "private func detailActions(",
        to: "private func logPathContextMenu("
    )

    XCTAssertTrue(source.contains("@State private var showFilterPopover"))
    XCTAssertTrue(source.contains("@FocusState private var isMessageFilterFocused"))
    XCTAssertTrue(toolbar.contains("historyLoadMenu"))
    XCTAssertTrue(toolbar.contains("historyMoreActionsMenu"))
    XCTAssertFalse(toolbar.contains("Button(\"AI Release Notes\")"))
    XCTAssertTrue(source.contains("MacSvnLogFilterSummary.activeCount"))
    XCTAssertTrue(source.contains("MacSvnCoreModeMetrics.masterIdealWidth"))
    XCTAssertTrue(detailActions.contains("Menu"))
}
```

- [ ] **步骤 2：运行测试并确认断言失败**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests/testHistoryUsesCompactToolbarCombinableFiltersAndStableMasterDetail
```

预期：断言失败，因为历史页仍使用 `logToolbar` / `logFilterBar` 和固定按钮堆叠。

- [ ] **步骤 3：实现稳定历史工具栏**

将 `logToolbar` 改为 `historyToolbar`：

```swift
private var historyToolbar: some View {
    HStack(spacing: 8) {
        Label("历史", systemImage: "clock.arrow.circlepath")
            .font(.headline)
        if let viewModel {
            Text("\(filteredEntries(viewModel.entries).count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Button { Task { await reload() } } label: {
            Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("刷新历史")
        .accessibilityLabel("刷新历史")
        historyLoadMenu
        historyMoreActionsMenu
    }
    .padding(.horizontal, 12)
    .frame(height: MacSvnCoreModeMetrics.toolbarHeight)
}
```

`historyLoadMenu` 保留 Next / Show All；`historyMoreActionsMenu` 保留统计与 AI Release Notes，均使用 icon-only label、`.menuStyle(.borderlessButton)`、`.menuIndicator(.hidden)`、tooltip 和 accessibility label。

- [ ] **步骤 4：实现组合筛选栏与 popover**

新增：

```swift
@State private var showFilterPopover = false
@FocusState private var isMessageFilterFocused: Bool
```

`historyFilterBar` 直接显示说明搜索框、筛选按钮、活动筛选数量和数据源。筛选 popover 内继续绑定 `authorFilter`、`pathFilter`、`stopOnCopy`、`offlineMode`，并接入 `.macSvnDismissiblePopover()`；不得删除原 `onChange` 中的 reload / stop-on-copy 逻辑。隐藏按钮提供 `⌘F`：

```swift
.background {
    Button("") { isMessageFilterFocused = true }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .accessibilityHidden(true)
}
```

- [ ] **步骤 5：稳定主从布局和修订动作**

修订 List 使用：

```swift
.frame(
    minWidth: MacSvnCoreModeMetrics.masterMinimumWidth,
    idealWidth: MacSvnCoreModeMetrics.masterIdealWidth,
    maxWidth: MacSvnCoreModeMetrics.masterMaximumWidth
)
```

变更路径增加 `.lineLimit(1)`、`.truncationMode(.middle)` 和 `.help(change.path)`。`detailActions` 只固定“在变更区查看 Diff”，其余更新到修订、修订属性、编辑作者/说明、复制摘要进入 `Menu("修订操作", systemImage: "ellipsis.circle")`。

- [ ] **步骤 6：运行历史、Localization 与性能测试**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests
swift test --filter LogViewModelTests
swift test --filter LogFilterPolicyTests
swift test --filter LocalizationResourceTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
```

预期：全部通过；离线、stop-on-copy、Next/All、统计、L01–L20 和 AI Release Notes 仍可达。

- [ ] **步骤 7：提交历史切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnLogView.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift
git commit -m "feat(UI): 统一历史模式筛选与动作层级（U6 任务 2/6）"
```

## 任务 3：统一仓库浏览模式

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`

- [ ] **步骤 1：增加响应式目录/详情和双击导航失败测试**

```swift
func testRepositoryBrowserPrioritizesDirectoryAndUsesResponsiveInspector() throws {
    let source = try Self.readRepoSource(
        at: "Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift"
    )

    XCTAssertTrue(source.contains("GeometryReader"))
    XCTAssertTrue(source.contains("private func repositoryWorkspace(width:"))
    XCTAssertTrue(source.contains("private var favoritesMenu"))
    XCTAssertTrue(source.contains("private var selectedEntryActionsMenu"))
    XCTAssertTrue(source.contains("@State private var showInspectorPopover"))
    XCTAssertTrue(source.contains(".onTapGesture(count: 2)"))
    XCTAssertTrue(source.contains("private func openDirectory("))
    XCTAssertFalse(source.contains("HSplitView"))
}
```

扩展性能守卫：读取 `MacSvnRepoBrowserView.swift`，断言不包含 `HSplitView {` 或 `VSplitView {`。

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests/testRepositoryBrowserPrioritizesDirectoryAndUsesResponsiveInspector
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
```

预期：源码断言失败，Repo Browser 仍为固定三栏 `HSplitView`。

- [ ] **步骤 3：重排地址工具栏和远端动作**

顶栏改为紧凑 URL 输入、前往图标、刷新、`favoritesMenu` 和仓库操作菜单。目录操作栏只固定“新建目录”；删除/复制/移动/重命名进入 `selectedEntryActionsMenu`，保留原 disabled 条件和 sheet 流程。

- [ ] **步骤 4：实现 regular/compact 工作区**

body 使用 `GeometryReader`，调用：

```swift
@ViewBuilder
private func repositoryWorkspace(width: CGFloat) -> some View {
    let widthClass = MacSvnCoreModeWidthClass.resolve(width: width)
    HStack(spacing: 0) {
        centerPane
            .frame(minWidth: MacSvnCoreModeMetrics.masterMinimumWidth)
        if widthClass == .regular {
            Divider()
            detailPane
                .frame(minWidth: MacSvnCoreModeMetrics.inspectorMinimumWidth)
        }
    }
}
```

compact 工具栏增加“详情”图标，popover 内复用 `detailPane` 并接入 `.macSvnDismissiblePopover()`。收藏始终通过菜单访问，不再常驻 sidebar。

- [ ] **步骤 5：分离选择与目录导航**

List selection setter 只设置 `selectedEntry` 并触发文件预览；目录行增加 `.onTapGesture(count: 2) { Task { await openDirectory(entry) } }`。`openDirectory` 只处理 `.directory`，加载 child URL 成功后更新 `rootURL` 并清空旧 selection/preview。

- [ ] **步骤 6：运行 Repo Browser 与真实命令测试**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests
swift test --filter RepositoryBrowserViewModelTests
swift test --filter RepositoryTransferViewModelTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter LocalizationResourceTests
```

预期：全部通过；收藏、预览、锁、Checkout、远端写、传输和 Create Repository 保持可达。

- [ ] **步骤 7：提交仓库浏览切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift \
  Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings
git commit -m "feat(UI): 重构响应式仓库浏览工作区（U6 任务 3/6）"
```

## 任务 4：统一分支选择、创建与 Merge handoff

**文件：**
- 修改：`Sources/MacSvnApp/App/MacSvnAppNavigator.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnFeatureHostView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnBranchesView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift`
- 修改：`Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`

- [ ] **步骤 1：编写分支到 Merge 原子 handoff 失败测试**

在 `MacSvnAppNavigatorTests` 增加：

```swift
func testBranchMergeHandoffCarriesSourceURLIntoConflictMode() {
    let navigator = MacSvnAppNavigator()

    navigator.openMerge(sourceURL: "https://svn.example.com/repo/branches/release")

    XCTAssertEqual(navigator.selectedMode, .conflicts)
    XCTAssertTrue(navigator.pendingMergeWizard)
    XCTAssertEqual(
        navigator.consumePendingMergeSourceURL(),
        "https://svn.example.com/repo/branches/release"
    )
    XCTAssertNil(navigator.consumePendingMergeSourceURL())
}
```

- [ ] **步骤 2：编写分支主从 UI 源码失败测试**

```swift
func testBranchesUseSelectionDrivenInspectorAndCreateSheet() throws {
    let source = try Self.readRepoSource(
        at: "Sources/MacSvnApp/Features/MacSvnBranchesView.swift"
    )

    XCTAssertTrue(source.contains("@State private var selectedReferenceURL"))
    XCTAssertTrue(source.contains("@State private var referenceFilter"))
    XCTAssertTrue(source.contains("@State private var showCreateSheet"))
    XCTAssertTrue(source.contains("private var branchInspector"))
    XCTAssertTrue(source.contains("navigator.openMerge(sourceURL:"))
    XCTAssertFalse(source.contains("HSplitView"))
}
```

- [ ] **步骤 3：运行测试并确认失败**

运行：

```bash
swift test --filter MacSvnAppNavigatorTests/testBranchMergeHandoffCarriesSourceURLIntoConflictMode
swift test --filter HumanCenteredCoreModesTests/testBranchesUseSelectionDrivenInspectorAndCreateSheet
```

预期：编译或断言失败，handoff 和选择驱动 UI 尚不存在。

- [ ] **步骤 4：实现 Navigator handoff**

```swift
@Published public var pendingMergeSourceURL: String?

public func openMerge(sourceURL: String) {
    pendingMergeSourceURL = sourceURL
    pendingMergeWizard = true
    selectMode(.conflicts)
}

public func consumePendingMergeSourceURL() -> String? {
    defer { pendingMergeSourceURL = nil }
    return pendingMergeSourceURL
}
```

`MacSvnMergeWizardView.task` 在默认 WC URL 后消费 pending source URL，非空时覆盖 `sourceURL`。FeatureHost 向 `MacSvnBranchesView` 注入 Navigator。

- [ ] **步骤 5：重排分支主从工作区**

列表建立可选 `selectedReferenceURL` 和 `ReferenceFilter`（all/branch/tag），移除行内“切换到此”按钮。右侧 `branchInspector` 显示所选引用、revision 输入、mergeinfo 摘要，并提供“切换到此引用”主按钮和“在 Merge 向导中使用”命令。

创建表单移入 `.sheet(isPresented: $showCreateSheet)`，接入 `.macSvnDismissibleSheet()`；顶栏固定刷新图标与“创建分支/标签”命令。创建成功关闭 sheet、清空名称并刷新，失败保留用户输入。

- [ ] **步骤 6：运行分支、Navigator、Merge 测试**

运行：

```bash
swift test --filter MacSvnAppNavigatorTests
swift test --filter HumanCenteredCoreModesTests
swift test --filter BranchBrowserViewModelTests
swift test --filter BranchSwitchViewModelTests
swift test --filter BranchCopyViewModelTests
swift test --filter MergeWizardViewModelTests
swift test --filter ModalDismissalAccessibilityTests
```

预期：全部通过；创建、切换本地变更确认、mergeinfo 与 Merge source URL handoff 正确。

- [ ] **步骤 7：提交分支切片**

```bash
git add Sources/MacSvnApp/App/MacSvnAppNavigator.swift \
  Sources/MacSvnApp/Features/MacSvnFeatureHostView.swift \
  Sources/MacSvnApp/Features/MacSvnBranchesView.swift \
  Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift \
  Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift \
  Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift
git commit -m "feat(UI): 统一分支详情与合并入口（U6 任务 4/6）"
```

## 任务 5：统一冲突列表与 Merge 向导

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`

- [ ] **步骤 1：增加冲突动作层级和稳定布局失败测试**

```swift
func testConflictWorkspaceSeparatesRowFocusBatchSelectionAndMergeActions() throws {
    let conflict = try Self.readRepoSource(
        at: "Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift"
    )
    let merge = try Self.readRepoSource(
        at: "Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift"
    )

    XCTAssertTrue(conflict.contains("private var conflictToolbar"))
    XCTAssertTrue(conflict.contains("private var conflictFilterBar"))
    XCTAssertTrue(conflict.contains("private var bulkSelectionMenu"))
    XCTAssertTrue(conflict.contains("MacSvnCoreModeMetrics.masterIdealWidth"))
    XCTAssertFalse(conflict.contains("HSplitView"))
    XCTAssertTrue(merge.contains("private var mergeParameterPane"))
    XCTAssertTrue(merge.contains("private var mergeResultPane"))
    XCTAssertTrue(merge.contains(".buttonStyle(.borderedProminent)"))
}
```

性能守卫增加 Conflict 主组合层无 SplitView 断言。

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests/testConflictWorkspaceSeparatesRowFocusBatchSelectionAndMergeActions
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
```

预期：断言失败，冲突页仍为大标题 + 自由 HSplitView，Merge 向导尚未拆分参数/结果。

- [ ] **步骤 3：实现冲突工具栏、筛选和主从布局**

将大标题块拆成 `conflictToolbar` 和 `conflictFilterBar`。类型 Picker 与路径搜索保留；“勾选可解决”“清除勾选”进入 `bulkSelectionMenu`，“标记已解决 (N)”保持固定。主区使用 `HStack(spacing: 0)`，列表按 CoreModeMetrics 固定宽度，详情占剩余空间。

列表行路径增加单行中部截断和 tooltip；复选框 setter 只写 checkedPaths，List selection setter 只写 selectedConflictPath 并加载详情。树冲突继续禁用批量复选框。

- [ ] **步骤 4：重排 Merge 参数、预览和执行**

`MacSvnMergeWizardView` 拆成：

```swift
private var mergeParameterPane: some View
private var mergeActions: some View
private var mergeResultPane: some View
```

参数区使用紧凑 segmented merge mode 和字段；动作区固定 Dry-run、Unified Diff、执行合并，其中只有执行按钮使用 `.borderedProminent`。结果区稳定显示 previewSummary / mergeSummary / unifiedDiff，路径单行中部截断并保留 tooltip。

- [ ] **步骤 5：运行冲突、Merge、性能与 Localization 测试**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests
swift test --filter ConflictListViewModelTests
swift test --filter MergeEditorViewModelTests
swift test --filter TreeConflictViewModelTests
swift test --filter PropertyConflictViewModelTests
swift test --filter MergeWizardViewModelTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter LocalizationResourceTests
```

预期：全部通过；文本/树/属性冲突、批量 Resolved、外置 Merge、AI 辅助、dry-run、Diff、执行与冲突回跳无回归。

- [ ] **步骤 6：提交冲突/Merge 切片**

```bash
git add Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift \
  Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift \
  Tests/MacSvnAppTests/HumanCenteredCoreModesTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings
git commit -m "feat(UI): 统一冲突处理与合并向导（U6 任务 5/6）"
```

## 任务 6：全量验证、真实窗口修正与文档收口

**文件：**
- 修改：`CHANGELOG.md`
- 修改：`docs/superpowers/specs/2026-07-15-human-centered-core-modes-ui-design.md`
- 修改：`docs/superpowers/plans/2026-07-15-human-centered-core-modes-ui.md`
- 修改：真实窗口验收暴露问题对应的 U6 SwiftUI 文件和测试

- [ ] **步骤 1：运行 U6 定向门禁**

运行：

```bash
swift test --filter HumanCenteredCoreModesTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter ModalDismissalAccessibilityTests
swift test --filter LocalizationResourceTests
```

预期：全部通过；四页无自由 SplitView，新增 popover/sheet 全部具有关闭能力。

- [ ] **步骤 2：运行全量测试**

运行：`swift test`

预期：全部测试通过，真实 SVN `49/49` 继续通过。

- [ ] **步骤 3：构建和冒烟最终 App**

运行：

```bash
./scripts/build-macos-app.sh
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
```

预期：`dist/SVNStudio.app` 结构校验和隔离启动冒烟通过。

- [ ] **步骤 4：真实窗口验收五个状态页**

在 `980 x 640`、`1180 x 760`、`1440 x 900` 检查历史、仓库浏览、分支、冲突列表和 Merge 向导；至少覆盖：

- 无选择、已有选择、加载、空态、错误；
- 历史组合筛选、Next/All/统计/AI 辅助；
- 仓库目录双击、详情、收藏、远端操作；
- 分支选择、创建 sheet、切换确认、Merge handoff；
- 冲突复选框与行选择分离、三类详情、批量解决、dry-run、Diff；
- 浅色、深色、Reduce Motion、键盘焦点、tooltip 和 VoiceOver 标签。

截图保存到本地 `artifacts/ui/u6-*.png`，因包含本机工作副本和仓库元数据不进入 Git 历史。

- [ ] **步骤 5：按截图问题继续 TDD 修正**

每个重叠、换行、游离菜单指示器、错误空态或能力不可达问题，先在 `HumanCenteredCoreModesTests` 增加精确断言并确认红灯，再修改对应视图并重跑定向测试和截图。

- [ ] **步骤 6：更新文档和最终验证**

在 CHANGELOG 记录四模式工作流、响应式行为和能力保留；在规格追加测试数量、截图路径、偏差和 U7/U8 边界。运行：

```bash
git diff --check
swift test
./scripts/build-macos-app.sh
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
git status --short
```

- [ ] **步骤 7：提交 U6 收口**

```bash
git add CHANGELOG.md docs/superpowers/specs/2026-07-15-human-centered-core-modes-ui-design.md \
  docs/superpowers/plans/2026-07-15-human-centered-core-modes-ui.md \
  Sources/MacSvnApp Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests
git commit -m "feat(UI): 完成人本核心模式统一（U6 任务 6/6）"
```

完成 U6 后继续 U7 辅助能力统一；不得把 U6 收口误报为整个 Human UI 长程目标完成。
