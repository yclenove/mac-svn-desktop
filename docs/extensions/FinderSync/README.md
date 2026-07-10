# SVN Studio Finder Sync 扩展（FR-EX-05）

在 Finder 中为 SVN 工作副本显示角标，并提供右键菜单（Update / Commit / Diff / Log 等），通过 `svnstudio://` 深链唤起主应用。

## 工程

| 项 | 值 |
|----|-----|
| Xcode Target | `MacSVN.xcodeproj` → `SVNStudioFinderSync`（嵌入 `SVNStudio.app/Contents/PlugIns/`） |
| 根目录导出 | 主应用写入 `~/Library/Application Support/SVNStudio/finder-sync-roots.json` |
| Bundle ID | `dev.yclenove.svnstudio.FinderSync` |

## 深链

- 更新 → `svnstudio://open?path=…&action=update`
- 提交 → `svnstudio://open?path=…&action=commit`
- 日志 → `svnstudio://log?path=…`
- Diff → `svnstudio://diff?path=…`
- 还原 / 解决冲突 → `svnstudio://open?path=…&action=…`

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
