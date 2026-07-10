# MacSVN SRS 缺口补齐长程 Loop Backlog

| 项 | 内容 |
|----|------|
| 创建日期 | 2026-07-10 |
| 上游 | `docs/01-requirements.md`（SRS v1.1）、`docs/06-innovative-features.md` |
| 前序里程碑 | `docs/superpowers/plans/2026-07-10-long-loop-backlog.md`（Wave A–H 已完成：主路径 UI 接线） |
| 基线分支 | `feat/long-loop-full-delivery` @ `f7bc62d`（或合入后的 `main`） |
| 建议工作分支 | `feat/srs-gap-full-delivery`（已从交付 tip 切出） |
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

### 唤醒协议（强制，2026-07-10 根因修复）

**禁止** `while true; do sleep N; echo WAKE; done` 无限心跳。

原因：无限循环只往终端写行；会话空闲或上下文摘要后，`notify_on_output` 订阅会失效，终端里继续刷 WAKE 但**代理不会被拉起**——表现为「停了十几二十分钟」。

**正确做法（每轮结束必须执行）：**

1. 本轮功能做完并 push 后，用 **一次性** Shell（`block_until_ms: 0` + `notify_on_output`）挂下一枪：
   ```bash
   sleep 120
   echo 'AGENT_LOOP_WAKE_macsvn_srs_gap {"prompt":"Continue MacSVN SRS-gap long-loop on feat/srs-gap-full-delivery: read docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md, implement first unchecked item with TDD, swift test, commit, push, update backlog+CHANGELOG; then re-arm one-shot wake (sleep 120 + echo AGENT_LOOP_WAKE_macsvn_srs_gap). Do not use while-true loops."}'
   ```
2. 唤醒后：读最新 WAKE 行里的 `prompt` → 干活 → **再挂下一发 one-shot**（重新建立订阅）。
3. 若发现仍有 `while true` 的旧进程：先 `pkill -f AGENT_LOOP_WAKE_macsvn_srs_gap` 再挂 one-shot。
4. 用户说停止：杀掉 sleeper，**不要**再挂下一发。

**建议间隔：** 120 秒（实现轮次重时可在本轮末尾改成 180–300）。

---

## Backlog（严格按序）

### Wave R — 验收基线与合入准备

- [x] **R1** 按 `docs/acceptance/H1-manual-checklist.md` 用真实 WC 跑通 P1 日常流（中文 commit）；失败项记入本文件「阻塞日志」并开对应修复条目
- [x] **R2** 从交付 tip 创建/确认 `feat/srs-gap-full-delivery`，README 功能矩阵改为「缺口补齐中」并链到本文档
- [x] **R3** 缺口对照表冻结：本文件 §0 与 SRS FR 编号一致（若发现新缺口只追加，不删已完成项）

### Wave S — P1/P2 体验缺口（高频）

- [x] **S1** 变更页：树视图 / 平铺切换完整可用（FR-ST-02）
- [x] **S2** Update 结果含冲突时一键跳转冲突页（FR-UP-02）
- [x] **S3** 日志：作者/日期/关键字过滤（FR-LG-03）
- [x] **S4** 日志：查看该版本 Diff、更新到该版本、还原文件（FR-LG-04）
- [x] **S5** 任意两 revision 文件 Diff（从日志/仓库发起）（FR-DF-03）
- [x] **S6** WC 深度调整 `update --set-depth` UI（FR-WC-06）
- [x] **S7** 认证失败弹窗 + Keychain/`--password-from-stdin` 路径验收（FR-AU-01,02）
- [x] **S8** 设置页补齐：分支布局、外部 Diff 工具配置并接到 Diff 页（FR-SE-01 / FR-DF-05）

### Wave T — P2/P4 仓库与冲突补齐

- [x] **T1** 拖拽添加工作副本（FR-WC-01）
- [x] **T2** `svn:ignore` 忽略配置 UI（FR-ST-05）
- [x] **T3** Side-by-side Diff（FR-DF-02）
- [x] **T4** 仓库浏览器远端写：mkdir / 删除 / 复制 / 移动（需提交说明）（FR-RB-06）
- [x] **T5** 分支页展示 `svn:mergeinfo`（接 `MergeInfoViewModel`）（FR-BR-05）
- [x] **T6** 属性冲突解决 UI（FR-CF-07）

### Wave U — P5/P6 创新能力补齐

- [x] **U1** Git 迁移：authors AI 批量推断 + 人工复核（FR-GM-03）
- [x] **U2** 迁移完成 revision 对账报告展示与失败阻断（FR-GM-04 / NFR-14）
- [x] **U3** AI Release Notes 页/入口（接 `AIReleaseNotesGenerator`）（FR-AI-05）
- [x] **U4** Blame 页接入演化解释（接 `AIBlameEvolutionExplainer`）（FR-AI-06）
- [x] **U5** AI Chat：确认门通过后真实执行低危/高危写工具（仍须确认+审计）（FR-AI-04 / NFR-13）
- [x] **U6** ⌘K：无匹配动作时转入 AI Chat 并带上 query（FR-EX-04）
- [x] **U7** 菜单栏：FSEvents（或等价）本地变更近实时刷新（FR-EX-03）
- [x] **U8** 团队活动：按日提交热力图可视化（FR-EX-06）

