# H1 手工验收清单（真实 WC）

在本机准备一个可写 SVN 工作副本后，按序勾选。

## 环境

- [ ] `swift run MacSvnDesktopApp` 可启动
- [ ] 环境门禁检测到 svn ≥ 1.14（或已配置自定义路径）

## P1 日常流

- [ ] 工作副本：添加 / 选中 / 移除
- [ ] 变更：刷新 status，Update / Cleanup / Add / Delete / Revert
- [ ] 提交：填写说明（中文）、Commit Guard 警告可见、提交成功
- [ ] Diff / 日志：可查看

## P2–P4

- [ ] 仓库浏览器懒加载与收藏
- [ ] Checkout / 分支标签 / Merge 向导
- [ ] 冲突列表 + 三路合并保存 resolve
- [ ] Blame / 属性 / 锁定 / 搁置

## P5–P6

- [ ] Git 迁移向导五步可走通（可用小仓库快照模式）
- [ ] 菜单栏角标刷新；远端新提交有通知（可选）
- [ ] `macsvn://open?path=...` 可打开 WC
- [ ] 设置中配置 AI Provider（可跳过真实 Key，验证表单与 Keychain 写入）
- [ ] ⌘K 命令面板可跳转路由
- [ ] 团队动态页可加载

## 扩展（可选）

- [ ] 按 `docs/extensions/FinderSync/README.md` 在 Xcode 包装工程验证
- [ ] 按 `docs/extensions/QuickLook/README.md` 验证预览

## 干净机冒烟（V4）

在**未安装 Xcode / 未开开发者模式**的 macOS 上（虚拟机或第二台机器），使用已 `stapler staple` 的 `MacSVN.app`：

### 准备

- [ ] 机器仅有用户级权限；未预先执行过 `spctl --master-disable`
- [ ] 已安装 `svn` ≥ 1.14（Homebrew 或系统包；应用本身不捆绑 svn）
- [ ] 拷贝公证后的 `MacSVN.app`（或 dmg/zip 解压结果），**不要**用 ad-hoc 开发包

### Gatekeeper

- [ ] 双击 `MacSVN.app`：Gatekeeper **直接放行**（无「无法打开，因为来自身份不明的开发者」阻断；若仅首次「打开」确认框可接受）
- [ ] 本机执行：`spctl --assess --type execute --verbose=4 /path/to/MacSVN.app` 结果为 `accepted`

### 功能冒烟（最小）

- [ ] 启动后环境门禁通过（检测到 svn）
- [ ] 添加一个真实 WC，变更页可刷新 status
- [ ] 菜单栏角标可见
- [ ] （可选）系统设置中启用 Finder 扩展后，WC 内可见角标
- [ ] （可选）对已修改文本文件空格预览可见 Diff

### 失败时

- 回查 `docs/packaging/signing-and-notarization.md` 常见失败表
- 确认分发的是 **staple 之后** 的副本，且扩展与主应用同一 Developer ID 签名
