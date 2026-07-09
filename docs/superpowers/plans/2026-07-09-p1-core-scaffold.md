# P1 Core Scaffold 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 MacSVN P1 建立可测试的 Swift 核心包，先实现 CLI 后端会依赖的领域模型、错误映射、认证参数构造、提交/update/status 输出解析。

**架构：** 新增 Swift Package `MacSvnCore`，作为后续 SwiftUI App 与 `SvnCliBackend` 共享的底层模块。首批代码只包含纯模型、纯解析器和纯参数构造，避免引入真实 `Process` 或 UI 依赖，确保可以用 XCTest 快速验证。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest、Foundation `XMLParser`。

---

## 文件结构

- 创建：`Package.swift`  
  定义 `MacSvnCore` library target 和 `MacSvnCoreTests` test target，macOS 14 起步。
- 创建：`Sources/MacSvnCore/Models/SvnModels.swift`  
  定义 `SvnVersion`、`Revision`、`ItemStatus`、`FileStatus`、`UpdateSummary`、`Credential` 等 P1 底层模型。
- 创建：`Sources/MacSvnCore/Errors/SvnError.swift`  
  定义 `SvnError` 枚举并保持 `Equatable`，方便测试错误分类。
- 创建：`Sources/MacSvnCore/Errors/SvnErrorMapper.swift`  
  从 `svn: E<num>` stderr 映射认证、out-of-date、WC locked、network、other 等错误。
- 创建：`Sources/MacSvnCore/Backend/AuthArguments.swift`  
  认证参数唯一入口，生成 `--username` 与 `--password-from-stdin`，密码只进 stdin data。
- 创建：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`  
  先实现 P1 commit/update/status 的参数构造，统一追加 `--non-interactive`、`--xml`、`--encoding UTF-8`、`--accept postpone`。
- 创建：`Sources/MacSvnCore/Parsers/CommitOutputParser.swift`  
  解析 `Committed revision N.`。
- 创建：`Sources/MacSvnCore/Parsers/UpdateOutputParser.swift`  
  容错解析 update 文本输出，统计 A/U/D/C/G/E/R 和目标 revision。
- 创建：`Sources/MacSvnCore/Parsers/StatusXMLParser.swift`  
  使用 `XMLParser` 解析 `svn status --xml`，支持中文路径、unversioned/modified/added/deleted/missing/conflicted/ignored/external/replaced/normal 和 `tree-conflicted`。
- 创建：`Tests/MacSvnCoreTests/SvnErrorMapperTests.swift`
- 创建：`Tests/MacSvnCoreTests/AuthArgumentsTests.swift`
- 创建：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 创建：`Tests/MacSvnCoreTests/CommitOutputParserTests.swift`
- 创建：`Tests/MacSvnCoreTests/UpdateOutputParserTests.swift`
- 创建：`Tests/MacSvnCoreTests/StatusXMLParserTests.swift`

## 任务 1：建立 Swift Package 与错误/认证核心

**文件：**
- 创建：`Package.swift`
- 创建：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Errors/SvnError.swift`
- 创建：`Sources/MacSvnCore/Errors/SvnErrorMapper.swift`
- 创建：`Sources/MacSvnCore/Backend/AuthArguments.swift`
- 测试：`Tests/MacSvnCoreTests/SvnErrorMapperTests.swift`
- 测试：`Tests/MacSvnCoreTests/AuthArgumentsTests.swift`

- [ ] **步骤 1：编写失败的错误映射测试**

```swift
import XCTest
@testable import MacSvnCore

final class SvnErrorMapperTests: XCTestCase {
    func testMapsAuthenticationErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E170001: Authentication failed")
        XCTAssertEqual(error, .authentication)
    }

    func testMapsOutOfDateErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E155011: File is out of date")
        XCTAssertEqual(error, .outOfDate)
    }

    func testMapsWorkingCopyLockedErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E155004: Working copy is locked")
        XCTAssertEqual(error, .wcLocked)
    }

    func testUnknownErrorPreservesCodeAndStderr() {
        let stderr = "svn: E199999: Strange failure"
        let error = SvnErrorMapper.map(exitCode: 7, stderr: stderr)
        XCTAssertEqual(error, .other(code: 199999, stderr: stderr))
    }
}
```

