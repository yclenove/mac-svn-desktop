# SVN Studio × TortoiseSVN 全量对标 — 完美 Loop 规划

> **面向 AI 代理的工作者：** 每轮只取本文件**第一个未完成** `[ ]`；用 TDD 实现 → 测 → 更新 inventory 状态 → 勾本文件 → CHANGELOG →（可选）push → **再挂 one-shot 唤醒**。  
> 必需参考：[`2026-07-10-tortoisesvn-feature-inventory.md`](../specs/2026-07-10-tortoisesvn-feature-inventory.md)（验收唯一真相）、[`2026-07-10-long-term-iteration-roadmap.md`](2026-07-10-long-term-iteration-roadmap.md)、[`2026-07-10-long-term-product-design.md`](../specs/2026-07-10-long-term-product-design.md)。  
> **Codex 长程续跑：** 见 [`2026-07-11-codex-tortoise-parity-long-loop.md`](2026-07-11-codex-tortoise-parity-long-loop.md)（交接快照 + 启动指令；当前队列以本文件首个未完成 Wave 项 **T5.6** 为准）。

| 项 | 内容 |
|----|------|
| 创建日期 | 2026-07-10 |
| 产品 | SVN Studio |
| Loop 代号 | `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` |
| 建议工作分支 | `feat/tortoise-parity-perfect-loop`（从当前交付 tip / `feat/ui-ux-ia-refactor` 切出） |
| 能力基线 | inventory **v2**（命令 #、日志 L#、设置 S#、Overlay、DUG 域） |
| 北极星 | **小乌龟有的，Studio 必须有**（平台换壳，不砍能力） |
| 停止条件 | 见 §2「完美定义」——**全部满足才停**；未满足则继续 loop |
| 当前状态（2026-07-14） | T0–T4 + G0/G1/G2/G3/G4、T5.1–T5.5 ✅；**下一 T5.6**；覆盖率 **108/114（94.74%）**；全量 **937** 绿 |

---

## 1. 本 Loop 是什么 / 不是什么

| 是 | 不是 |
|----|------|
| 把 inventory 每一行做到 ✅ | 「主路径能提交」就收工 |
| 对话框级选项对齐 DUG/CLI | 只加菜单 stub 勾完成 |
| Finder + 主窗口 + ⌘K 入口齐全 | 用「macOS 做不到」砍功能 |
| 每波出门有覆盖率与 H1 证据 | 跳过 T0 性能门禁直接堆功能 |
| T0→T5 严格按序 | 先做 T6 AI/Git 差异化 |

**T6（AI/Git/团队）不计入本 Loop 停止条件**；T0–T5 完美后另开差异化 loop。

---

## 2. 完美定义（停止条件 — 缺一不可）

记为 **PERFECT**，全部 `[x]` 后才允许停止唤醒：

- [ ] **P-INV**：inventory v2 中所有必须行（命令 #1–46、L01–L20、S01–S13、Overlay 表、域 D01–D28）状态均为 ✅（允许「平台等价形态」注释，禁止 ❌/🟡）
- [ ] **P-STUB**：不存在对用户可见的「未实现」stub（T0 骨架阶段临时 stub 必须在对应 Wave 清零）
- [ ] **P-TEST**：全量 `swift test` 绿；关键路径有单测或等价契约测
- [ ] **P-H1**：`docs/acceptance/` 下 Tortoise 对标手工清单全部跑通（真实 WC）
- [ ] **P-COV**：覆盖率报表 `✅/必须行 = 100%`（由 T0 工具生成，CI 或脚本可复跑）
- [ ] **P-PERF**：空闲无 AttributeGraph 死循环；大 Diff 不卡死（对照详设性能规范）
- [ ] **P-DOC**：README 功能矩阵与 inventory 一致；本文件全部 Wave `[x]`；CHANGELOG 有收口条目
- [ ] **P-SHIP**（T5 末）：可安装 `SVNStudio.app` + Finder Sync 冒烟；公证可后置但须有明确阻塞记录（若暂无证书：记入风险但 **P-INV 仍须 100%**）

任一未满足 → **禁止**宣称完美；继续取第一个 `[ ]`。

### 覆盖率公式

```
coverage = count(✅) / count(必须验收行)
目标 = 1.0
```

每轮结束若改了能力，必须同步改 inventory 状态列。

---

## 3. Loop 规则（每轮强制）

