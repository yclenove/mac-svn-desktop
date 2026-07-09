# P3 Conflict Info Resolve 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P3 冲突解决链路的第一块基础设施：从 `svn status --xml` 与 `svn info --xml` 得到冲突列表和 base/mine/theirs 路径，并支持 `svn resolve --accept ...`。

**架构：** 在模型层新增 `ConflictInfo`、`ConflictKind`、`ResolveAccept` 等类型；`InfoXMLParser` 解析 `<conflict>` 与 `<tree-conflict>`；Backend/Service 层新增 `resolve` 写操作；`ConflictService` 组合 status/info/resolve，提供冲突枚举、三方文本加载、写回并 resolve、整文件 mine/theirs resolve。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `ConflictKind`、`TreeConflictDetails`、`ConflictInfo`、`ResolveAccept`，并给 `SvnInfo` 增加 `conflicts: [ConflictInfo]` 默认值。
- 修改：`Sources/MacSvnCore/Parsers/InfoXMLParser.swift`
  解析文本冲突三方文件节点和树冲突属性。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `resolve(path:accept:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `resolve(wc:path:accept:)`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  在 WC 目录执行 `svn resolve --accept ...`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `resolve(wc:path:accept:)`，使用每 WC 写锁。
- 创建：`Sources/MacSvnCore/Services/ConflictService.swift`
  提供 `conflicts(wc:)`、`loadTextConflict(_:)`、`saveResolution(_:mergedText:)`、`resolveWholeFile(_:accept:)`。
- 修改：`Tests/MacSvnCoreTests/InfoXMLParserTests.swift`
  覆盖文本冲突和树冲突 XML。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 resolve 参数。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 resolve backend 在 WC 目录运行。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  覆盖 resolve 写操作转发与 mock 协议。
- 创建：`Tests/MacSvnCoreTests/ConflictServiceTests.swift`
  覆盖冲突枚举、三方文本读取、保存并 resolve、整文件 resolve。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  制造真实文本冲突，验证 `ConflictService.conflicts` 能取得三方文件，并验证 `mine-full` resolve 后 status 不再冲突。

## 任务 1：冲突模型与 info XML 解析

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 修改：`Sources/MacSvnCore/Parsers/InfoXMLParser.swift`
- 修改：`Tests/MacSvnCoreTests/InfoXMLParserTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `InfoXMLParserTests` 中新增：

```swift
func testParsesTextConflictFiles() throws {
    let xml = """
    <info>
      <entry path="README.txt" revision="3" kind="file">
        <url>file:///repo/trunk/README.txt</url>
        <conflict>
          <prev-base-file>README.txt.r1</prev-base-file>
          <prev-wc-file>README.txt.mine</prev-wc-file>
          <cur-base-file>README.txt.r3</cur-base-file>
        </conflict>
      </entry>
    </info>
    """

    let info = try InfoXMLParser.parse(Data(xml.utf8))

    XCTAssertEqual(info.conflicts, [
        ConflictInfo(
            path: "README.txt",
            kind: .text,
            baseFile: "README.txt.r1",
            mineFile: "README.txt.mine",
            theirsFile: "README.txt.r3",
            treeConflict: nil
        )
    ])
}

func testParsesTreeConflictDetails() throws {
    let xml = """
    <info>
      <entry path="src/main.txt" revision="3" kind="file">
        <url>file:///repo/trunk/src/main.txt</url>
        <tree-conflict victim="src/main.txt" kind="file" operation="update" action="delete" reason="edited"/>
      </entry>
    </info>
    """

    let info = try InfoXMLParser.parse(Data(xml.utf8))

    XCTAssertEqual(info.conflicts, [
        ConflictInfo(
            path: "src/main.txt",
            kind: .tree,
            baseFile: nil,
            mineFile: nil,
            theirsFile: nil,
            treeConflict: TreeConflictDetails(operation: "update", action: "delete", reason: "edited")
        )
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter InfoXMLParserTests/testParsesTextConflictFiles`
预期：编译失败，提示 `ConflictInfo` 或 `SvnInfo.conflicts` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `ConflictKind`：`.text`、`.tree`、`.property`、`.unknown`。
- `TreeConflictDetails(operation:action:reason:)`。
- `ConflictInfo(path:kind:baseFile:mineFile:theirsFile:treeConflict:)`。
- `ResolveAccept` 暂定义但本任务不使用：`.working`、`.mineFull`、`.theirsFull`，rawValue 分别为 `working`、`mine-full`、`theirs-full`。
- `SvnInfo` init 增加 `conflicts: [ConflictInfo] = []`。
- `InfoXMLParserDelegate` 收集 `<conflict>` 子节点并在结束时 append `.text`；遇到 `<tree-conflict>` 直接 append `.tree`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter InfoXMLParserTests`
预期：目标测试 PASS。

## 任务 2：resolve 命令、后端和服务

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testResolveUsesAcceptNonInteractiveAndPath() {
    let command = SvnCommandBuilder.resolve(path: "README.txt", accept: .mineFull)

    XCTAssertEqual(command.arguments, [
        "resolve", "--accept", "mine-full", "--non-interactive", "README.txt"
    ])
}
```

