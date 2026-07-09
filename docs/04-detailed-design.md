# Mac SVN Desktop 详细设计说明书（DLD）

| 项 | 内容 |
|----|------|
| 文档版本 | v1.0 |
| 编写日期 | 2026-07-09 |
| 编写人 | 杨超 |
| 上游文档 | `docs/03-high-level-design.md`（HLD v1.0） |
| 范围 | P1 全量详设 + P2/P3 关键模块详设（MergeEngine、ConflictService、RepoBrowser） |

> 代码示例为设计约定（接口签名与关键算法），非最终实现；实现阶段允许在不破坏接口契约的前提下调整内部细节。

## 1. L0 — ProcessRunner

### 1.1 接口

```swift
/// svn 子进程执行结果
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data          // 原始字节，编码由上层决定
    let stderr: String        // UTF-8 解码（失败则 lossy）
    let duration: TimeInterval
}

/// 子进程执行器：唯一允许创建 Process 的地方
protocol ProcessRunning: Sendable {
    /// 执行并等待完成（内部支持 Task 取消 → SIGTERM → 5s 后 SIGKILL）
    func run(executable: String,
             arguments: [String],
             stdin: Data?,
             currentDirectory: String?,
             timeout: TimeInterval) async throws -> ProcessResult

    /// 流式执行：逐行回调 stdout（供 checkout/update 进度、超大 status 使用）
    func runStreaming(executable: String,
                      arguments: [String],
                      currentDirectory: String?,
                      timeout: TimeInterval,
                      onStdoutLine: @Sendable (String) -> Void) async throws -> ProcessResult
}
```

### 1.2 实现要点

1. **环境变量**：继承用户环境基础上强制覆盖 `LC_ALL=C`、`LANG=C`；`PATH` 追加 `/opt/homebrew/bin:/usr/local/bin`（GUI 应用默认 PATH 不含 Homebrew）；
2. **取消传播**：`withTaskCancellationHandler` 中先 `process.terminate()`（SIGTERM），5 秒未退出升级 SIGKILL；取消抛 `SvnError.cancelled`；
3. **超时**：默认 120 s（`AppSettings.processTimeout`）；超时按取消路径终止并抛 `SvnError.network(timeout)`；
4. **stdin**：仅认证场景写入密码字节后立即关闭管道；`stdin` Data 不落日志；
5. **输出采集**：stdout 用 `FileHandle.readabilityHandler` 增量收集，避免管道 64 KB 缓冲区满导致子进程写阻塞死锁（经典 Process 陷阱，必须处理）；
6. **日志**：记录 executable、脱敏 argv（`--password-from-stdin` 后无密码，天然安全）、耗时、退出码。

## 2. L1 — SvnBackend 与 Parsers

### 2.1 SvnBackend 协议（后端可替换边界）

```swift
protocol SvnBackend: Sendable {
    // 环境
    func version() async throws -> SvnVersion                     // svn --version --quiet

    // 工作副本查询
    func status(wc: URL) async throws -> [FileStatus]             // status --xml -v 可选
    func info(target: String, revision: Revision?) async throws -> SvnInfo   // info --xml
    func log(target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
    func diff(target: String, r1: Revision?, r2: Revision?) async throws -> String
    func blame(target: String) async throws -> [BlameLine]        // P4

    // 工作副本写操作
    func update(wc: URL, paths: [String]?, revision: Revision?) async throws -> UpdateSummary
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Int
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL) async throws
    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws
    func switchTo(wc: URL, url: String) async throws -> UpdateSummary
    func merge(wc: URL, source: String, range: RevisionRange?, dryRun: Bool) async throws -> MergeSummary

    // 远端操作
    func list(url: String, depth: SvnDepth) async throws -> [RemoteEntry]    // list --xml
    func cat(url: String, revision: Revision?, sizeLimit: Int) async throws -> Data
    func checkout(url: String, to: URL, depth: SvnDepth,
                  onProgress: @Sendable (String) -> Void) async throws
    func copy(source: String, dest: String, message: String) async throws -> Int  // 分支/标签
}
```

**约定：**

- 所有方法可抛 `SvnError`；调用方不接触原始 stderr；
- `update`/`merge` 一律内部追加 `--accept postpone --non-interactive`；
- `commit` 一律追加 `--encoding UTF-8`；message 经 `-m` 传递（Process 参数数组无 shell 转义问题）。

### 2.2 错误映射（SvnErrorMapper）

```swift
enum SvnError: Error {
    case environment(detail: String)      // svn 缺失/版本低/非 WC
    case authentication                   // E170001, E215004
    case outOfDate                        // E155011, E160024
    case wcLocked                         // E155004 → 建议 cleanup
    case conflict(paths: [String])
    case network(detail: String)          // E170013, E175002, 超时
    case parse(detail: String)
    case cancelled
    case other(code: Int?, stderr: String)
}
```

