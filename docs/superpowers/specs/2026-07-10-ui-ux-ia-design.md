# SVN Studio UI/UX 信息架构设计

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-10 |
| 产品 | SVN Studio |
| 状态 | 已批准（Working-Copy Centric） |
| 对应迭代 | Wave U1–U4 |

## 1. 目标

将「17 个平级功能路由」改为「先选工作副本，再在工作区内干活」，对齐 SRS `FR-WC-02` 与 Versions / SourceTree 心智。

## 2. 壳层结构

```
NavigationSplitView
├── Sidebar: WC 列表（名称 / 路径摘要 / revision / 无效标记）
│            + 添加 / 移除 / 拖入
└── Detail: WorkingCopyShell
            ├── 顶栏 Mode：变更 | 历史 | 浏览 | 分支 | 冲突
            ├── 溢出：Blame / 属性 / 锁定 / 搁置
            ├── 工具：Git 迁移 / 团队 / AI / Release Notes / 设置
            └── 内容区：按 Mode 分发
```

## 3. WorkspaceMode

| Mode | 对应原 Route | 主导航 |
|------|--------------|--------|
| `changes` | workspace / changes / commit / diff | 是（默认） |
| `history` | log | 是 |
| `browser` | repositoryBrowser | 是 |
| `branches` | branches | 是 |
| `conflicts` | merge | 是 |
| `blame` / `properties` / `locks` / `shelve` | 同名 | 更多 |
| `gitMigration` / `teamActivity` / `aiAssistant` / `releaseNotes` / `settings` | 同名 | 工具 |

`MacSvnAppRoute` 保留，供深链 / CLI / ⌘K / 单测兼容；UI 以 Mode 呈现。

## 4. 变更工作区布局（Mode = changes）

```
VSplitView
├── HSplitView
│   ├── 变更树（筛选 / 更新 / 还原…）
│   └── Diff（随选中文件刷新）
└── 提交面板（说明 / Guard / 提交）
```

主操作文案中文：更新、清理、添加、删除、还原。

## 5. 导航与自动化

- 深链 / CLI `open`、`status`、`commit-ui` → 选中 WC + Mode `changes`（route 映射到 `.changes` / `.commit`）
- Update 产生冲突 → Mode `conflicts`
- 冲突解决后提供「返回变更」
- `lastAutomationMessage` → 详情区顶部可关闭 banner

## 6. 空态

1. 零 WC：引导添加 / 拖入  
2. 未选中：提示从侧栏选择  
3. WC 无效：标记「无效」并提示重新添加  

## 7. 非目标

品牌视觉翻新、Bundle ID 变更、业务 ViewModel 重写。
