# Mac SVN Desktop 创新功能设计（AI 智能 / Git 迁移 / 生态效率）

| 项 | 内容 |
|----|------|
| 文档版本 | v1.0 |
| 编写日期 | 2026-07-09 |
| 编写人 | 杨超 |
| 上游文档 | `docs/01-requirements.md`（SRS v1.1 新增 FR-AI/FR-GM/FR-EX 章节） |
| 定位 | 差异化能力设计——商业客户端（Versions/Cornerstone）均不具备的功能 |

## 0. 总览与阶段

在原 P1–P4 路线图之后新增两个阶段：

| 阶段 | 主题 | 内容 |
|------|------|------|
| **P5 Git 迁移** | 一键 SVN → Git | 迁移向导、增量同步、双向过渡期支持 |
| **P6 AI 智能** | 大模型驱动 | AI 提交说明、AI 评审、AI 冲突辅助、自然语言操作 SVN |

生态效率类功能（FR-EX）按开发成本穿插在 P4–P6 各阶段交付。

三类能力的共同原则：

1. **不碰核心数据路径**——AI 与迁移功能全部构建在既有 `SvnService` / `SvnBackend` 之上，失败不影响基础客户端功能；
2. **写操作必须确认**——任何由 AI 或向导发起的写操作（commit/revert/merge/删除），执行前展示完整命令与影响范围，用户确认后才执行；
3. **隐私默认保守**——代码内容发给大模型前有明确开关与脱敏选项，支持纯本地模型（Ollama）。

---

# 一、AI 智能助手（P6，FR-AI）

## 1.1 模型接入层（AIProviderService）

### 多 Provider 配置

| Provider 类型 | 说明 | 典型场景 |
|--------------|------|----------|
| OpenAI 兼容 | 自定义 baseURL + apiKey + model，覆盖 OpenAI/DeepSeek/Kimi/Qwen/公司内网网关 | 主流云端 |
| Anthropic | 原生 Messages API | Claude 系列 |
| Ollama 本地 | `http://localhost:11434`，无需 key | **隐私敏感代码不出内网/本机** |

设计要点：

- 配置模型：`AIProvider{id, name, kind, baseURL, model, apiKeyRef, maxTokens, temperature}`，可配置多个并指定默认；
- **API Key 存 macOS Keychain**（`apiKeyRef` 只存 Keychain 引用），配置文件与日志绝不出现明文；
- 统一抽象 `LLMClient` 协议：`chat(messages, tools?) async throws -> LLMResponse`，流式输出（SSE）供 UI 打字机渲染；
- 连通性测试按钮（发送固定 ping prompt，展示时延与计费 token 数）；
- 请求超时/重试与费用保护：单次会话 token 上限（默认 32 k）、单日调用次数上限，超限提示。

### 隐私与脱敏（发送前处理管道）

```
diff/文件内容 → 脱敏器（可选开关）→ prompt 组装 → LLM
脱敏规则：
  - 密钥形态字符串（AKIA…/ghp_…/sk-…/BEGIN PRIVATE KEY）→ ***REDACTED***
  - 可配置正则（公司域名、内网 IP、员工工号等）
  - 「仅发送 diff，不发送完整文件」默认开启
```

设置页明确标注每个 AI 功能会发送什么数据；首次启用任一 AI 功能时展示数据说明弹窗。

## 1.2 AI 场景功能

### FR-AI-01 AI 生成提交说明（最高频刚需）

- 提交对话框新增「AI 生成」按钮：将勾选文件的 unified diff（脱敏后）发给模型，生成中文提交说明（格式可配置：一行式 / Conventional Commits 中文式 / 公司模板）；
- 生成结果填入文本框供编辑，**不自动提交**；
- diff 超长时分文件摘要再汇总（map-reduce 两级 prompt）。

### FR-AI-02 提交前 AI 评审（Pre-commit Review）

