# P6 Team Activity Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-06` 建立团队活动视图 Core：从本地聚合的 SVN log 与锁状态生成提交热力图、作者排行、活跃路径 Top N 和锁定看板数据。

**架构：** 新增纯 Swift `TeamActivityAggregator` 做无 I/O 聚合；新增 `TeamActivityViewModel` 调用可注入 log/lock provider 并暴露 `TeamActivitySummary`。本切片不做 SwiftUI 图表、不拉取全量历史分页、不写缓存，只提供稳定 Core 数据结构和状态层。

**技术栈：** Swift 6、Foundation、Observation、XCTest、现有 `LogEntry` / `ChangedPath` / `SvnLock`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Models/TeamActivityModels.swift`
  - 增加 `TeamActivityDay`、`TeamActivityAuthorStat`、`TeamActivityPathStat`、`TeamActivityLockCard`、`TeamActivitySummary`。
- 创建：`Sources/MacSvnCore/Services/TeamActivityAggregator.swift`
  - 从 `[LogEntry]` 与 `[SvnLock]` 聚合团队活动摘要。
- 创建：`Sources/MacSvnCore/ViewModels/TeamActivityViewModel.swift`
  - 通过可注入 provider 加载 log 与 locks，调用 aggregator 并暴露状态。
- 创建测试：`Tests/MacSvnCoreTests/TeamActivityAggregatorTests.swift`
  - 覆盖热力图、作者排行、活跃路径、锁定看板排序。
- 创建测试：`Tests/MacSvnCoreTests/TeamActivityViewModelTests.swift`
  - 覆盖 ViewModel 成功加载和错误状态。

---

## 任务 1：团队活动纯聚合器

**文件：**
- 创建：`Sources/MacSvnCore/Models/TeamActivityModels.swift`
- 创建：`Sources/MacSvnCore/Services/TeamActivityAggregator.swift`
- 创建测试：`Tests/MacSvnCoreTests/TeamActivityAggregatorTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `TeamActivityAggregatorTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class TeamActivityAggregatorTests: XCTestCase {
    func testSummarizeBuildsHeatmapAuthorRankingActivePathsAndLockBoard() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let aggregator = TeamActivityAggregator(calendar: calendar, activePathLimit: 2)
        let entries = [
            logEntry(
                revision: 12,
                author: "alice",
                date: Date(timeIntervalSince1970: 86_400),
                paths: ["/trunk/login/LoginView.swift", "/trunk/payment/Pay.swift"]
            ),
            logEntry(
                revision: 11,
                author: "bob",
                date: Date(timeIntervalSince1970: 86_400 + 3_600),
                paths: ["/trunk/login/LoginView.swift"]
            ),
            logEntry(
                revision: 10,
                author: "alice",
                date: Date(timeIntervalSince1970: 0),
                paths: ["/trunk/login/LoginView.swift"]
            )
        ]
        let locks = [
            SvnLock(
                target: "zeta.txt",
                token: nil,
                owner: "bob",
                comment: "editing",
                created: Date(timeIntervalSince1970: 10),
                isOwnedByWorkingCopy: false,
                isRepositoryLocked: true
            ),
            SvnLock(
                target: "alpha.txt",
                token: "t",
                owner: "alice",
                comment: nil,
                created: nil,
                isOwnedByWorkingCopy: true,
                isRepositoryLocked: true
            )
        ]

        let summary = aggregator.summarize(entries: entries, locks: locks)

        XCTAssertEqual(summary.revisionRange, RevisionRange(start: Revision(10), end: Revision(12)))
        XCTAssertEqual(summary.dailyCommits.map(\.commitCount), [1, 2])
        XCTAssertEqual(summary.authorStats.map(\.author), ["alice", "bob"])
        XCTAssertEqual(summary.authorStats.map(\.commitCount), [2, 1])
        XCTAssertEqual(summary.authorStats.first?.latestRevision, Revision(12))
        XCTAssertEqual(summary.activePaths.map(\.path), ["/trunk/login/LoginView.swift", "/trunk/payment/Pay.swift"])
        XCTAssertEqual(summary.activePaths.map(\.changeCount), [3, 1])
        XCTAssertEqual(summary.lockCards.map(\.target), ["alpha.txt", "zeta.txt"])
        XCTAssertEqual(summary.lockCards.first?.owner, "alice")
    }

    private func logEntry(revision: Int, author: String, date: Date, paths: [String]) -> LogEntry {
        LogEntry(
            revision: Revision(revision),
            author: author,
            date: date,
            message: "r\(revision)",
            changedPaths: paths.map {
                ChangedPath(path: $0, action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
            }
        )
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter TeamActivityAggregatorTests
```

