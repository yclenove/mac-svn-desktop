# Mac SVN Desktop — 产品设计规格

- **日期：** 2026-07-08
- **状态：** 核心决策已锁定，待用户最终审查
- **作者：** 杨超（规划）

## 0. 已锁定决策

| 决策项 | 结论 | 影响 |
|--------|------|------|
| 产品档位 | **C — 替代商业客户端**（对标 Versions / Cornerstone） | 功能范围含分支、合并、blame、仓库浏览器 |
| 冲突解决 | **A — 内置三路合并 UI** | 需自研合并编辑器，不依赖外部 merge 工具 |
| 仓库浏览器 | **必备** | 无需完整检出即可浏览远端目录、查 log、浅检出 |

## 1. 背景与目标

### 1.1 问题

- macOS 上商业 SVN 客户端（Versions、Cornerstone）收费且部分已停止活跃维护
- 命令行 `svn` 对非 CLI 用户门槛高，中文提交说明编码易出错
- 团队需要可统一部署、可对接内网 SVN 的图形化工具

### 1.2 产品目标

开源、原生 macOS、中文友好的**全功能 SVN 桌面客户端**，最终覆盖商业客户端核心能力：工作副本管理、提交/更新、差异对比、日志、分支/标签、**内置三路合并**、**仓库浏览器**、blame、属性与锁定。

### 1.3 成功标准

- P1 交付后：3 分钟内完成「添加工作副本 → 查看变更 → 提交中文说明」且无乱码
- P3 交付后：文本冲突可完全在应用内解决（不依赖外部工具）
- 关键操作失败时给出可理解错误与操作建议（含 svn 原始输出摘要）

## 2. 技术选型（重要修正）

> **修正说明：** 此前草案曾建议「SwiftUI + SVNKit」。经核实 **SVNKit 是纯 Java 库**（TMate Software 出品），无法被 Swift 原生集成，该路线不成立，予以撤回。以下为修正后的真实候选。

### 2.1 候选方案

| 方案 | 架构 | 优点 | 缺点 |
|------|------|------|------|
| **一（推荐）：SwiftUI + svn CLI 混合架构** | 结构化查询走 `svn --xml`，合并/冲突基于 WC 冲突产物 + 自研 UI | 开发节奏快；svn 1.14 能力完整；解析层可单测；风险可控 | 依赖本机 svn；多次进程启动有开销 |
| **二：SwiftUI + libsvn C API 桥接** | 自写 Swift/C 封装（apr 内存池、auth 回调、WC context） | 不依赖外部 CLI；进度/取消回调细粒度 | 封装工作量极大；首版风险高；需自行分发 libsvn 二进制 |
| **三：Tauri 2 + Rust 绑定** | Web UI + Rust svn 绑定 | 未来可跨平台 | 原生体验弱；三路合并 UI 仍需从零做；绑定生态不成熟 |

### 2.2 结论

**P1–P3 采用方案一（CLI 混合架构）**，并通过 `SvnBackend` 协议隔离底层：

- 所有结构化输出使用 `svn --xml`（`status` / `info` / `log` / `list` / `blame` / `proplist`）
- 运行环境强制 `LC_ALL=C`，避免本地化输出破坏解析
- 认证优先复用 svn 自身的 Keychain 凭据缓存；首次认证失败时引导用户输入，通过 `--password-from-stdin`（svn ≥ 1.14）传递，**禁止密码上 argv**
- 三路合并所需的 base/mine/theirs 文件路径由 `svn info --xml` 的 conflict 节点提供；合并完成后 `svn resolve --accept working`
- 若后期遇到 CLI 天花板（超大 WC 性能、进度粒度），P4 评估新增 `LibSvnBackend` 实现，接口已预留

已验证：本机 svn 版本 **1.14.5**，满足要求。

### 2.3 风险与缓解

| 风险 | 缓解 |
|------|------|
| 大仓库 status/log 慢、进程启动开销 | 异步 + 结果流式解析；并发上限；`--depth` 控制范围 |
| 本机无 svn 或版本过低 | 启动检测，引导 `brew install subversion`，设置页可指定路径 |
| CLI 输出格式随版本漂移 | 只依赖 `--xml` 稳定契约；解析层单测覆盖多版本样例 |
| 密码泄漏 | 复用 svn 凭据缓存 + `--password-from-stdin`；日志脱敏 |

## 3. 功能范围（C 档全量，分期交付）

### P1 基础工作副本（MVP 骨架）

- 工作副本管理：添加文件夹、校验是否为 WC、移除记录、最近列表
- Status 树：M/A/D/C/? 状态聚合展示，目录分组
- Update / Revert（选中文件）/ Cleanup
- Commit：勾选文件、UTF-8 提交说明、中文无乱码
- Log：分页加载、按作者/路径筛选
- Unified Diff 文本视图
- 认证与设置：svn 路径检测、凭据引导

### P2 仓库浏览器 + 分支/标签

- 远端目录树浏览（`svn list --xml`，懒加载）
- 远端文件预览（`svn cat`）、远端 log
- Checkout：完整检出与浅检出（`--depth`，`update --set-depth`）
- 分支/标签创建（`svn copy`）、切换（`svn switch`）
- Merge 向导入口（选择来源分支/revision 区间，执行 `svn merge`）

