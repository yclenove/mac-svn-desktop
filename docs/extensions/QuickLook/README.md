# SVN Studio Quick Look 扩展（FR-EX-08）

为工作副本内文件提供空格预览：文本 Diff / 冲突摘要 / 二进制提示。

## 工程

| 项 | 值 |
|----|-----|
| Xcode Target | `MacSVN.xcodeproj` → `SVNStudioQuickLook`（嵌入 `SVNStudio.app/Contents/PlugIns/`） |
| Bundle ID | `dev.yclenove.svnstudio.QuickLook` |

## 预览文案

| 类型 | 行为 |
|------|------|
| 文本修改 | 展示 `svn diff` 摘要 |
| 冲突 | 展示冲突摘要，引导到三路合并 |
| 二进制 | 「二进制文件，请在 SVN Studio Diff 页查看」 |

## 构建与校验

```bash
xcodebuild -project MacSVN.xcodeproj -scheme SVNStudio -configuration Debug \
  -derivedDataPath build/DerivedData build
./scripts/verify-quicklook-appex.sh build/DerivedData/Build/Products/Debug/SVNStudio.app
```

## 手工启用

1. 安装/运行带 PlugIns 的 `SVNStudio.app`；
2. 在 Finder 中选中 WC 内已修改文本文件，按空格预览。

## 验收

- [x] `SVNStudio.app/Contents/PlugIns/SVNStudioQuickLook.appex` 存在且扩展点为 `com.apple.quicklook.preview`
