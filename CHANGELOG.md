# Changelog

## 2026-07-13

- Summary: Tortoise 完美 Loop T3.1：Diff with URL（#6）
- Affected: DiffWithURLValidationPolicy, DiffViewModel, SvnCommandBuilder/Backend/Service, MacSvnDiffView, MacSvnAppNavigator, SvnCommandCatalog, Tests/*, docs/*
- Impact: 新增 URL+revision 比较表单；留空 revision 使用 HEAD，支持 URL 末尾 peg revision 与 `svn+ssh://user@host`；拒绝 URL 内嵌密码；认证密码仅经 stdin 并支持一次重试；原子导航 intent 可从 CFM/⌘K 预填；嵌入式左右分栏使用两列完整文本并保留大 Diff 回退与请求代次保护；真实 SVN 验证跨 URL 输出方向；全量 710 绿；下一 T3.2

- Summary: Tortoise 完美 Loop T2.15：通过 G2 出门闸门
- Affected: tortoisesvn-feature-inventory, H-tortoise-parity, parity-coverage, perfect-loop/long-loop docs
- Impact: 核验 #41 已由日志 L05/L06 的 `cat URL@rev`、另存和系统打开完整覆盖并升为 ✅；#15/#16 波次与 T3.8 对齐；T2 独占范围、H-T2 与全量 688 测试通过；下一 T3.1

- Summary: Tortoise 完美 Loop T2.14：Progress Auto-close 基础策略（§4.7）
- Affected: ProgressAutoClosePolicy, AppSettings/SettingsStore, MacSvnSettingsView, MacSvnChangesView, Tests/*, docs/*
- Impact: 提供手动/无合并增删/无冲突/无错误四档持久化策略；更新结果按冲突与合并增删判定，本地成功操作可自动收起，错误提示始终保留；下一 T2.15/G2

- Summary: Tortoise 完美 Loop T2.13：Filename case conflict repair（#46）
- Affected: FilenameCaseConflictRepairPolicy, SvnBackend/Cli/Service, WorkingCopyActionsViewModel, MacSvnChangesView, MacSvnAppNavigator, SvnCommandCatalog, Tests/*, docs/*
- Impact: 新增同目录仅大小写改名修复向导；通过唯一临时 SVN 路径中转适配大小写不敏感文件系统，第二步失败会尝试恢复原名；CFM/⌘K 可达，真实 SVN 工作副本提交验证；下一 T2.14

- Summary: Tortoise 完美 Loop T2.12：Repo Browser 远端写、高危确认与锁列（#10、D24）
- Affected: RemoteInfoXMLParser, RepoRemoteWriteConfirmationPolicy, RepoBrowserViewModel, SvnCommandBuilder/Backend/Cli/Service, MacSvnRepoBrowserView, Tests/*, docs/*
- Impact: Repo Browser 支持远端 mkdir/delete/copy/move/rename；删除/移动/重命名由 Core 强制二次确认并展示源/目标；通过单次 `svn info --xml --depth immediates` 展示 owner/comment/created 锁信息；真实 SVN 远端写与锁集成验证；下一 T2.13

- Summary: T2.12 审查修复：确认快照绑定与远端路径 URL 编码
- Affected: RepoBrowserViewModel, MacSvnRepoBrowserView, RepoBrowserViewModelTests
- Impact: 移除 `confirmed` 绕过入口；确认只接受当前 pending operation 的不可变 source/destination/message/auth 快照；`#`、`?`、中文等远端条目路径通过 URL 组件编码后再访问；全量 673 测试绿

- Summary: Tortoise 完美 Loop T2.11：Properties 模板/编辑与 Blame 修订范围/悬停日志（#35,#31）
- Affected: PropertyViewModel, BlameViewModel, SvnCommandBuilder/Backend/Cli/Service, MacSvnPropertiesView, MacSvnBlameView, MacSvnAppNavigator, SvnCommandCatalog, Tests/*, docs/*
- Impact: 属性 CRUD/多行编辑/文件目录模板与 CFM/⌘K 路径意图齐全；Blame 支持 `-r X:Y` 和行悬停 revision 日志；Blame differences 仍属 T3.9；下一 T2.12

- Summary: Tortoise 完美 Loop T2.10：Create Patch / Apply Patch（#33,#34）
- Affected: PatchPathPolicy, PatchViewModel, SvnService, MacSvnShelveView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: 按勾选路径生成单一 patch，应用 patch 后报告新 `.rej` 冲突文件；搁置页与命令面板可达；下一 T2.11

- Summary: Tortoise 完美 Loop T2.9：Export / Import / Import in Place / Relocate / Remove from VC（#26,#27,#30,#43,#44）
- Affected: SvnCommandBuilder/Backend/Cli/Service, ImportExportViewModel, MacSvnRepoBrowserView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: 支持 `--ignore-externals`、UTF-8 导入说明、From/To relocate、就地导入后可用工作副本、安全移除 `.svn`；下一 T2.10

- Summary: Tortoise 完美 Loop T2.8：Branch/Tag 三种 copy 源、Switch 可选 revision/未提交确认、Merge 范围/两树/dry-run/Unified Diff/冲突回跳（#22–24）
- Affected: BranchCopyViewModel, BranchSwitchViewModel, MergeWizardViewModel, SvnCommandBuilder/Backend/Cli/Service, MacSvnBranchesView, MacSvnMergeWizardView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: inventory #22–24、D19/D20 ✅；Merge reintegrate 仍属 T3.6；下一 T2.9

## 2026-07-11

- Summary: Cursor→Codex 交接：新增 Tortoise 完美对标长程 Loop 说明书；暂停于 T2.7 完成后、T2.8 未开工
- Affected: docs/superpowers/plans/2026-07-11-codex-tortoise-parity-long-loop.md, CHANGELOG.md, perfect-loop 指针
- Impact: Codex 可按文档从 T2.8 续跑至 PERFECT；覆盖率基线 45/114

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.7：Get Lock / Release Lock / Break lock（#19–#21）— 确认门控、CFM/⌘K 深链、锁定页打磨
- Affected: LockActionPolicy, LockViewModel, MacSvnLocksView, MacSvnAppNavigator, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #19–#21、D21 ✅；needs-lock 提升仍属 T4；下一 T2.8

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.6：Edit Conflicts + Resolved（#11,#12）— CFM 入口、冲突工作区类型过滤/勾选批量 Resolved、树冲突排除
- Affected: ConflictResolveBatchPolicy, ConflictListViewModel, ConflictService, MacSvnConflictWorkspaceView, MacSvnChangesView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: inventory #11/#12、D08 ✅；下一 T2.7 Lock/Unlock/Break lock

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.5：Show Log 复制修订摘要到剪贴板（L17）
- Affected: LogClipboardSummary, MacSvnLogView, Tests/*, docs/*
- Impact: inventory L17 ✅；L15–L16 仍属 T3.10；下一 T2.6

## 2026-07-10

- Summary: T2.4 审计修复：peg URL 仅剥离末尾 `@rev`；L11 要求 HEAD>目标；L10 更新增加确认
- Affected: LogContextActionPolicy, MacSvnLogView, Tests/*, CHANGELOG.md
- Impact: 修复 svn+ssh user@host 误截断与 HEAD==目标时错误合并

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.4：Show Log 右键 L09–L12、L14（从修订建分支/标签、更新到修订、还原到/撤销修订、检出/导出）
- Affected: LogContextActionPolicy, MacSvnLogView, SvnService.repositoryHeadRevision, Tests/*, docs/*
- Impact: inventory L09–L12、L14 ✅；L13 仍属 T3；下一 T2.5（L17）

## 2026-07-10

- Summary: T2.3 审计修复：历史 Diff 改用原子 `pendingLogDiff`；SavePanel 回主线程；CFM 切文件重置修订范围；路径解析失败提示更明确
- Affected: MacSvnAppNavigator, MacSvnDiffView, MacSvnWorkingCopyWorkspaceView, MacSvnLogView, MacSvnRepoBrowserView, CHANGELOG.md
- Impact: 消除历史→嵌入 Diff 竞态与 SavePanel 线程风险

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.3：Show Log 右键 L01/L02/L04–L08（与 WC/上一修订比较、统一 Diff、另存/打开、Blame、Browse）；L03 仍属 T3
- Affected: LogContextActionPolicy, MacSvnLogView, MacSvnDiffView, MacSvnBlameView, MacSvnRepoBrowserView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: inventory L01–L08(除L03) ✅；下一 T2.4（L09–L12/L14）

## 2026-07-10

- Summary: T2.2 审计修复：LogViewModel 加载世代防重入；刷新校验选中修订；路径过滤无命中提示；嵌入 Diff 修订后到时重载
- Affected: LogViewModel.swift, MacSvnLogView.swift, MacSvnDiffView.swift, CHANGELOG.md
- Impact: 消除 stop-on-copy 并发错乱与历史→Diff 常显示 BASE 的竞态

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.2：Show Log 作者/说明/路径过滤、`--stop-on-copy`、Next / Show All、Actions（MADR）列
- Affected: LogActionsSummary, LogFilterPolicy, LogViewModel, SvnCommandBuilder/Backend/Cli/Service, MacSvnLogView, Tests/*, docs/*
- Impact: inventory #7 ✅；L18 过滤 ✅（统计/离线 T3）；L19–L20 ✅；下一 T2.3 日志右键

## 2026-07-10

- Summary: Tortoise 完美 Loop T2.1：Checkout / Update to revision 支持 `-r`、`--depth`/`--set-depth`、`--ignore-externals`；Repo Browser 与 CFM 对话框接线
- Affected: SvnCommandBuilder/Backend/Cli/Service, CheckoutViewModel, WorkingCopyActionsViewModel, MacSvnRepoBrowserView, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #1,#3 ✅；pristines 选项仍开

## 2026-07-10

- Summary: Tortoise 完美 Loop **闸门 G1（T1.12）**：确认 T1 命令 #2,4,5,8,13–14,17–18,29,32,36,45 均为 ✅；更新 domain D06/D07/D10/D14–D16；H-tortoise T1 全勾；澄清 #3 属 T2
- Affected: docs/superpowers/specs/*, docs/acceptance/*, docs/superpowers/plans/*, CHANGELOG.md
- Impact: **G1 通过**，进入 Wave T2；§4.1 进阶项 / global-ignores / Finder 拖拽仍开

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.11：CFM 右键改为 `SvnCommandCatalog.dailyCFMCommands`；⌘K 可搜索并分发同一日常命令子集
- Affected: SvnCommandCatalog.swift, CommandPaletteSearchEngine.swift, MacSvnCommandPaletteView, MacSvnChangesView, Tests/*, docs/*
- Impact: 右键与 ⌘K 同源；下一闸门 G1（T1.12）

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.10：Copy/Move 向导——目标相对路径校验（绝对/同路径/跳出 WC/冲突）+ `svn copy`/`svn move` + CFM 对话框
- Affected: CopyMoveValidationPolicy.swift, WorkingCopyActionsViewModel, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #36 ✅；Finder 拖拽引导仍开

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.9：Ignore 对话框——按文件名 / 按扩展名通配写入父目录 `svn:ignore`（去重合并）
- Affected: IgnorePatternPolicy.swift, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #32 ✅；global-ignores 仍属设置 S01/T5

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.8：Rename 同目录改名——新名校验（空/同名/分隔符/目标冲突）+ `svn rename` + CFM 对话框/右键
- Affected: RenameValidationPolicy.swift, SvnCommandBuilder/Backend/Cli/Service, WorkingCopyActionsViewModel, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #13 ✅；大小写冲突修复仍属 #46；跨目录移动属 #36

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.7：Add 未版本勾选列表、Delete 确认、Revert 递归+单项 Diff、Cleanup 断锁/pristine/externals；集成测对齐 status -v「干净」语义
- Affected: SvnCleanupOptions.swift, SvnCommandBuilder/Backend/Cli/Service, WorkingCopyActionsViewModel, MacSvnChangesView, IntegrationTests, Tests/*, docs/*
- Impact: inventory #14,#17,#18,#29 ✅；删除未版本（#16）/壳层刷新仍开

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.6：Diff 显式对比 BASE、双文件 `--old/--new`、外置查看器入口接线（设置中的 ExternalDiffTool）
- Affected: SvnCommandBuilder/Backend/Cli/Service, DiffViewModel, MacSvnDiffView, Tests/*, docs/*
- Impact: inventory #5 ✅；EOL/空白过滤仍为进阶项

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.5：多路径 Update 先 `info -r HEAD` 钉住统一 revision 再 update；CFM 多选走选中路径更新
- Affected: UpdateRevisionPolicy.swift, SvnCommandBuilder/Backend/Cli, SvnService, MacSvnChangesView, Tests/*, docs/*
- Impact: inventory #2 ✅；防 mixed-rev；Auto-close 仍待设置页

## 2026-07-10

- Summary: fix(T1.4)：Commit Guard 移到 add 之前，避免取消警告残留已 add 项；右键还原失败不再强制 reload 掩盖错误
- Affected: SvnService.swift, MacSvnCommitView.swift
- Impact: 警告/阻断路径保持 WC 干净；还原失败可见

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.4：Commit 对话框级——未版本进候选且勾选后提交前 add；Keep locks（`--no-unlock`）；单项 Diff/Revert；说明历史沿用
- Affected: CommitViewModel, CommitSelectionPolicy, SvnCommandBuilder/Backend/Cli/Service, MacSvnCommitView, Tests/*, docs/*
- Impact: inventory #4 ✅；§4.1 递归未版本目录/自动完成/重开对话框仍开

## 2026-07-10

- Summary: fix(T1.3)：Repair Copy 失败路径禁止删除 aside；写操作失败也刷新 CFM；成功刷新保留 Check Repository；D09 ✅
- Affected: SvnCliBackend.swift, MacSvnChangesView.swift, inventory D09, parity-coverage.json
- Impact: 避免用户未版本文件被误删；失败后列表与磁盘一致；远端高亮不因 Repair 回退

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.3：CFM Repair Move/Copy（配对校验 + WC 内 `svn move/copy`；目标已存在时先挪开/回填 missing 源）
- Affected: RepairMoveCopyPairing.swift, SvnCommandBuilder/Backend/Cli/Service, WorkingCopyActionsViewModel, MacSvnChangesView, Tests/*（含集成）, docs/*
- Impact: inventory #45 ✅；#8 CFM 核心（本地/远端/颜色/Repair）齐 → ✅

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.2：CFM Check Repository（`status -u -v`）+ 本地/远端/双方/冲突行高亮；解析 `repos-status`；远端状态列
- Affected: StatusXMLParser, SvnCommandBuilder, SvnBackend/Cli/Service, ChangesViewModel, MacSvnChangesView, CFMChangeHighlight, FileStatus.remoteItemStatus, Tests/*, docs/*
- Impact: #8 远端对照与颜色齐；Repair Move/Copy 仍待 T1.3（#8 保持 🟡）

## 2026-07-10

- Summary: Tortoise 完美 Loop T1.1：CFM 本地 status 对齐 `-v`；列配置（路径/状态/修订/树冲突）可切换并写入 AppSettings；刷新时间戳；变更列表按列渲染
- Affected: CFMColumnConfiguration.swift, ChangesViewModel.swift, MacSvnChangesView.swift, SvnCommandBuilder.swift, AppSettings, Tests/*, docs/acceptance/H-tortoise-parity.md, inventory #8
- Impact: 检查修改本地闭环可用；远端 Check Repository / Repair 仍待 T1.2–T1.3（#8 保持 🟡）

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.7 / **闸门 G0 通过**：全量 `swift test` 529 绿；parity-coverage 脚本与 fixture 测绿；T0 波次收口，进入 T1
- Affected: docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md, docs/acceptance/H-tortoise-parity.md, docs/acceptance/parity-coverage.json, docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md
- Impact: 骨架与门禁就绪；下一枪 T1.1 CFM 本地 status

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.6：新增 `docs/acceptance/H-tortoise-parity.md`（T0–T5/GP 分节空勾清单）
- Affected: docs/acceptance/H-tortoise-parity.md, docs/README.md, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: 后续各 Wave 出门以本清单 + inventory ✅ 双轨验收

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.5：新增 `scripts/parity-coverage.py` 解析 inventory 状态列，输出 `docs/acceptance/parity-coverage.json`（✅/总数）；含 fixture 单测
- Affected: scripts/parity-coverage.py, scripts/tests/test_parity_coverage.py, docs/acceptance/parity-coverage.json, docs/README.md, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: 当前基线 0/114（0%）；后续每波更新 inventory 后重跑脚本即可跟踪 PERFECT

## 2026-07-10

- Summary: 修复 Bugbot 指出的工作区接线问题：种子路径同步选中、提交说明预填、嵌入 Commit 去 HSplitView、CFM 不再误写 Diff 路径、嵌入 Diff 隐藏无效模式切换、pendingDiffPath 由工作区独占消费
- Affected: MacSvnChangesView/CommitView/DiffView/WorkingCopyWorkspaceView/FeatureHostView, MacSvnAppNavigator, Tests/MacSvnAppTests/*
- Impact: 深链/⌘K/CLI 与同屏 Diff/提交预填一致；降低 AttributeGraph 风险

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.4：`ProcessRunner` 支持 Task 取消（SIGTERM→5s SIGKILL→`SvnError.cancelled`）；新增 `SvnCancellableTask` 包装
- Affected: Sources/MacSvnCore/Process/ProcessRunner.swift, Tests/MacSvnCoreTests/ProcessRunnerTests.swift, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: 长耗时 svn 可被 UI 取消；对齐详设取消传播；清单：异常映射通过、无吞异常

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.3：`MacSvnAppNavigator.perform(command:paths:options:)` 统一入口；未接线命令返回 `unimplemented` 并提示「未实现」
- Affected: Sources/MacSvnApp/App/MacSvnAppNavigator.swift, Sources/MacSvnCore/Catalog/SvnCommandOptions.swift, Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: Finder/⌘K/后续对话框可共用同一命令分发；T0 stub 显式可追踪

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.2：新增 `SvnCommandCatalog`（#1–46 + L01–L20、扩展菜单标记、displayName/keywords、按 ID/inventoryKey 查询）及单测
- Affected: Sources/MacSvnCore/Catalog/SvnCommandCatalog.swift, Tests/MacSvnCoreTests/SvnCommandCatalogTests.swift, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: 命令矩阵可枚举，为 T0.3 Navigator 统一入口与覆盖率报表奠基

## 2026-07-10

- Summary: Tortoise 完美 Loop T0.1：落地 `DiffPerformanceLimits` 性能门禁；Diff/变更工作区走统一阈值；新增 Core/App 回归测与 `docs/acceptance/performance-guards.md`
- Affected: Sources/MacSvnCore/Models/DiffPerformanceLimits.swift, DiffViewModel.swift, MacSvnDiffView.swift, Tests/**/DiffPerformance*, WorkingCopyWorkspacePerformanceGuardTests.swift, docs/acceptance/performance-guards.md, docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md
- Impact: 防 AttributeGraph 卡死有可重复验证；清单核对：异常/空值 N/A（纯阈值）；测试通过；无 SQL