### P3 内置三路合并（核心壁垒）

- 冲突文件列表与导航
- 三窗格合并编辑器：Base（共同祖先）/ Mine / Theirs + 底部结果区
- 逐冲突块操作：采用左 / 采用右 / 双方保留 / 手动编辑
- 解决后写回工作文件并 `svn resolve`
- 树冲突基础处理（保留本地 / 采用远端）

### P4 商业客户端对标补全

- Blame / Annotate 视图
- 属性（props）查看与编辑、锁定管理（lock/unlock）
- Side-by-side Diff 增强、外部 Diff/Merge 工具可选集成
- 代码签名 + 公证、Sparkle 自动更新
- 多窗口 / 多工作副本并行操作打磨

### 明确不做

- SVN 服务器管理（hook、权限、仓库创建）
- Git-SVN 迁移向导
- 内置通用代码编辑器

## 4. 模块设计

```
┌──────────────────────────────────────────────────────┐
│                    SwiftUI Views                      │
│ WC列表│变更树│Diff│提交│日志│仓库浏览器│三路合并编辑器 │
└───────────────────────┬──────────────────────────────┘
                        │ @Observable ViewModels
┌───────────────────────▼──────────────────────────────┐
│  SvnService │ ConflictService │ RepoBrowserService   │
│        MergeEngine │ CredentialStore                  │
└───────────────────────┬──────────────────────────────┘
┌───────────────────────▼──────────────────────────────┐
│            SvnBackend（protocol, async）              │
│   ├── SvnCliBackend   ← P1–P3（svn --xml + Process）  │
│   └── LibSvnBackend   ← P4 可选（libsvn C API）       │
└───────────────────────┬──────────────────────────────┘
                 svn CLI ≥ 1.14（Homebrew）
```

| 模块 | 职责 | 关键约束 |
|------|------|----------|
| `SvnCliBackend` | 组装参数、启动 `Process`、超时/取消、stderr 捕获 | 参数与路径分离传递，禁止 shell 拼接；`LC_ALL=C` |
| `Parsers` | Status/Log/Info/List/Blame XML 解析为强类型模型 | 单测覆盖；异常输入不崩溃 |
| `SvnService` | 业务语义 API（status、commit、update、merge…） | 不向上层泄漏 XML/原始输出 |
| `ConflictService` | 枚举冲突、定位三方文件、resolve | 依赖 `svn info --xml` conflict 节点 |
| `MergeEngine` | 文本三路对齐（diff3 区块算法）、冲突块模型 | 纯函数、可单测；与 UI 解耦 |
| `RepoBrowserService` | 远端 list/log/cat、浅检出 | 懒加载 + 缓存 |
| `CredentialStore` | 用户名与仓库列表持久化；密码走 svn 凭据缓存 | 日志脱敏，不存明文密码 |

## 5. 关键数据流

### 5.1 提交

1. `ChangesView` 勾选文件 → `CommitSheet` 填写说明（校验非空）
2. `SvnService.commit(paths:message:)` → `svn commit --encoding UTF-8 -m <msg> <paths...>`
3. 失败展示 stderr 摘要与建议；成功后刷新 status

### 5.2 冲突解决（P3 核心）

1. update/merge 后 `svn status --xml` 发现 `C` 状态 → 冲突列表
2. `ConflictService` 经 `svn info --xml` 取 base/mine/theirs 文件路径
3. `MergeEngine` 三路对齐生成冲突块 → `MergeEditorView` 三窗格展示
4. 用户逐块选择或手动编辑 → 写回工作文件
5. `svn resolve --accept working <path>` → 刷新状态

## 6. 错误处理

- 错误分类：环境（无 svn/版本低）、认证、冲突、网络/超时、解析
- 每类错误映射「用户可读信息 + 操作建议」（如认证失败 → 引导重输凭据）
- 日志用 `os.Logger` 分级；生产路径不记录密码、token 与完整文件内容

## 7. 测试策略

- **单元测试：** 各 XML Parser、MergeEngine（diff3 对齐与冲突块）、参数构造器
- **集成测试：** `svnadmin create` 本地临时仓库 + `file://` 协议，覆盖 checkout → 修改 → 提交 → 制造冲突 → 合并 → resolve 全回路
- **手工清单：** 中文路径与提交说明、大文件、断网、Keychain 授权弹窗

## 8. 发布与分发

- 初期：GitHub Releases 提供构建说明与未签名 `.app`
- P4：Apple Developer 签名 + Notarization + Sparkle 自动更新

## 9. 默认假设（审查时可调整）

1. **系统要求 macOS 14+**（使用 `@Observable` 等现代 SwiftUI 能力），Xcode 16+
2. **要求本机 svn ≥ 1.14**（已验证本机为 1.14.5）；不满足时引导安装
3. 应用显示名暂定 **MacSVN**，仓库名 `mac-svn-desktop`
4. UI 语言先中文，i18n 结构预留（后续加英文）

---

*本规格经用户审查通过后，进入实现计划（writing-plans）阶段，逐阶段拆解 P1 任务。*
