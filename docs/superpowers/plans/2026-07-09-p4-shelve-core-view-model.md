# P4 Shelve Core ViewModel 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P4 `FR-EX-02` 的核心数据链路：把选中修改保存为本地 patch 快照并 revert 工作区，支持预览、恢复、删除，并为 revert/merge 前安全快照提供保留最近 20 份的底座。

**架构：** 新增 `ShelveSnapshot` 模型和 `ShelveStore` 持久化 `shelves/index.json` 与 patch 文件；新增 `ShelveService` 组合 `SvnService.diff`、`SvnService.revert`、新增 `SvnService.applyPatch` 完成 shelve/restore；新增 `ShelveViewModel` 负责加载列表、搁置、恢复、删除和错误状态。恢复使用 `svn patch --strip 0 --reverse-diff` 以外的普通 `svn patch` 路径，避免直接调用 shell patch 并复用 SVN 对新增/删除/属性差异的处理。

**技术栈：** Swift 6.1、Foundation 文件持久化、Observation、XCTest concurrency、现有 `SvnBackend` / `SvnService` / `PersistenceStore` / `ProcessRunner`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  增加 `ShelveSnapshot`、`ShelveKind`、`ShelveListFile`。
- 创建：`Sources/MacSvnCore/Services/ShelveStore.swift`
  管理 `shelves/index.json`、patch 文件写读删、最近 20 份安全快照裁剪。
- 创建：`Sources/MacSvnCore/Services/ShelveService.swift`
  组合 diff/revert/applyPatch，提供 `shelve`、`createSafetySnapshot`、`restore`、`delete`、`preview`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `patch(patchFile:)` 命令构造。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  新增 `applyPatch(wc:patchFile:)` 协议方法。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 `svn patch --non-interactive <patchFile>`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  增加写锁保护的 `applyPatch`，后续 `ShelveService.restore` 使用。
- 创建：`Sources/MacSvnCore/ViewModels/ShelveViewModel.swift`
  暴露可绑定状态、snapshot 列表、preview 文本、restore/delete/shelve 操作。
- 创建：`Tests/MacSvnCoreTests/ShelveStoreTests.swift`
- 创建：`Tests/MacSvnCoreTests/ShelveServiceTests.swift`
- 创建：`Tests/MacSvnCoreTests/ShelveViewModelTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

## 任务 1：Shelve 模型与本地存储

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/ShelveStore.swift`
- 创建：`Tests/MacSvnCoreTests/ShelveStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `ShelveStoreTests`，覆盖普通 shelve 写入、patch 预览、删除，以及安全快照裁剪：

```swift
func testCreateSnapshotPersistsMetadataAndPatchText() async throws {
    let root = try makeTemporaryDirectory()
    let store = ShelveStore(rootDirectory: root)

    let snapshot = try await store.createSnapshot(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        name: "修复登录",
        paths: ["Sources/App.swift"],
        patchText: "Index: Sources/App.swift\n+new\n",
        kind: .manual
    )

    XCTAssertEqual(snapshot.name, "修复登录")
    XCTAssertEqual(snapshot.paths, ["Sources/App.swift"])
    XCTAssertEqual(snapshot.kind, .manual)
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.patchRelativePath).path))
    XCTAssertEqual(try await store.preview(snapshot), "Index: Sources/App.swift\n+new\n")
    XCTAssertEqual(try await store.load(), [snapshot])
}

func testDeleteSnapshotRemovesMetadataAndPatchFile() async throws {
    let root = try makeTemporaryDirectory()
    let store = ShelveStore(rootDirectory: root)
    let snapshot = try await store.createSnapshot(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        name: "temp",
        paths: ["a.txt"],
        patchText: "patch",
        kind: .manual
    )

    try await store.delete(snapshot)

    XCTAssertEqual(try await store.load(), [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.patchRelativePath).path))
}

