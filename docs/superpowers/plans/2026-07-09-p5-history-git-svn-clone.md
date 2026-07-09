# P5 History Git-SVN Clone 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-02/03` 的历史保真迁移执行底座：生成 authors.txt，调用 `git svn clone` 完成基础历史迁移，并返回可审计报告。

**架构：** 沿用现有 `GitCommandBuilder` / `GitCliBackend` / `GitMigrationService` 分层。`GitCommandBuilder` 负责拼装 `git svn clone` 参数；`GitCliBackend` 运行命令但不接触 SVN 密码；`GitMigrationService` 先校验 authors 映射与目标目录，再导出 authors.txt 并执行 clone。`GitMigrationViewModel` 只暴露状态与输入校验。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Git CLI、git-svn、Foundation `ProcessRunning` 注入。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
  新增 `svnClone(sourceURL:destination:authorsFile:layout:revisionRange:username:)`，支持标准布局、自定义布局、revision 范围和用户名参数。
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
  新增 `svnClone(...)` 协议方法。
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
  实现 `git svn clone` 命令执行，非零退出继续映射为 `SvnError.other`。
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  扩展 `GitMigrationMode`、`GitMigrationStep` 和 `GitMigrationReport`，记录历史迁移 authors 文件、布局和 revision 范围。
- 修改：`Sources/MacSvnCore/Services/GitMigrationService.swift`
  新增 `historyMigrate(...)`，组合 authors.txt 导出与 `git svn clone`。
- 修改：`Sources/MacSvnCore/ViewModels/GitMigrationViewModel.swift`
  新增历史迁移入口，复用 `.running/.completed/.error` 状态。
- 修改测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitMigrationServiceTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitMigrationViewModelTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：git svn clone 命令与 backend

**文件：**
- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
- 测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitCommandBuilderTests` 新增：

```swift
func testSvnCloneUsesStandardLayoutAuthorsFileRevisionAndUsername() {
    let layout = GitMigrationRepositoryLayout(
        kind: .standard,
        trunkPath: "trunk",
        branchesPath: "branches",
        tagsPath: "tags",
        confidence: 1
    )

    XCTAssertEqual(
        GitCommandBuilder.svnClone(
            sourceURL: "file:///repo",
            destination: URL(fileURLWithPath: "/tmp/git-repo"),
            authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
            layout: layout,
            revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
            username: "yangchao"
        ).arguments,
        [
            "svn", "clone",
            "--authors-file", "/tmp/authors.txt",
            "--stdlayout",
            "--revision", "1:42",
            "--username", "yangchao",
            "file:///repo",
            "/tmp/git-repo"
        ]
    )
}

func testSvnCloneUsesCustomLayoutPathsWhenProvided() {
    let layout = GitMigrationRepositoryLayout(
        kind: .custom,
        trunkPath: "main",
        branchesPath: "dev/*",
        tagsPath: "releases/*",
        confidence: 0.8
    )

    XCTAssertEqual(
        GitCommandBuilder.svnClone(
            sourceURL: "https://svn.example.com/project",
            destination: URL(fileURLWithPath: "/tmp/custom"),
            authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
            layout: layout,
            revisionRange: nil,
            username: nil
        ).arguments,
        [
            "svn", "clone",
            "--authors-file", "/tmp/authors.txt",
            "--trunk", "main",
            "--branches", "dev/*",
            "--tags", "releases/*",
            "https://svn.example.com/project",
            "/tmp/custom"
        ]
    )
}
```

在 `GitCliBackendTests` 新增：

```swift
func testGitBackendRunsSvnCloneWithoutPasswordInArguments() async throws {
    let runner = RecordingGitProcessRunner(results: [
        ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
    ])
    let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)
    let layout = GitMigrationRepositoryLayout(
        kind: .standard,
        trunkPath: "trunk",
        branchesPath: "branches",
        tagsPath: "tags",
        confidence: 1
    )

    try await backend.svnClone(
        sourceURL: "file:///repo",
        destination: URL(fileURLWithPath: "/tmp/git-repo"),
        authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
        layout: layout,
        revisionRange: nil,
        username: "u"
    )

    XCTAssertEqual(runner.calls.map(\.executable), ["/usr/bin/git"])
    XCTAssertEqual(runner.calls.first?.arguments, [
        "svn", "clone",
        "--authors-file", "/tmp/authors.txt",
        "--stdlayout",
        "--username", "u",
        "file:///repo",
        "/tmp/git-repo"
    ])
    XCTAssertNil(runner.calls.first?.stdin)
    XCTAssertNil(runner.calls.first?.currentDirectory)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testSvnClone|GitCliBackendTests/testGitBackendRunsSvnClone"
