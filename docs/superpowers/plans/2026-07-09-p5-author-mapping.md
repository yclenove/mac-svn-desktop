# P5 Author Mapping 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P5 `FR-GM-03` 的 Core 非 UI 能力：把 SVN 作者列表转换为可编辑 Git authors 映射，支持 100% 覆盖校验、authors.txt 导入导出，并为迁移向导提供状态层。

**架构：** 在 `GitMigrationModels` 中新增映射行、覆盖率和错误模型；新增纯服务 `GitMigrationAuthorMapper` 负责草稿生成、覆盖校验和 git-svn authors 文件字符串解析/序列化。新增 `GitMigrationAuthorMappingViewModel` 作为 `@MainActor @Observable` 状态层，负责载入作者、编辑映射、导入导出和暴露 `canStartMigration`。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation、Foundation 文件读写。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  增加 `GitMigrationAuthorMapping`、`GitMigrationAuthorMappingCoverage`、`GitMigrationAuthorMappingError`。
- 创建：`Sources/MacSvnCore/Services/GitMigrationAuthorMapper.swift`
  纯服务，生成草稿映射、校验覆盖率、解析/序列化 git-svn authors 文件、按 URL 导入导出。
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationAuthorMappingViewModel.swift`
  状态层，提供载入作者、编辑姓名/邮箱、导入、导出和覆盖率。
- 测试：`Tests/MacSvnCoreTests/GitMigrationAuthorMapperTests.swift`
  覆盖草稿生成、覆盖校验、authors.txt 解析/序列化和文件导入导出。
- 测试：`Tests/MacSvnCoreTests/GitMigrationAuthorMappingViewModelTests.swift`
  覆盖成功载入、编辑、导入导出、错误状态和 `canStartMigration`。

## 任务 1：Author mapping 模型与 mapper 纯逻辑

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationAuthorMapper.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationAuthorMapperTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationAuthorMapperTests`，覆盖：

```swift
func testDraftMappingsAreSortedAndEmptyUntilUserFillsGitIdentity() {
    let mapper = GitMigrationAuthorMapper()
    let mappings = mapper.draftMappings(from: [
        GitMigrationAuthor(svnUsername: "zhangsan"),
        GitMigrationAuthor(svnUsername: "lisi")
    ])

    XCTAssertEqual(mappings, [
        GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "", gitEmail: ""),
        GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: "", gitEmail: "")
    ])
    XCTAssertEqual(mapper.coverage(for: mappings).coveredCount, 0)
    XCTAssertFalse(mapper.coverage(for: mappings).isComplete)
}

func testCoverageRequiresNonEmptyNameAndEmailForEveryAuthor() {
    let mapper = GitMigrationAuthorMapper()
    let mappings = [
        GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com"),
        GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: " ", gitEmail: "zhangsan@example.com")
    ]

    XCTAssertEqual(mapper.coverage(for: mappings), GitMigrationAuthorMappingCoverage(totalCount: 2, coveredCount: 1))
    XCTAssertThrowsError(try mapper.validateComplete(mappings)) { error in
        XCTAssertEqual(error as? GitMigrationAuthorMappingError, .incompleteAuthors(["zhangsan"]))
    }
}

func testAuthorsFileRoundTripsGitSvnFormat() throws {
    let mapper = GitMigrationAuthorMapper()
    let mappings = [
        GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com"),
        GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: "张三", gitEmail: "zhangsan@example.com")
    ]

    let text = try mapper.authorsFileContents(from: mappings)
    XCTAssertEqual(text, "lisi = 李四 <lisi@example.com>\nzhangsan = 张三 <zhangsan@example.com>\n")
    XCTAssertEqual(try mapper.parseAuthorsFile(text), mappings)
}
```

再增加文件导入导出测试：写入临时 `authors.txt`，`exportAuthorsFile` 后读回内容一致，`importAuthorsFile` 返回映射。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationAuthorMapperTests
```

预期：编译失败，提示模型或 `GitMigrationAuthorMapper` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

```swift
public struct GitMigrationAuthorMapping: Equatable, Sendable {
    public let svnUsername: String
    public var gitName: String
    public var gitEmail: String
}

