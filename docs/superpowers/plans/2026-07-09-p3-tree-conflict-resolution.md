# P3 Tree Conflict Resolution 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-CF-06 的 Core 非 UI 部分：树冲突展示可读详情，并提供“保留本地 / 接受远端”两种处理动作，最终调用 `svn resolve --accept mine-conflict/theirs-conflict`。

**架构：** 扩展 `ResolveAccept` 支持 svn 1.14 `mine-conflict` 与 `theirs-conflict`；在 `ConflictService` 中新增 `resolveTreeConflict(_:wc:resolution:)`，把领域语义 `TreeConflictResolution.keepLocal/acceptRemote` 映射到底层 accept 值。新增 `TreeConflictViewModel` 作为后续 SwiftUI 绑定层，只负责展示详情、状态、调用 resolve，不直接接触后端。

**技术栈：** Swift 6.1、Observation、XCTest concurrency、svn CLI 1.14。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `ResolveAccept.mineConflict` / `ResolveAccept.theirsConflict` 和 `TreeConflictResolution`。
- 修改：`Sources/MacSvnCore/Services/ConflictService.swift`
  新增 `resolveTreeConflict(_:wc:resolution:)`，只接受 `.tree` 冲突。
- 创建：`Sources/MacSvnCore/ViewModels/TreeConflictViewModel.swift`
  定义 `TreeConflictResolving`、`TreeConflictViewState`、`TreeConflictViewModel`，并让 `ConflictService` 遵循 `TreeConflictResolving`。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 `mine-conflict` / `theirs-conflict` 参数构造。
- 修改：`Tests/MacSvnCoreTests/ConflictServiceTests.swift`
  覆盖 tree conflict 语义映射、非树冲突阻断。
- 创建：`Tests/MacSvnCoreTests/TreeConflictViewModelTests.swift`
  覆盖详情展示、keep local / accept remote 调用、错误状态。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实树冲突的 keep local 与 accept remote 两条分支。
- 创建：`docs/superpowers/plans/2026-07-09-p3-tree-conflict-resolution.md`
  记录此切片计划。

## 任务 1：ResolveAccept 与 ConflictService 语义方法

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 修改：`Sources/MacSvnCore/Services/ConflictService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/ConflictServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCommandBuilderTests` 中新增：

```swift
func testResolveCanAcceptTreeConflictSides() {
    XCTAssertEqual(
        SvnCommandBuilder.resolve(path: "tree.txt", accept: .mineConflict).arguments,
        ["resolve", "--accept", "mine-conflict", "--non-interactive", "tree.txt"]
    )
    XCTAssertEqual(
        SvnCommandBuilder.resolve(path: "tree.txt", accept: .theirsConflict).arguments,
        ["resolve", "--accept", "theirs-conflict", "--non-interactive", "tree.txt"]
    )
}
```

在 `ConflictServiceTests` 中新增：

```swift
func testResolveTreeConflictMapsKeepLocalAndAcceptRemoteToSvnAcceptValues() async throws {
    let wc = URL(fileURLWithPath: "/tmp/wc")
    let provider = FakeConflictProvider()
    let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)
    let conflict = ConflictInfo(
        path: "tree.txt",
        kind: .tree,
        baseFile: nil,
        mineFile: nil,
        theirsFile: nil,
        treeConflict: TreeConflictDetails(operation: "update", action: "delete", reason: "edited")
    )

    try await service.resolveTreeConflict(conflict, wc: wc, resolution: .keepLocal)
    try await service.resolveTreeConflict(conflict, wc: wc, resolution: .acceptRemote)
    let resolves = await provider.recordedResolves()

    XCTAssertEqual(resolves, [
        ResolveCall(wc: wc, path: "tree.txt", accept: .mineConflict),
        ResolveCall(wc: wc, path: "tree.txt", accept: .theirsConflict)
    ])
}

func testResolveTreeConflictRejectsNonTreeConflict() async {
    let provider = FakeConflictProvider()
    let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)
    let conflict = ConflictInfo(path: "README.txt", kind: .text, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)

    do {
        try await service.resolveTreeConflict(conflict, wc: URL(fileURLWithPath: "/tmp/wc"), resolution: .keepLocal)
        XCTFail("Expected parse error")
    } catch let error as SvnError {
        XCTAssertEqual(error, .parse(detail: "Expected tree conflict for README.txt."))
    } catch {
        XCTFail("Expected SvnError, got \(error)")
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testResolveCanAcceptTreeConflictSides|ConflictServiceTests/testResolveTreeConflict"
```

