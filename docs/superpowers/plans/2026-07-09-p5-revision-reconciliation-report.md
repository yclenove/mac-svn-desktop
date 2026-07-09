# P5 Revision Reconciliation Report 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-04` / `NFR-14` 的迁移完成 revision 对账报告：从 `git svn` 迁移后的 Git 日志提取 SVN revision，与源仓库 revision 列表比对，输出缺失/额外 revision 和一致性结论。

**架构：** `GitCommandBuilder` / `GitCliBackend` 增加只读 Git 日志查询，解析 `git-svn-id` 元数据得到 migrated revisions。新增纯服务 `GitMigrationRevisionReconciler` 做集合对账，`GitMigrationService` 暴露报告生成入口，ViewModel 保存状态。源 revision 列表由调用方传入，后续向导可直接使用 `remoteLogFromHead` 的结果。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Git CLI、git-svn metadata、Foundation。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
  新增 `logGitSvnMetadata()` 命令，参数为 `git log --all --format=%B`。
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
  新增 `gitSvnRevisions(repository:)` 只读协议方法。
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
  运行 `git log` 并解析 stdout 中的 `git-svn-id` revision。
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  新增 `GitSvnRevisionMetadata` 与 `GitMigrationRevisionReconciliationReport`。
- 创建：`Sources/MacSvnCore/Parsers/GitSvnMetadataParser.swift`
  从 commit body 文本中提取 `git-svn-id: ...@123 ...` revision，去重排序。
- 创建：`Sources/MacSvnCore/Services/GitMigrationRevisionReconciler.swift`
  纯服务：输入 source/migrated revisions，输出 missing、unexpected、count 和一致性。
- 修改：`Sources/MacSvnCore/Services/GitMigrationService.swift`
  新增 `reconcileHistoryMigration(sourceRevisions:gitRepository:)`。
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationRevisionReconciliationViewModel.swift`
  状态层：idle/running/completed/error，保存 report。
- 修改测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitSvnMetadataParserTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationRevisionReconcilerTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitMigrationServiceTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationRevisionReconciliationViewModelTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：Git svn metadata 命令、解析器与 backend

**文件：**
- 修改：`Sources/MacSvnCore/Backend/GitCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/GitBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/GitCliBackend.swift`
- 创建：`Sources/MacSvnCore/Parsers/GitSvnMetadataParser.swift`
- 测试：`Tests/MacSvnCoreTests/GitCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitCliBackendTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitSvnMetadataParserTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitCommandBuilderTests` 新增：

```swift
func testLogGitSvnMetadataUsesAllCommitBodies() {
    XCTAssertEqual(
        GitCommandBuilder.logGitSvnMetadata().arguments,
        ["log", "--all", "--format=%B"]
    )
}
```

创建 `GitSvnMetadataParserTests`：

```swift
import XCTest
@testable import MacSvnCore

final class GitSvnMetadataParserTests: XCTestCase {
    func testParsesGitSvnIdsFromCommitBodiesDeduplicatedAndSorted() {
        let text = """
        initial import

        git-svn-id: file:///repo/trunk@3 abc

        branch work
        git-svn-id: file:///repo/branches/feature@5 abc

        duplicate
        git-svn-id: file:///repo/trunk@3 abc
        """

        XCTAssertEqual(GitSvnMetadataParser.parseRevisions(from: text), [
            GitSvnRevisionMetadata(revision: Revision(3)),
            GitSvnRevisionMetadata(revision: Revision(5))
        ])
    }

