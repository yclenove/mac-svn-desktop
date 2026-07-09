# P6 Command Palette Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-04` 建立命令面板 Core：对动作、文件路径和日志记录做轻量模糊搜索；当输入明显是自然语言且没有结构化命中时，产出 AI Chat handoff 项。

**架构：** 新增纯 Swift `CommandPaletteSearchEngine`，调用方传入可搜索的 action/file/log 数据。搜索引擎不执行命令、不访问 SVN、不弹 UI，只输出排序后的 `CommandPaletteResult`，供后续 SwiftUI 命令面板和 AI Chat 面板绑定。

**技术栈：** Swift 6、Foundation、XCTest、现有 `LogEntry` / `Revision`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  - 增加命令面板模型：`CommandPaletteActionID`、`CommandPaletteAction`、`CommandPaletteFileItem`、`CommandPaletteResultKind`、`CommandPaletteResult`。
- 创建：`Sources/MacSvnCore/Services/CommandPaletteSearchEngine.swift`
  - 增加 `CommandPaletteSearchEngine`，实现 action/file/log 搜索与 AI Chat handoff。
- 创建：`Tests/MacSvnCoreTests/CommandPaletteSearchEngineTests.swift`
  - 覆盖排序、revision/关键字日志搜索、自然语言 handoff、空查询。

---

## 任务 1：动作/文件/日志搜索主路径

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/CommandPaletteSearchEngine.swift`
- 创建测试：`Tests/MacSvnCoreTests/CommandPaletteSearchEngineTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `CommandPaletteSearchEngineTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class CommandPaletteSearchEngineTests: XCTestCase {
    func testSearchRanksActionsFilesAndLogs() {
        let engine = CommandPaletteSearchEngine(
            actions: [
                CommandPaletteAction(id: .commit, title: "提交更改", keywords: ["commit", "ci"]),
                CommandPaletteAction(id: .update, title: "更新工作副本", keywords: ["update", "pull"]),
                CommandPaletteAction(id: .switchBranch, title: "切换分支", keywords: ["branch", "switch"])
            ],
            files: [
                CommandPaletteFileItem(path: "Sources/LoginView.swift"),
                CommandPaletteFileItem(path: "Tests/LoginViewTests.swift")
            ],
            logs: [
                LogEntry(revision: Revision(1200), author: "alice", date: nil, message: "修复登录失败", changedPaths: []),
                LogEntry(revision: Revision(1199), author: "bob", date: nil, message: "调整支付回调", changedPaths: [])
            ]
        )

        let actionResults = engine.search("commit")
        let fileResults = engine.search("login view")
        let revisionResults = engine.search("r1200")
        let keywordResults = engine.search("支付")

        XCTAssertEqual(actionResults.first?.kind, .action(.commit))
        XCTAssertEqual(actionResults.first?.title, "提交更改")
        XCTAssertEqual(fileResults.first?.kind, .file(path: "Sources/LoginView.swift"))
        XCTAssertEqual(revisionResults.first?.kind, .log(revision: Revision(1200)))
        XCTAssertEqual(keywordResults.first?.kind, .log(revision: Revision(1199)))
        XCTAssertGreaterThan(actionResults.first?.score ?? 0, 0)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommandPaletteSearchEngineTests
```

预期：编译失败，提示 `CommandPaletteSearchEngine`、`CommandPaletteAction` 或 `CommandPaletteResultKind` 不存在。

- [x] **步骤 3：实现最少模型与搜索引擎**

在 `SvnModels.swift` 增加：

```swift
public enum CommandPaletteActionID: String, Codable, Equatable, Hashable, Sendable {
    case commit
    case update
    case switchBranch
    case openWorkingCopy
}

public struct CommandPaletteAction: Equatable, Sendable {
    public let id: CommandPaletteActionID
    public let title: String
    public let keywords: [String]

    public init(id: CommandPaletteActionID, title: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.keywords = keywords
    }
}

public struct CommandPaletteFileItem: Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public enum CommandPaletteResultKind: Equatable, Sendable {
    case action(CommandPaletteActionID)
    case file(path: String)
    case log(revision: Revision)
    case aiChat(query: String)
}

public struct CommandPaletteResult: Equatable, Sendable {
    public let kind: CommandPaletteResultKind
    public let title: String
    public let subtitle: String?
    public let score: Int

    public init(kind: CommandPaletteResultKind, title: String, subtitle: String?, score: Int) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
    }
}
```

创建 `CommandPaletteSearchEngine.swift`：

