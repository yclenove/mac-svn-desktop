# P5 Snapshot Git Migration 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [x]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-01` 的 Core 非 UI 闭环：从 SVN URL 导出当前代码到目标目录，初始化 Git 仓库，完成首次提交，并返回可审计的迁移报告。

**架构：** 先在既有 `SvnBackend` 链路补齐 `svn export`，继续使用 `AuthArguments` 和 `SvnService` 的认证重试。新增独立的 Git 命令层 `GitCommandBuilder` / `GitCliBackend`，复用 `ProcessRunning` 执行 `git init`、`git add .`、`git commit`。`GitMigrationService` 组合 SVN export 与 Git backend，`GitMigrationViewModel` 只负责状态、输入校验和报告展示。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Subversion CLI、Git CLI、Foundation `ProcessRunning` 注入。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  定义 `GitMigrationMode`、`GitMigrationStep`、`GitMigrationReport`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `export(url:to:revision:authArguments:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `export(url:to:revision:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 SVN export，远端 URL 使用 `normalizedRemoteURL`，认证密码只走 stdin。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `export(url:to:revision:auth:)`，用目标目录做写锁并支持认证重试。
- 创建：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
  定义 `GitCommand` 与 `initRepository()`、`addAll()`、`commit(message:)`。
- 创建：`Sources/MacSvnCore/Backend/GitBackend.swift`
  定义 `GitBackend` 协议。
- 创建：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
  使用 `ProcessRunning` 调用 git CLI 并映射非零退出为 `SvnError.other`。
- 创建：`Sources/MacSvnCore/Services/GitMigrationService.swift`
  组合 SVN export 与 Git 初始化/提交，产出 `GitMigrationReport`。
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationViewModel.swift`
  暴露快照迁移状态层。
- 修改/新增测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`、`SvnCliBackendTests.swift`、`SvnServiceTests.swift`、`GitCommandBuilderTests.swift`、`GitCliBackendTests.swift`、`GitMigrationServiceTests.swift`、`GitMigrationViewModelTests.swift`、`Integration/SvnCliBackendIntegrationTests.swift`。

## 任务 1：SVN export 后端链路

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 测试：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖 `export --non-interactive [-r N] [auth] <url> <destination>` 参数顺序、stdin 不泄漏密码、`SvnService.export` 认证重试，以及真实 `svn export` 从临时仓库导出文件。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testExport|SvnCliBackendTests/testExport|SvnServiceTests/testExport|SvnCliBackendIntegrationTests/testExport"
```

预期：编译失败或目标测试失败，提示 export API 未定义。

- [x] **步骤 3：编写最少实现代码**

实现 command builder、backend 协议、CLI backend 和 service 方法。`SvnService.export` 使用 `retryingAuthentication(wc: credentialScope(for: url), initialAuth: auth)`，写锁 key 使用目标目录，避免同一目标并发导出。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：Git CLI 后端

**文件：**
- 创建：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
- 创建：`Sources/MacSvnCore/Backend/GitBackend.swift`
- 创建：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
- 测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖 `git init`、`git add .`、`git commit -m <message>` 参数构造；验证 `GitCliBackend` 在目标目录运行命令、按顺序调用、非零退出保留 stderr。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitCommandBuilderTests|GitCliBackendTests"
```

预期：编译失败，提示 Git 类型未定义。

- [x] **步骤 3：编写最少实现代码**

实现 Git command builder 与 `GitCliBackend`。默认 git 可执行路径使用 `"git"`，由 `ProcessRunner` 的 PATH 处理实际解析；非零退出抛 `SvnError.other(code:stderr:)`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：GitMigrationService 快照迁移

**文件：**
- 创建：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationService.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationServiceTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖快照迁移顺序：`svn export` → `git init` → `git add .` → `git commit`；报告包含 `.snapshot`、源 URL、目标目录、提交说明和完成步骤；空源 URL、空提交说明、已存在非空目录都要阻断。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationServiceTests
```

预期：编译失败或行为失败。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationService.snapshotMigrate(sourceURL:destination:revision:commitMessage:auth:)`。目标目录不存在时创建父级，已存在且非空时抛 `GitMigrationError.destinationNotEmpty`，避免覆盖用户文件。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 4：GitMigrationViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

覆盖成功状态、错误状态、空输入阻断和报告暴露。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationViewModelTests
```

预期：编译失败，提示 ViewModel 未定义。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationState.idle/running/completed/error`，`snapshotMigrate(...)` 负责调用 provider 并保存 `report`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 5：真实 SVN + Git 快照迁移集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写集成测试**

用现有临时 SVN 仓库执行快照迁移，验证目标目录包含导出文件、存在 `.git`，并且 `git log --oneline` 能看到首次提交说明。

- [x] **步骤 2：运行集成测试**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testSnapshotGitMigrationExportsAndCommitsRepository
```

预期：PASS；如果机器缺少 git，则测试通过 `XCTSkip` 跳过。

- [x] **步骤 3：运行全量验证并提交**

运行：

```bash
swift test
git diff --check
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p5-snapshot-git-migration.md
git diff --cached --check
git commit -m "feat: add P5 snapshot git migration"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：测试 0 failures，空白检查无输出，提交后工作区干净。

## 自检

- 覆盖 `FR-GM-01`：`svn export` 当前代码、`git init`、首次提交。
- 不覆盖 `FR-GM-02~05`：历史保真、authors 映射、清理策略、增量同步另开计划。
- 不做 SwiftUI 真实界面；当前只实现 Core 与 ViewModel。
- 不保存 Git/SVN 凭据；SVN 认证继续沿用现有 stdin 安全路径。
