# P5 URL Scheme CLI Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-07` 建立 `macsvn://` URL Scheme 与轻量 `macsvn` CLI 伴生命令的 Core 解析层，把外部深链和终端参数转换成可审计、可测试的强类型动作。

**架构：** 新增纯 Swift 自动化模型和两个解析器：`MacSvnDeepLinkParser` 只解析 `macsvn://open/log/diff?...`，`MacSvnCLICommandParser` 只解析 `macsvn open/status/commit-ui` 参数。二者不触发 UI、不执行 SVN、不访问文件系统，只返回强类型动作供后续 App target 路由。

**技术栈：** Swift 6、Foundation `URLComponents`、XCTest、现有 `Revision` / `RevisionRange`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Models/AutomationModels.swift`
  - 增加 `MacSvnAutomationTarget`、`MacSvnDeepLinkAction`、`MacSvnDeepLinkParserError`、`MacSvnCLICommand`、`MacSvnCLICommandParserError`。
- 创建：`Sources/MacSvnCore/Services/MacSvnDeepLinkParser.swift`
  - 解析 `macsvn://open?path=...`、`macsvn://log?path=...&rev=...` / `url=...`、`macsvn://diff?path=...&from=...&to=...` / `url=...`。
- 创建：`Sources/MacSvnCore/Services/MacSvnCLICommandParser.swift`
  - 解析 `open <path>`、`status <path>`、`commit-ui <path> [--message <message>]`。
- 创建测试：`Tests/MacSvnCoreTests/MacSvnAutomationParserTests.swift`
  - 覆盖深链成功路径、深链错误路径、CLI 成功路径、CLI 错误路径。

---

## 任务 1：macsvn:// 深链解析

**文件：**
- 创建：`Sources/MacSvnCore/Models/AutomationModels.swift`
- 创建：`Sources/MacSvnCore/Services/MacSvnDeepLinkParser.swift`
- 创建测试：`Tests/MacSvnCoreTests/MacSvnAutomationParserTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `MacSvnAutomationParserTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class MacSvnAutomationParserTests: XCTestCase {
    func testDeepLinkParserParsesOpenLogAndDiffActions() throws {
        let parser = MacSvnDeepLinkParser()

        let open = try parser.parse(URL(string: "macsvn://open?path=/Users/me/repo")!)
        let log = try parser.parse(URL(string: "macsvn://log?url=https%3A%2F%2Fsvn.example.com%2Frepo%2Ftrunk&rev=r1200")!)
        let diff = try parser.parse(URL(string: "macsvn://diff?path=Sources%2FApp.swift&from=1199&to=1200")!)

        XCTAssertEqual(open, .open(path: "/Users/me/repo"))
        XCTAssertEqual(log, .log(target: .repositoryURL("https://svn.example.com/repo/trunk"), revision: Revision(1200)))
        XCTAssertEqual(diff, .diff(target: .path("Sources/App.swift"), range: RevisionRange(start: Revision(1199), end: Revision(1200))))
    }

    func testDeepLinkParserRejectsInvalidSchemeUnknownRouteMissingTargetAndBadRevision() throws {
        let parser = MacSvnDeepLinkParser()

        XCTAssertThrowsError(try parser.parse(URL(string: "https://open?path=/repo")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .invalidScheme("https"))
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "macsvn://blame?path=/repo/file.swift")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .unknownRoute("blame"))
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "macsvn://log?rev=1")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .missingTarget)
        }
        XCTAssertThrowsError(try parser.parse(URL(string: "macsvn://log?path=/repo&rev=abc")!)) { error in
            XCTAssertEqual(error as? MacSvnDeepLinkParserError, .invalidRevision("abc"))
        }
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter MacSvnAutomationParserTests
```

预期：编译失败，提示 `MacSvnDeepLinkParser` 或相关模型不存在。

- [x] **步骤 3：实现深链模型与解析器**

在 `AutomationModels.swift` 增加：

```swift
import Foundation

public enum MacSvnAutomationTarget: Equatable, Sendable {
    case path(String)
    case repositoryURL(String)
}

public enum MacSvnDeepLinkAction: Equatable, Sendable {
    case open(path: String)
    case log(target: MacSvnAutomationTarget, revision: Revision?)
    case diff(target: MacSvnAutomationTarget, range: RevisionRange?)
}

