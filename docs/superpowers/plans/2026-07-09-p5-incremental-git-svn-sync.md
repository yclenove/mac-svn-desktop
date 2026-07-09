# P5 Incremental Git-SVN Sync 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-05` 的 Core 底座：持久化迁移记录，手动执行 `git svn fetch` 追平 SVN 新提交，可选推送目标 Git 远程，并暴露 ViewModel 状态。

**架构：** 复用现有 `GitBackend` / `GitCliBackend` / `ProcessRunning`，新增 `git svn fetch` 与 `git push` 命令。新增 `GitMigrationSyncStore` 持久化 `migrations.json`，新增 `GitMigrationSyncService` 组合 store 与 git backend 产出同步报告，新增 `GitMigrationSyncViewModel` 给后续向导/菜单栏绑定。同步完成后读取 git-svn revisions，更新最后同步 revision 与时间。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Git CLI、git-svn、Foundation Codable。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  新增 `GitMigrationSyncRecord`、`GitMigrationSyncListFile`、`GitMigrationSyncReport`、`GitMigrationSyncStep`、`GitMigrationSyncError`。
- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
  新增 `svnFetch()`、`pushAll(remote:)`、`pushTags(remote:)`。
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
  新增 `svnFetch(repository:)`、`pushAll(repository:remote:)`、`pushTags(repository:remote:)` 默认不可用方法。
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
  实现 `git svn fetch` 与 `git push`。
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncStore.swift`
  管理 `migrations.json` 记录的增删改查。
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncService.swift`
  注册迁移记录、执行手动同步、更新最后同步信息。
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift`
  加载记录、注册记录、同步记录的状态层。
- 修改测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationSyncServiceTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：Git 增量同步命令与 backend

**文件：**
- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
- 测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitCommandBuilderTests` 新增：

```swift
func testSvnFetchUsesGitSvnFetch() {
    XCTAssertEqual(GitCommandBuilder.svnFetch().arguments, ["svn", "fetch"])
}

func testPushCommandsUseRemoteAllBranchesAndTags() {
    XCTAssertEqual(GitCommandBuilder.pushAll(remote: "origin").arguments, ["push", "origin", "--all"])
    XCTAssertEqual(GitCommandBuilder.pushTags(remote: "origin").arguments, ["push", "origin", "--tags"])
}
```

在 `GitCliBackendTests` 新增：

```swift
func testGitBackendRunsSvnFetchAndPushesRemoteInRepository() async throws {
    let runner = RecordingGitProcessRunner(results: [
        ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
        ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01),
        ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
    ])
    let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)
    let repository = URL(fileURLWithPath: "/tmp/history")

    try await backend.svnFetch(repository: repository)
    try await backend.pushAll(repository: repository, remote: "origin")
    try await backend.pushTags(repository: repository, remote: "origin")

    XCTAssertEqual(runner.calls.map(\.arguments), [
        ["svn", "fetch"],
        ["push", "origin", "--all"],
        ["push", "origin", "--tags"]
    ])
    XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/history", "/tmp/history", "/tmp/history"])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testSvnFetchUsesGitSvnFetch|GitCommandBuilderTests/testPushCommandsUseRemoteAllBranchesAndTags|GitCliBackendTests/testGitBackendRunsSvnFetchAndPushesRemoteInRepository"
```

预期：编译失败，提示 `svnFetch` / `pushAll` / `pushTags` 未定义。

- [x] **步骤 3：编写最少实现代码**

`GitCommandBuilder`：

```swift
public static func svnFetch() -> GitCommand {
    GitCommand(arguments: ["svn", "fetch"])
}

public static func pushAll(remote: String) -> GitCommand {
    GitCommand(arguments: ["push", remote, "--all"])
}

public static func pushTags(remote: String) -> GitCommand {
    GitCommand(arguments: ["push", remote, "--tags"])
}
```

`GitBackend`：

```swift
func svnFetch(repository: URL) async throws
func pushAll(repository: URL, remote: String) async throws
func pushTags(repository: URL, remote: String) async throws
```

