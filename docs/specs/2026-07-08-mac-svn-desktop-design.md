# Mac SVN Desktop — 产品设计规格

- **日期：** 2026-07-08
- **状态：** 草案，待用户确认
- **作者：** 杨超（规划）

## 1. 背景与目标

### 1.1 问题

开发者在 macOS 上使用公司内网 SVN 时，常见痛点包括：

- 命令行操作成本高，提交说明中文编码易出问题
- 商业 GUI 客户端授权费用与团队推广成本
- 现有免费工具功能分散或维护停滞

### 1.2 产品目标

构建一款**开源、原生 macOS、中文友好**的 SVN 桌面客户端，覆盖 80% 日常场景：查看状态、对比差异、提交、更新、浏览日志。

### 1.3 成功标准（MVP）

- 用户可在 3 分钟内完成：添加工作副本 → 查看变更 → 提交 UTF-8 中文说明
- 不依赖除系统 `svn` CLI 外的重量级运行时
- 关键操作失败时有可理解的错误提示（含 svn 原始输出摘要）

## 2. 用户画像

| 角色 | 诉求 |
|------|------|
| Java/前端开发者 | 快速提交、看 diff、查 log |
| 技术负责人 | 团队可统一部署、可审计配置 |
| 非 CLI 用户 | 图形化完成 update/commit |

## 3. 功能范围

### 3.1 MVP（必须）

- [ ] 工作副本：添加文件夹、验证是否为 WC、移除记录
- [ ] Status：展示 M/A/D/? 等状态，按目录树聚合
- [ ] Update / Revert（选中文件）
- [ ] Commit：勾选文件、填写 message、UTF-8 提交
- [ ] Diff：文本文件 side-by-side 或 unified
- [ ] Log：最近 N 条，展示 revision/author/date/message
- [ ] 设置：svn 可执行路径、默认 diff 工具、最近仓库列表
- [ ] 认证：用户名密码存 Keychain；支持 `--non-interactive` 场景

### 3.2 明确不做（MVP）

- SVN 服务器管理（hook、权限、仓库创建）
- Git-SVN 迁移向导
- 内置代码编辑器

### 3.3 后续迭代

- 分支/标签、合并冲突 UI、blame、外部 merge 工具、自动更新

## 4. 技术选型（推荐）

**方案 A：SwiftUI + svn CLI**（MVP 采用）

理由：

1. 最快验证产品价值，避免 libsvn 绑定风险
2. 与公司环境一致：开发者机器通常已有 `svn`
3. 原生菜单栏、Keychain、沙箱策略更可控

风险与缓解：

| 风险 | 缓解 |
|------|------|
| CLI 输出格式差异 | 优先 `svn --xml`；解析层单测覆盖 |
| 大仓库 status 慢 | 异步 + 进度；可选 `--depth` |
| 无 svn 命令 | 首次启动检测并引导 `brew install` |

## 5. 模块设计

### 5.1 SvnCliExecutor

- 职责：构造参数、启动 `Process`、捕获 stdout/stderr、超时取消
- 约束：禁止 shell 注入，路径与参数分开传递

### 5.2 SvnService

- 职责：业务语义 API（`status`, `commit`, `log`, `diff`）
- 返回强类型模型，不向上层泄漏原始 XML

### 5.3 CredentialStore

- 职责：Keychain 读写，按 repository URL 维度存储
- 不在日志中打印密码

### 5.4 UI 模块

- `WorkingCopyListView` — 侧边栏仓库
- `ChangesView` — 变更列表 + 筛选
- `DiffView` — 文本 diff 渲染
- `CommitSheet` — 提交对话框
- `LogView` — 历史记录

## 6. 数据流（Commit 示例）

1. 用户在 `ChangesView` 勾选文件
2. `CommitSheet` 收集 message，校验非空
3. `SvnService.commit(paths, message)` 组装 `svn commit --encoding UTF-8`
4. `SvnCliExecutor` 执行；失败则展示 stderr 摘要
5. 成功后刷新 status，写入本地操作历史（可选）

## 7. 错误处理

- 分类：环境错误（无 svn）、认证错误、冲突、网络、解析错误
- 所有用户可见错误带：**操作建议**（如「请检查 VPN」）
- 日志：`os.Logger`，生产路径不记录敏感字段

## 8. 测试策略

- **单元测试：** XML/文本解析器、参数构造
- **集成测试：** 对本地 `svnadmin create` 临时仓库跑 status/commit 回路
- **手工清单：** 中文提交、大文件、冲突场景

## 9. 发布与分发

- 初期：GitHub Releases + 本地 `.app` 构建说明
- 后期：Apple Developer 签名 + Notarization（可选）

## 10. 待确认项

以下问题需产品负责人确认后进入实现计划：

1. 目标用户是否**仅个人使用**还是**团队推广**？（影响签名、自动更新优先级）
2. 是否需要**对接特定内网 SVN**（如固定证书、SSO）？
3. MVP 是否必须包含 **Diff 可视化**，还是可先 unified 文本？

---

*确认本规格后，进入 `writing-plans` 阶段生成实现计划。*
