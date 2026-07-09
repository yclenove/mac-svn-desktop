# P5 Scheduled Git-SVN Sync 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 P5 `FR-GM-05` 的定时同步 Core 底座：迁移记录可配置同步间隔，调度器能筛选到期记录并调用现有 `GitMigrationSyncService` 执行同步。

**架构：** 在 `GitMigrationSyncRecord` 上增加可选调度配置，保持旧 `migrations.json` 可解码。`GitMigrationSyncStore` 负责保存调度设置；新增 `GitMigrationSyncScheduler` 只做可测试的 due 判断与批量执行，不创建真实后台 timer。`GitMigrationSyncViewModel` 暴露配置调度的方法，供后续菜单栏/后台常驻切片绑定。

**技术栈：** Swift Package、actor、Codable JSON 持久化、XCTest、TDD。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  - 为 `GitMigrationSyncRecord` 增加调度字段和 scheduled report 模型。
- 修改：`Sources/MacSvnCore/Services/GitMigrationSyncStore.swift`
  - 增加 `updateSchedule(id:isEnabled:intervalMinutes:)`，并校验 interval。
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncScheduler.swift`
  - 筛选到期记录并顺序调用 sync provider。
- 修改：`Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift`
  - 增加配置调度入口并刷新 records。
- 修改测试：`Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift`
- 创建测试：`Tests/MacSvnCoreTests/GitMigrationSyncSchedulerTests.swift`
- 修改测试：`Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift`

## 任务 1：调度字段与 Store 持久化

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 修改：`Sources/MacSvnCore/Services/GitMigrationSyncStore.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitMigrationSyncStoreTests` 增加：

```swift
func testUpdateSchedulePersistsEnabledInterval() async throws {
    let store = makeStore()
    let record = try await store.addRecord(
        sourceURL: "file:///repo",
        repository: URL(fileURLWithPath: "/tmp/history"),
        targetRemote: nil
    )

    let updated = try await store.updateSchedule(
        id: record.id,
        isEnabled: true,
        intervalMinutes: 30
    )

    XCTAssertTrue(updated.isScheduledSyncEnabled)
    XCTAssertEqual(updated.syncIntervalMinutes, 30)
    let records = try await store.loadRecords()
    XCTAssertEqual(records, [updated])
}

