# SVN Studio UI/UX IA 重构实现计划

> **面向 AI 代理的工作者：** 按 Wave U1→U4 顺序实现；步骤用复选框跟踪。

**目标：** Working-Copy Centric 壳层 + 统一变更工作区 + ⌘K 全覆盖 + 文档收口。

**架构：** 保留 `MacSvnAppRoute`；新增 `MacSvnWorkspaceMode`；`MacSvnRootView` 侧栏改为 WC 列表；详情为 `MacSvnWorkingCopyShellView`；变更 Mode 使用 `MacSvnWorkingCopyWorkspaceView` 组合 Changes/Diff/Commit。

**技术栈：** SwiftUI / macOS 14+ / 现有 MacSvnApp ViewModels

---

## 状态：已完成（2026-07-10）

### 任务 1：规格与 Mode 模型

- [x] 编写 `docs/superpowers/specs/2026-07-10-ui-ux-ia-design.md`
- [x] 实现 `MacSvnWorkspaceMode` + 单测
- [x] 更新导航相关单测

### 任务 2：Wave U1 壳层

- [x] RootView WC 侧栏 + 空态
- [x] WorkingCopyShellView
- [x] Navigator open 默认进入 changes

### 任务 3：Wave U2 统一工作区

- [x] WorkingCopyWorkspaceView
- [x] Changes/Commit/Diff 嵌入参数与中文主操作

### 任务 4：Wave U3 ⌘K 与工具收纳

- [x] 扩展 ActionID 与 CommandPalette
- [x] Shell 更多/工具菜单

### 任务 5：Wave U4 打磨与文档

- [x] 冲突「返回变更」
- [x] 日志 Diff 回到变更工作区
- [x] HLD/H1/README/CHANGELOG/文档索引
