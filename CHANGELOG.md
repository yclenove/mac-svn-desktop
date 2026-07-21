# Changelog

## 2026-07-22

- Summary: 工程收口 RC：合入 main 准备与发布说明
- Affected: docs/superpowers/specs/2026-07-22-release-closeout-design.md, docs/superpowers/plans/2026-07-22-release-closeout.md, docs/acceptance/release-notes-rc-2026-07-22.md, docs/acceptance/release-closeout-2026-07-22.md, docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md, README.md, docs/README.md, CHANGELOG.md
- Impact: 将 `main` 通知授权 MainActor 修复合并入 `feat/tortoise-parity-perfect-loop`（behind 0）；交付产品级发布说明与 residual 单一矩阵；长程 roadmap 标注历史归档（勾选过时，以 inventory 114/114 为准）；不改 inventory/H-tortoise；不实现公证/真 a11y；不重启 Perfect Loop。全量 1150/1150 绿（真实 SVN 49/49），parity 114/114，build/verify/smoke 与 git diff --check 通过。门禁明细见 docs/acceptance/release-closeout-2026-07-22.md

## 2026-07-21

- Summary: 人本专业工具面（ST）：完成 Blame / AI 助手 / Git 迁移 / Release Notes 统一
- Affected: MacSvnSpecializedToolsPresentation, MacSvnBlameView, MacSvnAIAssistantView, MacSvnGitMigrationView, MacSvnReleaseNotesView, HumanCenteredSpecializedToolsTests, en.lproj Localizable.strings, ST design/plan
- Impact: 新增 ST 契约与度量（工具栏 48、反馈 30、图标命中 ≥28、a11y 前缀 `macSvn.st.*`）；Blame/AI/Release Notes 接线 ⌘R 与 busy 门禁；Git 迁移统一反馈与 `isMigrationBusy`，保留对账失败阻断同步；独立页单层 HSplitView 门禁（H≤1、V=0）。ST 定向 12/12、全量 1150/1150、真实 SVN 49/49；Release App 构建、结构校验、隔离启动冒烟与八张三档真实窗口截图通过。VoiceOver/真实按键仍以自动化契约 + residual 验收（与 U6–U8 同口径）；inventory/H-tortoise 无能力状态变化。**ST 波次完成**；不重启 Tortoise Perfect Loop。


- Summary: Human UI Wave U8：完成人本全局体验收口（Human UI 长程收口）
- Affected: MacSvnGlobalExperiencePresentation, Changes/Log/Branches/Conflicts/Diff/Commit/Repo/Properties/Locks/Shelve/Settings/AuxiliaryWorkflowPresentation, HumanCenteredGlobalExperienceTests, U8 design/plan
- Impact: 落地全局键盘契约与 a11y 标识符命名（macSvn.<page>.search/refresh），变更页补齐 ⌘F 搜索焦点与 ⌘R 刷新，历史/分支/冲突/仓库/属性/锁/搁置/设置保持或补齐 ⌘R；Diff/Commit 独立页启用 ⌘R，嵌入工作区时关闭 ⌘R 以免与变更主刷新冲突。统一 MacSvnMotionPolicy，提交检查器折叠走 Reduce Motion 策略。U8 定向 10/10、HumanCentered*+Modal+Perf+Settings+L10n 相关回归与全量 1138/1138 通过，真实 SVN 49/49；Release App 构建、结构校验、隔离启动冒烟和九张三档跨页真实窗口截图通过。VoiceOver/真实按键仍以自动化契约 + residual 验收（与 U6/U7 同口径，AXIsProcessTrusted=false）；inventory/H-tortoise 无能力状态变化。**Human UI 长程目标（U5–U8）至此完成**；不重启 Tortoise Perfect Loop

- Summary: Human UI Wave U7：完成人本辅助工作流统一（任务 6/6）
- Affected: Properties/Locks/Shelve/Settings views, AuxiliaryWorkflowPresentation, ShelveViewModel, English Localization, HumanCenteredAuxiliaryWorkflows/Localization/ShelveViewModel tests, U7 design/plan
- Impact: 属性、锁、搁置/Patch 和设置统一为稳定的工具栏、反馈、主从工作区与固定动作层级；四页补齐 Command-F 搜索焦点和 Command-R 刷新，刷新、确认与 Shelve 异步结果使用完整 busy/generation 门禁。28 个 sheet 与 4 个 popover 继续提供可见关闭入口、Escape 和显式取消；dirty 关闭统一请求放弃确认，busy 时禁止关闭和重复提交。U7 五组定向门禁 78/78、ShelveVM 14/14、全量 1128/1128 通过，其中真实 SVN 49/49；Release App 构建、结构校验、隔离启动冒烟和三档四页 12 张真实窗口截图通过。VoiceOver 以共享关闭栏标签/identifier 与 Modal/U7 自动化契约验收（与 U6 同口径）；宿主 TCC 下动态 VO 遍历与真实按键注入仍为 residual 风险（`AXIsProcessTrusted=false`），交 U8 全局无障碍/键盘流继续；Tortoise inventory/H 清单无能力状态变化，U8 边界保持不变