预期：编译失败，提示 `TeamActivityAggregator` 或 `TeamActivitySummary` 不存在。

- [x] **步骤 3：实现团队活动模型与聚合器**

创建 `TeamActivityModels.swift`：

```swift
import Foundation

public struct TeamActivityDay: Equatable, Sendable {
    public let date: Date
    public let commitCount: Int

    public init(date: Date, commitCount: Int) {
        self.date = date
        self.commitCount = commitCount
    }
}

public struct TeamActivityAuthorStat: Equatable, Sendable {
    public let author: String
    public let commitCount: Int
    public let latestRevision: Revision
    public let latestDate: Date?

    public init(author: String, commitCount: Int, latestRevision: Revision, latestDate: Date?) {
        self.author = author
        self.commitCount = commitCount
        self.latestRevision = latestRevision
        self.latestDate = latestDate
    }
}

public struct TeamActivityPathStat: Equatable, Sendable {
    public let path: String
    public let changeCount: Int
    public let latestRevision: Revision

    public init(path: String, changeCount: Int, latestRevision: Revision) {
        self.path = path
        self.changeCount = changeCount
        self.latestRevision = latestRevision
    }
}

public struct TeamActivityLockCard: Equatable, Sendable {
    public let target: String
    public let owner: String?
    public let comment: String?
    public let created: Date?
    public let isOwnedByWorkingCopy: Bool
    public let isRepositoryLocked: Bool

    public init(
        target: String,
        owner: String?,
        comment: String?,
        created: Date?,
        isOwnedByWorkingCopy: Bool,
        isRepositoryLocked: Bool
    ) {
        self.target = target
        self.owner = owner
        self.comment = comment
        self.created = created
        self.isOwnedByWorkingCopy = isOwnedByWorkingCopy
        self.isRepositoryLocked = isRepositoryLocked
    }
}

public struct TeamActivitySummary: Equatable, Sendable {
    public let dailyCommits: [TeamActivityDay]
    public let authorStats: [TeamActivityAuthorStat]
    public let activePaths: [TeamActivityPathStat]
    public let lockCards: [TeamActivityLockCard]
    public let revisionRange: RevisionRange?

    public init(
        dailyCommits: [TeamActivityDay],
        authorStats: [TeamActivityAuthorStat],
        activePaths: [TeamActivityPathStat],
        lockCards: [TeamActivityLockCard],
        revisionRange: RevisionRange?
    ) {
        self.dailyCommits = dailyCommits
        self.authorStats = authorStats
        self.activePaths = activePaths
        self.lockCards = lockCards
        self.revisionRange = revisionRange
    }
}
```

创建 `TeamActivityAggregator.swift`：

