# SVN Studio × TortoiseSVN 全量对标 — 完美 Loop 规划

> **面向 AI 代理的工作者：** 每轮只取本文件**第一个未完成** `[ ]`；用 TDD 实现 → 测 → 更新 inventory 状态 → 勾本文件 → CHANGELOG →（可选）push → **再挂 one-shot 唤醒**。  
> 必需参考：[`2026-07-10-tortoisesvn-feature-inventory.md`](../specs/2026-07-10-tortoisesvn-feature-inventory.md)（验收唯一真相）、[`2026-07-10-long-term-iteration-roadmap.md`](2026-07-10-long-term-iteration-roadmap.md)、[`2026-07-10-long-term-product-design.md`](../specs/2026-07-10-long-term-product-design.md)。

| 项 | 内容 |
|----|------|
| 创建日期 | 2026-07-10 |
| 产品 | SVN Studio |
| Loop 代号 | `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` |
| 建议工作分支 | `feat/tortoise-parity-perfect-loop`（从当前交付 tip / `feat/ui-ux-ia-refactor` 切出） |
| 能力基线 | inventory **v2**（命令 #、日志 L#、设置 S#、Overlay、DUG 域） |
| 北极星 | **小乌龟有的，Studio 必须有**（平台换壳，不砍能力） |
| 停止条件 | 见 §2「完美定义」——**全部满足才停**；未满足则继续 loop |

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
| G1 | T1 末 | inventory #2–5,8,13–14,17–18,29,32,36,45 及 Commit/CFM 对话框清单 → ✅ |
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
- [ ] **T0.6** 验收清单骨架：`docs/acceptance/H-tortoise-parity.md`（按 Wave 分节，先空勾）
- [ ] **T0.7** **闸门 G0**：全量 `swift test`；覆盖率脚本跑通；进度日志写 G0 通过

### Wave T1 — 日常闭环（对话框级）

- [ ] **T1.1** Check for Modifications：本地 status、列、刷新（#8 升 🟡→接近 ✅）
- [ ] **T1.2** CFM：Check Repository (`status -u`)、颜色规则（#8）
- [ ] **T1.3** CFM：Repair Move / Repair Copy（#45）
- [ ] **T1.4** Commit 对话框级：勾选、未版本→add、Keep locks、说明历史、单项 Diff/Revert（#4 + §4.1）
- [ ] **T1.5** Update：同仓多路径统一 revision（#2 + §4.3）
- [ ] **T1.6** Diff：BASE、双文件、外置查看器入口（#5）
- [ ] **T1.7** Add / Delete / Revert（勾选列表）/ Cleanup（#14,17,18,29）
- [ ] **T1.8** Rename（#13）
- [ ] **T1.9** Ignore 文件/通配（#32）
- [ ] **T1.10** SVN Copy / Move 向导（#36）
- [ ] **T1.11** 变更树右键 = Catalog 日常子集；⌘K 可搜到
- [ ] **T1.12** **闸门 G1**：更新 inventory 对应行 → ✅；H-tortoise T1 节手工勾选；`swift test` 全绿

### Wave T2 — 进阶日常 + 仓库