默认实现抛 `SvnError.other`；`GitCliBackend` 调用现有 `run(...)`，`repository` 作为 current directory。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：迁移记录持久化

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncStore.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationSyncStoreTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testLoadMissingFileReturnsEmptyRecords() async throws {
        let store = makeStore()

        let records = try await store.loadRecords()

        XCTAssertEqual(records, [])
    }

    func testAddRecordPersistsAndReloads() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        let repository = URL(fileURLWithPath: "/tmp/history")

        let record = try await store.addRecord(
            sourceURL: " file:///repo ",
            repository: repository,
            targetRemote: "origin"
        )

        XCTAssertEqual(record.sourceURL, "file:///repo")
        XCTAssertEqual(record.repositoryPath, repository.path)
        XCTAssertEqual(record.targetRemote, "origin")

        let reloaded = try await makeStore(root: root).loadRecords()
        XCTAssertEqual(reloaded, [record])
    }

    func testAddRecordForSameRepositoryUpdatesExistingRecord() async throws {
        let store = makeStore()
        let repository = URL(fileURLWithPath: "/tmp/history")

        let first = try await store.addRecord(sourceURL: "file:///old", repository: repository, targetRemote: nil)
        let second = try await store.addRecord(sourceURL: "file:///new", repository: repository, targetRemote: "origin")
        let records = await store.records()

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceURL, "file:///new")
        XCTAssertEqual(records.first?.targetRemote, "origin")
    }

    func testUpdateSyncMetadataPersistsLatestRevisionAndDate() async throws {
        let store = makeStore()
        let record = try await store.addRecord(
            sourceURL: "file:///repo",
            repository: URL(fileURLWithPath: "/tmp/history"),
            targetRemote: nil
        )

        let updated = try await store.updateSyncMetadata(
            id: record.id,
            latestRevision: Revision(42),
            syncedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(updated.lastSyncedRevision, Revision(42))
        XCTAssertEqual(updated.lastSyncedAt, Date(timeIntervalSince1970: 100))
    }

    func testAddRecordRejectsEmptySourceOrRepository() async {
        let store = makeStore()

        do {
            _ = try await store.addRecord(sourceURL: " ", repository: URL(fileURLWithPath: "/tmp/history"), targetRemote: nil)
            XCTFail("Expected empty source URL")
        } catch let error as GitMigrationSyncError {
            XCTAssertEqual(error, .emptySourceURL)
        } catch {
            XCTFail("Expected GitMigrationSyncError, got \(error)")
        }

        do {
            _ = try await store.addRecord(sourceURL: "file:///repo", repository: URL(fileURLWithPath: ""), targetRemote: nil)
            XCTFail("Expected empty repository path")
        } catch let error as GitMigrationSyncError {
            XCTAssertEqual(error, .emptyRepositoryPath)
        } catch {
            XCTFail("Expected GitMigrationSyncError, got \(error)")
        }
    }

    private func makeStore(root: URL? = nil) -> GitMigrationSyncStore {
        let root = root ?? temporaryRoot()
        return GitMigrationSyncStore(fileURL: root.appendingPathComponent("migrations.json"))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreMigrationSync-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSyncStoreTests
```

预期：编译失败，提示 store、record、error 未定义。

- [x] **步骤 3：编写最少实现代码**

模型：

```swift
public enum GitMigrationSyncError: Error, Equatable, Sendable {
    case emptySourceURL
    case emptyRepositoryPath
    case recordNotFound(UUID)
}

public struct GitMigrationSyncRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var sourceURL: String
    public var repositoryPath: String
    public var targetRemote: String?
    public var createdAt: Date
    public var lastSyncedAt: Date?
    public var lastSyncedRevision: Revision?
}

public struct GitMigrationSyncListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var records: [GitMigrationSyncRecord]
}
```

`GitMigrationSyncStore` 使用 `PersistenceStore<GitMigrationSyncListFile>`，按 `repositoryPath` 去重更新，`updateSyncMetadata` 找不到记录时抛 `.recordNotFound(id)`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：同步服务与报告

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncService.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncServiceTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationSyncServiceTests`，覆盖：

