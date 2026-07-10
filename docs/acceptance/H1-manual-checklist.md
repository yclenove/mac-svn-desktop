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