func testUpdateScheduleRejectsNonPositiveInterval() async throws {
    let store = makeStore()
    let record = try await store.addRecord(
        sourceURL: "file:///repo",
        repository: URL(fileURLWithPath: "/tmp/history"),
        targetRemote: nil
    )

    do {
        _ = try await store.updateSchedule(
            id: record.id,
            isEnabled: true,
            intervalMinutes: 0
        )
        XCTFail("Expected invalid interval")
    } catch let error as GitMigrationSyncError {
        XCTAssertEqual(error, .invalidScheduleInterval(0))
    } catch {
        XCTFail("Expected GitMigrationSyncError, got \(error)")
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "GitMigrationSyncStoreTests/testUpdateSchedulePersistsEnabledInterval|GitMigrationSyncStoreTests/testUpdateScheduleRejectsNonPositiveInterval"
```

预期：编译失败，提示 `updateSchedule`、`isScheduledSyncEnabled`、`syncIntervalMinutes` 或 `invalidScheduleInterval` 未定义。

- [x] **步骤 3：实现最少代码**

修改 `GitMigrationSyncError`：

```swift
case invalidScheduleInterval(Int)
```

修改 `GitMigrationSyncRecord`：

```swift
public var isScheduledSyncEnabled: Bool
public var syncIntervalMinutes: Int?
```

为了兼容旧文件，给 `GitMigrationSyncRecord` 增加自定义 `init(from:)`，缺失字段默认 `false` 和 `nil`。修改公开 init 增加默认参数：

```swift
isScheduledSyncEnabled: Bool = false,
syncIntervalMinutes: Int? = nil
```

在 `GitMigrationSyncStore` 协议和 actor 中增加：

```swift
func updateSchedule(id: UUID, isEnabled: Bool, intervalMinutes: Int?) async throws -> GitMigrationSyncRecord
```

实现规则：

- `isEnabled == true` 时 `intervalMinutes` 必须大于 0；
- `isEnabled == false` 时允许 `intervalMinutes == nil`，并保存 disabled 状态；
- 找不到记录抛 `.recordNotFound(id)`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 2：可测试调度器

**文件：**
- 创建：`Sources/MacSvnCore/Services/GitMigrationSyncScheduler.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncSchedulerTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationSyncSchedulerTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSyncSchedulerTests: XCTestCase {
    func testRunDueSyncsOnlySyncsEnabledDueRecords() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let due = makeRecord(id: UUID(), path: "/tmp/due", enabled: true, interval: 30, lastSyncedAt: Date(timeIntervalSince1970: 1_000 - 31 * 60))
        let fresh = makeRecord(id: UUID(), path: "/tmp/fresh", enabled: true, interval: 30, lastSyncedAt: Date(timeIntervalSince1970: 1_000 - 10 * 60))
        let disabled = makeRecord(id: UUID(), path: "/tmp/disabled", enabled: false, interval: 30, lastSyncedAt: nil)
        let provider = FakeScheduledSyncProvider(records: [due, fresh, disabled])
        let scheduler = GitMigrationSyncScheduler(provider: provider)

        let report = try await scheduler.runDueSyncs(now: now)

        XCTAssertEqual(await provider.syncedRecordIDs(), [due.id])
        XCTAssertEqual(report.attemptedRecordIDs, [due.id])
        XCTAssertEqual(report.completedReports.count, 1)
        XCTAssertEqual(report.failedRecordIDs, [])
    }

    func testRunDueSyncsRecordsFailuresAndContinues() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let first = makeRecord(id: UUID(), path: "/tmp/first", enabled: true, interval: 10, lastSyncedAt: nil)
        let second = makeRecord(id: UUID(), path: "/tmp/second", enabled: true, interval: 10, lastSyncedAt: nil)
        let provider = FakeScheduledSyncProvider(records: [first, second], failingIDs: [first.id])
        let scheduler = GitMigrationSyncScheduler(provider: provider)

        let report = try await scheduler.runDueSyncs(now: now)

        XCTAssertEqual(report.attemptedRecordIDs, [first.id, second.id])
        XCTAssertEqual(report.failedRecordIDs, [first.id])
        XCTAssertEqual(report.completedReports.map(\.recordID), [second.id])
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSyncSchedulerTests
```

预期：编译失败，提示 `GitMigrationSyncScheduler` 或 scheduled report 类型未定义。

- [x] **步骤 3：实现最少代码**

新增模型：

```swift
public struct GitMigrationScheduledSyncReport: Equatable, Sendable {
    public let attemptedRecordIDs: [UUID]
    public let completedReports: [GitMigrationSyncReport]
    public let failedRecordIDs: [UUID]
}
```

新增 provider 协议和调度器：

```swift
public protocol GitMigrationScheduledSyncProviding: Sendable {
    func loadRecords() async throws -> [GitMigrationSyncRecord]
    func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport
}

public actor GitMigrationSyncScheduler {
    private let provider: any GitMigrationScheduledSyncProviding

    public init(provider: any GitMigrationScheduledSyncProviding) {
        self.provider = provider
    }

    public func dueRecords(now: Date) async throws -> [GitMigrationSyncRecord] {
        let records = try await provider.loadRecords()
        return records.filter { record in
            guard record.isScheduledSyncEnabled,
                  let interval = record.syncIntervalMinutes,
                  interval > 0 else {
                return false
            }
            guard let lastSyncedAt = record.lastSyncedAt else {
                return true
            }
            return now.timeIntervalSince(lastSyncedAt) >= TimeInterval(interval * 60)
        }
    }

    public func runDueSyncs(now: Date = Date()) async throws -> GitMigrationScheduledSyncReport {
        let dueRecords = try await dueRecords(now: now)
        var completedReports: [GitMigrationSyncReport] = []
        var failedRecordIDs: [UUID] = []
        for record in dueRecords {
            do {
                completedReports.append(try await provider.sync(record: record))
            } catch {
                failedRecordIDs.append(record.id)
            }
        }
        return GitMigrationScheduledSyncReport(
            attemptedRecordIDs: dueRecords.map(\.id),
            completedReports: completedReports,
            failedRecordIDs: failedRecordIDs
        )
    }
}
```

Due 规则：

- `isScheduledSyncEnabled == true`；
- `syncIntervalMinutes` 存在且大于 0；
- `lastSyncedAt == nil` 立即到期；
- 否则 `now.timeIntervalSince(lastSyncedAt) >= intervalMinutes * 60`。

`runDueSyncs` 顺序执行 due records；单条失败记录到 `failedRecordIDs`，后续记录继续执行。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 3：ViewModel 调度配置入口

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

在 `GitMigrationSyncViewModelTests` 增加：

```swift
@MainActor
func testConfigureScheduleUpdatesRecordState() async {
    let record = makeRecord()
    var scheduled = record
    scheduled.isScheduledSyncEnabled = true
    scheduled.syncIntervalMinutes = 30
    let provider = FakeGitMigrationSyncProvider(
        records: [record],
        scheduleResult: scheduled
    )
    let viewModel = GitMigrationSyncViewModel(provider: provider)

    await viewModel.loadRecords()
    await viewModel.configureSchedule(record, isEnabled: true, intervalMinutes: 30)

    XCTAssertEqual(viewModel.records, [scheduled])
    XCTAssertEqual(viewModel.state, .idle)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationSyncViewModelTests/testConfigureScheduleUpdatesRecordState
```

预期：编译失败，提示 provider 或 ViewModel 缺少调度方法。

- [x] **步骤 3：实现最少代码**

扩展 `GitMigrationSyncProviding`：

```swift
func updateSchedule(id: UUID, isEnabled: Bool, intervalMinutes: Int?) async throws -> GitMigrationSyncRecord
```

在 `GitMigrationSyncViewModel` 新增：

```swift
public func configureSchedule(
    _ record: GitMigrationSyncRecord,
    isEnabled: Bool,
    intervalMinutes: Int?
) async
```

成功后 `upsert(updatedRecord)` 且 `state = .idle`；失败时 `state = .error(String(describing: error))`。

让 `GitMigrationSyncService` 转发到 store 的 `updateSchedule`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 4：全量验证与提交

- [x] **步骤 1：运行目标集合**

```bash
swift test --filter "GitMigrationSyncStoreTests|GitMigrationSyncSchedulerTests|GitMigrationSyncServiceTests|GitMigrationSyncViewModelTests"
```

预期：0 failures。

- [x] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [ ] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/Models/GitMigrationModels.swift \
  Sources/MacSvnCore/Services/GitMigrationSyncStore.swift \
  Sources/MacSvnCore/Services/GitMigrationSyncService.swift \
  Sources/MacSvnCore/Services/GitMigrationSyncScheduler.swift \
  Sources/MacSvnCore/ViewModels/GitMigrationSyncViewModel.swift \
  Tests/MacSvnCoreTests/GitMigrationSyncStoreTests.swift \
  Tests/MacSvnCoreTests/GitMigrationSyncServiceTests.swift \
  Tests/MacSvnCoreTests/GitMigrationSyncSchedulerTests.swift \
  Tests/MacSvnCoreTests/GitMigrationSyncViewModelTests.swift \
  docs/superpowers/plans/2026-07-10-p5-scheduled-git-svn-sync.md
git diff --cached --check
git commit -m "feat: add P5 scheduled git svn sync core"
git status --short --branch
```

## 自检

- 覆盖 `FR-GM-05` 的定时同步 Core：每条迁移记录可保存调度配置，调度器能筛选 due records 并执行同步。
- 不覆盖真实后台 timer、菜单栏通知、通知中心、登录项、远程仓库创建或 Git remote 认证向导；这些属于后续 P5/FR-EX-03 UI 与系统集成切片。
