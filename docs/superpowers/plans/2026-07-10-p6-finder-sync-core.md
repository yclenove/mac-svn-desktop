# P6 Finder Sync Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-05` 建立 Finder Sync Core：根据工作副本状态快照为文件/目录生成 Finder 角标语义，并给出右键 SVN 菜单动作的启用状态。

**架构：** 新增纯 Swift `FinderSyncPresentationBuilder`，输入目标相对路径与 `[FileStatus]`，输出 `FinderSyncPresentation`。本切片不创建 FinderSync extension target，不导入 FinderSync.framework，只提供后续扩展 target 可复用的稳定模型与规则。

**技术栈：** Swift 6、Foundation、XCTest、现有 `FileStatus` / `ItemStatus`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/FinderSyncPresentationBuilder.swift`
  - 增加 `FinderSyncBadge`、`FinderSyncMenuActionID`、`FinderSyncMenuAction`、`FinderSyncPresentation` 与 `FinderSyncPresentationBuilder`。
- 创建测试：`Tests/MacSvnCoreTests/FinderSyncPresentationBuilderTests.swift`
  - 覆盖文件角标、目录聚合角标、modified/unversioned/conflicted 菜单可用性。

---

## 任务 1：文件与目录角标主路径

**文件：**
- 创建：`Sources/MacSvnCore/Services/FinderSyncPresentationBuilder.swift`
- 创建测试：`Tests/MacSvnCoreTests/FinderSyncPresentationBuilderTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `FinderSyncPresentationBuilderTests.swift`：

```swift
import XCTest
@testable import MacSvnCore

final class FinderSyncPresentationBuilderTests: XCTestCase {
    func testPresentationUsesExactFileBadgeAndHighestPriorityDirectoryBadge() {
        let builder = FinderSyncPresentationBuilder()
        let statuses = [
            FileStatus(path: "Sources/App.swift", itemStatus: .modified, revision: Revision(10), isTreeConflict: false),
            FileStatus(path: "Sources/Conflict.swift", itemStatus: .modified, revision: Revision(11), isTreeConflict: true),
            FileStatus(path: "README.md", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]

        let file = builder.presentation(for: "Sources/App.swift", statuses: statuses)
        let directory = builder.presentation(for: "Sources", statuses: statuses)
        let unknown = builder.presentation(for: "Sources/Unknown.swift", statuses: statuses)

        XCTAssertEqual(file.badge, .modified)
        XCTAssertEqual(directory.badge, .conflicted)
        XCTAssertEqual(unknown.badge, .normal)
        XCTAssertEqual(directory.targetPath, "Sources")
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter FinderSyncPresentationBuilderTests/testPresentationUsesExactFileBadgeAndHighestPriorityDirectoryBadge
```

预期：编译失败，提示 `FinderSyncPresentationBuilder` 或 `FinderSyncBadge` 不存在。

- [x] **步骤 3：实现最少角标模型与聚合规则**

创建 `FinderSyncPresentationBuilder.swift`：