### Wave V — 系统扩展与发布

- [x] **V1** Xcode 包装工程（或等价）可构建 `.app`，嵌入 SwiftPM 产物
- [x] **V2** Finder Sync `.appex` 可安装：角标 + 右键深链（FR-EX-05）；更新 `docs/extensions/FinderSync/`
- [x] **V3** Quick Look `.appex` 可安装：空格预览 Diff（FR-EX-08）；更新 `docs/extensions/QuickLook/`
- [ ] **V4** 签名 / 公证流程文档 + 脚本骨架（P4 验收）；干净机冒烟步骤写入验收清单
- [ ] **V5** 全量 `swift test` + 扩展冒烟；FF 合入 `main`；README 功能矩阵全部改为可验收状态

---

## 进度日志

| 时间 | 条目 | Commit | 验证 |
|------|------|--------|------|
| 2026-07-10 13:11 | 文档创建 | 44240be | 缺口梳理完成；Loop 未启动 |
| 2026-07-10 13:19 | R1–R3 / S1–S5 / S8 / T3 + 火山方舟接入 | a6f0f5b | `swift test --filter MacSvnApp` 10 passed；Ark `doubao-seed-code` HTTP 200；H1 CLI 冒烟通过 |
| 2026-07-10 13:20 | S6 / T1 | 81b0d8a | set-depth UI + 拖拽添加 WC；MacSvnApp 10 passed |
| 2026-07-10 13:30 | S7 / T2 | 5aea092 | 认证弹窗+password-from-stdin 测试；变更页忽略选中写 svn:ignore |
| 2026-07-10 13:58 | T4 / T5 / T6 | d686e47 | 远端写 UI；分支 mergeinfo；属性冲突 VM+UI；定向测试 30 passed |
| 2026-07-10 14:01 | U1 | 82427f7 | AI authors 推断 + 待复核标记；12 tests passed |
| 2026-07-10 14:06 | U2 | ee01a0e | 对账报告 UI + 失败阻断同步；源分析保留 sourceRevisions |
| 2026-07-10 14:13 | 唤醒协议 | a227fc6 | 废弃 while-true；改为 one-shot re-arm |
| 2026-07-10 14:16 | U3 | 0a066a6 | Release Notes 页+日志入口；one-shot 唤醒验证通过 |
| 2026-07-10 14:23 | U4 | 73ee382 | Blame 选区 AI 演化解释；4 tests passed |
| 2026-07-10 14:28 | U5 | 1247aac | 确认门后真实执行写工具+审计；10 tests passed |
| 2026-07-10 14:32 | U6 | 333206b | ⌘K 无匹配 handoff query→AI Chat 自动发送 |
| 2026-07-10 14:40 | U7 | a3e1ef4 | FSEvents + debounce 刷新；测试禁用通知权限；DispatchQueue 挂流 |
| 2026-07-10 14:46 | U8 | e3b82c9 | 日历热力图 Builder+UI；锚定今天；周标签跟随 firstWeekday |
| 2026-07-10 14:54 | V1 | 2e4f952 | MacSVN.xcodeproj + build-macos-app.sh；两条路径 verify 通过 |
| 2026-07-10 15:07 | V2 | 9c0f765 | Finder Sync appex 嵌入；roots 导出；深链 Builder；verify 通过 |
| 2026-07-10 15:14 | V3 | （本轮） | Quick Look appex 嵌入；PreviewTextBuilder；verify 通过 |

## 阻塞日志

| 时间 | 条目 | 阻塞 | 处理 |
|------|------|------|------|
| 2026-07-10 14:11 | 唤醒链路 | 无限 `while` 心跳终端有 WAKE 但代理不续跑 | 改为每轮结束 one-shot `sleep+echo` + `notify_on_output`；已杀旧进程；协议写入本文「唤醒协议」 |

---

## 启动 Loop 命令（参考）

在仓库根目录切到 `feat/srs-gap-full-delivery` 后，由 **Cursor Agent 在每轮结束** 挂下一发（不要手写 while）：

```bash
# 一次性唤醒（必须由 Agent Shell 以 block_until_ms=0 + notify_on_output 启动）
sleep 120
echo 'AGENT_LOOP_WAKE_macsvn_srs_gap {"prompt":"Continue MacSVN SRS-gap long-loop on feat/srs-gap-full-delivery: read docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md, implement first unchecked item with TDD, swift test, commit, push, update backlog+CHANGELOG; then re-arm one-shot wake. Do not use while-true."}'
```

停止条件：本文件全部 `[x]`，或用户明确要求停止（杀掉 sleeper 且不再挂下一发）。
