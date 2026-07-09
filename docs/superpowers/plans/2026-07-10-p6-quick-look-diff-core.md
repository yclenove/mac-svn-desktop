# P6 Quick Look Diff Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 `FR-EX-08` 建立 Quick Look diff Core：给定工作副本根目录和 Finder/Quick Look 传入的文件 URL，返回相对基线的 unified diff 预览、不可预览原因或错误状态。

**架构：** 新增纯 Core `QuickLookDiffPreviewService`，复用现有 `DiffProviding` 与 `DiffViewModel.parseLines`。本切片不创建 Quick Look extension target，不接触 Finder/系统 API，只提供后续 extension 可调用、可单测的预览模型与装载逻辑。

**技术栈：** Swift 6、Foundation、XCTest、现有 `DiffProviding` / `UnifiedDiffLine` / `BinaryFileDetails`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Services/QuickLookDiffPreviewService.swift`
  - 增加 `QuickLookDiffPreview`、`QuickLookDiffUnsupportedReason`、`QuickLookDiffPreviewResult` 与 `QuickLookDiffPreviewService`。
- 创建测试：`Tests/MacSvnCoreTests/QuickLookDiffPreviewServiceTests.swift`
  - 覆盖工作副本内文件 diff 预览、工作副本外路径、目录、二进制 diff、本地文件缺失和 provider 错误。

---

## 任务 1：工作副本内文件 diff 预览主路径

**文件：**
- 创建：`Sources/MacSvnCore/Services/QuickLookDiffPreviewService.swift`
- 创建测试：`Tests/MacSvnCoreTests/QuickLookDiffPreviewServiceTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `QuickLookDiffPreviewServiceTests.swift`：

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class QuickLookDiffPreviewServiceTests: XCTestCase {
    func testPreviewLoadsRelativeBaselineDiffAndClassifiesLines() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let sourceDirectory = workingCopy.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let fileURL = sourceDirectory.appendingPathComponent("App.swift")
        try "let value = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let diff = """
        Index: Sources/App.swift
        ===================================================================
        --- Sources/App.swift\t(revision 4)
        +++ Sources/App.swift\t(working copy)
        @@ -1,1 +1,1 @@
        -let value = 1
        +let value = 2
        """
        let provider = FakeQuickLookDiffProvider(result: .success(diff))
        let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

        let result = await service.preview(fileURL: fileURL)
        let calls = await provider.recordedCalls()

        guard case .preview(let preview) = result else {
            return XCTFail("Expected preview result, got \(result)")
        }
        XCTAssertEqual(preview.workingCopy, workingCopy.standardizedFileURL)
        XCTAssertEqual(preview.fileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(preview.target, "Sources/App.swift")
        XCTAssertEqual(preview.diffText, diff)
        XCTAssertEqual(preview.lines.map(\.kind), [
            .metadata, .metadata, .metadata, .metadata,
            .hunk, .deletion, .addition
        ])
        XCTAssertEqual(calls, [
            QuickLookDiffCall(wc: workingCopy.standardizedFileURL, target: "Sources/App.swift", r1: nil, r2: nil)
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct QuickLookDiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private actor FakeQuickLookDiffProvider: DiffProviding {
    private let result: Result<String, Error>
    private var calls: [QuickLookDiffCall] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func recordedCalls() -> [QuickLookDiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(QuickLookDiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return try result.get()
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter QuickLookDiffPreviewServiceTests/testPreviewLoadsRelativeBaselineDiffAndClassifiesLines
```

预期：编译失败，提示 `QuickLookDiffPreviewService` 或 `QuickLookDiffPreviewResult` 不存在。

- [x] **步骤 3：实现最少模型与服务主路径**

创建 `QuickLookDiffPreviewService.swift`：

```swift
import Foundation

public struct QuickLookDiffPreview: Equatable, Sendable {
    public let workingCopy: URL
    public let fileURL: URL
    public let target: String
    public let diffText: String
    public let lines: [UnifiedDiffLine]

    public init(workingCopy: URL, fileURL: URL, target: String, diffText: String, lines: [UnifiedDiffLine]) {
        self.workingCopy = workingCopy
        self.fileURL = fileURL
        self.target = target
        self.diffText = diffText
        self.lines = lines
    }
}

public enum QuickLookDiffUnsupportedReason: Equatable, Sendable {
    case outsideWorkingCopy
    case directory
    case missing
    case binary(BinaryFileDetails?)
}

public enum QuickLookDiffPreviewResult: Equatable, Sendable {
    case preview(QuickLookDiffPreview)
    case unsupported(QuickLookDiffUnsupportedReason)
    case error(String)
}

public struct QuickLookDiffPreviewService: Sendable {
    private let workingCopy: URL
    private let diffProvider: any DiffProviding

    public init(workingCopy: URL, diffProvider: any DiffProviding) {
        self.workingCopy = workingCopy.standardizedFileURL
        self.diffProvider = diffProvider
    }

    public func preview(fileURL: URL) async -> QuickLookDiffPreviewResult {
        let standardizedFileURL = fileURL.standardizedFileURL
        guard let target = Self.relativeTarget(for: standardizedFileURL, in: workingCopy) else {
            return .unsupported(.outsideWorkingCopy)
        }

        do {
            let diff = try await diffProvider.diff(wc: workingCopy, target: target, r1: nil, r2: nil)
            return .preview(QuickLookDiffPreview(
                workingCopy: workingCopy,
                fileURL: standardizedFileURL,
                target: target,
                diffText: diff,
                lines: DiffViewModel.parseLines(diff)
            ))
        } catch {
            return .error(String(describing: error))
        }
    }

    private static func relativeTarget(for fileURL: URL, in workingCopy: URL) -> String? {
        let wcPath = workingCopy.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(wcPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(wcPath.count + 1))
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter QuickLookDiffPreviewServiceTests/testPreviewLoadsRelativeBaselineDiffAndClassifiesLines
```

预期：主路径测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/QuickLookDiffPreviewService.swift Tests/MacSvnCoreTests/QuickLookDiffPreviewServiceTests.swift docs/superpowers/plans/2026-07-10-p6-quick-look-diff-core.md
git commit -m "feat: add P6 quick look diff preview core"
```

---

## 任务 2：不可预览与错误状态

**文件：**
- 修改：`Sources/MacSvnCore/Services/QuickLookDiffPreviewService.swift`
- 修改测试：`Tests/MacSvnCoreTests/QuickLookDiffPreviewServiceTests.swift`

- [x] **步骤 1：编写失败测试**

追加以下测试：

```swift
func testPreviewRejectsOutsideWorkingCopyDirectoriesAndMissingFilesWithoutCallingDiff() async throws {
    let workingCopy = try makeTemporaryDirectory()
    let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).swift")
    try "outside\n".write(to: outsideFile, atomically: true, encoding: .utf8)
    let directoryURL = workingCopy.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let missingFile = workingCopy.appendingPathComponent("Missing.swift")
    let provider = FakeQuickLookDiffProvider(result: .success(""))
    let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

    let outside = await service.preview(fileURL: outsideFile)
    let directory = await service.preview(fileURL: directoryURL)
    let missing = await service.preview(fileURL: missingFile)
    let calls = await provider.recordedCalls()

    XCTAssertEqual(outside, .unsupported(.outsideWorkingCopy))
    XCTAssertEqual(directory, .unsupported(.directory))
    XCTAssertEqual(missing, .unsupported(.missing))
    XCTAssertEqual(calls, [])
}

func testPreviewMapsBinaryDiffToUnsupportedWithLocalFileDetails() async throws {
    let workingCopy = try makeTemporaryDirectory()
    let fileURL = workingCopy.appendingPathComponent("image.bin")
    try Data([1, 2, 3, 4, 5]).write(to: fileURL)
    let provider = FakeQuickLookDiffProvider(result: .success("Cannot display: file marked as a binary type.\n"))
    let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

    let result = await service.preview(fileURL: fileURL)

    guard case .unsupported(.binary(let details)) = result else {
        return XCTFail("Expected binary unsupported result, got \(result)")
    }
    XCTAssertEqual(details?.size, 5)
    XCTAssertNotNil(details?.modifiedAt)
}

func testPreviewMapsProviderFailureToError() async throws {
    let workingCopy = try makeTemporaryDirectory()
    let fileURL = workingCopy.appendingPathComponent("App.swift")
    try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
    let provider = FakeQuickLookDiffProvider(result: .failure(SvnError.network(detail: "offline")))
    let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

    let result = await service.preview(fileURL: fileURL)

    XCTAssertEqual(result, .error(String(describing: SvnError.network(detail: "offline"))))
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter QuickLookDiffPreviewServiceTests
```

预期：测试失败，目录/缺失文件当前会调用 diff，二进制 diff 当前返回 `.preview`。

- [x] **步骤 3：实现不可预览与错误处理**

在 `preview(fileURL:)` 中调用 `fileExists(atPath:isDirectory:)`：

```swift
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: standardizedFileURL.path, isDirectory: &isDirectory) else {
    return .unsupported(.missing)
}
guard !isDirectory.boolValue else {
    return .unsupported(.directory)
}
```

在 diff 返回后检测二进制输出：

```swift
if Self.isBinaryUnsupportedDiff(diff) {
    return .unsupported(.binary(Self.binaryDetails(for: standardizedFileURL)))
}
```

新增私有辅助：

```swift
private static func isBinaryUnsupportedDiff(_ diff: String) -> Bool {
    let normalized = diff.lowercased()
    return (normalized.contains("cannot display") && normalized.contains("binary"))
        || normalized.contains("binary files")
}

private static func binaryDetails(for fileURL: URL) -> BinaryFileDetails? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
        return nil
    }
    let size = (attributes[.size] as? NSNumber)?.uint64Value
    let modifiedAt = attributes[.modificationDate] as? Date
    return BinaryFileDetails(size: size, modifiedAt: modifiedAt)
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter QuickLookDiffPreviewServiceTests
```

预期：Quick Look diff 目标测试 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Services/QuickLookDiffPreviewService.swift Tests/MacSvnCoreTests/QuickLookDiffPreviewServiceTests.swift docs/superpowers/plans/2026-07-10-p6-quick-look-diff-core.md
git commit -m "test: cover P6 quick look diff unsupported states"
```

---

## 任务 3：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p6-quick-look-diff-core.md`

- [x] **步骤 1：运行 FR-EX-08 目标集合**

```bash
swift test --filter QuickLookDiffPreviewServiceTests
```

预期：目标集合 PASS。

- [x] **步骤 2：运行全量验证**

```bash
swift test
```

预期：全部 XCTest PASS。

- [x] **步骤 3：运行空白检查**

```bash
git diff --check
```

预期：无输出、退出码 0。

- [x] **步骤 4：更新计划勾选并提交验证记录**

将本计划完成步骤勾选为 `[x]`，提交：

```bash
git add docs/superpowers/plans/2026-07-10-p6-quick-look-diff-core.md
git commit -m "docs: complete P6 quick look diff verification"
```

## 自检

- 覆盖 `FR-EX-08` 的 Core 支撑：Quick Look extension 可传入文件 URL 并获得相对基线 diff 预览。
- 不引入系统扩展 target；当前仓库还没有 App/Extension 产品结构，本计划只交付可测试 Core。
- 不执行 SVN 写操作，不影响基础客户端功能，符合创新模块故障隔离原则。
