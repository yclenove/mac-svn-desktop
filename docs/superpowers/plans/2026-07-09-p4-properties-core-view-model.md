# P4 Properties Core ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P4 `FR-PR-01` 的核心数据链路：查看、设置、删除文件/目录 SVN versioned properties，并提供可绑定的 `PropertyViewModel`。

**架构：** 新增 `SvnProperty` 模型和 `PropertyXMLParser`，解析 `svn proplist --xml --verbose` / `svn propget --xml` 输出。`SvnCommandBuilder` 负责构造 `proplist`、`propget`、`propset`、`propdel` 参数；`SvnCliBackend` 在 WC 目录执行；`SvnService` 对属性写操作复用现有每 WC 写锁；`PropertyViewModel` 负责加载、保存、删除、模板列表和错误状态。

**技术栈：** Swift 6.1、Foundation XMLParser、Observation、XCTest concurrency、现有 `SvnBackend` / `SvnService` / `ProcessRunner`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  - 新增 `SvnProperty`、`SvnPropertyTemplate`。
- 创建：`Sources/MacSvnCore/Parsers/PropertyXMLParser.swift`
  - 解析 `<properties><target path="..."><property name="...">value</property></target></properties>`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  - 新增 `proplist(target:)`、`propget(name:target:)`、`propset(name:value:target:)`、`propdel(name:target:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  - 新增 `properties`、`propertyValue`、`setProperty`、`deleteProperty`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  - 接入属性命令与 parser。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  - 新增属性查询和写操作，写操作走 `withWriteLock`。
- 创建：`Sources/MacSvnCore/ViewModels/PropertyViewModel.swift`
  - 提供 P4 属性页状态层和常用属性模板。
- 创建：`Tests/MacSvnCoreTests/PropertyXMLParserTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 创建：`Tests/MacSvnCoreTests/PropertyViewModelTests.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：属性模型与 XML Parser

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Parsers/PropertyXMLParser.swift`
- 创建：`Tests/MacSvnCoreTests/PropertyXMLParserTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `PropertyXMLParserTests`：

```swift
import XCTest
@testable import MacSvnCore

final class PropertyXMLParserTests: XCTestCase {
    func testParsesPropertiesWithTargetPathNameAndValue() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <properties>
          <target path="README.txt">
            <property name="svn:eol-style">native</property>
            <property name="custom:reviewer">杨超</property>
          </target>
        </properties>
        """

        let properties = try PropertyXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(properties, [
            SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native"),
            SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")
        ])
    }

    func testParsesEmptyPropertyValue() throws {
        let xml = """
        <properties><target path="README.txt"><property name="svn:needs-lock"></property></target></properties>
        """

        let properties = try PropertyXMLParser.parse(Data(xml.utf8))

        XCTAssertEqual(properties, [
            SvnProperty(target: "README.txt", name: "svn:needs-lock", value: "")
        ])
    }

    func testInvalidPropertyXMLThrowsParseError() {
        XCTAssertThrowsError(try PropertyXMLParser.parse(Data("<properties>".utf8))) { error in
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
swift test --filter PropertyXMLParserTests
```

预期：编译失败，提示 `PropertyXMLParser` / `SvnProperty` 未定义。

- [ ] **步骤 3：实现最少代码**

在 `SvnModels.swift` 新增：

```swift
public struct SvnProperty: Equatable, Sendable {
    public let target: String
    public let name: String
    public let value: String

    public init(target: String, name: String, value: String) {
        self.target = target
        self.name = name
        self.value = value
    }
}

public struct SvnPropertyTemplate: Equatable, Sendable {
    public let name: String
    public let defaultValue: String
    public let appliesToDirectory: Bool
    public let appliesToFile: Bool

    public init(name: String, defaultValue: String, appliesToDirectory: Bool, appliesToFile: Bool) {
        self.name = name
        self.defaultValue = defaultValue
        self.appliesToDirectory = appliesToDirectory
        self.appliesToFile = appliesToFile
    }
}
```

创建 `PropertyXMLParser`：
- `target@path` 记录当前 target。
- `property@name` 记录当前 property name。
- `property` 结束时追加 `SvnProperty(target:name:value:)`。
- 属性 value 保留原始文本内容，不 trim 掉中文或多行内容；只由 XMLParser 合并 `foundCharacters`。
- XML 解析失败抛 `SvnError.parse`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter PropertyXMLParserTests
```

预期：3 个 parser 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Parsers/PropertyXMLParser.swift Tests/MacSvnCoreTests/PropertyXMLParserTests.swift docs/superpowers/plans/2026-07-09-p4-properties-core-view-model.md
git commit -m "feat: add P4 property XML parser"
```

## 任务 2：属性命令、Backend、Service

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
func testPropertyCommandsUseXmlUtf8AndNonInteractive() {
    XCTAssertEqual(
        SvnCommandBuilder.proplist(target: "README.txt").arguments,
        ["proplist", "--xml", "--verbose", "--non-interactive", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.propget(name: "svn:eol-style", target: "README.txt").arguments,
        ["propget", "--xml", "--non-interactive", "svn:eol-style", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.propset(name: "svn:eol-style", value: "native", target: "README.txt").arguments,
        ["propset", "--encoding", "UTF-8", "--non-interactive", "svn:eol-style", "native", "README.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.propdel(name: "svn:eol-style", target: "README.txt").arguments,
        ["propdel", "--non-interactive", "svn:eol-style", "README.txt"]
    )
}
```

在 `SvnCliBackendTests` 新增：

```swift
func testPropertyQueriesRunInWorkingCopyAndParseXml() async throws {
    let xml = """
    <properties><target path="README.txt"><property name="svn:eol-style">native</property></target></properties>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let properties = try await backend.properties(wc: wc, target: "README.txt")

