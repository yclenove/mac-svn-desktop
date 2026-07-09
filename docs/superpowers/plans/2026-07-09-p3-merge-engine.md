# P3 Merge Engine 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P3 内置三路合并的纯算法底座：两路 diff、三路 merge3、冲突块模型与 resolution 输出，覆盖 `docs/05-test-plan.md` 的 TC-ME-01~09，并打通 TC-IT-05 的真实 SVN 冲突 resolve/commit 闭环。

**架构：** 新增 `MergeEngine` 纯函数模块，不依赖 UI、文件系统或 svn 进程；输入为 Base/Mine/Theirs 行数组，输出 `MergeBlock.stable` 与 `MergeBlock.conflict`。算法先从 Base 到 Mine/Theirs 分别计算 line diff 变化区间，再按 Base 行号合并重叠或相邻区间；单方修改自动采纳，双方相同修改自动采纳，双方不同修改保守地产生冲突。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest、Foundation、Subversion CLI 集成测试夹具。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/MergeEngine.swift`
  定义 `DiffEdit`、`MergeBlock`、`ConflictHunk` 与 `MergeEngine.diff` / `MergeEngine.merge3` / `MergeEngine.mergedLines`。
- 创建：`Tests/MacSvnCoreTests/MergeEngineTests.swift`
  覆盖 TC-ME-01~09：单方修改、双方不同区域、同一区域冲突、相同修改、删改冲突、相邻区间归并、空文件/单行边界、resolution 应用。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  新增 TC-IT-05：制造真实文本冲突，通过 `ConflictService` 读取三方文本，使用 `MergeEngine` 生成冲突块、保存 resolution、resolve 并提交。
- 创建：`docs/superpowers/plans/2026-07-09-p3-merge-engine.md`
  记录此切片计划。

## 任务 1：DiffEdit 与两路 diff 红绿循环

**文件：**
- 创建：`Sources/MacSvnCore/Services/MergeEngine.swift`
- 创建：`Tests/MacSvnCoreTests/MergeEngineTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `Tests/MacSvnCoreTests/MergeEngineTests.swift`，先覆盖 diff 的公开 API：

```swift
import XCTest
@testable import MacSvnCore

final class MergeEngineTests: XCTestCase {
    func testDiffProducesEqualDeleteAndInsertEdits() {
        let edits = MergeEngine.diff(lines("a\nb\nc"), lines("a\nB\nc\nnew"))

        XCTAssertEqual(edits, [
            .equal("a"),
            .delete("b"),
            .insert("B"),
            .equal("c"),
            .insert("new")
        ])
    }

    private func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast(text.hasSuffix("\n") ? 1 : 0)
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter MergeEngineTests/testDiffProducesEqualDeleteAndInsertEdits
```

预期：编译失败，提示 `MergeEngine` 或 `DiffEdit` 未定义。

- [ ] **步骤 3：编写最少实现代码**

在 `Sources/MacSvnCore/Services/MergeEngine.swift` 中实现：

```swift
public enum DiffEdit: Equatable, Sendable {
    case equal(String)
    case delete(String)
    case insert(String)
}

public enum MergeEngine {
    public static func diff(_ a: [Substring], _ b: [Substring]) -> [DiffEdit] {
        // 使用 LCS 表生成稳定的最短编辑脚本；后续 merge3 复用同一基础。
    }
}
```

实现要求：
- 输入行统一转 `String`；
- LCS 回溯时相等行输出 `.equal`；
- Base 独有行输出 `.delete`；
- 目标独有行输出 `.insert`；
- 输出顺序必须保持文本顺序。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEngineTests/testDiffProducesEqualDeleteAndInsertEdits
```

预期：目标测试 PASS。

## 任务 2：merge3 自动采纳与冲突块

**文件：**
- 修改：`Sources/MacSvnCore/Services/MergeEngine.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEngineTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEngineTests` 中新增 TC-ME-01~06：

```swift
func testMerge3AutoAcceptsMineOnlyChange() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nB\nc"),
        theirs: lines("a\nb\nc")
    )

    XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
}

func testMerge3AutoAcceptsTheirsOnlyChange() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nb\nc"),
        theirs: lines("a\nB\nc")
    )

    XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
}

func testMerge3AutoAcceptsDifferentRegionsFromBothSides() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nB\nc"),
        theirs: lines("a\nb\nC")
    )

    XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "C"])])
}

func testMerge3CreatesConflictForDifferentChangesOnSameLine() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nmine\nc"),
        theirs: lines("a\ntheirs\nc")
    )

    XCTAssertEqual(blocks, [
        .stable(lines: ["a"]),
        .conflict(ConflictHunk(baseLines: ["b"], mineLines: ["mine"], theirsLines: ["theirs"])),
        .stable(lines: ["c"])
    ])
}