- 提交对话框可选「AI 预检」：模型对 diff 输出分级意见（阻断建议/一般建议/仅提示），如空指针风险、调试代码残留、硬编码密钥；
- 结果仅展示，用户自行决定是否继续提交；检出「疑似密钥」时给醒目红色警示；
- 与 FR-EX-01 提交守护（规则引擎）互补：规则引擎管确定性检查，AI 管语义检查。

### FR-AI-03 AI 冲突解决辅助（与 P3 三路合并编辑器集成）

- 合并编辑器每个冲突块新增「AI 建议」：把 base/mine/theirs 三段 + 上下文发给模型，返回建议合并结果与一句话理由；
- 建议以「预填充到手动编辑区」方式呈现，用户确认才生效——**AI 不直接落盘**；
- 支持整文件级「AI 全量合并预览」，逐块标注置信度，低置信块强制人工处理。

### FR-AI-04 自然语言操作 SVN（AI Chat 面板，Agent 模式）

侧边栏常驻 AI 会话面板，模型通过 **tool-calling 循环**操作 SVN：

```
用户："看下这周 zhangsan 提交了什么，有没有动支付模块"
  → LLM 调用 tool: svn_log(author=zhangsan, from=本周一)
  → LLM 调用 tool: filter paths contains "payment"
  → 汇总回答 + 可点击的 revision 链接（跳转 Log 视图）
```

**工具分级（安全核心设计）：**

| 级别 | 工具 | 策略 |
|------|------|------|
| 只读 | svn_status / svn_log / svn_diff / svn_info / svn_list / svn_blame / svn_cat | 自动执行 |
| 写-低危 | svn_update / svn_add / svn_cleanup | 执行前展示命令卡片，一键确认 |
| 写-高危 | svn_commit / svn_revert / svn_merge / svn_switch / svn_delete / svn_copy | 确认卡片 + 展示影响文件清单；revert 类额外红色警示 |
| 禁止 | 任意 shell、文件系统直接写 | 工具集不提供 |

- 每轮工具调用与结果记入**会话审计日志**（本地 JSON，可导出），满足可追溯要求；
- 典型高价值指令：「把这次 update 拉下来的改动总结一下」「r1200 到 r1250 之间谁改过 login.java，为什么」「帮我把没提交的改动按功能分组，分两次提交」（AI 给分组方案，用户逐组确认提交）。

### FR-AI-05 版本日志智能摘要 / Release Notes 生成

- 选定 revision 范围或日期范围，AI 汇总生成结构化发布说明（新功能/修复/重构分组，关联变更文件）；
- 支持导出 Markdown，模板可配置（对接公司发版格式）。

### FR-AI-06 Blame 演化解释（P4 blame 视图集成）

- 选中代码段 → 「AI 解释演化」：自动收集该段相关的历史 revision diff 链，AI 讲清楚这段代码为什么长成这样、关键改动在哪个版本。

## 1.3 AI 架构

```
┌───────────────────────────────────────────┐
│  AI UI（Chat 面板 / 各功能内嵌按钮）          │
├───────────────────────────────────────────┤
│  AIOrchestrator（会话管理、tool 循环、审计）  │
│    ├── PromptTemplates（场景化提示词库）      │
│    ├── Redactor（脱敏管道）                  │
│    └── ToolRegistry（分级工具表 → SvnService）│
├───────────────────────────────────────────┤
│  LLMClient 协议                             │
│    ├── OpenAICompatibleClient               │
│    ├── AnthropicClient                      │
│    └── OllamaClient                         │
└───────────────────────────────────────────┘
```

- `ToolRegistry` 的工具实现直接调用 L2 `SvnService`，**复用全部互斥/错误处理/审计逻辑**，不另辟通道；
- prompt 模板独立资源文件维护，支持用户级覆盖（高级设置）。

---

# 二、一键迁移 Git（P5，FR-GM）

## 2.1 定位

面向「团队从 SVN 逐步转向 Git」的真实过程，提供三种模式：