- [ ] **步骤 2：编写失败的认证参数测试**

```swift
import XCTest
@testable import MacSvnCore

final class AuthArgumentsTests: XCTestCase {
    func testBuildsUsernameAndPasswordFromStdinWithoutLeakingPasswordInArguments() throws {
        let credential = Credential(username: "yangchao", password: "secret-pass")
        let result = try AuthArguments.build(credential: credential)

        XCTAssertEqual(result.arguments, ["--username", "yangchao", "--password-from-stdin"])
        XCTAssertEqual(result.stdin, Data("secret-pass\n".utf8))
        XCTAssertFalse(result.arguments.contains("secret-pass"))
    }

    func testNilCredentialBuildsNoArgumentsAndNoStdin() throws {
        let result = try AuthArguments.build(credential: nil)

        XCTAssertEqual(result.arguments, [])
        XCTAssertNil(result.stdin)
    }
}
```

- [ ] **步骤 3：运行测试验证失败**

运行：`swift test --filter SvnErrorMapperTests --filter AuthArgumentsTests`  
预期：FAIL 或编译失败，提示 `no such module 'MacSvnCore'` 或类型未定义。

- [ ] **步骤 4：编写最少实现代码**

实现 `Package.swift`、模型、`SvnError`、`SvnErrorMapper.map`、`AuthArguments.build`。`SvnError` 必须为 `Equatable`；`AuthArguments` 返回 `(arguments: [String], stdin: Data?)` 结构体。

- [ ] **步骤 5：运行测试验证通过**

运行：`swift test --filter SvnErrorMapperTests && swift test --filter AuthArgumentsTests`  
预期：两个测试类全部 PASS。

- [ ] **步骤 6：Commit**

```bash
git add Package.swift Sources/MacSvnCore Tests/MacSvnCoreTests
git commit -m "feat: add P1 core error and auth foundation"
```

## 任务 2：实现 P1 CLI 参数构造

**文件：**
- 创建：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`

- [ ] **步骤 1：编写失败的命令构造测试**

```swift
import XCTest
@testable import MacSvnCore

final class SvnCommandBuilderTests: XCTestCase {
    func testStatusUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.status()
        XCTAssertEqual(command.arguments, ["status", "--xml", "--non-interactive"])
    }

    func testCommitUsesUtf8EncodingNonInteractiveMessageAndPaths() {
        let command = SvnCommandBuilder.commit(paths: ["src/a.swift", "中文/文件.txt"], message: "修复：登录超时")
        XCTAssertEqual(command.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "修复：登录超时",
            "src/a.swift", "中文/文件.txt"
        ])
    }

    func testUpdatePostponesConflictsAndCanTargetRevision() {
        let command = SvnCommandBuilder.update(paths: ["src"], revision: Revision(42))
        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive", "-r", "42", "src"
        ])
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCommandBuilderTests`  
预期：FAIL 或编译失败，提示 `SvnCommandBuilder` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `SvnCommand` 和 `SvnCommandBuilder`，只包含 `status()`、`commit(paths:message:)`、`update(paths:revision:)` 三个方法。参数顺序必须与测试一致。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnCommandBuilderTests`  
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift
git commit -m "feat: add P1 svn command builders"
```

## 任务 3：实现提交与 update 输出解析

**文件：**
- 创建：`Sources/MacSvnCore/Parsers/CommitOutputParser.swift`
- 创建：`Sources/MacSvnCore/Parsers/UpdateOutputParser.swift`
- 测试：`Tests/MacSvnCoreTests/CommitOutputParserTests.swift`
- 测试：`Tests/MacSvnCoreTests/UpdateOutputParserTests.swift`

- [ ] **步骤 1：编写失败的提交解析测试**

```swift
import XCTest
@testable import MacSvnCore

final class CommitOutputParserTests: XCTestCase {
    func testParsesCommittedRevision() throws {
        let revision = try CommitOutputParser.parseRevision(from: "Sending file\nCommitted revision 42.\n")
        XCTAssertEqual(revision, Revision(42))
    }

    func testThrowsParseErrorWhenRevisionIsMissing() {
        XCTAssertThrowsError(try CommitOutputParser.parseRevision(from: "No revision here")) { error in
            XCTAssertEqual(error as? SvnError, .parse(detail: "Unable to find committed revision in svn commit output."))
        }
    }
}
```

- [ ] **步骤 2：编写失败的 update 解析测试**

```swift
import XCTest
@testable import MacSvnCore

