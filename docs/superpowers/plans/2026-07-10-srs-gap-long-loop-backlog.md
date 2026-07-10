# MacSVN SRS 缺口补齐长程 Loop Backlog

| 项 | 内容 |
|----|------|
| 创建日期 | 2026-07-10 |
| 上游 | `docs/01-requirements.md`（SRS v1.1）、`docs/06-innovative-features.md` |
| 前序里程碑 | `docs/superpowers/plans/2026-07-10-long-loop-backlog.md`（Wave A–H 已完成：主路径 UI 接线） |
| 基线分支 | `feat/long-loop-full-delivery` @ `f7bc62d`（或合入后的 `main`） |
| 建议工作分支 | `feat/srs-gap-full-delivery`（从最新交付分支切出） |
| 目标 | **按 SRS 逐条补齐缺口**，达到「规划功能可验收」而非仅「有接线」 |
| 停止条件 | 本文件全部 `[x]`，全量 `swift test` 绿，H1 真实 WC 抽检通过，CHANGELOG 记录完成 |

---

## 0. 现状梳理（相对 SRS）

### 0.1 已基本到位（主路径可演示）

| 域 | FR 范围 | 说明 |
|----|---------|------|
| WC / 变更 / Update / Commit / Unified Diff / Log | FR-WC-01~04,07；FR-ST-01~04 大部；FR-UP-01；FR-CM-* 大部；FR-DF-01,04；FR-LG-01,02 | App UI 已接 Core |
| 仓库浏览器 / Checkout / 分支 / Merge | FR-RB-01~05,07；FR-WC-05,06 大部；FR-BR-01~04 | 有 UI；深度/浅检出需对照验收 |
| 冲突三路 + 树冲突 | FR-CF-01~06,08 | 有 UI |
| Blame / 属性 / 锁 / 搁置 / 提交守护 | FR-BL-01 大部；FR-PR-01；FR-LK-01；FR-EX-01,02 | 有 UI |
| Git 迁移五步 + 同步 | FR-GM-01~05 大部 | 有向导；AI authors / 对账报告展示可能不全 |
| 菜单栏 / 深链 / CLI | FR-EX-03 大部；FR-EX-07 | MenuBarExtra + Navigator 已接 |
| AI Provider / Chat / 提交 AI / 冲突 AI / ⌘K / 团队 | FR-AI-00~04 大部；FR-EX-04,06 | 有 UI；Agent 写操作确认后未真正执行 svn 写 |

### 0.2 明确缺口（本 Loop 要做）

| 优先级 | 缺口 | 对应 FR | 现状 |
|--------|------|---------|------|
| P0 | 真实 WC 手工验收闭环 | 验收标准 P1–P3 | 仅有清单，未跑通 |
| P0 | 变更树/平铺切换 | FR-ST-02 | 筛选有，树视图可能不全 |
| P0 | Update 冲突跳转冲突页 | FR-UP-02 | 需接线 |
| P1 | 日志过滤 + 从日志 Diff/Update/还原 | FR-LG-03,04 | UI 缺 |
| P1 | 日志/仓库远端 revision Diff | FR-DF-03 | UI 缺 |
| P1 | Checkout 后 set-depth | FR-WC-06 | Core 可能有，App 需确认接线 |
| P1 | 凭据弹窗 / 认证失败重试 | FR-AU-01,02 | 需核对 UI |
| P1 | 设置：分支布局 + 外部 Diff | FR-SE-01 | 设置页字段不全 |
| P2 | Side-by-side Diff | FR-DF-02 | 未做 |
| P2 | 忽略配置 UI | FR-ST-05 | 未做 |
| P2 | 远端写操作（mkdir/删/复制/移动） | FR-RB-06 | 未做 |
| P2 | mergeinfo 展示 | FR-BR-05 | Core 有，App 未接 |
| P2 | 属性冲突 UI | FR-CF-07 | 未做 |
| P2 | 拖拽添加 WC | FR-WC-01 | 仅文件选择器 |
| P2 | AI Release Notes | FR-AI-05 | Core 有，App 未接 |
| P2 | Blame 演化解释 | FR-AI-06 | Core 有，App 未接 |
| P2 | Authors AI 批量推断 | FR-GM-03 | 未接 |
| P2 | 迁移 revision 对账报告展示 | FR-GM-04 / NFR-14 | 需确认 UI |
| P2 | Chat 写操作确认后真实执行 | FR-AI-04 / NFR-13 | 当前只记审计 |
| P2 | ⌘K 自然语言转 AI | FR-EX-04 | 仅动作/文件/日志 |
| P3 | 菜单栏 FSEvents 实时刷新 | FR-EX-03 | 仅轮询 |
| P3 | 团队热力图可视化 | FR-EX-06 | 现为列表 |
| P3 | Finder Sync 可安装 .appex | FR-EX-05 | 仅骨架文档 |
| P3 | Quick Look 可安装 .appex | FR-EX-08 | 仅骨架文档 |
| P3 | 签名 / 公证 / 干净机运行 | P4 验收 | 未做 |
| P3 | 合入 `main` + 发布说明 | 工程收口 | 未做 |

### 0.3 明确不做（禁止本 Loop 实现）

见 SRS §5：服务器管理、通用编辑器、Win/Linux、属性驱动工作流、BFG 级历史改写、自研托管大模型。

---

## Loop 规则（每轮必须遵守）