```swift
func testRegisterMigrationPersistsRecord() async throws {
    let store = FakeGitMigrationSyncStore()
    let service = GitMigrationSyncService(store: store, gitBackend: FakeGitMigrationSyncBackend())
    let repository = URL(fileURLWithPath: "/tmp/history")

    let record = try await service.registerMigration(sourceURL: "file:///repo", repository: repository, targetRemote: "origin")

    XCTAssertEqual(record.sourceURL, "file:///repo")
    XCTAssertEqual(record.repositoryPath, repository.path)
    XCTAssertEqual(record.targetRemote, "origin")
}

func testSyncFetchesReadsRevisionsUpdatesRecordAndPushesConfiguredRemote() async throws {
    let store = FakeGitMigrationSyncStore()
    let backend = FakeGitMigrationSyncBackend(revisions: [
        GitSvnRevisionMetadata(revision: Revision(1)),
        GitSvnRevisionMetadata(revision: Revision(3))
    ])
    let service = GitMigrationSyncService(store: store, gitBackend: backend)
    let record = GitMigrationSyncRecord(
        id: UUID(),
        sourceURL: "file:///repo",
        repositoryPath: "/tmp/history",
        targetRemote: "origin",
        createdAt: Date(timeIntervalSince1970: 10),
        lastSyncedAt: nil,
        lastSyncedRevision: nil
    )

    let report = try await service.sync(record: record, syncedAt: Date(timeIntervalSince1970: 20))
    let events = await backend.events()

    XCTAssertEqual(events, [
        .svnFetch(URL(fileURLWithPath: "/tmp/history")),
        .gitSvnRevisions(URL(fileURLWithPath: "/tmp/history")),
        .pushAll(URL(fileURLWithPath: "/tmp/history"), "origin"),
        .pushTags(URL(fileURLWithPath: "/tmp/history"), "origin")
    ])
    XCTAssertEqual(report.completedSteps, [.gitSvnFetch, .revisionScan, .gitPushBranches, .gitPushTags])
    XCTAssertEqual(report.latestRevision, Revision(3))
    XCTAssertEqual(report.updatedRecord.lastSyncedRevision, Revision(3))
}

func testSyncWithoutRemoteOnlyFetchesAndScansRevisions() async throws {
    let backend = FakeGitMigrationSyncBackend(revisions: [GitSvnRevisionMetadata(revision: Revision(5))])
    let service = GitMigrationSyncService(store: FakeGitMigrationSyncStore(), gitBackend: backend)
    let record = GitMigrationSyncRecord(
        id: UUID(),
        sourceURL: "file:///repo",
        repositoryPath: "/tmp/history",
        targetRemote: nil,
        createdAt: Date(timeIntervalSince1970: 10),
        lastSyncedAt: nil,
        lastSyncedRevision: nil
    )

    let report = try await service.sync(record: record, syncedAt: Date(timeIntervalSince1970: 20))

    XCTAssertEqual(report.completedSteps, [.gitSvnFetch, .revisionScan])
    XCTAssertEqual(report.latestRevision, Revision(5))
}
```

测试内定义 fake store/backend，fake backend 实现 `svnFetch`、`gitSvnRevisions`、`pushAll`、`pushTags` 并记录事件。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSyncServiceTests
```

预期：编译失败，提示 sync service/report/steps 未定义。

- [x] **步骤 3：编写最少实现代码**

模型：

```swift
public enum GitMigrationSyncStep: Equatable, Sendable {
    case gitSvnFetch
    case revisionScan
    case gitPushBranches
    case gitPushTags
}

public struct GitMigrationSyncReport: Equatable, Sendable {
    public let recordID: UUID
    public let repositoryPath: String
    public let completedSteps: [GitMigrationSyncStep]
    public let latestRevision: Revision?
    public let updatedRecord: GitMigrationSyncRecord
}
```

服务协议：

```swift
public protocol GitMigrationSyncRecordStoring: Sendable {
    func loadRecords() async throws -> [GitMigrationSyncRecord]
    func addRecord(sourceURL: String, repository: URL, targetRemote: String?) async throws -> GitMigrationSyncRecord
    func updateSyncMetadata(id: UUID, latestRevision: Revision?, syncedAt: Date) async throws -> GitMigrationSyncRecord
}
```

`GitMigrationSyncService.sync(record:syncedAt:)` 顺序：
1. `gitBackend.svnFetch(repository:)`
2. `gitBackend.gitSvnRevisions(repository:)`
3. 如果 `targetRemote` 非空，执行 `pushAll` 和 `pushTags`
4. 用最大 revision 更新 store
5. 返回 report

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 4：ViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationSyncViewModelTests`，覆盖：

```swift
@MainActor
func testLoadRegisterAndSyncUpdateStateAndRecords() async {
    let record = GitMigrationSyncRecord(
        id: UUID(),
        sourceURL: "file:///repo",
        repositoryPath: "/tmp/history",
        targetRemote: "origin",
        createdAt: Date(timeIntervalSince1970: 10),
        lastSyncedAt: nil,
        lastSyncedRevision: nil
    )
    let updated = GitMigrationSyncRecord(
        id: record.id,
        sourceURL: record.sourceURL,
        repositoryPath: record.repositoryPath,
        targetRemote: record.targetRemote,
        createdAt: record.createdAt,
        lastSyncedAt: Date(timeIntervalSince1970: 20),
        lastSyncedRevision: Revision(5)
    )
    let report = GitMigrationSyncReport(
        recordID: record.id,
        repositoryPath: record.repositoryPath,
        completedSteps: [.gitSvnFetch, .revisionScan],
        latestRevision: Revision(5),
        updatedRecord: updated
    )
    let provider = FakeGitMigrationSyncProvider(records: [record], registerResult: record, syncResult: report)
    let viewModel = GitMigrationSyncViewModel(provider: provider)

    await viewModel.loadRecords()
    XCTAssertEqual(viewModel.records, [record])

    await viewModel.registerMigration(
        sourceURL: "file:///repo",
        repository: URL(fileURLWithPath: "/tmp/history"),
        targetRemote: "origin"
    )
    XCTAssertEqual(viewModel.records, [record])

    await viewModel.sync(record)
    XCTAssertEqual(viewModel.state, .completed(report))
    XCTAssertEqual(viewModel.lastReport, report)
    XCTAssertEqual(viewModel.records, [updated])
}

@MainActor
func testProviderFailureStoresError() async {
    let provider = FakeGitMigrationSyncProvider(error: SvnError.other(code: 1, stderr: "boom"))
    let viewModel = GitMigrationSyncViewModel(provider: provider)

    await viewModel.loadRecords()

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.other(code: 1, stderr: "boom"))))
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSyncViewModelTests
```

