# SVN Studio

面向 macOS 的开源 Subversion（SVN）桌面客户端。SVN Studio 覆盖工作副本管理、提交与更新、差异对比、日志、分支与合并、仓库浏览、冲突解决、Finder 集成和完整设置体系。

> 当前状态（2026-07-15）：TortoiseSVN inventory v2 必须行已完成 **114/114（100%）**。验收真相见 [能力清单](docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md)，手工证据见 [H-Tortoise](docs/acceptance/H-tortoise-parity.md)，机器可读结果见 [覆盖率快照](docs/acceptance/parity-coverage.json)。

## 为什么做

- macOS 上商业 SVN 客户端收费且部分停止活跃维护，免费工具功能分散
- 命令行 `svn` 对非 CLI 用户门槛高，中文提交说明编码易出错
- 需要可对接公司内网 SVN、中文友好、可团队推广的原生工具

## 核心决策

| 决策项 | 结论 |
|--------|------|
| 产品档位 | TortoiseSVN 平台等价全量对标，macOS 形态允许变化但不删能力 |
| 冲突解决 | 内置三路合并编辑器（不依赖外部 merge 工具） |
| 仓库浏览器 | 必备（免检出浏览远端、浅检出） |
| 技术架构 | SwiftUI + svn CLI（`--xml`）混合架构，`SvnBackend` 协议预留 libsvn 替换点 |
| 更新检查 | 内置 HTTPS GitHub Releases 检查，发现新版本后打开发布页，不直接下载或安装 |
| 差异化创新 | 一键迁移 Git（git-svn 向导 + 增量同步）、AI 智能助手（提交说明/评审/冲突辅助/自然语言操作）、提交守护、本地搁置、Finder 集成 |

> 注：曾评估 SVNKit，因其为纯 Java 库无法被 Swift 原生集成，已排除。

## 架构

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
│   ├── SvnCliBackend   ← 当前实现（svn --xml + Process） │
│   └── LibSvnBackend   ← 可选（libsvn C API）            │
└───────────────────────┬──────────────────────────────┘
                 svn CLI ≥ 1.14（Homebrew）
