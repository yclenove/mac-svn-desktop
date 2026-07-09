# Changelog

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
