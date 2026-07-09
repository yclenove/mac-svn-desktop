# P2 Remote Log 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 仓库浏览器远端目录/文件日志能力，覆盖 FR-RB-05 与 FR-LG-05 的 Core 非 UI 部分。

**架构：** 保留现有 WC `log(wc:target:...)` 语义，新增远端 `remoteLog(url:from:batch:verbose:auth:)` 链路，避免把远端 URL 塞进工作副本 currentDirectory 调用。`SvnCommandBuilder.log` 复用同一参数构造并支持认证参数；`SvnCliBackend` 对远端 URL 使用 `currentDirectory: nil`，`SvnService` 提供认证重试；`RepoBrowserViewModel` 暴露按 URL 缓存的日志状态与分页数据。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Foundation XMLParser、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  让 `log(target:from:batch:verbose:)` 支持可选 `authArguments`，认证参数位于 `target` 前。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `remoteLog(url:from:batch:verbose:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `remoteLog`，复用 `LogXMLParser` 和 `AuthArguments`，远端 URL 使用 `normalizedRemoteURL`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 service 层 `remoteLog`，用 URL scope 请求凭据并认证重试一次。
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
  新增 `RepoLogProviding`、`RepoLogState`、日志缓存、`loadLog` / `loadMoreLog`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖远端 log 认证参数顺序。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 remote log 认证 stdin、`currentDirectory: nil`、XML 解析。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 remote log 认证失败后的凭据重试。
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`
  覆盖仓库浏览器日志首屏、加载更多、短页结束与错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `svn log --xml -v` 读取远端 trunk 日志。

