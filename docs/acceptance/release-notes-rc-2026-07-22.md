# SVN Studio 发布说明（里程碑 RC · 2026-07-22）

| 项 | 内容 |
|----|------|
| 里程碑 | **RC**（Release Closeout / 工程收口） |
| 日期 | 2026-07-22 |
| 工作分支 | `feat/tortoise-parity-perfect-loop` |
| 版本号策略 | 里程碑 tip（**非**正式 semver `v1.0.0` 强制发版） |
| 分发声明 | **未** Developer ID 公证；本机构建包 **不是** Gatekeeper 公开分发包 |

## 1. 本里程碑包含什么

### 1.1 TortoiseSVN 对标完成

- 能力清单 inventory v2：**114/114（100%）**
- 五维：DUG 28/28、主命令 46/46、Show Log L01–L20、设置 S01–S13、Overlay 7/7
- Perfect Loop **GP.6 已停止**；不再创建 wake / sleeper / automation
- 验收证据：[H-tortoise-parity.md](H-tortoise-parity.md)、[parity-coverage.json](parity-coverage.json)

### 1.2 人本体验收口（Human UI + ST）

| 波次 | 范围 | 状态 |
|------|------|------|
| U5 | 变更工作区与全局弹窗关闭 | 完成 |
| U6 | 核心模式（历史/仓库/分支/冲突） | 完成 |
| U7 | 辅助工作流（属性/锁定/搁置/设置） | 完成 |
| U8 | 全局键盘、a11y 契约、动效、性能守卫 | 完成 |
| ST | Blame / AI / Git 迁移 / Release Notes 专业工具面 | 完成 |

### 1.3 工程收口（本 RC）

- 将 `main` 上通知授权 MainActor 崩溃修复合并入 parity 分支
- 发布说明、residual 单一矩阵、过时路线图声明
- 全量测试与 App 包装门禁复跑，准备合入 `main`

## 2. 本机构建与校验（开发者）

```bash
./scripts/build-macos-app.sh
./scripts/verify-macos-app.sh dist/SVNStudio.app
./scripts/smoke-test-macos-app.sh dist/SVNStudio.app
swift test
python3 scripts/parity-coverage.py --fail-below 1.0
```

产物默认：`dist/SVNStudio.app`（含 Finder Sync / Quick Look 扩展的包装流程以仓库脚本为准）。

## 3. 明确非声明（请勿误读）

| 说法 | 是否成立 |
|------|----------|
| Tortoise 对标 114/114 | ✅ |
| Human UI U5–U8 + ST 完成 | ✅ |
| 本机可构建并隔离启动冒烟 | ✅（脚本门禁） |
| 已 Developer ID 签名并公证 | ❌ 本机 0 签名身份 |
| 可在未关 Gatekeeper 的干净机直接运行 ad-hoc 包 | ❌ 未公证 |
| 真 VoiceOver 动态遍历 / 真实按键注入已在本机跑通 | ❌ `AXIsProcessTrusted=false` 时仍为 residual |

解除公证阻塞步骤见 [distribution-smoke-2026-07-15.md](distribution-smoke-2026-07-15.md) 与 [signing-and-notarization.md](../packaging/signing-and-notarization.md)。

## 4. Residual 摘要

详见 [release-closeout-2026-07-22.md](release-closeout-2026-07-22.md) 与 [RC 规格 §5](../superpowers/specs/2026-07-22-release-closeout-design.md)。

| 项 | 后续波次 |
|----|----------|
| Developer ID / 公证 / 干净机 | **DX**（需凭据） |
| 真 VO / 真实按键 | **A11Y**（需 TCC） |
| T6 产品深化 | **T6+**（需选型） |
| 新体验波次 | **UX-N**（需选型） |

## 5. 合入 `main`

- 策略：`feat/tortoise-parity-perfect-loop` → PR → `main`（禁止 force-push `main`）
- **已完成**：[PR #2](https://github.com/yclenove/mac-svn-desktop/pull/2) MERGED
- merge commit：`89dc6a5`
- PR 描述与门禁明细见 [closeout 记录](release-closeout-2026-07-22.md)
