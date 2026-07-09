# P1 Workspace Info Import 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 P1 工作副本添加流程自动调用 `svn info` 获取 repoURL 与 revision，推进 FR-WC-01/02 的真实元数据闭环。

**架构：** 在 `WorkspaceStore` 中新增一个轻量协议 `WorkingCopyInfoProviding`，由 `SvnService` 实现。`WorkspaceStore.addExistingWorkingCopy(localPath:infoProvider:)` 先复用已有 `.svn` 校验，再通过 provider 读取 `SvnInfo`，最后调用现有 `addWorkingCopy` 保存记录。

**技术栈：** Swift 6.1、XCTest concurrency。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Services/WorkspaceStore.swift`
  增加 `WorkingCopyInfoProviding` 和 `addExistingWorkingCopy(localPath:infoProvider:username:name:)`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  让 `SvnService` 遵循 `WorkingCopyInfoProviding`。
- 修改：`Tests/MacSvnCoreTests/WorkspaceStoreTests.swift`
  增加 fake provider 测试自动填充 repoURL/revision、非法目录不调用 provider、provider 抛错不持久化。

## 任务 1：自动读取 info 的红绿循环

**文件：**
- 修改：`Tests/MacSvnCoreTests/WorkspaceStoreTests.swift`
- 修改：`Sources/MacSvnCore/Services/WorkspaceStore.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`

- [ ] **步骤 1：编写失败测试**

新增测试：

```swift
let provider = FakeInfoProvider(result: .success(SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(9), kind: "dir")))
let record = try await store.addExistingWorkingCopy(localPath: workingCopy, infoProvider: provider)
XCTAssertEqual(record.repoURL, "file:///repo/trunk")
XCTAssertEqual(record.revision, Revision(9))
let calls = await provider.recordedCalls()
XCTAssertEqual(calls, [workingCopy.resolvingSymlinksInPath()])
```

同时测试非法目录不调用 provider，以及 provider 抛错时 `records()` 仍为空。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter WorkspaceStoreTests`
预期：编译失败，提示 `addExistingWorkingCopy` 或 `WorkingCopyInfoProviding` 未定义。

- [ ] **步骤 3：实现最少代码**

实现协议和新方法。`SvnService` 通过已有 `info(wc:target:)` 自然满足协议；非法 WC 仍抛 `WorkspaceStoreError.invalidWorkingCopy`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter WorkspaceStoreTests`
预期：PASS。

## 任务 2：全量验证与提交

- [ ] **步骤 1：运行全量验证**

运行：`swift test && git diff --check`
预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore/Services Tests/MacSvnCoreTests/WorkspaceStoreTests.swift docs/superpowers/plans/2026-07-09-p1-workspace-info.md
git commit -m "feat: import workspace metadata from svn info"
```
