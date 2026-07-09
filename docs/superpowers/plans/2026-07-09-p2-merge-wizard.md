# P2 Merge Wizard 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-BR-04 的 Core 非 UI 部分：选择来源分支和可选 revision 范围，先用 `svn merge --dry-run` 预览受影响文件，再执行真实 merge。

**架构：** 新增 `RevisionRange`、`MergeAffectedPath`、`MergeSummary` 模型与容错文本解析器 `MergeOutputParser`。CLI 层通过 `svn merge --accept postpone --non-interactive [--dry-run] [-r A:B] <source>` 执行；Service 层复用每 WC 写锁与认证重试；ViewModel 层提供 preview/merge 两条状态流。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `RevisionRange`、`MergeAction`、`MergeAffectedPath`、`MergeSummary`。
- 创建：`Sources/MacSvnCore/Parsers/MergeOutputParser.swift`
  解析 `svn merge` 与 `svn merge --dry-run` 的文本输出，忽略无法识别的说明行。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `merge(source:range:dryRun:authArguments:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `merge(wc:source:range:dryRun:auth:) -> MergeSummary`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 merge 命令，工作目录为 WC，stdout 交给 `MergeOutputParser`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `merge(...)`，用写锁串行化，认证失败后按 source URL scope 重试一次。
- 创建：`Sources/MacSvnCore/ViewModels/MergeWizardViewModel.swift`
  定义 `MergeProviding`、`MergeWizardState`、`MergeWizardViewModel`。
- 创建：`Tests/MacSvnCoreTests/MergeOutputParserTests.swift`
  覆盖 merge action、冲突、mergeinfo property 行和说明行容错。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 merge 参数顺序、dry-run、revision range、认证参数。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 merge stdin、工作目录、解析 summary、密码不进 argv。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 merge 认证重试与写锁操作名。
- 创建：`Tests/MacSvnCoreTests/MergeWizardViewModelTests.swift`
  覆盖 preview、execute、空 source 阻断、错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖 copy 创建分支、分支提交、切回 trunk、dry-run 预览和真实 merge。

## 任务 1：Merge 模型与文本解析器

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Parsers/MergeOutputParser.swift`
- 创建：`Tests/MacSvnCoreTests/MergeOutputParserTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `MergeOutputParserTests`：

```swift
func testParsesMergeActionsAndAffectedPaths() throws {
    let output = """
    --- Merging r2 into '.':
    U    README.txt
    A    Sources/New.swift
    D    old.txt
    C    conflict.txt
    G    merged.txt
    --- Recording mergeinfo for merge of r2 into '.':
     U   .
    """

    let summary = try MergeOutputParser.parse(output)

    XCTAssertEqual(summary.updated, 2)
    XCTAssertEqual(summary.added, 1)
    XCTAssertEqual(summary.deleted, 1)
    XCTAssertEqual(summary.conflicted, 1)
    XCTAssertEqual(summary.merged, 1)
    XCTAssertEqual(summary.affectedPaths.map(\.path), [
        "README.txt", "Sources/New.swift", "old.txt", "conflict.txt", "merged.txt", "."
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter MergeOutputParserTests`
预期：编译失败，提示 `MergeOutputParser` / `MergeSummary` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `RevisionRange(start:end:)`，description 为 `start:end`。
- `MergeAction`：`added`、`updated`、`deleted`、`conflicted`、`merged`、`existed`、`replaced`、`unknown(Character)`。
- `MergeAffectedPath(action:path:)`。
- `MergeSummary` 计数字段与 `affectedPaths`。
- `MergeOutputParser.parse(_:)`：只解析形如 `U    path`、` C   path` 的 action 行，忽略 `--- Merging ...` 等说明行。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter MergeOutputParserTests`
预期：目标测试 PASS。

## 任务 2：命令构造与 CLI backend merge

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testMergeUsesPostponeDryRunRangeAuthAndSource() {
    let command = SvnCommandBuilder.merge(
        source: "file:///repo/branches/feature-one",
        range: RevisionRange(start: Revision(2), end: Revision(5)),
        dryRun: true,
        authArguments: ["--username", "u", "--password-from-stdin"]
    )

    XCTAssertEqual(command.arguments, [
        "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
        "--username", "u", "--password-from-stdin",
        "-r", "2:5",
        "file:///repo/branches/feature-one"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testMergePassesAuthStdinRunsInWorkingCopyAndParsesSummary() async throws {
    let output = "U    README.txt\n"
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let summary = try await backend.merge(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        source: "file:///repo/branches/feature-one",
        range: RevisionRange(start: Revision(2), end: Revision(5)),
        dryRun: true,
        auth: Credential(username: "u", password: "secret")
    )

    XCTAssertEqual(summary.updated, 1)
    XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testMerge|SvnCliBackendTests/testMerge"`
预期：编译失败，提示 merge API 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnCommandBuilder.merge(source:range:dryRun:authArguments:)`。
- `SvnBackend.merge(wc:source:range:dryRun:auth:)`。
- `SvnCliBackend.merge(...)`，用 `AuthArguments.build`，`currentDirectory: wc.path`，解析 stdout。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testMerge|SvnCliBackendTests/testMerge"`
预期：目标测试 PASS。

## 任务 3：SvnService merge 写锁与认证

**文件：**
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnServiceTests` 中新增：

```swift
func testMergePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.mergeErrors = [.authentication]
    backend.mergeResult = MergeSummary(updated: 1, affectedPaths: [
        MergeAffectedPath(action: .updated, path: "README.txt")
    ])
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let summary = try await service.merge(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        source: "file:///repo/branches/feature-one",
        range: nil,
        dryRun: true,
        auth: nil
    )
    let requestedScopes = await provider.recordedWorkingCopies()

    XCTAssertEqual(summary.updated, 1)
    XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/feature-one")!])
    XCTAssertEqual(backend.calls.map(\.name), ["merge", "merge"])
    XCTAssertEqual(backend.mergeCredentials, [nil, Credential(username: "u", password: "p")])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnServiceTests/testMerge`
预期：编译失败，提示 service/backend merge 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnService.merge(wc:source:range:dryRun:auth:)`。
- 用 `withWriteLock(wc: operation: "merge")` 包裹 backend 调用。
- 认证 retry scope 使用 `URL(string: source) ?? URL(fileURLWithPath: source)`。
- 更新 `MockSvnBackend` 记录 merge 调用、凭据和错误序列。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter SvnServiceTests/testMerge`
预期：目标测试 PASS。

## 任务 4：MergeWizardViewModel

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/MergeWizardViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/MergeWizardViewModelTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `MergeWizardViewModelTests`，覆盖：

```swift
@MainActor
func testPreviewUsesDryRunAndStoresSummary() async {
    let provider = FakeMergeProvider(results: [.success(MergeSummary(updated: 1))])
    let viewModel = MergeWizardViewModel(provider: provider)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    await viewModel.preview(wc: wc, source: "file:///repo/branches/feature-one", range: nil, auth: nil)

    XCTAssertEqual(viewModel.state, .previewReady(MergeSummary(updated: 1)))
    XCTAssertEqual(await provider.recordedCalls().map(\.dryRun), [true])
}

@MainActor
func testExecuteMergeUsesNonDryRunAndStoresSummary() async {
    let provider = FakeMergeProvider(results: [.success(MergeSummary(merged: 1))])
    let viewModel = MergeWizardViewModel(provider: provider)

    await viewModel.merge(wc: URL(fileURLWithPath: "/tmp/wc"), source: "file:///repo/branches/feature-one", range: nil, auth: nil)

    XCTAssertEqual(viewModel.state, .completed(MergeSummary(merged: 1)))
    XCTAssertEqual(await provider.recordedCalls().map(\.dryRun), [false])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter MergeWizardViewModelTests`
预期：编译失败，提示 `MergeWizardViewModel` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `MergeProviding` 协议，签名与 `SvnService.merge` 一致。
- `MergeWizardState`：`idle`、`previewing`、`previewReady(MergeSummary)`、`merging`、`completed(MergeSummary)`、`error(String)`。
- `preview(...)`、`merge(...)`，空 source 返回 `.error("emptyMergeSource")`。
- `extension SvnService: MergeProviding {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter MergeWizardViewModelTests`
预期：目标测试 PASS。

## 任务 5：真实 SVN 分支 merge 集成

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的测试**

新增：

```swift
func testServicePreviewAndMergeBranchChangesIntoTrunk() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let branchURL = "\(fixture.repositoryURL)/branches/merge-source"

    _ = try await service.copy(source: fixture.trunkURL, destination: branchURL, message: "create merge branch", auth: nil)
    try await fixture.backend.checkout(url: branchURL, to: fixture.workingCopy)
    try "branch change\n".write(to: fixture.workingCopy.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    _ = try await service.commit(wc: fixture.workingCopy, paths: ["README.txt"], message: "branch change", auth: nil)
    _ = try await service.switchTo(wc: fixture.workingCopy, url: fixture.trunkURL, auth: nil)

    let preview = try await service.merge(wc: fixture.workingCopy, source: branchURL, range: nil, dryRun: true, auth: nil)
    let summary = try await service.merge(wc: fixture.workingCopy, source: branchURL, range: nil, dryRun: false, auth: nil)

    XCTAssertTrue(preview.affectedPaths.map(\.path).contains("README.txt"))
    XCTAssertTrue(summary.affectedPaths.map(\.path).contains("README.txt"))
    XCTAssertEqual(try String(contentsOf: fixture.workingCopy.appendingPathComponent("README.txt"), encoding: .utf8), "branch change\n")
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testServicePreviewAndMergeBranchChangesIntoTrunk`
预期：实现前编译失败或 merge API 缺失。

- [ ] **步骤 3：运行目标测试验证通过**

运行：`swift test --filter "MergeOutputParserTests|SvnCommandBuilderTests/testMerge|SvnCliBackendTests/testMerge|SvnServiceTests/testMerge|MergeWizardViewModelTests|SvnCliBackendIntegrationTests/testServicePreviewAndMergeBranchChangesIntoTrunk"`
预期：目标测试 PASS。

- [ ] **步骤 4：全量验证与提交**

运行：
- `swift test`
- `git diff --check`
- `git add docs/superpowers/plans/2026-07-09-p2-merge-wizard.md Sources/MacSvnCore Tests/MacSvnCoreTests`
- `git diff --cached --check`
- `git commit -m "feat: add P2 merge wizard core"`
- `git diff HEAD^ HEAD --check`
- `git status --short --branch`

预期：测试 0 failures，空白检查无输出，提交后工作区干净。