```swift
import Foundation

public enum FinderSyncBadge: String, Equatable, Sendable {
    case normal
    case modified
    case added
    case deleted
    case missing
    case conflicted
    case replaced
    case unversioned
    case ignored
    case external
    case incomplete
    case obstructed
}

public enum FinderSyncMenuActionID: String, Codable, Equatable, Hashable, Sendable {
    case update
    case commit
    case log
    case diff
    case revert
    case add
    case delete
    case resolve
}

public struct FinderSyncMenuAction: Equatable, Sendable {
    public let id: FinderSyncMenuActionID
    public let title: String
    public let isEnabled: Bool

    public init(id: FinderSyncMenuActionID, title: String, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
    }
}

public struct FinderSyncPresentation: Equatable, Sendable {
    public let targetPath: String
    public let badge: FinderSyncBadge
    public let menuActions: [FinderSyncMenuAction]

    public init(targetPath: String, badge: FinderSyncBadge, menuActions: [FinderSyncMenuAction]) {
        self.targetPath = targetPath
        self.badge = badge
        self.menuActions = menuActions
    }
}

public struct FinderSyncPresentationBuilder: Sendable {
    public init() {}

    public func presentation(for targetPath: String, statuses: [FileStatus]) -> FinderSyncPresentation {
        let normalizedTarget = Self.normalize(targetPath)
        let matchedStatuses = Self.statusesMatching(targetPath: normalizedTarget, statuses: statuses)
        let badge = matchedStatuses
            .map(Self.badge)
            .sorted { Self.priority($0) > Self.priority($1) }
            .first ?? .normal

        return FinderSyncPresentation(
            targetPath: normalizedTarget,
            badge: badge,
            menuActions: []
        )
    }

    private static func statusesMatching(targetPath: String, statuses: [FileStatus]) -> [FileStatus] {
        statuses.filter { status in
            let path = normalize(status.path)
            return path == targetPath || path.hasPrefix(targetPath + "/")
        }
    }

    private static func badge(for status: FileStatus) -> FinderSyncBadge {
        if status.isTreeConflict {
            return .conflicted
        }

        switch status.itemStatus {
        case .normal, .none:
            return .normal
        case .modified:
            return .modified
        case .added:
            return .added
        case .deleted:
            return .deleted
        case .missing:
            return .missing
        case .conflicted:
            return .conflicted
        case .replaced:
            return .replaced
        case .unversioned:
            return .unversioned
        case .ignored:
            return .ignored
        case .external:
            return .external
        case .incomplete:
            return .incomplete
        case .obstructed:
            return .obstructed
        }
    }

    private static func priority(_ badge: FinderSyncBadge) -> Int {
        switch badge {
        case .conflicted:
            return 100
        case .modified, .replaced, .deleted, .missing, .added:
            return 80
        case .obstructed, .incomplete:
            return 70
        case .unversioned:
            return 60
        case .ignored, .external:
            return 20
        case .normal:
            return 0
        }
    }

    private static func normalize(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "/")
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter FinderSyncPresentationBuilderTests/testPresentationUsesExactFileBadgeAndHighestPriorityDirectoryBadge
```

预期：角标主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/FinderSyncPresentationBuilder.swift Tests/MacSvnCoreTests/FinderSyncPresentationBuilderTests.swift docs/superpowers/plans/2026-07-10-p6-finder-sync-core.md
git commit -m "feat: add P6 finder sync badge core"
```

---

## 任务 2：右键 SVN 菜单动作可用性

**文件：**
- 修改：`Sources/MacSvnCore/Services/FinderSyncPresentationBuilder.swift`
- 修改测试：`Tests/MacSvnCoreTests/FinderSyncPresentationBuilderTests.swift`

- [x] **步骤 1：编写失败测试**

追加以下测试：

```swift
func testMenuActionsReflectModifiedVersionedFile() {
    let builder = FinderSyncPresentationBuilder()
    let presentation = builder.presentation(
        for: "Sources/App.swift",
        statuses: [
            FileStatus(path: "Sources/App.swift", itemStatus: .modified, revision: Revision(10), isTreeConflict: false)
        ]
    )

    XCTAssertEqual(enabledActionIDs(in: presentation), [.update, .commit, .log, .diff, .revert, .delete])
    XCTAssertFalse(isEnabled(.add, in: presentation))
    XCTAssertFalse(isEnabled(.resolve, in: presentation))
}