- [ ] **T2.1** Checkout + Update to revision（depth、ignore-externals）（#1,#3）
- [ ] **T2.2** Show Log：过滤、stop-on-copy、Next/All、Actions 列（#7, L18–L20）
- [ ] **T2.3** 日志右键：Compare WC/previous、unified diff、Save/Open、Blame、Browse（L01–L08）
- [ ] **T2.4** 日志右键：Branch/Tag from rev、Update to rev、Revert to/from rev、Checkout/Export from log（L09–L12,L14）
- [ ] **T2.5** 日志：Copy clipboard（L17）；Edit author/msg / rev props 可放 T3（L15–L16 若本轮做不完保持 `[ ]` 并移到 T3 显式条目——**本条先做 L17**）
- [ ] **T2.6** Edit Conflicts + Resolved 打磨（#11,#12）；属性/树冲突入口
- [ ] **T2.7** Lock / Unlock / Break lock（#19–21）
- [ ] **T2.8** Branch-Tag / Switch / Merge+dry-run（#22–24）
- [ ] **T2.9** Export / Import / Import in Place / Relocate / Remove from VC（#26,#27,#30,#43,#44）
- [ ] **T2.10** Create Patch / Apply Patch（#33,#34）
- [ ] **T2.11** Properties 模板与编辑（#35）；Blame 悬停日志（#31）
- [ ] **T2.12** Repo Browser 远端写 + 高危确认 + 锁列（#10 + §4.5）
- [ ] **T2.13** Filename case conflict repair（#46）
- [ ] **T2.14** Progress Auto-close 策略（§4.7 基础）
- [ ] **T2.15** **闸门 G2**：inventory T2 范围 → ✅；H-tortoise T2；全量测试

### Wave T3 — 专业能力

- [ ] **T3.1** Diff with URL（#6）
- [ ] **T3.2** Revision Graph 核心 + 设置 pattern（#9, S07, §4.6）
- [ ] **T3.3** Change Lists（#38, D11）
- [ ] **T3.4** Externals 编辑与更新行为（#39, D18）
- [ ] **T3.5** 官方 `svn shelve` 对齐 + 本地搁置迁移方案落地（#37, S05 shelve 版本）
- [ ] **T3.6** Merge reintegrate + 日志 Merge revision to…（#25,#42, L13）
- [ ] **T3.7** Create Repository Here（#28）
- [ ] **T3.8** Delete keep local / Delete unversioned（#15,#16）
- [ ] **T3.9** Compare revisions / Blame differences（#40, L03）
- [ ] **T3.10** 日志 Edit author/message + revision properties（L15,L16）
- [ ] **T3.11** 日志统计 / 离线缓存（L18 剩余, S13）
- [ ] **T3.12** **闸门 G3**：inventory T3 → ✅；H-tortoise T3；全量测试

### Wave T4 — Shell 集成

- [ ] **T4.1** Overlay 全状态映射表落地（Normal/Modified/Conflicted/Added/Deleted/Missing/Locked/needs-lock/Ignored/Unversioned/depth/nested/externals/switched/mergeinfo）
- [ ] **T4.2** Status Cache 三模式：Default / Shell / None（S08）
- [ ] **T4.3** 包含/排除路径；可选角标种类
- [ ] **T4.4** Finder 右键：普通菜单 +「更多命令…」（≡ Shift 扩展）
- [ ] **T4.5** 多选批量命令
- [ ] **T4.6** 属性页等价：revision/作者/URL/锁/属性摘要（文件信息或应用内面板）
- [ ] **T4.7** Context Menu 设置：提升项、needs-lock 提升 Lock、隐藏未版本路径（S02）
- [ ] **T4.8** **闸门 G4**：Overlay + S02/S08 → ✅；Finder 冒烟；全量测试

### Wave T5 — 设置、钩子、品牌、分发

- [ ] **T5.1** 设置 IA：General / Dialogs / Colours / Network / External Programs / Saved Data（S01,S03–S06,S09–S11）
- [ ] **T5.2** 客户端钩子：至少 pre-commit、post-update（S11）
- [ ] **T5.3** Bugtraq / issue 正则 + `bugtraq:*` / 关键 `tsvn:*` 项目属性（S12, §8）
- [ ] **T5.4** 清认证缓存 / 清日志缓存（S11）
- [ ] **T5.5** 外置 Diff/Merge/Blame 按扩展名（S10 完善）
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
| 2026-07-10 | T0.5 | （待填） | scripts/tests/test_parity_coverage.py 2 测绿 | 生成 parity-coverage.json（当前 0/114） | `scripts/parity-coverage.py` |

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