预期：编译失败，提示 `mineConflict`、`theirsConflict`、`TreeConflictResolution` 或 `resolveTreeConflict` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：

```swift
public enum ResolveAccept: String, Equatable, Sendable {
    case working
    case mineConflict = "mine-conflict"
    case theirsConflict = "theirs-conflict"
    case mineFull = "mine-full"
    case theirsFull = "theirs-full"
}

public enum TreeConflictResolution: Equatable, Sendable {
    case keepLocal
    case acceptRemote

    public var accept: ResolveAccept {
        switch self {
        case .keepLocal:
            return .mineConflict
        case .acceptRemote:
            return .theirsConflict
        }
    }
}
```

`ConflictService.resolveTreeConflict`：
- 如果 `conflict.kind != .tree`，抛 `SvnError.parse(detail: "Expected tree conflict for \(conflict.path).")`；
- 否则调用 `resolveProvider.resolve(wc:path:accept:)`，accept 使用 `resolution.accept`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testResolveCanAcceptTreeConflictSides|ConflictServiceTests/testResolveTreeConflict"
```

预期：目标测试 PASS。

## 任务 2：TreeConflictViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/TreeConflictViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/TreeConflictViewModelTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `TreeConflictViewModelTests`：

```swift
import XCTest
@testable import MacSvnCore

final class TreeConflictViewModelTests: XCTestCase {
    @MainActor
    func testTreeConflictDetailsExposePathAndReasonParts() {
        let conflict = treeConflict()
        let provider = FakeTreeConflictResolver()
        let viewModel = TreeConflictViewModel(conflict: conflict, workingCopy: URL(fileURLWithPath: "/tmp/wc"), resolver: provider)

        XCTAssertEqual(viewModel.path, "tree.txt")
        XCTAssertEqual(viewModel.operation, "update")
        XCTAssertEqual(viewModel.action, "delete")
        XCTAssertEqual(viewModel.reason, "edited")
    }

    @MainActor
    func testKeepLocalAndAcceptRemoteCallResolverAndStoreState() async {
        let conflict = treeConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeTreeConflictResolver()
        let viewModel = TreeConflictViewModel(conflict: conflict, workingCopy: wc, resolver: provider)

        await viewModel.resolve(.keepLocal)
        await viewModel.resolve(.acceptRemote)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .resolved(.acceptRemote))
        XCTAssertEqual(calls, [
            TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: .keepLocal),
            TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: .acceptRemote)
        ])
    }

    @MainActor
    func testResolveFailureStoresError() async {
        let provider = FakeTreeConflictResolver(error: SvnError.network(detail: "offline"))
        let viewModel = TreeConflictViewModel(
            conflict: treeConflict(),
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            resolver: provider
        )

        await viewModel.resolve(.keepLocal)

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    }
}

private func treeConflict() -> ConflictInfo {
    ConflictInfo(
        path: "tree.txt",
        kind: .tree,
        baseFile: nil,
        mineFile: nil,
        theirsFile: nil,
        treeConflict: TreeConflictDetails(operation: "update", action: "delete", reason: "edited")
    )
}
```

测试 fake：

```swift
private struct TreeConflictResolveCall: Equatable, Sendable {
    let conflict: ConflictInfo
    let wc: URL
    let resolution: TreeConflictResolution
}