func testSafetySnapshotsKeepMostRecentTwenty() async throws {
    let root = try makeTemporaryDirectory()
    let store = ShelveStore(rootDirectory: root)

    for index in 0..<22 {
        _ = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "safety-\(index)",
            paths: ["a.txt"],
            patchText: "patch-\(index)",
            kind: .safety
        )
    }

    let snapshots = try await store.load()
    let safety = snapshots.filter { $0.kind == .safety }
    XCTAssertEqual(safety.count, 20)
    XCTAssertFalse(safety.contains { $0.name == "safety-0" })
    XCTAssertFalse(safety.contains { $0.name == "safety-1" })
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter ShelveStoreTests
```

预期：编译失败，提示 `ShelveStore`、`ShelveSnapshot` 或 `ShelveKind` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

```swift
public enum ShelveKind: String, Codable, Equatable, Sendable {
    case manual
    case safety
}

public struct ShelveSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let wcPath: String
    public let name: String
    public let paths: [String]
    public let patchRelativePath: String
    public let createdAt: Date
    public let kind: ShelveKind
}

public struct ShelveListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var snapshots: [ShelveSnapshot]
}
```

`ShelveStore` 使用 `PersistenceStore<ShelveListFile>` 读写 `index.json`，patch 文件保存到 `manual/<uuid>.patch` 或 `safety/<uuid>.patch`。每次写入 safety 后按 `createdAt` 降序保留 20 份 safety，并删除被裁剪的 patch 文件；manual snapshot 不参与裁剪。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter ShelveStoreTests
```

预期：`ShelveStoreTests` 全部 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Services/ShelveStore.swift Tests/MacSvnCoreTests/ShelveStoreTests.swift docs/superpowers/plans/2026-07-09-p4-shelve-core-view-model.md
git commit -m "feat: add P4 shelve snapshot store"
```

## 任务 2：svn patch 命令、Backend 与 Service

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCommandBuilderTests` 增加：

```swift
func testPatchUsesNonInteractiveAndPatchFile() {
    let command = SvnCommandBuilder.patch(patchFile: "/tmp/shelf.patch")
    XCTAssertEqual(command.arguments, ["patch", "--non-interactive", "/tmp/shelf.patch"])
}
```

在 `SvnCliBackendTests` 增加：

```swift
func testApplyPatchRunsPatchInWorkingCopy() async throws {
    let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
    let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

    try await backend.applyPatch(wc: URL(fileURLWithPath: "/tmp/wc"), patchFile: URL(fileURLWithPath: "/tmp/shelf.patch"))

    XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    XCTAssertEqual(runner.calls.single?.arguments, ["patch", "--non-interactive", "/tmp/shelf.patch"])
}
```

在 `SvnServiceTests` 增加写锁转发测试：`applyPatch(wc:patchFile:)` 调用 backend，并且与其它写操作共享同一 WC 锁。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter SvnCommandBuilderTests/testPatchUsesNonInteractiveAndPatchFile
swift test --filter SvnCliBackendTests/testApplyPatchRunsPatchInWorkingCopy
swift test --filter SvnServiceTests/testApplyPatchUsesBackendWriteOperation
```

预期：编译失败或测试失败，提示 `patch` / `applyPatch` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `SvnCommandBuilder.patch(patchFile:)`，在 `SvnBackend` 增加：

```swift
func applyPatch(wc: URL, patchFile: URL) async throws
```

`SvnCliBackend.applyPatch` 在 `wc.path` 作为 currentDirectory 下运行命令；`SvnService.applyPatch` 使用 `withWriteLock(wc:operation:"patch")` 包裹 backend 调用。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testPatch|SvnCliBackendTests/testApplyPatch|SvnServiceTests/testApplyPatch"
```

预期：目标测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Backend Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift
git commit -m "feat: add svn patch backend flow"
```

## 任务 3：ShelveService 搁置、恢复、删除与安全快照

**文件：**
- 创建：`Sources/MacSvnCore/Services/ShelveService.swift`
- 创建：`Tests/MacSvnCoreTests/ShelveServiceTests.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `ShelveServiceTests`：

