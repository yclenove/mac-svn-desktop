# Mac SVN Desktop 概要设计说明书（HLD）

| 项 | 内容 |
|----|------|
| 文档版本 | v1.0 |
| 编写日期 | 2026-07-09 |
| 编写人 | 杨超 |
| 上游文档 | `docs/01-requirements.md`、`docs/02-requirements-analysis.md` |

## 1. 设计目标与原则

1. **分层与依赖单向**：UI → 业务服务 → 后端抽象 → 进程执行，禁止反向依赖与跨层调用；
2. **后端可替换**：所有 svn 能力经 `SvnBackend` 协议暴露，P1–P3 用 CLI 实现，P4 可平滑接入 libsvn 实现；
3. **可测试优先**：解析器与合并引擎为纯函数模块，不依赖 UI 与真实进程即可单测；
4. **异步与可取消**：全链路 async/await，长任务基于 Task 取消传播到子进程终止。

## 2. 总体架构

### 2.1 分层图

```
┌────────────────────────────────────────────────────────────────┐
│ L4  Presentation（SwiftUI Views）                                │
│   SidebarView │ ChangesView │ CommitSheet │ DiffView │ LogView  │
│   RepoBrowserView │ BranchView │ MergeEditorView │ SettingsView │
├────────────────────────────────────────────────────────────────┤
│ L3  ViewModel（@Observable，主线程）                             │
│   WorkspaceStore │ ChangesVM │ LogVM │ RepoBrowserVM │ MergeVM  │
├────────────────────────────────────────────────────────────────┤
│ L2  Domain Services（actor / Sendable，业务语义）                │
│   SvnService │ ConflictService │ RepoBrowserService             │
│   MergeEngine（纯函数）│ CredentialStore │ SettingsStore        │
├────────────────────────────────────────────────────────────────┤
│ L1  Backend Abstraction                                         │
│   protocol SvnBackend ── SvnCliBackend（P1–P3 唯一实现）        │
│   Parsers（Status/Log/Info/List/Blame XML，Update/Merge 文本）  │
├────────────────────────────────────────────────────────────────┤
│ L0  Process Execution                                           │
│   ProcessRunner（Process 封装：环境、超时、取消、流式输出）      │
└────────────────────────────────────────────────────────────────┘
                              │
                    /opt/homebrew/bin/svn（≥1.14）
```

### 2.2 模块职责与依赖

| 模块 | 层 | 职责 | 依赖 |
|------|----|------|------|
| `ProcessRunner` | L0 | 启动子进程；注入 `LC_ALL=C`；stdout/stderr 流式采集；超时终止；Task 取消联动 SIGTERM | Foundation |
| `SvnCliBackend` | L1 | 将 `SvnBackend` 协议方法翻译为 svn 参数数组；调用 Parsers 产出模型 | ProcessRunner、Parsers |
| `Parsers` | L1 | XML（SAX 流式）与文本输出 → 强类型模型；容错不崩溃 | Foundation |
| `SvnService` | L2 | WC 相关业务 API：status/update/commit/revert/log/diff/switch/merge | SvnBackend |
| `ConflictService` | L2 | 冲突枚举、三方文件定位、resolve | SvnBackend |
| `RepoBrowserService` | L2 | 远端 list/cat/log、checkout；节点缓存 | SvnBackend |
| `MergeEngine` | L2 | 两路 diff + 三路归并纯算法；无 I/O | 无 |
| `CredentialStore` | L2 | 用户名持久化；密码仅内存暂存转交 stdin | Foundation |
| `SettingsStore` | L2 | svn 路径、分支布局、批量大小等设置持久化（UserDefaults） | Foundation |
| `WorkspaceStore` | L3 | 全局状态：WC 列表、当前选中、任务进度聚合 | L2 各服务 |
| 各 ViewModel | L3 | 页面状态与交互逻辑；调用 L2；主线程发布 | WorkspaceStore、L2 |
| 各 View | L4 | 纯声明式 UI；不含业务逻辑 | ViewModel |

### 2.3 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 并发模型 | L2 服务为 actor，每 WC 一个操作串行队列；只读查询可并行 | svn 对同一 WC 的写操作互斥（wc.db 锁），串行化从源头避免 E155004 锁冲突 |
| XML 解析 | `XMLParser`（SAX）流式 | 10 万文件 status 输出数十 MB，DOM 全量加载内存不可控（NFR-01） |
| 状态管理 | Swift `@Observable` + 单向数据流 | macOS 14 基线；比 Combine 心智负担低 |
| 持久化 | UserDefaults（设置）+ JSON 文件（WC 列表、URL 收藏、提交说明历史） | 数据量小，无需数据库 |
| 冲突策略 | 一切 update/merge 附加 `--accept postpone` | 冲突统一交 UI 处理，杜绝子进程交互挂起 |
| 密码传递 | `--password-from-stdin --non-interactive` | NFR-04；svn 1.14 基线支持 |

## 3. 核心流程设计

### 3.1 通用调用链

```
View 事件 → ViewModel(方法) → L2 Service(actor)
   → SvnBackend 方法 → 组装 argv → ProcessRunner
   → svn 子进程 → stdout 流 → Parser → 模型
   → Service 返回 → ViewModel @MainActor 更新 → View 刷新
失败路径：SvnError（分类）→ ViewModel.errorBanner → 用户可读文案+建议
```

### 3.2 提交流程（UC1）

