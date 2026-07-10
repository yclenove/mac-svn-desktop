# SVN Studio 长期产品开发详设

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-10 |
| 产品 | SVN Studio |
| 状态 | 草案（配合长期路线图；**全量对标小乌龟**） |
| 路线图 | `docs/superpowers/plans/2026-07-10-long-term-iteration-roadmap.md` |
| 能力基线（验收真相） | `docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md`（v2） |
| 完美 Loop（执行队列） | `docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md` |
| 关联 | SRS、HLD、IA 规格、Finder/QuickLook 扩展说明 |

## 1. 设计目标与约束

### 1.1 目标

在 **Working-Copy Centric** 壳层之上，实现与 **TortoiseSVN（小乌龟）命令/对话框/设置/Overlay 矩阵等价** 的完整客户端（见 inventory v2）；平台只换壳，不砍能力。  
冲突三路合并、AI、Git 迁移为差异化（T6），**不计入**「小乌龟完成度」，也不得挤占 T0–T5 主路径。

### 1.2 硬约束

| 约束 | 说明 |
|------|------|
| 后端 | 继续以 `svn` CLI + `--xml` 为主；`SvnBackend` 协议保留 libsvn 替换点 |
| 事务边界 | 写操作以 svn 原子性为准；应用层禁止「先改本地记账再 execute」类跨步提交 |
| UI 性能 | **禁止**嵌套 `VSplitView`+`HSplitView` + 数千行级 SwiftUI 子视图；大 Diff 必须单块文本或虚拟化 |
| 品牌 | 对外名 SVN Studio；模块名可保留 `MacSvn*` |
| 安全 | 密码不上 argv；AI 写操作必须确认门 |

### 1.3 已发生事故的设计教训（必须写入实现规范）

2026-07-10：变更工作区因嵌套 Split + 逐行 Diff 触发 AttributeGraph 死循环（CPU 100%）。

**规范：**

1. 变更工作区布局：固定 `HStack`/`VStack` + 明确 `frame` 上限，不用嵌套 Split 互抢 ideal size  
2. 嵌入 Diff：`Text(diffText)` 单块渲染；行数/字符超阈值则截断并提示外置工具  
3. `@Observable` ViewModel 禁止在 `body` 计算路径里触发写状态  
4. 任何 `onChange` → 更新父状态 → 再触发子 `onChange` 必须有相等性守卫  

## 2. 信息架构（沿用并扩展）

```
NavigationSplitView
├── Sidebar: WC 列表（FR-WC-02）
└── Detail: WorkingCopyShell
    ├── Mode: 变更 | 历史 | 浏览 | 分支 | 冲突
    ├── 更多: Blame | 属性 | 锁定 | 搁置
    ├── 工具: Git 迁移 | 团队 | AI | RN | 设置
    └── ⌘K / 深链 / Finder / 菜单栏 → selectMode/selectRoute
```

命令同源：Finder 右键、变更树右键、⌘K、工具栏 **共用一份 `SvnCommandCatalog`**（动作 ID、标题、是否需选中路径、危险级别）。

## 3. TortoiseSVN 能力映射

| 小乌龟能力 | SVN Studio 落点 | 波次 | 备注 |
|------------|-----------------|------|------|
| Overlay 角标 | Finder Sync badges | L1 | 缓存 + 节流 |
| 右键 Update/Commit/… | Finder Sync 菜单 → `svnstudio://` | L1 | 主程序拉起 |
| Check for modifications | 变更工作区 | L2 | 已有，加深右键 |
| Commit 对话框 | 变更区提交面板 | L2 | 对齐勾选/守护 |
| Diff | 嵌入 Diff + 外置工具 | L2 | 着色/阈值 |
| Show log | 历史 Mode | L3 | 路径级 + 详情 |
| Revision graph | 新视图/Mode 子页 | L3 | MVP |
| Repo browser | 浏览 Mode | L4 | 远端写操作高危确认 |
| Branch/Tag/Switch/Merge | 分支 Mode | L4 | |
| Edit conflicts | 冲突 Mode | L6 | 已有引擎，打磨 UX |
| Get/Release lock | 锁定 | L6 | |
| Add to ignore | 变更/Finder | L2 | FR-ST-05 |
| Cleanup | 变更工具栏 | 已有 | |
| Rename/Move/Delete | 变更右键 + Repo | L2/L4 | |
| Blame | 更多 | L6 | |
| Shelve | 更多 | L6 | |

不追求 1:1 复刻冷门命令；以「日活 Top 动作」为完成定义。

## 4. 模块详设

### 4.1 L0 性能与任务模型

**新增/强化：**

- `SvnProcessTask`：统一封装 `Process`，支持 `cancel()` → `terminate`  
- ViewModel 长任务状态：`idle | running(progress?) | cancelled | failed | succeeded`  
- Diff 展示策略枚举：`plainText` / `coloredLines(max:)` / `externalOnly`

**测试：**

- 取消 status 不留下僵尸进程  
- 超大 diff 字符串截断逻辑单测  

### 4.2 L1 Finder Sync（小乌龟核心）

**数据流：**

```
主程序 status 刷新
  → 写 ~/Library/Application Support/SVNStudio/finder-sync-roots.json
  → 可选写 per-root status cache（路径→badge）
Finder Sync
  → 读 roots + cache
  → requestBadgeIdentifier
  → 右键构造 svnstudio://open|diff|log?path=&action=
主程序 MacSvnAppNavigator
  → openLocalPath + selectMode
```