映射规则：正则 `svn: E(\d+)` 提取首个错误码 → 查表分类；表未命中 → `.other`。错误码表维护在 `SvnErrorMapper.swift` 常量区，附官方含义注释。

### 2.3 Parsers 设计

各 Parser 均为无状态结构体，输入 `Data`/`String`，输出模型或抛 `SvnError.parse`。

#### 2.3.1 StatusXMLParser（SAX 流式）

- 基于 `XMLParser` delegate；元素路径 `status/target/entry`；
- 每解析 500 条通过回调分批投递（支持超大 WC 渐进渲染）；
- 状态字符映射：`wc-status@item` → `ItemStatus` 枚举（unversioned/modified/added/deleted/missing/conflicted/replaced/normal/ignored/external）；`tree-conflicted="true"` → `isTreeConflict`。

#### 2.3.2 LogXMLParser

- 元素路径 `log/logentry`；`-v` 时解析 `paths/path`（action 与 copyfrom 信息）；
- 日期解析 ISO8601（svn 输出 UTC），展示层转本地时区。

#### 2.3.3 InfoXMLParser（冲突定位关键）

解析 `info/entry` 基本字段之外，重点处理冲突节点：

```xml
<entry ...>
  <conflict>
    <prev-base-file>foo.c.r10</prev-base-file>   <!-- Base -->
    <prev-wc-file>foo.c.mine</prev-wc-file>      <!-- Mine -->
    <cur-base-file>foo.c.r12</cur-base-file>     <!-- Theirs -->
  </conflict>
  <tree-conflict .../>                            <!-- 树冲突原因 -->
</entry>
```

→ `ConflictInfo{kind, baseFile, mineFile, theirsFile, treeReason}`；文件路径为相对 WC 路径，统一转绝对路径后返回。

#### 2.3.4 UpdateOutputParser（文本，容错）

逐行匹配 `^([ADUCGER ])([ADUCG ])\s+(.+)$` 动作前缀，统计各类计数；`Updated to revision N.` 提取目标版本；无法识别的行忽略并 debug 日志（R2 风险缓解）。

#### 2.3.5 ListXMLParser / BlameXMLParser

常规映射，`list --xml` 的 `entry@kind` 区分 file/dir；blame 按 `target/entry@line-number` 组装。

### 2.4 参数构造规范

- 全部命令追加 `--non-interactive`；
- 查询类追加 `--xml`（支持者）；
- WC 操作以 `currentDirectory = wc` 执行，路径参数使用相对路径（规避中文/空格绝对路径长度与展示问题；Process 参数数组本身无注入风险）；
- 认证参数拼装唯一入口 `AuthArguments.build(credential:)`：`["--username", u, "--password-from-stdin"]` + stdin 密码；禁止其他模块自行拼装。

## 3. L2 — Domain Services

### 3.1 SvnService（actor）

```swift
actor SvnService {
    private let backend: SvnBackend
    private var wcLocks: [URL: Bool] = [:]   // 每 WC 写操作互斥

    // 查询（可并行）
    func status(wc: URL) async throws -> [FileStatus]
    func log(wc: URL, from: Revision, batch: Int) async throws -> [LogEntry]
    func unifiedDiff(wc: URL, path: String) async throws -> UnifiedDiff

    // 写操作（同 WC 串行，进行中则抛 wcBusy 由 UI 提示）
    func update(wc: URL) async throws -> UpdateSummary
    func commit(wc: URL, paths: [String], message: String) async throws -> Int
    func revert(wc: URL, paths: [String]) async throws
    ...
}
```

**写互斥实现**：`wcLocks` 置位/复位 + `defer`；已锁时抛 `SvnServiceError.wcBusy(operation)`，UI 层提示「该工作副本正在执行 update，请稍候」。

**认证重试**：`commit`/`update` 等捕获 `.authentication` 后，经 `CredentialPrompt`（UI 回调闭包注入）拿新凭据重试一次；再失败原样抛出。

### 3.2 MergeEngine（纯函数，P3 核心算法）

#### 3.2.1 接口

