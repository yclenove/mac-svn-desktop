# 人本专业工具面（ST）实现计划

> **面向 AI 代理的工作者：** 推荐使用 subagent-driven-development 或 executing-plans 逐任务实现。步骤使用复选框（`- [ ]`）跟踪进度。

**目标：** 将 Blame、AI Assistant、Git 迁移、Release Notes 等专业/差异化工具面，统一到 U5–U8 的人本交互语言（工具栏、反馈、键盘、关闭、Reduce Motion、a11y），且不删减 AI 确认门与迁移写路径能力。

**架构：** 新增纯策略呈现模块 `MacSvnSpecializedToolsPresentation` + 定向源码门禁测试；逐页接线现有 View；独立页允许单层 HSplitView 并门禁锁边界；最终三档窗口截图与全量门禁收口。

**技术栈：** SwiftUI、XCTest、现有 MacSvnApp / MacSvnCore、UI testing launch 参数、`artifacts/ui/st-*.png`。

**规格：** `docs/superpowers/specs/2026-07-21-human-centered-specialized-tools-ui-design.md`

**约束：**

- 不重启 Tortoise Perfect Loop / wake / heartbeat；
- inventory / H-tortoise 仅能力真变时改；
- artifacts 不入库；
- 发现问题先补失败测试再修，禁止降级砍功能；
- 环境 unrestricted FS、approval never → 自主执行不请求权限。

---

## 文件结构

- 创建：`Sources/MacSvnApp/Features/MacSvnSpecializedToolsPresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredSpecializedToolsTests.swift`
- 修改：`MacSvnBlameView.swift`、`MacSvnAIAssistantView.swift`、`MacSvnGitMigrationView.swift`、`MacSvnReleaseNotesView.swift`（必要时 `MacSvnAIProviderSettingsView.swift`）
- 修改：`CHANGELOG.md`、本计划、ST 规格、`docs/README.md`
- 截图：`artifacts/ui/st-*.png`（不提交）

---

## 任务 1：ST 契约模块与失败测试骨架

**文件：**

- 创建：`Sources/MacSvnApp/Features/MacSvnSpecializedToolsPresentation.swift`
- 创建：`Tests/MacSvnAppTests/HumanCenteredSpecializedToolsTests.swift`

- [ ] **步骤 1：编写失败测试**

断言：

- `MacSvnSpecializedToolsPage` 含 `blame` / `aiAssistant` / `gitMigration` / `releaseNotes`
- Blame / AI / Release Notes 需要 ⌘R；Git Migration 若有显式刷新则需要，否则契约表写清
- a11y id：`macSvn.st.blame.refresh` 等
- 度量：toolbarHeight == 48，feedbackHeight == 30
- 源码门禁（实现前可先对缺失 id 失败）：四目标文件将接线 refresh shortcut

```swift
func testSpecializedPagesExposeStableAccessibilityIdentifiers() {
    XCTAssertEqual(
        MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: .blame),
        "macSvn.st.blame.refresh"
    )
}
```

- [ ] **步骤 2：运行确认失败**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
```

- [ ] **步骤 3：实现策略模块**

```swift
enum MacSvnSpecializedToolsPage: String, CaseIterable, Sendable {
    case blame, aiAssistant, gitMigration, releaseNotes
}

enum MacSvnSpecializedToolsMetrics {
    static let toolbarHeight: CGFloat = 48
    static let feedbackBarHeight: CGFloat = 30
    static let iconButtonMinSide: CGFloat = 28
}

enum MacSvnSpecializedToolsContract {
    static func requiresRefreshShortcut(for page: MacSvnSpecializedToolsPage) -> Bool
    static func requiresSearchFocus(for page: MacSvnSpecializedToolsPage) -> Bool
    static func refreshAccessibilityIdentifier(for page: MacSvnSpecializedToolsPage) -> String?
    static func searchAccessibilityIdentifier(for page: MacSvnSpecializedToolsPage) -> String?
}
```

- [ ] **步骤 4：定向测试通过并提交**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
git add Sources/MacSvnApp/Features/MacSvnSpecializedToolsPresentation.swift \
  Tests/MacSvnAppTests/HumanCenteredSpecializedToolsTests.swift
git commit -m "feat(UI): 增加专业工具面契约模块（ST 任务 1）"
```

---

## 任务 2：Blame 人本接线

**文件：**

