# P2 Repo Cat Preview 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 仓库浏览器远端文本文件预览底座，覆盖 FR-RB-03 的 Core 非 UI 部分：`svn cat`、认证 stdin、5 MB 大小限制、二进制/超限提示和 ViewModel 状态层。

**架构：** 在现有 `list` 栈旁边新增 `cat(url:revision:sizeLimit:auth:)`，继续由 `SvnCommandBuilder` 固定参数顺序、`SvnCliBackend` 调用真实 CLI、`SvnService` 做认证重试。`RepoBrowserViewModel` 新增 preview 状态，优先用 `RemoteEntry.size` 做 5 MB 前置阻断，后端再对实际 `Data` 长度兜底检查。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Errors/SvnError.swift`
  新增 `.fileTooLarge(limit:actual:)` 与 `.binaryFile`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `cat(url:revision:authArguments:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `cat(url:revision:sizeLimit:auth:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `cat` 命令、认证 stdin 和 sizeLimit 兜底。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  实现远端 cat 查询和认证重试。
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
  新增 `RepoPreviewProviding`、`RepoPreviewState`、预览缓存与 `preview(entry:baseURL:auth:)`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 cat 命令参数。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 cat backend auth/stdin、revision、size limit。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 cat 认证重试。
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`
  覆盖文本预览、超限阻断、二进制提示和错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `svn cat` 读取中文远端文件内容。

## 任务 1：Command/backend/service cat

**文件：**
- 修改：`Sources/MacSvnCore/Errors/SvnError.swift`
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
func testCatUsesRevisionAuthenticationAndUrl() {
    let command = SvnCommandBuilder.cat(
        url: "file:///repo/trunk/README.txt",
        revision: Revision(7),
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "cat", "--non-interactive",
        "-r", "7",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk/README.txt"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testCatPassesRevisionAuthStdinAndReturnsData() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("hello\n".utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let data = try await backend.cat(
        url: "file:///repo/trunk/README.txt",
        revision: Revision(7),
        sizeLimit: 10,
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.arguments, [
        "cat", "--non-interactive",
        "-r", "7",
        "--username", "u", "--password-from-stdin",
        "file:///repo/trunk/README.txt"
    ])
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}

func testCatThrowsFileTooLargeWhenOutputExceedsLimit() async {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("abcdef".utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    do {
        _ = try await backend.cat(url: "file:///repo/trunk/big.txt", revision: nil, sizeLimit: 5, auth: nil)
        XCTFail("Expected fileTooLarge")
    } catch let error as SvnError {
        XCTAssertEqual(error, .fileTooLarge(limit: 5, actual: 6))
    } catch {
        XCTFail("Expected SvnError, got \(error)")
    }
}
```

在 `SvnServiceTests` 中新增：

```swift
func testCatPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.catErrors = [.authentication]
    backend.catResult = Data("hello".utf8)
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let data = try await service.cat(url: "file:///repo/trunk/README.txt", revision: nil, sizeLimit: 5, auth: nil)
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(String(data: data, encoding: .utf8), "hello")
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk/README.txt")!])
    XCTAssertEqual(backend.calls.map(\.name), ["cat", "cat"])
    XCTAssertEqual(backend.catCredentials, [nil, Credential(username: "u", password: "p")])
    XCTAssertEqual(backend.catSizeLimits, [5, 5])
}
```

在集成测试新增：

```swift
func testCatRemoteFileReturnsUtf8Contents() async throws {
    let fixture = try makeFixture()

    let data = try await fixture.backend.cat(
        url: "\(fixture.trunkURL)/中文文件.txt",
        revision: nil,
        sizeLimit: 5 * 1024 * 1024,
        auth: nil
    )

    XCTAssertEqual(String(data: data, encoding: .utf8), "中文内容\n")
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testCat|SvnCliBackendTests/testCat|SvnServiceTests/testCat|SvnCliBackendIntegrationTests/testCatRemote"
```

预期：编译失败或测试失败，提示 cat API 和错误枚举未实现。

- [x] **步骤 3：编写最少实现代码**

实现：

- `SvnError.fileTooLarge(limit:actual:)` 和 `SvnError.binaryFile`。
- `SvnCommandBuilder.cat(url:revision:authArguments:)`，revision 为 nil 时不输出 `-r`。
- `SvnBackend.cat(url:revision:sizeLimit:auth:)`。
- `SvnCliBackend.cat` 通过 `AuthArguments.build` 传 stdin，`currentDirectory: nil`，成功后若 `stdout.count > sizeLimit` 抛 `.fileTooLarge(limit:actual:)`。
- `SvnService.cat` 使用 `URL(string: url) ?? URL(fileURLWithPath: url)` 作为 credential scope，认证失败后重试一次。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试。预期：全部 PASS。

## 任务 2：RepoBrowserViewModel preview 状态

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `RepoBrowserViewModelTests` 中新增：

```swift
@MainActor
func testPreviewTextFileFetchesCatDataAndDecodesUtf8() async {
    let provider = FakeRepoBrowserProvider(
        listResult: .success([]),
        catResult: .success(Data("中文内容\n".utf8))
    )
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider)
    let entry = RemoteEntry(name: "中文文件.txt", path: "中文文件.txt", kind: .file, size: 13, revision: Revision(2), author: nil, date: nil)

    await viewModel.preview(entry: entry, baseURL: "file:///repo/trunk")
    let calls = await provider.recordedCatCalls()

    XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/中文文件.txt"), .loaded("中文内容\n"))
    XCTAssertEqual(calls, [
        RepoCatCall(url: "file:///repo/trunk/中文文件.txt", revision: nil, sizeLimit: RepoBrowserViewModel.defaultPreviewSizeLimit, auth: nil)
    ])
}

@MainActor
func testPreviewRejectsDirectoriesBinaryFilesAndKnownOversizedFilesBeforeCat() async {
    let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider)

    await viewModel.preview(
        entry: RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil),
        baseURL: "file:///repo/trunk"
    )
    await viewModel.preview(
        entry: RemoteEntry(name: "big.txt", path: "big.txt", kind: .file, size: RepoBrowserViewModel.defaultPreviewSizeLimit + 1, revision: nil, author: nil, date: nil),
        baseURL: "file:///repo/trunk"
    )

    XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/src"), .unsupported("directory"))
    XCTAssertEqual(viewModel.previewState(for: "file:///repo/trunk/big.txt"), .tooLarge(limit: RepoBrowserViewModel.defaultPreviewSizeLimit, actual: RepoBrowserViewModel.defaultPreviewSizeLimit + 1))
    XCTAssertTrue(await provider.recordedCatCalls().isEmpty)
}
```

同时新增 provider 返回含 NUL 字节时置 `.unsupported("binary")`、provider 抛 `.fileTooLarge` 时置 `.tooLarge`、普通错误置 `.error(String)`。

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：编译失败或新增测试失败，提示 preview API 未实现。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RepoPreviewProviding` 协议：`cat(url:revision:sizeLimit:auth:)`。
- `RepoPreviewState`：`.idle/.loading/.loaded(String)/.tooLarge(limit:actual:)/.unsupported(String)/.error(String)`。
- `RepoBrowserViewModel.defaultPreviewSizeLimit = 5 * 1024 * 1024`。
- 初始化器新增可选 `previewProvider`，默认使用 `listProvider as? RepoPreviewProviding`。
- `preview(entry:baseURL:auth:)` 拼接远端 URL；目录或非 file 直接 `.unsupported("directory")`；已知 size 超限直接 `.tooLarge`；cat 后若含 NUL 字节直接 `.unsupported("binary")`；UTF-8 解码失败直接 `.unsupported("binary")`；成功保存 `.loaded(text)`。
- `extension SvnService: RepoPreviewProviding {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：全部 PASS。

## 任务 3：全量验证与提交

- [x] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p2-repo-cat-preview.md
git commit -m "feat: add P2 repo file preview support"
```
