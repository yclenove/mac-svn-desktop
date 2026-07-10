# Mac SVN Desktop

面向 macOS 的开源 Subversion（SVN）桌面客户端，目标对标商业客户端（Versions / Cornerstone）：工作副本管理、提交/更新、差异对比、日志、分支/标签、**内置三路合并**、**仓库浏览器**、blame 与锁定。

> 当前阶段：**长程交付分支 `feat/long-loop-full-delivery` 已接线 P1–P6 UI**（文档见 [docs 文档索引](docs/README.md)；验收清单见 [H1](docs/acceptance/H1-manual-checklist.md)）

## 为什么做

- macOS 上商业 SVN 客户端收费且部分停止活跃维护，免费工具功能分散
- 命令行 `svn` 对非 CLI 用户门槛高，中文提交说明编码易出错
- 需要可对接公司内网 SVN、中文友好、可团队推广的原生工具

## 核心决策

| 决策项 | 结论 |
|--------|------|
| 产品档位 | 替代商业客户端（全功能） |
| 冲突解决 | 内置三路合并编辑器（不依赖外部 merge 工具） |
| 仓库浏览器 | 必备（免检出浏览远端、浅检出） |
| 技术架构 | SwiftUI + svn CLI（`--xml`）混合架构，`SvnBackend` 协议预留 libsvn 替换点 |
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
│   ├── SvnCliBackend   ← P1–P3（svn --xml + Process）  │
│   └── LibSvnBackend   ← P4 可选（libsvn C API）       │
└───────────────────────┬──────────────────────────────┘
                 svn CLI ≥ 1.14（Homebrew）
```

要点：

- 结构化输出全部走 `svn --xml`，`LC_ALL=C` 防止本地化破坏解析
- 认证复用 svn 自身 Keychain 凭据缓存，补输密码用 `--password-from-stdin`（svn ≥ 1.14），密码不上 argv
- 三路合并基于工作副本冲突产物（base/mine/theirs），UI 与合并引擎自研

## 路线图

| 阶段 | 目标 | 核心交付 |
|------|------|----------|
| **P1 基础 WC** | 日常可用 | 添加 WC、Status 树、Update、Commit（UTF-8 中文）、Log、Unified Diff、认证 |
| **P2 仓库浏览器 + 分支** | 分支工作流 | 远端目录树/log/预览、完整与浅检出、branch/tag 创建切换、merge 向导 |
| **P3 内置三路合并** | 核心壁垒 | 冲突列表、三窗格合并编辑器、逐块采用/手改、resolve |
| **P4 商业对标** | 完整体验 | Blame、属性与锁定、Diff 增强、提交守护、本地搁置、签名公证、Sparkle 自动更新 |
| **P5 Git 迁移** | 平滑转 Git | 快照/历史保真迁移向导、authors 映射（AI 辅助）、过渡期增量同步、菜单栏常驻 |
| **P6 AI 智能** | 大模型驱动 | 多 Provider 配置（含 Ollama 本地）、AI 提交说明/评审/冲突辅助、自然语言操作 SVN（分级确认+审计）、Finder 集成、命令面板 |

## 如何运行

```bash
cd mac-svn-desktop
swift run MacSvnDesktopApp
```

打包为可双击 `.app`（Xcode 包装工程或 SwiftPM 脚本，见 [docs/packaging](docs/packaging/README.md)）：

```bash
./scripts/build-macos-app.sh          # → dist/MacSVN.app
# 或 open MacSVN.xcodeproj → scheme MacSVN
```

测试：

```bash
swift test
```

依赖：macOS 14+、Xcode 16+ / Swift 6.1、本机 `svn` ≥ 1.14（`brew install subversion`）。

## 功能矩阵（长程交付）

| 能力 | 状态 |
|------|------|
| 工作副本 / 变更 / Update·Cleanup·Add·Delete·Revert | ✅ UI 已接 |
| 提交（UTF-8）+ Commit Guard + 说明历史 | ✅ |
| Diff / 日志 / 仓库浏览器 / Checkout / 分支标签 / Merge | ✅ |
| 冲突列表 + 内置三路合并 + 树冲突 | ✅ |
| Blame / 属性 / 锁定 / 搁置 | ✅ |
| Git 迁移向导 + 增量同步 | ✅ |
| 菜单栏角标 / `macsvn://` 深链 / CLI 伴生 | ✅ |
| AI Provider（Keychain）/ Chat / 提交 AI / 冲突 AI | ✅ |
| 命令面板 ⌘K / 团队动态 | ✅ |
| Finder Sync / Quick Look | ✅ 契约+骨架（见 `docs/extensions/`，需 Xcode 包装工程装扩展） |

> 当前分支：`feat/srs-gap-full-delivery` — **SRS 缺口补齐中**（见 [缺口 Loop](docs/superpowers/plans/2026-07-10-srs-gap-long-loop-backlog.md)）

## AI Provider（本机）

火山方舟 Coding（OpenAI 兼容）：

```bash
export ARK_API_KEY='你的密钥'   # 勿提交到 git
./scripts/seed-volcengine-ark.sh
```

默认写入 `~/Library/Application Support/MacSVN/ai-providers.json`，API Key 仅进 Keychain。

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

## 合并回 main

长程功能在 `feat/long-loop-full-delivery`。全量 `swift test` 绿且 H1 清单抽检通过后：

```bash
git checkout main
git merge --ff-only feat/long-loop-full-delivery
git push origin main
```

## License

MIT — 详见 [LICENSE](LICENSE)