1. **读本文件** → 取第一个未完成 `[ ]` 作为本轮唯一目标（同 Wave 内极小相关项可合并，进度日志写清）。
2. **对照 inventory**：实现前打开对应 #/L#/S#/Overlay 行；实现后更新状态 ❌→🟡→✅。
3. **分支**：在 `feat/tortoise-parity-perfect-loop` 上工作；不存在则从当前 tip 创建。
4. **TDD**：先测 → 实现 → `swift test`（相关 filter；Wave 出门与 PERFECT 前全量）。
5. **质量**：遵守事务边界、空值防护、中文注释、性能规范（禁止嵌套 Split+逐行 Diff）。
6. **提交**：中文 commit；勾本文件；更新 `CHANGELOG.md`；需要时 `git push`。
7. **禁止**：
   - 把 stub / 文档骨架勾成 ✅
   - 跳过更早 Wave 去做更晚 Wave
   - `while true; do sleep; echo WAKE; done` 无限心跳
   - 未达对话框级就勾命令 ✅
8. **阻塞**：能力上限 / 信息缺失 → 进度日志写清候选方案，**暂停与用户确认**；禁止擅自降级砍功能。
9. Wave 全部 `[x]` 后执行该 Wave 的 **出门闸门**；未过闸不得开下一 Wave。
10. 全部 Wave + PERFECT 满足后：**停止挂唤醒**，输出收口报告。

### 唤醒协议（强制）

**禁止**无限 `while true` 心跳（订阅会失效，代理不会被拉起）。

每轮结束后挂 **一次性** sleeper：

```bash
sleep 120
echo 'AGENT_LOOP_WAKE_svnstudio_tortoise_parity {"prompt":"Continue SVN Studio Tortoise-parity perfect loop on feat/tortoise-parity-perfect-loop: read docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md, implement FIRST unchecked [ ] with TDD, update inventory status, swift test, commit, CHANGELOG; then re-arm one-shot wake (sleep 120 + echo AGENT_LOOP_WAKE_svnstudio_tortoise_parity). Stop only when PERFECT criteria in §2 are all met. Do not use while-true loops."}'
```

- 唤醒后：读 prompt → 干活 → **再挂下一发** one-shot。  
- 用户说停止：杀 sleeper，不再挂。  
- 间隔：默认 120s；重轮次可 180–300s。

### 每轮最小产出模板（进度日志）

```text
| 时间 | 条目 | commit | 测试 | inventory 变更 | 备注 |
```

---

## 4. 闸门总览

| 闸门 | 何时 | 通过标准 |
|------|------|----------|
| G0 | T0 末 | 命令 ID 全齐可枚举；覆盖率脚本可跑；性能规范有测试或静态检查说明；空闲 CPU 正常 |
| G1 | T1 末 | inventory **#2,4,5,8,13–14,17–18,29,32,36,45**（不含 #3 Update to revision，属 T2）及 Commit/CFM 对话框 T1 必选项 → ✅ |
| G2 | T2 末 | 检出/日志 L 大部/锁/分支合并/导出导入补丁/Repo 写等对应行 → ✅ |
| G3 | T3 末 | 修订图/Changelist/Externals/官方 Shelve/扩展命令等 → ✅ |
| G4 | T4 末 | Overlay 全状态 + Cache 三模式 + Finder 菜单 → ✅ |
| G5 | T5 末 | 设置 S01–S13 + 钩子/Bugtraq + 品牌冒烟 → ✅ |
| GP | 收口 | §2 PERFECT 全勾 |

---

## 5. Backlog（严格按序 — 一直做到完美）

### Wave T0 — 门禁与骨架

- [x] **T0.1** 性能规范落地：变更工作区/Diff 回归测试或文档化断言（防 AttributeGraph 再发）；确认无嵌套 Split+逐行 Diff
- [x] **T0.2** 新增 `SvnCommandCatalog`：ID 对齐 inventory `#1–46` + `L01–L20` + 扩展菜单标记；可枚举、可查 displayName
- [x] **T0.3** `Navigator.perform(command:paths:options:)`（或等价）统一入口；未实现命令明确 `unimplemented`（仅 T0 允许）
- [x] **T0.4** 可取消 `svn` 任务模型（取消令牌 / Task 取消接到 ProcessRunner）
- [x] **T0.5** 覆盖率工具：解析 inventory 状态列或维护 `parity-coverage.json`，输出 `✅/总数`
- [x] **T0.6** 验收清单骨架：`docs/acceptance/H-tortoise-parity.md`（按 Wave 分节，先空勾）
- [x] **T0.7** **闸门 G0**：全量 `swift test`；覆盖率脚本跑通；进度日志写 G0 通过

