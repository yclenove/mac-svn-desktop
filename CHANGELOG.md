# Changelog

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
