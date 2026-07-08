# Mac SVN Desktop

面向 macOS 的 Subversion（SVN）桌面客户端，聚焦日常开发工作流：检出、更新、提交、差异对比、日志浏览与冲突处理。

> 当前阶段：**规划与规格设计**（尚未进入实现）

## 为什么做

macOS 上成熟的 SVN GUI 选择有限（如 Versions、Cornerstone 多为商业软件），而命令行 `svn` 对非技术同学门槛高。本项目目标是提供**原生 macOS 体验**、**中文友好**、**可对接公司内网 SVN** 的开源桌面工具。

## 技术方案对比

| 方案 | 优点 | 缺点 | 适合场景 |
|------|------|------|----------|
| **A. SwiftUI + 调用 svn CLI**（推荐 MVP） | 原生体验、体积小、签名分发简单、开发快 | 依赖本机安装 svn、需解析命令输出 | 个人/团队内网，已有 `svn` 命令行 |
| **B. Tauri 2 + Vue/React** | UI 迭代快、跨平台潜力、Web 生态丰富 | 仍需捆绑或依赖 svn CLI；Rust 层有一定学习成本 | 需要复杂 UI、未来可能做 Windows 版 |
| **C. Swift + libsvn / SVNKit** | 不依赖外部 CLI、可深度定制协议层 | 绑定与维护成本高、C/ObjC 桥接复杂 | 长期产品化、需离线/细粒度控制 |

**推荐路径：** 先做 **方案 A（SwiftUI + svn CLI）** 验证核心工作流；若 CLI 解析成为瓶颈，再评估 libsvn 封装。

## 核心功能（MVP）

1. **工作副本管理** — 添加/移除本地 WC，记住最近仓库
2. **基础操作** — Update、Commit、Revert、Cleanup
3. **变更浏览** — 文件状态列表、Side-by-side Diff
4. **日志** — `svn log` 图形化、按路径/作者筛选
5. **提交体验** — 变更文件勾选、UTF-8 提交说明、中文不乱码
6. **认证** — 保存到 macOS Keychain（用户名/密码或证书路径）

## 非 MVP（后续）

- 分支/标签浏览与切换
- 三路合并与冲突解决 UI
- Blame / Annotate
- 外部 Diff/Merge 工具配置（Kaleidoscope、Beyond Compare）
- 多仓库工作区、托盘菜单、通知中心

## 架构草案

```
┌─────────────────────────────────────────┐
│           SwiftUI Views (macOS)          │
│  WC列表 │ 变更树 │ Diff │ 提交 │ 日志    │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│              ViewModel / AppState        │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│         SvnService (async/await)         │
│  checkout │ status │ diff │ commit │ log │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│      SvnCliExecutor + OutputParser       │
│   Process │ XML/Plain parser │ Errors    │
└─────────────────┬───────────────────────┘
                  │
            /usr/local/bin/svn
```

## 目录规划（实现阶段）

```
mac-svn-desktop/
├── MacSvnDesktop/          # SwiftUI App 主工程
│   ├── App/
│   ├── Features/           # WC、Commit、Diff、Log 等模块
│   ├── Services/           # SvnService、Keychain、Config
│   └── Models/
├── docs/
│   └── specs/              # 设计规格
├── scripts/                # 构建、签名、公证
└── README.md
```

## 开发环境要求

- macOS 13+
- Xcode 15+
- 本机已安装 Subversion CLI（`brew install subversion`）
- （可选）GitHub CLI `gh` 用于发布

## 路线图

| 阶段 | 目标 | 交付物 |
|------|------|--------|
| P0 规划 | 确认需求与技术选型 | 设计规格、GitHub 仓库 |
| P1 骨架 | Xcode 工程、svn status/update | 可运行空壳 + 状态列表 |
| P2 提交 | Commit + Keychain + UTF-8 | 端到端提交流程 |
| P3 Diff/Log | 差异与历史 | 日常可用 MVP |
| P4 打磨 | 签名、设置、错误处理 | 0.1.0 内测版 |

## 本地初始化 GitHub 仓库

GitHub CLI 需先登录：

```bash
gh auth login -h github.com
```

然后在项目根目录执行：

```bash
cd mac-svn-desktop
gh repo create mac-svn-desktop --public --description "macOS Subversion desktop client" --source=. --remote=origin --push
```

若仓库名需带用户名前缀，将 `mac-svn-desktop` 改为 `yclenove/mac-svn-desktop` 等形式。

## License

MIT — 详见 [LICENSE](LICENSE)