## 任务 1：Command/backend/service remote log

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testLogCanIncludeAuthenticationArgumentsBeforeTarget() {
    let command = SvnCommandBuilder.log(
        target: "file:///repo/trunk",
        from: Revision(20),
        batch: 50,
        verbose: true,
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "log", "--xml", "-v", "--non-interactive",
        "-r", "20:0",
        "-l", "50",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testRemoteLogPassesAuthStdinRunsWithoutWorkingCopyAndParsesEntries() async throws {
    let xml = """
    <log><logentry revision="7"><author>a</author><msg>remote msg</msg></logentry></log>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let entries = try await backend.remoteLog(
        url: "file:///repo/trunk",
        from: Revision(7),
        batch: 10,
        verbose: true,
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(entries.map(\.revision), [Revision(7)])
    XCTAssertEqual(entries.first?.message, "remote msg")
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
    XCTAssertEqual(runner.calls.single?.arguments, [
        "log", "--xml", "-v", "--non-interactive",
        "-r", "7:0",
        "-l", "10",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

在 `SvnServiceTests` 中新增：

```swift
func testRemoteLogPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.remoteLogErrors = [.authentication]
    backend.remoteLogResult = [
        LogEntry(revision: Revision(7), author: "a", date: nil, message: "m", changedPaths: [])
    ]
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let entries = try await service.remoteLog(url: "file:///repo/trunk", from: Revision(7), batch: 10, verbose: true, auth: nil)
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(entries.map(\.revision), [Revision(7)])
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk")!])
    XCTAssertEqual(backend.calls.map(\.name), ["remoteLog", "remoteLog"])
    XCTAssertEqual(backend.remoteLogCredentials, [nil, Credential(username: "u", password: "p")])
}
```

在集成测试中新增：

```swift
func testRemoteLogReadsTrunkHistoryWithoutCheckout() async throws {
    let fixture = try makeFixture()

    let entries = try await fixture.backend.remoteLog(
        url: fixture.trunkURL,
        from: Revision(1),
        batch: 10,
        verbose: true,
        auth: nil
    )

    XCTAssertEqual(entries.first?.revision, Revision(1))
    XCTAssertFalse(entries.first?.changedPaths.isEmpty ?? true)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testLogCanIncludeAuthenticationArgumentsBeforeTarget|SvnCliBackendTests/testRemoteLog|SvnServiceTests/testRemoteLog|SvnCliBackendIntegrationTests/testRemoteLogReadsTrunkHistoryWithoutCheckout"
```

预期：编译失败或测试失败，提示 `authArguments` 或 `remoteLog` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnCommandBuilder.log(... authArguments: [String] = [])`，保持现有 WC log 测试参数不变，新增认证参数在 target 之前。
- `SvnBackend.remoteLog(url:from:batch:verbose:auth:)`。
- `SvnCliBackend.remoteLog`：用 `AuthArguments.build`，`currentDirectory: nil`，`SvnCommandBuilder.log(target: normalizedRemoteURL(url), ...)`。
- `SvnService.remoteLog`：用 `URL(string: url) ?? URL(fileURLWithPath: url)` 作为 credential scope，认证失败后重试一次。
- 更新 `MockSvnBackend` 记录 remote log 调用、auth、错误序列。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试。

预期：目标测试全部 PASS。

## 任务 2：RepoBrowserViewModel remote log 状态与分页

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `RepoBrowserViewModelTests` 中新增：

```swift
@MainActor
func testLoadLogStoresEntriesAndUsesRemoteEntryUrl() async {
    let provider = FakeRepoBrowserProvider(
        listResult: .success([]),
        catResult: .success(Data()),
        logResults: [.success([logEntry(Revision(7)), logEntry(Revision(6))])]
    )
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, logProvider: provider, logBatchSize: 2)
    let entry = RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 10, revision: Revision(7), author: nil, date: nil)

    await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(7))
    let calls = await provider.recordedLogCalls()

    XCTAssertEqual(viewModel.logState(for: "file:///repo/trunk/README.txt"), .loaded)
    XCTAssertEqual(viewModel.logEntries(for: "file:///repo/trunk/README.txt").map(\.revision), [Revision(7), Revision(6)])
    XCTAssertTrue(viewModel.hasMoreLog(for: "file:///repo/trunk/README.txt"))
    XCTAssertEqual(calls, [
        RepoLogCall(url: "file:///repo/trunk/README.txt", from: Revision(7), batch: 2, verbose: true, auth: nil)
    ])
}
```

继续新增加载更多、短页结束和错误状态测试：

```swift
@MainActor
func testLoadMoreLogStartsBeforeLowestLoadedRevisionAndStopsOnShortPage() async {
    let provider = FakeRepoBrowserProvider(
        listResult: .success([]),
        catResult: .success(Data()),
        logResults: [
            .success([logEntry(Revision(10)), logEntry(Revision(9))]),
            .success([logEntry(Revision(8))])
        ]
    )
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, logProvider: provider, logBatchSize: 2)
    let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

    await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(10))
    await viewModel.loadMoreLog(entry: entry, baseURL: "file:///repo/trunk")
    let url = "file:///repo/trunk/src"

    XCTAssertEqual(viewModel.logEntries(for: url).map(\.revision), [Revision(10), Revision(9), Revision(8)])
    XCTAssertFalse(viewModel.hasMoreLog(for: url))
}

@MainActor
func testLoadLogFailureStoresErrorAndClearsEntries() async {
    let provider = FakeRepoBrowserProvider(
        listResult: .success([]),
        catResult: .success(Data()),
        logResults: [.failure(SvnError.network(detail: "offline"))]
    )
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, logProvider: provider)
    let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

    await viewModel.loadLog(entry: entry, baseURL: "file:///repo/trunk", from: Revision(10))

    XCTAssertEqual(viewModel.logState(for: "file:///repo/trunk/src"), .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.logEntries(for: "file:///repo/trunk/src"), [])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter RepoBrowserViewModelTests
```

预期：编译失败或新增测试失败，提示 repo log API 未实现。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RepoLogProviding` 协议：`remoteLog(url:from:batch:verbose:auth:)`。
- `RepoLogState`：`.idle/.loading/.loadingMore/.loaded/.error(String)`。
- `RepoBrowserViewModel` 新增 `logProvider`、`logBatchSize`、`logStatesByURL`、`logEntriesByURL`、`nextLogRevisionByURL`、`hasMoreLogByURL`。
- 初始化器新增可选 `logProvider` 和 `logBatchSize`；默认尝试 `listProvider as? RepoLogProviding`。
- `loadLog(entry:baseURL:from:auth:)`：拼接 URL，清空旧 entries，调用 provider，按短页更新 pagination。
- `loadMoreLog(entry:baseURL:auth:)`：无下一页、已结束或正在加载时直接返回；成功追加 entries；失败保留旧 entries 并置错误状态。
- `extension SvnService: RepoLogProviding {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter RepoBrowserViewModelTests
```

预期：全部 ViewModel 测试 PASS。

## 任务 3：全量验证与提交

**文件：**
- 上述全部文件
- 新增：`docs/superpowers/plans/2026-07-09-p2-remote-log.md`

- [x] **步骤 1：运行目标测试**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testLogCanIncludeAuthenticationArgumentsBeforeTarget|SvnCliBackendTests/testRemoteLog|SvnServiceTests/testRemoteLog|RepoBrowserViewModelTests|SvnCliBackendIntegrationTests/testRemoteLogReadsTrunkHistoryWithoutCheckout"
```

预期：目标测试全部 PASS。

- [x] **步骤 2：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p2-remote-log.md
git commit -m "feat: add P2 repo remote log support"
```
