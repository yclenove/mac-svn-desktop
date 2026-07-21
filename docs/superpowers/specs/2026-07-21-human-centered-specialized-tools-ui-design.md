# SVN Studio 人本专业工具面 UI/UX 设计

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-21 |
| 产品 | SVN Studio |
| 状态 | 已批准（用户要求「新开规划 继续迭代」；沿用 Human UI 后续设计自主授权） |
| 对应迭代 | Human Specialized Tools Wave **ST**（U5–U8 之后新开波次） |
| 前序 | U5 变更工作区、U6 核心模式、U7 辅助工作流、U8 全局体验均已完成 |
| 非目标 | 不重启 Tortoise Perfect Loop；不修改 inventory/H-tortoise 除非能力真变；不解决 Developer ID 凭据阻塞 |

## 1. 背景

U5–U8 已把高频变更工作区、核心模式、辅助页与全局键盘/a11y/动效收口。仍有一批**差异化 / 专业工具面**未纳入该长程：

| 面 | 现状问题 |
|----|----------|
| **Blame** | 独立 `HSplitView`；状态/错误/空态样式与 Core/Auxiliary 不一致；缺少 ⌘R 与稳定 a11y id |
| **AI Assistant** | 独立 `HSplitView`；会话列表/详情层级偏工程化；busy 与发送门禁不统一；缺全局契约接线 |
| **Git 迁移** | 多步骤向导信息密度高；分析/推断/对账错误散落；缺统一反馈条与关闭/busy 策略抽检 |
| **Release Notes** | 功能可用但反馈与空态弱于 U7 辅助页语言 |
| **AI Provider 设置** | 挂在设置体系内，部分标识符/忙态可与 ST 契约对齐（不重做设置 IA） |

U8 residual 已明确：Diff/Blame/AI 独立页 SplitView 属非嵌入工作区路径；本波次**允许**独立专业页继续使用单层 `HSplitView`，但必须：

1. 禁止嵌套 SplitView；
2. 嵌入任何工作区路径时不得引入 SplitView；
3. 用源码门禁锁住边界；
4. 补齐与 U5–U8 一致的工具栏、反馈、键盘、关闭与 Reduce Motion 契约。

业务能力（AI tool 确认门、Git 迁移写路径、Blame 范围/外置/演化解释）**禁止删减**。

## 2. 方案选择

### 方案 A：仅文档 residual，不改 UI

零风险，但专业工具面继续像「另一款 App」，与 U5–U8 体验割裂。

### 方案 B：共享 ST 契约 + 四页接线 + 门禁（采用）

1. 新增纯策略/轻量呈现模块 `MacSvnSpecializedToolsPresentation`；
2. 对齐工具栏高度、反馈条、busy/error/empty 语义与 a11y 前缀 `macSvn.st.<page>.*`；
3. Blame / AI / Git Migration / Release Notes 逐页接线；
4. 扩展 U8 键盘/Motion 源码门禁到 ST 页；
5. 三档窗口真实截图收口。

### 方案 C：重写四页为全新布局

体验上限更高，但回归面过大，易误伤 AI 确认门与迁移写路径，超出一波可控范围。

## 3. 信息架构与页面清单

| 页面 | 入口 | ST 目标 |
|------|------|---------|
| Blame | 历史/变更/⌘K | 上下文栏 + 刷新 + 主列表/详情稳定；hover 日志/演化解释不挡关闭 |
| AI Assistant | 工具/⌘K | 会话列表 + 消息区 + 输入栏固定层级；发送 busy 防重入 |
| Git Migration | 工具 | 步骤条/分区清晰；分析·authors·对账反馈统一；危险写确认保留 |
| Release Notes | 日志/工具 | 生成 busy、错误可读、结果区可复制；空态可操作 |
| AI Provider（轻量） | 设置 | 仅补 identifier / busy 禁用；不重排设置 IA |

## 4. 共享契约

### 4.1 度量（与 Core/Auxiliary 对齐）

| 项 | 值 |
|----|-----|
| 工具栏高度 | 48 |
| 反馈条高度 | 30 |
| 图标按钮命中 | ≥ 28×28 |
| 窗口档位 | 980×640 / 1180×760 / 1440×900 |

### 4.2 键盘与 a11y

| 场景 | 契约 |
|------|------|
| 可刷新 | ⌘R + `macSvn.st.<page>.refresh`；busy 时禁用 |
| 可搜索（若有过滤） | ⌘F + `macSvn.st.<page>.search` |
| 关闭 sheet | 共享 `macSvnDismissibleSheet` / 关闭栏；dirty 确认；busy 禁止关闭 |
| 主操作 | Return 仅挂在明确主按钮；破坏性操作不得静默默认 |