```swift
import Foundation

public struct TeamActivityAggregator: Sendable {
    private let calendar: Calendar
    private let activePathLimit: Int

    public init(calendar: Calendar = .current, activePathLimit: Int = 10) {
        self.calendar = calendar
        self.activePathLimit = max(1, activePathLimit)
    }

    public func summarize(entries: [LogEntry], locks: [SvnLock] = []) -> TeamActivitySummary {
        TeamActivitySummary(
            dailyCommits: dailyCommits(from: entries),
            authorStats: authorStats(from: entries),
            activePaths: activePaths(from: entries),
            lockCards: lockCards(from: locks),
            revisionRange: revisionRange(from: entries)
        )
    }

    private func dailyCommits(from entries: [LogEntry]) -> [TeamActivityDay] {
        let counts = Dictionary(grouping: entries.compactMap { entry -> Date? in
            guard let date = entry.date else {
                return nil
            }
            return calendar.startOfDay(for: date)
        }) { $0 }.mapValues(\.count)

        return counts
            .map { TeamActivityDay(date: $0.key, commitCount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func authorStats(from entries: [LogEntry]) -> [TeamActivityAuthorStat] {
        Dictionary(grouping: entries, by: \.author)
            .map { author, authorEntries in
                let latest = authorEntries.max { $0.revision.value < $1.revision.value }!
                return TeamActivityAuthorStat(
                    author: author,
                    commitCount: authorEntries.count,
                    latestRevision: latest.revision,
                    latestDate: latest.date
                )
            }
            .sorted {
                if $0.commitCount != $1.commitCount {
                    return $0.commitCount > $1.commitCount
                }
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
    }

    private func activePaths(from entries: [LogEntry]) -> [TeamActivityPathStat] {
        let changedPaths = entries.flatMap { entry in
            entry.changedPaths.map { (path: $0.path, revision: entry.revision) }
        }

        return Dictionary(grouping: changedPaths, by: { $0.path })
            .map { path, changes in
                TeamActivityPathStat(
                    path: path,
                    changeCount: changes.count,
                    latestRevision: changes.map { $0.revision }.max { $0.value < $1.value }!
                )
            }
            .sorted {
                if $0.changeCount != $1.changeCount {
                    return $0.changeCount > $1.changeCount
                }
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            .prefix(activePathLimit)
            .map { $0 }
    }

    private func lockCards(from locks: [SvnLock]) -> [TeamActivityLockCard] {
        locks
            .map {
                TeamActivityLockCard(
                    target: $0.target,
                    owner: $0.owner,
                    comment: $0.comment,
                    created: $0.created,
                    isOwnedByWorkingCopy: $0.isOwnedByWorkingCopy,
                    isRepositoryLocked: $0.isRepositoryLocked
                )
            }
            .sorted { $0.target.localizedCaseInsensitiveCompare($1.target) == .orderedAscending }
    }

    private func revisionRange(from entries: [LogEntry]) -> RevisionRange? {
        let revisions = entries.map(\.revision.value)
        guard let min = revisions.min(), let max = revisions.max() else {
            return nil
        }
        return RevisionRange(start: Revision(min), end: Revision(max))
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter TeamActivityAggregatorTests
```

预期：聚合器测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/TeamActivityModels.swift Sources/MacSvnCore/Services/TeamActivityAggregator.swift Tests/MacSvnCoreTests/TeamActivityAggregatorTests.swift docs/superpowers/plans/2026-07-10-p6-team-activity-core.md
git diff --cached --check
git commit -m "feat: add P6 team activity aggregator core"
```

---

## 任务 2：团队活动 ViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/TeamActivityViewModel.swift`
- 创建测试：`Tests/MacSvnCoreTests/TeamActivityViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `TeamActivityViewModelTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class TeamActivityViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsSummaryFromLogAndLocks() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeTeamActivityProvider(
            logResult: .success([
                LogEntry(
                    revision: Revision(2),
                    author: "alice",
                    date: Date(timeIntervalSince1970: 0),
                    message: "m",
                    changedPaths: [
                        ChangedPath(path: "/trunk/a.swift", action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
                    ]
                )
            ]),
            lockResult: .success([
                SvnLock(target: "a.swift", token: nil, owner: "alice", comment: nil, created: nil, isOwnedByWorkingCopy: true, isRepositoryLocked: true)
            ])
        )
        let viewModel = TeamActivityViewModel(workingCopy: wc, target: ".", logProvider: provider, lockProvider: provider)

        await viewModel.load(from: Revision(100), batch: 50, lockTargets: ["a.swift"])
        let logCalls = await provider.recordedLogCalls()
        let lockCalls = await provider.recordedLockCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.summary?.authorStats.map(\.author), ["alice"])
        XCTAssertEqual(viewModel.summary?.lockCards.map(\.target), ["a.swift"])
        XCTAssertEqual(logCalls, [
            TeamActivityLogCall(wc: wc, target: ".", from: Revision(100), batch: 50, verbose: true)
        ])
        XCTAssertEqual(lockCalls, [
            TeamActivityLockCall(wc: wc, targets: ["a.swift"])
        ])
    }

    @MainActor
    func testLoadFailureStoresErrorAndClearsSummary() async {
        let provider = FakeTeamActivityProvider(logResult: .failure(SvnError.network(detail: "offline")), lockResult: .success([]))
        let viewModel = TeamActivityViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            logProvider: provider,
            lockProvider: provider
        )

        await viewModel.load(from: Revision(1), batch: 50, lockTargets: [])

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.summary)
    }
}

