# TortoiseSVN（小乌龟）全量能力清单与 SVN Studio 差距矩阵

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-10 |
| 版本 | **v2（深度挖掘）** |
| 来源 | [DUG 目录](https://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-dug.html)、[CLI Cross-Ref](https://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-cli-main.html)、[Settings](https://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-dug-settings.html)、[Show Log](https://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-dug-showlog.html)、[Extended menu](https://tortoisesvn.net/extendedcontextmenu.html)、[Features](https://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-preface-features.html) |
| 产品原则 | **小乌龟有的，SVN Studio 必须有**（平台换壳，不砍能力） |
| 路线图 | [`2026-07-10-long-term-iteration-roadmap.md`](../plans/2026-07-10-long-term-iteration-roadmap.md) |
| 完美 Loop（执行队列） | [`2026-07-10-tortoise-parity-perfect-loop.md`](../plans/2026-07-10-tortoise-parity-perfect-loop.md) |
| 状态图例 | ✅ 可用 · 🟡 雏形/弱 · ❌ 缺失 · 🔷 小乌龟扩展菜单（Shift） |

---

## 0. 怎么用这份清单

1. **唯一验收真相**：每一行（含对话框子项、日志右键、设置页）都要变成 ✅。  
2. **不是「有个按钮」就算有**：必须达到 §4 对话框级选项 + CLI 行为一致。  
3. **平台映射**见 §1；映射失败时用主窗口/⌘K/Services 补齐，**禁止**以「macOS 做不到」关闭需求。  
4. 每波结束只改本文件状态列，并附 H1/单测证据。

---

## 1. 平台等价映射

| Windows 小乌龟 | macOS SVN Studio 必须等价 |
|----------------|---------------------------|
| Explorer 右键（普通 + Shift 扩展） | Finder Sync 右键 +「更多命令…」+ 变更树右键 + ⌘K |
| Overlay 角标 + Status Cache | Finder Sync badge + 缓存三模式设置 |
| Explorer 属性页 Subversion 页 | 文件信息扩展 / 应用内「SVN 信息」面板 / Quick Look |
| 右键拖拽 Copy/Move | Finder 拖拽引导 + 应用内 SVN Copy/Move 向导 + Services |
| TortoiseMerge | 内置三路合并 + 可配外置 Diff/Merge |
| TortoiseBlame | Blame 视图 + 行悬停日志 |
| TortoiseIDiff / Office Diff | 外置工具注册（图片/Office） |
| `svnadmin create` | 「在此创建仓库」 |
| 客户端钩子 / Bugtraq / tsvn: 项目属性 | 设置 + 属性编辑器同等能力 |
| 进度对话框 + Auto-close 策略 | 统一 Progress / 可配置自动关闭 |
| 认证缓存清理 | 设置「保存的数据」清 Keychain/svn auth |

---

## 2. DUG 能力域总表（小乌龟整章都要覆盖）

对照官方 Daily Use Guide 目录；Studio 不得缺域。

| 域 ID | DUG 章节 | 必须覆盖的能力要点 | Studio | 波次 |
|-------|----------|-------------------|--------|------|
| D01 | Icon Overlays / WC Status | 全状态角标、递归传播、属性页状态 | 🟡 | T4 |
| D02 | Context Menus / Drag-Drop | 普通+扩展菜单、拖拽 copy/move、快捷键 | 🟡 CFM/⌘K 齐；Finder 拖拽 T4 | T1/T4 |
| D03 | Authentication | 提示凭据、缓存、清缓存 | 🟡 | T2/T5 |
| D04 | Import / Import in Place | import、就地导入 | ✅ `svn import` + 导入后临时检出替换，保留可用工作副本 | T2 |
| D05 | Checkout | depth、revision、ignore-externals、pristines | ✅ depth/rev/omit-ext；pristines 进阶仍开 | T2 |
| D06 | Commit | 勾选、changelist、部分提交、日志历史、进度 | ✅ | T1 |
| D07 | Update | 统一 HEAD 修订、冲突列表入口 | ✅ | T1 |
| D08 | Conflicts | 文件/属性/树冲突、编辑、resolved | ✅ 文本三路/树/属性面板 + 批量 Resolved；外置合并工具仍可增强 | T2 |
| D09 | Check for Modifications | 本地+远端、颜色、Repair、列配置 | ✅ | T1 |
| D10 | Diff | BASE、双文件、EOL/空白、文件夹比较、外置工具 | ✅ T1 核心；EOL/文件夹 T2 | T1/T2 |
| D11 | Change Lists | 分组、提交按列表 | ✅ status XML 归属；CFM 列/分组与列表移入/移出；Commit 按列表选择并保留 `ignore-on-commit` 语义 | T3 |
| D12 | Shelving | 官方 svn shelve V2/V3 选项 | ✅ 官方 `x-shelve`/`x-unshelve`/list/diff/log/drop；能力探测；本地手工快照迁移且失败保留快照 | T3 |
| D13 | Show Log | 三栏、过滤、统计、离线、右键动作全集 | 🟡 过滤/stop/Next·All/Actions/L01–L17 ✅；统计/离线仍开 | T2/T3 |
| D14 | Add / Ignore | 递归可添加、ignore 通配、global-ignores | ✅ 文件名/通配；global-ignores T5 | T1 |
| D15 | Copy/Move/Rename/Delete | rename、delete keep local、清未版本、Repair rename、大小写冲突 | ✅ Rename/Copy/Move/Delete/Repair/大小写冲突修复向导；keep-local 确认与未版本预览勾选/路径复核齐全 | T1/T2/T3 |
| D16 | Revert / Cleanup | 勾选 revert、回收站安全网、cleanup 选项 | ✅ | T1 |
| D17 | Properties | svn: + tsvn: 项目属性、属性编辑器 | ✅ CRUD、多行编辑、文件/目录模板过滤、常用 svn:/tsvn:/bugtraq: 模板 | T2/T5 |
| D18 | Externals | 文件夹/文件 externals、拖拽创建 | ✅ 结构化编辑器支持目录/文件 external、operative/peg revision、注释保留、仓库浏览器 URL 拖拽预填；保存可立即更新且不忽略 externals | T3 |
| D19 | Branch/Tag / Switch | 三种 copy 源、switch 警告 | ✅ HEAD/特定 revision/WC；Switch `-r` + 未提交确认；主窗口/CFM/⌘K 可达 | T2 |
| D20 | Merge | 范围/树/reintegrate、dry-run、mergeinfo、冲突 | ✅ 范围/两树/现代 complete merge（reintegrate）/dry-run/Unified Diff/mergeinfo/冲突回跳；日志单修订合并也已接入 | T2/T3 |
| D21 | Locking | lock/unlock/break、needs-lock、锁钩子 | ✅ lock/unlock/break+确认；needs-lock 提升/钩子仍属 T4/T5 | T2 |
| D22 | Patch | create/apply patch | ✅ 按勾选路径生成单一 patch、应用 patch、`.rej` 冲突报告、搁置页/⌘K 入口 | T2 |
| D23 | Blame | blame + blame differences | ✅ 修订范围/悬停日志；双修订内容+归属差异、BASE/previous、变化筛选；历史 URL/peg 解析 | T2/T3 |
| D24 | Repo Browser | 浏览+远端写操作+锁信息 | ✅ 远端 mkdir/delete/copy/move/rename 均有提交说明与高危确认；`svn info --xml --depth immediates` 锁信息列展示 owner/comment/created | T2 |
| D25 | Revision Graph | 节点分类、视图、剪枝、节点动作 | ✅ repo-root verbose log 构图；拓扑/时间线；标签/未分类/已删除剪枝；Log/Checkout/Blame/Diff 节点动作 | T3 |
| D26 | Export / Unversion / Relocate | export、移除版本控制、relocate | ✅ export（含 omit externals）、安全移除 `.svn`、`switch --relocate` | T2 |
| D27 | Bugtraq / Repo Viewer 集成 | issue 正则、Web 仓库链接 | ❌ | T5 |
| D28 | Settings 全页 | 见 §6 | ❌/弱 | T4/T5 |

---

## 3. 命令矩阵（CLI Cross-Ref + 扩展菜单）

| # | 命令 | 核心 `svn` / 行为 | 对话框必选项（摘要） | Studio | 波次 |
|---|------|-------------------|----------------------|--------|------|
| 1 | Checkout | `checkout [-depth] [--ignore-externals] [-r] URL PATH` | depth、omit externals、revision | ✅ | T2 |
| 2 | Update | 先 `info` 取统一 rev 再 `update`（多选同仓） | 进度、冲突入口 | ✅ | T1 |
| 3 | Update to revision | `update [-r][-depth][--ignore-externals]` | rev、depth、omit externals | ✅ | T2 |
| 4 | Commit | `status`→可选 `add`→`commit [-depth][--no-unlock]` | 勾选、未版本、Keep locks、说明历史 | ✅ | T1 |
| 5 | Diff | 视觉 Diff（非仅 unified）；双任意文件 | 外置查看器、EOL/空白（进阶） | ✅ | T1 |
| 6 | Diff with URL | 🔷 与 URL@rev | URL+rev 选择器 | ✅ URL+revision 表单；peg revision、svn+ssh user@host、认证重试；Unified/左右分栏复用；真实 SVN 跨 URL 验证 | T3 |
| 7 | Show Log | `log -v [--limit][--stop-on-copy]` | 见 §5 日志动作 | ✅ 过滤/stop/Next·All/Actions/L01–L17；统计/离线→T3 | T2 |
| 8 | Check for Modifications | `status -v` / `status -u -v` | Check Repository、颜色、Repair | ✅ | T1 |
| 9 | Revision Graph | `log -v` @ repo root 分析 | 分类模式、节点菜单 | ✅ copy/history 边；拓扑 Canvas/时间线；分页/All；四类节点动作；真实 SVN copy-edge/Diff 验证 | T3 |
| 10 | Repo Browser | `list -v`、`info`（含锁） | 远端 mkdir/delete/copy/move/rename | ✅ `svn info --xml --depth immediates` 返回锁详情；mkdir/delete/copy/move/rename 均需提交说明，delete/move/rename 二次确认 | T2 |
| 11 | Edit Conflicts | 外置/内置三路 | mine/theirs/base | ✅ CFM/冲突工作区入口；内置三路+树/属性；外置工具可增强 | T2 |
| 12 | Resolved | `resolved` | 多选 | ✅ 冲突工作区勾选批量 + CFM 确认；树冲突排除 | T2 |
| 13 | Rename | `rename` | 新名校验 | ✅ | T1 |
| 14 | Delete | `delete` | 确认 | ✅ | T1 |
| 15 | Delete (keep local) | `delete --keep-local` | 确认 | ✅ CFM/⌘K 原子意图、二次确认；真实 SVN 验证调度 deleted 且本地文件保留 | T3 |
| 16 | Delete unversioned | status 复核后删除本地项 | 预览列表 | ✅ 未版本候选预览/勾选；执行前二次 status、WC 边界与版本状态校验；文件/目录真实往返 | T3 |
| 17 | Revert | `status`→勾选→`revert [-R]` | 勾选、单项 Diff | ✅ | T1 |
| 18 | Cleanup | `cleanup` | 刷新壳层/断锁等选项 | ✅ | T1 |
| 19 | Get Lock | `lock -m [--force]` | 注释、steal | ✅ 锁定页+CFM/⌘K；注释与夺锁确认 | T2 |
| 20 | Release Lock | `unlock` | 多选 | ✅ 多选释放；优先本 WC 持有 | T2 |
| 21 | Break lock | 🔷 | 高危确认 | ✅ `unlock --force` + 确认门控 | T2 |
| 22 | Branch/Tag | `copy` 三种源 | HEAD / 特定修订 / WC | ✅ 三源表单；peg 仅剥末尾 `@数字`；CFM/⌘K 可达 | T2 |
| 23 | Switch | `switch [-r] URL` | 未提交警告 | ✅ 可选 revision；未提交变更二次确认并保留目标参数；CFM/⌘K 可达 | T2 |
| 24 | Merge | `merge [--dry-run]` + unified 预览 | 范围/树、Test merge | ✅ 范围/两树、dry-run、Unified Diff、大文本门禁、冲突工作区回跳 | T2 |
| 25 | Merge reintegrate | 🔷 | 确认 | ✅ 现代 SVN complete merge 语义；Merge 向导支持 dry-run/执行/冲突回跳；真实 WC 验证 | T3 |
| 26 | Export | `export` 或 WC 文件复制 | 含未版本、omit externals | ✅ URL/WC 导出、修订、`--ignore-externals`、UI | T2 |
| 27 | Relocate | `switch --relocate` | From/To URL | ✅ From/To 校验、写锁、认证重试、UI | T2 |
| 28 | Create Repository Here | `svnadmin create --fs-type fsfs` | 路径 | ✅ 仓库浏览器/⌘K 入口、目录选择、用户工具链同目录 `svnadmin`、真实 FSFS 仓库验证 | T3 |
| 29 | Add | 递归扫描可添加 | 勾选列表 | ✅ | T1 |
| 30 | Import | `import -m PATH URL` | 说明 | ✅ UTF-8 说明、认证重试、UI | T2 |
| 31 | Blame | `blame` + `log` tip | 修订范围、悬停 | ✅ `-r X:Y`、行悬停 revision 日志、作者/日期/路径摘要 | T2 |
| 32 | Add to Ignore List | `propget/propset svn:ignore` | 文件名/通配 | ✅ | T1 |
| 33 | Create Patch | `diff > patch` | 路径勾选 | ✅ 按选择路径聚合 diff、原子写入 patch、UI | T2 |
| 34 | Apply Patch | TortoiseMerge 级应用 | 冲突处理 | ✅ `svn patch`、缺文件校验、新 `.rej` 路径报告、UI | T2 |
| 35 | Properties | 属性 CRUD + 模板 | svn:/tsvn: 编辑器 | ✅ CRUD、多行值、删除确认、文件/目录模板、CFM/⌘K 路径意图 | T2 |
| 36 | Copy / Move | `copy`/`move` | 目标路径 | ✅ | T1 |
| 37 | Shelve / Unshelve | 官方 shelving | V2/V3 设置、官方列表/Diff/Log/Unshelve/Drop、手工快照迁移 | ✅ | T3 |
| 38 | Change Lists | changelist 分组 | 提交按列表 | ✅ CFM 列/分组、移入/移出、Commit 按列表选择；真实 SVN 往返验证 | T3 |
| 39 | Externals | `svn:externals` | 编辑器、更新行为 | ✅ 现代/旧式语法解析、相对 URL、peg/operative revision、注释保留；属性保存与更新行为对齐；真实目录/文件 external 往返验证 | T3 |
| 40 | Compare revisions / Blame differences | 双侧 blame + `diff -r OLD:NEW` | 双修订 | ✅ Blame 分段模式、双修订/BASE 表单、左右作者/日期/内容、增删改与归属汇总；CFM/⌘K；真实 SVN 往返 | T3 |
| 41 | Save revision / Open / Open with | 取历史文件 | 另存、打开 | ✅ L05/L06 路径右键；`cat URL@rev` 后原子另存或系统默认应用打开 | T2 |
| 42 | Merge revision to… | 从日志拣选合并 | 目标 WC | ✅ `svn merge -c REV`；日志右键确认后合并到当前 WC | T3 |
| 43 | Import in Place | DUG 就地导入 | 向导 | ✅ 导入后临时检出并原子替换目录内容 | T2 |
| 44 | Remove from version control | 导出式去 `.svn` | 确认 | ✅ 路径安全校验，仅删除 `.svn` 元数据并保留工作文件 | T2 |
| 45 | Repair Move / Repair Copy | CFM 内修复 | 配对选择 | ✅ | T1 |
| 46 | Filename case conflict repair | DUG rename 章 | 修复向导：同目录仅大小写改名，临时 SVN 改名中转并失败回滚 | ✅ | T2 |

---

## 4. 对话框级验收（「好用」的真正来源）

### 4.1 Commit（必须）

- [x] 修改项默认勾选（可配置「不自动勾选」）  
- [x] 显示未版本；勾选未版本 → 提交前 `add`  
- [ ] 递归进入未版本目录（可关）  
- [x] 双击/按钮 Diff；单项 Revert  
- [x] 最近日志消息历史（条数可配）  
- [ ] 路径/关键字自动完成（可配超时）  
- [x] Keep locks → `--no-unlock`  
- [ ] Bugtraq / issue 正则高亮与校验（T5）  
- [ ] 客户端 pre-commit 钩子（T5）  
- [ ] 提交后若仍有未提交项可重开对话框（可配）  

### 4.2 Check for Modifications（必须）

- [x] 本地 `status -v`  
- [x] **Check Repository** → `status -u`  
- [x] 颜色：仅本地 / 仅远端 / 双方 / 冲突  
- [x] Repair Move / Repair Copy  
- [x] Changelist 列与分组；列表移入/移出；Commit 按列表选择（含 `ignore-on-commit`）
- [x] 列宽/可见列持久化  
- [ ] 显示未修改 / 忽略项（可配）  
- [ ] 启动时是否自动联系仓库（可配）  

### 4.3 Update（必须）

- [x] 多路径同仓：先统一 revision 再更新（防 mixed-rev）  
- [x] 结束后冲突列表 → 一键 Edit Conflicts  
- [x] Auto-close 策略与完成日志提示（手动/无合并增删/无冲突/无错误，可持久化）

### 4.4 Merge（必须）

- [x] 修订范围合并、两树合并
- [x] Test merge (`--dry-run`)、Unified diff 预览
- [ ] reintegrate（T3）  
- [x] 冲突后进入编辑器；mergeinfo 可观察

### 4.5 Repo Browser（必须）

- [ ] 任意 URL@rev；不可高于 repo root  
- [ ] 预取子目录 / 显示 externals（可关，防弱服务器）  
- [ ] Checkout / Export / Log / Blame  
- [x] 远端：创建文件夹、删除、复制、移动、重命名（高危确认）
- [x] 锁信息列：owner / comment / created；未锁条目不发起逐项查询

### 4.6 Revision Graph（必须，T3）

- [x] trunk/branches/tags glob 路径模式可配（`*`/`?`/`**`，设置持久化）
- [x] 节点颜色/分类与 copy 源色混合；标签/未分类/已删除剪枝；拓扑/时间线切换
- [x] 节点：Log / Checkout / Blame / Diff（远端 URL/revision 原子传递；日志/Diff 认证重试）

### 4.7 Progress / 通用对话框行为（必须）

- [x] Auto-close：手动 / 无合并增删 / 无冲突 / 无错误
- [x] 本地成功操作可自动关闭，错误始终保留
- [ ] Revert 可选进废纸篓（安全网）  

---

## 5. Show Log 右键动作全集（小乌龟「历史」真正深度）

当前 Studio 仅有「列表+详情」雏形；下列**每一项**都是必须能力（入口可在历史详情右键 / ⌘K）。

| L# | 动作 | 说明 | Studio | 波次 |
|----|------|------|--------|------|
| L01 | Compare with working copy | 与 WC 比 | ✅ | T2 |
| L02 | Compare with previous revision | 与前一修订比 | ✅ | T2 |
| L03 | Compare and blame with BASE/previous | Blame 差异 | ✅ 日志路径菜单默认 PREV:REV；仓库 URL@peg 原子注入 Blame 差异页；BASE 可直接取目标基线 | T3 |
| L04 | Show changes as unified diff | 含 Shift 选项（EOL/空白） | ✅ 统一 Diff 面板；EOL/空白进阶仍开 | T2 |
| L05 | Save revision to… | 另存历史文件 | ✅ | T2 |
| L06 | Open / Open with… | 打开历史内容 | ✅ 系统默认打开；Open with… 进阶仍开 | T2 |
| L07 | Blame… | 到该修订 | ✅ 跳转 Blame 并注入路径 | T2 |
| L08 | Browse repository | 打开该 URL@rev | ✅ | T2 |
| L09 | Create branch/tag from revision | 从修订打分支 | ✅ | T2 |
| L10 | Update item to revision | 更新到该修订 | ✅ | T2 |
| L11 | Revert to this revision | 反向合并到该点（WC） | ✅ | T2 |
| L12 | Revert changes from this revision | 只撤销该修订 | ✅ | T2 |
| L13 | Merge revision to… | 合并到另一 WC | ✅ 日志路径菜单、确认门控、`-c REV` 合并、冲突工作区回跳 | T3 |
| L14 | Checkout… / Export… | 从日志检出/导出 | ✅ | T2 |
| L15 | Edit author / log message | 改修订属性（需仓库钩子允许） | ✅ 日志右键/详情与 ⌘K；仅写变化的 `svn:author`/`svn:log`；认证重试、写锁、UTF-8 安全临时文件；hook 拒绝提示与真实 SVN 往返 | T3 |
| L16 | Show revision properties | 修订属性 | ✅ `proplist --revprop -r` 全量展示内置/自定义属性；Unicode XML 解析；日志右键/详情与 ⌘K 原子修订意图 | T3 |
| L17 | Copy to clipboard | 复制日志摘要 | ✅ | T2 |
| L18 | Filter / Statistics / Offline cache | 过滤、统计、离线 | 🟡 作者/说明/路径过滤 ✅；统计/离线 T3 | T2/T3 |
| L19 | Actions 列图标 | M/A/D/R/Moved/Merged 等 | ✅ MADR 汇总；Moved/Merged 图标进阶仍开 | T2 |
| L20 | stop-on-copy、Next 100、Show All | 拉取策略 | ✅ | T2 |

---

## 6. 设置页矩阵（整页也是功能）

| S# | 小乌龟设置页 | 必须等价项 | Studio | 波次 |
|----|--------------|------------|--------|------|
| S01 | General | 语言、检查更新、全局 ignore、last-commit-time、编辑 svn config、externals 本地修改策略 | 弱 | T5 |
| S02 | Context Menu | 主菜单/子菜单提升、needs-lock 时提升 Lock、隐藏未版本路径菜单、排除路径 | ❌ | T4 |
| S03 | Dialogs 1 | 默认日志条数、字体、短日期、双击比修订、Auto-close、Revert→废纸篓、默认 checkout 路径/URL | ❌ | T5 |
| S04 | Dialogs 2 | 递归未版本、自动完成、日志历史条数、自动勾选、提交后重开、CFM 启动联系仓库、Lock 对话框 | ❌ | T5 |
| S05 | Dialogs 3 | Repo 预取、显示 externals、Shelve V2/V3 | ✅ 官方 Shelve V2/V3 分段选择、能力探测与双轨操作；本地手工快照可迁移，安全快照拒绝迁移 | T3/T5 |
| S06 | Colours | 冲突/增/删/合并/改 等颜色 + 暗色 | ❌ | T5 |
| S07 | Revision Graph | 分类 pattern、颜色混合 | ✅ trunk/branches/tags 多 pattern；四类颜色；copy 源色混合开关；SettingsStore 持久化 | T3 |
| S08 | Icon Overlays | Cache Default/Shell/None、仅 Finder、包含/排除驱动器与路径、可选角标种类 | 弱 | T4 |
| S09 | Network | 代理、SSH 客户端等 | 弱 | T5 |
| S10 | External Programs | Diff/Merge/Blame/统一 Diff 查看器、按扩展名 | 弱 | T1/T5 |
| S11 | Saved Data / Hook Scripts | 清认证与日志缓存、客户端钩子 | ❌ | T5 |
| S12 | Bugtraq / Issue tracker | 正则、消息模板 | ❌ | T5 |
| S13 | Log Cache | 日志缓存策略 | ❌ | T3 |

---

## 7. Overlay 全状态（必须）

| 状态 | Studio | 波次 |
|------|--------|------|
| Normal / Modified / Conflicted / Added | 部分 | T4 |
| Deleted / Missing / Replaced | 缺口 | T4 |
| Locked / needs-lock(readonly) | 缺口 | T4 |
| Ignored / Unversioned（可选显示） | 缺口 | T4 |
| Depth shallow / Nested WC / Externals / Switched | 缺口 | T4 |
| 仅 mergeinfo 属性变更 | 缺口 | T4 |
| Status Cache 三模式 + 包含排除路径 | 缺口 | T4 |

---

## 8. 项目属性（tsvn: / bugtraq:）— 小乌龟「项目级」能力

| 属性族 | 用途 | Studio | 波次 |
|--------|------|--------|------|
| `bugtraq:*` | issue 号、URL、消息正则 | ❌ | T5 |
| `tsvn:logminsize` / `logwidthmarker` 等 | 提交说明约束 | ❌ | T5 |
| `tsvn:projectlanguage` | 拼写检查语言 | ❌ | T5 |
| `tsvn:lockmsgminsize` | 锁说明强制 | ❌ | T2/T5 |
| 自动属性（svn config） | 新增文件自动 props | 弱（可编辑 config） | T5 |

---

## 9. 差距量化（v2）

| 类别 | 约数 | 含义 |
|------|------|------|
| 命令 #1–46 | 🟡 ~15 · ❌ ~25+ | 入口或对话框不足 |
| 日志右键 L01–L20 | ❌ 为主 | 历史深度几乎未做 |
| 设置 S01–S13 | ❌/弱 | 设置体系未成型 |
| Overlay 全状态 | 大部分缺口 | Finder 集成未完成 |
| 域 D01–D28 | 无一域可称「对标完成」 | — |

**结论：** 对标小乌龟 = **命令矩阵 + 对话框选项 + 日志动作 + 设置页 + Overlay 策略** 五层全部 ✅；仅「能提交/能看 log」不算完成。

---

## 10. 验收定义（强制）

对任意一行：

1. **入口**：Finder 和/或主窗口右键和/或 ⌘K  
2. **对话框**：§4/§5/§6 对应选项具备（布局可不同）  
3. **结果**：与 CLI Cross-Ref / DUG 行为一致  
4. **证据**：H1 或单测引用  

任一行未 ✅ ⇒ 不得宣称「小乌龟有的都有」。

---

## 11. 与路线图波次对齐

| 波次 | 清掉什么 |
|------|----------|
| T0 | 命令 ID 骨架对齐本表 #/L#/S#；性能门禁 |
| T1 | #2,4,5,8,13–14,17–18,29,32,36,45 + Commit/CFM/Diff 对话框（#3 属 T2） |
| T2 | 检出更新进阶、日志 L 大部、锁、分支合并、导出导入补丁属性、Repo 写 |
| T3 | 修订图、Changelist、Externals、官方 Shelve、reintegrate、日志高级 L |
| T4 | Overlay 全状态 + Cache + 菜单设置 |
| T5 | 设置全页、钩子、Bugtraq、品牌分发 |
| T6 | AI/Git 等差异化（**不计入**小乌龟完成度） |
