# Changelog

## 2026-07-10

- Summary: 启动长程 Loop 全量交付；新建 `feat/long-loop-full-delivery` 与 backlog（Wave A–H）；完成 A1–A3/B1/B2/B7——`MacSvnAppSession` DI、svn 环境门禁、工作副本管理页、变更页接线、设置页、App 启动引导
- Affected: Sources/MacSvnApp/**, Sources/MacSvnDesktopApp/**, Tests/MacSvnAppTests/**, docs/superpowers/plans/2026-07-10-long-loop-backlog.md
- Impact: App 可启动并管理 WC / 查看 status；下一轮 backlog 首项为 B3（Update/Cleanup/Revert 等动作栏）

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