| 模式 | 场景 | 底层 |
|------|------|------|
| **快照迁移** | 只要当前代码，不要历史（最快） | `svn export` + `git init` + 首次提交 |
| **历史保真迁移** | 完整提交历史、分支、标签 | `git svn clone`（--stdlayout 或自定义布局） |
| **过渡期增量同步** | 迁移后 SVN 仍有人提交，Git 侧持续追平 | `git svn fetch` + rebase + push，可手动/定时触发 |

> 公司已有 SVN→Forgejo 迁移实战经验（authors 映射、BFG 清理大文件、增量同步），本设计将该流程产品化为 GUI 向导。

## 2.2 迁移向导流程（五步）

```
① 源分析 → ② 映射配置 → ③ 清理策略 → ④ 执行迁移 → ⑤ 推送与同步
```

**① 源分析（自动）**

- 检测仓库布局（标准 trunk/branches/tags 或自定义，读取远端 list 推断）；
- 统计：总 revision 数、作者列表（`svn log --xml -q` 全量去重）、预估耗时；
- 扫描大文件（> 10 MB）与二进制占比，给出仓库瘦身建议；
- 环境检查：`git` 与 `git-svn` 可用性（缺失时给 brew 安装指引）。

**② 映射配置（authors.txt 生成器）**

- 自动列出全部 SVN 作者 → 表格编辑 Git 姓名/邮箱；
- **AI 辅助补全**（可选，复用 LLMClient）：按公司邮箱规则批量推断（如 `zhangsan → 张三 <zhangsan@company.com>`），人工复核；
- 映射表可导出/导入（团队多仓库复用）。

**③ 清理策略**

- 勾选排除路径（如历史 zip、构建产物目录）；
- `svn:ignore` / 全局 ignores → 自动生成 `.gitignore`；
- 超大文件处理：提示迁移后用 BFG/git-filter-repo 清理的操作指引（不内置改写，避免破坏历史一致性的责任边界）。

**④ 执行迁移**