    func testIgnoresCommitBodiesWithoutGitSvnIds() {
        XCTAssertEqual(GitSvnMetadataParser.parseRevisions(from: "plain git commit"), [])
    }
}
```

在 `GitCliBackendTests` 新增：

```swift
func testGitBackendReadsGitSvnRevisionsFromRepositoryLog() async throws {
    let stdout = Data("""
    initial
    git-svn-id: file:///repo/trunk@1 abc

    second
    git-svn-id: file:///repo/trunk@2 abc
    """.utf8)
    let runner = RecordingGitProcessRunner(results: [
        ProcessResult(exitCode: 0, stdout: stdout, stderr: "", duration: 0.01)
    ])
    let backend = GitCliBackend(gitExecutable: "/usr/bin/git", runner: runner)

    let revisions = try await backend.gitSvnRevisions(repository: URL(fileURLWithPath: "/tmp/history"))

    XCTAssertEqual(revisions, [
        GitSvnRevisionMetadata(revision: Revision(1)),
        GitSvnRevisionMetadata(revision: Revision(2))
    ])
    XCTAssertEqual(runner.calls.first?.arguments, ["log", "--all", "--format=%B"])
    XCTAssertEqual(runner.calls.first?.currentDirectory, "/tmp/history")
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testLogGitSvnMetadata|GitSvnMetadataParserTests|GitCliBackendTests/testGitBackendReadsGitSvnRevisions"
```

预期：编译失败，提示 parser、metadata model 或 backend 方法未定义。

- [x] **步骤 3：编写最少实现代码**

在模型中新增：

```swift
public struct GitSvnRevisionMetadata: Equatable, Sendable {
    public let revision: Revision

    public init(revision: Revision) {
        self.revision = revision
    }
}
```

实现 command：

```swift
public static func logGitSvnMetadata() -> GitCommand {
    GitCommand(arguments: ["log", "--all", "--format=%B"])
}
```

实现 parser：

```swift
public enum GitSvnMetadataParser {
    public static func parseRevisions(from text: String) -> [GitSvnRevisionMetadata] {
        let pattern = #"git-svn-id:\s+\S+@(\d+)\s+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let revisions = regex?.matches(in: text, range: range).compactMap { match -> Revision? in
            guard
                let matchRange = Range(match.range(at: 1), in: text),
                let value = Int(text[matchRange])
            else {
                return nil
            }
            return Revision(value)
        } ?? []

        return Set(revisions)
            .sorted { $0.value < $1.value }
            .map(GitSvnRevisionMetadata.init(revision:))
    }
}
```

扩展 `GitBackend`：

```swift
func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata]
```

`GitCliBackend.gitSvnRevisions` 运行 `GitCommandBuilder.logGitSvnMetadata()`，按 UTF-8 解码 stdout 后调用 parser。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：Revision reconciler 纯逻辑

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationRevisionReconciler.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationRevisionReconcilerTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationRevisionReconcilerTests`：

```swift
import XCTest
@testable import MacSvnCore

final class GitMigrationRevisionReconcilerTests: XCTestCase {
    func testConsistentRevisionsProducePassingReport() {
        let report = GitMigrationRevisionReconciler().reconcile(
            sourceRevisions: [Revision(1), Revision(2), Revision(3)],
            migratedRevisions: [
                GitSvnRevisionMetadata(revision: Revision(3)),
                GitSvnRevisionMetadata(revision: Revision(1)),
                GitSvnRevisionMetadata(revision: Revision(2))
            ]
        )

        XCTAssertEqual(report, GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: 3,
            migratedRevisionCount: 3,
            missingRevisions: [],
            unexpectedRevisions: []
        ))
        XCTAssertTrue(report.isConsistent)
    }

    func testReportsMissingAndUnexpectedRevisions() {
        let report = GitMigrationRevisionReconciler().reconcile(
            sourceRevisions: [Revision(1), Revision(2), Revision(4)],
            migratedRevisions: [
                GitSvnRevisionMetadata(revision: Revision(1)),
                GitSvnRevisionMetadata(revision: Revision(3))
            ]
        )

        XCTAssertEqual(report.missingRevisions, [Revision(2), Revision(4)])
        XCTAssertEqual(report.unexpectedRevisions, [Revision(3)])
        XCTAssertFalse(report.isConsistent)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationRevisionReconcilerTests
```

预期：编译失败，提示 report/reconciler 未定义。

- [x] **步骤 3：编写最少实现代码**

模型：

```swift
public struct GitMigrationRevisionReconciliationReport: Equatable, Sendable {
    public let sourceRevisionCount: Int
    public let migratedRevisionCount: Int
    public let missingRevisions: [Revision]
    public let unexpectedRevisions: [Revision]

    public init(
        sourceRevisionCount: Int,
        migratedRevisionCount: Int,
        missingRevisions: [Revision],
        unexpectedRevisions: [Revision]
    ) {
        self.sourceRevisionCount = sourceRevisionCount
        self.migratedRevisionCount = migratedRevisionCount
        self.missingRevisions = missingRevisions
        self.unexpectedRevisions = unexpectedRevisions
    }

    public var isConsistent: Bool {
        missingRevisions.isEmpty && unexpectedRevisions.isEmpty
    }
}
```

服务：