final class UpdateOutputParserTests: XCTestCase {
    func testParsesActionCountsAndRevision() throws {
        let output = """
        A    new.txt
        U    changed.txt
        D    removed.txt
        C    conflicted.txt
        G    merged.txt
        Updated to revision 88.
        """

        let summary = try UpdateOutputParser.parse(output)

        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(summary.conflicted, 1)
        XCTAssertEqual(summary.merged, 1)
        XCTAssertEqual(summary.revision, Revision(88))
    }

    func testIgnoresUnknownLines() throws {
        let output = """
        Random progress line
        U    known.txt
        At revision 9.
        """

        let summary = try UpdateOutputParser.parse(output)

        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.revision, Revision(9))
    }
}
```

- [ ] **步骤 3：运行测试验证失败**

运行：`swift test --filter CommitOutputParserTests && swift test --filter UpdateOutputParserTests`  
预期：FAIL 或编译失败，提示 parser 类型未定义。

- [ ] **步骤 4：编写最少实现代码**

实现提交 revision 正则与 update 行首动作解析。update 解析应识别 `Updated to revision N.` 和 `At revision N.`，未知行忽略。

- [ ] **步骤 5：运行测试验证通过**

运行：`swift test --filter CommitOutputParserTests && swift test --filter UpdateOutputParserTests`  
预期：PASS。

- [ ] **步骤 6：Commit**

```bash
git add Sources/MacSvnCore/Parsers Tests/MacSvnCoreTests/CommitOutputParserTests.swift Tests/MacSvnCoreTests/UpdateOutputParserTests.swift
git commit -m "feat: add P1 commit and update parsers"
```

## 任务 4：实现 status XML 解析

**文件：**
- 创建：`Sources/MacSvnCore/Parsers/StatusXMLParser.swift`
- 测试：`Tests/MacSvnCoreTests/StatusXMLParserTests.swift`

- [ ] **步骤 1：编写失败的 status XML 解析测试**

```swift
import XCTest
@testable import MacSvnCore

final class StatusXMLParserTests: XCTestCase {
    func testParsesMixedStatusesAndTreeConflict() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <status>
          <target path=".">
            <entry path="Sources/App.swift">
              <wc-status item="modified" revision="12"/>
            </entry>
            <entry path="中文/新增.txt">
              <wc-status item="added" revision="0"/>
            </entry>
            <entry path="deleted.txt">
              <wc-status item="deleted" revision="10"/>
            </entry>
            <entry path="conflict.txt">
              <wc-status item="conflicted" revision="11" tree-conflicted="true"/>
            </entry>
            <entry path="ignored.log">
              <wc-status item="ignored"/>
            </entry>
          </target>
        </status>
        """

        let statuses = try StatusXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(statuses.map(\\.path), [
            "Sources/App.swift",
            "中文/新增.txt",
            "deleted.txt",
            "conflict.txt",
            "ignored.log"
        ])
        XCTAssertEqual(statuses.map(\\.itemStatus), [.modified, .added, .deleted, .conflicted, .ignored])
        XCTAssertEqual(statuses[0].revision, Revision(12))
        XCTAssertTrue(statuses[3].isTreeConflict)
    }

    func testInvalidXMLThrowsParseError() {
        XCTAssertThrowsError(try StatusXMLParser.parse(Data("<status>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \\(error)")
            }
        }
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter StatusXMLParserTests`  
预期：FAIL 或编译失败，提示 `StatusXMLParser` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `XMLParserDelegate`，在 `entry` 开始时记录 path，在 `wc-status` 开始时映射 item、revision、`tree-conflicted`，在 entry 结束时追加 `FileStatus`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter StatusXMLParserTests`  
预期：PASS。

- [ ] **步骤 5：运行全部核心测试**

运行：`swift test`  
预期：所有测试 PASS，无编译警告。

- [ ] **步骤 6：Commit**

```bash
git add Sources/MacSvnCore/Parsers/StatusXMLParser.swift Tests/MacSvnCoreTests/StatusXMLParserTests.swift
git commit -m "feat: add P1 status xml parser"
```
