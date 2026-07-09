# P4 Blame Core ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P4 `FR-BL-01` 的核心数据链路：解析 `svn blame --xml`，通过 `SvnBackend` / `SvnService` 暴露 blame 行数据，并提供可绑定的 `BlameViewModel`。

**架构：** 新增 `BlameLine` 模型和 `BlameXMLParser`，沿用现有 XMLParser delegate 风格。`SvnCommandBuilder` 负责生成 `blame --xml --non-interactive <target>`，`SvnCliBackend` 在 WC 目录执行并解析 XML，`SvnService` 透传查询，`BlameViewModel` 只负责加载状态、错误状态和选中 revision。

**技术栈：** Swift 6.1、Foundation XMLParser、Observation、XCTest concurrency、已有 `SvnBackend` / `SvnService` / `SvnError.parse`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  - 新增 `BlameLine`。
- 创建：`Sources/MacSvnCore/Parsers/BlameXMLParser.swift`
  - 解析 `svn blame --xml` 输出。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  - 新增 `blame(target:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  - 新增 `blame(wc:target:) async throws -> [BlameLine]`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  - 调用 command builder 并解析 blame XML。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  - 新增 `blame(wc:target:)` 查询方法。
- 创建：`Sources/MacSvnCore/ViewModels/BlameViewModel.swift`
  - 新增 blame 视图状态层。
- 创建：`Tests/MacSvnCoreTests/BlameXMLParserTests.swift`
  - 覆盖标准 XML、缺作者/日期、非法 XML。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  - 覆盖 blame argv。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  - 覆盖 backend 在 WC 中运行 blame 并解析。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  - 覆盖 service 透传。
- 创建：`Tests/MacSvnCoreTests/BlameViewModelTests.swift`
  - 覆盖加载成功、失败、选择 revision。

## 任务 1：BlameLine 模型与 XML Parser

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Parsers/BlameXMLParser.swift`
- 创建：`Tests/MacSvnCoreTests/BlameXMLParserTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `BlameXMLParserTests`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class BlameXMLParserTests: XCTestCase {
    func testParsesBlameLinesWithCommitMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <blame>
          <target path="README.txt">
            <entry line-number="1">
              <commit revision="7">
                <author>yangchao</author>
                <date>2026-07-09T06:00:00.000000Z</date>
              </commit>
            </entry>
            <entry line-number="2">
              <commit revision="8">
                <author>alice</author>
                <date>2026-07-09T07:00:00.000000Z</date>
              </commit>
            </entry>
          </target>
        </blame>
        """

        let lines = try BlameXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(lines, [
            BlameLine(
                lineNumber: 1,
                revision: Revision(7),
                author: "yangchao",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T06:00:00.000000Z")
            ),
            BlameLine(
                lineNumber: 2,
                revision: Revision(8),
                author: "alice",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T07:00:00.000000Z")
            )
        ])
    }

    func testParsesLineWithMissingCommitMetadata() throws {
        let xml = """
        <blame><target path="README.txt"><entry line-number="1"/></target></blame>
        """

        let lines = try BlameXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(lines, [
            BlameLine(lineNumber: 1, revision: nil, author: nil, date: nil)
        ])
    }

    func testInvalidBlameXMLThrowsParseError() {
        XCTAssertThrowsError(try BlameXMLParser.parse(Data("<blame>".utf8))) { error in
            guard case .parse = error as? SvnError else {
                return XCTFail("Expected SvnError.parse, got \(error)")
            }
        }
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter BlameXMLParserTests
```

预期：编译失败，提示 `BlameXMLParser` 和 `BlameLine` 未定义。

- [ ] **步骤 3：实现最少代码**

在 `SvnModels.swift` 中新增：

```swift
public struct BlameLine: Equatable, Sendable {
    public let lineNumber: Int
    public let revision: Revision?
    public let author: String?
    public let date: Date?

    public init(lineNumber: Int, revision: Revision?, author: String?, date: Date?) {
        self.lineNumber = lineNumber
        self.revision = revision
        self.author = author
        self.date = date
    }
}
```

创建 `BlameXMLParser.swift`，按 `blame/target/entry/commit` 结构解析：
- `entry@line-number` → `lineNumber`。
- `commit@revision` → `Revision?`。
- `author` 空文本转 nil。
- `date` 使用 `ISO8601DateFormatter.svnXML`。
- `entry` 结束时如果有合法 `lineNumber` 就追加 `BlameLine`。
- XML 解析失败抛 `SvnError.parse`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter BlameXMLParserTests
```

预期：3 个 parser 测试 PASS。

## 任务 2：Backend / Service blame 查询链路

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCommandBuilderTests` 新增：

```swift
func testBlameUsesXmlNonInteractiveAndTarget() {
    let command = SvnCommandBuilder.blame(target: "README.txt")

    XCTAssertEqual(command.arguments, ["blame", "--xml", "--non-interactive", "README.txt"])
}
```

在 `SvnCliBackendTests` 新增：

```swift
func testBlameRunsInWorkingCopyAndParsesXml() async throws {
    let xml = """
    <blame><target path="README.txt"><entry line-number="1"><commit revision="7"><author>yangchao</author><date>2026-07-09T06:00:00.000000Z</date></commit></entry></target></blame>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let lines = try await backend.blame(wc: wc, target: "README.txt")

    XCTAssertEqual(lines, [
        BlameLine(
            lineNumber: 1,
            revision: Revision(7),
            author: "yangchao",
            date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T06:00:00.000000Z")
        )
    ])
    XCTAssertEqual(runner.calls.single?.arguments, ["blame", "--xml", "--non-interactive", "README.txt"])
    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
}
```

在 `SvnServiceTests` 的 `FakeBackend` 添加 `blameResult`、`recordedBlameTargets`，新增测试：

