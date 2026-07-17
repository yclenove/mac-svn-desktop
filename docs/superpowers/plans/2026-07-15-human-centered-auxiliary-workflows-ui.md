# SVN Studio 人本辅助工作流实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将属性、锁、搁置/Patch、设置、弹窗和操作反馈统一为稳定、可读、键盘可达且不牺牲任何 SVN 能力的人本辅助工作流。

**架构：** 新增纯展示策略承载辅助页尺寸、路径和反馈语义；属性、锁、搁置继续拥有独立 ViewModel，只统一 SwiftUI 组合结构。设置保留九类持久化映射，通过可比较草稿快照提供搜索、脏状态和稳定保存反馈。

**技术栈：** Swift 6、SwiftUI、AppKit、XCTest、Swift Package Manager、现有 MacSvnCore ViewModel/Service、`DiffPerformanceLimits`。

---

## 文件结构

- 创建 `Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift`：辅助页稳定尺寸、路径转换、反馈模型和共享反馈视图。
- 创建 `Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`：U7 纯策略与源码契约测试。
- 修改 `Sources/MacSvnApp/Features/MacSvnPropertiesView.swift`：属性目标主栏、信息/列表/编辑器详情和响应式布局。
- 修改 `Sources/MacSvnApp/Features/MacSvnLocksView.swift`：锁目标主栏、锁详情、资格动作和空态。
- 修改 `Sources/MacSvnApp/Features/MacSvnShelveView.swift`：创建 sheet、官方/本地记录主栏、详情预览和动作层级。
- 修改 `Sources/MacSvnApp/Features/MacSvnSettingsCategory.swift`：分类搜索关键字和匹配策略。
- 修改 `Sources/MacSvnApp/Features/MacSvnSettingsView.swift`：搜索、草稿快照、固定保存栏和可定位校验反馈。
- 修改 `Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift`：未保存 sheet 的交互关闭策略（仅在实际需要时扩展，不改变已有关闭契约）。
- 修改 `Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`：禁止属性、锁和搁置主组合层使用自由 SplitView。
- 修改 `Tests/MacSvnAppTests/SettingsInformationArchitectureTests.swift`：设置搜索、脏状态与保存事务契约。
- 修改 `Tests/MacSvnAppTests/ModalDismissalAccessibilityTests.swift`：弹窗关闭、取消和 busy 防重入审计。
- 修改 `Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`：U7 新增英文资源。
- 修改 `CHANGELOG.md`、本计划和 U7 规格：回填测试、截图和现场偏差。

## 任务 1：共享展示策略与属性工作流