func testMerge3AutoAcceptsIdenticalChangesFromBothSides() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nB\nc"),
        theirs: lines("a\nB\nc")
    )

    XCTAssertEqual(blocks, [.stable(lines: ["a", "B", "c"])])
}

func testMerge3CreatesConflictForDeleteVersusModify() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("a\nc"),
        theirs: lines("a\nB\nc")
    )

    XCTAssertEqual(blocks, [
        .stable(lines: ["a"]),
        .conflict(ConflictHunk(baseLines: ["b"], mineLines: [], theirsLines: ["B"])),
        .stable(lines: ["c"])
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEngineTests/testMerge3AutoAccepts|MergeEngineTests/testMerge3CreatesConflict"
```

预期：编译失败或新增测试失败，提示 `MergeBlock` / `ConflictHunk` / `merge3` 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：

```swift
public enum MergeBlock: Equatable, Sendable {
    case stable(lines: [String])
    case conflict(ConflictHunk)
}

public struct ConflictHunk: Equatable, Sendable {
    public let baseLines: [String]
    public let mineLines: [String]
    public let theirsLines: [String]
    public var resolution: Resolution?

    public init(baseLines: [String], mineLines: [String], theirsLines: [String], resolution: Resolution? = nil) {
        self.baseLines = baseLines
        self.mineLines = mineLines
        self.theirsLines = theirsLines
        self.resolution = resolution
    }

    public enum Resolution: Equatable, Sendable {
        case takeMine
        case takeTheirs
        case takeBoth(mineFirst: Bool)
        case manual(lines: [String])
    }
}
```

`merge3` 实现要求：
- 将 Base→Mine 与 Base→Theirs 的 diff 压缩为变化区间；
- 以 Base 行号为坐标合并重叠或相邻区间；
- 单方修改输出 stable；
- 双方修改内容相同输出 stable；
- 双方修改内容不同输出 conflict；
- 相邻 stable 块应合并压缩，避免碎片化。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter "MergeEngineTests/testMerge3AutoAccepts|MergeEngineTests/testMerge3CreatesConflict"
```

预期：目标测试 PASS。

## 任务 3：相邻编辑区间、边界与 resolution 应用

**文件：**
- 修改：`Sources/MacSvnCore/Services/MergeEngine.swift`
- 修改：`Tests/MacSvnCoreTests/MergeEngineTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `MergeEngineTests` 中新增 TC-ME-07~09：

```swift
func testMerge3MergesAdjacentOppositeSideEditsIntoSingleConflict() {
    let blocks = MergeEngine.merge3(
        base: lines("a\nb\nc"),
        mine: lines("A\nb\nc"),
        theirs: lines("a\nB\nc")
    )

    XCTAssertEqual(blocks, [
        .conflict(ConflictHunk(baseLines: ["a", "b"], mineLines: ["A", "b"], theirsLines: ["a", "B"])),
        .stable(lines: ["c"])
    ])
}

func testMerge3HandlesEmptySingleLineAndInsertionOnlyInputs() {
    XCTAssertEqual(MergeEngine.merge3(base: [], mine: [], theirs: []), [])

    XCTAssertEqual(
        MergeEngine.merge3(base: [], mine: lines("mine"), theirs: []),
        [.stable(lines: ["mine"])]
    )

    XCTAssertEqual(
        MergeEngine.merge3(base: lines("base"), mine: lines("mine"), theirs: lines("theirs")),
        [.conflict(ConflictHunk(baseLines: ["base"], mineLines: ["mine"], theirsLines: ["theirs"]))]
    )
}

func testConflictResolutionProducesMergedLinesAndRequiresAllConflictsResolved() {
    let unresolved = ConflictHunk(baseLines: ["base"], mineLines: ["mine"], theirsLines: ["theirs"])
    XCTAssertNil(MergeEngine.mergedLines(from: [.conflict(unresolved)]))

    let blocks: [MergeBlock] = [
        .stable(lines: ["start"]),
        .conflict(ConflictHunk(
            baseLines: ["base"],
            mineLines: ["mine"],
            theirsLines: ["theirs"],
            resolution: .takeBoth(mineFirst: false)
        )),
        .conflict(ConflictHunk(
            baseLines: ["old"],
            mineLines: ["mine-only"],
            theirsLines: ["theirs-only"],
            resolution: .manual(lines: ["manual"])
        )),
        .stable(lines: ["end"])
    ]

    XCTAssertEqual(MergeEngine.mergedLines(from: blocks), [
        "start", "theirs", "mine", "manual", "end"
    ])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "MergeEngineTests/testMerge3MergesAdjacent|MergeEngineTests/testMerge3HandlesEmpty|MergeEngineTests/testConflictResolution"
```

预期：相邻区间、边界或 `mergedLines` 测试失败。

- [ ] **步骤 3：编写最少实现代码**

实现：
- 区间合并规则包含 `next.start <= current.end`，因此相邻双方编辑合并为一个候选块；
- 空输入返回空块；
- 零长度插入区间必须推进变更游标，避免无限循环；
- `ConflictHunk.resolvedLines()` 根据 resolution 返回 mine/theirs/both/manual；
- `MergeEngine.mergedLines(from:)` 拼接 stable 与已 resolved conflict，遇到未解决冲突返回 `nil`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter MergeEngineTests
```

预期：`MergeEngineTests` 全部 PASS。

## 任务 4：真实 SVN 冲突通过 MergeEngine 解决并提交

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败集成测试**

在 `SvnCliBackendIntegrationTests` 中新增：

```swift
func testMergeEngineResolvesTextConflictAndCommitSucceeds() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)
    let conflictService = ConflictService(statusProvider: service, infoProvider: service, resolveProvider: service)
    let otherWC = fixture.root.appendingPathComponent("wc-other-merge-engine", isDirectory: true)

    try await fixture.backend.checkout(url: fixture.trunkURL, to: fixture.workingCopy)
    try await fixture.backend.checkout(url: fixture.trunkURL, to: otherWC)
    try "mine change\n".write(
        to: fixture.workingCopy.appendingPathComponent("README.txt"),
        atomically: true,
        encoding: .utf8
    )
    try "theirs change\n".write(
        to: otherWC.appendingPathComponent("README.txt"),
        atomically: true,
        encoding: .utf8
    )
    _ = try await service.commit(wc: otherWC, paths: ["README.txt"], message: "theirs change", auth: nil)
    _ = try await service.update(wc: fixture.workingCopy)

    let conflict = try XCTUnwrap(await conflictService.conflicts(wc: fixture.workingCopy).first)
    let text = try await conflictService.loadTextConflict(conflict)
    let blocks = MergeEngine.merge3(
        base: lines(text.base),
        mine: lines(text.mine),
        theirs: lines(text.theirs)
    )

    guard case .conflict(let hunk) = blocks.first(where: {
        if case .conflict = $0 { return true }
        return false
    }) else {
        return XCTFail("Expected a text conflict hunk")
    }

    let resolvedBlocks: [MergeBlock] = blocks.map { block in
        guard case .conflict = block else { return block }
        return .conflict(ConflictHunk(
            baseLines: hunk.baseLines,
            mineLines: hunk.mineLines,
            theirsLines: hunk.theirsLines,
            resolution: .takeBoth(mineFirst: true)
        ))
    }
    let merged = try XCTUnwrap(MergeEngine.mergedLines(from: resolvedBlocks))
    try await conflictService.saveResolution(conflict, wc: fixture.workingCopy, mergedText: merged.joined(separator: "\n") + "\n")

    let statuses = try await service.status(wc: fixture.workingCopy)
    XCTAssertFalse(statuses.contains { $0.itemStatus == .conflicted || $0.isTreeConflict })
    let revision = try await service.commit(
        wc: fixture.workingCopy,
        paths: ["README.txt"],
        message: "resolve conflict with merge engine",
        auth: nil
    )
    XCTAssertGreaterThan(revision.value, 1)
}
```

测试文件已有私有 `lines(_:)` 辅助时复用；若没有，在测试类末尾新增与 `MergeEngineTests` 相同的 helper。

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter SvnCliBackendIntegrationTests/testMergeEngineResolvesTextConflictAndCommitSucceeds
```

预期：实现前编译失败；若 `MergeEngine` 没有产生可 resolution 的冲突块，测试失败。

- [ ] **步骤 3：运行目标测试验证通过**

运行：

```bash
swift test --filter "MergeEngineTests|SvnCliBackendIntegrationTests/testMergeEngineResolvesTextConflictAndCommitSucceeds"
```

预期：目标测试 PASS。

## 任务 5：全量验证与提交

**文件：**
- 上述全部文件

- [ ] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

运行：

```bash
git add Sources/MacSvnCore/Services/MergeEngine.swift Tests/MacSvnCoreTests/MergeEngineTests.swift Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift docs/superpowers/plans/2026-07-09-p3-merge-engine.md
git diff --cached --check
git commit -m "feat: add P3 merge engine"
git diff HEAD^ HEAD --check
git status --short --branch
```

预期：暂存区检查无输出，提交后补丁检查无输出，工作区干净。
