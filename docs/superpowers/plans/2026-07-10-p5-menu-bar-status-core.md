# P5 Menu Bar Status Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-03` 建立菜单栏常驻状态 Core：按工作副本生成本地未提交数、冲突数、远端新提交数和通知摘要，供后续 NSStatusItem、通知中心与后台轮询绑定。

**架构：** 新增 `MenuBarStatusSnapshotter`，复用 `WorkingCopyRecord`、`StatusProviding`、`SvnService.remoteLogFromHead` 的只读能力。该切片不创建真实菜单栏、通知中心、Timer 或 FSEvents，只做可测试的快照计算、远端轮询摘要和容错隔离。

**技术栈：** Swift 6、Foundation、XCTest、现有 `WorkingCopyRecord` / `FileStatus` / `LogEntry` / `StatusProviding` / `SvnService`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  - 增加 `MenuBarMonitorConfiguration`、`MenuBarWorkingCopySnapshotState`、`MenuBarWorkingCopySnapshot`、`MenuBarStatusSnapshot`。
- 创建：`Sources/MacSvnCore/Services/MenuBarStatusSnapshotter.swift`
  - 增加 `MenuBarRemoteLogProviding` 协议与 `MenuBarStatusSnapshotting` / `MenuBarStatusSnapshotter`。
- 创建：`Tests/MacSvnCoreTests/MenuBarStatusSnapshotterTests.swift`
  - 覆盖本地/远端计数、通知摘要、无效 WC、provider 失败隔离和默认配置。

---

## 任务 1：菜单栏状态快照主路径

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/MenuBarStatusSnapshotter.swift`
- 创建测试：`Tests/MacSvnCoreTests/MenuBarStatusSnapshotterTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `MenuBarStatusSnapshotterTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class MenuBarStatusSnapshotterTests: XCTestCase {
    func testSnapshotCountsLocalChangesRemoteCommitsAndBuildsNotificationSummary() async throws {
        let now = Date(timeIntervalSince1970: 1_800)
        let record = WorkingCopyRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "ProjectA",
            localPath: "/tmp/ProjectA",
            repoURL: "https://svn.example.com/repo/trunk",
            username: "yangchao",
            addedAt: Date(timeIntervalSince1970: 1_000),
            lastOpenedAt: Date(timeIntervalSince1970: 1_200),
            isValid: true,
            revision: Revision(100)
        )
        let statusProvider = FakeMenuBarStatusProvider(statuses: [
            URL(fileURLWithPath: "/tmp/ProjectA"): [
                FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(100), isTreeConflict: false),
                FileStatus(path: "Sources/App.swift", itemStatus: .normal, revision: Revision(100), isTreeConflict: false),
                FileStatus(path: "conflicted.txt", itemStatus: .conflicted, revision: Revision(100), isTreeConflict: true)
            ]
        ])
        let remoteLogProvider = FakeMenuBarRemoteLogProvider(entries: [
            "https://svn.example.com/repo/trunk": [
                LogEntry(revision: Revision(103), author: "alice", date: nil, message: "修复支付回调", changedPaths: []),
                LogEntry(revision: Revision(102), author: "bob", date: nil, message: "补充登录重试", changedPaths: []),
                LogEntry(revision: Revision(100), author: "root", date: nil, message: "baseline", changedPaths: [])
            ]
        ])
        let snapshotter = MenuBarStatusSnapshotter(
            statusProvider: statusProvider,
            remoteLogProvider: remoteLogProvider,
            configuration: MenuBarMonitorConfiguration(remoteLogBatchSize: 10)
        )

        let snapshot = try await snapshotter.snapshot(records: [record], now: now)

        XCTAssertEqual(snapshot.checkedAt, now)
        XCTAssertEqual(snapshot.totalLocalChangeCount, 2)
        XCTAssertEqual(snapshot.totalRemoteNewCommitCount, 2)
        XCTAssertTrue(snapshot.hasAttentionItems)
        XCTAssertEqual(snapshot.workingCopies.count, 1)
        XCTAssertEqual(snapshot.workingCopies[0].recordID, record.id)
        XCTAssertEqual(snapshot.workingCopies[0].name, "ProjectA")
        XCTAssertEqual(snapshot.workingCopies[0].state, .loaded)
        XCTAssertEqual(snapshot.workingCopies[0].localChangeCount, 2)
        XCTAssertEqual(snapshot.workingCopies[0].conflictedCount, 1)
        XCTAssertEqual(snapshot.workingCopies[0].remoteNewCommitCount, 2)
        XCTAssertEqual(snapshot.workingCopies[0].remoteLatestRevision, Revision(103))
        XCTAssertEqual(snapshot.workingCopies[0].notificationSummary, "ProjectA 有 2 个新提交（alice: 修复支付回调）")

        let statusCalls = await statusProvider.recordedCalls()
        let remoteLogCalls = await remoteLogProvider.recordedCalls()
        XCTAssertEqual(statusCalls, [URL(fileURLWithPath: "/tmp/ProjectA")])
        XCTAssertEqual(remoteLogCalls, [
            RemoteLogCall(url: "https://svn.example.com/repo/trunk", batch: 10, verbose: false, auth: nil)
        ])
    }
}

private struct RemoteLogCall: Equatable, Sendable {
    let url: String
    let batch: Int
    let verbose: Bool
    let auth: Credential?
}

private actor FakeMenuBarStatusProvider: StatusProviding {
    private let statuses: [URL: [FileStatus]]
    private var calls: [URL] = []

    init(statuses: [URL: [FileStatus]]) {
        self.statuses = statuses
    }

    func recordedCalls() -> [URL] {
        calls
    }

    func status(wc: URL) async throws -> [FileStatus] {
        calls.append(wc)
        return statuses[wc] ?? []
    }
}

private actor FakeMenuBarRemoteLogProvider: MenuBarRemoteLogProviding {
    private let entries: [String: [LogEntry]]
    private var calls: [RemoteLogCall] = []

    init(entries: [String: [LogEntry]]) {
        self.entries = entries
    }

    func recordedCalls() -> [RemoteLogCall] {
        calls
    }

    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        calls.append(RemoteLogCall(url: url, batch: batch, verbose: verbose, auth: auth))
        return entries[url] ?? []
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter MenuBarStatusSnapshotterTests
```

