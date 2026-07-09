# P1 Diff View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 Unified Diff 状态层，覆盖 FR-DF-01/04 的非 UI 部分：加载 `svn diff` 文本、按行分类以支持语法着色、识别二进制不可显示提示并暴露本地文件大小/修改时间。

**架构：** 新增 `DiffViewModel` 作为 `@MainActor @Observable` 状态对象，依赖新的 `DiffProviding` 协议。`SvnService.diff` 继续提供原始 diff 文本；ViewModel 只负责调用、状态、unified diff 行分类与二进制文件提示。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation、Foundation 文件属性读取。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/DiffViewModel.swift`
  定义 `DiffProviding`、`DiffViewState`、`UnifiedDiffLineKind`、`UnifiedDiffLine`、`BinaryFileDetails`、`DiffViewModel`，并让 `SvnService` 遵循 `DiffProviding`。
- 创建：`Tests/MacSvnCoreTests/DiffViewModelTests.swift`
  覆盖 diff 调用参数、行分类、二进制不可显示状态、错误状态。
- 创建：`docs/superpowers/plans/2026-07-09-p1-diff-view-model.md`
  记录此切片计划。

## 任务 1：Unified Diff 加载与行分类

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/DiffViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/DiffViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `DiffViewModelTests`，先覆盖文本 diff：

```swift
@MainActor
func testLoadUnifiedDiffPassesTargetRevisionRangeAndClassifiesLines() async {
    let diff = """
    Index: a.swift
    ===================================================================
    --- a.swift\t(revision 1)
    +++ a.swift\t(working copy)
    @@ -1,2 +1,2 @@
     let unchanged = true
    -old
    +new
    \\ No newline at end of file
    """
    let provider = FakeDiffProvider(result: .success(diff))
    let viewModel = DiffViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        diffProvider: provider
    )

    await viewModel.load(target: "a.swift", r1: Revision(1), r2: Revision(2))

    XCTAssertEqual(viewModel.state, .loaded)
    XCTAssertEqual(viewModel.lines.map(\.kind), [
        .metadata, .metadata, .metadata, .metadata,
        .hunk, .context, .deletion, .addition, .noNewlineMarker
    ])
    XCTAssertEqual(await provider.recordedCalls(), [
        DiffCall(wc: URL(fileURLWithPath: "/tmp/wc"), target: "a.swift", r1: Revision(1), r2: Revision(2))
    ])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter DiffViewModelTests`
预期：编译失败，提示 `DiffViewModel`、`DiffProviding` 或 diff 行类型未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `DiffProviding` 协议：`diff(wc:target:r1:r2:)`。
- `DiffViewState`：`.idle/.loading/.loaded/.binaryUnsupported(BinaryFileDetails?)/.error(String)`。
- `UnifiedDiffLineKind` 与 `UnifiedDiffLine`。
- `DiffViewModel.load(target:r1:r2:)`：调用 provider，保存原始文本，按行分类，置 `.loaded`。
- `UnifiedDiffLine.classify(_:)`：`@@` 为 hunk，`+++`/`---` 和 `Index:`/`===` 为 metadata，`+` 为 addition，`-` 为 deletion，`\` 为 noNewlineMarker，其余为 context。
- `extension SvnService: DiffProviding {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter DiffViewModelTests`
预期：文本 diff 测试 PASS。

## 任务 2：二进制文件提示

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/DiffViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/DiffViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增二进制 diff 测试：

```swift
@MainActor
func testBinaryDiffStoresUnsupportedStateAndLocalFileDetails() async throws {
    let workingCopy = try makeTemporaryDirectory()
    let fileURL = workingCopy.appendingPathComponent("image.bin")
    try Data([1, 2, 3, 4]).write(to: fileURL)
    let provider = FakeDiffProvider(result: .success("Cannot display: file marked as a binary type.\\n"))
    let viewModel = DiffViewModel(workingCopy: workingCopy, diffProvider: provider)

    await viewModel.load(target: "image.bin")

    guard case .binaryUnsupported(let details) = viewModel.state else {
        return XCTFail("Expected binary unsupported state, got \\(viewModel.state)")
    }
    XCTAssertEqual(details?.size, 4)
    XCTAssertNotNil(details?.modifiedAt)
    XCTAssertEqual(viewModel.lines, [])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter DiffViewModelTests`
预期：二进制状态测试失败或编译失败。

- [x] **步骤 3：编写最少实现代码**

实现：

- `BinaryFileDetails(size:modifiedAt:)`。
- 检测原始 diff 文本中包含 `Cannot display` 且包含 `binary`，或包含 `Binary files`。
- 对二进制结果读取 `workingCopy/target` 的 `.size` 与 `.modificationDate`，置 `.binaryUnsupported(details)`，清空 `lines`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter DiffViewModelTests`
预期：二进制测试 PASS。

## 任务 3：错误状态、全量验证与提交

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/DiffViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/DiffViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

新增错误路径测试：

```swift
@MainActor
func testDiffFailureStoresErrorAndClearsLines() async {
    let provider = FakeDiffProvider(result: .failure(SvnError.network(detail: "offline")))
    let viewModel = DiffViewModel(
        workingCopy: URL(fileURLWithPath: "/tmp/wc"),
        diffProvider: provider
    )

    await viewModel.load(target: "a.swift")

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.diffText, "")
    XCTAssertEqual(viewModel.lines, [])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter DiffViewModelTests`
预期：错误路径测试失败或编译失败。

- [x] **步骤 3：编写最少实现代码**

确保 provider 失败时清空 `diffText` 和 `lines`，并置 `.error(String(describing: error))`。

- [x] **步骤 4：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/DiffViewModel.swift Tests/MacSvnCoreTests/DiffViewModelTests.swift docs/superpowers/plans/2026-07-09-p1-diff-view-model.md
git commit -m "feat: add P1 diff view model"
```