```swift
public struct GitMigrationRevisionReconciler: Sendable {
    public init() {}

    public func reconcile(
        sourceRevisions: [Revision],
        migratedRevisions: [GitSvnRevisionMetadata]
    ) -> GitMigrationRevisionReconciliationReport {
        let source = Set(sourceRevisions)
        let migrated = Set(migratedRevisions.map(\.revision))

        return GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: source.count,
            migratedRevisionCount: migrated.count,
            missingRevisions: source.subtracting(migrated).sorted { $0.value < $1.value },
            unexpectedRevisions: migrated.subtracting(source).sorted { $0.value < $1.value }
        )
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：GitMigrationService 与 ViewModel 对账状态

**文件：**
- 修改：`Sources/MacSvnCore/Services/GitMigrationService.swift`
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationRevisionReconciliationViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationServiceTests.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationRevisionReconciliationViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitMigrationServiceTests` 新增：

```swift
func testReconcileHistoryMigrationReadsGitSvnRevisionsAndReturnsReport() async throws {
    let recorder = MigrationRecorder()
    let git = FakeGitMigrationGitBackend(
        recorder: recorder,
        gitSvnRevisions: [
            GitSvnRevisionMetadata(revision: Revision(1)),
            GitSvnRevisionMetadata(revision: Revision(3))
        ]
    )
    let service = GitMigrationService(
        svnExporter: FakeGitMigrationSvnExporter(recorder: recorder),
        gitBackend: git
    )
    let repository = URL(fileURLWithPath: "/tmp/history")

    let report = try await service.reconcileHistoryMigration(
        sourceRevisions: [Revision(1), Revision(2), Revision(3)],
        gitRepository: repository
    )

    XCTAssertEqual(report.missingRevisions, [Revision(2)])
    XCTAssertFalse(report.isConsistent)
    XCTAssertEqual(await recorder.recordedEvents(), [
        .gitSvnRevisions(repository: repository)
    ])
}
```

创建 `GitMigrationRevisionReconciliationViewModelTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationRevisionReconciliationViewModelTests: XCTestCase {
    @MainActor
    func testReconcileStoresCompletedReport() async {
        let report = GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: 1,
            migratedRevisionCount: 1,
            missingRevisions: [],
            unexpectedRevisions: []
        )
        let provider = FakeGitMigrationRevisionReconciliationProvider(result: .success(report))
        let viewModel = GitMigrationRevisionReconciliationViewModel(provider: provider)

        await viewModel.reconcile(
            sourceRevisions: [Revision(1)],
            gitRepository: URL(fileURLWithPath: "/tmp/history")
        )

        XCTAssertEqual(viewModel.state, .completed(report))
        XCTAssertEqual(viewModel.report, report)
    }

    @MainActor
    func testReconcileFailureClearsReportAndStoresError() async {
        let provider = FakeGitMigrationRevisionReconciliationProvider(result: .failure(SvnError.parse(detail: "bad log")))
        let viewModel = GitMigrationRevisionReconciliationViewModel(provider: provider)

        await viewModel.reconcile(
            sourceRevisions: [Revision(1)],
            gitRepository: URL(fileURLWithPath: "/tmp/history")
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.parse(detail: "bad log"))))
        XCTAssertNil(viewModel.report)
    }
}
```

测试内补 fake provider，记录调用参数。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitMigrationServiceTests/testReconcileHistoryMigration|GitMigrationRevisionReconciliationViewModelTests"
```

预期：编译失败，提示 service 方法、ViewModel 或 fake backend 方法未定义。

- [x] **步骤 3：编写最少实现代码**

`GitMigrationService` 增加 `private let revisionReconciler`，init 默认 `GitMigrationRevisionReconciler()`，并新增：

```swift
public func reconcileHistoryMigration(
    sourceRevisions: [Revision],
    gitRepository: URL
) async throws -> GitMigrationRevisionReconciliationReport {
    let migratedRevisions = try await gitBackend.gitSvnRevisions(repository: gitRepository)
    return revisionReconciler.reconcile(
        sourceRevisions: sourceRevisions,
        migratedRevisions: migratedRevisions
    )
}
```

ViewModel：

```swift
public protocol GitMigrationRevisionReconciliationProviding: Sendable {
    func reconcileHistoryMigration(
        sourceRevisions: [Revision],
        gitRepository: URL
    ) async throws -> GitMigrationRevisionReconciliationReport
}

