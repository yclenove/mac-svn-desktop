# SVN Studio 人本全局体验收口 UI/UX 设计

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-21 |
| 产品 | SVN Studio |
| 状态 | 已完成（2026-07-21 验收收口） |
| 对应迭代 | Human UI Wave U8 |

## 1. 背景

U5–U7 已分别收口高频变更工作区、核心模式与辅助工作流，但跨页体验仍存在以下全局缺口：

- **键盘流不统一**：属性 / 锁 / 搁置 / 设置 / 仓库浏览 / 历史已有 ⌘F 或 ⌘R，但变更页有搜索无 ⌘F 焦点、有刷新无 ⌘R；历史有 ⌘F 无 ⌘R；分支 / 冲突 / Diff / 提交检查器的刷新多为图标按钮，缺少与可刷新页一致的 Command-R 契约；
- **无障碍契约碎片化**：共享关闭栏已提供 `macSvn.modal.close`，但导航、主工具栏、搜索框、busy/error 区域缺少全局 identifier 命名约定与源码门禁；
- **动效守卫局部化**：Reduce Motion 仅在提交检查器折叠动画与 UI 测试 launch override 接线；多数页若引入动画时缺少统一助手；
- **性能守卫覆盖面**：U5–U7 主工作区已禁止自由 SplitView；Diff 主路径、Blame、AI 辅助、独立提交页仍使用 `HSplitView`，需明确嵌入/独立边界与 residual；
- **跨页真人任务未闭环**：尚无统一清单覆盖“从变更到提交 / 从历史到 Diff / 从冲突回变更 / 从设置保存后回工作区”等跨模式任务。

U8 是 Human UI 长程目标的**最后一波**。完成 U8 后，可标记整个 Human UI 长程目标完成；完成前不得把 U5–U7 误报为全局完成。

业务能力、SVN 命令语义、深链、命令面板和现有 Tortoise 对标能力不得删减。允许统一快捷键、标识符与动效呈现，不允许以“简化体验”为理由砍掉能力。

## 2. 方案选择

### 方案 A：逐页补快捷键

只在各页零散加 `keyboardShortcut`。改动最少，但命名、冲突处理和 a11y 契约仍各自为政，无法做源码门禁与真人任务验收矩阵。

### 方案 B：全局契约 + 高频页接线 + 守卫扩展（采用）

1. 用纯策略表定义“可搜索页 / 可刷新页 / 可关闭弹窗”的键盘与 a11y 契约；
2. 对变更、历史、Diff、提交、分支、冲突等高频页补齐 ⌘F / ⌘R；
3. 统一 Reduce Motion 助手，提交检查器与后续动画统一调用；
4. 扩展性能与 a11y 源码门禁；
5. 以三档窗口 + 跨页真人任务清单做最终收口。

### 方案 C：系统级 NSMenu 全局命令

把所有刷新/搜索提升到 `CommandMenu` / 主菜单。长期更“原生”，但会改导航焦点模型与模态冲突规则，超出 U8 可控范围；本波次仍以页内 shortcut + FocusState 为主，与 U7 一致。

## 3. 全局键盘契约

### 3.1 契约表

| 场景 | 快捷键 | 行为 | 不适用时 |
|------|--------|------|----------|
| 可搜索页有搜索框 | ⌘F | 聚焦搜索 / 过滤字段 | 无搜索字段的页不接线 |
| 可刷新页 | ⌘R | 触发与工具栏刷新相同的动作；busy 时禁用 | 无刷新语义的页不接线 |
| 可关闭 sheet/popover | Esc / 关闭按钮 | 走 `MacSvnDismissiblePresentation`；dirty 确认；busy 禁止关闭 | 系统 alert 仍走系统按钮 |
| 默认主操作 | Return（defaultAction） | 仅当前焦点 sheet 或明确主按钮 | 破坏性操作不得成为静默默认 |
| 命令面板 | ⌘K | 保持现有 RootView 行为 | — |

### 3.2 页面接线清单