页面 rawValue：`blame` / `aiAssistant` / `gitMigration` / `releaseNotes`。

### 4.3 反馈语义

复用或对齐 `MacSvnAuxiliaryWorkflowFeedback` / Core 错误呈现：

- loading / success / warning / failure；
- 可恢复失败提供刷新或重试；
- 认证/网络/超时走可读摘要 + 原始诊断可达。

### 4.4 动效

所有装饰性动画调用 `MacSvnMotionPolicy`；AI 流式输出允许无动画追加，禁止在 Reduce Motion 下做弹跳/闪烁装饰。

### 4.5 SplitView 边界

| 路径 | 规则 |
|------|------|
| 变更工作区嵌入 | **禁止** H/VSplitView（U5–U7 守卫保持） |
| 独立 Blame / AI / 独立 Commit / Diff | 允许**单层** HSplitView；禁止嵌套；记 residual |
| 门禁 | ST 测试断言：目标文件中 `HSplitView` 出现次数 ≤ 1（每结构体/主 body），且无 `VSplitView` |

## 5. 分页面要求

### 5.1 Blame

1. 顶栏：路径/修订范围上下文 + 刷新（⌘R）+ 外置 Blame 入口保持；
2. 主区：行 blame 列表 + 悬停/选中 revision 详情；比较模式结果区不与主列表语义混淆；
3. 空态：未选路径 / 无 blame 行 / 比较无差异 三分；
4. 错误：加载失败可重试；hover 日志失败不污染主列表；
5. AI 演化解释：sheet 或固定侧栏，关闭可达，生成 busy 防重入。

### 5.2 AI Assistant

1. 左：会话/上下文列表；右：消息流 + 底部输入；
2. 发送/执行工具：busy 禁用重复发送；写工具仍走确认门 + 审计（能力不降级）；
3. 错误与限流：反馈条 + 原始信息可达；
4. ⌘R：刷新当前会话上下文或工具状态（与现有刷新语义对齐，不新造危险动作）。

### 5.3 Git Migration

1. 分区：源仓 → authors → 目标 → 分析/执行 → 对账；
2. 每步 busy 时禁止重复提交与关闭进行中的事务 sheet；
3. AI authors 待复核标记保持醒目；
4. 对账失败阻断同步路径保持。

### 5.4 Release Notes

1. 入口上下文（修订范围/条目数）可见；
2. 生成中 Progress + 禁用重复生成；
3. 成功结果可选择/复制；失败可重试。

## 6. 测试策略

| 类型 | 覆盖 |
|------|------|
| 纯策略 | ST 页面枚举、是否需要 ⌘F/⌘R、a11y id 前缀 |
| 源码门禁 | 四页含 refresh id / keyboardShortcut；SplitView 边界；MotionPolicy 引用 |
| 回归 | HumanCentered*、ModalDismissal、GlobalExperience、PerformanceGuard |
| 真实窗口 | 三档 + 浅色/深色/Reduce Motion；截图 `artifacts/ui/st-*.png` |
| 全量 | `swift test`、真实 SVN 49/49、build/verify/smoke、`git diff --check` |

## 7. 非目标

- 不重启 Tortoise Perfect Loop / wake / heartbeat；
- 不把 ST 完成误报为「重新打开 U 系列」或改写 inventory 覆盖率；
- 不实现 Developer ID 公证（凭据阻塞保持 residual）；
- 不重做设置信息架构全文；
- 不删除 AI 确认门、迁移对账失败阻断、Blame 外置工具。

## 8. 完成定义

1. ST 契约模块落地，四页按表接线；
2. Modal / 键盘 / Motion / 性能边界门禁绿；
3. 业务能力无回归；
4. 三档真实窗口有截图记录；
5. 全量测试与 App 门禁通过；
6. CHANGELOG、本规格、计划回填；docs 索引登记 ST；
7. inventory / H-tortoise 仅能力真变时改。

## 9. 风险与 residual

| 风险 | 处理 |
|------|------|
| TCC 无障碍 residual | 与 U8 同：自动化契约，不砍功能 |
| 独立页 HSplitView | 单层允许 + 门禁；文档 residual |
| AI/迁移写路径误伤 | 禁止改确认门语义；定向 + 全量测试 |
| 向导页信息过密 | 反馈上提、分区，不删字段 |

## 10. 验收记录

（实现收口时回填：日期、测试数量、截图路径、现场偏差。）