预期：编译失败，提示 `MenuBarStatusSnapshotter`、`MenuBarMonitorConfiguration` 或 `MenuBarRemoteLogProviding` 不存在。

- [x] **步骤 3：实现最少模型与快照器代码**

在 `SvnModels.swift` 增加：

```swift
public struct MenuBarMonitorConfiguration: Equatable, Sendable {
    public var pollIntervalMinutes: Int
    public var remoteLogBatchSize: Int

    public init(pollIntervalMinutes: Int = 10, remoteLogBatchSize: Int = 50) {
        self.pollIntervalMinutes = max(1, pollIntervalMinutes)
        self.remoteLogBatchSize = max(1, remoteLogBatchSize)
    }
}

public enum MenuBarWorkingCopySnapshotState: Equatable, Sendable {
    case loaded
    case invalidWorkingCopy
    case error(String)
}

public struct MenuBarWorkingCopySnapshot: Equatable, Sendable {
    public let recordID: UUID
    public let name: String
    public let localPath: String
    public let repoURL: String
    public let state: MenuBarWorkingCopySnapshotState
    public let localChangeCount: Int
    public let conflictedCount: Int
    public let remoteNewCommitCount: Int
    public let remoteLatestRevision: Revision?
    public let notificationSummary: String?
}

public struct MenuBarStatusSnapshot: Equatable, Sendable {
    public let checkedAt: Date
    public let workingCopies: [MenuBarWorkingCopySnapshot]

    public var totalLocalChangeCount: Int {
        workingCopies.reduce(0) { $0 + $1.localChangeCount }
    }

    public var totalRemoteNewCommitCount: Int {
        workingCopies.reduce(0) { $0 + $1.remoteNewCommitCount }
    }

    public var hasAttentionItems: Bool {
        totalLocalChangeCount > 0 || totalRemoteNewCommitCount > 0
    }
}
```

创建 `MenuBarStatusSnapshotter.swift`：