- `git svn clone` 长任务：流式进度（当前 revision / 总数、速率、预估剩余时间）、可暂停恢复（git-svn 天然支持断点续传）、可取消；
- 完成后自动整理：`git svn` 的 remote 分支 → 本地分支，tags/* → 真正的 git tag（附注标签，保留原提交信息与日期）；
- 迁移报告：revision 对账（SVN 总数 vs Git 提交数及差异原因）、分支/标签清单、耗时。

**⑤ 推送与同步**

- 配置目标远程（GitHub / Gitee / 内网 GitLab/Forgejo URL），一键 push（含全部分支与标签）；
- **过渡期增量同步**：迁移记录持久化保存，随时「同步最新 SVN 提交」；可配定时（每日）自动同步 + 菜单栏通知结果；
- 同步冲突（Git 侧已有本地提交）时明确提示策略（rebase 顺序），不静默处理。

## 2.3 架构

```
GitMigrationService (actor)
 ├── SourceAnalyzer      // 布局探测、作者统计、大文件扫描（复用 SvnBackend）
 ├── AuthorsMapper       // authors.txt 生成/校验（可选 AI 补全）
 ├── GitSvnRunner        // git/git-svn 子进程（复用 ProcessRunner）
 ├── PostProcessor       // 分支/标签整理、.gitignore 生成、对账报告
 └── SyncScheduler       // 增量同步任务与定时器
持久化：migrations.json（迁移记录、同步游标、目标 remote）
```

风险与对策：

| 风险 | 对策 |
|------|------|
| 超大仓库（10 万+ revision）clone 数天 | 断点续传 + 后台任务常驻 + 支持 `-r N:HEAD` 截断迁移（保留近史） |
| 作者映射缺漏导致 git-svn 中断 | 预校验：log 全量作者必须 100% 覆盖才允许开始 |
| git-svn 对非标准布局兼容差 | 布局探测置信度低时强制人工确认路径映射 |
| 中文提交说明编码 | git-svn 默认 UTF-8；探测到 GBK 历史时提示 `--log-encoding=GBK` 选项 |

---

# 三、生态与效率创新（FR-EX，穿插 P4–P6）

## FR-EX-01 提交守护（Commit Guard，规则引擎）

提交前自动本地检查（毫秒级，非 AI）：

- 冲突标记残留（`<<<<<<<` / `>>>>>>>`）——历史上最恶性的低级事故；
- 大文件警告（阈值可配，默认 10 MB）；
- 禁提交模式（glob：`*.log`、`node_modules/**`、`.DS_Store`，默认库 + 自定义）；
- 疑似密钥/证书内容（正则库）；
- 检查不通过默认**警告可跳过**，团队可配置为硬阻断。

## FR-EX-02 本地搁置（Shelve / 时光机）

- 「暂存当前修改」：对选中文件生成 patch 快照存本地（`shelves/` 目录 + 元数据），并 revert 工作区——解决「改一半要切去修线上 bug」的高频场景；
- 搁置列表可预览 diff、恢复（`patch` 应用，冲突时提示）、删除；
- 每次 revert/merge 前自动创建**安全快照**（静默，保留最近 20 份）——误操作可救回，弥补 SVN 没有 reflog 的天然短板。

## FR-EX-03 菜单栏常驻与智能提醒

- 菜单栏图标：各 WC 状态角标（本地未提交数 / 远端新提交数）；
- 后台轮询远端（间隔可配，默认 10 分钟）：「trunk 有 3 个新提交（zhangsan: 修复支付回调…）」通知，点击直达 Log；
- 本地文件变更监控（FSEvents）：变更列表实时刷新，无需手动刷新。

## FR-EX-04 命令面板（⌘K）

- 全局快捷面板：模糊搜索动作（提交、更新、切分支、打开 WC）、搜索文件、按 revision/关键字搜日志；
- 与 AI Chat 打通：面板输入自然语言时无缝转给 AI 处理。

## FR-EX-05 Finder 集成

- Finder Sync 扩展：WC 内文件图标角标（已修改/已忽略/冲突），右键菜单（提交、更新、查看日志、diff）——对标 TortoiseSVN 的核心体验；
- macOS 上此体验长期空缺，差异化价值高；实现依赖 FinderSync API，独立扩展 target。

## FR-EX-06 团队活动视图

- 仓库贡献统计：提交热力图（日历式）、作者排行、活跃路径 Top N（全部基于 `svn log --xml` 本地聚合，无需服务端支持）；
- 「谁在锁定什么」看板（needs-lock 工作流可视化）。

## FR-EX-07 URL Scheme 与自动化

- `svnstudio://` scheme：`open?path=…`、`log?url=…&rev=…`、`diff?…`——供 CI 通知、聊天工具消息深链跳转；
- 提供轻量 CLI 伴生命令（open/status/commit-ui），方便终端用户唤起 GUI。

## FR-EX-08 Quick Look 插件

- 空格预览 WC 内文件时直接展示「相对基线的 diff」而非文件内容（可切换）。

---

# 四、需求编号汇总（并入 SRS v1.1）

| 编号段 | 功能 | 阶段 |
|--------|------|------|
| FR-AI-01~06 | AI 提交说明/评审/冲突辅助/自然语言操作/发布摘要/演化解释 | P6 |
| FR-GM-01~05 | 快照迁移/历史保真迁移/authors 映射/清理策略/增量同步 | P5 |
| FR-EX-01~08 | 提交守护/搁置/菜单栏/命令面板/Finder/团队视图/URL Scheme/QuickLook | P4–P6 穿插 |

非功能补充：

| 编号 | 需求 |
|------|------|
| NFR-11 | AI 数据出境可控：默认仅发 diff、脱敏管道、本地模型选项、首次启用告知 |
| NFR-12 | AI/迁移功能故障隔离：任一创新模块崩溃不影响基础 SVN 客户端功能 |
| NFR-13 | AI 写操作 100% 走确认门 + 本地审计日志 |
| NFR-14 | 迁移过程幂等可续传：中断后重入不产生重复/损坏数据 |