## 2026-07-10

- Summary: 新增 Tortoise 全量对标「完美 Loop」规划：T0–T5 原子 backlog、G0–G5/PERFECT 闸门、one-shot 唤醒协议、停止条件=inventory 100%+无 stub+全测+H1
- Affected: docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md, docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md, docs/README.md
- Impact: 说「开始 loop」即从 T0.1 在 `feat/tortoise-parity-perfect-loop` 上执行，直到 PERFECT 才停

## 2026-07-10

- Summary: 深入挖掘 TortoiseSVN 能力并升为验收基线 v2：DUG 28 域、命令 #1–46、日志右键 L01–L20、设置 S01–S13、Overlay 全状态；路线图改为 T0–T6 全量对标（小乌龟有的必须有）
- Affected: docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md, docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md, docs/superpowers/specs/2026-07-10-long-term-product-design.md, docs/README.md
- Impact: 后续交付以 inventory 状态列 ✅ 为完成标准；默认开工 T0→T1；差异化 AI/Git 不计入小乌龟完成度

## 2026-07-10

- Summary: 新增长期迭代路线图（L0–L8）与长期产品开发详设（TortoiseSVN 映射、性能规范、模块设计）
- Affected: docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md, docs/superpowers/specs/2026-07-10-long-term-product-design.md, docs/README.md
- Impact: 已被同日 T0–T6 / inventory v2 覆盖；保留条目作历史痕迹

