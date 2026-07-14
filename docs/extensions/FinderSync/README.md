# SVN Studio Finder Sync 扩展（FR-EX-05）

在 Finder 中为 SVN 工作副本显示角标，并提供普通右键菜单与「更多命令…」扩展菜单，通过 `svnstudio://` 深链唤起主应用。

## 工程

| 项 | 值 |
|----|-----|
| Xcode Target | `MacSVN.xcodeproj` → `SVNStudioFinderSync`（嵌入 `SVNStudio.app/Contents/PlugIns/`） |
| 根目录与缓存模式 | 主应用原子写入 `~/Library/Application Support/SVNStudio/finder-sync-roots.json`（v4；v1/v2/v3 缺失字段按默认值迁移） |
| Bundle ID | `dev.yclenove.svnstudio.FinderSync` |

## Status Cache

- Default：按工作副本根采集完整递归快照，缓存 8 秒。
- Shell：只按 Finder 当前请求目标采集，缓存 2 秒。
- None：不执行 SVN 状态采集、不显示角标，Finder 右键菜单保持可用。

模式可在设置的 Finder 角标区域切换；扩展监听配置目录，连续原子保存可热更新。配置切换会清空缓存并使旧的并发采集结果失效。

包含路径为空时覆盖所有已登记工作副本；填写后只监视工作副本内匹配的卷/路径。排除路径优先于包含路径，路径按标准化绝对路径的子树匹配。

## Context Menu 设置

- 设置页可选择哪些命令提升到 Finder 顶层，其余日常命令进入「更多命令…」；配置与角标设置一起原子导出。
- `needs-lock` 且目标只读、未被仓库锁定时，Lock 会自动提升到顶层；状态尚未进入同步快照时保持保守，不会误隐藏菜单。
- 可隐藏全部目标均为已知未版本/已忽略状态的菜单，并可按标准化绝对路径配置排除路径。
- Finder 菜单回调只读取线程安全状态快照，不同步执行 SVN；状态采集完成后更新下一次菜单规划。
- Finder Sync 没有 Windows 右键拖拽回调，Copy/Move 通过菜单深链携带绝对路径，主应用选择对应工作副本、转换相对路径并自动打开 Copy/Move 向导，作为平台等价入口。

## 深链

- Finder 普通菜单与「更多命令…」均使用统一命令路由：`svnstudio://command?path=…&command=cmd.…`
- 普通菜单包括更新、提交、日志、Diff、还原、解决冲突。
- 扩展菜单包括添加、删除、属性，以及 Catalog 标记的 Shift 扩展命令（Diff with URL、删除保留本地、删除未版本项、打断锁、重新整合合并）。
- 深链命令通过 `SvnCommandID` 校验后交给主应用既有 `perform(command:paths:)` 执行。
- Finder 多选时为每个选中项生成一个 `path` 参数并保持 Finder 顺序；无选中项时回退到当前 targeted URL。
- 属性命令以绝对路径打开对应工作副本的应用内属性页，展示 WC 状态、修订、最后作者、仓库 URL、锁与属性摘要。

## 构建与校验

```bash
xcodebuild -project MacSVN.xcodeproj -scheme SVNStudio -configuration Debug \
  -derivedDataPath build/DerivedData build
./scripts/verify-finder-sync-appex.sh build/DerivedData/Build/Products/Debug/SVNStudio.app
```

## 手工启用

1. 运行/安装带 PlugIns 的 `SVNStudio.app`（至少启动一次以导出 WC 根目录）；
2. 系统设置 → 隐私与安全性 → 扩展 → **Finder 扩展** → 启用 **SVN Studio Finder**；
3. 在 WC 目录内查看角标与右键菜单。

## 验收

- [x] `SVNStudio.app/Contents/PlugIns/SVNStudioFinderSync.appex` 存在且 Bundle ID / 扩展点正确
- [x] 18 类角标已注册：normal/modified/conflicted/added/deleted/missing/replaced/locked/needs-lock/ignored/unversioned/shallow/nested/external/switched/mergeinfo-only/incomplete/obstructed
- [x] `svn status --xml --verbose --no-ignore` + info depth + current/BASE property 快照结构化采集
- [x] 工作副本根与目录按角标优先级递归聚合；同一 WC 并发刷新合并为一个采集任务
- [x] Status Cache Default / Shell / None；设置持久化、v1 配置迁移、原子热更新与旧任务隔离
- [x] 包含/排除卷与路径（exclude 优先）；18 类角标可在设置中选择并影响目录聚合
- [x] Finder 普通菜单与「更多命令…」扩展菜单；菜单命令共用 `SvnCommandCatalog`，并通过统一 command 深链唤起主应用
- [x] Finder 多选路径批量传递；重复 `path` query 保序解析并进入 Navigator 批量命令入口
- [x] Finder 属性命令与应用内 SVN 信息面板；绝对路径定位 WC，展示状态/revision/作者/URL/锁/属性摘要
- [x] Context Menu 设置：顶层/子菜单提升、needs-lock Lock 提升、未版本/已忽略隐藏、排除路径；配置 v4 兼容旧版本
- [x] Copy/Move 平台等价入口：Finder 菜单深链自动选择 WC 相对路径并打开应用内向导
