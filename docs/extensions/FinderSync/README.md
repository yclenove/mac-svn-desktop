# MacSVN Finder Sync 扩展（G7）

## 目标

在 Finder 中为 SVN 工作副本显示角标，并提供右键菜单（Update / Commit UI / Diff）。

## 落地形态（本仓库阶段）

SwiftPM 可执行应用无法直接打包 App Extension。本目录提供：

1. **扩展契约说明**：角标状态映射、菜单动作与主应用深链约定；
2. **Xcode 集成清单**：后续用 Xcode 工程包装 `MacSvnDesktopApp` 时添加 Finder Sync target 的步骤；
3. **桥接协议**：扩展通过 `macsvn://` 深链或 `DistributedNotification` 唤起主应用。

## 角标映射

| SVN 状态 | Finder 角标文案 |
|----------|----------------|
| modified / added / deleted | 本地变更 |
| conflicted / tree conflict | 冲突 |
| 干净且有远端新提交 | 可更新 |
| 干净 | （无角标） |

## 右键菜单 → 深链

- Update → `macsvn://open?path=<wc>` 后主应用切到变更页并触发 Update（后续可加 `action=update`）
- Commit → `macsvn://` + CLI `commit-ui <path>`
- Diff → `macsvn://diff?path=<path>`

## Xcode 集成步骤（验收用）

1. 用 Xcode 打开/生成包装工程，嵌入 `MacSvnDesktopApp`；
2. File → New → Target → macOS → Finder Sync Extension，Bundle ID 如 `com.yclenove.MacSVN.FinderSync`；
3. 将本目录 `MacSvnFinderSync.swift` 加入扩展 target；
4. 启用 App Groups（可选）共享 WC 列表；
5. 签名并安装后，在「系统设置 → 隐私与安全性 → 扩展」启用 Finder。

## 验证

- [ ] 在已登记 WC 目录上看到角标
- [ ] 右键菜单可唤起主应用对应页面
