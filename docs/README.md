# 文档索引

| 文档 | 内容 | 状态 |
|------|------|------|
| [01-requirements.md](01-requirements.md) | 需求规格说明书（SRS）：用户画像、全量功能需求（FR）与非功能需求（NFR）、验收标准 | v1.0 |
| [02-requirements-analysis.md](02-requirements-analysis.md) | 需求分析：核心用例拆解、svn CLI 能力映射、可行性与风险登记册 | v1.0 |
| [03-high-level-design.md](03-high-level-design.md) | 概要设计（HLD）：分层架构、模块职责、核心流程、数据模型、工程结构 | v1.0 |
| [04-detailed-design.md](04-detailed-design.md) | 详细设计（DLD）：各层接口签名、三路合并算法、解析器规格、边界场景清单 | v1.0 |
| [05-test-plan.md](05-test-plan.md) | 测试计划：单元/集成/对拍/性能用例、环境矩阵、验收清单、CI 方案 | v1.0 |
| [specs/2026-07-08-mac-svn-desktop-design.md](specs/2026-07-08-mac-svn-desktop-design.md) | 原始决策记录（产品档位、技术选型过程） | 归档 |

## 阅读顺序

- 了解产品做什么：01 → 02
- 参与开发：03 → 04（先看第 2 节 `SvnBackend` 协议）
- 参与测试：01 第 6 节验收标准 → 05
