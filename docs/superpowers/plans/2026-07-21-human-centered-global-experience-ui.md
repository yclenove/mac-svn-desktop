# SVN Studio 人本全局体验收口（U8）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Human UI Wave U8——统一全局键盘流、无障碍标识、Reduce Motion、性能守卫扩展与跨页真人任务验收，从而收口整个 Human UI 长程目标。

**Architecture:** 新增纯策略模块 `MacSvnGlobalExperiencePresentation.swift`，定义键盘契约、页面 shortcut 需求与 MotionPolicy；各高频页按契约接线 ⌘F/⌘R 与 a11y identifier；扩展源码门禁测试；真实窗口验收后回填文档。不重做 U5–U7 布局，不删减能力。

**Tech Stack:** SwiftUI、XCTest、现有 MacSvnApp / MacSvnCore、UI testing launch 参数、`artifacts/ui/u8-*.png`。

**规格：** `docs/superpowers/specs/2026-07-21-human-centered-global-experience-ui-design.md`

---

## 文件结构

- 创建：`Sources/MacSvnApp/Features/MacSvnGlobalExperiencePresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredGlobalExperienceTests.swift`
- 修改：`Sources/MacSvnApp/Features/MacSvnChangesView.swift`（⌘F/⌘R、搜索 identifier）
- 修改：`Sources/MacSvnApp/Features/MacSvnLogView.swift`（⌘R）
- 修改：`Sources/MacSvnApp/Features/MacSvnBranchesView.swift`（⌘R）
- 修改：`Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift`（⌘R）
- 修改：`Sources/MacSvnApp/Features/MacSvnDiffView.swift`（⌘R）
- 修改：`Sources/MacSvnApp/Features/MacSvnCommitView.swift`（⌘R + MotionPolicy）
- 修改：`Tests/MacSvnAppTests/WorkingCopyWorkspacePerformanceGuardTests.swift`（可选扩展）
- 修改：`Tests/MacSvnAppTests/ModalDismissalAccessibilityTests.swift`（若需补全局标识审计）
- 修改：`CHANGELOG.md`、本计划、U8 规格
- 截图：`artifacts/ui/u8-*.png`（不提交）

---

## 任务 1：全局键盘契约与策略模块

**文件：**
- 创建：`Sources/MacSvnApp/Features/MacSvnGlobalExperiencePresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredGlobalExperienceTests.swift`

- [ ] **步骤 1：编写失败测试**

```swift
func testKeyboardContractRequiresSearchFocusForSearchablePages() {
    XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .changes))
    XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .log))
    XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .branches))
    XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .commit))
}

func testKeyboardContractRequiresRefreshForRefreshablePages() {
    for page in MacSvnGlobalKeyboardPage.allCases where page != .about {
        XCTAssertTrue(
            MacSvnGlobalKeyboardContract.requiresRefreshShortcut(for: page),
            "\(page) should support ⌘R"
        )
    }
}

func testMotionPolicyDisablesAnimationWhenReduceMotionOverrideIsTrue() {
    XCTAssertFalse(MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: false, override: true))
    XCTAssertFalse(MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: true, override: nil))
    XCTAssertTrue(MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: false, override: nil))
}
```

源码门禁（先写断言，实现前失败）：变更页含 `keyboardShortcut("f"` 与 `keyboardShortcut("r"`，以及 `macSvn.changes.search` / `macSvn.changes.refresh`。

- [ ] **步骤 2：运行并确认失败**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
```

- [ ] **步骤 3：实现策略模块**

```swift
enum MacSvnGlobalKeyboardPage: String, CaseIterable {
    case changes, log, repoBrowser, branches, conflicts, diff, commit
    case properties, locks, shelve, settings
    case about // 对照：不要求刷新
}

enum MacSvnGlobalKeyboardContract {
    static func requiresSearchFocus(for page: MacSvnGlobalKeyboardPage) -> Bool
    static func requiresRefreshShortcut(for page: MacSvnGlobalKeyboardPage) -> Bool
    static func searchAccessibilityIdentifier(for page: MacSvnGlobalKeyboardPage) -> String?
    static func refreshAccessibilityIdentifier(for page: MacSvnGlobalKeyboardPage) -> String?
}

enum MacSvnMotionPolicy {
    static func shouldAnimate(accessibilityReduceMotion: Bool, override: Bool?) -> Bool
    static func run(accessibilityReduceMotion: Bool, override: Bool?, animation: Animation, _ body: () -> Void)
}
```

- [ ] **步骤 4：重跑策略测试至绿**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
```

- [ ] **步骤 5：提交任务 1**

```bash
git add Sources/MacSvnApp/Features/MacSvnGlobalExperiencePresentation.swift \
  Tests/MacSvnAppTests/HumanCenteredGlobalExperienceTests.swift
git commit -m "feat(UI): 增加全局键盘与动效契约（U8 任务 1）"
```

---

## 任务 2：变更页 ⌘F / ⌘R 与标识符

**文件：**
- 修改：`Sources/MacSvnApp/Features/MacSvnChangesView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredGlobalExperienceTests.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredWorkingCopyWorkspaceTests.swift`（若需）

