# P5 Source Analysis Authors 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-02/03` 的 Core 前置能力：检测 Git/git-svn 环境、分析 SVN 源仓库标准布局、从全量日志提取作者与 revision 范围，为历史保真迁移向导做准备。

**架构：** 复用现有 `SvnService` / `SvnBackend` 只读链路，新增 `remoteLogFromHead` 以支持 `svn log -r HEAD:0`。新增 `GitMigrationSourceAnalyzer` 组合远端 list 与日志，产出 `GitMigrationSourceAnalysis`；新增 `GitMigrationSourceAnalysisViewModel` 暴露状态层。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Subversion CLI、Git CLI、Foundation `ProcessRunning` 注入。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `logFromHead(target:batch:verbose:authArguments:)`，参数形状为 `svn log --xml [-v] --non-interactive -r HEAD:0 -l <batch> [auth] <target>`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `remoteLogFromHead(url:batch:verbose:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现远端 HEAD 日志解析，认证继续走 stdin。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `remoteLogFromHead` 并沿用认证重试。
- 创建：`Sources/MacSvnCore/Services/GitMigrationEnvironmentChecker.swift`
  使用 `ProcessRunning` 检测 git 与 `git svn` 可用性。
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  增加环境、布局、作者、源分析报告模型。
- 创建：`Sources/MacSvnCore/Services/GitMigrationSourceAnalyzer.swift`
  组合环境检查、仓库 list、HEAD 日志，提取 authors、latest/oldest revision、标准布局置信度。
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationSourceAnalysisViewModel.swift`
  暴露 idle/analyzing/completed/error 状态。
- 修改/新增测试：`SvnCommandBuilderTests.swift`、`SvnCliBackendTests.swift`、`SvnServiceTests.swift`、`GitMigrationEnvironmentCheckerTests.swift`、`GitMigrationSourceAnalyzerTests.swift`、`GitMigrationSourceAnalysisViewModelTests.swift`、`Integration/SvnCliBackendIntegrationTests.swift`。

## 任务 1：remoteLogFromHead 链路

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖 `log --xml --non-interactive -r HEAD:0 -l <batch>` 参数、`-v` 可选、认证参数与 stdin 不泄漏密码、`SvnService.remoteLogFromHead` 认证失败后重试一次。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testLogFromHead|SvnCliBackendTests/testRemoteLogFromHead|SvnServiceTests/testRemoteLogFromHead"
```

预期：编译失败或目标测试失败，提示 API 未定义。

- [x] **步骤 3：编写最少实现代码**

实现 command builder、backend 协议、CLI backend 与 service 透传。`SvnService` 认证 scope 使用远端 URL。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：Git/git-svn 环境检查

**文件：**
- 创建：`Sources/MacSvnCore/Services/GitMigrationEnvironmentChecker.swift`
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationEnvironmentCheckerTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖 git 可用时记录版本输出、git-svn 可用时标记可用、任一命令非零退出时记录不可用与 stderr。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationEnvironmentCheckerTests
```

预期：编译失败，提示环境检查类型未定义。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationEnvironmentChecker.check()`：运行 `git --version` 与 `git svn --version`，返回 `GitMigrationEnvironmentStatus`，不抛出非零退出，保留错误摘要。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：SVN 源分析与 authors 提取

**文件：**
- 创建：`Sources/MacSvnCore/Services/GitMigrationSourceAnalyzer.swift`
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSourceAnalyzerTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖标准布局检测（root 下有 trunk/branches/tags 目录）、authors 去重排序、latest/oldest revision、totalRevisionCount、空 URL 阻断、认证参数透传。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSourceAnalyzerTests
```

预期：编译失败或行为失败。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationSourceAnalyzer.analyze(repositoryRoot:auth:)`：调用环境检查、`list(depth:.immediates)` 和 `remoteLogFromHead(batch:.max, verbose:false)`，从返回日志提取作者与 revision 范围。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 4：SourceAnalysis ViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationSourceAnalysisViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSourceAnalysisViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖分析成功、provider 错误、空 URL 阻断、报告暴露。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSourceAnalysisViewModelTests
```

预期：编译失败，提示 ViewModel 未定义。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationSourceAnalysisState.idle/analyzing/completed/error`，ViewModel 只做输入校验、调用 provider、保存 `analysis`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 5：真实 SVN 集成与全量验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写集成测试**

用现有临时 SVN 仓库调用 `remoteLogFromHead` 和 `GitMigrationSourceAnalyzer`，验证 authors 至少包含导入作者、布局识别为 standard、latest revision 不小于 oldest revision。

- [x] **步骤 2：运行集成测试**

运行：

```bash
swift test --filter "SvnCliBackendIntegrationTests/testRemoteLogFromHeadReadsLatestHistory|SvnCliBackendIntegrationTests/testGitMigrationSourceAnalyzerReadsFixtureRepository"
```

预期：PASS。

- [x] **步骤 3：运行全量验证并提交**

运行：

```bash
swift test
git diff --check
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p5-source-analysis-authors.md
git diff --cached --check
git commit -m "feat: add P5 source analysis authors"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：测试 0 failures，空白检查无输出，提交后工作区干净。

## 自检

- 覆盖 `FR-GM-02` 的源分析前置能力：标准布局、revision 范围、git/git-svn 环境检查。
- 覆盖 `FR-GM-03` 的 authors 自动提取底座：从全量 SVN 日志去重得到作者列表。
- 不覆盖 authors 表格编辑、AI 补全、git-svn clone 执行、清理策略、推送与增量同步；这些另开计划。