```

预期：编译失败，提示 `svnClone` API 未定义。

- [x] **步骤 3：编写最少实现代码**

实现命令构造：

```swift
public static func svnClone(
    sourceURL: String,
    destination: URL,
    authorsFile: URL,
    layout: GitMigrationRepositoryLayout,
    revisionRange: RevisionRange?,
    username: String?
) -> GitCommand {
    var arguments = ["svn", "clone", "--authors-file", authorsFile.path]

    switch layout.kind {
    case .standard:
        arguments.append("--stdlayout")
    case .custom:
        if let trunkPath = layout.trunkPath {
            arguments += ["--trunk", trunkPath]
        }
        if let branchesPath = layout.branchesPath {
            arguments += ["--branches", branchesPath]
        }
        if let tagsPath = layout.tagsPath {
            arguments += ["--tags", tagsPath]
        }
    }

    if let revisionRange {
        arguments += ["--revision", revisionRange.description]
    }

    if let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        arguments += ["--username", username]
    }

    arguments += [sourceURL, destination.path]
    return GitCommand(arguments: arguments)
}
```

扩展 `GitBackend` 与 `GitCliBackend.svnClone(...)`，`GitCliBackend` 继续用 `runner.run(...)`，`currentDirectory: nil`，`stdin: nil`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：GitMigrationService 历史迁移流程与报告

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 修改：`Sources/MacSvnCore/Services/GitMigrationService.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationServiceTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitMigrationServiceTests` 新增：

```swift
func testHistoryMigrationWritesAuthorsFileThenRunsGitSvnCloneAndReturnsReport() async throws {
    let recorder = MigrationRecorder()
    let svn = FakeGitMigrationSvnExporter(recorder: recorder)
    let git = FakeGitMigrationGitBackend(recorder: recorder)
    let service = GitMigrationService(svnExporter: svn, gitBackend: git)
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("history")
    let layout = GitMigrationRepositoryLayout(
        kind: .standard,
        trunkPath: "trunk",
        branchesPath: "branches",
        tagsPath: "tags",
        confidence: 1
    )
    let mappings = [
        GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "杨超", gitEmail: "yangchao@example.com")
    ]

    let report = try await service.historyMigrate(
        sourceURL: "file:///repo",
        destination: destination,
        layout: layout,
        authorMappings: mappings,
        revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
        auth: Credential(username: "yangchao", password: "secret")
    )
    let events = await recorder.recordedEvents()

    XCTAssertEqual(events, [
        .gitSvnClone(
            sourceURL: "file:///repo",
            destination: destination,
            authorsFile: destination.deletingLastPathComponent().appendingPathComponent("history-authors.txt"),
            layout: layout,
            revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
            username: "yangchao"
        )
    ])
    XCTAssertEqual(
        try String(contentsOf: destination.deletingLastPathComponent().appendingPathComponent("history-authors.txt"), encoding: .utf8),
        "yangchao = 杨超 <yangchao@example.com>\n"
    )
    XCTAssertEqual(report.mode, .historyPreserving)
    XCTAssertEqual(report.sourceURL, "file:///repo")
    XCTAssertEqual(report.destinationPath, destination.path)
    XCTAssertEqual(report.completedSteps, [.authorsFile, .gitSvnClone])
    XCTAssertEqual(report.authorsFilePath, destination.deletingLastPathComponent().appendingPathComponent("history-authors.txt").path)
    XCTAssertEqual(report.layout, layout)
    XCTAssertEqual(report.revisionRange, RevisionRange(start: Revision(1), end: Revision(42)))
}
```

再增加两个阻断测试：

```swift
func testHistoryMigrationRejectsIncompleteAuthorsBeforeClone() async throws {
    let recorder = MigrationRecorder()
    let service = GitMigrationService(
        svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
        gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
    )

    do {
        _ = try await service.historyMigrate(
            sourceURL: "file:///repo",
            destination: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            layout: GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1),
            authorMappings: [GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "", gitEmail: "yangchao@example.com")]
        )
        XCTFail("Expected incompleteAuthors")
    } catch {
        XCTAssertEqual(error as? GitMigrationAuthorMappingError, .incompleteAuthors(["yangchao"]))
    }

    let events = await recorder.recordedEvents()
    XCTAssertTrue(events.isEmpty)
}