**菜单命令表（最小集）：**

更新、提交、还原、清理、日志、Diff、解决冲突、添加到忽略列表、锁定/解锁、在 SVN Studio 中显示

**风险：**

- 扩展沙箱/权限；关闭沙箱需文档说明  
- 角标刷新风暴 → 防抖 ≥ 400ms，单根串行 status  

### 4.3 L2 变更 / 提交 / Diff

**变更树：**

- 双击 → 聚焦 Diff（不切 Mode）  
- 右键 → `SvnCommandCatalog`  
- 多选批量 add/delete/revert  

**提交面板：**

- 与变更树选中双向同步（可选：提交候选独立勾选，默认跟变更选中）  
- Commit Guard 警告区固定高度，避免撑爆布局  

**Diff：**

- 嵌入：plainText + 截断  
- 独立/外置：设置中配置 `ExternalDiffToolConfiguration`  
- 从历史带 `r1/r2` 时写入 DiffViewModel，不整页跳转丢失 WC  

### 4.4 L3 历史与修订图

**历史页布局（已初版，加深）：**

```
HStack
├── List(修订) 筛选：作者/说明/日期/路径
└── Detail：说明、变更路径表、动作
```

**路径级日志：**

- 输入：当前变更树选中路径或历史页路径过滤器  
- 调用：`svn log --xml -v <path>`  

**修订图 MVP：**

- 数据：`svn log -v` + copy-from 信息构建 DAG  
- 展示：Canvas/SwiftUI 简单节点（trunk/branches），点击跳转历史详情  
- 非目标（MVP）：交互式拖拽合并线编辑  

### 4.5 L4 仓库浏览器与分支

**Repo Browser：**

- 懒加载 `list --xml`  
- cat 预览 ≤ 5MB  
- 远端写操作：统一 `RemoteMutationSheet`（说明必填 + 影响预览）  

**分支：**

- switch 前 `status` 有本地变更 → 阻断或强警告  
- merge dry-run 结果表可跳转冲突 Mode  

### 4.6 L5 视觉品牌

| 资产 | 规格 |
|------|------|
| App Icon | 1024 源图 → asset catalog 全尺寸；识别物：简洁「SVN」字母或仓库+对勾，避免与商业 macSvn 撞脸 |
| 空态 | 零 WC / 无变更 / 无冲突 / 扩展未启用 四套 |
| 关于页 | 版本、svn 路径与版本、许可证 |
| 密度 | 工具栏高度、列表行高写入短规范，避免再次「简陋堆控件」 |

不包含：营销落地页、多主题商店、启动动画长片。

### 4.7 L6 冲突与高级

- 三路合并：块导航快捷键、未保存离开确认（FR-CF-08）  
- 锁定：列表 + 夺锁确认  
- 搁置：提交/切换分支前可选自动 shelve  

### 4.8 L7 分发

- 沿用 `scripts/sign-and-notarize.sh`  
- Sparkle appcast 或手动发布说明  
- H1 干净机清单强制项  

## 5. 横切：命令目录与导航

```swift
// 概念模型（实现时可落在 MacSvnCore）
struct SvnCommandDescriptor: Identifiable {
  var id: String            // "commit", "update", ...
  var title: String         // 中文
  var needsSelection: Bool
  var danger: DangerLevel   // none | confirm | destructive
  var mode: MacSvnWorkspaceMode?
  var deepLinkAction: String?
}
```

`MacSvnAppNavigator` 扩展：

- `perform(_ command:path:)`：统一深链/CLI/Finder/右键入口  
- 保持 `selectMode` / `selectRoute` 无歧义 API  

## 6. 数据与目录

```
~/Library/Application Support/SVNStudio/
  workspace-store.json
  settings.json
  ai-providers.json
  finder-sync-roots.json
  finder-sync-status-cache.json   // L1 新增
  command-audit/                  // AI 审计已有则可复用
```

Keychain：`SVNStudio.AIProvider`（已定）。

## 7. 测试策略

| 层级 | 内容 |
|------|------|
| 单测 | 命令目录、Diff 截断、深链解析、修订图 DAG 构建 |
| 集成 | 真实 WC：status/commit/log/path-log（有 svn） |
| UI 冒烟 | L0 卡死回归；Finder 扩展启用清单 |
| 性能 | 1 万文件 status；>2MB diff 打开 |

## 8. 风险登记

| 风险 | 影响 | 缓解 |
|------|------|------|
| Finder Sync 系统限制/用户未启用 | L1 体感差 | 应用内引导 + 降级主窗口右键 |
| 大仓库 status 慢 | 卡顿 | 可取消、增量、缓存、目录级 status |
| 修订图数据不全 | 图不准确 | MVP 标注「基于 log -v」，不承诺完整合并拓扑 |
| 视觉返工 | 耗时 | L5 独立波次，不阻塞 L1–L4 |
| AI 干扰主路径 | 复杂感 | 保持「工具」菜单，默认不进顶栏 |

## 9. 里程碑定义「可对外给同事用」

同时满足：

1. L0 性能门禁绿  
2. L1 Finder 右键闭环  
3. L2 变更工作区日常提交顺手  
4. L3 历史详情 + 路径日志可用  
5. 签名包可在干净机打开（L7 可并行）  

## 10. 下一步

1. 你确认路线图波次顺序（默认 **T0→T1→…T5**；验收以 inventory v2 为准）  
2. 确认后拆 **L0 实现计划**（writing-plans 粒度）并开工  
3. 每波结束更新本详设「实现状态」表（可另附）  
