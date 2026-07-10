# 文档索引

| 文档 | 内容 | 状态 |
|------|------|------|
| [01-requirements.md](01-requirements.md) | 需求规格说明书（SRS）：用户画像、全量功能需求（FR）与非功能需求（NFR）、验收标准 | v1.1 |
| [02-requirements-analysis.md](02-requirements-analysis.md) | 需求分析：核心用例拆解、svn CLI 能力映射、可行性与风险登记册 | v1.0 |
| [03-high-level-design.md](03-high-level-design.md) | 概要设计（HLD）：分层架构、模块职责、核心流程、数据模型、工程结构 | v1.0 |
| [04-detailed-design.md](04-detailed-design.md) | 详细设计（DLD）：各层接口签名、三路合并算法、解析器规格、边界场景清单 | v1.0 |
| [05-test-plan.md](05-test-plan.md) | 测试计划：单元/集成/对拍/性能用例、环境矩阵、验收清单、CI 方案 | v1.0 |
| [06-innovative-features.md](06-innovative-features.md) | 创新功能设计：AI 智能助手（多 Provider、tool-calling 分级安全）、一键迁移 Git（五步向导、增量同步）、生态效率（提交守护/搁置/Finder/命令面板等） | v1.0 |
| [specs/2026-07-08-mac-svn-desktop-design.md](specs/2026-07-08-mac-svn-desktop-design.md) | 原始决策记录（产品档位、技术选型过程） | 归档 |
| [superpowers/plans/2026-07-10-long-loop-backlog.md](superpowers/plans/2026-07-10-long-loop-backlog.md) | 长程 Loop 一：主路径 UI 接线（Wave A–H，已完成） | 完成 |
| [superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md](superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md) | 长程 Loop 二：SRS 缺口补齐（验收/体验/扩展/发布） | 完成 |
| [superpowers/specs/2026-07-10-ui-ux-ia-design.md](superpowers/specs/2026-07-10-ui-ux-ia-design.md) | UI/UX 信息架构：WC 侧栏 + WorkspaceMode + 变更工作区 | 已落地 |
| [superpowers/plans/2026-07-10-ui-ux-ia-refactor.md](superpowers/plans/2026-07-10-ui-ux-ia-refactor.md) | UI/UX IA 重构实现计划（U1–U4） | 已落地 |
| [superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md](superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md) | **小乌龟全量能力清单 v2**（DUG 域、命令#、日志右键 L#、设置 S#、Overlay；验收唯一真相） | 基线 |
| [superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md](superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md) | **完美 Loop**：T0–T5 原子 backlog + 唤醒协议 + PERFECT 停止条件 | 执行中（T0.1 已完成） |
| [acceptance/performance-guards.md](acceptance/performance-guards.md) | UI 性能门禁（AttributeGraph / Diff 阈值，T0.1） | 生效 |
| [acceptance/parity-coverage.json](acceptance/parity-coverage.json) | Tortoise 对标覆盖率快照（由 `scripts/parity-coverage.py` 生成） | 自动 |
| [superpowers/plans/2026-07-10-long-term-iteration-roadmap.md](superpowers/plans/2026-07-10-long-term-iteration-roadmap.md) | 长期迭代路线图 **T0–T6**（全量对标小乌龟；旧 L0–L8 已映射） | 草案 |
| [superpowers/specs/2026-07-10-long-term-product-design.md](superpowers/specs/2026-07-10-long-term-product-design.md) | 长期产品开发详设（对标原则、模块、性能规范、风险） | 草案 |
| [acceptance/H1-manual-checklist.md](acceptance/H1-manual-checklist.md) | 真实 WC 手工验收清单 | 待跑通 |
| [acceptance/H-tortoise-parity.md](acceptance/H-tortoise-parity.md) | Tortoise 全量对标手工验收（按 T0–T5/GP 分节） | 骨架 |

## 阅读顺序

- 了解产品做什么：01 → 02
- 参与开发：03 → 04（先看第 2 节 `SvnBackend` 协议）
- 参与测试：01 第 6 节验收标准 → 05
- 继续长程交付（小乌龟完美 Loop）：[完美 Loop 规划](superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md) ← 每轮执行入口；真相 [能力清单 v2](superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md)；战略 [路线图 T0–T6](superpowers/plans/2026-07-10-long-term-iteration-roadmap.md)；[长期详设](superpowers/specs/2026-07-10-long-term-product-design.md)；UI/UX 见 [IA 规格](superpowers/specs/2026-07-10-ui-ux-ia-design.md)
