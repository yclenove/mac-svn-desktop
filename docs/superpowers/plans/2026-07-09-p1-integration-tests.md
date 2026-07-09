# P1 Integration Tests 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 P1 后端增加基于本地 `svnadmin` 临时仓库的真实 SVN 回路集成测试，覆盖测试计划 TC-IT-01 到 TC-IT-03 的基础路径。

**架构：** 集成夹具放在 `Tests/MacSvnCoreTests/Integration/`，每个用例创建独立临时目录、`svnadmin create` 仓库、导入 trunk 种子文件并 checkout 工作副本。真实操作全部通过现有 `SvnCliBackend` 执行，夹具只负责测试仓库生命周期和少量 setup 命令。

**技术栈：** Swift 6.1、XCTest、Foundation `Process`、本机 Subversion CLI 1.14+。

---

## 文件结构

- 创建：`Tests/MacSvnCoreTests/Integration/SvnIntegrationTestCase.swift`
  提供 `requireSvnTools()`、`makeFixture()`、`runTool()`、临时目录清理和 `SvnIntegrationFixture`。
- 创建：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `SvnCliBackend` 的 checkout 后 status、修改/新增/删除 status、中文提交说明 log 读回。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `checkout(url:to:)` 命令构造。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `checkout(url:to:)` 协议方法。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `checkout(url:to:)`，继续复用 `ProcessRunning` 与错误映射。
- 修改：相关 mock 后端测试桩，补齐新增协议方法。

## 任务 1：真实 SVN 集成测试红灯

**文件：**
- 创建：`Tests/MacSvnCoreTests/Integration/SvnIntegrationTestCase.swift`
- 创建：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的集成测试夹具和用例**

新增测试基类：

```swift
class SvnIntegrationTestCase: XCTestCase {
    func makeFixture() throws -> SvnIntegrationFixture
}
```

新增用例：

```swift
final class SvnCliBackendIntegrationTests: SvnIntegrationTestCase {
    func testCheckoutThenStatusIsClean() async throws
    func testStatusSeesModifiedAddedAndDeletedFiles() async throws
    func testCommitWithChineseMessageIsReadBackFromLog() async throws
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests`
预期：编译失败，提示 `SvnCliBackend.checkout` 或协议方法未定义。

## 任务 2：最小 checkout 后端能力

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败的 checkout 命令构造测试**

在 `SvnCommandBuilderTests` 增加：

```swift
func testCheckoutUsesNonInteractiveUrlAndDestination() {
    let command = SvnCommandBuilder.checkout(url: "file:///repo/trunk", to: "/tmp/wc")
    XCTAssertEqual(command.arguments, ["checkout", "--non-interactive", "file:///repo/trunk", "/tmp/wc"])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCommandBuilderTests/testCheckoutUsesNonInteractiveUrlAndDestination`
预期：编译失败，提示 `checkout` 未定义。

- [ ] **步骤 3：实现最少代码**

实现 `SvnCommandBuilder.checkout(url:to:)`、`SvnBackend.checkout(url:to:)`、`SvnCliBackend.checkout(url:to:)`。补齐测试 mock 的空实现。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnCommandBuilderTests/testCheckoutUsesNonInteractiveUrlAndDestination`
预期：PASS。

## 任务 3：真实回路验证与提交

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行集成测试**

运行：`swift test --filter SvnCliBackendIntegrationTests`
预期：3 个集成测试全部 PASS；若机器缺少 `svn` 或 `svnadmin`，用例通过 `XCTSkip` 跳过。

- [ ] **步骤 2：运行全量验证**

运行：`swift test && git diff --check`
预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/Backend Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p1-integration-tests.md
git commit -m "test: add P1 svn backend integration tests"
```
