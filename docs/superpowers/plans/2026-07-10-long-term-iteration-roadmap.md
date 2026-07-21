# SVN Studio 长期迭代路线图（TortoiseSVN 全量对标）

> **⚠️ 历史归档（2026-07-22 RC）——勾选表已过时，不可再作为未完成真相。**
>
> Tortoise 能力验收唯一真相为：
> - [inventory v2](../specs/2026-07-10-tortoisesvn-feature-inventory.md) **114/114（100%）**
> - [H-Tortoise](../../acceptance/H-tortoise-parity.md)
> - [parity-coverage.json](../../acceptance/parity-coverage.json)
>
> Perfect Loop 已于 GP.6 **停止**。下文 T0–T5 的 `[ ]` 为早期规划残留，**禁止**据此重新开启 T0–T5 能力开发或重启 Loop。
> 工程收口与 residual 见 [RC 规格](../specs/2026-07-22-release-closeout-design.md) 与 [release-closeout-2026-07-22.md](../../acceptance/release-closeout-2026-07-22.md)。


| 项 | 内容 |
|----|------|
| 日期 | 2026-07-10 |
| 状态 | **强制目标：小乌龟有的，Studio 必须有** |
| 能力基线 | [`2026-07-10-tortoisesvn-feature-inventory.md`](../specs/2026-07-10-tortoisesvn-feature-inventory.md) |
| 详设 | [`2026-07-10-long-term-product-design.md`](../specs/2026-07-10-long-term-product-design.md) |
| 前序 | IA U1–U4 已落地；卡死修复已合入 |

## 1. 北极星

> 在 macOS 上提供与 **TortoiseSVN 命令矩阵等价** 的完整客户端：Finder 集成 + 全套对话框选项 + 设置体系；平台差异只换壳，不砍能力。

验收不以「能提交」为准，而以 **inventory 每一行 ✅** 为准。

## 2. 总览波次（T 系列 = Tortoise Parity）

| 波次 | 主题 | 覆盖 inventory | 预估 |
|------|------|----------------|------|
| **T0** | 性能门禁 + 命令目录骨架 | 横切 | 1 周 |
| **T1** | 日常 Top：CFM/Commit/Update/Diff/Add/Delete/Revert/Rename/Ignore/Copy-Move | #2–5,8,13–18,29,32,36 | 3–4 周 |
| **T2** | 日志/冲突/锁/分支切换合并/检出导出导入/补丁/属性/Relocate | #1,3,6部分,7,10–12,19–24,26–27,30–31,33–35,41 | 4–5 周 |
| **T3** | 修订图、Changelist、Externals、Shelve 官方、扩展菜单命令、Create Repo、高级合并 | #6,9,25,28,37–40,42 + 扩展菜单 | 4–5 周 |
| **T4** | Finder 叠图全状态 + 缓存策略 + 属性页等价 + 设置全页 | Overlay 全表 + Settings | 3–4 周 |
| **T5** | 钩子/Bugtraq/外置工具链/视觉品牌/分发公证 | 设置高级 + L5/L7 | 2–3 周 |
| **T6** | 差异化（AI/Git 迁移） | 非小乌龟，不阻塞 T0–T5 | 持续 |

旧 L0–L8 映射：L0→T0；L1∪L2→T1+T4；L3→T2/T3；L4→T2；L5/L7→T5；L6→T2；L8→T6。

## 3. 波次详单

### T0 — 门禁与骨架（先做）

- [x] 固化布局/Diff 性能规范（防 AttributeGraph 再发）
- [x] 落地 `SvnCommandCatalog`（全命令 ID，与 inventory `#` 对齐）
- [x] 统一 `Navigator.perform(command:paths:options:)`
- [x] 可取消 `svn` 任务模型
- [x] 自动化：inventory 覆盖率报表（已实现命令 / 总数）

**出门标准：** ✅ G0 已通过（2026-07-10：`swift test` 529；coverage 脚本可跑；基线 0/114）。

### T1 — 日常闭环（小乌龟每天用的）

必须达到对话框级，而非仅按钮：

- [x] **Check for Modifications**：本地 status、Check Repository(`-u`)、颜色规则、列配置、Repair Move/Copy
- [x] **Commit**：勾选、未版本勾选→add、Keep locks、说明历史、单项 Diff/Revert
- [x] **Update**：统一 revision 更新策略
- [x] **Diff**：BASE Diff、双文件 Diff、外置查看器入口
- [ ] **Add / Delete / Revert / Cleanup / Rename**
- [ ] **Ignore**（文件/通配）
- [ ] **SVN Copy / Move**（应用内 + 尽量 Finder 拖拽引导）
- [ ] 变更树右键 = 命令目录子集

