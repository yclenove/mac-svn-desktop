# 工程收口与发布说明（RC）实现计划

> **面向 AI 代理的工作者：** 推荐使用 executing-plans 逐任务实现。步骤使用复选框（`- [x]` / `- [ ]`）跟踪进度。

**目标：** 在 ST 完成后做工程收口：merge `main`、发布说明、residual 矩阵、文档索引对齐，准备合入 `main`；不开发新功能、不重启 Perfect Loop。

**架构：** 文档驱动收口 + merge 对齐 + 既有门禁复跑；无新增产品能力。

**技术栈：** git merge、swift test、现有 packaging scripts、parity-coverage。

**规格：** `docs/superpowers/specs/2026-07-22-release-closeout-design.md`

**约束：**

- 不重启 Tortoise Perfect Loop / wake / heartbeat；
- inventory / H-tortoise 仅能力真变时改（本波默认不改）；
- merge 非 rebase；禁止 force-push `main`；
- 不伪造 Developer ID / 真 a11y 成功；
- 环境 unrestricted FS、approval never → 自主执行。

---

## 任务 1：RC 规格与计划落盘

- [x] 新增 `docs/superpowers/specs/2026-07-22-release-closeout-design.md`
- [x] 新增本计划文件
- [x] 在 `docs/README.md` 索引登记 RC 文档（状态随任务 4 更新为完成）

**出门：** 规格边界清晰；非目标与 residual 表齐全。

---

## 任务 2：merge `main` 到本分支

- [x] 记录 merge-base 与 ahead/behind
- [x] `git merge main`（允许 CHANGELOG 文档合并）
- [x] 保留 MainActor 通知回调安全写法
- [x] 合并后工作树可进入后续门禁

**出门：** 无未解决冲突；不丢失 main 崩溃修复。

---

## 任务 3：发布说明 + residual + roadmap 过时声明

- [x] `docs/acceptance/release-notes-rc-2026-07-22.md`
- [x] `docs/acceptance/release-closeout-2026-07-22.md`（含 residual 矩阵与 merge 记录）
- [x] `long-term-iteration-roadmap.md` 顶部过时声明
- [x] 根 README 分发段保持 0 身份诚实表述并链 residual/发布说明

**出门：** residual 单一真相；roadmap 不可再被当作未完成 T0–T5 真相。

---

## 任务 4：全量门禁 + 索引收口

- [x] 全量 `swift test`（含真实 SVN 49/49）
- [x] `python3 scripts/parity-coverage.py --fail-below 1.0`
- [x] `./scripts/build-macos-app.sh`
- [x] `./scripts/verify-macos-app.sh dist/SVNStudio.app`
- [x] `./scripts/smoke-test-macos-app.sh dist/SVNStudio.app`
- [x] `git diff --check`
- [x] 更新根 README / docs/README / CHANGELOG 为 RC 完成
- [x] 回填 closeout 文档门禁数字

**出门：** 全部门禁绿；索引与 CHANGELOG 一致。

---

## 任务 5：提交收口与合入准备

- [x] 中文 Conventional Commit 收口
- [x] 工作树干净
- [x] PR 描述模板写入 closeout 文档
- [x] 可选：`gh pr create`（尽力而为）

**建议提交：**

- 若 merge 产生独立 merge commit：保留 git merge 信息
- 文档收口：`docs(release): 完成合入 main 准备与发布说明（RC）`

**出门：** tip 可开 PR 合入 `main`；报告 commit SHA 与门禁结果。

---

## 非目标复查

- [x] 未实现公证
- [x] 未要求真 VO
- [x] 未改 inventory/H-tortoise
- [x] 未创建 wake/heartbeat
- [x] 未推进 T6 / UX-N

---

## 进度日志

| 时间 | 任务 | 结果 |
|------|------|------|
| 2026-07-22 | 1–5 | 见 acceptance/release-closeout-2026-07-22.md |