- 修改：`Sources/MacSvnApp/Features/MacSvnBlameView.swift`
- 修改：`Tests/MacSvnAppTests/HumanCenteredSpecializedToolsTests.swift`

- [ ] **步骤 1：失败测试**

源码门禁：

- 含 `keyboardShortcut("r", modifiers: .command)`
- 含 `macSvn.st.blame.refresh`
- `HSplitView` 至多 1 处；无 `VSplitView`
- 若有装饰动画则引用 `MacSvnMotionPolicy`

- [ ] **步骤 2：实现**

- 工具栏高度对齐 `MacSvnSpecializedToolsMetrics.toolbarHeight`
- 刷新按钮 ⌘R + identifier；loading 时 disabled
- 主错误/空态上提为稳定反馈区（可复用 Auxiliary 反馈样式）
- 保持外置 Blame、范围、比较、演化解释能力

- [ ] **步骤 3：定向测试**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
swift test --filter Blame
```

- [ ] **步骤 4：提交**

```bash
git commit -m "feat(UI): 统一 Blame 工具栏与刷新契约（ST 任务 2）"
```

---

## 任务 3：AI Assistant 人本接线

**文件：**

- 修改：`Sources/MacSvnApp/Features/MacSvnAIAssistantView.swift`
- 修改：`HumanCenteredSpecializedToolsTests.swift`

- [ ] **步骤 1：失败测试**

- `macSvn.st.aiAssistant.refresh`（或明确「无刷新语义」时契约 `requiresRefreshShortcut == false` 且测试同步）
- 发送/主操作 busy 时 disabled 可测路径
- 单层 `HSplitView` 边界
- **禁止**削弱写工具确认门：源码仍含确认/审计相关符号（现有命名）

- [ ] **步骤 2：实现**

- 固定列表 | 消息 | 输入层级
- 发送中防重入
- 错误反馈条
- 可选 ⌘R 刷新上下文

- [ ] **步骤 3：定向测试**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
swift test --filter AI
```

- [ ] **步骤 4：提交**

```bash
git commit -m "feat(UI): 统一 AI 助手布局与忙态门禁（ST 任务 3）"
```

---

## 任务 4：Git 迁移 + Release Notes

**文件：**

- 修改：`MacSvnGitMigrationView.swift`、`MacSvnReleaseNotesView.swift`
- 修改：`HumanCenteredSpecializedToolsTests.swift`

- [ ] **步骤 1：失败测试**

- Release Notes：`macSvn.st.releaseNotes.refresh` 或生成动作 identifier；generating 时主按钮 disabled
- Git Migration：关键执行按钮 busy disabled；错误反馈可见；对账失败阻断路径符号保留

- [ ] **步骤 2：实现**

- 迁移页分区与统一反馈
- Release Notes 生成 busy/空态/错误对齐
- 所有 sheet 继续 dismissible 关闭栏

- [ ] **步骤 3：定向测试**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
swift test --filter GitMigration
swift test --filter ReleaseNotes
```

- [ ] **步骤 4：提交**

```bash
git commit -m "feat(UI): 统一迁移与发布说明反馈（ST 任务 4）"
```

---

## 任务 5：全量验证、真实窗口与文档收口

**文件：**

- 修改：`CHANGELOG.md`、ST 规格 §10、本计划、`docs/README.md`、必要时 README 状态行
- 截图：`artifacts/ui/st-*.png`（不提交）

- [ ] **步骤 1：定向 + 全量**

```bash
swift test --filter HumanCenteredSpecializedToolsTests
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

- [ ] **步骤 3：三档真实窗口**

覆盖 Blame / AI / Git Migration / Release Notes 至少各一档组合，浅色/深色/Reduce Motion 抽样；截图 `artifacts/ui/st-*.png`。

- [ ] **步骤 4：回填文档**

测试数量、截图、residual（含独立 HSplitView、TCC a11y、Developer ID 凭据阻塞仍在包装层）。

- [ ] **步骤 5：最终提交**

```bash
git add CHANGELOG.md docs Sources/MacSvnApp Tests/MacSvnAppTests
git commit -m "feat(UI): 完成人本专业工具面统一（ST）"
```

---

## 完成口径提醒

- ST 是 **U5–U8 之后的新波次**，不重开 Perfect Loop；
- VoiceOver / 真实按键：自动化契约 + residual；
- 截图不入库；
- 禁止因 residual 删减 AI/迁移/Blame 能力；
- 未完成任务 5 前不得标记 ST 完成。