在 `SvnCliBackendTests` 中新增：

```swift
func testResolveRunsInWorkingCopy() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    try await backend.resolve(wc: URL(fileURLWithPath: "/tmp/wc"), path: "README.txt", accept: .working)

    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    XCTAssertEqual(runner.calls.single?.arguments, [
        "resolve", "--accept", "working", "--non-interactive", "README.txt"
    ])
}
```

在 `SvnServiceTests` 中新增：

```swift
func testResolveUsesBackendWriteOperation() async throws {
    let backend = MockSvnBackend()
    let service = SvnService(backend: backend)

    try await service.resolve(wc: URL(fileURLWithPath: "/tmp/wc"), path: "README.txt", accept: .theirsFull)

    XCTAssertEqual(backend.calls.map(\.name), ["resolve"])
    XCTAssertEqual(backend.resolveAccepts, [.theirsFull])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter "SvnCommandBuilderTests/testResolve|SvnCliBackendTests/testResolve|SvnServiceTests/testResolve"`
预期：编译失败，提示 `resolve` API 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `SvnCommandBuilder.resolve(path:accept:)`。
- `SvnBackend.resolve(wc:path:accept:)`。
- `SvnCliBackend.resolve(...)`，无认证参数，`currentDirectory: wc.path`。
- `SvnService.resolve(...)`，用 `withWriteLock(wc: operation: "resolve")`。
- 更新 `MockSvnBackend` 记录 resolve 调用和 accept。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter "SvnCommandBuilderTests/testResolve|SvnCliBackendTests/testResolve|SvnServiceTests/testResolve"`
预期：目标测试 PASS。

## 任务 3：ConflictService 枚举、读取与 resolve

**文件：**
- 创建：`Sources/MacSvnCore/Services/ConflictService.swift`
- 创建：`Tests/MacSvnCoreTests/ConflictServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `ConflictServiceTests`，覆盖：

```swift
func testConflictsLoadsInfoForConflictedStatusesAndAbsolutizesSideFiles() async throws {
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeConflictProvider(
        statuses: [
            FileStatus(path: "README.txt", itemStatus: .conflicted, revision: Revision(3), isTreeConflict: false)
        ],
        infos: [
            "README.txt": SvnInfo(
                path: "README.txt",
                url: "file:///repo/trunk/README.txt",
                repositoryRoot: "file:///repo",
                revision: Revision(3),
                kind: "file",
                conflicts: [
                    ConflictInfo(
                        path: "README.txt",
                        kind: .text,
                        baseFile: "README.txt.r1",
                        mineFile: "/tmp/wc/README.txt.mine",
                        theirsFile: "README.txt.r3",
                        treeConflict: nil
                    )
                ]
            )
        ]
    )
    let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)

    let conflicts = try await service.conflicts(wc: wc)

    XCTAssertEqual(conflicts, [
        ConflictInfo(
            path: "README.txt",
            kind: .text,
            baseFile: "/tmp/wc/README.txt.r1",
            mineFile: "/tmp/wc/README.txt.mine",
            theirsFile: "/tmp/wc/README.txt.r3",
            treeConflict: nil
        )
    ])
}

func testLoadTextConflictReadsBaseMineAndTheirs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "base\n".write(to: root.appendingPathComponent("base.txt"), atomically: true, encoding: .utf8)
    try "mine\n".write(to: root.appendingPathComponent("mine.txt"), atomically: true, encoding: .utf8)
    try "theirs\n".write(to: root.appendingPathComponent("theirs.txt"), atomically: true, encoding: .utf8)
    let conflict = ConflictInfo(path: "README.txt", kind: .text, baseFile: root.appendingPathComponent("base.txt").path, mineFile: root.appendingPathComponent("mine.txt").path, theirsFile: root.appendingPathComponent("theirs.txt").path, treeConflict: nil)
    let provider = FakeConflictProvider()
    let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)

    let text = try await service.loadTextConflict(conflict)

    XCTAssertEqual(text.base, "base\n")
    XCTAssertEqual(text.mine, "mine\n")
    XCTAssertEqual(text.theirs, "theirs\n")
}
```