public enum GitMigrationRevisionReconciliationState: Equatable, Sendable {
    case idle
    case running
    case completed(GitMigrationRevisionReconciliationReport)
    case error(String)
}
```

`GitMigrationRevisionReconciliationViewModel` 调 provider，成功保存 report，失败清空 report。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 4：真实 git-svn 对账集成验证与提交

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [x] **步骤 1：编写集成测试**

在历史迁移集成附近新增：

```swift
func testHistoryGitSvnMigrationProducesConsistentRevisionReconciliation() async throws {
    let fixture = try makeFixture()
    let gitExecutable = try requireGitExecutable()
    try await requireGitSvn(gitExecutable: gitExecutable)
    let destination = fixture.root.appendingPathComponent("git-history-reconcile", isDirectory: true)
    let svnService = SvnService(backend: fixture.backend)
    let migrationService = GitMigrationService(
        svnExporter: svnService,
        gitBackend: GitCliBackend(gitExecutable: gitExecutable, runner: ProcessRunner(), timeout: 60)
    )
    let layout = GitMigrationRepositoryLayout(kind: .standard, trunkPath: "trunk", branchesPath: "branches", tagsPath: "tags", confidence: 1)
    let sourceLogEntries = try await fixture.backend.remoteLogFromHead(
        url: fixture.repositoryURL,
        batch: 100,
        verbose: false,
        auth: nil
    )
    let sourceRevisions = sourceLogEntries.map(\.revision)

    _ = try await migrationService.historyMigrate(
        sourceURL: fixture.repositoryURL,
        destination: destination,
        layout: layout,
        authorMappings: [
            GitMigrationAuthorMapping(svnUsername: NSUserName(), gitName: "MacSVN Test", gitEmail: "macsvn@example.invalid")
        ]
    )
    let report = try await migrationService.reconcileHistoryMigration(
        sourceRevisions: sourceRevisions,
        gitRepository: destination
    )

    XCTAssertTrue(report.isConsistent)
    XCTAssertEqual(report.sourceRevisionCount, Set(sourceRevisions).count)
    XCTAssertEqual(report.missingRevisions, [])
    XCTAssertEqual(report.unexpectedRevisions, [])
}
```

- [x] **步骤 2：运行集成测试验证通过**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testHistoryGitSvnMigrationProducesConsistentRevisionReconciliation
```

预期：PASS；如果机器缺少 git-svn，则 `XCTSkip`。

- [x] **步骤 3：运行目标集合与全量验证**

运行：

```bash
swift test --filter "GitCommandBuilderTests/testLogGitSvnMetadata|GitSvnMetadataParserTests|GitCliBackendTests/testGitBackendReadsGitSvnRevisions|GitMigrationRevisionReconcilerTests|GitMigrationServiceTests/testReconcileHistoryMigration|GitMigrationRevisionReconciliationViewModelTests|SvnCliBackendIntegrationTests/testHistoryGitSvnMigrationProducesConsistentRevisionReconciliation"
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [x] **步骤 4：Commit**

运行：

```bash
git add Sources/MacSvnCore/Backend/GitCommandBuilder.swift Sources/MacSvnCore/Backend/GitBackend.swift Sources/MacSvnCore/Backend/GitCliBackend.swift Sources/MacSvnCore/Models/GitMigrationModels.swift Sources/MacSvnCore/Parsers/GitSvnMetadataParser.swift Sources/MacSvnCore/Services/GitMigrationRevisionReconciler.swift Sources/MacSvnCore/Services/GitMigrationService.swift Sources/MacSvnCore/ViewModels/GitMigrationRevisionReconciliationViewModel.swift Tests/MacSvnCoreTests/GitCommandBuilderTests.swift Tests/MacSvnCoreTests/GitCliBackendTests.swift Tests/MacSvnCoreTests/GitSvnMetadataParserTests.swift Tests/MacSvnCoreTests/GitMigrationRevisionReconcilerTests.swift Tests/MacSvnCoreTests/GitMigrationServiceTests.swift Tests/MacSvnCoreTests/GitMigrationRevisionReconciliationViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p5-revision-reconciliation-report.md
git diff --cached --check
git commit -m "feat: add P5 revision reconciliation report"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：staged 空白检查无输出，提交后工作区干净。

## 自检

- 覆盖 `FR-GM-04` 的迁移完成 revision 对账报告核心：source revisions vs git-svn migrated revisions，输出总数、缺失、额外和一致性。
- 覆盖 `NFR-14` 中“迁移完成必须通过 revision 对账”的可验证底座。
- 不覆盖清理策略、分支/tag 整理、推送远程、增量同步、菜单栏和 URL Scheme；这些继续拆分为后续计划。