```swift
enum MergeEngine {
    /// 两路 diff：Myers O(ND)；同时服务 DiffView 与三路归并
    static func diff(_ a: [Substring], _ b: [Substring]) -> [DiffEdit]

    /// 三路归并：输出稳定块与冲突块交替序列
    static func merge3(base: [Substring], mine: [Substring], theirs: [Substring]) -> [MergeBlock]
}

enum MergeBlock: Equatable {
    case stable(lines: [String])                       // 无冲突，直接进结果
    case conflict(ConflictHunk)
}

struct ConflictHunk: Equatable {
    let baseLines: [String]
    let mineLines: [String]
    let theirsLines: [String]
    var resolution: Resolution?       // nil = 未解决
    enum Resolution: Equatable {
        case takeMine, takeTheirs
        case takeBoth(mineFirst: Bool)
        case manual(lines: [String])
    }
}
```

#### 3.2.2 算法（diff3 语义）

1. 分别计算 `diff(base, mine)`、`diff(base, theirs)`，得到各自相对 base 的编辑区间；
2. 以 base 行号为坐标轴，将双方编辑区间做区间重叠归并（重叠或相邻的双方修改合成一个候选块）；
3. 块分类：
   - 仅一方修改 → 自动采纳该方（进 stable）；
   - 双方修改且修改内容完全一致 → 采纳任一（stable）；
   - 双方修改且不一致 → conflict 块；
4. 相邻 stable 段落合并压缩。

**语义基准**：与 `diff3 -m` 对拍（见测试计划 TC-ME 组）；判定分歧时倾向保守（多报冲突不算错，漏报/错并才是缺陷——对应风险 R1）。

#### 3.2.3 编码处理（MergeFileIO，有 I/O 的薄壳）

- 读取顺序：UTF-8 严格解码 → 失败尝试 GB18030 → 再失败 ISO-8859-1（lossy 兜底 + UI 黄条警告）；
- 记录原编码与换行风格（LF/CRLF），结果写回时还原；
- 三方文件编码不一致时以工作文件（mine）为准。

### 3.3 ConflictService（actor）

```swift
actor ConflictService {
    func conflicts(wc: URL) async throws -> [ConflictInfo]        // status C 项 + info 详情
    func loadTextConflict(_ c: ConflictInfo) async throws -> (base: String, mine: String, theirs: String)
    func saveResolution(_ c: ConflictInfo, mergedText: String) async throws
        // 写临时文件 → 原子替换工作文件 → backend.resolve(accept: .working)
    func resolveWholeFile(_ c: ConflictInfo, accept: ResolveAccept) async throws  // mine-full / theirs-full
    func resolveTreeConflict(_ c: ConflictInfo, keepLocal: Bool) async throws
}
```

**写回原子性**：合并结果先写 `path.tmp-macsvn`，`FileManager.replaceItemAt` 原子替换，再 resolve；任一步失败则回滚临时文件并保持冲突状态（用户可重试）。

### 3.4 RepoBrowserService（actor）

- `children(url:)`：`list --depth immediates` → 缓存（key=url，TTL 60 s，容量 500 节点，LRU）；
- `preview(url:)`：先 `info` 取 size 与 mime，size > 5 MB 或 mime 非 text 拒绝；`cat` 结果按 MergeFileIO 编码链解码；
- `checkout`：流式进度行透传 UI（`runStreaming`）。

### 3.5 CredentialStore / SettingsStore

- `CredentialStore`：`username` 随 WC/URL 记录存 `workspaces.json`；密码只存内存 `[String: String]`（URL host → password，应用退出即失）——持久密码信任 svn 自身 Keychain 缓存；
- `SettingsStore`：UserDefaults 封装，`@Observable` 包装供设置页绑定；svn 路径探测顺序：用户指定 → `/opt/homebrew/bin/svn` → `/usr/local/bin/svn` → `/usr/bin/svn`（逐个 `--version` 验证）。

## 4. L3/L4 — ViewModel 与 UI

### 4.1 页面结构与导航

```
NavigationSplitView
├── Sidebar：WC 列表（分组：工作副本 / 仓库收藏）+ 添加按钮
└── Detail（随选中 WC 切换，TabView）
    ├── 变更 Changes（默认）
    ├── 历史 Log
    ├── 分支 Branches        (P2)
    ├── 冲突 Conflicts       (P3，有冲突时红点)
    └── 仓库 RepoBrowser     (P2，选中收藏 URL 时为主视图)
工具栏：Update │ Commit │ Cleanup │ 刷新 │ 设置
弹窗：CommitSheet / CheckoutSheet / CredentialSheet / MergeEditorWindow(独立窗口)
```

### 4.2 关键 ViewModel 契约（以 ChangesVM 为例）

```swift
@Observable @MainActor
final class ChangesViewModel {
    enum ViewState { case idle, loading(progress: String?), loaded, error(SvnUserError) }
    private(set) var state: ViewState = .idle
    private(set) var entries: [FileStatusNode] = []   // 树/平铺双形态
    var filter: StatusFilter = .all
    var searchText: String = ""

    func refresh() async            // 可重入保护：进行中忽略新请求
    func revert(paths: [String]) async   // 内部弹确认
    func openDiff(path: String)
    func cancelCurrent()
}
```

