# MacSVN 长程 Loop Backlog

| 项 | 内容 |
|----|------|
| 创建日期 | 2026-07-10 |
| 基线分支 | `main` @ `a31deed` |
| 工作分支 | `feat/long-loop-full-delivery` |
| 目标 | 规划功能全部可交付：核心已齐 → 补齐 SwiftUI 接线、系统扩展、端到端验收 |
| 停止条件 | 本文件全部条目为 `[x]`，且 `swift test` 全绿，CHANGELOG 记录完成 |

## Loop 规则（每轮必须遵守）

1. 读取本文件，取**第一个未完成**条目（`[ ]`）作为本轮唯一目标。
2. 在 `feat/long-loop-full-delivery` 上工作；若当前不在该分支则切过去。
3. TDD：先写/补测试 → 实现 → `swift test`（至少相关 target，收尾前全量）。
4. 小步提交：一个 backlog 条目至少 1 个 commit；中文 commit message。
5. 完成后把该条目改为 `[x]`，在「进度日志」追加一行（时间、commit、验证结果）。
6. 更新根目录 `CHANGELOG.md`（按日合并条目即可）。
7. `git push -u origin HEAD`（若远程已存在则 push）。
8. **禁止停在半成品**：本轮做不完也要留下可编译状态 + 进度日志说明阻塞点，然后进入下一轮。
9. 若条目依赖缺失：先补最小依赖，再继续；不要跳过 P1 日常流去先做 P6。
10. 全部 `[x]` 后：跑全量测试、合并说明写入 CHANGELOG、停止 loop。

## 现状判断（2026-07-10）

- ✅ `MacSvnCore`：P1–P6 服务/ViewModel/解析器/测试大体完成（464 tests 绿）。
- ❌ `MacSvnApp`：仅路由壳 + Placeholder，**未接真实 ViewModel**。
- ❌ 系统扩展：Finder Sync / Quick Look / 菜单栏 App 未落地为可安装 target。
- ❌ 端到端：真实 WC 手工验收清单未闭环。

## Backlog（严格按序）

### Wave A — 应用骨架与依赖注入

- [x] **A1** AppSession / DI：集中创建 `ProcessRunner`、`SvnCliBackend`、`SvnService`、`WorkspaceStore`、`SettingsStore`，注入 `MacSvnRootView`
- [x] **A2** 环境门禁页：`SvnEnvironmentChecker` 失败时展示引导（brew 安装 / 指定路径），通过后进入主界面
- [x] **A3** 根视图接线：侧边栏选中路由 → 真实 Feature View（去掉纯占位，可保留空态）

### Wave B — P1 日常工作流 UI

- [x] **B1** 工作副本页：列表 / 添加（文件夹选择）/ 移除确认 / 无效 WC 灰显
- [x] **B2** 变更页：接 `ChangesViewModel`（刷新、筛选、搜索、树/平铺）
- [x] **B3** 工作副本动作：Update / Cleanup / Add / Delete / Revert（确认）接 `WorkingCopyActionsViewModel`
- [x] **B4** 提交页：接 `CommitViewModel` + 提交说明历史 + Commit Guard 警告展示
- [x] **B5** Diff 页：接 `DiffViewModel`（unified；二进制提示）
- [x] **B6** 日志页：接 `LogViewModel`（分页加载更多）
- [x] **B7** 设置页：svn 路径、超时、日志批量、分支布局；保存后生效

### Wave C — P2 仓库 / 分支 UI

- [x] **C1** 仓库浏览器：接 `RepoBrowserViewModel`（懒加载树、预览、收藏）
- [x] **C2** Checkout 向导：深度选项 + 进度
- [x] **C3** 分支与标签：列表 / 创建 / 切换（未提交变更警告）
- [x] **C4** Merge 向导：dry-run 预览 + 执行

### Wave D — P3 冲突 UI

- [x] **D1** 冲突列表：接 `ConflictListViewModel`，有冲突时侧边栏角标
- [x] **D2** 三路合并编辑器窗口：接 `MergeEditorViewModel`（逐块操作、保存 resolve）
- [x] **D3** 树冲突解决：接 `TreeConflictViewModel`

### Wave E — P4 高级 SVN + 效率 UI

- [ ] **E1** Blame 页
- [ ] **E2** 属性页
- [ ] **E3** 锁定页
- [ ] **E4** 搁置页（Shelve）
- [ ] **E5** 提交守护结果在 Commit 页硬/软阻断可配置

### Wave F — P5 Git 迁移 + 菜单栏 + 深链

- [ ] **F1** Git 迁移向导 UI（源分析→authors→清理→执行→推送/同步）
- [ ] **F2** 菜单栏常驻：状态角标 + 远端提交通知（`MenuBarStatusSnapshotter`）
- [ ] **F3** `macsvn://` 深链与 CLI 伴生入口接到 App

### Wave G — P6 AI + 生态

- [ ] **G1** AI Provider 设置页（Keychain、连通性测试、脱敏开关）
- [ ] **G2** AI 助手 Chat 面板（tool 确认门 + 审计展示）
- [ ] **G3** 提交页接入 AI 生成说明 / AI 预检
- [ ] **G4** 合并编辑器接入 AI 冲突建议
- [ ] **G5** 命令面板 ⌘K
- [ ] **G6** 团队活动页
- [ ] **G7** Finder Sync 扩展 target（角标 + 右键菜单）
- [ ] **G8** Quick Look 预览扩展 target

### Wave H — 验收与收口

- [ ] **H1** 手工验收脚本/清单：真实 WC 走通 P1 日常流（中文 commit）
- [ ] **H2** README 更新：如何运行 `swift run MacSvnDesktopApp`、功能矩阵勾选
- [ ] **H3** 全量 `swift test` + 推送 + 准备合并 `main` 的说明

## 进度日志

| 时间 | 条目 | Commit | 验证 |
|------|------|--------|------|
| 2026-07-10 12:17 | A1/A2/A3/B1/B2/B7 | bf0cbe9 | `swift test --filter MacSvnApp` 6 passed |
| 2026-07-10 12:19 | B3/B4/B5/B6 | 9488ab8 | `swift test --filter MacSvnApp` 6 passed |
| 2026-07-10 12:23 | C1/C2/C3/C4 | （本轮提交） | `swift test --filter MacSvnApp` 6 passed |