## 2026-07-10

- Summary: 修复变更工作区卡死（嵌套 SplitView + 逐行 Diff 导致 AttributeGraph 100% CPU）；历史页改为左列表右详情可点开查看；Diff 嵌入模式改单块文本渲染
- Affected: MacSvnWorkingCopyWorkspaceView.swift, MacSvnDiffView.swift, DiffViewModel.swift, MacSvnLogView.swift
- Impact: 应用应可正常响应；历史可点选修订看说明与变更路径

## 2026-07-10

- Summary: UI/UX Working-Copy Centric 重构（U1–U4）：侧栏改为 WC 列表；变更+Diff+提交同屏；Mode 顶栏收纳高级/工具；⌘K 全覆盖；冲突「返回变更」；IA 规格与文档收口
- Affected: Sources/MacSvnApp/App/MacSvnRootView.swift, MacSvnWorkspaceMode.swift, MacSvnAppNavigator.swift, Features/MacSvnWorkingCopy*.swift, MacSvnChangesView/CommitView/DiffView/CommandPalette/Conflict/Log, Tests/**, docs/superpowers/specs/2026-07-10-ui-ux-ia-design.md, docs/superpowers/plans/2026-07-10-ui-ux-ia-refactor.md, README.md, docs/**
- Impact: 日常提交无需在 5 个平级页间跳转；符合 FR-WC-02；请 `swift run MacSvnDesktopApp` 或重打包 `dist/SVNStudio.app` 体验

## 2026-07-10

- Summary: 产品彻底换皮为 **SVN Studio**：显示名 / Bundle ID `dev.yclenove.svnstudio` / `svnstudio://` / Application Support `SVNStudio` / Keychain 前缀；包装产物 `SVNStudio.app`；文档与脚本同步
- Affected: Sources/MacSvnCore/ProductBranding.swift, Packaging/SVNStudio/**, MacSVN.xcodeproj, scripts/**, README.md, docs/packaging/**, docs/extensions/**, docs/acceptance/H1-manual-checklist.md, Tests/**
- Impact: 与旧商业 macSvn / 旧 MacSVN 品牌隔离；旧 `~/Library/Application Support/MacSVN` 与 Keychain **不自动迁移**，需重新配置 AI Provider；请打开 `dist/SVNStudio.app`

## 2026-07-10

- Summary: 修复启动后通知授权回调在后台队列触碰 MainActor 导致的 SIGILL 崩溃（`requestNotificationPermission` 改为 `nonisolated`）
- Affected: Sources/MacSvnApp/Features/MacSvnMenuBarController.swift
- Impact: 点击「添加工作副本」等路径不再因通知权限回调崩溃；请重新打开 `dist/SVNStudio.app`

## 2026-07-10

- Summary: SRS 缺口 Loop V5：全量 `swift test` 502 通过；Xcode/SPM `.app` 与 Finder Sync/Quick Look 冒烟通过；README 功能矩阵改为可验收；合入 `main`（因 main 已有早期 PR merge，采用 merge 而非纯 FF）
- Affected: README.md, docs/README.md, docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md
- Impact: SRS 缺口 Loop 全部 `[x]`；长程交付收口

## 2026-07-10

- Summary: SRS 缺口 Loop V4：新增签名/公证流程文档与 `sign-and-notarize.sh` / `verify-signing-prereqs.sh`（支持 DRY_RUN）；H1 验收清单补充干净机冒烟步骤
- Affected: docs/packaging/signing-and-notarization.md, docs/packaging/README.md, docs/acceptance/H1-manual-checklist.md, scripts/sign-and-notarize.sh, scripts/verify-signing-prereqs.sh
- Impact: NFR-10 / P4 分发路径可按文档执行；下一未勾项 V5 全量测试合 main

## 2026-07-10

- Summary: SRS 缺口 Loop V3：MacSVN.xcodeproj 增加 Quick Look 扩展并嵌入 PlugIns；`QuickLookPreviewTextBuilder` 生成 Diff/冲突/二进制预览文案；verify-quicklook-appex 通过
- Affected: Packaging/QuickLook/**, MacSVN.xcodeproj, Sources/MacSvnCore/Services/QuickLookPreviewTextBuilder.swift, Tests/**, scripts/verify-quicklook-appex.sh, docs/extensions/QuickLook/**
- Impact: FR-EX-08 可安装形态可验收；下一未勾项 V4 签名/公证

## 2026-07-10

- Summary: SRS 缺口 Loop V2：MacSVN.xcodeproj 增加 Finder Sync 扩展并嵌入 PlugIns；主应用导出 WC 根目录；角标+右键 macsvn 深链；verify-finder-sync-appex 通过
- Affected: Packaging/FinderSync/**, MacSVN.xcodeproj, Sources/MacSvnCore/Services/FinderSync*.swift, MacSvnWorkspaceController.swift, MacSvnAppSession.swift, scripts/verify-finder-sync-appex.sh, docs/extensions/FinderSync/**
- Impact: FR-EX-05 可安装形态可验收；下一未勾项 V3 Quick Look `.appex`

## 2026-07-10

- Summary: SRS 缺口 Loop V1：新增 MacSVN.xcodeproj 包装工程（嵌入本地 SwiftPM）与 `scripts/build-macos-app.sh`；两条路径均可产出并通过 `verify-macos-app.sh`
- Affected: MacSVN.xcodeproj/**, Packaging/MacSVN/Info.plist, scripts/build-macos-app.sh, scripts/verify-macos-app.sh, docs/packaging/README.md, README.md, docs/extensions/FinderSync/README.md
- Impact: 可构建 `MacSVN.app`；下一未勾项 V2 Finder Sync `.appex`

## 2026-07-10

- Summary: SRS 缺口 Loop U8：团队活动页按日提交改为日历热力图（12 周）；窗口锚定今天、强度按窗内峰值、周标签跟随 firstWeekday
- Affected: Sources/MacSvnCore/Services/TeamActivityHeatmapBuilder.swift, Sources/MacSvnApp/Features/MacSvnTeamActivityView+Heatmap.swift, MacSvnTeamActivityView.swift, Tests/MacSvnCoreTests/TeamActivityHeatmapBuilderTests.swift
- Impact: FR-EX-06 可验收；下一未勾项 Wave V（Xcode .app / 扩展）

## 2026-07-10

- Summary: SRS 缺口 Loop U7：菜单栏接入 FSEvents 本地变更监视，debounce 后近实时刷新；测试可注入 Fake watcher 并关闭通知权限
- Affected: Sources/MacSvnCore/Services/FSEventsWorkingCopyWatcher.swift, Sources/MacSvnApp/Features/MacSvnMenuBarController.swift, Tests/MacSvnAppTests/MacSvnMenuBarControllerTests.swift
- Impact: FR-EX-03 可验收；下一未勾项 U8 团队活动按日提交热力图

## 2026-07-10

- Summary: SRS 缺口 Loop U6：⌘K 无结构化命中时 handoff 到 AI Chat，并自动带上原 query 发送
- Affected: Sources/MacSvnApp/App/MacSvnAppNavigator.swift, Features/MacSvnCommandPaletteView.swift, MacSvnAIAssistantView.swift, MacSvnFeatureHostView.swift, Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift
- Impact: FR-EX-04 可验收；下一未勾项 U7 菜单栏 FSEvents 近实时刷新

## 2026-07-10

- Summary: SRS 缺口 Loop U5：AI Chat 确认门通过后真实执行低危/高危写工具（update/add/cleanup/commit/revert/merge/switch/delete/copy）并审计
- Affected: Sources/MacSvnCore/Services/AISVNToolRegistry.swift, ViewModels/AIAssistantChatViewModel.swift, Tests/MacSvnCoreTests/AISVNToolRegistryTests.swift, AIAssistantChatViewModelTests.swift, AIToolAuditStoreTests.swift
- Impact: FR-AI-04 / NFR-13 可验收；下一未勾项 U6 ⌘K 无匹配转 AI Chat

## 2026-07-10

- Summary: SRS 缺口 Loop U4：Blame 页接入行选区 AI 演化解释（摘要 + 关键 revision 变更）
- Affected: Sources/MacSvnCore/ViewModels/AIBlameEvolutionViewModel.swift, Sources/MacSvnApp/Features/MacSvnBlameView.swift, MacSvnAppSession.swift, Tests/MacSvnCoreTests/AIBlameEvolutionViewModelTests.swift
- Impact: FR-AI-06 可验收；下一未勾项 U5 AI Chat 真实写工具执行

## 2026-07-10

- Summary: SRS 缺口 Loop U3：新增 AI Release Notes 页与侧边栏路由；日志页可带入过滤结果；one-shot 唤醒已验证可续跑
- Affected: Sources/MacSvnCore/ViewModels/AIReleaseNotesViewModel.swift, Sources/MacSvnApp/Features/MacSvnReleaseNotesView.swift, MacSvnAppRoute.swift, MacSvnAppSession.swift, MacSvnLogView.swift, Tests/**
- Impact: FR-AI-05 可验收；下一未勾项 U4 Blame 演化解释

## 2026-07-10

- Summary: 修复长程 Loop「续不上」根因：废弃无限 while 心跳，改为每轮结束 one-shot sleep+WAKE 并重新挂 notify；协议写入 SRS backlog
- Affected: docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md
- Impact: 终端刷 WAKE 但代理空闲的问题有明确修复路径；下一功能项仍为 U3

## 2026-07-10

- Summary: SRS 缺口 Loop U2：历史迁移后展示 revision 对账报告；不一致时阻断进入同步；源分析保留 `sourceRevisions` 供对账
- Affected: Sources/MacSvnCore/Models/GitMigrationModels.swift, Services/GitMigrationSourceAnalyzer.swift, Sources/MacSvnApp/Features/MacSvnGitMigrationView.swift, Tests/MacSvnCoreTests/GitMigrationSourceAnalyzerTests.swift
- Impact: FR-GM-04 / NFR-14 可验收；下一未勾项 U3 AI Release Notes

## 2026-07-10

- Summary: SRS 缺口 Loop U1：Git 迁移 Authors 页接入 AI 批量推断（邮箱域名规则）与「AI 待复核」标记；编辑/确认后清除待复核
- Affected: Sources/MacSvnCore/Services/AIAuthorMappingInferrer.swift, ViewModels/GitMigrationAuthorMappingViewModel.swift, Sources/MacSvnApp/Features/MacSvnGitMigrationView.swift, MacSvnAppSession.swift, Tests/**
- Impact: FR-GM-03 AI 路径可验收；下一未勾项 U2 revision 对账报告

## 2026-07-10

- Summary: SRS 缺口 Loop 续跑 T4–T6：仓库浏览器远端写（mkdir/删/复制/移动+提交说明）、分支页 `svn:mergeinfo`、属性冲突双方对比与 Mine/Theirs resolve；心跳仍在但会话空闲未续跑，已人工续上
- Affected: Sources/MacSvnApp/Features/MacSvnRepoBrowserView.swift, MacSvnBranchesView.swift, MacSvnConflictWorkspaceView.swift, Sources/MacSvnCore/ViewModels/PropertyConflictViewModel.swift, Tests/MacSvnCoreTests/PropertyConflictViewModelTests.swift
- Impact: Wave T 全部勾完；下一未勾项为 U1（Git 迁移 authors AI）

## 2026-07-10

- Summary: SRS 缺口 Loop 续跑：S7 认证失败弹窗（`--password-from-stdin`）+ T2 变更页「忽略选中」写 `svn:ignore`；修复心跳进程中断后以可监听方式重启
- Affected: Sources/MacSvnApp/App/MacSvnInteractiveCredentialProvider.swift, MacSvnAppSession.swift, MacSvnChangesView.swift, Tests/MacSvnCoreTests/AuthArgumentsPasswordFromStdinTests.swift
- Impact: 下一未勾项为 T4 远端写操作

## 2026-07-10

- Summary: 启动 SRS 缺口 Loop：接入火山方舟 Coding 预设与本机 Keychain 注入脚本；完成 R1–R3、S1–S5/S8、T3（树/平铺、Update→冲突跳转、日志过滤与动作、双 revision Diff、左右分栏 Diff、设置分支布局/外部 Diff）
- Affected: Sources/MacSvnApp/**, scripts/seed-volcengine-ark.sh, docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md, docs/acceptance/H1-run-2026-07-10.md, README.md
- Impact: 工作分支 `feat/srs-gap-full-delivery`；API Key 不入库；下一波 S6/S7 与 Wave T/U

## 2026-07-10

- Summary: 梳理 SRS 相对当前交付的缺口，新增第二轮长程 Loop 文档（Wave R–V：验收、P1/P2 体验、仓库/冲突补齐、AI/迁移补齐、扩展与发布）
- Affected: docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md, docs/README.md
- Impact: 明确「主路径接线完成 ≠ SRS 全量完成」；后续 loop 按该文档第一个未勾项推进

## 2026-07-10

- Summary: 长程 Loop 收口 H3：全量 `swift test` 472 通过；backlog Wave A–H 全部勾选；README 含合入 `main` 说明；2 分钟心跳 loop 可停止
- Affected: docs/superpowers/plans/2026-07-10-long-loop-backlog.md, CHANGELOG.md, README.md
- Impact: `feat/long-loop-full-delivery` 具备快进合并 `main` 条件（建议先抽检 H1 清单）

## 2026-07-10

- Summary: 长程 Loop 完成 Wave G + H1/H2：AI Provider/Chat/提交与冲突 AI、⌘K、团队动态；Finder Sync/Quick Look 扩展契约与骨架；验收清单与 README 运行说明/功能矩阵
- Affected: Sources/MacSvnApp/**, Sources/MacSvnCore/ViewModels/AIAssistantChatViewModel.swift, Sources/MacSvnCore/Models/SvnModels.swift, docs/extensions/**, docs/acceptance/H1-manual-checklist.md, README.md
- Impact: backlog 仅剩 H3（全量测试与合 main 说明）；扩展需 Xcode 包装工程安装 .appex

## 2026-07-10

- Summary: 长程 Loop 完成 Wave F：Git 迁移五步向导 UI、MenuBarExtra 状态角标与远端提交通知、`macsvn://` 深链与 CLI 伴生入口（`MacSvnAppNavigator`）
- Affected: Sources/MacSvnApp/**, Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift, Tests/MacSvnAppTests/MacSvnAppNavigatorTests.swift, docs/superpowers/plans/2026-07-10-long-loop-backlog.md
- Impact: 自动化分区仅剩团队动态/AI 助手占位；下一波 G（AI + 生态扩展）

## 2026-07-10

- Summary: 长程 Loop 完成 Wave A–E（P1–P4 UI 接线）：日常流、仓库/分支、冲突三路合并、Blame/属性/锁定/搁置、提交守护硬阻断设置；8 分钟心跳 loop 已武装，下一波为 F（Git 迁移/菜单栏/深链）
- Affected: Sources/MacSvnApp/**, Sources/MacSvnCore/Models/SvnModels.swift, docs/superpowers/plans/2026-07-10-long-loop-backlog.md
- Impact: 侧边栏除 Git 迁移/团队/AI 外均已接真实页；剩余 F/G/H

## 2026-07-10

- Summary: 将 `codex/p1-core-scaffold` 快进合并进 `main` 并推送远程；全量测试 464 通过；`main` 现为可继续开发的基线（含 MacSvnCore P1–P6 核心、SwiftUI App 壳）
- Affected: 分支合并（无新增业务代码）；远程 `main` / `codex/p1-core-scaffold`
- Impact: 后续应从最新 `main` 新开功能分支；旧 scaffold 分支仅作历史备份

## 2026-07-09（创新功能规划）

- Summary: 新增创新功能设计文档（06-innovative-features.md）并将 SRS 升级至 v1.1——一键迁移 Git（FR-GM-01~05，git-svn 五步向导 + 过渡期增量同步）、AI 智能助手（FR-AI-00~06，多 Provider 配置、AI 提交说明/评审/冲突辅助、自然语言操作 SVN 含三级工具分权与审计）、生态效率八项（FR-EX-01~08，提交守护/本地搁置/菜单栏/命令面板/Finder/团队视图/URL Scheme/QuickLook）；新增 NFR-11~14（AI 隐私、故障隔离、AI 写操作确认门、迁移幂等）；路线图扩展 P5/P6 阶段
- Affected: docs/06-innovative-features.md, docs/01-requirements.md, docs/README.md, README.md
- Impact: 原不做范围中「Git-SVN 迁移向导」升级为 P5 一级功能；创新模块与核心客户端故障隔离，不影响 P1–P4 开发计划

## 2026-07-09

- Summary: 创建 GitHub 远程仓库（github.com/yclenove/mac-svn-desktop）并推送；完成完整文档体系——需求规格说明书（SRS）、需求分析报告、概要设计（HLD）、详细设计（DLD）、测试计划，新增 docs 索引
- Affected: docs/01-requirements.md, docs/02-requirements-analysis.md, docs/03-high-level-design.md, docs/04-detailed-design.md, docs/05-test-plan.md, docs/README.md, README.md
- Impact: 需求编号（FR/NFR）与 P1–P4 阶段建立追踪关系；详设锁定 SvnBackend 协议、MergeEngine 算法与解析器规格，可直接进入 P1 开发；测试计划含 diff3 对拍与集成测试基础设施设计

## 2026-07-08

- Summary: 锁定产品决策并定稿设计规格——C 档对标商业客户端、内置三路合并 UI、仓库浏览器必备；修正技术选型错误（SVNKit 为纯 Java 库不适用 Swift，改为 svn CLI 混合架构 + SvnBackend 协议预留 libsvn）；路线图调整为 P1 基础 WC → P2 仓库浏览器/分支 → P3 内置合并 → P4 商业对标
- Affected: README.md, docs/specs/2026-07-08-mac-svn-desktop-design.md, CHANGELOG.md
- Impact: 规格进入待审查状态；GitHub 远程仓库因 gh token 失效尚未创建，待用户重新登录后推送

## 2026-07-08

- Summary: 初始化 Mac SVN Desktop 项目规划与产品设计规格草案
- Affected: README.md, docs/specs/2026-07-08-mac-svn-desktop-design.md, LICENSE, .gitignore
- Impact: 建立 GitHub 仓库前的本地骨架；技术选型倾向 SwiftUI + svn CLI；待用户确认需求后进入实现计划
