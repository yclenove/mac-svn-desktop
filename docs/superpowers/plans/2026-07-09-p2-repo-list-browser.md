# P2 Repo List Browser 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 仓库浏览器的远端目录懒加载底座，覆盖 FR-RB-01/02 的 Core 非 UI 部分：`svn list --xml`、远端条目元数据解析、backend/service 调用和 ViewModel 状态层。

**架构：** 新增 `RemoteEntry` / `RemoteEntryKind` 模型和 `ListXMLParser`；扩展 `SvnCommandBuilder`、`SvnBackend`、`SvnCliBackend` 与 `SvnService` 支持远端 `list(url:depth:auth:)`。新增 `RepoBrowserViewModel` 依赖 `RepoListProviding`，按 URL 懒加载 children，并保留 loaded/error 状态。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Foundation XMLParser、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `RemoteEntryKind`、`RemoteEntry`。
- 创建：`Sources/MacSvnCore/Parsers/ListXMLParser.swift`
  解析 `svn list --xml` 输出为 `[RemoteEntry]`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `list(url:depth:authArguments:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `list(url:depth:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 list 命令、认证 stdin 和 XML parser 调用。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  实现远端 list 查询和认证重试。
- 创建：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
  定义 `RepoListProviding`、`RepoBrowserState`、`RepoBrowserViewModel`。
- 创建：`Tests/MacSvnCoreTests/ListXMLParserTests.swift`
  覆盖目录/文件元数据、非法 XML。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 list 命令。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 list backend auth/stdin/parser。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 list 认证重试。
- 创建：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`
  覆盖懒加载、缓存状态、错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `svn list --xml --depth immediates`。
- 创建：`docs/superpowers/plans/2026-07-09-p2-repo-list-browser.md`
  记录此切片计划。

## 任务 1：List XML parser

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Parsers/ListXMLParser.swift`
- 创建：`Tests/MacSvnCoreTests/ListXMLParserTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `ListXMLParserTests`：

```swift
func testParsesRemoteEntriesWithMetadata() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <lists>
      <list path="file:///repo/trunk">
        <entry kind="dir">
          <name>src</name>
          <commit revision="7">
            <author>yangchao</author>
            <date>2026-07-09T04:00:00.000000Z</date>
          </commit>
        </entry>
        <entry kind="file">
          <name>README.txt</name>
          <size>12</size>
          <commit revision="8">
            <author>alice</author>
            <date>2026-07-09T05:00:00.000000Z</date>
          </commit>
        </entry>
      </list>
    </lists>
    """

    let entries = try ListXMLParser.parse(Data(xml.utf8))

    XCTAssertEqual(entries, [
        RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: Revision(7), author: "yangchao", date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T04:00:00.000000Z")),
        RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 12, revision: Revision(8), author: "alice", date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T05:00:00.000000Z"))
    ])
}

func testInvalidListXMLThrowsParseError() {
    XCTAssertThrowsError(try ListXMLParser.parse(Data("<lists>".utf8))) { error in
        guard case .parse = error as? SvnError else {
            return XCTFail("Expected SvnError.parse, got \\(error)")
        }
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter ListXMLParserTests`
预期：编译失败，提示 `ListXMLParser` / `RemoteEntry` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RemoteEntryKind`：`.file/.directory/.unknown`，`init(rawSvnKind:)` 将 `"dir"` 映射为 `.directory`。
- `RemoteEntry` 字段：`name/path/kind/size/revision/author/date`。
- `ListXMLParser` 使用 `XMLParserDelegate`，解析 `entry@kind`、`name`、`size`、`commit@revision`、`author`、`date`。
- `path` 先等于 `name`；后续 ViewModel 再拼接 URL。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter ListXMLParserTests`
预期：parser 测试 PASS。

## 任务 2：Command/backend/service list

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

在 `SvnCommandBuilderTests` 新增：

```swift
func testListUsesXmlDepthAuthAndUrl() {
    let command = SvnCommandBuilder.list(
        url: "file:///repo/trunk",
        depth: .immediates,
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "list", "--xml", "--non-interactive",
        "--depth", "immediates",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk"
    ])
}
```

在 `SvnCliBackendTests` 新增：

```swift
func testListPassesDepthAuthStdinAndParsesEntries() async throws {
    let xml = """
    <lists><list path="file:///repo/trunk"><entry kind="file"><name>README.txt</name><size>5</size><commit revision="2"><author>a</author></commit></entry></list></lists>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let entries = try await backend.list(
        url: "file:///repo/trunk",
        depth: .immediates,
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(entries.map(\\.name), ["README.txt"])
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\\n".utf8))
    XCTAssertEqual(runner.calls.single?.arguments, [
        "list", "--xml", "--non-interactive",
        "--depth", "immediates",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

在 `SvnServiceTests` 新增：

```swift
func testListPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.listErrors = [.authentication]
    backend.listResult = [RemoteEntry(name: "trunk", path: "trunk", kind: .directory, size: nil, revision: Revision(1), author: "a", date: nil)]
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let entries = try await service.list(url: "file:///repo", depth: .immediates, auth: nil)
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(entries.map(\\.name), ["trunk"])
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo")!])
    XCTAssertEqual(backend.calls.map(\\.name), ["list", "list"])
    XCTAssertEqual(backend.listCredentials, [nil, Credential(username: "u", password: "p")])
}
```

在集成测试新增真实 `list`：

```swift
func testListRemoteTrunkReturnsImmediateChildrenMetadata() async throws {
    let fixture = try makeFixture()

    let entries = try await fixture.backend.list(url: fixture.trunkURL, depth: .immediates, auth: nil)
    let names = Set(entries.map(\\.name))

    XCTAssertTrue(names.contains("README.txt"))
    XCTAssertTrue(names.contains("src"))
    XCTAssertEqual(entries.first(where: { $0.name == "src" })?.kind, .directory)
    XCTAssertEqual(entries.first(where: { $0.name == "README.txt" })?.kind, .file)
    XCTAssertNotNil(entries.first(where: { $0.name == "README.txt" })?.revision)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testList|SvnCliBackendTests/testList|SvnServiceTests/testList|SvnCliBackendIntegrationTests/testListRemote"`
预期：编译失败或测试失败。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnCommandBuilder.list(url:depth:authArguments:)`。
- `SvnBackend.list(url:depth:auth:)`。
- `SvnCliBackend.list(url:depth:auth:)`。
- `SvnService.list(url:depth:auth:)`，认证失败后用 `CredentialProviding` 重试一次；credential scope 用 `URL(string: url) ?? URL(fileURLWithPath: url)`。
- 更新 `MockSvnBackend`。

- [x] **步骤 4：运行目标测试验证通过**

运行：同上目标测试。
预期：全部 PASS。

## 任务 3：RepoBrowserViewModel 懒加载

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `RepoBrowserViewModelTests`：

```swift
@MainActor
func testLoadChildrenStoresEntriesByUrlAndUsesImmediateDepth() async {
    let provider = FakeRepoListProvider(result: .success([
        RemoteEntry(name: "trunk", path: "trunk", kind: .directory, size: nil, revision: Revision(1), author: "a", date: nil)
    ]))
    let viewModel = RepoBrowserViewModel(listProvider: provider)

    await viewModel.loadChildren(of: "file:///repo")

    XCTAssertEqual(viewModel.state(for: "file:///repo"), .loaded)
    XCTAssertEqual(viewModel.children(of: "file:///repo").map(\\.name), ["trunk"])
    XCTAssertEqual(await provider.recordedCalls(), [
        RepoListCall(url: "file:///repo", depth: .immediates, auth: nil)
    ])
}

@MainActor
func testLoadChildrenFailureStoresError() async {
    let provider = FakeRepoListProvider(result: .failure(SvnError.network(detail: "offline")))
    let viewModel = RepoBrowserViewModel(listProvider: provider)

    await viewModel.loadChildren(of: "file:///repo")

    XCTAssertEqual(viewModel.state(for: "file:///repo"), .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.children(of: "file:///repo"), [])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：编译失败，提示 ViewModel 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RepoListProviding` 协议。
- `RepoBrowserState`: `.idle/.loading/.loaded/.error(String)`。
- `RepoBrowserViewModel.loadChildren(of:auth:)`：固定 `.immediates` depth，按 URL 保存 state 和 children。
- `SvnService: RepoListProviding`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：ViewModel 测试 PASS。

## 任务 4：全量验证与提交

- [x] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Parsers/ListXMLParser.swift Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Sources/MacSvnCore/Backend/SvnBackend.swift Sources/MacSvnCore/Backend/SvnCliBackend.swift Sources/MacSvnCore/Services/SvnService.swift Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift Tests/MacSvnCoreTests/ListXMLParserTests.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p2-repo-list-browser.md
git commit -m "feat: add P2 repo list browser support"
```