private actor FakeTreeConflictResolver: TreeConflictResolving {
    let error: Error?
    private var calls: [TreeConflictResolveCall] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func resolveTreeConflict(_ conflict: ConflictInfo, wc: URL, resolution: TreeConflictResolution) async throws {
        if let error {
            throw error
        }
        calls.append(TreeConflictResolveCall(conflict: conflict, wc: wc, resolution: resolution))
    }

    func recordedCalls() -> [TreeConflictResolveCall] {
        calls
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter TreeConflictViewModelTests
```

预期：编译失败，提示 `TreeConflictViewModel` 或 `TreeConflictResolving` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `TreeConflictResolving` 协议，签名与 `ConflictService.resolveTreeConflict` 一致；
- `TreeConflictViewState`: `.idle/.resolving/.resolved(TreeConflictResolution)/.error(String)`；
- `TreeConflictViewModel` 属性：`state`、`path`、`operation`、`action`、`reason`；
- `resolve(_:)` 设置 `.resolving`，调用 resolver，成功 `.resolved(resolution)`，失败 `.error(String(describing: error))`；
- `extension ConflictService: TreeConflictResolving {}`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter TreeConflictViewModelTests
```

预期：目标测试 PASS。

## 任务 3：真实 SVN 树冲突集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCliBackendIntegrationTests` 中新增：

```swift
func testTreeConflictKeepLocalResolvesAndKeepsWorkingFile() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
    let conflict = try await makeLocalEditRemoteDeleteTreeConflict(fixture: fixture, service: service)

    try await conflictService.resolveTreeConflict(
        conflict,
        wc: fixture.workingCopy,
        resolution: .keepLocal
    )

    let statuses = try await service.status(wc: fixture.workingCopy)
    XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
}

func testTreeConflictAcceptRemoteResolvesAndRemovesWorkingFile() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
    let conflict = try await makeLocalEditRemoteDeleteTreeConflict(fixture: fixture, service: service)

    try await conflictService.resolveTreeConflict(
        conflict,
        wc: fixture.workingCopy,
        resolution: .acceptRemote
    )

    let statuses = try await service.status(wc: fixture.workingCopy)
    XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workingCopy.appendingPathComponent("README.txt").path))
}
```

在测试类末尾、既有 `lines(_:)` helper 附近新增：

```swift
private func makeLocalEditRemoteDeleteTreeConflict(
    fixture: SvnIntegrationFixture,
    service: SvnService
) async throws -> ConflictInfo {
    let otherWC = fixture.root.appendingPathComponent("wc-tree-other-\(UUID().uuidString)", isDirectory: true)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)
    try "local edit before remote delete\n".write(
        to: fixture.workingCopy.appendingPathComponent("README.txt"),
        atomically: true,
        encoding: .utf8
    )
    try await fixture.backend.delete(wc: otherWC, paths: ["README.txt"])
    _ = try await service.commit(
        wc: otherWC,
        paths: ["README.txt"],
        message: "delete readme remotely",
        auth: nil
    )
    _ = try await service.update(wc: fixture.workingCopy)

    let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
    let conflicts = try await conflictService.conflicts(wc: fixture.workingCopy)
    return try XCTUnwrap(conflicts.first { $0.kind == .tree && $0.path == "README.txt" })
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "SvnCliBackendIntegrationTests/testTreeConflict"
```

预期：实现前编译失败；实现错误时真实 svn resolve 断言失败。

- [ ] **步骤 3：编写最少实现代码**

如果任务 1 的 accept 映射正确，此任务通常只需要补集成测试。若真实 svn 对某一类树冲突无法用自动 accept 处理，保留失败输出并把该场景收窄到 svn 支持的自动 resolve 形式，不扩大为手动文件系统修复。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "SvnCommandBuilderTests/testResolveCanAcceptTreeConflictSides|ConflictServiceTests/testResolveTreeConflict|TreeConflictViewModelTests|SvnCliBackendIntegrationTests/testTreeConflict"
```

预期：目标测试 PASS。

## 任务 4：全量验证与提交

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行验证**

运行：

```bash
swift test
git diff --check
```

预期：全量测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

运行：

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Services/ConflictService.swift Sources/MacSvnCore/ViewModels/TreeConflictViewModel.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/ConflictServiceTests.swift Tests/MacSvnCoreTests/TreeConflictViewModelTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p3-tree-conflict-resolution.md
git diff --cached --check
git commit -m "feat: add P3 tree conflict resolution"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：暂存区检查无输出，提交后补丁检查无输出，工作区干净。
