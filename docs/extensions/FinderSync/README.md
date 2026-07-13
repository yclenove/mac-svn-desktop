# SVN Studio Finder Sync 扩展（FR-EX-05）

在 Finder 中为 SVN 工作副本显示角标，并提供普通右键菜单与「更多命令…」扩展菜单，通过 `svnstudio://` 深链唤起主应用。

## 工程

| 项 | 值 |
|----|-----|
| Xcode Target | `MacSVN.xcodeproj` → `SVNStudioFinderSync`（嵌入 `SVNStudio.app/Contents/PlugIns/`） |
| 根目录与缓存模式 | 主应用原子写入 `~/Library/Application Support/SVNStudio/finder-sync-roots.json`（v3；v1/v2 缺失字段按默认值迁移） |
| Bundle ID | `dev.yclenove.svnstudio.FinderSync` |

## Status Cache

- Default：按工作副本根采集完整递归快照，缓存 8 秒。
- Shell：只按 Finder 当前请求目标采集，缓存 2 秒。
- None：不执行 SVN 状态采集、不显示角标，Finder 右键菜单保持可用。

模式可在设置的 Finder 角标区域切换；扩展监听配置目录，连续原子保存可热更新。配置切换会清空缓存并使旧的并发采集结果失效。

包含路径为空时覆盖所有已登记工作副本；填写后只监视工作副本内匹配的卷/路径。排除路径优先于包含路径，路径按标准化绝对路径的子树匹配。

## 深链

- Finder 普通菜单与「更多命令…」均使用统一命令路由：`svnstudio://command?path=…&command=cmd.…`
- 普通菜单包括更新、提交、日志、Diff、还原、解决冲突。
- 扩展菜单包括添加、删除，以及 Catalog 标记的 Shift 扩展命令（Diff with URL、删除保留本地、删除未版本项、打断锁、重新整合合并）。
- 深链命令通过 `SvnCommandID` 校验后交给主应用既有 `perform(command:paths:)` 执行。
- Finder 多选时为每个选中项生成一个 `path` 参数并保持 Finder 顺序；无选中项时回退到当前 targeted URL。

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