预期：编译失败，提示 ViewModel/state/protocol 未定义。

- [x] **步骤 3：编写最少实现代码**

`GitMigrationSyncProviding` 包含 `loadRecords`、`registerMigration`、`sync`。`GitMigrationSyncState` 为 `.idle/.loading/.running/.completed(report)/.error(String)`。ViewModel 保存 `records` 与 `lastReport`，注册成功追加/替换记录，同步成功用 `report.updatedRecord` 替换现有记录。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 5：真实 git-svn fetch 集成验证与提交

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写集成测试**

在历史迁移集成附近新增：

```swift
func testIncrementalGitSvnSyncFetchesNewSvnRevision() async throws {
    let fixture = try makeFixture()
    let gitExecutable = try requireGitExecutable()
    try await requireGitSvn(gitExecutable: gitExecutable)
    let destination = fixture.root.appendingPathComponent("git-history-sync", isDirectory: true)
    let svnService = SvnService(backend: fixture.backend)
    let gitBackend = GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
    let migrationService = GitMigrationService(svnExporter: svnService, gitBackend: gitBackend)
    let syncStore = GitMigrationSyncStore(fileURL: fixture.root.appendingPathComponent("migrations.json"))
    let syncService = GitMigrationSyncService(store: syncStore, gitBackend: gitBackend)
    let layout = GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1)

    _ = try await migrationService.historyMigrate(
        sourceURL: fixture.repositoryURL,
        destination: destination,
        layout: layout,
        authorMappings: [
            GitMigrationAuthorMapping(svnUsername: NSUserName(), gitName: "MacSVN Test", gitEmail: "macsvn@example.invalid")
        ]
    )
    let newRevision = try await svnService.mkdir(
        url: "\(fixture.trunkURL)/post-migration",
        message: "add post migration directory",
        auth: nil
    )
    let record = try await syncService.registerMigration(
        sourceURL: fixture.repositoryURL,
        repository: destination,
        targetRemote: nil
    )

    let report = try await syncService.sync(record: record)

    XCTAssertEqual(report.latestRevision, newRevision)
    XCTAssertEqual(report.updatedRecord.lastSyncedRevision, newRevision)
    XCTAssertTrue(report.completedSteps.contains(.gitSvnFetch))
}
```

- [x] **步骤 2：运行集成测试验证通过**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testIncrementalGitSvnSyncFetchesNewSvnRevision
```

预期：PASS；如果机器缺少 git-svn，则 `XCTSkip`。

- [x] **步骤 3：运行目标集合与全量验证**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testSvnFetchUsesGitSvnFetch|GitCommandBuilderTests/testPushCommandsUseRemoteAllBranchesAndTags|GitCliBackendTests/testGitBackendRunsSvnFetchAndPushesRemoteInRepository|GitMigrationSyncStoreTests|GitMigrationSyncServiceTests|GitMigrationSyncViewModelTests|SvnCliBackendIntegrationTests/testIncrementalGitSvnSyncFetchesNewSvnRevision"
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [ ] **步骤 4：Commit**

运行：

```bash
git add Sources/MacSvnCore/Backend/GitCommandBuilder.swift Sources/MacSvnCore/Backend/GitBackend.swift Sources/MacSvnCore/Backend/GitCliBackend.swift Sources/MacSvnCore/Models/GitMigrationModels.swift Sources/MacSvnCore/Services/GitMigrationSyncStore.swift Sources/MacSvnCore/Services/GitMigrationSyncService.swift Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift Tests/MacSvnCoreTests/GitCommandBuilderTests.swift Tests/MacSvnCoreTests/GitCliBackendTests.swift Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift Tests/MacSvnCoreTests/GitMigrationSyncServiceTests.swift Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p5-incremental-git-svn-sync.md
git diff --cached --check
git commit -m "feat: add P5 incremental git svn sync"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：staged 空白检查无输出，提交后工作区干净。

## 自检

- 覆盖 `FR-GM-05` 的 Core 底座：迁移记录持久化、手动 `git svn fetch`、可选 push 到目标 Git 远程。
- 覆盖迁移记录 `migrations.json` 的本地持久化。
- 覆盖真实 git-svn fetch 追平 SVN 新 revision 的集成验证。
- 不覆盖定时同步调度、菜单栏通知、后台任务常驻和远程创建/认证向导；这些属于后续 P5/FR-EX-03 计划。
