# T5.7 Release 分发与冒烟记录（2026-07-15）

## 结论

- 双架构 `SVNStudio.app` 包装：通过
- 主应用、Finder Sync、Quick Look 结构、递归依赖与签名校验：通过
- 隔离环境本机启动冒烟：通过
- Developer ID 签名、公证、Gatekeeper 与真实干净机冒烟：阻塞，当前机器没有签名身份和公证凭据

计划允许无证书时以明确阻塞记录完成 T5.7；本记录不把 ad-hoc 开发包冒充为可公开分发产物。

## Release 构建

执行：

```bash
SVNSTUDIO_RELEASE_OUT_DIR=/tmp/svnstudio-t57-release-unsigned \
SVNSTUDIO_DERIVED_DATA_PATH=/tmp/svnstudio-t57-release-derived \
  ./scripts/build-release-app.sh
```

结果：`BUILD SUCCEEDED`，随后 `verify-release-app: OK`、`smoke-test-macos-app: 启动稳定性冒烟通过` 与 `build-release-app: OK`。

产物：`/tmp/svnstudio-t57-release-unsigned/SVNStudio.app`

| 可执行文件 | `lipo -archs` |
|------------|---------------|
| `Contents/MacOS/SVNStudio` | `x86_64 arm64` |
| `SVNStudioFinderSync.appex/Contents/MacOS/SVNStudioFinderSync` | `x86_64 arm64` |
| `SVNStudioQuickLook.appex/Contents/MacOS/SVNStudioQuickLook` | `x86_64 arm64` |

`verify-release-app.sh` 同时确认：

- 主 App、Finder Sync 与 Quick Look 的 Bundle 结构及扩展点正确
- Finder Sync 保留 App Sandbox entitlements
- 三个 Mach-O 仅依赖系统路径；若出现 `@rpath` / loader 路径，必须按 dyld 加载链继承 run-path、解析为包内真实文件、保持双架构并递归校验其依赖
- `codesign --verify --deep --strict` 通过

行为夹具在带空格的 App、Frameworks 和 install name 路径中构建了 `arm64 x86_64` 主程序、父 dylib 和子 dylib：仅主程序声明 `@executable_path` run-path，父 dylib 通过继承 run-path 加载子 dylib。完整夹具校验通过；删除子 dylib 后以非零状态和“依赖无法解析到应用包内”拒绝，证明不会截断路径或只按字符串前缀误放行。

## 本机启动冒烟

`smoke-test-macos-app.sh` 使用 `CFFIXED_USER_HOME` 隔离 Foundation 用户目录，同时设置临时 `HOME` / `TMPDIR` 和 `PATH=/usr/bin:/bin`，直接启动主可执行文件并持续观察 5 秒。审计目录只出现临时 `.subversion`、`Library/Application Support/SVNStudio/{settings,workspaces,finder-sync-roots}.json` 与冒烟日志，证明没有读写真实用户配置。

脚本以 Bash 3.2 job control 为应用建立独立进程组，先向整个组发送 `SIGTERM`，超时后升级 `SIGKILL`。行为测试使用明确忽略 `SIGTERM` 的假 App 与子进程，观察到升级日志，并确认冒烟在有限时间内结束且父子 PID 均不残留。

## 公证阻塞

当前钥匙串检查：

```text
$ security find-identity -v -p codesigning
0 valid identities found
```

当前 Release 签名信息：

```text
Identifier=dev.yclenove.svnstudio
Signature=adhoc
TeamIdentifier=not set
Runtime Version=15.5.0
```

`notarytool` 与 `stapler` 已安装，但环境中没有配置 `SVNSTUDIO_NOTARY_KEY_ID`、`SVNSTUDIO_NOTARY_ISSUER_ID`、`SVNSTUDIO_NOTARY_KEY_PATH`，因此无法提交真实公证。`verify-signing-prereqs.sh` 会要求完整 Developer ID Application 身份并以非零状态拒绝继续；真实签名后还会核对主应用与扩展的 Authority 和 Team ID。签名、公证与 Gatekeeper 均在隐藏目录完成，只有全绿后才发布最终 App/ZIP；输入与发布路径会先做 canonical 碰撞检查，防止错误身份、混签、半成品或路径别名进入发布流程。

ad-hoc 包的 Gatekeeper 审计结果符合预期阻塞：

```text
$ spctl --assess --type execute --verbose=4 /tmp/svnstudio-t57-release-unsigned/SVNStudio.app
/tmp/svnstudio-t57-release-unsigned/SVNStudio.app: rejected
exit_status=3
```

真实 Gatekeeper 与未安装 Xcode 的干净机验收不得勾选。

## 解除阻塞

1. 将 Developer ID Application 证书及对应私钥导入当前用户钥匙串。
2. 配置 App Store Connect API Key 三个 `SVNSTUDIO_NOTARY_*` 环境变量。
3. 以本记录的双架构 Release 包执行 `./scripts/sign-and-notarize.sh`。
4. 确认公证 JSON 状态为 `Accepted`、stapler validate 与本机 `spctl` 通过。
5. 将 staple 后重新生成的 `SVNStudio.zip` 复制到未安装 Xcode、未关闭 Gatekeeper 的干净机，完成 [H1 手工清单](H1-manual-checklist.md) 的功能冒烟。
