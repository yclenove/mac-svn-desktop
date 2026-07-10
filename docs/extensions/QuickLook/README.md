# MacSVN Quick Look 扩展（FR-EX-08）

## 目标

在 Finder 空格预览中展示 SVN 文本 Diff / 冲突三路摘要。

## 落地形态

| 产物 | 路径 |
|------|------|
| 扩展源码 | `Packaging/QuickLook/MacSvnQuickLookPreviewProvider.swift` |
| 扩展 Info.plist | `Packaging/QuickLook/Info.plist` |
| Xcode Target | `MacSVN.xcodeproj` → `MacSVNQuickLook`（嵌入 `MacSVN.app/Contents/PlugIns/`） |
| 预览文本生成 | `MacSvnCore.QuickLookPreviewTextBuilder`（可单测） |
| 既有契约 | `QuickLookDiffPreviewService`（异步 Diff 服务，主应用复用） |

## 预览策略

| 文件场景 | 预览内容 |
|----------|----------|
| WC 内已修改文本文件 | `svn diff` unified |
| 冲突文件（存在 `.mine` / `.r*`） | 三路提示文案 |
| 二进制 | 「二进制文件，请在 MacSVN Diff 页查看」 |
| 非 WC | 明确提示无法预览 |

## 构建与校验

```bash
xcodebuild -project MacSVN.xcodeproj -scheme MacSVN -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="-"
./scripts/verify-quicklook-appex.sh build/DerivedData/Build/Products/Debug/MacSVN.app
```

## 安装启用

1. 安装/运行带 PlugIns 的 `MacSVN.app`；
2. `qlmanage -r` 刷新 Quick Look 缓存；
3. 在 WC 内已修改文本文件上按空格预览。

> 扩展关闭 App Sandbox，以便调用 `svn diff` 并读取工作副本（正式分发见 V4）。

## 验证清单

- [x] `MacSVN.app/Contents/PlugIns/MacSVNQuickLook.appex` 存在且扩展点为 `com.apple.quicklook.preview`
- [ ] 对已修改源文件按空格可见 Diff 预览（需本机安装启用）
- [ ] 冲突文件显示三路提示而非空白