```swift
import Foundation

public protocol MenuBarRemoteLogProviding: Sendable {
    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
}

public protocol MenuBarStatusSnapshotting: Sendable {
    func snapshot(records: [WorkingCopyRecord], now: Date) async throws -> MenuBarStatusSnapshot
}

public actor MenuBarStatusSnapshotter: MenuBarStatusSnapshotting {
    private let statusProvider: any StatusProviding
    private let remoteLogProvider: any MenuBarRemoteLogProviding
    private let configuration: MenuBarMonitorConfiguration

    public init(
        statusProvider: any StatusProviding,
        remoteLogProvider: any MenuBarRemoteLogProviding,
        configuration: MenuBarMonitorConfiguration = MenuBarMonitorConfiguration()
    ) {
        self.statusProvider = statusProvider
        self.remoteLogProvider = remoteLogProvider
        self.configuration = configuration
    }

    public func snapshot(records: [WorkingCopyRecord], now: Date = Date()) async throws -> MenuBarStatusSnapshot {
        var snapshots: [MenuBarWorkingCopySnapshot] = []

        for record in records {
            snapshots.append(try await snapshot(record: record))
        }

        return MenuBarStatusSnapshot(checkedAt: now, workingCopies: snapshots)
    }

    private func snapshot(record: WorkingCopyRecord) async throws -> MenuBarWorkingCopySnapshot {
        let statuses = try await statusProvider.status(wc: URL(fileURLWithPath: record.localPath))
        let remoteEntries = try await remoteLogProvider.remoteLogFromHead(
            url: record.repoURL,
            batch: configuration.remoteLogBatchSize,
            verbose: false,
            auth: nil
        )
        let remoteNewEntries = Self.remoteNewEntries(remoteEntries, baseline: record.revision)

        return MenuBarWorkingCopySnapshot(
            recordID: record.id,
            name: record.name,
            localPath: record.localPath,
            repoURL: record.repoURL,
            state: .loaded,
            localChangeCount: Self.localChangeCount(statuses),
            conflictedCount: Self.conflictedCount(statuses),
            remoteNewCommitCount: remoteNewEntries.count,
            remoteLatestRevision: remoteEntries.map(\.revision).max { $0.value < $1.value },
            notificationSummary: Self.notificationSummary(recordName: record.name, newEntries: remoteNewEntries)
        )
    }

    private static func localChangeCount(_ statuses: [FileStatus]) -> Int {
        statuses.filter { status in
            switch status.itemStatus {
            case .normal, .ignored, .external, .none:
                return false
            default:
                return true
            }
        }.count
    }

    private static func conflictedCount(_ statuses: [FileStatus]) -> Int {
        statuses.filter { $0.itemStatus == .conflicted || $0.isTreeConflict }.count
    }

    private static func remoteNewEntries(_ entries: [LogEntry], baseline: Revision?) -> [LogEntry] {
        guard let baseline else {
            return []
        }

        return entries.filter { $0.revision.value > baseline.value }
    }

    private static func notificationSummary(recordName: String, newEntries: [LogEntry]) -> String? {
        guard let first = newEntries.first else {
            return nil
        }

        return "\(recordName) 有 \(newEntries.count) 个新提交（\(first.author): \(first.message)）"
    }
}

extension SvnService: MenuBarRemoteLogProviding {}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter MenuBarStatusSnapshotterTests
```