```swift
func testShelveCreatesPatchSnapshotThenRevertsSelectedPaths() async throws {
    let store = ShelveStore(rootDirectory: try makeTemporaryDirectory())
    let svn = FakeShelveSvnProvider()
    svn.diffResults["a.txt"] = "Index: a.txt\n+new\n"
    let service = ShelveService(store: store, svn: svn)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let snapshot = try await service.shelve(wc: wc, name: "work in progress", paths: ["a.txt"])

    XCTAssertEqual(snapshot.kind, .manual)
    XCTAssertEqual(try await store.preview(snapshot), "Index: a.txt\n+new\n")
    XCTAssertEqual(await svn.revertCalls, [ShelveRevertCall(wc: wc, paths: ["a.txt"], recursive: true)])
}

func testShelveRejectsEmptyDiffBeforeRevert() async throws {
    let store = ShelveStore(rootDirectory: try makeTemporaryDirectory())
    let svn = FakeShelveSvnProvider()
    svn.diffResults["a.txt"] = ""
    let service = ShelveService(store: store, svn: svn)

    await XCTAssertThrowsErrorAsync(try await service.shelve(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        name: "empty",
        paths: ["a.txt"]
    ))

    XCTAssertTrue(await svn.revertCalls.isEmpty)
}

func testRestoreAppliesPatchAndOptionallyDeletesManualSnapshot() async throws {
    let store = ShelveStore(rootDirectory: try makeTemporaryDirectory())
    let snapshot = try await store.createSnapshot(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        name: "saved",
        paths: ["a.txt"],
        patchText: "Index: a.txt\n+new\n",
        kind: .manual
    )
    let svn = FakeShelveSvnProvider()
    let service = ShelveService(store: store, svn: svn)

    try await service.restore(snapshot, deleteAfterRestore: true)

    XCTAssertEqual(await svn.patchCalls.map(\.patchFile.lastPathComponent), [snapshot.patchFileName])
    XCTAssertEqual(try await store.load(), [])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter ShelveServiceTests
```

预期：编译失败，提示 `ShelveService` 和测试 fake 协议未定义。

- [ ] **步骤 3：编写最少实现代码**

定义：

```swift
public protocol ShelveSvnProviding: Sendable {
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func applyPatch(wc: URL, patchFile: URL) async throws
}
```

`SvnService` 遵循 `ShelveSvnProviding`。`ShelveService.shelve` 对每个 path 调 `diff`，拼接非空 patch；patch 全为空时抛 `ShelveServiceError.emptyPatch`；保存 snapshot 后调用 `revert(... recursive: true)`。`restore` 用 snapshot 的 `wcPath` 和 patch 文件调用 `applyPatch`，`deleteAfterRestore` 为 true 时删除 snapshot。`createSafetySnapshot` 只保存 patch，不 revert。

- [ ] **步骤 4：编写真实 SVN 集成测试**

在 `SvnCliBackendIntegrationTests` 增加：

```swift
func testShelveRevertsWorkingCopyAndRestoreAppliesPatch() async throws {
    let fixture = try makeFixture()
    let backend = SvnCliBackend(svnExecutable: fixture.svn, runner: ProcessRunner())
    let service = SvnService(backend: backend)
    let store = ShelveStore(rootDirectory: fixture.root.appendingPathComponent("shelves"))
    let shelve = ShelveService(store: store, svn: service)
    let file = fixture.wcA.appendingPathComponent("trunk/README.txt")
    try "changed through shelve\n".write(to: file, atomically: true, encoding: .utf8)

    let snapshot = try await shelve.shelve(wc: fixture.wcA.appendingPathComponent("trunk"), name: "readme change", paths: ["README.txt"])
    XCTAssertFalse(try String(contentsOf: file).contains("changed through shelve"))

    try await shelve.restore(snapshot, deleteAfterRestore: false)

    XCTAssertTrue(try String(contentsOf: file).contains("changed through shelve"))
}
```

- [ ] **步骤 5：运行目标测试验证通过**

运行：

```bash
swift test --filter ShelveServiceTests
swift test --filter SvnCliBackendIntegrationTests/testShelveRevertsWorkingCopyAndRestoreAppliesPatch
```

预期：目标与集成测试 PASS。

- [ ] **步骤 6：Commit**

