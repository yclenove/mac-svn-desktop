# RC 工程收口现场记录（2026-07-22）

| 项 | 内容 |
|----|------|
| 波次 | Release Closeout **RC** |
| 分支 | `feat/tortoise-parity-perfect-loop` |
| 规格 | [2026-07-22-release-closeout-design.md](../superpowers/specs/2026-07-22-release-closeout-design.md) |
| 计划 | [2026-07-22-release-closeout.md](../superpowers/plans/2026-07-22-release-closeout.md) |
| 发布说明 | [release-notes-rc-2026-07-22.md](release-notes-rc-2026-07-22.md) |

## 1. Merge 对齐

| 项 | 值 |
|----|-----|
| 收口前 tip | `5bf4bd6`（ST 完成） |
| `main` tip | `0de8490`（通知授权 MainActor 修复） |
| merge-base（合并后） | `0de8490`（`main` 已为祖先） |
| merge commit | `19fd174` `chore: 合并 main 通知授权 MainActor 修复到 parity 分支` |
| 合并后 ahead/behind `main` | ahead ~186 / behind **0** |
| 代码 diff 于 merge | 无（菜单栏安全写法已同源；ort 策略空树合并） |
| inventory / H-tortoise | **未修改** |

## 2. Residual 矩阵（单一真相）

| Residual | 现场状态 | 本波处理 |
|----------|----------|----------|
| Developer ID / notarytool / 干净机 Gatekeeper | `security find-identity -v -p codesigning` → **0 valid identities** | 仅文档；不伪造成功 |
| VoiceOver 动态遍历 / 真实按键注入 | `AXIsProcessTrusted=0` | 仅文档；契约测试保持 |
| 独立 Blame/AI/Commit/Diff 单层 HSplitView | ST 允许 + 源码门禁 | 仅文档；禁止嵌套回退 |
| long-term-iteration-roadmap 旧 `[ ]` | 与 114/114 矛盾 | 已加 **历史归档** 顶栏声明 |

## 3. 门禁结果

> 下列数字在任务 4 全量复跑后回填。

| 门禁 | 结果 |
|------|------|
| `swift test`（全量） | **1150/1150** 通过（0 failures） |
| 真实 SVN 集成 `SvnCliBackendIntegrationTests` | **49/49** 通过 |
| `python3 scripts/parity-coverage.py --fail-below 1.0` | **114/114（100%）** |
| `./scripts/build-macos-app.sh` | OK → `dist/SVNStudio.app` |
| `./scripts/verify-macos-app.sh dist/SVNStudio.app` | OK |
| `./scripts/smoke-test-macos-app.sh dist/SVNStudio.app` | OK（隔离 HOME 启动稳定性） |
| `git diff --check` | OK |

## 4. 文档交付

- [x] RC 规格 / 计划
- [x] 发布说明
- [x] 本 closeout 记录
- [x] roadmap 过时声明
- [x] README / docs/README / CHANGELOG（任务 4 同步）

## 5. PR 描述模板（中文）

**标题：** `docs(release): 完成合入 main 准备与发布说明（RC）`

**正文：**

```markdown
## 范围
- 工程收口 Wave RC：merge main、发布说明、residual 矩阵、文档索引对齐
- 包含 ST 完成以来的 Human UI / Tortoise 114/114 全部历史（相对 main）

## 测试矩阵
- 全量 swift test：见 docs/acceptance/release-closeout-2026-07-22.md
- 真实 SVN 49/49
- parity-coverage 114/114
- build / verify / smoke App 脚本
- git diff --check

## Residual（诚实）
- Developer ID / 公证：本机 0 身份，未做真实公证
- VoiceOver / 真实按键：AX 未信任时仍为 residual
- 独立专业页单层 HSplitView：ST 已门禁，禁止嵌套

## 非范围
- 不实现公证（DX）
- 不做真 a11y 实机（A11Y）
- 不推进 T6 产品增强 / 新体验波次
- 不重启 Tortoise Perfect Loop

## 合入说明
- 禁止 force-push main
- 本分支已 merge main（behind 0）
```

## 6. 可选远程动作

| 动作 | 状态 |
|------|------|
| `gh pr create` | 任务 5 尽力而为 |
| GitHub Release / 公证上传 | **不做** |

## 7. 合入 main（完成）

| 项 | 值 |
|----|-----|
| PR | https://github.com/yclenove/mac-svn-desktop/pull/2 |
| 状态 | **MERGED** |
| merge commit | `89dc6a5` `合并工程收口 RC：parity 分支合入 main` |
| 合入时间（UTC） | 2026-07-21T16:58:16Z |
| 本地 `main` tip | 与 `origin/main` 一致 `89dc6a5` |
| 策略 | merge commit（非 squash / 非 rebase `main`） |