func testHistoryMigrationRejectsExistingNonEmptyDestinationBeforeClone() async throws {
    let recorder = MigrationRecorder()
    let service = GitMigrationService(
        svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
        gitBackend: FakeGitMigrationGitBackend(recorder: recorder)
    )
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try "keep".write(to: destination.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)

    do {
        _ = try await service.historyMigrate(
            sourceURL: "file:///repo",
            destination: destination,
            layout: GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1),
            authorMappings: [GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "杨超", gitEmail: "yangchao@example.com")]
        )
        XCTFail("Expected destinationNotEmpty")
    } catch {
        XCTAssertEqual(error as? GitMigrationError, .destinationNotEmpty(path: destination.path))
    }

    let events = await recorder.recordedEvents()
    XCTAssertTrue(events.isEmpty)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitMigrationServiceTests/testHistoryMigration"
```

预期：编译失败，提示 `historyMigrate`、`.historyPreserving`、`.gitSvnClone` 等未定义。

- [x] **步骤 3：编写最少实现代码**

模型扩展：

```swift
public enum GitMigrationMode: Equatable, Sendable {
    case snapshot
    case historyPreserving
}

public enum GitMigrationStep: Equatable, Sendable {
    case svnExport
    case gitInit
    case gitAdd
    case gitCommit
    case authorsFile
    case gitSvnClone
}
```

在 `GitMigrationReport` 增加：

```swift
public let authorsFilePath: String?
public let layout: GitMigrationRepositoryLayout?
public let revisionRange: RevisionRange?
```

并在 init 尾部提供默认值，避免破坏快照迁移调用。

服务实现：

```swift
public func historyMigrate(
    sourceURL: String,
    destination: URL,
    layout: GitMigrationRepositoryLayout,
    authorMappings: [GitMigrationAuthorMapping],
    revisionRange: RevisionRange? = nil,
    auth: Credential? = nil
) async throws -> GitMigrationReport {
    let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSourceURL.isEmpty else {
        throw GitMigrationError.emptySourceURL
    }

    let authorsFile = destination
        .deletingLastPathComponent()
        .appendingPathComponent("\(destination.lastPathComponent)-authors.txt")

    try authorMapper.validateComplete(authorMappings)
    try validateDestinationIsEmpty(destination)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try authorMapper.exportAuthorsFile(authorMappings, to: authorsFile)
    try await gitBackend.svnClone(
        sourceURL: trimmedSourceURL,
        destination: destination,
        authorsFile: authorsFile,
        layout: layout,
        revisionRange: revisionRange,
        username: auth?.username
    )

    return GitMigrationReport(
        mode: .historyPreserving,
        sourceURL: trimmedSourceURL,
        destinationPath: destination.path,
        revision: nil,
        commitMessage: "",
        completedSteps: [.authorsFile, .gitSvnClone],
        authorsFilePath: authorsFile.path,
        layout: layout,
        revisionRange: revisionRange
    )
}
```

`GitMigrationService` 初始化增加 `authorMapper: GitMigrationAuthorMapper = GitMigrationAuthorMapper()`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：GitMigrationViewModel 历史迁移状态

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/GitMigrationViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitMigrationViewModelTests` 新增：

```swift
@MainActor
func testHistoryMigrationStoresCompletedReportAndPassesInputs() async {
    let destination = URL(fileURLWithPath: "/tmp/history")
    let layout = GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1)
    let mappings = [
        GitMigrationAuthorMapping(svnUsername: "yangchao", gitName: "杨超", gitEmail: "yangchao@example.com")
    ]
    let report = GitMigrationReport(
        mode: .historyPreserving,
        sourceURL: "file:///repo",
        destinationPath: destination.path,
        revision: nil,
        commitMessage: "",
        completedSteps: [.authorsFile, .gitSvnClone],
        authorsFilePath: "/tmp/history-authors.txt",
        layout: layout,
        revisionRange: nil
    )
    let provider = FakeGitMigrationProvider(result: .success(report))
    let viewModel = GitMigrationViewModel(provider: provider)

    await viewModel.historyMigrate(
        sourceURL: "file:///repo",
        destination: destination,
        layout: layout,
        authorMappings: mappings,
        revisionRange: nil,
        auth: nil
    )
    let calls = await provider.recordedHistoryCalls()

    XCTAssertEqual(viewModel.state, .completed(report))
    XCTAssertEqual(viewModel.report, report)
    XCTAssertEqual(calls.first?.sourceURL, "file:///repo")
    XCTAssertEqual(calls.first?.destination, destination)
    XCTAssertEqual(calls.first?.layout, layout)
    XCTAssertEqual(calls.first?.authorMappings, mappings)
}
```