```swift
import Foundation

public struct CommandPaletteSearchEngine: Sendable {
    private let actions: [CommandPaletteAction]
    private let files: [CommandPaletteFileItem]
    private let logs: [LogEntry]

    public init(actions: [CommandPaletteAction], files: [CommandPaletteFileItem], logs: [LogEntry]) {
        self.actions = actions
        self.files = files
        self.logs = logs
    }

    public func search(_ rawQuery: String, limit: Int = 20) -> [CommandPaletteResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return []
        }

        let results = actionResults(query: query) + fileResults(query: query) + logResults(query: query)
        return Array(results.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }.prefix(max(1, limit)))
    }

    private func actionResults(query: String) -> [CommandPaletteResult] {
        actions.compactMap { action in
            let haystack = ([action.title] + action.keywords).joined(separator: " ")
            guard let score = Self.score(query: query, text: haystack) else {
                return nil
            }
            return CommandPaletteResult(kind: .action(action.id), title: action.title, subtitle: nil, score: score + 10)
        }
    }

    private func fileResults(query: String) -> [CommandPaletteResult] {
        files.compactMap { file in
            guard let score = Self.score(query: query, text: file.path) else {
                return nil
            }
            return CommandPaletteResult(kind: .file(path: file.path), title: (file.path as NSString).lastPathComponent, subtitle: file.path, score: score)
        }
    }

    private func logResults(query: String) -> [CommandPaletteResult] {
        logs.compactMap { entry in
            let revisionToken = "r\(entry.revision.value)"
            let haystack = "\(revisionToken) \(entry.author) \(entry.message)"
            guard let score = Self.score(query: query, text: haystack) else {
                return nil
            }
            return CommandPaletteResult(kind: .log(revision: entry.revision), title: revisionToken, subtitle: "\(entry.author): \(entry.message)", score: score + 5)
        }
    }

    private static func score(query: String, text: String) -> Int? {
        let queryTokens = query.lowercased().split(separator: " ").map(String.init)
        let lowerText = text.lowercased()
        guard queryTokens.allSatisfy({ lowerText.contains($0) }) else {
            return nil
        }
        let exactBonus = lowerText == query.lowercased() ? 100 : 0
        let prefixBonus = lowerText.hasPrefix(query.lowercased()) ? 50 : 0
        return exactBonus + prefixBonus + queryTokens.reduce(0) { $0 + $1.count }
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter CommandPaletteSearchEngineTests
```

预期：主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Services/CommandPaletteSearchEngine.swift Tests/MacSvnCoreTests/CommandPaletteSearchEngineTests.swift docs/superpowers/plans/2026-07-10-p6-command-palette-core.md
git diff --cached --check
git commit -m "feat: add P6 command palette search core"
```

---

## 任务 2：自然语言 AI handoff 与空查询

**文件：**
- 修改：`Sources/MacSvnCore/Services/CommandPaletteSearchEngine.swift`
- 修改测试：`Tests/MacSvnCoreTests/CommandPaletteSearchEngineTests.swift`

- [x] **步骤 1：编写失败测试**

在 `CommandPaletteSearchEngineTests` 增加：

```swift
func testSearchReturnsAIChatHandoffForNaturalLanguageWithoutStructuredMatches() {
    let engine = CommandPaletteSearchEngine(actions: [], files: [], logs: [])

    let results = engine.search("帮我把未提交修改按功能分组")

    XCTAssertEqual(results, [
        CommandPaletteResult(
            kind: .aiChat(query: "帮我把未提交修改按功能分组"),
            title: "转给 AI 助手",
            subtitle: "帮我把未提交修改按功能分组",
            score: 1
        )
    ])
}

func testSearchReturnsEmptyForWhitespaceOnlyQuery() {
    let engine = CommandPaletteSearchEngine(actions: [], files: [], logs: [])

    XCTAssertEqual(engine.search("   "), [])
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter CommandPaletteSearchEngineTests
```

预期：自然语言 handoff 测试失败，因为任务 1 实现无结构化命中时返回空数组。

- [x] **步骤 3：实现 AI handoff**

实现要求：
- 空白查询返回空数组；
- 非空查询如果没有结构化 action/file/log 命中，返回一个 `.aiChat(query:)` 结果；
- 如果已有结构化命中，不追加 AI Chat 结果，避免抢占明确命令。

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter CommandPaletteSearchEngineTests
```

预期：全部 `CommandPaletteSearchEngineTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/CommandPaletteSearchEngine.swift Tests/MacSvnCoreTests/CommandPaletteSearchEngineTests.swift docs/superpowers/plans/2026-07-10-p6-command-palette-core.md
git diff --cached --check
git commit -m "test: cover P6 command palette AI handoff"
```

---

## 任务 3：目标验证与计划收尾

- [x] **步骤 1：运行 FR-EX-04 目标集合**

```bash
swift test --filter "CommandPaletteSearchEngineTests|LogViewModelTests|RepoBrowserViewModelTests"
```

预期：0 failures。

- [x] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：全量测试 0 failures，空白检查无输出。

- [x] **步骤 3：Commit**

```bash
git add docs/superpowers/plans/2026-07-10-p6-command-palette-core.md
git diff --cached --check
git commit -m "docs: complete P6 command palette verification"
```