private struct TeamActivityLogCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let from: Revision
    let batch: Int
    let verbose: Bool
}

private struct TeamActivityLockCall: Equatable, Sendable {
    let wc: URL
    let targets: [String]
}

private actor FakeTeamActivityProvider: TeamActivityLogProviding, TeamActivityLockProviding {
    private let logResult: Result<[LogEntry], Error>
    private let lockResult: Result<[SvnLock], Error>
    private var logCalls: [TeamActivityLogCall] = []
    private var lockCalls: [TeamActivityLockCall] = []

    init(logResult: Result<[LogEntry], Error>, lockResult: Result<[SvnLock], Error>) {
        self.logResult = logResult
        self.lockResult = lockResult
    }

    func recordedLogCalls() -> [TeamActivityLogCall] {
        logCalls
    }

    func recordedLockCalls() -> [TeamActivityLockCall] {
        lockCalls
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        logCalls.append(TeamActivityLogCall(wc: wc, target: target, from: from, batch: batch, verbose: verbose))
        return try logResult.get()
    }

    func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        lockCalls.append(TeamActivityLockCall(wc: wc, targets: targets))
        return try lockResult.get()
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter TeamActivityViewModelTests
```

预期：编译失败，提示 `TeamActivityViewModel` 或 provider 协议不存在。

- [x] **步骤 3：实现 ViewModel**

创建 `TeamActivityViewModel.swift`：

```swift
import Foundation
import Observation

public protocol TeamActivityLogProviding: Sendable {
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
}

public protocol TeamActivityLockProviding: Sendable {
    func locks(wc: URL, targets: [String]) async throws -> [SvnLock]
}

public enum TeamActivityViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class TeamActivityViewModel {
    private let workingCopy: URL
    private let target: String
    private let logProvider: any TeamActivityLogProviding
    private let lockProvider: any TeamActivityLockProviding
    private let aggregator: TeamActivityAggregator

    public private(set) var state: TeamActivityViewState = .idle
    public private(set) var summary: TeamActivitySummary?

    public init(
        workingCopy: URL,
        target: String,
        logProvider: any TeamActivityLogProviding,
        lockProvider: any TeamActivityLockProviding,
        aggregator: TeamActivityAggregator = TeamActivityAggregator()
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.logProvider = logProvider
        self.lockProvider = lockProvider
        self.aggregator = aggregator
    }

    public func load(from revision: Revision, batch: Int, lockTargets: [String]) async {
        state = .loading
        summary = nil

        do {
            let entries = try await logProvider.log(
                wc: workingCopy,
                target: target,
                from: revision,
                batch: max(1, batch),
                verbose: true
            )
            let locks = try await lockProvider.locks(wc: workingCopy, targets: lockTargets)
            summary = aggregator.summarize(entries: entries, locks: locks)
            state = .loaded
        } catch {
            summary = nil
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: TeamActivityLogProviding {}
extension SvnService: TeamActivityLockProviding {}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter "TeamActivityAggregatorTests|TeamActivityViewModelTests"
```

预期：团队活动聚合器与 ViewModel 测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/TeamActivityViewModel.swift Tests/MacSvnCoreTests/TeamActivityViewModelTests.swift docs/superpowers/plans/2026-07-10-p6-team-activity-core.md
git diff --cached --check
git commit -m "feat: add P6 team activity view model core"
```

---

## 任务 3：目标验证与计划收尾

- [ ] **步骤 1：运行 FR-EX-06 目标集合**

```bash
swift test --filter "TeamActivityAggregatorTests|TeamActivityViewModelTests|LogViewModelTests|LockViewModelTests"
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
git add docs/superpowers/plans/2026-07-10-p6-team-activity-core.md
git diff --cached --check
git commit -m "docs: complete P6 team activity verification"
```