再增加错误测试：空 source URL 时不调用 provider，state 为 `.error(String(describing: GitMigrationError.emptySourceURL))`。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitMigrationViewModelTests/testHistoryMigration"
```

预期：编译失败，提示 `historyMigrate` 未定义。

- [x] **步骤 3：编写最少实现代码**

扩展 `GitMigrationProviding`：

```swift
func historyMigrate(
    sourceURL: String,
    destination: URL,
    layout: GitMigrationRepositoryLayout,
    authorMappings: [GitMigrationAuthorMapping],
    revisionRange: RevisionRange?,
    auth: Credential?
) async throws -> GitMigrationReport
```

在 `GitMigrationViewModel` 新增同名方法：trim source，空源阻断；否则设为 `.running`，调用 provider，成功写 `report` 与 `.completed(report)`，失败写 `.error(String(describing: error))`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 4：真实 git-svn 集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写集成测试**

新增：

```swift
func testHistoryGitSvnMigrationClonesFixtureRepositoryWithAuthorsMapping() async throws {
    let fixture = try makeFixture()
    let gitExecutable = try requireGitExecutable()
    try await requireGitSvn(gitExecutable: gitExecutable)
    let destination = fixture.root.appendingPathComponent("git-history", isDirectory: true)
    let service = GitMigrationService(
        svnExporter: SvnService(backend: fixture.backend),
        gitBackend: GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
    )
    let layout = GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1)

    let report = try await service.historyMigrate(
        sourceURL: fixture.repositoryURL,
        destination: destination,
        layout: layout,
        authorMappings: [
            GitMigrationAuthorMapping(svnUsername: NSUserName(), gitName: "MacSVN Test", gitEmail: "macsvn@example.invalid")
        ]
    )
    let logResult = try await ProcessRunner().run(
        executable: gitExecutable,
        arguments: ["log", "--all", "-1", "--pretty=%an <%ae>"],
        stdin: nil,
        currentDirectory: destination.path,
        timeout: 30
    )

    XCTAssertEqual(report.completedSteps, [.authorsFile, .gitSvnClone])
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
    XCTAssertEqual(logResult.exitCode, 0)
    XCTAssertEqual(
        String(data: logResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        "MacSVN Test <macsvn@example.invalid>"
    )
}
```

新增 helper：

```swift
private func requireGitSvn(gitExecutable: String) async throws {
    let result = try await ProcessRunner().run(
        executable: gitExecutable,
        arguments: ["svn", "--version"],
        stdin: nil,
        currentDirectory: nil,
        timeout: 30
    )

    guard result.exitCode == 0 else {
        throw XCTSkip("git svn is not available.")
    }
}
```

- [x] **步骤 2：运行集成测试验证行为**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testHistoryGitSvnMigrationClonesFixtureRepositoryWithAuthorsMapping
```

预期：任务 1-3 完成后 PASS；若机器缺少 git-svn，则 `XCTSkip`。

- [x] **步骤 3：运行目标测试验证通过**

运行同上集成测试，预期 PASS 或明确 SKIP。

- [x] **步骤 4：全量验证与提交**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testSvnClone|GitCliBackendTests/testGitBackendRunsSvnClone|GitMigrationServiceTests/testHistoryMigration|GitMigrationViewModelTests/testHistoryMigration|SvnCliBackendIntegrationTests/testHistoryGitSvnMigrationClonesFixtureRepositoryWithAuthorsMapping"
swift test
git diff --check
git add Sources/MacSvnCore/Backend/GitCommandBuilder.swift Sources/MacSvnCore/Backend/GitBackend.swift Sources/MacSvnCore/Backend/GitCliBackend.swift Sources/MacSvnCore/Models/GitMigrationModels.swift Sources/MacSvnCore/Services/GitMigrationService.swift Sources/MacSvnCore/ViewModels/GitMigrationViewModel.swift Tests/MacSvnCoreTests/GitCommandBuilderTests.swift Tests/MacSvnCoreTests/GitCliBackendTests.swift Tests/MacSvnCoreTests/GitMigrationServiceTests.swift Tests/MacSvnCoreTests/GitMigrationViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p5-history-git-svn-clone.md
git diff --cached --check
git commit -m "feat: add P5 history git svn clone"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：测试 0 failures，空白检查无输出，提交后工作区干净。

## 自检

- 覆盖 `FR-GM-02` 的历史保真迁移基础执行：`git svn clone`、标准/自定义布局参数、authors 映射输入、revision 范围参数和报告。
- 覆盖 `FR-GM-03` 与执行步骤的衔接：映射未完整时禁止开始，完整映射导出为 git-svn authors 文件。
- 不覆盖分支/tag 后处理、revision 对账报告、清理策略、推送远程、增量同步、暂停恢复和流式进度；这些继续拆为后续计划。