```swift
func testBlameForwardsToBackend() async throws {
    let backend = FakeBackend()
    backend.blameResult = [
        BlameLine(lineNumber: 1, revision: Revision(7), author: "yangchao", date: nil)
    ]
    let service = SvnService(backend: backend)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let lines = try await service.blame(wc: wc, target: "README.txt")

    XCTAssertEqual(lines, backend.blameResult)
    XCTAssertEqual(await backend.blameCalls, [
        BlameCall(wc: wc, target: "README.txt")
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testBlame|SvnCliBackendTests/testBlame|SvnServiceTests/testBlame"
```

预期：编译失败，提示 `blame` command/backend/service API 未定义。

- [ ] **步骤 3：实现最少代码**

实现：
- `SvnCommandBuilder.blame(target:)` 返回 `["blame", "--xml", "--non-interactive", target]`。
- `SvnBackend` 新增 `blame(wc:target:)`。
- `SvnCliBackend.blame(wc:target:)` 在 `wc.path` 下运行 command，调用 `BlameXMLParser.parse`。
- `SvnService.blame(wc:target:)` 直接调用 backend。
- 更新 `FakeBackend` 满足协议。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testBlame|SvnCliBackendTests/testBlame|SvnServiceTests/testBlame"
```

预期：3 个 blame 链路测试 PASS。

## 任务 3：BlameViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/BlameViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/BlameViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `BlameViewModelTests`：

```swift
import XCTest
@testable import MacSvnCore

final class BlameViewModelTests: XCTestCase {
    @MainActor
    func testLoadBlameStoresLinesAndSelectsRevision() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let lines = [
            BlameLine(lineNumber: 1, revision: Revision(7), author: "yangchao", date: nil),
            BlameLine(lineNumber: 2, revision: Revision(8), author: "alice", date: nil)
        ]
        let provider = FakeBlameProvider(result: .success(lines))
        let viewModel = BlameViewModel(workingCopy: wc, target: "README.txt", provider: provider)

        await viewModel.load()
        viewModel.selectLine(2)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.lines, lines)
        XCTAssertEqual(viewModel.selectedRevision, Revision(8))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [BlameProviderCall(wc: wc, target: "README.txt")])
    }

    @MainActor
    func testLoadBlameFailureClearsLinesAndStoresError() async {
        let provider = FakeBlameProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = BlameViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.lines, [])
        XCTAssertNil(viewModel.selectedRevision)
    }
}
```

测试辅助：

```swift
struct BlameProviderCall: Equatable {
    let wc: URL
    let target: String
}

actor FakeBlameProvider: BlameProviding {
    private let result: Result<[BlameLine], Error>
    private var calls: [BlameProviderCall] = []

    init(result: Result<[BlameLine], Error>) {
        self.result = result
    }

    func recordedCalls() -> [BlameProviderCall] {
        calls
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        calls.append(BlameProviderCall(wc: wc, target: target))
        return try result.get()
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter BlameViewModelTests
```

预期：编译失败，提示 `BlameViewModel` / `BlameProviding` / `BlameViewState` 未定义。

- [ ] **步骤 3：实现最少代码**

创建：

```swift
public protocol BlameProviding: Sendable {
    func blame(wc: URL, target: String) async throws -> [BlameLine]
}

public enum BlameViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class BlameViewModel {
    private let workingCopy: URL
    private let target: String
    private let provider: any BlameProviding

    public private(set) var state: BlameViewState = .idle
    public private(set) var lines: [BlameLine] = []
    public private(set) var selectedRevision: Revision?

    public init(workingCopy: URL, target: String, provider: any BlameProviding) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
    }

    public func load() async {
        state = .loading
        lines = []
        selectedRevision = nil

        do {
            lines = try await provider.blame(wc: workingCopy, target: target)
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func selectLine(_ lineNumber: Int) {
        selectedRevision = lines.first { $0.lineNumber == lineNumber }?.revision
    }
}

extension SvnService: BlameProviding {}
```

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter BlameViewModelTests
```

预期：2 个 ViewModel 测试 PASS。

## 任务 4：真实 SVN 集成与全量验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败集成测试**

在 `SvnCliBackendIntegrationTests` 新增：

```swift
func testBlameReadsLineRevisionAuthorFromWorkingCopy() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)

    let lines = try await service.blame(wc: fixture.workingCopy, target: "README.txt")

    XCTAssertFalse(lines.isEmpty)
    XCTAssertEqual(lines.first?.lineNumber, 1)
    XCTAssertNotNil(lines.first?.revision)
    XCTAssertNotNil(lines.first?.author)
}
```

- [ ] **步骤 2：运行测试验证失败或通过**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testBlameReadsLineRevisionAuthorFromWorkingCopy
```

预期：如果任务 1-3 已实现，测试应 PASS；如果缺少真实 SVN 行为，会暴露具体失败。

- [ ] **步骤 3：运行 blame 目标集**

运行：

```bash
swift test --filter "BlameXMLParserTests|BlameViewModelTests|SvnCommandBuilderTests/testBlame|SvnCliBackendTests/testBlame|SvnServiceTests/testBlame|SvnCliBackendIntegrationTests/testBlameReadsLineRevisionAuthorFromWorkingCopy"
```

预期：全部 PASS。

- [ ] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全量测试 PASS，空白检查无输出。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p4-blame-core-view-model.md
git commit -m "feat: add P4 blame core view model"
```

## 自检

- 覆盖 `FR-BL-01` 的核心数据链路：逐行 revision、作者、日期可从 SVN XML 进入 ViewModel。
- 不实现 SwiftUI blame 视图；实际行表格渲染和点击跳 Log 留给后续 UI shell。
- 不添加外部依赖。
- 不改变现有 log/status/diff 命令行为。