### Wave T1 — 日常闭环（对话框级）

- [x] **T1.1** Check for Modifications：本地 status、列、刷新（#8 升 🟡→接近 ✅）
- [x] **T1.2** CFM：Check Repository (`status -u`)、颜色规则（#8）
- [x] **T1.3** CFM：Repair Move / Repair Copy（#45）
- [x] **T1.4** Commit 对话框级：勾选、未版本→add、Keep locks、说明历史、单项 Diff/Revert（#4 + §4.1）
- [x] **T1.5** Update：同仓多路径统一 revision（#2 + §4.3）
- [x] **T1.6** Diff：BASE、双文件、外置查看器入口（#5）
- [x] **T1.7** Add / Delete / Revert（勾选列表）/ Cleanup（#14,17,18,29）
- [x] **T1.8** Rename（#13）
- [x] **T1.9** Ignore 文件/通配（#32）
- [x] **T1.10** SVN Copy / Move 向导（#36）
- [x] **T1.11** 变更树右键 = Catalog 日常子集；⌘K 可搜到
- [x] **T1.12** **闸门 G1**：更新 inventory 对应行 → ✅；H-tortoise T1 节手工勾选；`swift test` 全绿

### Wave T2 — 进阶日常 + 仓库

- [x] **T2.1** Checkout + Update to revision（depth、ignore-externals）（#1,#3）
- [x] **T2.2** Show Log：过滤、stop-on-copy、Next/All、Actions 列（#7, L18–L20）
- [x] **T2.3** 日志右键：Compare WC/previous、unified diff、Save/Open、Blame、Browse（L01–L08）
- [x] **T2.4** 日志右键：Branch/Tag from rev、Update to rev、Revert to/from rev、Checkout/Export from log（L09–L12,L14）
- [x] **T2.5** 日志：Copy clipboard（L17）；Edit author/msg / rev props 可放 T3（L15–L16 若本轮做不完保持 `[ ]` 并移到 T3 显式条目——**本条先做 L17**）
- [x] **T2.6** Edit Conflicts + Resolved 打磨（#11,#12）；属性/树冲突入口
- [x] **T2.7** Lock / Unlock / Break lock（#19–21）
- [x] **T2.8** Branch-Tag / Switch / Merge+dry-run（#22–24）
- [x] **T2.9** Export / Import / Import in Place / Relocate / Remove from VC（#26,#27,#30,#43,#44）
- [x] **T2.10** Create Patch / Apply Patch（#33,#34）
- [x] **T2.11** Properties 模板与编辑（#35）；Blame 悬停日志（#31）
- [x] **T2.12** Repo Browser 远端写 + 高危确认 + 锁列（#10 + §4.5）
- [x] **T2.13** Filename case conflict repair（#46）
- [x] **T2.14** Progress Auto-close 策略（§4.7 基础）
- [x] **T2.15** **闸门 G2**：inventory T2 范围 → ✅；H-tortoise T2；全量测试

### Wave T3 — 专业能力

- [x] **T3.1** Diff with URL（#6）
- [x] **T3.2** Revision Graph 核心 + 设置 pattern（#9, S07, §4.6）
- [x] **T3.3** Change Lists（#38, D11）
- [x] **T3.4** Externals 编辑与更新行为（#39, D18）
- [x] **T3.5** 官方 `svn shelve` 对齐 + 本地搁置迁移方案落地（#37, S05 shelve 版本）
- [x] **T3.6** Merge reintegrate + 日志 Merge revision to…（#25,#42, L13）
- [x] **T3.7** Create Repository Here（#28）
- [x] **T3.8** Delete keep local / Delete unversioned（#15,#16）
- [x] **T3.9** Compare revisions / Blame differences（#40, L03）
- [x] **T3.10** 日志 Edit author/message + revision properties（L15,L16）
- [x] **T3.11** 日志统计 / 离线缓存（L18、S13）
- [x] **T3.12** **闸门 G3**：inventory T3 → ✅；H-tortoise T3；全量 798 tests 绿

### Wave T4 — Shell 集成

