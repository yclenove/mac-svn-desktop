# SVN Studio 工程收口与发布说明（RC）设计

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-22 |
| 产品 | SVN Studio |
| 状态 | **完成**（2026-07-22 RC 任务 1–5 收口；PR #2 已合入 `main` @ `89dc6a5`） |
| 对应迭代 | Release Closeout Wave **RC**（ST 之后工程收口） |
| 前序 | Tortoise Perfect Loop GP.6 已停止；Human UI U5–U8 与 ST 均已完成 |
| 非目标 | 不实现 Developer ID 公证；不做真 VoiceOver/按键注入；不重启 Perfect Loop；不推进 T6 产品增强或新体验波次；不修改 inventory/H-tortoise（能力无变化） |

## 1. 背景

当前 `feat/tortoise-parity-perfect-loop` 已交付：

- Tortoise inventory **114/114（100%）**，Perfect Loop **已停止**；
- Human UI **U5–U8** + 专业工具面 **ST** 人本体验收口完成；
- 相对 `main` 约领先 185 提交、落后 3 提交（菜单栏 MainActor 通知回调修复）。

产品能力与体验主轴已闭环，但仍缺一次**工程收口**：与 `main` 对齐、发布说明、residual 单一真相表、文档索引对齐，以及合入 `main` 的准备材料。

## 2. 目标与成功标准

| 目标 | 成功标准 |
|------|----------|
| 与 `main` 对齐 | 本分支 merge `main` 成功；不丢失 MainActor 崩溃修复 |
| 门禁绿 | 全量 `swift test`、真实 SVN 49/49、build/verify/smoke、`git diff --check`、parity 114/114 |
| 发布说明 | 产品级里程碑说明（非公证声明）已落盘并链入索引 |
| residual | Developer ID / AX-VO / 独立 HSplitView / 过时 roadmap 有单一矩阵 |
| 合入准备 | 分支 tip 干净；PR 描述模板就绪；可选创建 PR |
| 能力诚实 | inventory / H-tortoise / parity-coverage **默认不改** |

## 3. 方案选择

### 方案 A：仅写发布说明，不合 `main`（否决）

文档与可合入状态脱节，工程风险仍在。

### 方案 B：rebase 185 历史到 `main`（否决）

重写长历史风险高；本波默认 **merge 非 rebase**。

### 方案 C：merge `main` + 文档收口 + 合入准备（采用）

1. 先写 RC 规格/计划；
2. 本分支 `git merge main`；
3. 发布说明 + residual 矩阵 + roadmap 过时声明；
4. 全量门禁；
5. README/CHANGELOG 收口；可选 PR。

## 4. 合入策略

| 项 | 决策 |
|----|------|
| 方向 | 先 **merge `main` → 本分支**，再准备 **本分支 → `main`** 的 PR |
| 历史 | **merge**，禁止 force-push `main`，禁止改写 185 提交历史 |
| 冲突 | 仅允许文档/CHANGELOG 级；代码冲突须先失败测试再修 |
| MainActor 修复 | 以安全写法为准（通知授权回调不触碰 MainActor 状态） |
| 版本号 | 里程碑 **RC / 2026-07-22 tip**；不强行 `v1.0.0` |

## 5. Residual 矩阵（单一真相）

| Residual | 状态 | 本波处理 | 后续波次 |
|----------|------|----------|----------|
| Developer ID / notarytool / 干净机 Gatekeeper | 本机 0 签名身份 | **仅文档**；不伪造成功 | **DX**（需凭据） |
| VoiceOver 动态遍历 / 真实按键注入 | `AXIsProcessTrusted=false` | **仅文档**；契约测试保持 | **A11Y**（需 TCC） |
| 独立 Blame/AI/Commit/Diff 单层 HSplitView | ST 已允许 + 门禁 | **仅文档**；禁止嵌套回退 | 无强制 |
| `long-term-iteration-roadmap` 旧 `[ ]` | 与 114/114 矛盾 | **标注过时**；禁止据此重开 T0–T5 | — |

证据与解除步骤：

- 分发阻塞：[distribution-smoke-2026-07-15.md](../../acceptance/distribution-smoke-2026-07-15.md)、[signing-and-notarization.md](../../packaging/signing-and-notarization.md)
- a11y residual：U6–U8/ST 规格 § residual；自动化契约 + identifier，不砍功能
- HSplitView：ST 规格允许独立页单层；嵌入工作区仍禁自由 SplitView

## 6. 发布说明范围（产品级，非公证）

必须覆盖：

1. Tortoise 对标 114/114 + Perfect Loop 终止（GP.6）；
2. Human UI U5–U8 + ST 人本体验收口；
3. 本机构建与校验路径：`build-macos-app` / `verify-macos-app` / `smoke-test-macos-app`；
4. **明确非声明**：未 Developer ID 公证 ≠ 公开 Gatekeeper 分发包；ad-hoc 仅开发/本机。

## 7. 文档交付清单

| 文档 | 用途 |
|------|------|
| 本规格 | RC 边界与 residual |
| [2026-07-22-release-closeout.md](../plans/2026-07-22-release-closeout.md) | 任务勾选与出门标准 |
| [release-notes-rc-2026-07-22.md](../../acceptance/release-notes-rc-2026-07-22.md) | 产品发布说明 |
| [release-closeout-2026-07-22.md](../../acceptance/release-closeout-2026-07-22.md) | merge base、门禁、residual 现场记录 |
| README / docs/README / CHANGELOG | 状态与索引 |
| long-term-iteration-roadmap | 过时声明 |

## 8. 明确非目标

- 不实现 Developer ID 签名/公证；
- 不要求本机开启辅助功能后做真 VO 回归；
- 不重做 U5–U8/ST UI；
- 不推进 T6 能力增强或 UX-N 新体验波次；
- 不重启 Perfect Loop / wake / automation；
- 不因 residual 删减 AI/迁移/Blame/Finder 能力；
- 不自动打 GitHub Release / 不上传公证产物。

## 9. 后续波次挂牌（不实施）

| 代号 | 条件 | 内容 |
|------|------|------|
| **DX** | Developer ID + notary 凭据 | 真实签名/公证/Gatekeeper/干净机 |
| **A11Y** | AX 信任或人工 VO 环境 | 真 VoiceOver / 真实按键验收 |
| **T6+** | 产品选型 | AI/迁移/Release Notes 能力深化 |
| **UX-N** | 产品选型 | 跨页任务流、空态引导、大仓性能等 |

## 10. 收口记录

### 10.1 状态

- **完成**（2026-07-22）。门禁与 merge 细节见 [release-closeout-2026-07-22.md](../../acceptance/release-closeout-2026-07-22.md)。

### 10.2 U8/ST 边界继承

- Perfect Loop 保持终止态；
- inventory / H-tortoise 无能力状态变更；
- ST residual（独立 HSplitView、TCC a11y、Developer ID）继续诚实记录，不降级为「已解决」。
