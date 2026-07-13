# Codex 长程 Loop 交接：SVN Studio × Tortoise 全量对标

> **给 Codex / 长程代理：** 本文是从 Cursor 会话切出后的**唯一启动说明书**。  
> 执行队列仍以 [`2026-07-10-tortoise-parity-perfect-loop.md`](./2026-07-10-tortoise-parity-perfect-loop.md) 为准；inventory 以 [`../specs/2026-07-10-tortoisesvn-feature-inventory.md`](../specs/2026-07-10-tortoisesvn-feature-inventory.md) 为验收真相。  
> **交接时刻：** 2026-07-11（UTC+8）；Codex 已完成 T2.8–T2.15/G2 与 T3.1–T3.11，当前继续 T3.12/G3。

---

## 0. 30 秒启动（复制即用）

```text
你在仓库 /Users/yangchao/Desktop/hlkj/newworkspace/aicoding/mac-svn-desktop
分支 feat/tortoise-parity-perfect-loop（干净 tip）。

执行 Tortoise 完美对标长程 Loop：
1. 读 docs/superpowers/plans/2026-07-11-codex-tortoise-parity-long-loop.md（本文）
2. 读 docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md → 取第一个 [ ]
3. 对照 docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md 对应行
4. TDD 实现 → swift test → 更新 inventory / H-tortoise / CHANGELOG / 进度日志 → 中文 commit
5. 未达 PERFECT 则继续下一条；禁止 while-true 心跳；Codex 用会话续跑或 one-shot sleep 120 + AGENT_LOOP_WAKE_svnstudio_tortoise_parity
6. 禁止降级砍功能；阻塞则写进度日志并暂停问用户

当前第一个未完成项：T3.12 闸门 G3（inventory T3、H-tortoise T3、全量测试）
北极星：小乌龟有的必须都有（platform-equivalent 可，砍能力不可）
```

---

## 1. 当前进度快照（交接基线）

| 项 | 值 |
|----|-----|
| 仓库路径 | `/Users/yangchao/Desktop/hlkj/newworkspace/aicoding/mac-svn-desktop` |
| 分支 | `feat/tortoise-parity-perfect-loop` |
| 工作区 | T3.11 实现与验收文档已更新，提交后应干净 |
| 最近功能 tip | `73cf430`（T3.11 日志统计 / 离线缓存）；前一功能 tip 为 `c9c41ef` |
| 覆盖率 | **91/114 = 79.82%**（`python3 scripts/parity-coverage.py`） |
| 测试 | 全量 **798** 绿（2026-07-13；含日志统计、缓存降容/保留期、强制离线与原有真实 SVN 集成测） |
| Wave | **G0 ✅ · G1 ✅ · G2 ✅**；T3.1–T3.11 ✅；下一 **T3.12/G3** |
| 停止条件 | inventory 必须行 100% ✅ + PERFECT 清单（见 perfect-loop §2） |

### 1.1 已完成（本 Loop）

- **T0 全套 + G0**
- **T1 全套 + G1**（日常 CFM/Commit/Update/Diff/Add/Delete/Revert/Cleanup/Rename/Ignore/Copy-Move/右键+⌘K）
- **T2.1–T2.7**
  - T2.1 Checkout / Update to revision（#1,#3）
  - T2.2–T2.5 Show Log 过滤/Actions/右键 L01–L12+L14+L17（L03/L13/L15–L16 → T3）
  - T2.6 Edit Conflicts + Resolved（#11,#12）、D08
  - T2.7 Get/Release/Break Lock（#19–#21）、D21（needs-lock 提升仍属 T4）
  - T3.11 日志统计 / 离线缓存（L18、S13）

### 1.2 未完成（按队列顺序）

| 条目 | 内容 | 备注 |
|------|------|------|
| **T2.8** | Branch-Tag / Switch / Merge+dry-run（#22–24） | ✅ |
| **T2.9** | Export / Import / Import in Place / Relocate / Remove from VC | ✅ |
| **T2.10** | Create / Apply Patch | ✅ |
| **T2.11** | Properties 模板；Blame 悬停 | ✅ |
| **T2.12** | Repo Browser 远端写 + 高危确认 + 锁列 | ✅ |
| **T2.13** | Filename case conflict repair | ✅ |
| **T2.14** | Progress Auto-close 基础 | ✅ |
| **T2.15 / G2** | T2 出门闸门 | ✅ |
| **T3.1** | Diff with URL（#6） | ✅ |
| **T3.2** | Revision Graph 核心 + 设置 pattern（#9、D25、S07、§4.6） | ✅ |
| **T3.3** | Change Lists（#38、D11） | ✅ |
| **T3.4** | Externals 编辑与更新行为（#39、D18） | ✅ |
| **T3.5** | 官方 `svn shelve` 对齐 + 本地搁置迁移（#37、D12、S05） | ✅ |
| **T3.6** | Merge reintegrate + 日志 Merge revision to…（#25、#42、L13） | ✅ |
| **T3.7** | Create Repository Here（#28） | ✅ |
| **T3.8** | Delete keep local / Delete unversioned（#15、#16） | ✅ |
| **T3.9** | Compare revisions / Blame differences（#40、L03、D23） | ✅ |
| **T3.10** | Edit author/message + revision properties（L15、L16） | ✅ |
| **T3.11** | 日志统计 / 离线缓存（L18、S13） | ✅ |
| T3.* | 专业能力（含 L03/L13/L15–L16、reintegrate、Revision Graph…） | |
| T4.* | Overlay / Finder / Status Cache | |
| T5.* | 设置 / 钩子 / 品牌 / 分发 | |
| **GP.*** | 100% 覆盖率收口后停 loop | |