## 2026-07-15

- Summary: Human UI Wave U6：完成人本核心模式统一与弹窗关闭收口
- Affected: MacSvnCoreModePresentation, Log/RepoBrowser/Branches/Conflict/Merge views, DismissiblePresentation, DesktopLaunchConfiguration, AppNavigator/Root/EnvironmentGate, Localization, HumanCenteredCoreModes/ModalDismissal/DesktopLaunchConfiguration tests, U6 design/plan
- Impact: 历史、仓库浏览、分支与标签、冲突及 Merge 统一为稳定的上下文栏、筛选、主列表和详情层级，在 980×640、1180×760、1440×900 三档及浅色、深色、Reduce Motion 下完成真实窗口验收；错误与空态固定到工作区顶部，网络/认证/SSL/超时错误显示可读摘要并保留原始诊断。Branch/Tag 命令直接打开创建 sheet，启动参数和启动阶段深链等待主工作区就绪后再消费；所有自定义 sheet/popover 使用醒目的右上角关闭按钮，并保留 Esc、tooltip、VoiceOver 标签和显式取消动作。全量 1061/1061 绿（真实 SVN 49/49），Release App 构建、结构校验与隔离启动冒烟通过；Tortoise inventory/H 清单无能力状态变化，后续仍为 U7/U8

- Summary: Human UI Wave U5：完成真人高频变更工作区与全局弹窗关闭能力
- Affected: MacSvnRootView, WorkingCopyWorkspace/Shell/Changes/Diff/Commit, DismissiblePresentation, Log/RepoBrowser/Properties/Locks/Shelve/Settings/RevisionGraph sheets, Localization, HumanCenteredWorkingCopyWorkspaceTests, ModalDismissalAccessibilityTests, U5 design/plan
- Impact: 将工作副本侧栏稳定在 220–320 pt，重排工作副本上下文、变更、Diff 与可收起提交检查器；行选择只控制 Diff，独立复选框控制提交集合，未选择/加载/无差异/二进制/错误状态不再混淆，AI 退入“说明辅助”菜单。默认窗口改为 1180×760，并在 980、1180、1440 与深色外观下修复标签换行、路径逐字换行、按钮越界及菜单指示器游离。新增统一弹窗关闭栏，26 个 sheet 与 2 个 popover 均提供右上角 xmark、tooltip、无障碍标签和 Esc 关闭，原业务“取消”按钮继续保留；全量 1034/1034 绿（真实 SVN 49/49），Release App 构建、结构校验与隔离启动冒烟通过

- Summary: Tortoise 完美 Loop GP.6：停止 Loop
- Affected: README parity contract, docs index, H-tortoise-parity, perfect-loop, codex-tortoise-parity-long-loop
- Impact: PERFECT 八项与 GP.1–GP.5 已全部完成后，勾选 GP.6 并将两份 Loop 文档切换为终止态；移除可执行的 one-shot 唤醒和续跑指令，不再创建 `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` sleeper/automation。运行时审计未发现匹配进程，`~/.codex/automations` 不存在；新增停止态文档契约；全量 1017/1017 绿（真实 SVN 49/49），覆盖率 114/114（100%）

- Summary: Tortoise 全量对标完成（GP.5 PERFECT 收口）
- Affected: README parity contract, H-tortoise-parity, distribution-smoke, parity-coverage, perfect-loop, codex-tortoise-parity-long-loop
- Impact: PERFECT 的 P-INV、P-STUB、P-TEST、P-H1、P-COV、P-PERF、P-DOC、P-SHIP 全部满足：inventory 五维 114/114（100%），T0–T5 真实 WC/Finder/H 清单全勾，README 与验收证据对齐。重新构建 Xcode Release 双架构 App，主应用、Finder Sync、Quick Look 的包结构、Mach-O 依赖、深层签名与隔离启动冒烟全部通过，产物位于 `/tmp/svnstudio-gp5-release/SVNStudio.app`；Developer ID/公证因本机 0 个有效签名身份继续按计划明示阻塞，不降低 P-INV 或平台能力。新增 PERFECT 文档契约测试；全量 1016/1016 绿（真实 SVN 49/49），覆盖率 114/114（100%）；下一 GP.6 停止 Loop

