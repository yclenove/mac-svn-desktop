# H-Tortoise 手工验收清单（小乌龟全量对标）

| 项 | 内容 |
|----|------|
| 产品 | SVN Studio |
| 关联 | [`tortoisesvn-feature-inventory.md`](../superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md)、[`tortoise-parity-perfect-loop.md`](../superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md) |
| 覆盖率 | 跑 `python3 scripts/parity-coverage.py` → [`parity-coverage.json`](parity-coverage.json) |
| 规则 | 对应 Wave 功能落地后，在**真实 WC**上勾选；勾选前须把 inventory 对应行升为 ✅ |

> T0 节为门禁/骨架，可在无业务对话框时勾选。T1 起必须真实 WC。

---

## 环境（每次验收前）

- [ ] `swift run MacSvnDesktopApp` 或 `dist/SVNStudio.app` 可启动
- [ ] 本机 `svn` ≥ 1.14（或设置中自定义路径）
- [ ] 准备可写测试 WC（含若干修改/未版本文件更佳）
- [ ] 空闲时 Activity Monitor 中 SVNStudio **无持续 100% CPU**（AttributeGraph 门禁）

---

## T0 — 门禁与骨架

- [x] T0.1：大 Diff / 变更工作区不卡死；嵌入 Diff 为单块文本
- [x] T0.2：`SvnCommandCatalog` 可枚举 #1–46 + L01–L20（单测或调试打印）
- [x] T0.3：`Navigator.perform` 对未接线命令提示「未实现」，不假装成功
- [x] T0.4：长耗时操作可取消（或单测证明取消 → `SvnError.cancelled`）
- [x] T0.5：`python3 scripts/parity-coverage.py` 成功写出 JSON
- [x] T0.6：本清单文件存在且按 Wave 分节
- [x] **G0**：全量 `swift test` 绿；覆盖率脚本跑通

---

## T1 — 日常闭环（对话框级）

- [x] CFM：本地 status、列、刷新（#8）
- [x] CFM：Check Repository（`status -u`）、颜色（#8）
- [x] CFM：Repair Move / Repair Copy（#45）
- [x] Commit：勾选、未版本→add、Keep locks、说明历史、单项 Diff/Revert（#4）
- [x] Update：同仓多路径统一 revision（#2）
- [ ] Diff：BASE、双文件、外置查看器入口（#5）
- [ ] Add / Delete / Revert（勾选）/ Cleanup（#14,#17,#18,#29）
- [ ] Rename（#13）
- [ ] Ignore 文件/通配（#32）
- [ ] SVN Copy / Move 向导（#36）
- [ ] 变更树右键 + ⌘K 可达日常命令子集
- [ ] **G1**：inventory T1 范围全 ✅；本节全部勾选；`swift test` 绿

---

## T2 — 进阶日常 + 仓库

- [ ] Checkout / Update to revision（depth、ignore-externals）（#1,#3）
- [ ] Show Log：过滤、stop-on-copy、Next/All、Actions 列（#7, L18–L20）
- [ ] 日志右键 L01–L08、L09–L12、L14、L17（见 inventory §5）
- [ ] Edit Conflicts + Resolved（#11,#12）
- [ ] Lock / Unlock / Break lock（#19–21）
- [ ] Branch-Tag / Switch / Merge+dry-run（#22–24）
- [ ] Export / Import / Import in Place / Relocate / Remove from VC（#26,#27,#30,#43,#44）
- [ ] Create / Apply Patch（#33,#34）
- [ ] Properties + Blame 悬停（#35,#31）
- [ ] Repo Browser 远端写 + 高危确认（#10）
- [ ] Filename case conflict repair（#46）
- [ ] Progress Auto-close 基础策略（§4.7）
- [ ] **G2**：inventory T2 范围全 ✅；本节勾选；全量测试绿

---

## T3 — 专业能力

- [ ] Diff with URL（#6）
- [ ] Revision Graph（#9）
- [ ] Change Lists（#38）
- [ ] Externals（#39）
- [ ] 官方 Shelve 对齐（#37）
- [ ] Merge reintegrate + 日志 Merge revision to…（#25,#42, L13）
- [ ] Create Repository Here（#28）
- [ ] Delete keep local / Delete unversioned（#15,#16）
- [ ] Compare revisions / Blame differences（#40, L03）
- [ ] 日志 Edit author/message + rev props（L15,L16）
- [ ] 日志统计 / 离线缓存（L18 剩余, S13）
- [ ] **G3**：inventory T3 全 ✅；本节勾选；全量测试绿

---

## T4 — Shell 集成

- [ ] Overlay 全状态（含 locked / needs-lock / ignored / depth / externals / switched 等）
- [ ] Status Cache 三模式（Default / Shell / None）（S08）
- [ ] 包含/排除路径；可选角标种类
- [ ] Finder 右键：普通 +「更多命令…」（扩展菜单）
- [ ] 多选批量
- [ ] 属性页等价（revision/作者/URL/锁/属性摘要）
- [ ] Context Menu 设置（S02）
- [ ] **G4**：Overlay + S02/S08 ✅；Finder 冒烟；全量测试绿

---

## T5 — 设置 / 钩子 / 品牌 / 分发

- [ ] 设置 IA：General / Dialogs / Colours / Network / External / Saved Data（S01,S03–S06,S09–S11）
- [ ] 客户端钩子：pre-commit、post-update（S11）
- [ ] Bugtraq / `bugtraq:*` / 关键 `tsvn:*`（S12）
- [ ] 清认证缓存 / 清日志缓存
- [ ] 外置 Diff/Merge/Blame 按扩展名（S10）
- [ ] App Icon / 空态 / 关于页
- [ ] `SVNStudio.app` 冒烟；公证（有证书则做）
- [ ] **G5**：设置全表 ✅；本节勾选；全量测试绿

---

## GP — 完美收口

- [ ] `python3 scripts/parity-coverage.py --fail-below 1.0` 通过（100%）
- [ ] 无用户可见「未实现」stub
- [ ] 全量 `swift test` 绿
- [ ] 本文件 T0–T5 全部勾选
- [ ] README 功能矩阵与 inventory 对齐
- [ ] CHANGELOG 收口「Tortoise 全量对标完成」
- [ ] 停止 `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` 唤醒

---

## 记录

| 日期 | 验收人 | Wave | 结果 | 备注 |
|------|--------|------|------|------|
| 2026-07-10 | agent | T0/G0 | 通过 | `swift test` 529 绿；parity-coverage 0/114 基线；自动化门禁项已勾 |