### 1.3 T2.8 已有代码（勿从零重写）

| 能力 | 现状 | 缺口（要对齐小乌龟才可 ✅） |
|------|------|------------------------------|
| Branch/Tag `#22` | `BranchCopyViewModel` + `MacSvnBranchesView` 创建表单 | **三种 copy 源**：HEAD / 特定修订 / WC；现多用 `record.repoURL` |
| Switch `#23` | `BranchSwitchViewModel` 未提交变更确认已有 | CFM/⌘K Catalog 入口；确认 UX 与 inventory 对齐 |
| Merge `#24` | `MergeWizardViewModel` dry-run + `MacSvnMergeWizardView` | **两树合并**；**Unified Diff 预览**；冲突后进冲突工作区；Catalog 入口 |
| Domain | D19/D20 ✅ | 现代 complete merge 作为 reintegrate 的平台等价实现已在 T3.6 验证 |

相关文件（优先改这些）：

- `Sources/MacSvnCore/ViewModels/BranchCopyViewModel.swift`
- `Sources/MacSvnCore/ViewModels/BranchSwitchViewModel.swift`
- `Sources/MacSvnCore/ViewModels/MergeWizardViewModel.swift`
- `Sources/MacSvnApp/Features/MacSvnBranchesView.swift`
- `Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift`
- `Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`（`copy` / `merge` / `switchTo`）
- `Sources/MacSvnApp/App/MacSvnAppNavigator.swift` + `SvnCommandCatalog.dailyCFMCommandIDs`

---

## 2. 真相源与工具

| 角色 | 路径 |
|------|------|
| 执行队列 | `docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md` |
| 能力矩阵 | `docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md` |
| 手工清单 | `docs/acceptance/H-tortoise-parity.md` |
| 覆盖率 | `python3 scripts/parity-coverage.py` → `docs/acceptance/parity-coverage.json` |
| 变更记录 | `CHANGELOG.md`（每次必写） |
| 战略路线 | `docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md` |

---

## 3. Codex 长程 Loop 协议（强制）

### 3.1 每轮唯一目标

1. 打开 perfect-loop → **第一个** `[ ]`（当前应为 **T3.12/G3**）。
2. 同 Wave 内仅当极小相关才可合并；进度日志写清合并理由。
3. **禁止**跳过 T2 去做 T3/T4/T5；**禁止**把 stub 勾成 ✅。

### 3.2 实现标准（完美方案，禁止降级）

- 正确性 > 性能稳定 > 可维护 > 速度。
- 对话框级选项对齐 DUG/CLI；入口：主窗口 + CFM 右键/⌘K（Catalog）尽量齐。
- 空值防护、中文注释（解释为什么）、事务边界（先业务成功再记账/改状态）。
- 性能：禁止嵌套 Split + 逐行 Diff；大文件走 `DiffPerformanceLimits`。
- 遇能力上限 / 需求不清：**停下来问用户**，写进度日志；禁止擅自砍功能。

### 3.3 每轮交付清单

```text
[ ] 代码 + 单测（TDD）
[ ] swift test（相关 filter；Wave 出门 / 收口前全量）
[ ] inventory 对应行 ❌/🟡 → ✅（或诚实保留 🟡 并说明剩余）
[ ] H-tortoise 对应勾选
[ ] perfect-loop 勾 [x] + 进度日志行（commit 先写「（提交后回填）」再 docs 回填哈希）
[ ] CHANGELOG.md 条目（日期 / Summary / Affected / Impact）
[ ] 中文 Conventional 风格 commit（feat/fix/docs）
[ ] 可选：git push（用户未要求则可不 push）
[ ] 未达 PERFECT → 续跑下一 [ ] 或挂 one-shot 唤醒
```

### 3.4 唤醒（Cursor / Codex 通用）