public struct GitMigrationAuthorMappingCoverage: Equatable, Sendable {
    public let totalCount: Int
    public let coveredCount: Int
    public var isComplete: Bool { totalCount > 0 && totalCount == coveredCount }
}

public enum GitMigrationAuthorMappingError: Error, Equatable, Sendable {
    case incompleteAuthors([String])
    case invalidAuthorsFileLine(String)
}
```

`GitMigrationAuthorMapper`：
- `draftMappings(from:)`：按 `svnUsername` 去重排序，`gitName/gitEmail` 为空。
- `coverage(for:)`：姓名和邮箱 trim 后都非空才计入 covered。
- `validateComplete(_:)`：有未覆盖作者时抛 `.incompleteAuthors`。
- `authorsFileContents(from:)`：先校验完整，再输出 `svn = Name <email>\n`。
- `parseAuthorsFile(_:)`：解析 `svn = Name <email>`，忽略空行，非法行抛 `.invalidAuthorsFileLine`。
- `exportAuthorsFile(_:to:)` / `importAuthorsFile(from:)`：UTF-8 文件读写。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 2：Author mapping ViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/GitMigrationAuthorMappingViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationAuthorMappingViewModelTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `GitMigrationAuthorMappingViewModelTests`，覆盖：

```swift
@MainActor
func testLoadAuthorsCreatesDraftRowsAndCoverage() {
    let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())

    viewModel.loadAuthors([
        GitMigrationAuthor(svnUsername: "zhangsan"),
        GitMigrationAuthor(svnUsername: "lisi")
    ])

    XCTAssertEqual(viewModel.state, .editing)
    XCTAssertEqual(viewModel.mappings.map(\.svnUsername), ["lisi", "zhangsan"])
    XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 2, coveredCount: 0))
    XCTAssertFalse(viewModel.canStartMigration)
}

@MainActor
func testUpdateMappingRefreshesCoverageAndCanStartMigration() {
    let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
    viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])

    viewModel.updateMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")

    XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 1, coveredCount: 1))
    XCTAssertTrue(viewModel.canStartMigration)
}

@MainActor
func testExportIncompleteMappingStoresError() async {
    let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
    viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])

    await viewModel.exportAuthorsFile(to: URL(fileURLWithPath: "/tmp/authors.txt"))

    XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationAuthorMappingError.incompleteAuthors(["lisi"]))))
}
```

再增加导入测试：导入 `authors.txt` 后 `mappings` 更新、覆盖率完成、状态为 `.editing`；导入非法文件时状态为 `.error(...)`。

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationAuthorMappingViewModelTests
```

预期：编译失败，提示 ViewModel 未定义。

- [x] **步骤 3：编写最少实现代码**

实现 `GitMigrationAuthorMappingState.idle/editing/exported(URL)/error(String)`；ViewModel 保存 `mappings`、`coverage`，并暴露 `canStartMigration`。`loadAuthors` 使用 mapper 生成草稿；`updateMapping` 只更新匹配 SVN 用户；导入/导出调用 mapper 文件方法。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期全部 PASS。

## 任务 3：全量验证与提交

- [x] **步骤 1：运行目标测试**

运行：

```bash
swift test --filter "GitMigrationAuthorMapperTests|GitMigrationAuthorMappingViewModelTests"
```

预期：全部 PASS。

- [x] **步骤 2：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [x] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/Models/GitMigrationModels.swift Sources/MacSvnCore/Services/GitMigrationAuthorMapper.swift Sources/MacSvnCore/ViewModels/GitMigrationAuthorMappingViewModel.swift Tests/MacSvnCoreTests/GitMigrationAuthorMapperTests.swift Tests/MacSvnCoreTests/GitMigrationAuthorMappingViewModelTests.swift docs/superpowers/plans/2026-07-09-p5-author-mapping.md
git diff --cached --check
git commit -m "feat: add P5 author mapping"
git diff HEAD^ HEAD --check
git status --short --branch
```

## 自检

- 覆盖 `FR-GM-03` 的 authors 映射 Core：从 SVN 作者生成表格数据、人工编辑所需模型、导入导出和 100% 覆盖校验。
- 不覆盖 AI 批量推断；AI 补全依赖 P6 `LLMClient`，后续单独计划实现。
- 不启动 `git svn clone`；迁移执行步骤依赖 authors 映射完成后另开计划。