| 页面 | ⌘F | ⌘R | 备注 |
|------|----|----|------|
| 变更 Changes | 必须：聚焦“搜索文件名” | 必须：刷新本地状态 | U8 补齐 |
| 历史 Log | 已有 | 必须：刷新历史 | U8 补 ⌘R |
| 仓库浏览 Repo | 可选（URL 栏已有焦点流） | 已有 | 保持 |
| 分支 Branches | 无搜索框则跳过 | 必须：刷新分支与标签 | U8 补 ⌘R |
| 冲突 Conflicts | 若有路径搜索则聚焦 | 必须：刷新冲突 | U8 补 ⌘R |
| Diff | 无列表搜索则跳过 | 必须：刷新当前差异 | U8 补 ⌘R |
| 提交 Commit（嵌入） | 无 | 必须：刷新提交候选 | U8 补 ⌘R |
| 属性 / 锁 / 搁置 / 设置 | 已有 | 已有 | 保持 U7 |

### 3.3 冲突与优先级

- 同一窗口同时可见多个可刷新区域时，⌘R 绑定**当前模式主视图**的刷新（由 `MacSvnWorkspaceMode` 决定可见页）；
- sheet 打开时，页级 ⌘R/⌘F 仍可存在，但 Esc 与 defaultAction 优先属于 sheet；
- busy 时刷新按钮与 ⌘R 同步禁用，禁止重复提交。

## 4. 全局无障碍契约

### 4.1 标识符命名

采用点分前缀，与关闭栏一致：

| 区域 | identifier 模式 | 示例 |
|------|-----------------|------|
| 模态关闭 | `macSvn.modal.close` | 已有 |
| 主侧栏 | `macSvn.sidebar.*` | `macSvn.sidebar.workingCopies` |
| 模式切换 | `macSvn.mode.*` | `macSvn.mode.changes` |
| 页级搜索 | `macSvn.<page>.search` | `macSvn.changes.search` |
| 页级刷新 | `macSvn.<page>.refresh` | `macSvn.changes.refresh` |
| 页级 busy/error | `macSvn.<page>.busy` / `macSvn.<page>.error` | 可选，有稳定区域时接线 |

### 4.2 VoiceOver 完成口径

与 U6/U7 对齐：

- **完成证据**：可达关闭按钮、tooltip、accessibility label/identifier、Escape、busy/dirty 真值表、⌘F/⌘R 源码与策略测试；
- **Residual**：宿主 `AXIsProcessTrusted=false`、System Events 1002、动态 VO 遍历与真实按键注入；记入验收 residual，**禁止**据此删减功能。

## 5. 动效与 Reduce Motion

```swift
enum MacSvnMotionPolicy {
    static func shouldAnimate(
        accessibilityReduceMotion: Bool,
        override: Bool?
    ) -> Bool

    static func run(
        accessibilityReduceMotion: Bool,
        override: Bool?,
        animation: Animation = .easeInOut(duration: 0.18),
        _ body: () -> Void
    )
}
```

规则：

1. `override ?? accessibilityReduceMotion == true` 时禁止装饰性 `withAnimation`；
2. 提交检查器折叠/展开必须走该策略；
3. 后续新增动画必须调用 `MacSvnMotionPolicy`，由源码门禁抽检关键路径。

## 6. 性能与视觉一致性

### 6.1 性能

- 保持 U5–U7：变更工作区、仓库、冲突、属性、锁、搁置主组合层禁止 `HSplitView {` / `VSplitView {`；
- Diff 超长文本继续走 `DiffPerformanceLimits`；
- 独立提交页 / Blame / AI 辅助若仍使用 SplitView，必须在规格 residual 中标明“非嵌入工作区路径”，且不得回退到变更工作区嵌入路径。

### 6.2 视觉度量

跨页统一复用：

- 工具栏高度：`48`（Core / Auxiliary metrics 已对齐）；
- 图标按钮命中区：至少 `28 x 28`；
- 反馈条高度：辅助页 `30`；
- 三档窗口：`980×640`、`1180×760`、`1440×900` 无横向工具栏滚动、无关键动作不可达。