**通用约定：**

- ViewModel 全部 `@MainActor`；对 L2 的调用用 `Task` 持有引用以支持取消；
- 错误统一转 `SvnUserError{title, suggestion, rawDetail}` 展示（横幅 + 可展开原始输出）；
- 长任务进度经 `WorkspaceStore.activeTasks` 聚合，侧边栏 WC 行显示 spinner。

### 4.3 MergeEditorView（P3 核心 UI）

- 独立窗口（`Window` scene），布局：上三栏（Base/Mine/Theirs，只读、同步滚动、冲突块着色）+ 下结果区（可编辑 `TextEditor` 定制）；
- 冲突块渲染：行号槽 + 背景色（mine 蓝/theirs 橙/未解决红/已解决绿）；
- 顶部工具栏：上一处/下一处冲突、采用左/采用右/双方保留、整文件 mine-full/theirs-full、保存并标记已解决（未全部解决时禁用，FR-CF-04）；
- 未保存关闭 → `NSWindow.delegate` 拦截确认（FR-CF-08）；
- 同步滚动实现：以块序列为坐标系（每块在四个窗格中有对应区间），滚动主窗格时按块映射其余窗格偏移。

### 4.4 状态树构建（ChangesView）

- `[FileStatus]`（相对路径）→ 前缀树构建 `FileStatusNode`；目录节点状态聚合（子级含冲突则目录标 C 色）；
- 10 万级条目：树构建在后台 `Task.detached`，UI 用 `List` 惰性渲染 + 搜索防抖 300 ms。

## 5. 数据持久化详设

### 5.1 workspaces.json

```json
{
  "version": 1,
  "workspaces": [
    {
      "id": "UUID",
      "name": "my-project",
      "localPath": "/Users/x/dev/my-project",
      "repoURL": "https://svn.example.com/repos/my-project/trunk",
      "username": "yangchao",
      "addedAt": "2026-07-09T01:00:00Z",
      "lastOpenedAt": "2026-07-09T02:00:00Z"
    }
  ]
}
```

- 读写经 `PersistenceStore<T: Codable>` 泛型封装：原子写（临时文件 + replace）、版本字段向前兼容（未知字段忽略，版本升级迁移函数表）；
- 启动时校验 `localPath` 存在且含 `.svn`，失效项标记 `isValid=false` 灰显。

### 5.2 commit-history.json / bookmarks.json

同一 `PersistenceStore` 机制；提交说明按 WC id 分组，FIFO 上限 10 条。

## 6. 异常与边界场景清单（实现必须覆盖）

| # | 场景 | 行为 |
|---|------|------|
| E1 | WC 被外部工具（终端）同时操作导致 wc.db 锁 | 捕获 E155004 → 提示并提供一键 Cleanup |
| E2 | 中文/空格/emoji 路径 | 参数数组传递天然安全；UI 全程 NSString 规范化（NFC） |
| E3 | 符号链接 WC 路径 | 添加时 resolve 真实路径存储 |
| E4 | svn 升级导致 WC 格式不兼容 | 捕获对应错误码 → 提示 `svn upgrade` 指引 |
| E5 | 提交中途取消 | SIGTERM 后 svn 自行回滚事务；刷新 status 确认 |
| E6 | 二进制文件冲突 | 不进三路编辑器，仅提供 mine-full/theirs-full 二选一 |
| E7 | 只读文件系统/权限不足 | 错误分类 environment，提示检查权限 |
| E8 | 合并编辑器打开期间文件被外部修改 | 保存时 mtime 比对，不一致警告并要求重新加载 |

## 7. 性能设计要点

1. status 流式解析 + 分批（500 条）投递，首屏 ≤ 3 s（NFR-01）；
2. 同一 WC 的 status 请求合并（进行中则复用结果），避免连点刷新叠加进程；
3. 日志、远端 list 结果缓存；WC 写操作后失效相关缓存（提交→status/log 失效）；
4. MergeEngine 对超长文件（>2 万行）分段处理进度回调，编辑器虚拟化渲染。

## 8. 详设级测试挂钩

- `SvnBackend`、`ProcessRunning`、`CredentialPrompt` 均为协议注入 → 单测可全链路 mock；
- Parsers 测试样例目录 `Tests/Fixtures/`：收录 svn 1.14 真实输出样本（status/log/info-conflict/list/blame + update/merge 文本）；
- MergeEngine 对拍脚本 `scripts/diff3-fuzz.sh`：随机生成三方文本 → 本引擎与 `diff3 -m` 结果比对。