    XCTAssertEqual(properties, [
        SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
    ])
    XCTAssertEqual(runner.calls.single?.arguments, ["proplist", "--xml", "--verbose", "--non-interactive", "README.txt"])
    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
}

func testPropertyValueReturnsFirstMatchingProperty() async throws {
    let xml = """
    <properties><target path="README.txt"><property name="svn:eol-style">native</property></target></properties>
    """
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    let property = try await backend.propertyValue(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        target: "README.txt",
        name: "svn:eol-style"
    )

    XCTAssertEqual(property, SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native"))
    XCTAssertEqual(runner.calls.single?.arguments, ["propget", "--xml", "--non-interactive", "svn:eol-style", "README.txt"])
}

func testPropertyWritesRunInWorkingCopy() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    try await backend.setProperty(wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超")
    try await backend.deleteProperty(wc: wc, target: "README.txt", name: "custom:reviewer")

    XCTAssertEqual(runner.calls.map(\.arguments), [
        ["propset", "--encoding", "UTF-8", "--non-interactive", "custom:reviewer", "杨超", "README.txt"],
        ["propdel", "--non-interactive", "custom:reviewer", "README.txt"]
    ])
    XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/wc", "/tmp/wc"])
}
```

在 `SvnServiceTests` 的 `MockSvnBackend` 加属性结果与调用记录，新增：

```swift
func testPropertyMethodsForwardToBackendAndWritesUseLocks() async throws {
    let backend = MockSvnBackend()
    backend.propertiesResult = [
        SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
    ]
    backend.propertyValueResult = SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
    let service = SvnService(backend: backend)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let properties = try await service.properties(wc: wc, target: "README.txt")
    let value = try await service.propertyValue(wc: wc, target: "README.txt", name: "svn:eol-style")
    try await service.setProperty(wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超")
    try await service.deleteProperty(wc: wc, target: "README.txt", name: "custom:reviewer")

    XCTAssertEqual(properties, backend.propertiesResult)
    XCTAssertEqual(value, backend.propertyValueResult)
    XCTAssertEqual(backend.calls.map(\.name), ["properties", "propertyValue", "setProperty", "deleteProperty"])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testProperty|SvnCliBackendTests/testProperty|SvnServiceTests/testProperty"
```

预期：编译失败，提示属性 command/backend/service API 未定义。

- [ ] **步骤 3：实现最少代码**

实现：
- `SvnCommandBuilder.proplist(target:)`。
- `SvnCommandBuilder.propget(name:target:)`。
- `SvnCommandBuilder.propset(name:value:target:)`。
- `SvnCommandBuilder.propdel(name:target:)`。
- `SvnBackend` 新增四个属性方法。
- `SvnCliBackend` 调用命令并用 `PropertyXMLParser.parse`。
- `propertyValue` 返回 parser 的 first。
- `SvnService.properties` / `propertyValue` 直接查询。
- `SvnService.setProperty` / `deleteProperty` 走 `withWriteLock(wc:operation:)`。
- 更新 `MockSvnBackend`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testProperty|SvnCliBackendTests/testProperty|SvnServiceTests/testProperty"
```

预期：属性链路测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Backend Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift
git commit -m "feat: add P4 property backend service"
```

## 任务 3：PropertyViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/PropertyViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/PropertyViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `PropertyViewModelTests`：

```swift
import XCTest
@testable import MacSvnCore

final class PropertyViewModelTests: XCTestCase {
    @MainActor
    func testLoadSaveDeletePropertiesAndRefreshesList() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakePropertyProvider(results: [
            .success([SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")]),
            .success([SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")]),
            .success([])
        ])
        let viewModel = PropertyViewModel(workingCopy: wc, target: "README.txt", provider: provider)

        await viewModel.load()
        await viewModel.save(name: "custom:reviewer", value: "杨超")
        await viewModel.delete(name: "custom:reviewer")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.properties, [])
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil),
            PropertyProviderCall(operation: "set", wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超"),
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil),
            PropertyProviderCall(operation: "delete", wc: wc, target: "README.txt", name: "custom:reviewer", value: nil),
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil)
        ])
    }

    @MainActor
    func testRejectsEmptyPropertyNameBeforeProviderCall() async {
        let provider = FakePropertyProvider(results: [.success([])])
        let viewModel = PropertyViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.save(name: "  ", value: "x")

        XCTAssertEqual(viewModel.state, .error("emptyPropertyName"))
        XCTAssertEqual(await provider.recordedCalls(), [])
    }

    func testCommonTemplatesIncludeSvnIgnoreEolExecutableAndNeedsLock() {
        XCTAssertEqual(PropertyViewModel.commonTemplates.map(\.name), [
            "svn:ignore",
            "svn:eol-style",
            "svn:executable",
            "svn:needs-lock"
        ])
    }
}
```

测试辅助：

```swift
struct PropertyProviderCall: Equatable {
    let operation: String
    let wc: URL
    let target: String
    let name: String?
    let value: String?
}

actor FakePropertyProvider: PropertyProviding {
    private var results: [Result<[SvnProperty], Error>]
    private var calls: [PropertyProviderCall] = []

    init(results: [Result<[SvnProperty], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [PropertyProviderCall] {
        calls
    }

    func properties(wc: URL, target: String) async throws -> [SvnProperty] {
        calls.append(PropertyProviderCall(operation: "properties", wc: wc, target: target, name: nil, value: nil))
        return try results.removeFirst().get()
    }

    func setProperty(wc: URL, target: String, name: String, value: String) async throws {
        calls.append(PropertyProviderCall(operation: "set", wc: wc, target: target, name: name, value: value))
    }

    func deleteProperty(wc: URL, target: String, name: String) async throws {
        calls.append(PropertyProviderCall(operation: "delete", wc: wc, target: target, name: name, value: nil))
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter PropertyViewModelTests
```

预期：编译失败，提示 `PropertyViewModel` / `PropertyProviding` 未定义。

- [ ] **步骤 3：实现最少代码**

创建 `PropertyViewModel`：
- `PropertyProviding` 协议：`properties`、`setProperty`、`deleteProperty`。
- `PropertyViewState`: `.idle`、`.loading`、`.saving`、`.deleting`、`.loaded`、`.error(String)`。
- `PropertyViewModel.commonTemplates` 包含：
  - `svn:ignore` 默认 `""`，目录 true，文件 false。
  - `svn:eol-style` 默认 `"native"`，目录 false，文件 true。
  - `svn:executable` 默认 `"*"`，目录 false，文件 true。
  - `svn:needs-lock` 默认 `"*"`，目录 false，文件 true。
- `load()` 查询属性。
- `save(name:value:)` trim name，空名报 `emptyPropertyName`；成功后刷新属性。
- `delete(name:)` trim name，空名报 `emptyPropertyName`；成功后刷新属性。
- `extension SvnService: PropertyProviding {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter PropertyViewModelTests
```

预期：3 个 ViewModel 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/PropertyViewModel.swift Tests/MacSvnCoreTests/PropertyViewModelTests.swift
git commit -m "feat: add P4 property view model"
```

## 任务 4：真实 SVN 集成与全量验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写集成测试**

在 `SvnCliBackendIntegrationTests` 新增：

```swift
func testPropertiesSetListGetDeleteOnWorkingCopyFile() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    try await service.setProperty(
        wc: fixture.workingCopy,
        target: "README.txt",
        name: "custom:reviewer",
        value: "杨超"
    )

    let listed = try await service.properties(wc: fixture.workingCopy, target: "README.txt")
    let value = try await service.propertyValue(wc: fixture.workingCopy, target: "README.txt", name: "custom:reviewer")

    XCTAssertTrue(listed.contains(SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")))
    XCTAssertEqual(value?.name, "custom:reviewer")
    XCTAssertEqual(value?.value, "杨超")

    try await service.deleteProperty(wc: fixture.workingCopy, target: "README.txt", name: "custom:reviewer")
    let afterDelete = try await service.properties(wc: fixture.workingCopy, target: "README.txt")

    XCTAssertFalse(afterDelete.contains { $0.name == "custom:reviewer" })
}
```

- [ ] **步骤 2：运行集成测试**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testPropertiesSetListGetDeleteOnWorkingCopyFile
```

预期：PASS。

- [ ] **步骤 3：运行属性目标集**

运行：

```bash
swift test --filter "PropertyXMLParserTests|PropertyViewModelTests|SvnCommandBuilderTests/testProperty|SvnCliBackendTests/testProperty|SvnServiceTests/testProperty|SvnCliBackendIntegrationTests/testPropertiesSetListGetDeleteOnWorkingCopyFile"
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
git add Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift
git commit -m "test: cover P4 property integration"
```

## 自检

- 覆盖 `FR-PR-01` 的核心 versioned properties：查看、读取、设置、删除。
- 覆盖常用模板名称：`svn:ignore`、`svn:eol-style`、`svn:executable`、`svn:needs-lock`。
- 不覆盖 revision properties、recursive properties、属性冲突 UI；这些仍是 P4 后续子切片。
- 不引入外部依赖，不改变现有 status/log/diff/blame 行为。