```bash
git add Sources/MacSvnCore/Services/ShelveService.swift Tests/MacSvnCoreTests/ShelveServiceTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift
git commit -m "feat: add P4 shelve service flow"
```

## 任务 4：ShelveViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/ShelveViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/ShelveViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `ShelveViewModelTests`：

```swift
@MainActor
func testLoadShelvePreviewRestoreAndDeleteStateFlow() async throws {
    let provider = FakeShelveProvider()
    let snapshot = shelveSnapshot(name: "saved")
    provider.snapshots = [snapshot]
    provider.previewText = "Index: a.txt\n+new\n"
    let viewModel = ShelveViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        shelveProvider: provider
    )

    await viewModel.load()
    await viewModel.preview(snapshot)
    await viewModel.restore(snapshot, deleteAfterRestore: true)
    await viewModel.delete(snapshot)

    XCTAssertEqual(viewModel.snapshots, [snapshot])
    XCTAssertEqual(viewModel.previewText, "Index: a.txt\n+new\n")
    XCTAssertEqual(await provider.restoreCalls, [ShelveRestoreCall(snapshot: snapshot, deleteAfterRestore: true)])
    XCTAssertEqual(await provider.deleteCalls, [snapshot])
}

@MainActor
func testShelveRejectsEmptyNameAndPathsBeforeProviderCall() async {
    let provider = FakeShelveProvider()
    let viewModel = ShelveViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        shelveProvider: provider
    )

    await viewModel.shelve(name: " ", paths: ["a.txt"])
    XCTAssertEqual(viewModel.state, .error("emptyShelveName"))

    await viewModel.shelve(name: "saved", paths: [])
    XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))

    XCTAssertTrue(await provider.shelveCalls.isEmpty)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter ShelveViewModelTests
```

预期：编译失败，提示 `ShelveViewModel` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `ShelveProviding` 协议与 `ShelveViewState`：`.idle`、`.loading`、`.running(ShelveOperation)`、`.loaded`、`.completed(ShelveOperation)`、`.error(String)`。ViewModel 方法：`load()`、`shelve(name:paths:)`、`createSafetySnapshot(name:paths:)`、`preview(_:)`、`restore(_:deleteAfterRestore:)`、`delete(_:)`。成功的写操作后重新加载 snapshot 列表。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter ShelveViewModelTests
```

预期：ViewModel 测试 PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/ShelveViewModel.swift Tests/MacSvnCoreTests/ShelveViewModelTests.swift
git commit -m "feat: add P4 shelve view model"
```

## 任务 5：全量验证

- [ ] **步骤 1：运行目标测试**

运行：

```bash
swift test --filter "ShelveStoreTests|ShelveServiceTests|ShelveViewModelTests|SvnCommandBuilderTests/testPatch|SvnCliBackendTests/testApplyPatch|SvnServiceTests/testApplyPatch|SvnCliBackendIntegrationTests/testShelve"
```

预期：目标测试全部 PASS。

- [ ] **步骤 2：运行全量测试**

运行：

```bash
swift test
```

预期：全部测试 PASS。

- [ ] **步骤 3：运行空白字符检查**

运行：

```bash
git diff --check
```

预期：无输出，退出码 0。

- [ ] **步骤 4：确认工作区**

运行：

```bash
git status --short --branch
```

预期：工作区干净，位于 `codex/p1-core-scaffold` 或当前功能分支。

## 自检

- 覆盖 `FR-EX-02` 的 Core 范围：手动 shelve、preview、restore、delete、安全快照保留 20 份。
- 不实现 SwiftUI 真实界面；当前仓库仍是 `MacSvnCore` Swift Package，UI shell 属于后续应用 target 切片。
- 不把 safety snapshot 自动接入已有 `revert`/`merge` 按钮确认流；本切片提供 `createSafetySnapshot` 和 ViewModel 方法，下一切片可把它挂到 `WorkingCopyActionsViewModel` / `MergeWizardViewModel`。
- 不调用 shell `patch`；恢复通过 `svn patch`，避免绕过 SVN 对 patch 的语义处理。