- [x] **T4.1** Overlay 全状态映射表落地（Normal/Modified/Conflicted/Added/Deleted/Missing/Locked/needs-lock/Ignored/Unversioned/depth/nested/externals/switched/mergeinfo）
- [x] **T4.2** Status Cache 三模式：Default / Shell / None（S08）
- [x] **T4.3** 包含/排除路径；可选角标种类
- [x] **T4.4** Finder 右键：普通菜单 +「更多命令…」（≡ Shift 扩展）
- [x] **T4.5** 多选批量命令
- [x] **T4.6** 属性页等价：revision/作者/URL/锁/属性摘要（文件信息或应用内面板）
- [x] **T4.7** Context Menu 设置：提升项、needs-lock 提升 Lock、隐藏未版本路径（S02）；Copy/Move 平台等价入口
- [x] **T4.8** **闸门 G4**：Overlay + S02/S08 → ✅；Finder 冒烟；全量测试

### Wave T5 — 设置、钩子、品牌、分发

- [x] **T5.1** 设置 IA：General / Dialogs / Colours / Network / External Programs / Saved Data（S01,S03–S06,S09–S11）
- [x] **T5.2** 客户端钩子：至少 pre-commit、post-update（S11）
- [x] **T5.3** Bugtraq / issue 正则 + `bugtraq:*` / 关键 `tsvn:*` 项目属性（S12, §8）
- [x] **T5.4** 清认证缓存 / 清日志缓存（S11）
- [x] **T5.5** 外置 Diff/Merge/Blame 按扩展名（S10 完善）
- [ ] **T5.6** App Icon / 空态 / 关于页
- [ ] **T5.7** 包装 `SVNStudio.app` + 干净机/本机冒烟；公证（有证书则做，无则文档阻塞）
- [ ] **T5.8** **闸门 G5**：S 全表 → ✅；H-tortoise T5；全量测试

### Wave GP — 完美收口（强制）

- [ ] **GP.1** 跑覆盖率：必须 = 100%；修任何残留 🟡/❌
- [ ] **GP.2** 清零所有用户可见 `unimplemented` stub
- [ ] **GP.3** 全量 `swift test` + H-tortoise 全文勾选
- [ ] **GP.4** README 功能矩阵与 inventory 对齐
- [ ] **GP.5** 勾选 §2 PERFECT 全部项；CHANGELOG 收口「Tortoise 全量对标完成」
- [ ] **GP.6** **停止 loop**：不再挂 `AGENT_LOOP_WAKE_svnstudio_tortoise_parity`

---

## 6. 与 inventory / 路线图的关系

```
inventory v2（真相） ←每轮更新状态—
        ↑
perfect-loop.md（本文件，执行队列）
        ↑
roadmap T0–T6（战略波次）
```

- 路线图说「做什么波次」；本文件说「每轮做哪一条」。  
- inventory 说「有没有、算不算 ✅」。  
- 冲突时：**inventory 验收定义优先**。

---

## 7. 进度日志