- Summary: Tortoise 完美 Loop GP.4：README 功能矩阵与 inventory 对齐
- Affected: README, docs/README, ReadmeParityTests, H-tortoise-parity, parity-coverage, perfect-loop, codex-tortoise-parity-long-loop
- Impact: 根 README 将 Tortoise 对标拆为 D01–D28、命令 #1–#46、日志 L01–L20、设置 S01–S13 与 Overlay 7/7 五维矩阵，显式发布 114/114（100%）并链接 inventory、H-Tortoise 和覆盖率快照；移除旧交付分支、旧 main 收口状态与 Sparkle 误述，更新为当前 HTTPS GitHub Releases 检查和 T0–T6 波次；文档索引同步 GP.4 与覆盖率状态；新增 3 项 README 契约测试；全量 1015/1015 绿（真实 SVN 49/49），覆盖率门禁 114/114；下一 GP.5

- Summary: Tortoise 完美 Loop GP.3：全测、H 环境与性能门禁
- Affected: H-tortoise-parity, perfect-loop, codex-tortoise-parity-long-loop, parity-coverage
- Impact: 全量 `swift test` 1012/1012 绿，真实 SVN 集成 49/49；Xcode Debug App 在隔离 Foundation/HOME/TMPDIR 下稳定启动 8 秒；确认 `/usr/local/bin/svn` 1.14.5，并准备同时含 modified/unversioned 的临时可写真实 WC；空闲 CPU 每 2 秒采样 5 次均为 0.0%，大 Diff 与工作区 AttributeGraph 性能守卫继续通过；P-TEST/P-PERF 与 H 环境/T0–T5 汇总 ✅，下一 GP.4

