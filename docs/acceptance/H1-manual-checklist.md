# H1 手工验收清单（真实 WC）

在本机准备一个可写 SVN 工作副本后，按序勾选。

## 环境

- [ ] `swift run MacSvnDesktopApp` 可启动
- [ ] 环境门禁检测到 svn ≥ 1.14（或已配置自定义路径）

## P1 日常流（Working-Copy Centric）

- [ ] 左侧侧栏：添加 / 选中 / 移除工作副本（可拖入目录）
- [ ] 默认进入「变更」工作区：刷新 status；**更新 / 清理 / 添加 / 删除 / 还原**
- [ ] 同屏：点文件看 Diff；底部提交面板填写说明（中文）、Commit Guard、提交成功
- [ ] 顶栏可切到「历史」查看日志；从日志「查看 Diff」回到变更工作区
- [ ] 更新产生冲突时自动切到「冲突」；解决后点「返回变更」
## P2–P4

- [ ] 仓库浏览器懒加载与收藏
- [ ] Checkout / 分支标签 / Merge 向导
- [ ] 冲突列表 + 三路合并保存 resolve
- [ ] Blame / 属性 / 锁定 / 搁置

## P5–P6

- [ ] Git 迁移向导五步可走通（可用小仓库快照模式）
- [ ] 菜单栏角标刷新；远端新提交有通知（可选）
- [ ] `svnstudio://open?path=...` 可打开 WC
- [ ] 设置中配置 AI Provider（可跳过真实 Key，验证表单与 Keychain 写入）
- [ ] ⌘K 命令面板可到达变更/历史/浏览/分支/冲突/高级/工具等全部能力
- [ ] 「工具」菜单可打开 Git 迁移 / 团队 / AI / Release Notes / 设置（默认不占主导航）
- [ ] 团队动态页可加载
## 扩展（可选）

- [ ] 按 `docs/extensions/FinderSync/README.md` 在 Xcode 包装工程验证
- [ ] 按 `docs/extensions/QuickLook/README.md` 验证预览

## Release 本机冒烟（T5.7）

- [x] `build-release-app.sh` 产出含 Finder Sync / Quick Look 的 `arm64 x86_64` Release 包
- [x] `verify-release-app.sh` 通过包结构、扩展点、双架构、继承 run-path、递归包内依赖与深层签名校验
- [x] 隔离 Foundation 用户目录、`HOME` / `TMPDIR`、最小 `PATH` 下真实启动 5 秒且无致命日志；独立进程组限时退出

实证见 [distribution-smoke-2026-07-15.md](distribution-smoke-2026-07-15.md)。当前产物是 ad-hoc 本机验证包，不可用于下面的 Gatekeeper 验收。

## 干净机冒烟（V4 / T5.7 后续）

> 2026-07-15 阻塞：当前机器没有 Developer ID Application 身份和公证 API Key；以下项目保持未勾选，解除方式见 [T5.7 分发记录](distribution-smoke-2026-07-15.md)。

在**未安装 Xcode / 未开开发者模式**的 macOS 上（虚拟机或第二台机器），使用已 `stapler staple` 的 `SVNStudio.app`：

### 准备

- [ ] 机器仅有用户级权限；未预先执行过 `spctl --master-disable`
- [ ] 已安装 `svn` ≥ 1.14（Homebrew 或系统包；应用本身不捆绑 svn）
- [ ] 拷贝公证后的 `SVNStudio.app`（或 dmg/zip 解压结果），**不要**用 ad-hoc 开发包

### Gatekeeper

- [ ] 双击 `SVNStudio.app`：Gatekeeper **直接放行**（无「无法打开，因为来自身份不明的开发者」阻断；若仅首次「打开」确认框可接受）
- [ ] 本机执行：`spctl --assess --type execute --verbose=4 /path/to/SVNStudio.app` 结果为 `accepted`

### 功能冒烟（最小）

- [ ] 启动后环境门禁通过（检测到 svn）
- [ ] 添加一个真实 WC，变更页可刷新 status
- [ ] 菜单栏角标可见
- [ ] （可选）系统设置中启用 Finder 扩展后，WC 内可见角标
- [ ] （可选）对已修改文本文件空格预览可见 Diff

### 失败时

- 回查 `docs/packaging/signing-and-notarization.md` 常见失败表
- 确认分发的是 **staple 之后** 的副本，且扩展与主应用同一 Developer ID 签名
