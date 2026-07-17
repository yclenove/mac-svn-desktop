# U7 辅助工作流 UI 会话交接

> 更新时间：2026-07-17
> 用途：下一 Codex session 从 U7 任务 6 继续，不重复任务 5，不重启已结束的 Tortoise Perfect Loop。

## 1. 当前快照

| 项 | 状态 |
|----|------|
| 仓库 | `/Users/yangchao/Desktop/hlkj/newworkspace/aicoding/mac-svn-desktop` |
| 分支 | `feat/tortoise-parity-perfect-loop` |
| 功能基线 | `59096b5 feat(UI): 统一辅助任务反馈与弹窗状态（U7 任务 5/6）` |
| 已完成切片 | U7 任务 1–5 |
| 下一切片 | U7 任务 6：全量验证、真实窗口修正与文档收口 |
| 阻塞 | 无 |
| 可运行 App | `dist/SVNStudio.app` |

功能提交完成后工作树为干净状态。本文应作为单独的 `docs:` 提交存在；下一 session 先用 `git status --short --branch` 复核，不要假设或清理用户新增改动。

## 2. 真相源

- U7 执行计划：[`2026-07-15-human-centered-auxiliary-workflows-ui.md`](2026-07-15-human-centered-auxiliary-workflows-ui.md)
- U7 设计规格：[`2026-07-15-human-centered-auxiliary-workflows-ui-design.md`](../specs/2026-07-15-human-centered-auxiliary-workflows-ui-design.md)
- Tortoise 能力清单：[`2026-07-10-tortoisesvn-feature-inventory.md`](../specs/2026-07-10-tortoisesvn-feature-inventory.md)
- Tortoise 长程记录：[`2026-07-11-codex-tortoise-parity-long-loop.md`](2026-07-11-codex-tortoise-parity-long-loop.md)

Tortoise Perfect Loop 已在 GP.6 进入终止态，覆盖率为 `114/114`。U7 是后续 Human UI 长程工作，不得重新执行旧 Loop、创建 wake token，或把完成 U7 误报为整个 Human UI 长程目标完成。

## 3. 任务 5 已交付内容

### 3.1 统一反馈

- 增加共享 `progress`、`success`、`warning`、`failure` 反馈模型和固定高度视图。
- 图标与语义颜色互异，不以颜色作为唯一信息。
- 用户可读摘要遵循 SwiftUI `locale`；英文动态格式与错误摘要已本地化。
- 原始 SVN 诊断通过 tooltip 保留，避免主界面直接铺满命令输出。
- Properties、Locks、Shelve、Settings 已迁移到共享反馈。

### 3.2 弹窗关闭与防重入

- `macSvnDismissibleSheet(preventsDismissal:onDismissalBlocked:)` 统一右上角关闭、Escape 和底部取消。
- dirty 弹窗的三种关闭入口统一进入“放弃未保存更改”确认。
- busy 弹窗禁止关闭、系统交互绕过和重复提交。
- 外部定义、获取锁、创建 Shelf、Patch 均保存展示时的初始草稿快照。
- 获取锁在 sheet 内执行时，成功才关闭；失败保留输入与错误反馈。
- “关闭锁前对话框”设置控制的无 sheet 快路径必须保留，不能为了统一交互强制弹窗。
- 全仓源码门禁覆盖 `28` 个 sheet 与 `4` 个 popover。

### 3.3 并发与恢复修正

- `LockViewModel` 保留项目属性原始诊断，并用 generation 与 transaction failure version 阻止旧请求覆盖新状态。
- 锁工具栏刷新同时刷新项目属性与锁记录，可从错误状态真实恢复。
- Lock 并发测试改为 actor gate，不依赖毫秒级 `Task.sleep`。
- Shelf 官方加载失败时，本地快照预览仍重新加载。
- Properties 普通刷新或切换目标会清除陈旧反馈；命令来源和 externals 部分失败反馈按需保留。
- externals 属性保存成功但 update 失败时推进 baseline，不再误报“未保存”。
- Settings Finder 同步失败后保持 dirty 是任务 4 的既定重试语义，不要改成保存失败后清空 dirty。