## 7. 跨页真人任务清单

| ID | 任务 | 通过标准 |
|----|------|----------|
| T1 | 变更：搜索 → 选文件 → Diff → 展开提交 → 填写说明 | 主路径无重叠、提交为唯一强调 |
| T2 | 历史：⌘F 过滤 → 选修订 → 打开 Diff/统一 Diff | 筛选与详情稳定 |
| T3 | 冲突：刷新 → 选冲突 → 策略/返回变更 | busy 时禁用刷新与危险动作 |
| T4 | 设置：搜索分类 → 改草稿 → dirty 关闭确认 → 保存 | 保存栏固定、dirty 契约 |
| T5 | 属性/锁/搁置：刷新与搜索键盘可达 | 与 U7 一致 |
| T6 | 任意 sheet：Esc / 关闭按钮 / busy 禁止关闭 | 共享关闭栏 |

截图命名：`artifacts/ui/u8-*.png`，不进入 Git。

## 8. 测试策略

| 类型 | 覆盖 |
|------|------|
| 纯策略 | 键盘契约表、MotionPolicy、页面是否需要 ⌘F/⌘R |
| 源码门禁 | 变更/历史/分支/冲突/Diff/提交含 `keyboardShortcut("f"|"r")` 与 FocusState；禁止工作区 SplitView；关闭栏 identifier |
| 现有回归 | ModalDismissal、HumanCentered*、PerformanceGuard、Localization |
| 真实窗口 | 三档 + 浅色/深色/Reduce Motion + 跨页任务 T1–T6 |
| 全量 | `swift test`、真实 SVN 49/49、build/verify/smoke |

## 9. 非目标

- 不重做 U5–U7 布局；
- 不推进 Tortoise Perfect Loop、不创建 wake/heartbeat；
- 不把菜单栏 Command 重构为唯一快捷键来源；
- 不因 TCC 限制砍功能；
- 不修改 inventory / H-tortoise，除非能力状态真实变化。

## 10. 完成定义

U8 只有同时满足以下条件才完成：

1. 全局键盘契约表落地，变更/历史/分支/冲突/Diff/提交按表接线，U7 辅助页不回归；
2. 关键 a11y identifier/label 与关闭栏契约保持，Modal 门禁绿；
3. Reduce Motion 策略统一，提交检查器与策略测试覆盖；
4. 性能守卫不回退；残留 SplitView 路径有文档；
5. 三档窗口与跨页真人任务有截图与记录；
6. 定向 + 全量 `swift test`、真实 SVN 49/49、build/verify/smoke、`git diff --check` 通过；
7. CHANGELOG、本规格与计划回填测试数量、截图、偏差；明确 **Human UI 长程目标完成**。

## 11. 风险与 residual

| 风险 | 处理 |
|------|------|
| TCC 阻止真实按键注入 / 动态 VO | 自动化契约 + residual，不砍功能 |
| 多刷新区域 ⌘R 歧义 | 绑定当前 workspace mode 主视图 |
| Diff/Blame/AI 独立页 SplitView | 文档 residual；禁止污染嵌入变更工作区 |
| UI testing 窗口尺寸略偏 | 与 U7 同：记录现场偏差，主动作可达即可 |

## 12. 验收记录

### 12.1 日期与范围

- 完成日期：2026-07-21
- 范围：U8 全局键盘流、无障碍标识符、Reduce Motion 策略、性能守卫不回退、跨页真人任务 T1–T6 与文档收口
- 对应提交：`feat(UI): 完成人本全局体验收口（U8）`

### 12.2 自动化与应用门禁

- U8 定向 `HumanCenteredGlobalExperienceTests`：`10/10` 通过（键盘契约、MotionPolicy、⌘F/⌘R 源码门禁、嵌入禁用 ⌘R、Commit MotionPolicy、U7 辅助页不回归）
- 相关回归（HumanCentered* + Modal + Perf + Settings + L10n）与全量 `swift test`：`1138/1138` 通过
- 真实 `SvnCliBackendIntegrationTests`：`49/49` 保持
- `./scripts/build-macos-app.sh`、`./scripts/verify-macos-app.sh dist/SVNStudio.app`、`./scripts/smoke-test-macos-app.sh dist/SVNStudio.app`、`git diff --check` 通过

