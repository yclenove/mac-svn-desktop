# P2 Checkout Depth 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 checkout 深度底座，覆盖 FR-WC-05/06 的 Core 非 UI 部分：完整检出、浅检出 depth 参数、认证参数 stdin 传递、service 层认证重试。

**架构：** 在模型层新增 `SvnDepth`；扩展 `SvnBackend.checkout`、`SvnCliBackend.checkout` 和 `SvnCommandBuilder.checkout` 支持 `depth` 与 `auth`。`SvnService.checkout` 负责认证重试和目的目录写操作互斥；UI 状态层留到后续和 workspace 导入一起实现。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `SvnDepth` 枚举：`empty/files/immediates/infinity`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  将 checkout 协议签名扩展为 `checkout(url:to:depth:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  `checkout` 命令增加 `--depth` 和认证参数。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  构造 checkout auth 参数、stdin，并传给 process runner。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 service checkout，支持认证重试。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 checkout depth/auth 参数。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 checkout stdin 和 argv 不泄露密码。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 checkout 认证失败后重试。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖 `depth: .empty` 浅检出结果。
- 创建：`docs/superpowers/plans/2026-07-09-p2-checkout-depth.md`
  记录此切片计划。

## 任务 1：命令构造与 CLI backend

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中修改 checkout 测试：

```swift
func testCheckoutUsesDepthAuthenticationUrlAndDestination() {
    let command = SvnCommandBuilder.checkout(
        url: "file:///repo/trunk",
        to: "/tmp/wc",
        depth: .files,
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "checkout", "--non-interactive",
        "--depth", "files",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk", "/tmp/wc"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testCheckoutPassesDepthAuthStdinAndRunsOutsideWorkingCopy() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    try await backend.checkout(
        url: "file:///repo/trunk",
        to: URL(fileURLWithPath: "/tmp/wc"),
        depth: .empty,
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
    XCTAssertEqual(runner.calls.single?.arguments, [
        "checkout", "--non-interactive",
        "--depth", "empty",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk", "/tmp/wc"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testCheckout|SvnCliBackendTests/testCheckout"`
预期：编译失败或测试失败，提示 `SvnDepth`、checkout 参数或 backend 签名缺失。

- [x] **步骤 3：编写最少实现代码**

实现：

- `public enum SvnDepth: String, Codable, Equatable, Sendable { case empty, files, immediates, infinity }`
- `SvnCommandBuilder.checkout(url:to:depth:authArguments:)` 固定输出 `--depth <rawValue>`。
- `SvnBackend.checkout(url:to:depth:auth:)`。
- `SvnCliBackend.checkout(url:to:depth:auth:)` 使用 `AuthArguments.build`，stdin 只走 `--password-from-stdin`。
- 为 `SvnCliBackend.checkout` 保留默认参数：`depth: .infinity, auth: nil`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testCheckout|SvnCliBackendTests/testCheckout"`
预期：checkout 命令和 backend 测试 PASS。

## 任务 2：Service 认证重试

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `SvnServiceTests` 中新增：

```swift
func testCheckoutPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.checkoutErrors = [.authentication]
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)
    let destination = URL(fileURLWithPath: "/tmp/wc")

    try await service.checkout(url: "file:///repo/trunk", to: destination, depth: .files, auth: nil)
    let requestedWorkingCopies = await provider.recordedWorkingCopies()

    XCTAssertEqual(requestedWorkingCopies, [destination])
    XCTAssertEqual(backend.calls.map(\.name), ["checkout", "checkout"])
    XCTAssertEqual(backend.checkoutCredentials, [nil, Credential(username: "u", password: "p")])
    XCTAssertEqual(backend.checkoutDepths, [.files, .files])
}
```

更新 `MockSvnBackend.checkout` 签名，记录 depth/auth。

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnServiceTests/testCheckoutPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure`
预期：编译失败或测试失败，提示 `SvnService.checkout` 缺失。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnService.checkout(url:to:depth:auth:)`，使用 `withWriteLock(wc: destination, operation: "checkout")`。
- 内部走 `retryingAuthentication(wc: destination, initialAuth: auth)`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter SvnServiceTests/testCheckoutPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure`
预期：service checkout 测试 PASS。

## 任务 3：真实 svn 浅检出集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写失败的测试**

新增集成测试：

```swift
func testCheckoutWithEmptyDepthCreatesWorkingCopyWithoutChildren() async throws {
    let fixture = try makeFixture()

    try await fixture.backend.checkout(
        url: fixture.trunkURL,
        to: fixture.workingCopy,
        depth: .empty,
        auth: nil
    )
    let statuses = try await fixture.backend.status(wc: fixture.workingCopy)

    XCTAssertEqual(statuses, [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("src").path))
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testCheckoutWithEmptyDepthCreatesWorkingCopyWithoutChildren`
预期：在实现前编译失败；实现后若行为错误则断言失败。

- [x] **步骤 3：编写最少实现代码**

若前两任务实现正确，此任务通常无需额外生产代码；只需更新旧集成测试调用以使用默认参数或显式 `.infinity`。

- [x] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Backend/SvnBackend.swift Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Sources/MacSvnCore/Backend/SvnCliBackend.swift Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p2-checkout-depth.md
git commit -m "feat: add P2 checkout depth support"
```
