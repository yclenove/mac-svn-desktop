# P1 SvnService 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 `SvnBackend` 之上实现 P1 业务服务 `SvnService`，为后续 ViewModel/UI 提供查询透传、写操作互斥、提交前校验。

**架构：** `SvnService` 是 actor，持有 `SvnBackend`。读操作直接转发；写操作通过 per-WC 锁保护，已有写操作时抛 `SvnServiceError.wcBusy`；`commit` 在调用 backend 前校验提交说明非空并检查选中文件是否存在冲突状态。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/SvnService.swift`
  定义 `SvnService` actor、`SvnServiceError`，实现 P1 服务方法。
- 测试：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  使用 mock backend 验证转发、写互斥、提交校验。

## 任务 1：SvnService 查询透传与提交校验

**文件：**
- 创建：`Sources/MacSvnCore/Services/SvnService.swift`
- 测试：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `SvnServiceTests`：
- `status/log/diff` 直接调用 backend；
- 空提交说明抛 `SvnServiceError.emptyCommitMessage`；
- 选中文件包含 `.conflicted` 或 `isTreeConflict` 时抛 `SvnError.conflict(paths:)`，且不调用 backend commit；
- 无冲突时 commit 调用 backend 并返回 revision。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnServiceTests`
预期：FAIL 或编译失败，提示 `SvnService` 未定义。

- [ ] **步骤 3：实现最少代码**

实现 `SvnService` actor 的查询转发、commit 校验和调用。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnServiceTests`
预期：PASS。

## 任务 2：SvnService 写操作互斥

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

增加并发测试：第一个 `update` 在 mock backend 中挂起时，同一 WC 的第二个 `update` 应立即抛 `SvnServiceError.wcBusy(operation: "update")`；不同 WC 的写操作不互相阻塞。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnServiceTests`
预期：新增互斥测试 FAIL。

- [ ] **步骤 3：实现最少代码**

为所有写操作 `update/commit/add/delete/revert/cleanup` 加 per-WC 锁和 `defer` 解锁。读操作不加锁。

- [ ] **步骤 4：运行全部测试并 Commit**

运行：`swift test`
预期：全部 PASS。

```bash
git add Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnServiceTests.swift docs/superpowers/plans/2026-07-09-p1-svn-service.md
git commit -m "feat: add P1 svn service"
```