**文件：**
- 创建：`Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnPropertiesView.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`
- 修改：`Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

- [x] **步骤 1：编写路径边界和属性布局失败测试**

新增纯策略测试：

```swift
func testAuxiliaryPathPresentationOnlyRelativizesTargetsInsideWorkingCopy() {
    let wc = URL(fileURLWithPath: "/tmp/wc", isDirectory: true)
    XCTAssertEqual(MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc", workingCopy: wc), ".")
    XCTAssertEqual(MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc/src/a.swift", workingCopy: wc), "src/a.swift")
    XCTAssertEqual(MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc-other/a.swift", workingCopy: wc), "/tmp/wc-other/a.swift")
    XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "."), "工作副本根目录")
}
```

新增源码契约：属性页包含 `propertiesToolbar`、`propertiesMasterPane`、`propertyInspector`、`propertyEditor`、搜索和 `MacSvnAuxiliaryWorkflowMetrics.masterWidth`，且不包含 `HSplitView` / `VSplitView`。

在性能守卫增加属性页两种 SplitView 均为 false 的断言。

- [x] **步骤 2：运行测试并确认失败**

运行：

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests/testPropertiesWorkspaceAvoidsSplitViews
```

预期：展示策略类型不存在，属性页仍使用 `HSplitView`，测试失败。

- [x] **步骤 3：实现辅助页尺寸和路径策略**

创建：

```swift
enum MacSvnAuxiliaryWorkflowMetrics {
    static let toolbarHeight: CGFloat = 48
    static let masterWidth: CGFloat = 300
    static let masterMinimumWidth: CGFloat = 280
    static let masterMaximumWidth: CGFloat = 340
    static let detailMinimumWidth: CGFloat = 420
    static let feedbackHeight: CGFloat = 30
}

enum MacSvnAuxiliaryPathPresentation {
    static func relativePath(_ path: String, workingCopy: URL) -> String
    static func title(for path: String) -> String
}
```

使用 `standardizedFileURL`、根路径相等和带 `/` 的子路径前缀判断，禁止相邻目录误命中。

- [x] **步骤 4：重排属性页**

将页面拆为：

```swift
private var propertiesToolbar: some View
private var propertiesFeedback: some View
private var propertiesWorkspace: some View
private var propertiesMasterPane: some View
private var propertyInspector: some View
private var propertyList: some View
private var propertyEditor: some View
```

主区使用 `HStack(spacing: 0)` 和固定 `300 pt` 主栏。主栏增加搜索、结果数、单行中部截断和 tooltip。详情稳定显示 SVN 信息、属性列表/空态和可滚动编辑器；保存为唯一强调按钮，删除继续确认。Finder 绝对路径在消费 pending intent 时先转换为相对路径。

- [x] **步骤 5：运行属性、性能、Finder 和 Localization 测试**

运行：

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter PropertyViewModelTests
swift test --filter FinderSyncPackagingGuardTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter LocalizationResourceTests
```

预期：全部通过；属性读取/保存/删除、外部定义、信息 generation 隔离和 Finder 深链无回归。

- [x] **步骤 6：真实窗口验收并提交任务 1**

在 `980 x 640`、`1180 x 760`、`1440 x 900` 检查根目录、长路径、空属性、已有属性、编辑和错误状态，保存 `artifacts/ui/u7-properties-*.png`。

结果：U7/属性/Finder/性能/Localization 定向回归 `45/45` 通过；Release App 构建和结构校验通过。真实窗口证据为 `u7-properties-dark-980x640.png`、`u7-properties-light-1180x760.png`、`u7-properties-light-reduce-motion-1440x900.png`；截图驱动增加固定编辑器动作栏，保证三档窗口的保存按钮始终可达。

```bash
git add Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift \
  Sources/MacSvnApp/Features/MacSvnPropertiesView.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 重构人本属性工作流（U7 任务 1/6）"
```

## 任务 2：锁工作流

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnLocksView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`
- 修改：`Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

- [x] **步骤 1：编写锁布局和动作资格失败测试**

源码契约要求 `locksToolbar`、`locksMasterPane`、`lockDetailPane`、`eligibleReleasePaths`、`eligibleBreakPaths`、锁空态和 `HStack(spacing: 0)`；禁止 SplitView。保留 `LockActionPolicy.pathsEligibleForRelease` / `pathsEligibleForBreak`、项目属性模板、夺锁和打断锁确认。

- [x] **步骤 2：运行测试并确认失败**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests/testLocksUseTargetMasterDetailAndQualificationDrivenActions
swift test --filter WorkingCopyWorkspacePerformanceGuardTests/testLocksWorkspaceAvoidsSplitViews
```

预期：旧页仍平铺四个动作并使用 `HSplitView`，测试失败。

- [x] **步骤 3：实现锁主从布局和稳定状态**

目标主栏复用辅助路径标题规则，增加搜索和选择数。详情显示锁记录、所有者、创建时间、注释及明确空态。固定主操作只保留“获取锁”；释放和打断根据资格数组进入动作菜单，按钮 disabled 与实际执行使用同一数组。

- [x] **步骤 4：保持获取锁和高危确认语义**

获取锁 sheet 继续加载模板和最小说明长度；busy 时禁用取消以外的重复动作。夺锁、打断锁继续通过不可绕过的 confirmation dialog，取消时清理 pending confirmation。

- [x] **步骤 5：运行锁、导航、性能和 Localization 测试**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter LockViewModelTests
swift test --filter MacSvnAppNavigatorTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter LocalizationResourceTests
```

- [x] **步骤 6：真实窗口验收并提交任务 2**

检查无锁、本 WC 锁、他人锁、多选、获取 sheet、夺锁和打断确认，保存 `artifacts/ui/u7-locks-*.png`。

结果：U7/锁 ViewModel/锁动作策略/导航/性能/Localization 定向门禁 `75/75` 通过；Release App 构建和结构校验通过。真实窗口证据为 `u7-locks-dark-980x640.png`、`u7-locks-light-1180x760.png`、`u7-locks-light-reduce-motion-1440x900.png`、`u7-locks-get-sheet-dark.png`；获取锁 sheet 同时提供醒目的右上角关闭按钮、取消和默认动作。释放锁的 UI 资格进一步收紧为必须存在明确的“本工作副本持有锁”记录，缺少证据时不允许以 release 试探仓库状态。

```bash
git add Sources/MacSvnApp/Features/MacSvnLocksView.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 统一锁定任务与高危动作层级（U7 任务 2/6）"
```

## 任务 3：搁置与 Patch 工作流

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnShelveView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`
- 修改：`Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

- [x] **步骤 1：编写 shelf 列表/详情和性能失败测试**

源码契约要求 `shelveToolbar`、`shelfRecordList`、`shelfDetailPane`、`showCreateShelfSheet`、`selectedShelfID`、`DiffPerformanceLimits`，且禁止 SplitView。断言创建参数不再常驻主工具栏，每个列表行不再平铺五个按钮。

- [x] **步骤 2：运行测试并确认失败**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests/testShelveSeparatesCreationRecordSelectionAndPreviewActions
swift test --filter WorkingCopyWorkspacePerformanceGuardTests/testShelveWorkspaceAvoidsSplitViews
```

- [x] **步骤 3：实现创建 sheet 和记录主栏**

顶栏固定“新建搁置”、刷新和 Patch 菜单。创建 sheet 包含路径选择、名称、说明、官方/本地类型、保留本地改动和安全快照选项。主栏使用 segmented control 切换官方 shelves 与本地快照；行只负责选择记录。

- [x] **步骤 4：实现详情预览和语义动作**

详情区显示记录摘要、预览类型切换和截断后的等宽文本。官方 shelf 主操作为 Unshelve，本地快照主操作为恢复；Log/Diff、Unshelve + Drop、Drop、迁移和删除进入菜单。破坏性 Drop/删除新增显式确认。

- [x] **步骤 5：运行 Shelve、Patch、性能和 Localization 测试**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter ShelveViewModelTests
swift test --filter ShelveServiceTests
swift test --filter PatchViewModelTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter LocalizationResourceTests
```

- [x] **步骤 6：真实窗口验收并提交任务 3**

检查官方可用/不可用、空 shelf、本地快照、长 Diff、创建、恢复和 Patch sheet，保存 `artifacts/ui/u7-shelve-*.png`。

结果：U7/Shelve/Patch/导航/性能/Localization/Modal 定向门禁 `83/83` 通过；全量 `1076/1076` 通过，其中真实 SVN `49/49`；Release App 构建、结构校验和隔离启动冒烟通过。真实窗口证据为 `u7-shelve-dark-980x640.png`、`u7-shelve-light-1180x760.png`、`u7-shelve-light-reduce-motion-1440x900.png`、`u7-shelve-create-sheet-dark-980.png`、`u7-shelve-patch-sheet-dark-980.png` 和 `u7-shelve-main-light-reduce-motion-1440x900.png`。创建与 Patch sheet 均提供醒目的右上角关闭、Escape 和显式取消；Finder/深链绝对路径统一转换为工作副本相对路径并正确预选。预览通过代际校验、80 ms 防抖和 latest-wins runner 防止旧请求覆盖；迁移、Drop、Unshelve + Drop 与删除均保留确认，创建/Patch 错误留在当前 sheet 内展示。Tortoise inventory/H 清单无能力状态变化。

```bash
git add Sources/MacSvnApp/Features/MacSvnShelveView.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift \
  Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift
git commit -m "feat(UI): 重排搁置与 Patch 工作流（U7 任务 3/6）"
```

## 任务 4：可搜索且有脏状态的设置

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnSettingsCategory.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnSettingsView.swift`
- 修改：`Tests/MacSvnAppTests/SettingsInformationArchitectureTests.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- 修改：`Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

- [x] **步骤 1：编写分类搜索和草稿状态失败测试**

纯策略测试分类可按中文、英文和功能关键字匹配。源码契约要求 `settingsSearchText`、`filteredCategories`、`baselineDraft`、`currentDraft`、`hasUnsavedChanges`、`isSaving` 和固定 `settingsActionBar`。

```swift
func testSettingsCategoriesMatchHumanSearchTerms() {
    XCTAssertTrue(MacSvnSettingsCategory.network.matches(search: "代理"))
    XCTAssertTrue(MacSvnSettingsCategory.savedData.matches(search: "cache"))
    XCTAssertFalse(MacSvnSettingsCategory.ai.matches(search: "锁定"))
}
```

- [x] **步骤 2：运行测试并确认失败**

```bash
swift test --filter SettingsInformationArchitectureTests
swift test --filter HumanCenteredAuxiliaryWorkflowsTests/testSettingsExposeSearchDirtyStateAndStableSaveFeedback
```

- [x] **步骤 3：实现设置分类搜索**

为每类增加稳定 `searchKeywords` 和大小写/空白归一化 `matches(search:)`。侧栏搜索过滤分类；当前分类被过滤掉时选择第一个结果，无结果显示 `ContentUnavailableView`。

- [x] **步骤 4：实现可比较草稿和固定保存栏**

定义包含全部设置字段及 SVN managed config 字段的 `SettingsDraftSnapshot: Equatable`。加载后设置 `baselineDraft = currentDraft`；`hasUnsavedChanges` 比较快照；保存成功更新基线，失败保留草稿。`isSaving` 防止并发保存，底栏稳定显示脏状态、保存中、成功或错误。

- [x] **步骤 5：让校验错误定位到分类**

hook 校验失败选择 `.savedData`，外置工具规则失败选择 `.externalPrograms`，网络配置失败选择 `.network`。保存按钮只有 `hasUnsavedChanges && !isSaving` 时可用。

- [x] **步骤 6：运行设置、持久化、Finder、Localization 和全量映射测试**

```bash
swift test --filter SettingsInformationArchitectureTests
swift test --filter TortoiseParitySettingsPersistenceCoordinatorTests
swift test --filter SettingsStoreTests
swift test --filter FinderSyncPackagingGuardTests
swift test --filter LocalizationResourceTests
```

- [x] **步骤 7：真实窗口验收并提交任务 4**

检查九类、中文/英文搜索、无匹配、修改、保存中、保存成功、hook/外置工具错误和深色外观，保存 `artifacts/ui/u7-settings-*.png`。

结果：设置/U7/持久化/Finder/Localization/启动配置定向门禁 `73/73` 通过；全量 `1082/1082` 通过，其中真实 SVN `49/49`；Release App 构建、结构校验和隔离启动冒烟通过。真实窗口证据为 `u7-settings-dark-980x640.png`、`u7-settings-light-1180x760.png` 和 `u7-settings-light-reduce-motion-1440x900.png`，三档均保持可搜索侧栏、可滚动表单和固定保存栏，无重叠或动作不可达。分类支持中英文及功能词搜索，无结果提供清除动作；40 个可编辑字段与 SVN managed config 纳入草稿基线，加载/保存期间禁止覆盖或重复提交。Hook、外置工具和可识别的 SVN 配置错误会清除冲突搜索并定位到所属分类；Finder 导出失败保留脏状态以允许重试。新增仅在显式 `--ui-testing` 门控下生效的 `--ui-route`，用于确定性真实窗口验收。两轮只读审查发现的 4 个 Important 已全部修复，复核无新增 Critical/Important；Tortoise inventory/H 清单无能力状态变化。

```bash
git add Sources/MacSvnApp/Features/MacSvnSettingsCategory.swift \
  Sources/MacSvnApp/Features/MacSvnSettingsView.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/SettingsInformationArchitectureTests.swift \
  Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift
git commit -m "feat(UI): 增加可搜索设置与保存状态（U7 任务 4/6）"
```

## 任务 5：统一反馈与弹窗交互审计

**文件：**
- 修改：`Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnPropertiesView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnLocksView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnShelveView.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnSettingsView.swift`
- 修改：`Sources/MacSvnCore/ViewModels/LockViewModel.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- 修改：`Tests/MacSvnAppTests/ModalDismissalAccessibilityTests.swift`
- 修改：`Tests/MacSvnCoreTests/LockViewModelTests.swift`
- 修改：`Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

- [x] **步骤 1：编写反馈语义和弹窗防重入失败测试**

测试 `MacSvnAuxiliaryFeedback` 的 progress/success/warning/failure 图标与颜色角色互异。源码契约要求四页使用 `MacSvnInlineFeedbackView`，原始诊断通过 `.help` 可访问；所有异步 sheet 默认动作带 busy disabled，现有 modal close/escape/cancel 门禁保持。新增 dismissal 策略测试，要求 dirty sheet 的关闭按钮和 Escape 走同一个放弃确认入口。

- [x] **步骤 2：运行测试并确认失败**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter ModalDismissalAccessibilityTests
```

- [x] **步骤 3：实现共享反馈模型和视图**

```swift
enum MacSvnAuxiliaryFeedbackKind: Equatable {
    case progress, success, warning, failure
}

struct MacSvnAuxiliaryFeedback: Equatable {
    let kind: MacSvnAuxiliaryFeedbackKind
    let message: String
    let diagnostic: String?
}
```

反馈视图使用稳定高度、图标+文字、单行中部/尾部截断和 diagnostic tooltip，不以颜色作为唯一信息。

扩展共享关闭 API：

```swift
func macSvnDismissibleSheet(
    preventsDismissal: Bool = false,
    onDismissalBlocked: @escaping () -> Void = {}
) -> some View
```

关闭按钮和 `.cancelAction` 统一调用 requestDismiss；`preventsDismissal` 为 true 时执行 `onDismissalBlocked`，否则 dismiss。内容同时使用 `.interactiveDismissDisabled(preventsDismissal)`，防止系统交互绕过。

- [x] **步骤 4：迁移四页状态并审计 sheet**

属性、锁、搁置和设置把加载、成功、警告、失败映射为共享反馈。可恢复加载失败提供页面现有刷新动作；认证/SSL、网络和超时调用 `MacSvnCoreModeErrorPresentation.message`。保存 external、获取锁、Patch、创建 shelf 和设置保存均在 busy 时阻止重复执行。

外部定义、获取锁、创建 shelf 和 Patch sheet 分别保存展示时的初始草稿；当前草稿不同且操作未提交时，右上角关闭、Escape 和“取消”均弹出“放弃未保存更改”确认。确认放弃后清理草稿并关闭，继续编辑则保留全部输入；busy 状态不允许关闭正在执行的事务。

- [x] **步骤 5：运行 U7 定向、Modal、Localization 和业务测试**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter ModalDismissalAccessibilityTests
swift test --filter LocalizationResourceTests
swift test --filter PropertyViewModelTests
swift test --filter LockViewModelTests
swift test --filter ShelveViewModelTests
swift test --filter SettingsInformationArchitectureTests
```

- [x] **步骤 6：提交任务 5**

结果：共享反馈、诊断 tooltip、dirty 放弃确认、busy 防关闭/防重入和统一关闭入口均已覆盖；全仓 `28` 个 sheet 与 `4` 个 popover 的关闭可达性门禁通过。全量 `swift test --quiet` 为 `1114/1114` 通过，其中真实 SVN `49/49`；Release App 构建、结构校验、英文资源 `plutil` 校验、隔离启动冒烟和 `git diff --check` 均通过。规格审查与代码质量复核最终均为 `0 Critical / 0 Important / 0 Minor`，质量复核相关门禁 `22/22` 通过。锁属性加载增加代际保护并保留原始诊断，刷新可从错误状态恢复；Shelf 官方加载失败仍保留本地快照预览；Properties 刷新和目标切换不再残留旧反馈。Tortoise inventory/H 清单无能力状态变化，不修改。

```bash
git add Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift \
  Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift \
  Sources/MacSvnApp/Features/MacSvnPropertiesView.swift \
  Sources/MacSvnApp/Features/MacSvnLocksView.swift \
  Sources/MacSvnApp/Features/MacSvnShelveView.swift \
  Sources/MacSvnApp/Features/MacSvnSettingsView.swift \
  Sources/MacSvnCore/ViewModels/LockViewModel.swift \
  Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift \
  Tests/MacSvnAppTests/ModalDismissalAccessibilityTests.swift \
  Tests/MacSvnCoreTests/LockViewModelTests.swift \
  docs/superpowers/plans/2026-07-15-human-centered-auxiliary-workflows-ui.md
git commit -m "feat(UI): 统一辅助任务反馈与弹窗状态（U7 任务 5/6）"
```

## 任务 6：全量验证、真实窗口修正与文档收口

**文件：**
- 修改：`CHANGELOG.md`
- 修改：`docs/superpowers/specs/2026-07-15-human-centered-auxiliary-workflows-ui-design.md`
- 修改：`docs/superpowers/plans/2026-07-15-human-centered-auxiliary-workflows-ui.md`
- 修改：真实窗口验收暴露问题对应的 U7 SwiftUI 文件和测试

- [ ] **步骤 1：运行 U7 定向门禁**

```bash
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter ModalDismissalAccessibilityTests
swift test --filter SettingsInformationArchitectureTests
swift test --filter LocalizationResourceTests
```

- [ ] **步骤 2：运行全量测试**

运行 `swift test`，要求全部通过且真实 SVN `49/49` 保持。

- [ ] **步骤 3：构建、校验和冒烟最终 App**

```bash
./scripts/build-macos-app.sh
./scripts/verify-macos-app.sh dist/SVNStudio.app
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
```

- [ ] **步骤 4：三档四页真实窗口验收**

在 `980 x 640`、`1180 x 760`、`1440 x 900` 检查属性、锁、搁置和设置；覆盖浅色、深色、Reduce Motion、长文本、空态、错误、busy、sheet、Escape、键盘焦点和 VoiceOver。截图保存为 `artifacts/ui/u7-*.png`。

- [ ] **步骤 5：按截图问题继续 TDD 修正**

每个重叠、截断失控、动作不可达、状态跳动或关闭缺口先在 U7 测试增加精确失败断言，再修改视图并重跑定向测试和截图。

- [ ] **步骤 6：更新文档和最终验证**

CHANGELOG 记录辅助工作流、设置、反馈和能力保留；U7 规格追加测试数量、截图路径、现场偏差和 U8 边界。运行：

```bash
git diff --check
swift test
./scripts/build-macos-app.sh
./scripts/verify-macos-app.sh dist/SVNStudio.app
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
git status --short
```

- [ ] **步骤 7：提交 U7 收口**

```bash
git add CHANGELOG.md \
  docs/superpowers/specs/2026-07-15-human-centered-auxiliary-workflows-ui-design.md \
  docs/superpowers/plans/2026-07-15-human-centered-auxiliary-workflows-ui.md \
  Sources/MacSvnApp Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings \
  Tests/MacSvnAppTests
git commit -m "feat(UI): 完成人本辅助工作流统一（U7 任务 6/6）"
```

完成 U7 后继续 U8 全局体验收口；不得把 U7 完成误报为整个 Human UI 长程目标完成。
