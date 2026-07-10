# SVN Studio 包装与 `.app` 构建

两条等价路径均可产出可双击的 `SVNStudio.app`（嵌入 SwiftPM 产物）。

## 路径 A：SwiftPM 脚本（日常最快）

```bash
./scripts/build-macos-app.sh
# 产物：dist/SVNStudio.app
./scripts/verify-macos-app.sh dist/SVNStudio.app
```

> 说明：脚本路径不嵌入 Finder Sync / Quick Look；需要扩展时用路径 B。

## 路径 B：Xcode 包装工程（含扩展）

```bash
open MacSVN.xcodeproj
# scheme: SVNStudio
xcodebuild -project MacSVN.xcodeproj -scheme SVNStudio -configuration Release \
  -derivedDataPath build/DerivedData build
```

要点：

- Target `SVNStudio`：application，编译 `Sources/MacSvnDesktopApp`
- `Packaging/SVNStudio/Info.plist`：Bundle ID `dev.yclenove.svnstudio`、URL scheme `svnstudio://`
- Finder Sync：`SVNStudioFinderSync`（已嵌入）；见 `docs/extensions/FinderSync/`
- Quick Look：`SVNStudioQuickLook`（已嵌入）；见 `docs/extensions/QuickLook/`

## 验收

1. `dist/SVNStudio.app` 或 Xcode `BUILT_PRODUCTS_DIR/SVNStudio.app` 存在
2. `verify-macos-app.sh` 通过（可执行文件、Bundle ID、`svnstudio` scheme）
3. （可选）`verify-finder-sync-appex.sh` / `verify-quicklook-appex.sh` 通过

## 签名与公证

见 [signing-and-notarization.md](signing-and-notarization.md)。干跑示例：

```bash
SVNSTUDIO_DRY_RUN=1 SVNSTUDIO_APP_PATH=dist/SVNStudio.app \
  SVNSTUDIO_SIGN_IDENTITY="Developer ID Application: …" \
  ./scripts/sign-and-notarize.sh
```
