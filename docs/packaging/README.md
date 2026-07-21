# SVN Studio 包装与 `.app` 构建

日常开发与正式分发使用不同包装路径。正式分发必须使用 Xcode Release 路径，确保主应用、Finder Sync 与 Quick Look 同时进入包体。

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

## Release 分发包（推荐）

```bash
./scripts/build-release-app.sh
# 产物：dist/release-unsigned/SVNStudio.app
```

脚本固定使用 Xcode `Release`、`generic/platform=macOS` 与 `arm64 x86_64`，并依次执行：

1. 主应用、Finder Sync、Quick Look 包结构校验
2. 三个可执行文件及包内动态库的双架构、dyld run-path 继承、递归依赖与深层签名校验
3. 隔离 Foundation 用户目录、`HOME` / `TMPDIR`、最小 `PATH` 下的真实启动稳定性冒烟；退出超时会终止独立进程组

可将中间产物移出仓库，便于 CI 或审计复跑：

```bash
SVNSTUDIO_DERIVED_DATA_PATH=/tmp/svnstudio-release-derived \
SVNSTUDIO_RELEASE_OUT_DIR=/tmp/svnstudio-release \
  ./scripts/build-release-app.sh
```

此阶段产物使用 ad-hoc 签名，只用于本机验证；对外分发前必须继续执行 Developer ID 签名与公证。

## 验收

1. `dist/release-unsigned/SVNStudio.app` 存在
2. `./scripts/verify-release-app.sh dist/release-unsigned/SVNStudio.app` 通过
3. `./scripts/smoke-test-macos-app.sh dist/release-unsigned/SVNStudio.app` 通过

T5.7 本机实证与公证阻塞见 [distribution-smoke-2026-07-15.md](../acceptance/distribution-smoke-2026-07-15.md)。

## 签名与公证

见 [signing-and-notarization.md](signing-and-notarization.md)。干跑示例：

```bash
SVNSTUDIO_DRY_RUN=1 SVNSTUDIO_APP_PATH=dist/release-unsigned/SVNStudio.app \
  SVNSTUDIO_SIGN_IDENTITY="Developer ID Application: …" \
  ./scripts/sign-and-notarize.sh
```
