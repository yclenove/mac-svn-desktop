# P1 Settings Store 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 设置与启动环境检测核心层，覆盖 FR-SE-01/02 的非 UI 部分：svn 路径、日志批量大小、分支布局、进程超时，以及 svn 可用性/版本检查。

**架构：** 新增 Codable `AppSettings` 和 `SettingsStore`，使用现有 `PersistenceStore` 保存 JSON，方便测试与未来迁移。新增 `SvnEnvironmentChecker`，通过注入 `SvnBackendFactory` 和 `FileChecking` 来测试路径探测顺序与版本门槛。

**技术栈：** Swift 6.1、Foundation、XCTest concurrency。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  增加 `BranchLayout`、`AppSettings`、`SvnEnvironmentStatus`。
- 创建：`Sources/MacSvnCore/Services/SettingsStore.swift`
  actor，提供 `load()`、`settings()`、`update(_:)`、`reset()`。
- 创建：`Sources/MacSvnCore/Services/SvnEnvironmentChecker.swift`
  按“用户指定 → /opt/homebrew/bin/svn → /usr/local/bin/svn → /usr/bin/svn”检查路径与版本。
- 测试：`Tests/MacSvnCoreTests/SettingsStoreTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnEnvironmentCheckerTests.swift`

## 任务 1：SettingsStore 持久化

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/SettingsStore.swift`
- 测试：`Tests/MacSvnCoreTests/SettingsStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

测试默认值：

```swift
let settings = try await store.load()
XCTAssertNil(settings.svnPath)
XCTAssertEqual(settings.logBatchSize, 100)
XCTAssertEqual(settings.branchLayout, BranchLayout())
XCTAssertEqual(settings.processTimeout, 120)
```

测试 update 后重新创建 store 能读回手动 svnPath、logBatchSize、branchLayout、processTimeout。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SettingsStoreTests`
预期：编译失败，提示 `SettingsStore` 或 `AppSettings` 未定义。

- [ ] **步骤 3：实现最少代码**

实现模型和 actor，保存文件格式 `{"version":1,"settings":{...}}`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SettingsStoreTests`
预期：PASS。

## 任务 2：svn 环境检测

**文件：**
- 创建：`Sources/MacSvnCore/Services/SvnEnvironmentChecker.swift`
- 测试：`Tests/MacSvnCoreTests/SvnEnvironmentCheckerTests.swift`

- [ ] **步骤 1：编写失败测试**

测试：
- 手动路径存在且版本 `1.14.5` 时返回 `.available(path:version:)`
- 手动路径不存在时回退到候选路径
- 候选路径版本低于 `1.14.0` 时返回 `.unsupportedVersion(path:version:minimum:)`
- 所有路径缺失时返回 `.missing(checkedPaths:)`

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnEnvironmentCheckerTests`
预期：编译失败，提示 `SvnEnvironmentChecker` 未定义。

- [ ] **步骤 3：实现最少代码**

实现 `FileChecking`、`SvnBackendFactory` 注入点，默认生产实现使用 `FileManager` 和 `SvnCliBackend`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnEnvironmentCheckerTests`
预期：PASS。

## 任务 3：全量验证与提交

- [ ] **步骤 1：运行全量验证**

运行：`swift test && git diff --check`
预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p1-settings-store.md
git commit -m "feat: add P1 settings and svn environment check"
```