## 4. 验证证据

2026-07-17 基于功能基线 `59096b5` 完成独立验证：

| 门禁 | 结果 |
|------|------|
| `swift test --quiet` | `1114/1114` 通过，0 failures |
| 真实 SVN 集成测试 | `49/49` 通过 |
| `./scripts/build-macos-app.sh` | Release 构建成功，生成 `dist/SVNStudio.app` |
| `./scripts/verify-macos-app.sh dist/SVNStudio.app` | OK |
| `./scripts/smoke-test-macos-app.sh dist/SVNStudio.app` | 隔离 HOME 启动稳定性通过 |
| `plutil -lint Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings` | OK |
| `git diff --check` | 通过，无输出 |
| 规格审查 | `0 Critical / 0 Important / 0 Minor` |
| 代码质量复核 | `0 Critical / 0 Important / 0 Minor`，相关门禁 `22/22` |

Tortoise inventory 与 `docs/acceptance/H-tortoise-parity.md` 没有能力状态变化，因此任务 5 未修改二者。

## 5. 任务 5 关键文件

- `Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift`
- `Sources/MacSvnApp/Features/MacSvnAuxiliaryWorkflowPresentation.swift`
- `Sources/MacSvnApp/Features/MacSvnPropertiesView.swift`
- `Sources/MacSvnApp/Features/MacSvnLocksView.swift`
- `Sources/MacSvnApp/Features/MacSvnShelveView.swift`
- `Sources/MacSvnApp/Features/MacSvnSettingsView.swift`
- `Sources/MacSvnCore/ViewModels/LockViewModel.swift`
- `Tests/MacSvnAppTests/HumanCenteredAuxiliaryWorkflowsTests.swift`
- `Tests/MacSvnAppTests/ModalDismissalAccessibilityTests.swift`
- `Tests/MacSvnCoreTests/LockViewModelTests.swift`
- `Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings`

## 6. 下一 session 执行顺序

严格从 U7 计划的任务 6 开始：

1. 复核分支、HEAD 和工作树；如有用户改动，与其共存，不得回滚。
2. 读取 U7 计划任务 6、U7 规格和本交接文档。
3. 运行 U7 定向门禁和全量 `swift test`，保持真实 SVN `49/49`。
4. 构建、校验并冒烟 `dist/SVNStudio.app`。
5. 在 `980 x 640`、`1180 x 760`、`1440 x 900` 验收 Properties、Locks、Shelve、Settings。
6. 覆盖浅色、深色、Reduce Motion、长文本、空态、错误、busy、sheet、Escape、键盘焦点和 VoiceOver。
7. 截图写入 `artifacts/ui/u7-*.png`，不要提交截图。
8. 发现视觉或交互缺口时先补失败测试，再修实现并重跑门禁；禁止降级砍功能。
9. 更新 `CHANGELOG.md`、U7 规格和 U7 计划，明确截图、测试数量、现场偏差和 U8 边界。
10. 最终运行计划中的完整门禁，提交：`feat(UI): 完成人本辅助工作流统一（U7 任务 6/6）`。

完成任务 6 前不要推进 U8，也不要把长期 Human UI 目标标记完成。

## 7. 恢复命令

```bash
cd /Users/yangchao/Desktop/hlkj/newworkspace/aicoding/mac-svn-desktop
git status --short --branch
git log -3 --oneline --decorate
sed -n '388,470p' docs/superpowers/plans/2026-07-15-human-centered-auxiliary-workflows-ui.md
open dist/SVNStudio.app
```

当前 Codex 会话是 unrestricted filesystem 且 approval policy 为 `never`。若下一 session 显示相同权限配置，不要再次请求用户批准；只有实际环境改变并形成外部阻塞时才说明具体限制。