public enum MacSvnDeepLinkParserError: Error, Equatable, Sendable {
    case invalidScheme(String?)
    case missingRoute
    case unknownRoute(String)
    case missingTarget
    case missingParameter(String)
    case invalidRevision(String)
}
```

创建 `MacSvnDeepLinkParser.swift`：

```swift
import Foundation

public struct MacSvnDeepLinkParser: Sendable {
    public init() {}

    public func parse(_ url: URL) throws -> MacSvnDeepLinkAction {
        guard url.scheme?.lowercased() == "macsvn" else {
            throw MacSvnDeepLinkParserError.invalidScheme(url.scheme)
        }
        guard let route = url.host?.lowercased(), !route.isEmpty else {
            throw MacSvnDeepLinkParserError.missingRoute
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items {
            if let value = item.value {
                values[item.name.lowercased()] = value
            }
        }

        switch route {
        case "open":
            guard let path = values["path"], !path.isEmpty else {
                throw MacSvnDeepLinkParserError.missingParameter("path")
            }
            return .open(path: path)
        case "log":
            let target = try target(from: values)
            return .log(target: target, revision: try optionalRevision(values["rev"]))
        case "diff":
            let target = try target(from: values)
            let from = try optionalRevision(values["from"])
            let to = try optionalRevision(values["to"])
            let range = try revisionRange(from: from, to: to)
            return .diff(target: target, range: range)
        default:
            throw MacSvnDeepLinkParserError.unknownRoute(route)
        }
    }

    private func target(from values: [String: String]) throws -> MacSvnAutomationTarget {
        if let path = values["path"], !path.isEmpty {
            return .path(path)
        }
        if let url = values["url"], !url.isEmpty {
            return .repositoryURL(url)
        }
        throw MacSvnDeepLinkParserError.missingTarget
    }

    private func optionalRevision(_ value: String?) throws -> Revision? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let normalized = value.lowercased().hasPrefix("r") ? String(value.dropFirst()) : value
        guard let intValue = Int(normalized) else {
            throw MacSvnDeepLinkParserError.invalidRevision(value)
        }
        return Revision(intValue)
    }