func testMenuActionsReflectUnversionedFile() {
    let builder = FinderSyncPresentationBuilder()
    let presentation = builder.presentation(
        for: "scratch.txt",
        statuses: [
            FileStatus(path: "scratch.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
    )

    XCTAssertEqual(enabledActionIDs(in: presentation), [.update, .add])
    XCTAssertFalse(isEnabled(.commit, in: presentation))
    XCTAssertFalse(isEnabled(.diff, in: presentation))
    XCTAssertFalse(isEnabled(.log, in: presentation))
}

func testMenuActionsDisableCommitAndEnableResolveForConflicts() {
    let builder = FinderSyncPresentationBuilder()
    let presentation = builder.presentation(
        for: "Sources/Conflict.swift",
        statuses: [
            FileStatus(path: "Sources/Conflict.swift", itemStatus: .modified, revision: Revision(11), isTreeConflict: true)
        ]
    )

    XCTAssertEqual(presentation.badge, .conflicted)
    XCTAssertTrue(isEnabled(.update, in: presentation))
    XCTAssertTrue(isEnabled(.log, in: presentation))
    XCTAssertTrue(isEnabled(.diff, in: presentation))
    XCTAssertTrue(isEnabled(.revert, in: presentation))
    XCTAssertTrue(isEnabled(.resolve, in: presentation))
    XCTAssertFalse(isEnabled(.commit, in: presentation))
}

private func enabledActionIDs(in presentation: FinderSyncPresentation) -> [FinderSyncMenuActionID] {
    presentation.menuActions.filter(\.isEnabled).map(\.id)
}

private func isEnabled(_ id: FinderSyncMenuActionID, in presentation: FinderSyncPresentation) -> Bool {
    presentation.menuActions.first { $0.id == id }?.isEnabled ?? false
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter FinderSyncPresentationBuilderTests
```

预期：测试失败，因为 `menuActions` 目前为空。

- [x] **步骤 3：实现菜单动作规则**

在 `presentation(for:statuses:)` 中取最高优先级状态并生成菜单：

```swift
let dominantStatus = matchedStatuses.sorted {
    Self.priority(Self.badge(for: $0)) > Self.priority(Self.badge(for: $1))
}.first
let badge = dominantStatus.map(Self.badge) ?? .normal
let menuActions = Self.menuActions(for: dominantStatus)
```

新增私有规则：

```swift
private static func menuActions(for status: FileStatus?) -> [FinderSyncMenuAction] {
    let itemStatus = status?.itemStatus ?? .normal
    let isConflicted = status?.isTreeConflict == true || itemStatus == .conflicted
    let isUnversioned = itemStatus == .unversioned
    let isIgnored = itemStatus == .ignored
    let isVersioned = !isUnversioned && !isIgnored
    let hasLocalChange = isConflicted || [.modified, .added, .deleted, .missing, .replaced].contains(itemStatus)
    let canCommit = hasLocalChange && !isConflicted
    let canDiff = isConflicted || [.modified, .added, .deleted, .replaced].contains(itemStatus)
    let canDelete = isVersioned && ![.deleted, .missing, .conflicted].contains(itemStatus)

    return [
        FinderSyncMenuAction(id: .update, title: "更新", isEnabled: true),
        FinderSyncMenuAction(id: .commit, title: "提交", isEnabled: canCommit),
        FinderSyncMenuAction(id: .log, title: "查看日志", isEnabled: isVersioned),
        FinderSyncMenuAction(id: .diff, title: "查看差异", isEnabled: canDiff),
        FinderSyncMenuAction(id: .revert, title: "还原", isEnabled: hasLocalChange),
        FinderSyncMenuAction(id: .add, title: "加入版本控制", isEnabled: isUnversioned),
        FinderSyncMenuAction(id: .delete, title: "SVN 删除", isEnabled: canDelete),
        FinderSyncMenuAction(id: .resolve, title: "解决冲突", isEnabled: isConflicted)
    ]
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter FinderSyncPresentationBuilderTests
```

预期：Finder Sync Core 目标测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/FinderSyncPresentationBuilder.swift Tests/MacSvnCoreTests/FinderSyncPresentationBuilderTests.swift docs/superpowers/plans/2026-07-10-p6-finder-sync-core.md
git commit -m "test: cover P6 finder sync menu actions"
```

---

## 任务 3：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p6-finder-sync-core.md`

- [x] **步骤 1：运行 FR-EX-05 目标集合**

```bash
swift test --filter FinderSyncPresentationBuilderTests
```

预期：目标集合 PASS。

- [x] **步骤 2：运行全量验证**

```bash
swift test
```

预期：全部 XCTest PASS。

- [x] **步骤 3：运行空白检查**

```bash
git diff --check
```

预期：无输出、退出码 0。

- [x] **步骤 4：更新计划勾选并提交验证记录**

将本计划完成步骤勾选为 `[x]`，提交：

```bash
git add docs/superpowers/plans/2026-07-10-p6-finder-sync-core.md
git commit -m "docs: complete P6 finder sync verification"
```

## 自检

- 覆盖 `FR-EX-05` 的 Core 支撑：状态角标语义和右键 SVN 菜单可用性。
- 不引入 FinderSync extension target；当前仓库还没有 App/Extension 产品结构，本计划只交付可测试 Core。
- 不执行任何 SVN 写操作，只描述菜单动作状态，后续 UI/extension 必须继续走既有 `SvnService` 确认门与错误处理。