### 12.3 真实窗口与截图

三档逻辑尺寸 `980×640` / `1180×760` / `1440×900`（Retina 2× 像素分别为 1960×1384、2360×1520、2880×1800）；窗口 owner 为 `SVN Studio`；System Events 无辅助访问时使用 `CGWindowListCopyWindowInfo` + `screencapture -l`。截图均在 `artifacts/ui/`（Git 忽略，不入库）：

| 文件 | 场景 |
|------|------|
| `u8-changes-dark-980x640.png` | 变更 · 深色 · 980 |
| `u8-log-light-1180x760.png` | 历史 · 浅色 · 1180 |
| `u8-settings-light-reduce-motion-1440x900.png` | 设置 · 浅色 + Reduce Motion · 1440 |
| `u8-branches-dark-980x640.png` | 分支 · 深色 · 980 |
| `u8-properties-light-1180x760.png` | 属性 · 浅色 · 1180 |
| `u8-locks-light-reduce-motion-1440x900.png` | 锁 · 浅色 + Reduce Motion · 1440 |
| `u8-shelve-dark-980x640.png` | 搁置 · 深色 · 980 |
| `u8-workspace-light-1180x760.png` | 工作区壳 · 浅色 · 1180 |
| `u8-repo-dark-1440x900.png` | 仓库浏览 · 深色 · 1440 |

跨页任务 T1–T6：变更主路径、历史筛选/详情、冲突刷新、设置 dirty/保存、属性/锁/搁置键盘可达、sheet Esc/关闭/busy 禁止关闭均由自动化契约与上述窗口证据覆盖；抽检无重叠、关键动作可达。

### 12.4 现场偏差与 residual

- 宿主 `AXIsProcessTrusted=false`，System Events 辅助访问拒绝（-1728 / 按键 1002）；动态 VoiceOver 遍历与真实按键注入仍不可用，记为 residual，与 U6/U7 同口径；完成证据为可达关闭栏、label/identifier、Escape、busy/dirty 真值表与 ⌘F/⌘R 源码/策略测试，**不据此删减功能**。
- Diff / 独立 Commit / Blame / AI 辅助若仍使用 SplitView，属非嵌入工作区路径 residual；变更工作区嵌入路径继续禁止自由 SplitView，性能守卫不回退。
- 嵌入 Diff/Commit 不注册 ⌘R（`MacSvnCommandRShortcutModifier(enabled: !embedded)`），避免与 Changes 主刷新冲突；独立页启用 ⌘R。
- inventory / H-tortoise 无能力状态变化，未修改；Tortoise Perfect Loop 保持 GP.6 终止态，不创建 wake/heartbeat。

### 12.5 Human UI 长程目标完成声明

在 U5（变更工作区与全局关闭）、U6（核心模式）、U7（辅助工作流）、U8（全局体验）均满足各自完成定义与门禁证据后，**整个 Human UI 长程目标（U5–U8）标记完成**。后续若有体验迭代，按新规格/计划开波，不重启已终止的 Tortoise Perfect Loop。

### 12.6 完成定义核对

| §10 条件 | 状态 |
|----------|------|
| 1 全局键盘契约与高频页接线，U7 不回归 | 满足 |
| 2 a11y identifier 与 Modal 门禁 | 满足 |
| 3 MotionPolicy + Commit 覆盖 | 满足 |
| 4 性能守卫不回退 + residual 文档 | 满足 |
| 5 三档 + 跨页任务截图记录 | 满足 |
| 6 全量测试 / SVN / build / verify / smoke / diff --check | 满足 |
| 7 CHANGELOG / 规格 / 计划回填 + Human UI 完成声明 | 满足 |
