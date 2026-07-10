# MacSVN 包装与 `.app` 构建

V1 交付两条等价路径，均可产出可双击的 `MacSVN.app`（嵌入 SwiftPM 产物）。

## 路径 A：SwiftPM 包装脚本（CI / 无 Xcode GUI）

```bash
./scripts/build-macos-app.sh
# 产物：dist/MacSVN.app
./scripts/verify-macos-app.sh dist/MacSVN.app
```

环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `CONFIGURATION` | `release` | `debug` / `release` |
| `OUT_DIR` | `dist` | `.app` 输出目录 |

## 路径 B：Xcode 包装工程（后续挂 Finder Sync / Quick Look）

```bash
open MacSVN.xcodeproj
# 或
xcodebuild -project MacSVN.xcodeproj -scheme MacSVN -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

工程说明：

- Target `MacSVN`：application，编译 `Sources/MacSvnDesktopApp`
- 本地 Swift Package（`.`）产品依赖：`MacSvnApp`（进而带上 `MacSvnCore`）
- `Packaging/MacSVN/Info.plist`：Bundle ID `com.yclenove.MacSVN`、URL scheme `macsvn://`

扩展 target（V2/V3）在本工程上追加：

- Finder Sync：`MacSVNFinderSync`（已嵌入）；见 `docs/extensions/FinderSync/`
- Quick Look：`MacSVNQuickLook`（已嵌入）；见 `docs/extensions/QuickLook/`


## 验收标准（V1）

1. `dist/MacSVN.app` 或 Xcode `BUILT_PRODUCTS_DIR/MacSVN.app` 存在
2. `verify-macos-app.sh` 通过（可执行文件、Bundle ID、`macsvn` scheme）
3. 本机可双击启动（开发签名为 ad-hoc；正式公证见 [signing-and-notarization.md](signing-and-notarization.md)）

## 签名与公证（V4）

见 **[signing-and-notarization.md](signing-and-notarization.md)**。

```bash
# 无证书时验证脚本骨架
MACSVN_DRY_RUN=1 ./scripts/verify-signing-prereqs.sh
MACSVN_DRY_RUN=1 MACSVN_APP_PATH=dist/MacSVN.app \
  MACSVN_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
  ./scripts/sign-and-notarize.sh
```