预期：主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Services/MenuBarStatusSnapshotter.swift Tests/MacSvnCoreTests/MenuBarStatusSnapshotterTests.swift docs/superpowers/plans/2026-07-10-p5-menu-bar-status-core.md
git diff --cached --check
git commit -m "feat: add P5 menu bar status snapshot core"
```

---

## 任务 2：无效 WC、provider 失败与配置边界

**文件：**
- 修改：`Sources/MacSvnCore/Services/MenuBarStatusSnapshotter.swift`
- 修改测试：`Tests/MacSvnCoreTests/MenuBarStatusSnapshotterTests.swift`

- [x] **步骤 1：编写失败测试**

在 `MenuBarStatusSnapshotterTests` 增加：

```swift
func testSnapshotIsolatesInvalidWorkingCopiesAndProviderFailures() async throws {
    let invalid = WorkingCopyRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "MissingWC",
        localPath: "/tmp/MissingWC",
        repoURL: "https://svn.example.com/repo/missing",
        username: nil,
        addedAt: Date(timeIntervalSince1970: 1),
        lastOpenedAt: Date(timeIntervalSince1970: 1),
        isValid: false,
        revision: Revision(1)
    )
    let failing = WorkingCopyRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "FailingWC",
        localPath: "/tmp/FailingWC",
        repoURL: "https://svn.example.com/repo/failing",
        username: nil,
        addedAt: Date(timeIntervalSince1970: 1),
        lastOpenedAt: Date(timeIntervalSince1970: 1),
        isValid: true,
        revision: Revision(1)
    )
    let statusProvider = FakeMenuBarStatusProvider(
        statuses: [:],
        errors: [URL(fileURLWithPath: "/tmp/FailingWC"): FakeMenuBarError.failed]
    )
    let remoteLogProvider = FakeMenuBarRemoteLogProvider(entries: [:])
    let snapshotter = MenuBarStatusSnapshotter(statusProvider: statusProvider, remoteLogProvider: remoteLogProvider)

    let snapshot = try await snapshotter.snapshot(records: [invalid, failing], now: Date(timeIntervalSince1970: 2))

    XCTAssertEqual(snapshot.workingCopies.map(\.state), [
        .invalidWorkingCopy,
        .error(String(describing: FakeMenuBarError.failed))
    ])
    XCTAssertEqual(snapshot.totalLocalChangeCount, 0)
    XCTAssertEqual(snapshot.totalRemoteNewCommitCount, 0)
    XCTAssertFalse(snapshot.hasAttentionItems)
    let statusCalls = await statusProvider.recordedCalls()
    let remoteLogCalls = await remoteLogProvider.recordedCalls()
    XCTAssertEqual(statusCalls, [URL(fileURLWithPath: "/tmp/FailingWC")])
    XCTAssertEqual(remoteLogCalls, [])
}

func testConfigurationClampsInvalidValuesToPositiveDefaults() {
    let configuration = MenuBarMonitorConfiguration(pollIntervalMinutes: 0, remoteLogBatchSize: -5)

    XCTAssertEqual(configuration.pollIntervalMinutes, 1)
    XCTAssertEqual(configuration.remoteLogBatchSize, 1)
}

private enum FakeMenuBarError: Error {
    case failed
}
```

同时扩展 `FakeMenuBarStatusProvider`：

```swift
private actor FakeMenuBarStatusProvider: StatusProviding {
    private let statuses: [URL: [FileStatus]]
    private let errors: [URL: FakeMenuBarError]
    private var calls: [URL] = []

    init(statuses: [URL: [FileStatus]], errors: [URL: FakeMenuBarError] = [:]) {
        self.statuses = statuses
        self.errors = errors
    }

    func status(wc: URL) async throws -> [FileStatus] {
        calls.append(wc)
        if let error = errors[wc] {
            throw error
        }
        return statuses[wc] ?? []
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter MenuBarStatusSnapshotterTests
```

预期：无效 WC / provider failure 测试失败，因为任务 1 实现会抛出错误或仍尝试远端查询。

- [x] **步骤 3：实现容错隔离**

实现要求：
- `record.isValid == false` 时返回 `.invalidWorkingCopy`，不调用 status/remote log；
- 单个 WC 的 status 或 remote log 失败时返回 `.error(String(describing: error))`，不让整批快照失败；
- 错误/无效快照的本地、冲突、远端计数均为 0，`notificationSummary == nil`；
- `MenuBarMonitorConfiguration` 已在任务 1 中做正数夹取，配置测试应通过。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter MenuBarStatusSnapshotterTests
```

预期：全部 `MenuBarStatusSnapshotterTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/MenuBarStatusSnapshotter.swift Tests/MacSvnCoreTests/MenuBarStatusSnapshotterTests.swift docs/superpowers/plans/2026-07-10-p5-menu-bar-status-core.md
git diff --cached --check
git commit -m "test: cover P5 menu bar status fault isolation"
```

---

## 任务 3：目标验证与计划收尾

- [ ] **步骤 1：运行 FR-EX-03 目标集合**

```bash
swift test --filter "MenuBarStatusSnapshotterTests|ChangesViewModelTests|LogViewModelTests|WorkspaceStoreTests"
```

预期：0 failures。

- [ ] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：全量测试 0 failures，空白检查无输出。

- [ ] **步骤 3：Commit**

```bash
git add docs/superpowers/plans/2026-07-10-p5-menu-bar-status-core.md
git diff --cached --check
git commit -m "docs: complete P5 menu bar status verification"
```
