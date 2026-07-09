# Mac SVN Desktop

面向 macOS 的开源 Subversion（SVN）桌面客户端，目标对标商业客户端（Versions / Cornerstone）：工作副本管理、提交/更新、差异对比、日志、分支/标签、**内置三路合并**、**仓库浏览器**、blame 与锁定。

> 当前阶段：**文档体系已完成，待进入 P1 开发**（需求/概设/详设/测试计划见 [docs 文档索引](docs/README.md)）

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
| **P4 商业对标** | 完整体验 | Blame、属性与锁定、Diff 增强、签名公证、Sparkle 自动更新 |

## 目录规划（实现阶段）

```
mac-svn-desktop/
├── MacSvnDesktop/          # SwiftUI App 主工程
│   ├── App/
│   ├── Features/           # Changes、Commit、Diff、Log、RepoBrowser、Merge
│   ├── Services/           # SvnBackend、SvnService、Conflict、Credential
│   └── Models/
├── docs/
│   └── specs/              # 设计规格
├── scripts/                # 构建、签名、公证
└── README.md
```

## 开发环境要求

- macOS 14+，Xcode 16+
- 本机 Subversion CLI ≥ 1.14（`brew install subversion`）
- （可选）GitHub CLI `gh` 用于发布

## 初始化 GitHub 仓库

GitHub CLI 需先登录：

```bash
gh auth login -h github.com
```

然后在项目根目录执行：

```bash
cd mac-svn-desktop
gh repo create mac-svn-desktop --public \
  --description "macOS Subversion desktop client — 原生 SVN 图形客户端，内置三路合并与仓库浏览器" \
  --source=. --remote=origin --push
```

## License

MIT — 详见 [LICENSE](LICENSE)