- [ ] **步骤 1：失败测试**

断言 `MacSvnChangesView.swift` 包含：

- `@FocusState` 与搜索 `TextField` 的 `.focused`
- 隐藏 `Button` 或等价接线：`keyboardShortcut("f", modifiers: .command)`
- 刷新按钮：`keyboardShortcut("r", modifiers: .command)` 且 `disabled` 与 busy 同步
- `accessibilityIdentifier("macSvn.changes.search")` 与 `macSvn.changes.refresh`

- [ ] **步骤 2：实现**

对齐 U7 Properties 模式：

```swift
@FocusState private var isSearchFocused: Bool
// background 隐藏 Button 触发 isSearchFocused = true + ⌘F
// 刷新 Button 增加 ⌘R 与 identifier
// 搜索 TextField 增加 identifier 与 focused
```

- [ ] **步骤 3：定向测试**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
```

- [ ] **步骤 4：提交**

```bash
git commit -m "feat(UI): 变更页补齐搜索与刷新快捷键（U8 任务 2）"
```

---

## 任务 3：历史 / 分支 / 冲突 / Diff / 提交 ⌘R

**文件：**
- 修改：`MacSvnLogView.swift`、`MacSvnBranchesView.swift`、`MacSvnConflictWorkspaceView.swift`、`MacSvnDiffView.swift`、`MacSvnCommitView.swift`
- 修改：`HumanCenteredGlobalExperienceTests.swift`

- [ ] **步骤 1：源码门禁失败测试**

各文件刷新按钮须含 `keyboardShortcut("r", modifiers: .command)` 与对应 `macSvn.<page>.refresh`（或已有 label 保留并追加 identifier）。

- [ ] **步骤 2：逐页接线**

与工具栏现有刷新闭包相同；`disabled` 与 loading/resolving 同步。

- [ ] **步骤 3：Commit 走 MotionPolicy**

替换 `withAnimation` 分支为 `MacSvnMotionPolicy.run(...)`。

- [ ] **步骤 4：定向测试**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
swift test --filter HumanCenteredCoreModesTests
swift test --filter HumanCenteredWorkingCopyWorkspaceTests
```

- [ ] **步骤 5：提交**

```bash
git commit -m "feat(UI): 核心页统一刷新快捷键与动效策略（U8 任务 3）"
```

---

## 任务 4：全局 a11y / 性能守卫与 U7 回归

**文件：**
- 修改：`WorkingCopyWorkspacePerformanceGuardTests.swift`、`ModalDismissalAccessibilityTests.swift`、`HumanCenteredGlobalExperienceTests.swift`
- 必要时为侧栏/模式切换补 identifier（不改布局）

- [ ] **步骤 1：门禁**

- 工作区 SplitView 禁令不回退；
- 全仓 sheet 仍走 `macSvnDismissibleSheet`；
- U7 辅助页仍含 ⌘F/⌘R；
- MotionPolicy 被 Commit 引用。

- [ ] **步骤 2：运行**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
swift test --filter ModalDismissalAccessibilityTests
swift test --filter HumanCenteredAuxiliaryWorkflowsTests
```

- [ ] **步骤 3：提交**

```bash
git commit -m "test(UI): 扩展全局体验源码门禁（U8 任务 4）"
```

---

## 任务 5：全量验证、真实窗口与文档收口

**文件：**
- 修改：`CHANGELOG.md`、U8 规格、本计划
- 截图：`artifacts/ui/u8-*.png`（不提交）

- [ ] **步骤 1：定向 + 全量**

```bash
swift test --filter HumanCenteredGlobalExperienceTests
swift test
# 真实 SVN 49/49 保持
```

- [ ] **步骤 2：构建与冒烟**

```bash
./scripts/build-macos-app.sh
./scripts/verify-macos-app.sh dist/SVNStudio.app
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
git diff --check
```

- [ ] **步骤 3：三档 + 跨页真人任务**

窗口：`980×640`、`1180×760`、`1440×900`；覆盖浅色、深色、Reduce Motion；任务 T1–T6。截图 `artifacts/ui/u8-*.png`。

发现问题：先补失败测试，再修，禁止砍功能。

- [ ] **步骤 4：回填文档**

记录测试数量、截图、现场偏差、residual；声明 **Human UI 长程目标完成**；inventory / H-tortoise 仅能力真变时改。

- [ ] **步骤 5：最终提交**

```bash
git add CHANGELOG.md \
  docs/superpowers/specs/2026-07-21-human-centered-global-experience-ui-design.md \
  docs/superpowers/plans/2026-07-21-human-centered-global-experience-ui.md \
  Sources/MacSvnApp Tests/MacSvnAppTests
git commit -m "feat(UI): 完成人本全局体验收口（U8）"
```

完成 U8 后，整个 Human UI（U5–U8）长程目标完成。不重启 Tortoise Perfect Loop。

---

## 完成口径提醒

- VoiceOver / 真实按键：自动化契约 + residual；与 U6/U7 一致；
- 截图不入库；
- 禁止因 residual 删减功能；
- 未完成 U8 前不得标记整个 Human UI 完成。