    private func revisionRange(from: Revision?, to: Revision?) throws -> RevisionRange? {
        switch (from, to) {
        case let (.some(start), .some(end)):
            return RevisionRange(start: start, end: end)
        case (nil, nil):
            return nil
        case (.some, nil):
            throw MacSvnDeepLinkParserError.missingParameter("to")
        case (nil, .some):
            throw MacSvnDeepLinkParserError.missingParameter("from")
        }
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter MacSvnAutomationParserTests
```

预期：深链相关测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AutomationModels.swift Sources/MacSvnCore/Services/MacSvnDeepLinkParser.swift Tests/MacSvnCoreTests/MacSvnAutomationParserTests.swift docs/superpowers/plans/2026-07-10-p5-url-scheme-cli-core.md
git diff --cached --check
git commit -m "feat: add P5 macsvn deep link parser core"
```

---

## 任务 2：轻量 CLI 伴生命令解析

**文件：**
- 修改：`Sources/MacSvnCore/Models/AutomationModels.swift`
- 创建：`Sources/MacSvnCore/Services/MacSvnCLICommandParser.swift`
- 修改测试：`Tests/MacSvnCoreTests/MacSvnAutomationParserTests.swift`

- [x] **步骤 1：编写失败测试**

在 `MacSvnAutomationParserTests` 增加：

```swift
func testCLICommandParserParsesOpenStatusAndCommitUICommands() throws {
    let parser = MacSvnCLICommandParser()

    XCTAssertEqual(try parser.parse(["open", "/Users/me/repo"]), .open(path: "/Users/me/repo"))
    XCTAssertEqual(try parser.parse(["status", "/Users/me/repo"]), .status(path: "/Users/me/repo"))
    XCTAssertEqual(
        try parser.parse(["commit-ui", "/Users/me/repo", "--message", "修复登录失败"]),
        .commitUI(path: "/Users/me/repo", initialMessage: "修复登录失败")
    )
}

func testCLICommandParserRejectsEmptyUnknownMissingAndUnexpectedArguments() {
    let parser = MacSvnCLICommandParser()

    XCTAssertThrowsError(try parser.parse([])) { error in
        XCTAssertEqual(error as? MacSvnCLICommandParserError, .emptyArguments)
    }
    XCTAssertThrowsError(try parser.parse(["blame", "/repo/file.swift"])) { error in
        XCTAssertEqual(error as? MacSvnCLICommandParserError, .unknownCommand("blame"))
    }
    XCTAssertThrowsError(try parser.parse(["open"])) { error in
        XCTAssertEqual(error as? MacSvnCLICommandParserError, .missingValue("path"))
    }
    XCTAssertThrowsError(try parser.parse(["status", "/repo", "--json"])) { error in
        XCTAssertEqual(error as? MacSvnCLICommandParserError, .unexpectedArgument("--json"))
    }
    XCTAssertThrowsError(try parser.parse(["commit-ui", "/repo", "--message"])) { error in
        XCTAssertEqual(error as? MacSvnCLICommandParserError, .missingValue("--message"))
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter MacSvnAutomationParserTests
```

预期：编译失败，提示 `MacSvnCLICommandParser` 或 `MacSvnCLICommand` 不存在。

- [x] **步骤 3：实现 CLI 命令模型与解析器**

在 `AutomationModels.swift` 增加：

```swift
public enum MacSvnCLICommand: Equatable, Sendable {
    case open(path: String)
    case status(path: String)
    case commitUI(path: String, initialMessage: String?)
}

public enum MacSvnCLICommandParserError: Error, Equatable, Sendable {
    case emptyArguments
    case unknownCommand(String)
    case missingValue(String)
    case unexpectedArgument(String)
}
```

创建 `MacSvnCLICommandParser.swift`：

```swift
import Foundation

public struct MacSvnCLICommandParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> MacSvnCLICommand {
        guard let command = arguments.first else {
            throw MacSvnCLICommandParserError.emptyArguments
        }

        switch command {
        case "open":
            return .open(path: try singlePath(arguments))
        case "status":
            return .status(path: try singlePath(arguments))
        case "commit-ui":
            return try parseCommitUI(Array(arguments.dropFirst()))
        default:
            throw MacSvnCLICommandParserError.unknownCommand(command)
        }
    }

    private func singlePath(_ arguments: [String]) throws -> String {
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            throw MacSvnCLICommandParserError.missingValue("path")
        }
        guard arguments.count == 2 else {
            throw MacSvnCLICommandParserError.unexpectedArgument(arguments[2])
        }
        return arguments[1]
    }

    private func parseCommitUI(_ arguments: [String]) throws -> MacSvnCLICommand {
        guard let path = arguments.first, !path.isEmpty else {
            throw MacSvnCLICommandParserError.missingValue("path")
        }

        var message: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--message":
                let valueIndex = index + 1
                guard valueIndex < arguments.count, !arguments[valueIndex].isEmpty else {
                    throw MacSvnCLICommandParserError.missingValue("--message")
                }
                message = arguments[valueIndex]
                index += 2
            default:
                throw MacSvnCLICommandParserError.unexpectedArgument(argument)
            }
        }

        return .commitUI(path: path, initialMessage: message)
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter MacSvnAutomationParserTests
```

预期：全部 `MacSvnAutomationParserTests` PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/AutomationModels.swift Sources/MacSvnCore/Services/MacSvnCLICommandParser.swift Tests/MacSvnCoreTests/MacSvnAutomationParserTests.swift docs/superpowers/plans/2026-07-10-p5-url-scheme-cli-core.md
git diff --cached --check
git commit -m "feat: add P5 macsvn CLI command parser core"
```

---

## 任务 3：目标验证与计划收尾

- [x] **步骤 1：运行 FR-EX-07 目标集合**

```bash
swift test --filter "MacSvnAutomationParserTests|CommandPaletteSearchEngineTests|WorkspaceStoreTests"
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
git add docs/superpowers/plans/2026-07-10-p5-url-scheme-cli-core.md
git diff --cached --check
git commit -m "docs: complete P5 URL scheme CLI verification"
```