Add tests for `saveResolution` and `resolveWholeFile`:
- `saveResolution` writes merged text to `wc/path` and records `.working`.
- `resolveWholeFile` records `.mineFull`.

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter ConflictServiceTests`
预期：编译失败，提示 `ConflictService` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `ConflictStatusProviding`、`ConflictInfoProviding`、`ConflictResolving` 协议。
- `ConflictService.conflicts(wc:)`：筛选 `.conflicted` 或 `isTreeConflict`；逐项调用 `info(wc:target:)`；把三方文件路径转为绝对路径。
- `loadTextConflict(_:)`：读取 base/mine/theirs UTF-8 文本，缺少三方路径时抛 `SvnError.parse`。
- `saveResolution(_:wc:mergedText:)`：写 `path.tmp-macsvn`，原子替换工作文件，然后 `resolve(..., .working)`。
- `resolveWholeFile(_:wc:accept:)`：直接调用 resolve。
- `extension SvnService: ConflictStatusProviding, ConflictInfoProviding, ConflictResolving {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter ConflictServiceTests`
预期：目标测试 PASS。

## 任务 4：真实 SVN 冲突枚举和整文件 resolve

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的测试**

新增：

```swift
func testConflictServiceListsTextConflictAndResolveMineFull() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let otherWC = fixture.root.appendingPathComponent("wc-other", isDirectory: true)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)
    try "mine change\n".write(to: fixture.workingCopy.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    try "theirs change\n".write(to: otherWC.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    _ = try await service.commit(wc: otherWC, paths: ["README.txt"], message: "theirs change", auth: nil)

    _ = try await service.update(wc: fixture.workingCopy)
    let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
    let conflicts = try await conflictService.conflicts(wc: fixture.workingCopy)

    XCTAssertEqual(conflicts.first?.path, "README.txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.baseFile ?? ""))
    XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.mineFile ?? ""))
    XCTAssertTrue(FileManager.default.fileExists(atPath: conflicts.first?.theirsFile ?? ""))

    try await conflictService.resolveWholeFile(conflicts[0], wc: fixture.workingCopy, accept: .mineFull)
    let statuses = try await service.status(wc: fixture.workingCopy)
    XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testConflictServiceListsTextConflictAndResolveMineFull`
预期：实现前编译失败或 `ConflictService` 缺失。

- [ ] **步骤 3：运行目标测试验证通过**

运行：`swift test --filter "InfoXMLParserTests/testParsesTextConflictFiles|SvnCommandBuilderTests/testResolve|SvnCliBackendTests/testResolve|SvnServiceTests/testResolve|ConflictServiceTests|SvnCliBackendIntegrationTests/testConflictServiceListsTextConflictAndResolveMineFull"`
预期：目标测试 PASS。

- [ ] **步骤 4：全量验证与提交**

运行：
- `swift test`
- `git diff --check`
- `git add docs/superpowers/plans/2026-07-09-p3-conflict-info-resolve.md Sources/MacSvnCore Tests/MacSvnCoreTests`
- `git diff --cached --check`
- `git commit -m "feat: add P3 conflict info resolve core"`
- `git diff HEAD^ HEAD --check`
- `git status --short --branch`

预期：测试 0 failures，空白检查无输出，提交后工作区干净。