1. 读取本文件，取**第一个未完成** `[ ]` 作为本轮唯一目标（可同 Wave 内合并极小相关项，但须在进度日志写清）。
2. 在 `feat/srs-gap-full-delivery` 上工作；不存在则从当前交付 tip 创建并 push。
3. TDD：先测 → 实现 → `swift test`（相关 filter；收尾前全量）。
4. 中文 commit；勾 backlog；更新 `CHANGELOG.md`；`git push`。
5. **禁止把「文档骨架」勾成「可安装扩展」**——G7/G8 类条目必须能在目标形态下验证（Xcode 包装工程或明确的安装步骤）。
6. **禁止把「清单文件」勾成「手工验收完成」**——真实 WC 跑通后才能勾 R1。
7. Core 已有能力优先 **App 接线**；没有 Core 再补服务/VM。
8. 全部 `[x]` 后：全量测试、更新 README 功能矩阵、停止 loop。

**建议唤醒间隔：** 3–5 分钟（实现轮次重，不必 2 分钟空转）。

---

## Backlog（严格按序）

### Wave R — 验收基线与合入准备

- [ ] **R1** 按 `docs/acceptance/H1-manual-checklist.md` 用真实 WC 跑通 P1 日常流（中文 commit）；失败项记入本文件「阻塞日志」并开对应修复条目
- [ ] **R2** 从交付 tip 创建/确认 `feat/srs-gap-full-delivery`，README 功能矩阵改为「缺口补齐中」并链到本文档
- [ ] **R3** 缺口对照表冻结：本文件 §0 与 SRS FR 编号一致（若发现新缺口只追加，不删已完成项）

### Wave S — P1/P2 体验缺口（高频）

- [ ] **S1** 变更页：树视图 / 平铺切换完整可用（FR-ST-02）
- [ ] **S2** Update 结果含冲突时一键跳转冲突页（FR-UP-02）
- [ ] **S3** 日志：作者/日期/关键字过滤（FR-LG-03）
- [ ] **S4** 日志：查看该版本 Diff、更新到该版本、还原文件（FR-LG-04）
- [ ] **S5** 任意两 revision 文件 Diff（从日志/仓库发起）（FR-DF-03）
- [ ] **S6** WC 深度调整 `update --set-depth` UI（FR-WC-06）
- [ ] **S7** 认证失败弹窗 + Keychain/`--password-from-stdin` 路径验收（FR-AU-01,02）
- [ ] **S8** 设置页补齐：分支布局、外部 Diff 工具配置并接到 Diff 页（FR-SE-01 / FR-DF-05）

### Wave T — P2/P4 仓库与冲突补齐

- [ ] **T1** 拖拽添加工作副本（FR-WC-01）
- [ ] **T2** `svn:ignore` 忽略配置 UI（FR-ST-05）
- [ ] **T3** Side-by-side Diff（FR-DF-02）
- [ ] **T4** 仓库浏览器远端写：mkdir / 删除 / 复制 / 移动（需提交说明）（FR-RB-06）
- [ ] **T5** 分支页展示 `svn:mergeinfo`（接 `MergeInfoViewModel`）（FR-BR-05）
- [ ] **T6** 属性冲突解决 UI（FR-CF-07）

### Wave U — P5/P6 创新能力补齐

- [ ] **U1** Git 迁移：authors AI 批量推断 + 人工复核（FR-GM-03）
- [ ] **U2** 迁移完成 revision 对账报告展示与失败阻断（FR-GM-04 / NFR-14）
- [ ] **U3** AI Release Notes 页/入口（接 `AIReleaseNotesGenerator`）（FR-AI-05）
- [ ] **U4** Blame 页接入演化解释（接 `AIBlameEvolutionExplainer`）（FR-AI-06）
- [ ] **U5** AI Chat：确认门通过后真实执行低危/高危写工具（仍须确认+审计）（FR-AI-04 / NFR-13）
- [ ] **U6** ⌘K：无匹配动作时转入 AI Chat 并带上 query（FR-EX-04）
- [ ] **U7** 菜单栏：FSEvents（或等价）本地变更近实时刷新（FR-EX-03）
- [ ] **U8** 团队活动：按日提交热力图可视化（FR-EX-06）

### Wave V — 系统扩展与发布

- [ ] **V1** Xcode 包装工程（或等价）可构建 `.app`，嵌入 SwiftPM 产物
- [ ] **V2** Finder Sync `.appex` 可安装：角标 + 右键深链（FR-EX-05）；更新 `docs/extensions/FinderSync/`
- [ ] **V3** Quick Look `.appex` 可安装：空格预览 Diff（FR-EX-08）；更新 `docs/extensions/QuickLook/`
- [ ] **V4** 签名 / 公证流程文档 + 脚本骨架（P4 验收）；干净机冒烟步骤写入验收清单
- [ ] **V5** 全量 `swift test` + 扩展冒烟；FF 合入 `main`；README 功能矩阵全部改为可验收状态

---

## 进度日志

| 时间 | 条目 | Commit | 验证 |
|------|------|--------|------|
| 2026-07-10 13:11 | 文档创建 | （本提交） | 缺口梳理完成；Loop 未启动 |

## 阻塞日志

| 时间 | 条目 | 阻塞 | 处理 |
|------|------|------|------|
| （空） | | | |

---

## 启动 Loop 命令（参考）

在仓库根目录：

```bash
# 建议分支
git checkout feat/long-loop-full-delivery
git pull
git checkout -b feat/srs-gap-full-delivery
git push -u origin HEAD

# 心跳（示例：每 180 秒）；实现代理读取本文件第一个 [ ]
while true; do
  sleep 180
  echo 'AGENT_LOOP_WAKE_macsvn_srs_gap {"prompt":"Continue MacSVN SRS-gap long-loop on feat/srs-gap-full-delivery: read docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md, implement first unchecked item with TDD, swift test, commit, push, update backlog+CHANGELOG; do not stop until all items done."}'
done
```

停止条件：本文件全部 `[x]` 或用户明确要求 kill loop。