```

要点：

- 结构化输出全部走 `svn --xml`，`LC_ALL=C` 防止本地化破坏解析
- 认证复用 svn 自身 Keychain 凭据缓存，补输密码用 `--password-from-stdin`（svn ≥ 1.14），密码不上 argv
- 三路合并基于工作副本冲突产物（base/mine/theirs），UI 与合并引擎自研

## 交付波次

| Wave | 范围 | 状态 |
|------|------|------|
| **T0** | 性能门禁、命令 Catalog、统一导航、可取消任务、覆盖率工具 | ✅ |
| **T1** | 工作副本日常闭环与对话框级 Commit / Update / Diff / CFM | ✅ |
| **T2** | 检出、日志动作、冲突、锁、分支、合并、补丁和仓库写操作 | ✅ |
| **T3** | Revision Graph、Changelist、Externals、Shelve、Revprops 和日志缓存 | ✅ |
| **T4** | Finder Sync、Overlay、Status Cache、上下文菜单与多选 | ✅ |
| **T5** | 设置、钩子、Bugtraq、品牌、双架构 App 包装与分发流程 | ✅ |
| **T6** | AI、Git 迁移与团队差异化能力，不计入 Tortoise 对标覆盖率 | 独立演进 |

## 如何运行

```bash
cd mac-svn-desktop
swift run MacSvnDesktopApp
```

### 日常使用（UI 重构后）

1. 左侧添加 / 选中工作副本  
2. 默认「变更」工作区：看 status → 点文件看 Diff → 底部写说明并提交  
3. 顶栏切换：历史 / 浏览 / 分支 / 冲突；「更多」「工具」收纳高级能力  
4. ⌘K 搜索命令与页面  

打包为可双击 `.app`（Xcode 包装工程或 SwiftPM 脚本，见 [docs/packaging](docs/packaging/README.md)）：

```bash
./scripts/build-macos-app.sh          # → dist/SVNStudio.app
# 或 open MacSVN.xcodeproj → scheme SVNStudio
```

测试：

```bash
swift test
```

依赖：macOS 14+、Xcode 16+ / Swift 6.1、本机 `svn` ≥ 1.14（`brew install subversion`）。

对外分发签名与公证：见 [docs/packaging/signing-and-notarization.md](docs/packaging/signing-and-notarization.md)。

## TortoiseSVN 功能矩阵

下表与 [inventory v2](docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md) 一一对应；范围计数相加即完整的 114 行强制验收口径。

| Inventory 维度 | 范围 | 完成度 | SVN Studio 对应能力 |
|----------------|------|--------|---------------------|
| DUG 能力域 | D01–D28 | 28/28 ✅ | 工作副本、认证、提交、冲突、分支合并、仓库浏览、属性、锁、补丁、Revision Graph、Bugtraq 与设置全域 |
| 主命令 | #1–#46 | 46/46 ✅ | Checkout 到大小写冲突修复；主窗口、Finder 右键与 ⌘K 统一路由 |
| Show Log 动作 | L01–L20 | 20/20 ✅ | 比较、Blame、Unified Diff、分支、回滚、合并、Revprops、过滤统计与离线缓存 |
| 设置页 | S01–S13 | 13/13 ✅ | General、Dialogs、Colours、Network、External Programs、Saved Data、Finder、Revision Graph 与 Log Cache |
| Overlay 7/7 | 全状态与策略 | 7/7 ✅ | Finder 角标映射、递归聚合、三种 Cache 模式、包含/排除路径与可选角标 |
| **总计** | **全部必须行** | **114/114（100%）** | partial=0，missing=0 |

手工清单 [H-Tortoise](docs/acceptance/H-tortoise-parity.md) 记录真实 WC、Finder、App 启动与性能门禁；[parity-coverage.json](docs/acceptance/parity-coverage.json) 记录五类机器可读计数。可随时复跑：

```bash
python3 scripts/parity-coverage.py --fail-below 1.0
swift test
```

### 差异化能力（不计入 Tortoise 覆盖率）

| 能力 | 状态 |
|------|------|
| Git 迁移向导、authors 映射与增量同步 | ✅ 可验收 |
| AI Provider（Keychain）、提交/评审/冲突/Blame/发布说明助手 | ✅ 可验收 |
| 自然语言 SVN 工具调用、分级确认与审计 | ✅ 可验收 |
| 命令面板 ⌘K、菜单栏状态、团队热力图 | ✅ 可验收 |
| Finder Sync / Quick Look `.appex` 与 `SVNStudio.app` 包装 | ✅ 可验收 |

## AI Provider（本机）

火山方舟 Coding（OpenAI 兼容）：

```bash
export ARK_API_KEY='你的密钥'   # 勿提交到 git
./scripts/seed-volcengine-ark.sh
```

默认写入 `~/Library/Application Support/SVNStudio/ai-providers.json`，API Key 仅进 Keychain。

## 工程结构

```
mac-svn-desktop/
├── Package.swift
├── Sources/
│   ├── MacSvnCore/         # 服务、ViewModel、解析器
│   ├── MacSvnApp/          # SwiftUI 功能页
│   └── MacSvnDesktopApp/   # @main 入口（含 MenuBarExtra）
├── Tests/
├── docs/                   # SRS/HLD/DLD、长程 backlog、扩展说明、验收清单
└── README.md
```

## 验收与发布

- 完整文档入口：[docs/README.md](docs/README.md)
- Tortoise 手工验收：[docs/acceptance/H-tortoise-parity.md](docs/acceptance/H-tortoise-parity.md)
- App 包装：[docs/packaging/README.md](docs/packaging/README.md)
- Developer ID 签名与公证：[docs/packaging/signing-and-notarization.md](docs/packaging/signing-and-notarization.md)

当前机器没有 Developer ID Application 身份和公证凭据；仓库已提供签名、公证、Gatekeeper 与干净机流程，实际公证需要在持有凭据的发布环境执行。

## License

MIT，详见 [LICENSE](LICENSE)。