| 时间 | 条目 | commit | 测试 | inventory 变更 | 备注 |
|------|------|--------|------|----------------|------|
| 2026-07-10 | T0.1 | bd0e03b | DiffPerformanceLimits* + WorkspaceGuard 6 测绿 | 无（横切门禁） | `DiffPerformanceLimits` + 源码门禁 + docs/acceptance/performance-guards.md |
| 2026-07-10 | T0.2 | 18f8413 | SvnCommandCatalogTests 7 测绿 | 无（骨架 ID） | `SvnCommandCatalog` 对齐 #1–46 + L01–L20 |
| 2026-07-10 | T0.3 | 931cf06 | MacSvnAppNavigatorTests 11 测绿 | 无 | `perform` + unimplemented 不假装成功 |
| 2026-07-10 | T0.4 | 53cb676 | ProcessRunnerTests 取消相关测绿 | 无 | Task 取消→SIGTERM/5s SIGKILL→`SvnError.cancelled`；`SvnCancellableTask` |
| 2026-07-10 | T0.5 | 27d3fcd | scripts/tests/test_parity_coverage.py 2 测绿 | 生成 parity-coverage.json（当前 0/114） | `scripts/parity-coverage.py` |
| 2026-07-10 | T0.6 | 3e970f5 | 文档骨架 | 无 | `docs/acceptance/H-tortoise-parity.md` |
| 2026-07-10 | T0.7 / G0 | 5330255 | `swift test` 529 绿；parity-coverage + fixture 测绿 | 0/114 基线 | **G0 通过**；进入 T1 |
| 2026-07-10 | T1.1 | 2b4068a | CFMColumn* + ChangesViewModel + status -v | #8 仍 🟡（本地列/刷新齐） | CFM 列持久化 + 刷新时间戳 |
| 2026-07-10 | T1.2 | 4621639 | CFMChangeHighlight* + status -u + repos-status | #8 仍 🟡（远端/颜色齐；Repair 待 T1.3） | Check Repository + 行高亮 |
| 2026-07-10 | T1.3 | d84b794 | RepairMoveCopyPairing + WC move/copy + CFM 菜单 | #45 ✅；#8 ✅ | Repair Move/Copy 集成测绿 |
| 2026-07-10 | T1.4 | d91dfef | CommitSelection+keepLocks+unversioned add+Diff/Revert | #4 ✅ | 说明历史已有；§4.1 进阶项仍开 |
| 2026-07-10 | T1.5 | b92abb7 | UpdateRevisionPolicy + repositoryHeadRevision + 多选更新 | #2 ✅ | 多路径先钉 HEAD 再 -r |
| 2026-07-10 | T1.6 | e8d8067 | diffAgainstBase / diffBetweenPaths + 外置 Diff UI | #5 ✅ | EOL/空白进阶仍开 |
| 2026-07-10 | T1.7 | 097bf1f | Add 勾选 / Delete 确认 / Revert 递归+Diff / Cleanup 选项 | #14,#17,#18,#29 ✅ | 壳层刷新仍属 #16 外 |
| 2026-07-10 | T1.8 | ed54297 | Rename 新名校验 + svn rename + CFM 对话框 | #13 ✅ | 大小写冲突修复仍属 #46 |
| 2026-07-10 | T1.9 | 7021266 | Ignore 文件名/扩展名通配 + svn:ignore 合并写入 | #32 ✅ | global-ignores 仍属 S01/T5 |
| 2026-07-10 | T1.10 | 3f4a472 | Copy/Move 目标路径校验 + svn copy/move 向导 | #36 ✅ | Finder 拖拽引导仍开 |
| 2026-07-10 | T1.11 | 3803f1c | CFM 右键=Catalog 日常子集；⌘K 可搜 svnCommand | 入口齐 | G1 待 T1.12 |
| 2026-07-10 | T1.12 / G1 | 5771e3e | G1：T1 命令行全 ✅；domain D06/07/10/14–16；H-T1 全勾；全测绿 | G1 通过 | 进入 T2.1；#3 仍 T2 |
| 2026-07-10 | T2.1 | 50d0eaa | Checkout/Update-to-rev：-r、depth、--ignore-externals | #1,#3 ✅ | pristines 进阶仍开 |
| 2026-07-10 | T2.2 | eba8ef7 | Show Log：过滤/stop-on-copy/Next·All/Actions | #7 ✅；L18 🟡；L19–L20 ✅ | 统计/离线 T3；右键 T2.3 |
| 2026-07-10 | T2.3 | 48b94a8 | 日志右键 L01/L02/L04–L08 | L01–L08(除L03) ✅ | L03→T3；L09+→T2.4 |
| 2026-07-10 | T2.4 | 687137b | 日志右键 L09–L12、L14 | L09–L12、L14 ✅ | L13→T3；下一 T2.5 L17 |
| 2026-07-10 | T2.5 | ea8cd77 | 日志复制到剪贴板 L17 | L17 ✅ | L15–L16→T3.10 |
| 2026-07-10 | T2.6 | 4f25cc2 | Edit Conflicts + Resolved；属性/树入口 | #11/#12、D08 ✅ | 下一 T2.7 Lock |
| 2026-07-10 | T2.7 | a877356 | Lock/Unlock/Break lock + CFM 入口 | #19–21、D21 ✅ | needs-lock→T4；下一 T2.8 |
| 2026-07-11 | 交接 | 425cba7 | Cursor→Codex 长程说明书 | 无功能变更 | 下一刀仍 T2.8；见 codex-tortoise-parity-long-loop.md |
| 2026-07-13 | T2.8 | c8a2ff0 | Branch/Switch/Merge 单测 + 真实 SVN 两树/Diff 集成测；全量 638 绿 | #22–24、D19/D20 ✅；§4.4 核心勾选 | reintegrate 仍属 T3.6；下一 T2.9 |
| 2026-07-13 | T2.9 | aad330a | Export/Import/Import in Place/Relocate/Remove VC；命令、Service、UI、真实 SVN 集成测 | #26/#27/#30/#43/#44、D04/D26 ✅ | 就地导入通过临时检出原子替换；下一 T2.10 |
| 2026-07-13 | T2.10 | ab0d64a | Create/Apply Patch；路径策略、PatchViewModel、搁置页/⌘K、真实 SVN 往返与 `.rej` 测试 | #33/#34、D22 ✅ | 下一 T2.11 |
| 2026-07-13 | T2.11 | c4a6682 | Properties CRUD/模板/多行编辑；Blame `-r` 范围与悬停日志；CFM/⌘K 路径意图；真实 SVN 测试 | #31/#35、D17 ✅；D23 保持 🟡 | Blame differences→T3.9；下一 T2.12 |
| 2026-07-13 | T2.12 | 4acd365 + 1f444a5 | Repo Browser 远端 mkdir/delete/copy/move/rename；pending 确认快照；远端 owner/comment/created 锁列；全量 673 绿，含真实 SVN 写操作/锁信息集成测 | #10、D24 ✅；§4.5 远端写/锁列 ✅ | 下一 T2.13 |
| 2026-07-13 | T2.13 | e646b1d | Filename case conflict repair：策略校验、临时 SVN 改名中转、失败回滚、CFM/⌘K 向导与真实 SVN 提交验证 | #46、D15 ✅；全量 683 绿 | 下一 T2.14 |
| 2026-07-13 | T2.14 | 5a418c9 | Progress Auto-close 四档策略、设置持久化、更新/本地操作完成提示接线 | §4.3/§4.7 Auto-close ✅；全量 688 绿 | 下一 T2.15/G2 |
| 2026-07-13 | T2.15/G2 | 4d5fff6 | 审计 T2 独占范围；确认 #41 已由 L05/L06 覆盖；#15/#16 波次纠正为计划中的 T3.8 | #41 ✅；H-T2/G2 ✅；全量 688 绿 | 下一 T3.1 |
| 2026-07-13 | T3.1 | 7e5b1e0 | Diff with URL：URL+revision 表单、peg/user@host 校验、认证 stdin/重试、原子导航 intent、Unified/左右分栏、真实 SVN 跨 URL 测试 | #6 ✅；H-T3 对应项 ✅；覆盖率 68/114；全量 710 绿 | 下一 T3.2 |
| 2026-07-13 | T3.2 | 681268b | Revision Graph：repo-root verbose log 构图、copy/history 边、glob 分类/颜色混色、剪枝、拓扑/时间线、分页/All、四类节点动作；真实 SVN copy-edge/Diff；全量 724 绿 | #9、D25、S07、§4.6 ✅；H-T3 对应项 ✅；覆盖率 71/114 | 下一 T3.3 |
| 2026-07-13 | T3.3 | eb73ea1 | Change Lists：status XML 归属、CFM 列/分组、移入/移出与深度、Commit 按列表选择、`ignore-on-commit` 默认排除、cmd.38 原子路径意图；真实 SVN 往返；全量 730 绿 | #38、D11、§4.2 Changelist ✅；H-T3 对应项 ✅；覆盖率 73/114 | 下一 T3.4 |
| 2026-07-13 | T3.4 | 4658126 | Externals：现代/旧式定义解析、目录/文件 external 结构化编辑、operative/peg revision、注释保留、安全本地路径校验、仓库 URL 拖拽预填、保存后非忽略 externals 更新；真实 SVN 往返；全量 738 绿 | #39、D18、H-T3 Externals ✅；覆盖率 75/114 | 下一 T3.5 |
| 2026-07-13 | T3.5 | c4bf526 | 官方 `svn shelve` V2/V3：能力探测、列表/Diff/Log/Unshelve/Drop；设置持久化；官方与本地双轨 UI；手工快照迁移事务与失败保留；真实 SVN V2/V3 往返；全量 749 绿 | #37、D12、S05、H-T3 ✅；覆盖率 78/114 | 下一 T3.6 |
| 2026-07-13 | T3.6 | 240f71c | 现代 complete merge reintegrate、dry-run/执行、日志 L13 `svn merge -c REV` 与确认门控；真实 SVN 单修订/完整合并验证；全量 755 绿 | #25、#42、L13、D20、H-T3 ✅；覆盖率 81/114 | 下一 T3.7 |
| 2026-07-13 | T3.7 | ab5f77a | `svnadmin create --fs-type fsfs`、用户工具链路径解析、仓库浏览器/⌘K 入口、错误码保留；真实仓库结构验证；全量 761 绿 | #28、H-T3 ✅；覆盖率 82/114 | 下一 T3.8 |
| 2026-07-13 | T3.8 | 86d65da | `svn delete --keep-local`；未版本预览勾选、二次 status/WC 边界复核、父子路径合并；CFM/⌘K 原子意图；真实 SVN 文件/目录往返；全量 771 绿 | #15/#16、D15、H-T3 ✅；覆盖率 84/114 | 下一 T3.9 |
| 2026-07-13 | T3.9 | 5f519b9 | 双修订 blame+diff 行对齐；左右作者/日期/内容、变化汇总/筛选、BASE；L03 PREV:REV、仓库 URL@peg、CFM/⌘K；真实 SVN 双提交往返；全量 778 绿 | #40、L03、D23、H-T3 ✅；覆盖率 87/114 | 下一 T3.10 |
| 2026-07-13 | T3.10 | c9c41ef | 全量 revprops 展示；作者/日志说明仅变化写入；认证重试/写锁；UTF-8 `0600` 临时值文件；hook 拒绝提示；日志右键/详情/⌘K；真实 SVN 无 hook 拒绝与中文/自定义属性往返；全量 787 绿 | L15、L16、H-T3 ✅；覆盖率 89/114 | 下一 T3.11 |
| 2026-07-13 | T3.11 | 73cf430 | 日志统计作用于当前过滤结果；作者/日期/动作统计；日志缓存按仓库目标/stop-on-copy 隔离，支持容量/保留期、清理、网络/认证/环境失败回退与强制离线；设置持久化；全量 798 绿 | L18、S13、H-T3 ✅；覆盖率 91/114 | 下一 T3.12/G3 |
| 2026-07-13 | T3.12/G3 | 73cf430 + 本次 docs | D13 聚合域验收描述修正；T3 inventory/H 清单核验；全量 798 绿；覆盖率 92/114 | G3 ✅ | 下一 T4.1 |
| 2026-07-13 | T4.1 | 304d2b6 | 全状态结构化采集/角标映射；current/BASE 属性差集识别 mergeinfo-only；根/目录递归聚合；并发刷新合并；Finder Sync target/appex 校验；全量 810 绿 | Overlay 5 行 ✅、Ignored/Unversioned 🟡；D01 保持 🟡 | 覆盖率 97/114；下一 T4.2 |
| 2026-07-13 | T4.2 | 9e4cd78 | Default 整棵 WC/8s、Shell 请求目标/2s、None 禁用采集但保留菜单；设置持久化、v1 迁移、原子热更新；generation 丢弃旧并发结果；Finder Sync target/appex 校验；全量 822 绿 | S08 与 Overlay 第 7 行升为 🟡；路径/可选角标待 T4.3 | 覆盖率 97/114；下一 T4.3 |
| 2026-07-13 | T4.3 | 5fa45f5 | Finder 包含/排除卷与路径、exclude 优先；18 类角标可选；配置 v3；include 子树监视目录；Finder Sync target/appex 校验；全量 836 绿 | S08、Overlay 第 4/7 行升为 ✅；D01 保持 🟡 | 覆盖率 100/114；下一 T4.4 |
| 2026-07-13 | T4.4 | 011a7b2 | Finder 普通菜单与「更多命令…」扩展菜单；统一 `SvnCommandID` / `svnstudio://command` 深链；普通命令与 5 个 Catalog 扩展命令复用 Navigator 执行；Finder Sync target/appex 校验；全量 839 绿 | H-T4.4 ✅；D02 保持 🟡（Finder 拖拽待 T4）；S02 保持 ❌（T4.7） | 覆盖率 100/114；下一 T4.5 |
| 2026-07-13 | T4.5 | f26cf1e | Finder 全部选中项保序传递；重复 `path` query 构建/解析；无选中项回退 targeted URL；Navigator 复用批量 `perform`；Finder Sync target/appex 校验；全量 842 绿 | H-T4.5 ✅；D02 保持 🟡（Finder 拖拽待 T4） | 覆盖率 100/114；下一 T4.6 |
| 2026-07-13 | T4.6 | 5a21470 | Finder「更多命令…」属性入口；绝对子文件路径选择包含它的最深已登记 WC；应用内面板结构化解析 info commit/lock，展示 WC 状态、修订、作者、URL、锁与属性摘要；请求代次丢弃旧的异步 info/status 结果；真实 SVN 锁信息验证；全量 846 绿；Finder appex 校验通过 | D01、H-T4.6 ✅；D02 保持 🟡（Finder 拖拽待 T4） | 覆盖率 101/114；下一 T4.7 |
| 2026-07-14 | T4.7 | 69a820f | Context Menu 设置模型与持久化；顶层/子菜单规划、needs-lock 自动提升 Lock、未版本/已忽略隐藏与排除路径；Finder 同步状态快照；Finder Copy/Move 菜单深链进入应用内向导；配置 v4 兼容旧版本；全量 862 绿；Finder appex 构建与校验通过 | S02、D02、H-T4.7 ✅；G4 仍待 Finder 冒烟与闸门审计 | 覆盖率 103/114；下一 T4.8/G4 |
| 2026-07-14 | T4.8/G4 | 66ce3c1 | Finder target App Sandbox；配置镜像到扩展容器；Homebrew SVN 直接探测与只读执行前缀；真实 `status/info/proplist` 成功日志；Added/Modified 不同角标；appex/深层签名校验；全量 868 绿 | Overlay、S02、S08、H-T4/G4 ✅ | 覆盖率 103/114；下一 T5.1 |
| 2026-07-14 | T5.1 | c113d7d | 设置页稳定分类侧栏与分区内容；原设置保存/加载契约保持；分类模型/映射守卫、存储、Finder packaging 测试及全量 871 绿；Xcode Debug 构建通过 | D28、S01/S03/S04/S06/S09/S10/S11 升为 🟡；H-T5 设置 IA ✅ | 覆盖率 103/114；下一 T5.2 |
| 2026-07-14 | T5.2 | c488dd5 | pre-commit/post-update 配置与 UTF-8 官方参数文件；WC 祖先路径匹配；非零退出/超时；Commit add 前阻断；Update/Switch/Checkout 成败回调；设置持久化与旧配置兼容；全量 879 绿 | H-T5 客户端钩子 ✅；S11 保持 🟡（认证清理待 T5.4） | 覆盖率 103/114；下一 T5.3 |
| 2026-07-14 | T5.3 | b3a528b | Bugtraq 项目属性解析；`bugtraq:message/number/append/logregex/url` 文本内高亮、链接、输入与诊断；`^/` 仓库根缺失显式诊断；通用及所有操作 `tsvn:logtemplate*` 接线；项目 LCID/locale 生效到 macOS 拼写检查；提交/锁定按每路径祖先属性 fail-closed、并发刷新不打断写操作、夺锁确认保留说明；属性草稿诊断；无扩展名文件/带点目录节点类型覆盖；全量 917 绿 | D17、D27、S12、H-T5 Bugtraq ✅ | 覆盖率 105/114；下一 T5.4 |
| 2026-07-14 | T5.4 | 874122f | 设置页二次确认清认证缓存；使用配置 SVN 的 `auth --remove '*'` 同时清理 auth 文件与 macOS Keychain；空缓存幂等，命令失败保留文件，AI Provider Keychain 隔离；日志缓存清理防重入；全量 924 绿 | D03、S11、H-T5 缓存清理 ✅ | 覆盖率 107/114（93.86%）；下一 T5.5 |
| 2026-07-14 | T5.5 | 92efa39 | 外置 Diff/Merge/Blame 规则按用途和扩展名持久化；大小写无关精确规则优先，留空/`*`/`*.*` 为默认；Diff 保留旧配置兜底，Merge 使用 base/mine/theirs/result 且不自动 resolve，Blame 限制工作副本边界；全量 937 绿 | S10、H-T5 外置工具 ✅ | 覆盖率 108/114（94.74%）；下一 T5.6 |

---

## 8. 启动指令（给人 / 给代理）

```text
开始 SVN Studio Tortoise 完美 Loop：
1. 切分支 feat/tortoise-parity-perfect-loop
2. 打开 docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
3. 做第一个 [ ]（T0.1），遵守 §3 规则
4. 每轮结束挂 one-shot AGENT_LOOP_WAKE_svnstudio_tortoise_parity
5. 直到 §2 PERFECT 全满足再停
```

用户说「继续 loop / 唤醒」时：只读本文件 + inventory，禁止另起炉灶砍范围。