**禁止** `while true; do sleep; echo WAKE; done`。

每轮结束可挂一次性：

```bash
sleep 120; echo AGENT_LOOP_WAKE_svnstudio_tortoise_parity
```

Codex 若支持会话续跑：完成一条后**直接**读队列下一条，不必等唤醒；唤醒仅作断线保险。

Wake token：`AGENT_LOOP_WAKE_svnstudio_tortoise_parity`

### 3.5 提交约定

- 仅提交本任务文件；中文说明。
- 进度日志哈希回填单独 `docs:` commit（与既有风格一致）。
- 不改 git config；不 force push main；用户未要求不 push。

### 3.6 审计

代码改动后：对照需求做空值/确认门控/路径消费竞态检查；关键路径跑 `swift test`；有 Bugbot/等价审查则用。回复中简列审计结论。

---

## 4. T2.8 建议实现要点（下一刀）

### 4.1 Branch/Tag（#22）

- 增加 copy 源枚举：`head` / `revision` / `workingCopy`。
- HEAD：仓库 URL；修订：`url@rev`（peg 剥离复用 `LogContextActionPolicy.stripPegRevision` 规则，勿误伤 `user@host`）；WC：本地路径作 `svn copy` 源。
- UI：`MacSvnBranchesView` 创建区增加源类型 + 修订号字段。
- 测：`BranchCopyViewModel` / 新 Policy 单测。

### 4.2 Switch（#23）

- 已有 local-changes 确认；补 Catalog（`switchBranch`）→ Navigator → 分支页。
- 未提交警告文案对齐小乌龟语义。

### 4.3 Merge + dry-run（#24）

- 保留现有 range merge + `--dry-run`。
- 补两树：`svn merge FromURL ToURL [WC]`（CommandBuilder + Service + Wizard UI）。
- Unified Diff 预览：对范围用 `svn diff -r X:Y URL`（或等价）展示文本；执行合并后冲突引导到冲突 Mode。
- Catalog：`merge` / `branchTag` 进日常可达入口（CFM 或 ⌘K）。

### 4.4 出门勾选

- inventory `#22 #23 #24`、D19/D20 → ✅（注明 reintegrate/L13 仍 T3）。
- H-tortoise T2 对应项；perfect-loop T2.8 `[x]`；覆盖率应升到约 **48+/114**（以脚本为准）。

---

## 5. 已知坑（本会话踩过）

1. **peg URL**：只剥末尾 `@数字`，不要剥 `svn+ssh://user@host`。
2. **pending 深链**：先确保目标 VM 就绪再 `consume`；否则路径被吞。
3. **锁定**：有锁列表时释放锁只允许本 WC 持有；勿 fallback 误 unlock 他人锁。
4. **锁定命令**：相对路径不要写入 `pendingOpenPath`（会误触发打开 WC）。
5. **批量 resolve**：允许部分成功并回报，勿一失败假装全失败。
6. **Log 大 View**：避免单文件过大导致 type-check 超时，拆子 ViewBuilder。
7. **唤醒**：只用 one-shot `sleep N; echo TOKEN`，旧 wake 重复通知可忽略，以队列第一个 `[ ]` 为准。

---

## 6. 闸门与 PERFECT

- **G2**（T2.15）：T2 范围内 inventory ✅ + H-tortoise T2 勾满 + 全量 `swift test`。
- **PERFECT**（GP.*）：覆盖率 100%、无用户可见 unimplemented、H 全文勾、README 对齐后**停止挂唤醒**。
- **T6 AI/Git** 不计入本 Loop 停止条件。

---

## 7. 交接检查表（给人）

- [x] Cursor 侧停止新功能（T2.8 未半成品提交）
- [x] tip 在 T2.7（`a877356` / docs `23299fc`）
- [x] 工作区干净、分支正确
- [x] 本文已写入仓库
- [x] 在 Codex 粘贴 §0 启动指令并开始 T2.8
- [ ] （可选）`git push -u origin feat/tortoise-parity-perfect-loop` 便于多机续跑

---

## 8. 进度日志（交接行）