```
CommitSheet(勾选+说明)
  → 校验：说明非空、无冲突文件（FR-CM-02/04）
  → SvnService.commit(paths, message)
      argv: commit --encoding UTF-8 -m <msg> --non-interactive <paths...>
  → 成功：解析 "Committed revision N." → 刷新 status → Toast(rN)
  → 失败：错误分类
      认证类 → 弹凭据框 → 带凭据重试一次
      过期类(out of date) → 提示先 Update
      其他 → stderr 摘要 + 建议
```

### 3.3 冲突解决流程（UC2，P3 核心）

```
update/merge (--accept postpone) 完成
  → status --xml 发现 C 项 → ConflictListView
  → 选中文件 → ConflictService.detail(file)
       info --xml → ConflictInfo{baseFile, mineFile, theirsFile, kind}
  → 读三方文件（编码探测：UTF-8 优先，失败回退 GB18030/Latin-1）
  → MergeEngine.merge3(base, mine, theirs)
       → [MergeBlock]  // .stable(lines) | .conflict(mine, theirs, base)
  → MergeEditorView 渲染；用户逐块决策/手改
  → 全部块 resolved → 结果写回工作文件（原编码回写）
  → svn resolve --accept working <file>
  → 刷新冲突列表与 status
```

### 3.4 仓库浏览器流程（UC5）

```
输入/选择 URL → RepoBrowserService.children(url)
   list --xml --depth immediates → [RemoteEntry]（缓存 60s）
树节点展开 → 懒加载下一层
文件选中 → 预览（≤5MB 且文本）/ 日志 / 检出入口
```

## 4. 数据模型（概要）

```
WorkingCopy      { id, name, localPath, repoURL, revision, isValid }
FileStatus       { path, itemStatus, propStatus, isTreeConflict, revision }
LogEntry         { revision, author, date, message, changedPaths[] }
RemoteEntry      { url, name, kind(file/dir), size, lastRev, lastAuthor, lastDate }
ConflictInfo     { path, kind(text/tree/property), baseFile?, mineFile?, theirsFile?, treeReason? }
MergeBlock       enum { stable([Line]) | conflict(base:[Line], mine:[Line], theirs:[Line], resolution?) }
SvnError         enum { environment, authentication, outOfDate, conflict, network, parse, cancelled, other(code, stderr) }
AppSettings      { svnPath, logBatchSize, branchLayout, externalDiffTool?, processTimeout }
```

持久化文件（`~/Library/Application Support/MacSVN/`）：

| 文件 | 内容 |
|------|------|
| `workspaces.json` | WC 列表 |
| `bookmarks.json` | 仓库 URL 收藏 |
| `commit-history.json` | 最近提交说明（≤10 条/WC） |

## 5. 错误处理与日志（全局策略）

1. `SvnError` 统一分类：由 stderr 的 svn 错误码（`svn: E<num>`）映射，未知码归 `other`；
2. 每类错误绑定「用户文案 + 操作建议」字典（本地化文案表维护）；
3. 认证错误自动重试一次（拿到新凭据后），其余不自动重试；
4. 日志：`os.Logger` 按子系统（process/parse/service/ui）分类；记录 argv（密码位替换为 `***`）、耗时、退出码；文件内容不进日志。

## 6. 工程结构

```
MacSvnDesktop.xcodeproj
MacSvnDesktop/
├── App/                    # 入口、AppState、路由
├── Features/
│   ├── Workspace/          # 侧边栏、WC 管理
│   ├── Changes/            # 状态树、revert/add/delete
│   ├── Commit/
│   ├── Diff/
│   ├── Log/
│   ├── RepoBrowser/
│   ├── Branches/
│   ├── Merge/              # 冲突列表 + 三路合并编辑器
│   └── Settings/
├── Services/               # L2：SvnService 等
├── Backend/                # L1：SvnBackend、SvnCliBackend、Parsers
├── Process/                # L0：ProcessRunner
├── Models/
└── Resources/              # String Catalog、Assets
MacSvnDesktopTests/         # 单元测试（Parsers、MergeEngine、参数构造）
MacSvnDesktopIntegrationTests/  # svnadmin 临时仓库集成测试
scripts/                    # 构建、生成测试仓库、性能压测
```

## 7. 阶段交付映射

| 阶段 | 模块交付 |
|------|----------|
| P1 | L0/L1 全量骨架 + SvnService(status/update/commit/revert/log/diff/cleanup) + Workspace/Changes/Commit/Diff/Log/Settings UI |
| P2 | RepoBrowserService + Branch/Merge 向导 + checkout（含浅检出）+ 认证补全（svn+ssh 引导） |
| P3 | MergeEngine + ConflictService + 冲突列表/三路合并编辑器 UI |
| P4 | Blame/属性/锁定、Side-by-side diff、签名公证、Sparkle、LibSvnBackend 评估 |

## 8. 兼容性与降级

| 场景 | 策略 |
|------|------|
| svn 1.10–1.13 | 禁用 `--password-from-stdin`，认证失败时引导用户在终端 `svn auth` 缓存凭据 |
| svn 缺失 | 引导页：brew 安装命令 + 手动指定路径 |
| 非标准分支布局 | SettingsStore.branchLayout 自定义 trunk/branches/tags 相对路径 |
| 超大文件（>10 MB）diff/merge | 内置视图禁用，提示使用外部工具（P4 集成后可直接唤起） |