- Summary: Tortoise 完美 Loop GP.2：清零用户可见未实现 stub
- Affected: MacSvnAppNavigator, MacSvnRootView, MacSvnFeatureHostView, SvnCommandCatalog/Options, MacSvnDesktopApp, MacSvnAppNavigatorTests, docs/*
- Impact: 将 66 个 Catalog ID 到真实功能页的路由改为非 Optional 穷尽映射，删除 T0 阶段 `.unimplemented` 结果与用户提示、未使用的 Core dispatch 枚举和死路由占位视图；设置 bootstrap 改为明确的加载状态。新增源码门禁，阻止 `.unimplemented`、用户可见“未实现”和死占位回归；生产源码扫描为 0，Navigator 33 测、全量 1012 测绿，Xcode Debug 构建通过；P-STUB/H-GP ✅，下一 GP.3

- Summary: Tortoise 完美 Loop GP.1：覆盖率 100% 严格门禁
- Affected: parity-coverage, H-tortoise-parity, perfect-loop, codex-tortoise-parity-long-loop
- Impact: 实跑 `python3 scripts/parity-coverage.py --fail-below 1.0`，确认 command 46/46、domain 28/28、log 20/20、settings 13/13、overlay 7/7 全部完成，合计 114/114（100%），partial 与 missing 均为 0；覆盖率脚本 2 项单测通过；P-INV/P-COV 与 H-GP 对应门禁勾选，下一 GP.2

- Summary: Tortoise 完美 Loop T5.8 / G5：设置全表与运行时出门闸门
- Affected: TortoiseParitySettings, SettingsStore, SvnClientConfigurationStore, RevertSafetyService, UnversionedTreeExpander, AppUpdateService, Changes/Commit/RepoBrowser/WorkingCopyActions ViewModel, MacSvnSettings/Changes/Commit/RepoBrowser views, Localization resources, Tests/*, docs/*
- Impact: 补齐 S01/S03/S04/S05/S06/S09 并使 D28 与 S01–S13 全部 ✅：中英文动态界面与 HTTPS 更新检查、真实 SVN config/servers 和统一 `--config-dir`、代理密码 0600、亮暗状态色、Dialogs 策略热更新、Revert 废纸篓恢复、Repo Browser 直接子目录预取与 externals、递归未版本后台取消/ignored 边界/100,000 项上限、提交自动完成限时索引均完成。设置协调保存 settings/提交历史/SVN 配置，后段失败会回滚 settings 与 SVN 配置，并以 generation 防止旧刷新覆盖新设置；全量 1012 绿（真实 SVN 49/49），覆盖率 114/114（100%），Localization、Xcode Debug 与 SwiftPM Debug App 包装通过；G5 ✅，下一 GP.1

- Summary: Tortoise 完美 Loop T5.7：双架构 Release 包装、本机冒烟与公证审计
- Affected: build-release-app.sh, verify-release-app.sh, verify-mach-o-dependencies.sh, smoke-test-macos-app.sh, sign-and-notarize.sh, verify-signing-prereqs.sh, DistributionPackagingTests, docs/packaging/*, docs/acceptance/*, perfect-loop/long-loop docs
- Impact: 新增 Xcode Release `arm64 x86_64` 分发构建闭环，强制校验主应用、Finder Sync、Quick Look 的包结构、扩展点、架构、dyld run-path 继承、递归包内依赖与深层签名，并在隔离 Foundation 用户目录、HOME/TMPDIR、最小 PATH 下真实启动冒烟，超时会终止独立进程组。签名公证流程保留 Finder 专属 entitlements，限定 Developer ID Application 并核对三包 Team ID，要求 `notarytool` JSON 状态 `Accepted`，所有步骤在隐藏目录过闸后才原子发布最终 App/ZIP。当前机器无 Developer ID 身份及公证凭据，已如实记录 Gatekeeper/干净机阻塞；全量 948 绿，覆盖率保持 108/114；下一 T5.8/G5

- Summary: Tortoise 完美 Loop T5.6：App Icon、首次空态与关于页
- Affected: SVNStudio.icns, generate-app-icon.swift, ProductBranding, MacSvnWorkingCopyShellView, MacSvnAboutView, MacSvnDesktopApp, macOS packaging scripts, Xcode project, BrandingExperienceTests, docs/*
- Impact: 新增可重复生成的多尺寸原生 macOS App Icon，并由 SwiftPM release 包装与 Xcode target 统一嵌入、逐字节校验；首次无工作副本空态提供可执行的添加工作副本与设置入口；应用菜单以独立单例窗口展示实际应用图标、版本/build 和项目主页，关闭全部主窗口后仍可打开。新增品牌体验与包装资源契约测试；全量 941 绿，SwiftPM release 包装和 Xcode Debug 构建通过；inventory 无状态变化，覆盖率保持 108/114；下一 T5.7

## 2026-07-14

- Summary: Tortoise 完美 Loop T5.5：按扩展名配置外置 Diff / Merge / Blame
- Affected: ExternalToolRuleResolver, ExternalToolLaunchService, ExternalDiffService, AppSettings, MacSvnSettingsView, MacSvnDiffView, MacSvnConflictWorkspaceView, MacSvnBlameView, Tests/*, docs/*
- Impact: External Programs 支持按用途和文件扩展名保存外置工具；精确扩展名大小写无关匹配并优先于默认规则，留空、`*`、`*.*` 可作为默认规则。Diff 延续旧统一查看器配置作为兼容兜底；文本冲突 Merge 传入 base/mine/theirs/result 且不会自动执行 `svn resolve`；Blame 只接受工作副本内文件。统一参数替换和非零退出码处理，并覆盖规则解析、持久化、启动参数、路径边界和失败传播契约；全量 937 绿，覆盖率 108/114，S10 升为 ✅；下一 T5.6

- Summary: Tortoise 完美 Loop T5.4：清理认证缓存与日志缓存
- Affected: SvnAuthenticationCacheStore, MacSvnAppSession, MacSvnSettingsView, SvnAuthenticationCacheStoreTests, SettingsInformationArchitectureTests, docs/*
- Impact: Saved Data 新增二次确认的 Subversion 认证缓存清理；通过用户配置的 SVN 客户端执行 `svn --config-dir … auth --remove '*'`，同时覆盖 auth 文件和 macOS Keychain 凭据，空缓存幂等成功，命令失败时保留文件缓存；明确隔离 AI Provider Keychain 凭据。已有日志缓存全量清理入口增加执行中防重入；全量 924 绿，覆盖率 107/114，D03/S11 升为 ✅；下一 T5.5

- Summary: Tortoise 完美 Loop T5.3：Bugtraq / tsvn 项目属性
- Affected: ProjectPropertyPolicy, CommitViewModel, LockViewModel, PropertyViewModel, MacSvnCommitView, MacSvnLocksView, MacSvnBranchesView, MacSvnRepoBrowserView, MacSvnPropertiesView, BugtraqIssueTextEditor, MacSvnProjectPropertyLoader, Tests, docs/*
- Impact: 解析并诊断 `bugtraq:url/message/number/append/logregex` 与关键 `tsvn:*` 项目属性；支持 WC 祖先属性合并、`^/` 仓库根 URL 展开与失败诊断、单/双阶段 issue 文本内高亮/提取/链接、输入模式插入/追加 issue、提交说明最小长度阻断与宽度提示、通用及全部操作模板、Windows LCID/locale 到 macOS 原生拼写检查、锁说明最小长度和锁模板；属性页可在保存前提示无效 Bugtraq/tsvn 草稿并将属性模板带入提交。属性加载器按实际节点类型处理无扩展名文件与带点目录；缺少 `%BUGID%` 的模板保留诊断并禁用无效输入入口；多选严格合并、属性读取 fail-closed、陈旧刷新不打断写操作、夺锁确认保留原说明；全量 917 绿，覆盖率 105/114；下一 T5.4

- Summary: Tortoise 完美 Loop T5.2：客户端 pre-commit / post-update 钩子
- Affected: ClientHookService, AppSettings, SvnService, MacSvnAppSession, MacSvnSettingsView, ClientHookServiceTests, SettingsStoreTests, SvnServiceTests, docs/*
- Impact: Saved Data 支持按工作副本祖先路径配置启用状态、类型、脚本、参数与超时；执行器按 Tortoise 官方顺序生成 UTF-8 PATH/DEPTH/MESSAGEFILE/REVISION/ERROR/CWD/RESULTPATH 参数，临时文件权限 0600；pre-commit 在 add/commit 前同步阻断，post-update 覆盖 Update/Switch/Checkout 的成功与失败路径且 SVN 原始错误优先；配置持久化并兼容旧 settings；S11 保持 🟡，认证缓存清理待 T5.4；全量 879 绿，覆盖率 103/114；下一 T5.3

- Summary: Tortoise 完美 Loop T5.1：设置分类信息架构
- Affected: MacSvnSettingsCategory, MacSvnSettingsView, SettingsInformationArchitectureTests, inventory, H-tortoise-parity, perfect-loop, codex-tortoise-parity-long-loop
- Impact: 设置页改为 General / Dialogs / Colours / Network / External Programs / Saved Data 稳定侧栏，并为 Finder / Revision Graph / AI 保留独立分类；现有 SVN、对话框、日志缓存、Finder、修订图、外置 Diff 与 AI 设置按领域迁入，保存/加载契约不变，并以分类模型和双向映射守卫防回归；D28 与 S01/S03/S04/S06/S09/S10/S11 诚实升为 🟡，未提前宣称代理、钩子、认证清理或按扩展名外置工具完成；全量 871 绿，覆盖率 103/114；下一 T5.2

- Summary: Tortoise 完美 Loop T4.8 / G4：Finder App Sandbox 真实冒烟与 Shell 集成闸门
- Affected: SVNStudioFinderSync target/entitlements, MacSvnFinderSync, FinderSyncRootsExporter, MacSvnAppSession, MacSvnWorkspaceController, verify-finder-sync-appex, Tests/*, docs/*
- Impact: Finder target 启用 App Sandbox 后可由 `pluginkit` 正常登记；主应用将 v4 配置镜像到扩展容器；扩展直接探测 Homebrew/系统 SVN，并以只读例外访问常见工作副本根，OSLog 保留命令成功/失败诊断；真实 WC 中 `status/info/proplist` 全部成功，Added 与 Modified 显示不同 Finder 角标；appex、深层签名与 Xcode Debug 构建校验通过；全量 868 绿，覆盖率 103/114；G4 ✅，下一 T5.1

- Summary: Tortoise 完美 Loop T4.7：Finder Context Menu 设置与 Copy/Move 平台等价入口
- Affected: FinderSyncContextMenuSettings, FinderSyncContextMenuBuilder, FinderSyncRootsExporter, MacSvnFinderSync, MacSvnSettingsView, MacSvnAppNavigator, MacSvnChangesView, Tests/*, docs/*
- Impact: 设置页支持选择 Finder 顶层提升命令、needs-lock 自动提升 Lock、隐藏已知未版本/已忽略路径菜单与菜单排除路径；`finder-sync-roots.json` 升级 v4 并兼容旧配置；Finder 同步回调只读线程安全状态快照，未知状态保守不隐藏；Copy/Move 通过 Finder 菜单深链携带绝对路径，主应用自动选择工作副本、转换相对路径并打开既有向导，作为无右拖回调时的平台等价入口；S02、D02 升为 ✅；全量 862 绿，Xcode Debug 构建与 Finder appex 校验通过；覆盖率 103/114；下一 T4.8/G4

## 2026-07-13

- Summary: Tortoise 完美 Loop T4.6：Finder SVN 信息面板
- Affected: MacSvnFinderSync, MacSvnAppNavigator, MacSvnWorkspaceController, MacSvnPropertiesView, SvnInfo, InfoXMLParser, Tests/*, docs/*
- Impact: Finder「更多命令…」新增属性入口，绝对路径深链会选择包含该文件的最深已登记工作副本并进入应用内属性页；`svn info --xml` 结构化解析最后提交作者/修订/日期与仓库锁，面板集中展示 WC 状态、修订、最后作者、仓库 URL、锁和属性摘要；属性页用请求代次丢弃旧的异步 info/status 结果；真实 SVN 锁信息往返验证、全量 846 绿及 Finder appex 嵌入校验通过；D01 升为 ✅，覆盖率 101/114；下一 T4.7

- Summary: Tortoise 完美 Loop T4.5：Finder 多选批量命令
- Affected: MacSvnFinderSync, FinderSyncDeepLinkBuilder, MacSvnDeepLinkParser, MacSvnDeepLinkAction, MacSvnAppNavigator, Tests/*, docs/*
- Impact: Finder 菜单优先捕获全部选中项，无选中项时回退 targeted URL；统一 command 深链使用重复 `path` query 保序传递，Parser 不再覆盖重复路径，Navigator 原样交给既有 `perform(command:paths:)` 批量入口；单路径构建 API 保持兼容；全量 842 绿，Finder Sync target 构建及 appex 嵌入校验通过；覆盖率 100/114；下一 T4.6

- Summary: Tortoise 完美 Loop T4.4：Finder 普通与「更多命令…」扩展菜单
- Affected: MacSvnFinderSync, FinderSyncDeepLinkBuilder, MacSvnDeepLinkParser, MacSvnAppNavigator, SvnCommandCatalog, Tests/*, docs/*
- Impact: Finder Sync 提供更新、提交、日志、Diff、还原、解决冲突普通菜单，以及添加、删除和 Catalog 标记扩展命令；所有菜单动作统一使用 `SvnCommandID` 与 `svnstudio://command` 深链，复用主应用既有命令执行入口；全量 839 绿，Finder Sync target 构建及 appex 嵌入校验通过；覆盖率 100/114；下一 T4.5

- Summary: Tortoise 完美 Loop T4.3：Finder 路径过滤与可选角标
- Affected: FinderSyncOverlaySettings, FinderSyncPresentationBuilder, FinderSyncRootsExporter, AppSettings, MacSvnSettingsView, MacSvnFinderSync, Tests/*, docs/*
- Impact: Finder 设置支持包含/排除卷与路径（标准化绝对路径子树匹配、exclude 优先）和 18 类角标逐项选择；include 子树成为实际监视目录，禁用角标不参与文件/目录优先级聚合；配置升级为 v3 并兼容 v1/v2 缺失字段，设置持久化与原子热更新保持；全量 836 绿，Finder Sync target 构建及 appex 嵌入校验通过；覆盖率 100/114；下一 T4.4

- Summary: Tortoise 完美 Loop T4.2：Finder Status Cache 三模式
- Affected: FinderSyncCachePolicy, FinderSyncRootsExporter, AppSettings, MacSvnSettingsView, MacSvnFinderSync, Tests/*, docs/*
- Impact: 设置页支持 Default/Shell/None 并持久化到 `finder-sync-roots.json` v2；Default 按 WC 根缓存 8 秒完整快照，Shell 按 Finder 请求目标缓存 2 秒，None 停止 SVN 状态采集与角标但保留右键菜单；兼容 v1 默认迁移，工作副本刷新保留模式；配置原子热更新使用 generation 隔离旧并发结果，并监听稳定目录以支持连续保存；全量 822 绿，Finder Sync target 构建及 appex 嵌入校验通过；覆盖率 97/114；下一 T4.3

- Summary: Tortoise 完美 Loop T4.1：Finder Overlay 全状态映射
- Affected: FileStatusOverlayMetadata, StatusXMLParser, FinderSyncInfoXMLParser, FinderSyncStatusEnricher, FinderSyncPresentationBuilder, MacSvnFinderSync, Tests/*, docs/*
- Impact: Finder Sync 覆盖 normal/modified/conflicted/added/deleted/missing/replaced/locked/needs-lock/ignored/unversioned/shallow/nested/external/switched/mergeinfo-only；结构化读取 status/info/current+BASE properties，精确识别属性冲突、只读 needs-lock 与仅 mergeinfo 变化；目录含根路径按优先级递归聚合；并发刷新按 WC 合并；全量 810 绿，Finder Sync target 构建及 appex 嵌入校验通过；覆盖率 97/114；下一 T4.2

- Summary: Tortoise 完美 Loop T3.12 / G3：专业能力波次出门闸门
- Affected: inventory, H-tortoise-parity, parity-coverage, perfect-loop, codex-tortoise-parity-long-loop
- Impact: 补齐 Show Log 聚合域 D13 的统计/离线验收描述；T3 相关命令、日志、设置和 DUG 域逐项核验通过；全量 798 绿；覆盖率 92/114（80.70%）；下一 T4.1

- Summary: Tortoise 完美 Loop T3.11：日志统计 / 离线缓存（L18、S13）
- Affected: LogStatisticsBuilder, LogCacheStore, LogViewModel, MacSvnLogView, MacSvnSettingsView, MacSvnAppSession, AppSettings, Tests/*, docs/*
- Impact: 日志统计支持当前过滤结果的修订、作者、日期、动作汇总；在线日志按仓库目标与 stop-on-copy 隔离缓存，支持容量/保留期策略、全量清理、网络/认证/环境失败回退和强制离线读取；设置持久化日志缓存策略；真实应用目标编译通过；全量 798 绿；覆盖率 91/114；下一 T3.12/G3

- Summary: Tortoise 完美 Loop T3.10：Edit author/message + revision properties（L15、L16）
- Affected: RevisionPropertyViewModel, MacSvnLogView, MacSvnAppNavigator, SvnCommandBuilder, SvnBackend, SvnCliBackend, SvnService, PropertyXMLParser, ProcessRunner, Tests/*, docs/*
- Impact: 日志详情与右键可查看目标修订全部 revprops，并编辑 `svn:author` / `svn:log`；仅写变化属性，认证失败自动重试，写操作互斥；UTF-8 值通过 `0600` 临时文件传递，稳定支持中文且不暴露在 argv；仓库拒绝时展示 `pre-revprop-change` hook 提示；⌘K 原子注入修订/仓库；真实 SVN 验证无 hook 拒绝及作者/中文说明/自定义属性往返；全量 787 绿；覆盖率 89/114；下一 T3.11

- Summary: Tortoise 完美 Loop T3.9：Compare revisions / Blame differences（#40、L03、D23）
- Affected: BlameDifferenceViewModel, MacSvnBlameView, LogContextActionPolicy, MacSvnLogView, MacSvnAppNavigator, SvnCommandBuilder, SvnCommandCatalog, MacSvnChangesView, Tests/*, docs/*
- Impact: 双修订分别读取 blame，并用 `svn diff -r OLD:NEW` 对齐左右内容与行号，展示作者/日期/修订、增删改和归属变化汇总；支持仅变化筛选、目标 BASE 与任意双修订；日志 L03 默认 PREV:REV，使用仓库 URL 与 `@peg` 保证历史路径解析；CFM/⌘K 可达；真实 SVN 双提交往返；全量 778 绿；覆盖率 87/114；下一 T3.10

- Summary: Tortoise 完美 Loop T3.8：Delete keep local / Delete unversioned（#15、#16）
- Affected: UnversionedDeletionPolicy, SvnCommandBuilder, SvnBackend, SvnCliBackend, SvnService, WorkingCopyActionsViewModel, MacSvnChangesView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: 支持 `svn delete --keep-local` 并二次确认；删除未版本项提供 status 候选预览和勾选，执行前重新读取 status、校验 WC 路径边界与未版本状态，父子路径合并避免重复删除；CFM/⌘K 使用一次性原子意图；真实 SVN 验证本地保留、文件/目录删除与版本文件不受影响；全量 771 绿；覆盖率 84/114；下一 T3.9

- Summary: Tortoise 完美 Loop T3.7：Create Repository Here（#28）
- Affected: SvnRepositoryCreator, CreateRepositoryViewModel, MacSvnRepoBrowserView, MacSvnAppNavigator, MacSvnAppSession, SvnErrorMapper, Tests/*, docs/*
- Impact: 仓库浏览器与 ⌘K 支持选择目录并执行 `svnadmin create --fs-type fsfs`；`svnadmin` 跟随用户配置的 SVN 工具链并保留结构化错误码；创建成功后直接浏览 `file://` 仓库；真实 FSFS format/db/conf 验证；全量 761 绿；覆盖率 82/114；下一 T3.8

- Summary: Tortoise 完美 Loop T3.6：Merge reintegrate 与日志 Merge revision to…（#25、#42、L13）
- Affected: SvnCommandBuilder, SvnBackend, SvnCliBackend, SvnService, MergeWizardViewModel, MacSvnMergeWizardView, LogContextActionPolicy, MacSvnLogView, Tests/*, docs/*
- Impact: 适配 SVN 1.14 的现代 complete merge reintegrate 语义（不使用已废弃的 `--reintegrate`）；Merge 向导支持重新整合 dry-run/执行及冲突回跳；日志路径菜单新增 L13，使用 `svn merge -c REV` 合并到当前工作副本并提供高危确认；真实 SVN 验证；全量 755 绿；覆盖率 81/114；下一 T3.7

- Summary: Tortoise 完美 Loop T3.5：官方 `svn shelve` 对齐与本地搁置迁移（#37、D12、S05）
- Affected: SvnExperimentalShelvingClient, ShelveService, ShelveViewModel, MacSvnShelveView, MacSvnSettingsView, MacSvnAppSession, AppSettings, Tests/*, docs/*
- Impact: 通过 `SVN_EXPERIMENTAL_COMMANDS=shelf2|shelf3` 接入官方 `x-shelve`、`x-shelf-list`、`x-shelf-diff`、`x-shelf-log`、`x-unshelve`、`x-shelf-drop`；设置支持 V2/V3（默认 V3）；搁置页提供官方与本地双轨能力，手工本地快照可迁移且官方失败保留快照，安全快照拒绝迁移；全量 749 绿；覆盖率 78/114；下一 T3.6

- Summary: Tortoise 完美 Loop T3.4：Externals 编辑与更新行为（#39、D18）
- Affected: ExternalsPolicy, PropertyViewModel, MacSvnPropertiesView, MacSvnRepoBrowserView, MacSvnAppNavigator, SvnCommandBuilder, SvnCommandCatalog, Tests/*, docs/*
- Impact: 新增 `svn:externals` 现代/旧式语法解析与结构化编辑器，支持目录/文件 external、operative/peg revision、注释保留和安全本地路径校验；仓库浏览器可拖拽 URL 预填；保存后可选择立即更新且明确不忽略 externals；真实 SVN 验证目录/文件 external materialize；全量 738 绿；覆盖率 75/114；下一 T3.5

- Summary: Tortoise 完美 Loop T3.3：Change Lists（#38、D11、CFM §4.2）
- Affected: ChangelistPolicy, FileStatus/StatusXMLParser, SvnCommandBuilder/Backend/Service, ChangesViewModel, CommitViewModel, MacSvnChangesView, MacSvnCommitView, MacSvnAppNavigator, SvnCommandCatalog, Tests/*, docs/*
- Impact: 解析并展示 SVN changelist 归属；CFM 支持变更列表列、分组和按深度移入/移出；Commit 提供按列表选择并默认排除 `ignore-on-commit`；cmd.38 从 CFM/⌘K 可达且不会误打开相对路径；真实 SVN 往返验证；全量 730 绿；覆盖率 73/114；下一 T3.4

- Summary: Tortoise 完美 Loop T3.2：Revision Graph 核心与设置（#9、D25、S07、§4.6）
- Affected: RevisionGraphModels/Builder/PathClassifier/NodeActionPolicy/ViewModel, SvnCommandBuilder/Backend/Service, MacSvnRevisionGraphView, MacSvnSettingsView, MacSvnAppNavigator, Tests/*, docs/*
- Impact: 从仓库根 `svn log -v` 构建 history/copy 图，支持 trunk/branches/tags glob 分类、颜色与 copy 混色、标签/未分类/已删除剪枝、拓扑/时间线、分页/All；节点 Log/Checkout/Blame/Diff 经原子 intent 与认证重试接入现有工作流；真实 SVN 验证 copy-edge 和跨位置 Diff；覆盖率 71/114；全量 724 绿；下一 T3.3

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