| 时间 | 条目 | commit | 备注 |
|------|------|--------|------|
| 2026-07-11 | 交接 | 425cba7 | Cursor→Codex；下一刀 T2.8；覆盖率 45/114 |
| 2026-07-13 | T2.9 | aad330a | Export/Import/Import in Place/Relocate/Remove VC；覆盖率 57/114；下一刀 T2.10 |
| 2026-07-13 | T2.10 | ab0d64a | Create/Apply Patch；真实 SVN 往返和 `.rej` 冲突报告；覆盖率 60/114；下一刀 T2.11 |
| 2026-07-13 | T2.11 | c4a6682 | Properties 模板/多行编辑；Blame 修订范围/悬停日志；覆盖率 63/114；下一刀 T2.12 |
| 2026-07-13 | T2.12 | 4acd365 + 1f444a5 | Repo Browser 远端写与高危确认；pending 确认快照；`svn info --xml --depth immediates` 锁列；路径 URL 编码；全量 673 绿；下一刀 T2.13 |
| 2026-07-13 | T2.13 | e646b1d | 大小写冲突修复策略、两步临时 SVN 改名、失败回滚、CFM/⌘K 向导；真实 SVN 提交验证；全量 683 绿；下一刀 T2.14 |
| 2026-07-13 | T2.14 | 5a418c9 | Progress Auto-close 四档策略、设置持久化、更新/本地成功操作完成提示接线；全量 688 绿；下一刀 T2.15/G2 |
| 2026-07-13 | T2.15/G2 | 4d5fff6 | #41 Save/Open 实现核验；#15/#16 对齐 T3.8；T2 inventory/H 闸门审计；全量 688 绿；下一刀 T3.1 |
| 2026-07-13 | T3.1 | 7e5b1e0 | Diff with URL：URL+revision/peg 校验、认证 stdin/重试、原子导航 intent、真实 SVN 跨 URL 集成测；覆盖率 68/114；全量 710 绿；下一刀 T3.2 |
| 2026-07-13 | T3.2 | 681268b | Revision Graph：repo-root verbose log 构图、copy/history 边、glob 分类/颜色混色、剪枝、拓扑/时间线、分页/All、Log/Checkout/Blame/Diff；真实 SVN copy-edge/Diff；覆盖率 71/114；全量 724 绿；下一刀 T3.3 |
| 2026-07-13 | T3.3 | eb73ea1 | Change Lists：status XML 归属、CFM 列/分组、移入/移出与深度、Commit 按列表选择、`ignore-on-commit` 默认排除、cmd.38 原子路径意图；真实 SVN 往返；覆盖率 73/114；全量 730 绿；下一刀 T3.4 |
| 2026-07-13 | T3.4 | 4658126 | Externals：现代/旧式定义解析、目录/文件 external 结构化编辑、operative/peg revision、注释保留、安全本地路径校验、仓库 URL 拖拽预填、保存后非忽略 externals 更新；覆盖率 75/114；全量 738 绿；下一刀 T3.5 |
| 2026-07-13 | T3.5 | c4bf526 | 官方 `svn shelve` V2/V3、能力探测、双轨搁置 UI 与本地手工快照迁移；真实 SVN 往返；覆盖率 78/114；全量 749 绿；下一刀 T3.6 |
| 2026-07-13 | T3.6 | 240f71c | 现代 complete merge reintegrate、日志 L13 `svn merge -c REV`、确认门控与冲突回跳；真实 SVN 往返；覆盖率 81/114；全量 755 绿；下一刀 T3.7 |
| 2026-07-13 | T3.7 | ab5f77a | `svnadmin create --fs-type fsfs`、仓库浏览器/⌘K 入口、用户工具链路径与结构化错误码；真实仓库验证；覆盖率 82/114；全量 761 绿；下一刀 T3.8 |
| 2026-07-13 | T3.8 | 86d65da | `svn delete --keep-local`；未版本预览勾选、二次 status/WC 边界复核、父子路径合并；CFM/⌘K 原子意图；真实 SVN 文件/目录往返；覆盖率 84/114；全量 771 绿；下一刀 T3.9 |
| 2026-07-13 | T3.9 | 5f519b9 | 双修订 blame+diff 行对齐；左右作者/日期/内容、变化汇总/筛选、BASE；L03 PREV:REV、仓库 URL@peg、CFM/⌘K；真实 SVN 双提交往返；覆盖率 87/114；全量 778 绿；下一刀 T3.10 |
| 2026-07-13 | T3.10 | c9c41ef | 全量 revprops 展示；作者/日志说明仅变化写入；认证重试/写锁；UTF-8 `0600` 临时值文件；hook 拒绝提示；日志右键/详情/⌘K；真实 SVN 无 hook 拒绝与中文/自定义属性往返；覆盖率 89/114；全量 787 绿；下一刀 T3.11 |
| 2026-07-13 | T3.11 | 73cf430 | 日志统计作用于当前过滤结果；作者/日期/动作统计；缓存按仓库目标/stop-on-copy 隔离，支持容量/保留期、清理、网络/认证/环境失败回退与强制离线；设置持久化；覆盖率 91/114；全量 798 绿；下一刀 T3.12/G3 |

---

**维护：** 每完成一条 Wave 项，无需改本文结构；以 perfect-loop 进度日志为准。若分支/路径变更，只更新 §0 与 §1 表头。
