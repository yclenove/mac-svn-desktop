# MacSVN Finder Sync 扩展（FR-EX-05）

## 目标

在 Finder 中为 SVN 工作副本显示角标，并提供右键菜单（Update / Commit / Diff / Log 等），通过 `macsvn://` 深链唤起主应用。

## 落地形态

| 产物 | 路径 |
|------|------|
| 扩展源码 | `Packaging/FinderSync/MacSvnFinderSync.swift` |
| 扩展 Info.plist | `Packaging/FinderSync/Info.plist` |
| Xcode Target | `MacSVN.xcodeproj` → `MacSVNFinderSync`（嵌入 `MacSVN.app/Contents/PlugIns/`） |
| 根目录导出 | 主应用写入 `~/Library/Application Support/MacSVN/finder-sync-roots.json` |
| 角标/菜单契约 | `MacSvnCore`：`FinderSyncPresentationBuilder` / `FinderSyncDeepLinkBuilder` |

## 角标映射

| SVN 状态 | Finder 角标 |
|----------|-------------|
| modified / added / deleted / replaced / missing | 对应彩色圆点 |
| conflicted / tree conflict | 冲突（紫） |
| unversioned / ignored / … | 对应标识 |
| 干净 | 无角标 |

## 右键菜单 → 深链

- 更新 → `macsvn://open?path=…&action=update`
- 提交 → `macsvn://open?path=…&action=commit`
- 日志 → `macsvn://log?path=…`
- Diff → `macsvn://diff?path=…`
- 还原 / 解决冲突 → `macsvn://open?path=…&action=…`

## 构建与校验

```bash
xcodebuild -project MacSVN.xcodeproj -scheme MacSVN -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="-"
./scripts/verify-finder-sync-appex.sh build/DerivedData/Build/Products/Debug/MacSVN.app
```

## 安装启用

1. 运行/安装带 PlugIns 的 `MacSVN.app`（至少启动一次以导出 WC 根目录）；
2. 系统设置 → 隐私与安全性 → 扩展 → **Finder 扩展** → 启用 **MacSVN Finder**；
3. 在已登记工作副本目录中查看角标与右键菜单。

> 本扩展关闭 App Sandbox，以便读取任意 WC 并调用 `svn status`（开发工具常见配置；正式分发见 V4 签名公证）。

## 验证清单

- [x] `MacSVN.app/Contents/PlugIns/MacSVNFinderSync.appex` 存在且 Bundle ID / 扩展点正确
- [ ] 在已登记 WC 目录上看到角标（需本机启用扩展）
- [ ] 右键菜单可唤起主应用对应页面