**出门标准：** inventory 对应行全部从 ❌/弱 升为 ✅（手工清单可勾）。

### T2 — 进阶日常 + 仓库

- [ ] Checkout / Update to revision（depth、ignore-externals）
- [ ] Show Log 完整：过滤、stop-on-copy、文件列表动作（Diff/Blame/另存/打开）
- [x] Edit Conflicts + Resolved 打磨
- [x] Lock / Unlock / Break lock
- [ ] Branch-Tag / Switch / Merge（含 dry-run）
- [ ] Export / Import / Relocate
- [ ] Create Patch / Apply Patch
- [ ] Properties 模板与编辑
- [ ] Blame 体验（悬停日志）
- [ ] Repo Browser 远端写操作（mkdir/delete/copy/move/rename）+ 高危确认
- [ ] Diff with URL（可放 T2 末或 T3）

### T3 — 小乌龟「专业」能力

- [ ] Revision Graph（可配 trunk/branches/tags 模式）
- [ ] Change Lists
- [ ] Externals 编辑与更新行为
- [ ] 官方 `svn shelve` 对齐（保留现有本地 shelve 为兼容层或迁移）
- [ ] Merge reintegrate、日志「合并所选修订」
- [ ] Create Repository Here
- [ ] Delete keep local / Delete unversioned
- [ ] Compare revisions / Blame differences / 高级日志动作

### T4 — Shell 集成完整度（对标 Explorer Integration）

- [ ] Overlay **全状态**（含 needs-lock、locked、ignored、unversioned、depth、externals、switched、nested）
- [ ] Status Cache 三模式等价（Default/Shell/None）
- [ ] 包含/排除路径
- [ ] Finder 右键：普通菜单 +「更多命令」（≡ Shift 扩展菜单）
- [ ] 多选批量
- [ ] 属性页等价（文件信息扩展或专用面板）：revision、作者、URL、锁、属性摘要

### T5 — 设置、钩子、品牌、分发

- [ ] 设置信息架构对齐小乌龟分类（通用/叠图/网络/外部工具/钩子/Bugtraq/保存数据/颜色）
- [ ] 客户端钩子（至少 pre-commit / post-update 脚本）
- [ ] Bugtraq / issue 正则（提交说明）
- [ ] 清认证缓存
- [ ] App Icon / 空态 / 关于页
- [ ] Developer ID 公证 + 干净机冒烟

### T6 — 差异化（不计入小乌龟完成度）

- AI、Git 迁移、团队热力图等按反馈增强。

## 4. 跟踪方式

1. **唯一真相：** `tortoisesvn-feature-inventory.md` 状态列  
2. 每波结束更新：❌→🟡→✅，并附验证证据（测试名 / H1 条目）  
3. 覆盖率公式：`✅ / (全部必须行)` → 目标 **100%**  
4. 禁止用「主路径能用」关闭波次  

## 5. 风险（全量对标特有）

| 风险 | 缓解 |
|------|------|
| macOS Finder Sync 能力 < Explorer | 主窗口补齐 100% 命令；Finder 尽力；缺口用 Services/拖拽向导补 |
| 工作量巨大 | T0 先齐命令 ID；按 T1→T5 切片，但范围不砍 |
| svn shelve 与现有本地搁置冲突 | T3 专设迁移方案 |
| 修订图性能 | 异步 + 限深度 + 取消 |

## 6. 执行载体（完美 Loop）

原则已定为 **全量必须有**。日常执行不靠本文件勾选，而靠：

**[`2026-07-10-tortoise-parity-perfect-loop.md`](2026-07-10-tortoise-parity-perfect-loop.md)**

- 每轮只做第一个 `[ ]`，挂 `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` one-shot 唤醒  
- **停止条件**：该文件 §2 PERFECT（inventory 100% ✅ + 无 stub + 全量测试 + H1 + 文档收口）  
- 开工：切 `feat/tortoise-parity-perfect-loop`，从 **T0.1** 开始  

## 7. 你需要确认的一点

若同意完美 Loop：直接说「开始 loop」或「从 T0 开工」即可进入编码；无需再拆一层空计划。
