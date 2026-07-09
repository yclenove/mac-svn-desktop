# P5 Cleanup Strategy Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 P5 `FR-GM-04` 的清理策略 Core 底座：从 SVN 条目识别超大文件、规范化用户排除路径，并把 `svn:ignore` 属性转换为可写入 `.gitignore` 的内容。

**架构：** 新增纯 Swift `GitMigrationCleanupPlanner`，不执行 SVN/Git 子进程，只消费 `RemoteEntry` 与 `SvnProperty` 输入，输出可绑定到迁移向导的 `GitMigrationCleanupPlan`。后续 UI/远端属性采集/真实写入 `.gitignore` 可复用该 planner。

**技术栈：** Swift Package、纯模型、XCTest、TDD。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
  - 增加清理策略模型：large file finding、cleanup plan、cleanup error。
- 创建：`Sources/MacSvnCore/Services/GitMigrationCleanupPlanner.swift`
  - 纯函数式 planner：大文件扫描、排除路径规范化、`.gitignore` 内容生成。
- 创建：`Tests/MacSvnCoreTests/GitMigrationCleanupPlannerTests.swift`
  - 覆盖大文件阈值、排除路径、`svn:ignore` 转换与非法阈值。

## 任务 1：大文件与排除路径计划

**文件：**
- 修改：`Sources/MacSvnCore/Models/GitMigrationModels.swift`
- 创建：`Sources/MacSvnCore/Services/GitMigrationCleanupPlanner.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationCleanupPlannerTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `GitMigrationCleanupPlannerTests` 并加入：

```swift
func testPlanFlagsLargeFilesAndNormalizesExcludedPaths() throws {
    let planner = GitMigrationCleanupPlanner()
    let entries = [
        remoteFile("trunk/build/app.zip", size: 12 * 1024 * 1024),
        remoteFile("trunk/README.md", size: 1024),
        RemoteEntry(name: "build", path: "trunk/build", kind: .directory, size: nil, revision: nil, author: nil, date: nil)
    ]

    let plan = try planner.plan(
        entries: entries,
        svnIgnoreProperties: [],
        excludedPaths: [" /trunk/build/ ", "trunk/tmp", "trunk/build"],
        largeFileThresholdBytes: 10 * 1024 * 1024
    )

    XCTAssertEqual(plan.largeFiles, [
        GitMigrationLargeFileFinding(
            path: "trunk/build/app.zip",
            sizeBytes: 12 * 1024 * 1024,
            thresholdBytes: 10 * 1024 * 1024
        )
    ])
    XCTAssertEqual(plan.excludedPaths, ["trunk/build", "trunk/tmp"])
    XCTAssertTrue(plan.hasLargeFileWarnings)
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationCleanupPlannerTests/testPlanFlagsLargeFilesAndNormalizesExcludedPaths
```

预期：编译失败，提示 `GitMigrationCleanupPlanner` / `GitMigrationLargeFileFinding` 未定义。

- [ ] **步骤 3：实现最少代码**

在模型中增加：

```swift
public struct GitMigrationLargeFileFinding: Equatable, Sendable {
    public let path: String
    public let sizeBytes: Int
    public let thresholdBytes: Int
}

public struct GitMigrationCleanupPlan: Equatable, Sendable {
    public let largeFiles: [GitMigrationLargeFileFinding]
    public let excludedPaths: [String]
    public let gitIgnoreContents: String

    public var hasLargeFileWarnings: Bool { !largeFiles.isEmpty }
}

public enum GitMigrationCleanupError: Error, Equatable, Sendable {
    case invalidLargeFileThreshold(Int)
}
```

新增 `GitMigrationCleanupPlanner.plan(...)`，规则：

- 只扫描 `RemoteEntry.kind == .file` 且 `size != nil` 的条目；
- `sizeBytes > largeFileThresholdBytes` 记为大文件；
- 排除路径 trim 空白、去掉首尾 `/`、去重后字典序排序；
- 大文件按 path 字典序稳定排序；
- `gitIgnoreContents` 先返回空字符串，后续任务扩展。

- [ ] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 2：`svn:ignore` 转 `.gitignore`

**文件：**
- 修改：`Sources/MacSvnCore/Services/GitMigrationCleanupPlanner.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationCleanupPlannerTests.swift`

- [ ] **步骤 1：编写失败测试**

在同一测试文件增加：

```swift
func testPlanConvertsSvnIgnorePropertiesToGitIgnoreContents() throws {
    let planner = GitMigrationCleanupPlanner()
    let plan = try planner.plan(
        entries: [],
        svnIgnoreProperties: [
            SvnProperty(target: ".", name: "svn:ignore", value: "*.log\nbuild\n\n"),
            SvnProperty(target: "src", name: "svn:ignore", value: "DerivedData\n*.tmp"),
            SvnProperty(target: "docs", name: "svn:eol-style", value: "native")
        ],
        excludedPaths: []
    )

    XCTAssertEqual(plan.gitIgnoreContents, "*.log\nbuild\nsrc/DerivedData\nsrc/*.tmp\n")
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationCleanupPlannerTests/testPlanConvertsSvnIgnorePropertiesToGitIgnoreContents
```

预期：测试失败，`gitIgnoreContents` 为空。

- [ ] **步骤 3：实现最少代码**

扩展 planner：

- 只读取 `name == "svn:ignore"` 的属性；
- value 按换行拆分，trim 空白，忽略空行；
- target 为 `""`、`.`、`/` 时规则保持原样；
- 其他 target 去掉首尾 `/` 后作为路径前缀，例如 `src` + `*.tmp` → `src/*.tmp`；
- 规则去重，保留首次出现顺序；
- 非空结果以换行结尾。

- [ ] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 3：非法阈值与验证

**文件：**
- 修改：`Sources/MacSvnCore/Services/GitMigrationCleanupPlanner.swift`
- 测试：`Tests/MacSvnCoreTests/GitMigrationCleanupPlannerTests.swift`

- [ ] **步骤 1：编写失败测试**

```swift
func testPlanRejectsNonPositiveLargeFileThreshold() {
    let planner = GitMigrationCleanupPlanner()

    XCTAssertThrowsError(try planner.plan(entries: [], largeFileThresholdBytes: 0)) { error in
        XCTAssertEqual(error as? GitMigrationCleanupError, .invalidLargeFileThreshold(0))
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter GitMigrationCleanupPlannerTests/testPlanRejectsNonPositiveLargeFileThreshold
```

预期：测试失败或编译失败，因为 planner 尚未校验阈值。

- [ ] **步骤 3：实现最少代码**

在 `plan(...)` 开头增加：

```swift
guard largeFileThresholdBytes > 0 else {
    throw GitMigrationCleanupError.invalidLargeFileThreshold(largeFileThresholdBytes)
}
```

- [ ] **步骤 4：运行目标集合**

运行：

```bash
swift test --filter GitMigrationCleanupPlannerTests
```

预期：3 个测试全部 PASS。

## 任务 4：全量验证与提交

- [ ] **步骤 1：运行 P5 目标集合**

```bash
swift test --filter "GitMigrationCleanupPlannerTests|GitMigrationSourceAnalyzerTests|GitMigrationServiceTests|GitMigrationViewModelTests"
```

预期：0 failures。

- [ ] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [ ] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/Models/GitMigrationModels.swift \
  Sources/MacSvnCore/Services/GitMigrationCleanupPlanner.swift \
  Tests/MacSvnCoreTests/GitMigrationCleanupPlannerTests.swift \
  docs/superpowers/plans/2026-07-10-p5-cleanup-strategy-core.md
git diff --cached --check
git commit -m "feat: add P5 cleanup strategy core"
git status --short --branch
```

## 自检

- 覆盖 `FR-GM-04` 的 Core 底座：排除路径、超大文件扫描提示、`svn:ignore` → `.gitignore` 内容生成。
- 不覆盖 GUI 表格、远端递归属性采集、真实 `.gitignore` 写盘、BFG/git-filter-repo 自动执行；这些属于后续迁移向导 UI 与高级清理切片。
