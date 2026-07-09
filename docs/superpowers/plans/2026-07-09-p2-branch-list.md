# P2 Branch List 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 FR-BR-01 的 Core 非 UI 部分：按可配置 `BranchLayout` 从仓库根列出 trunk、branches 和 tags。

**架构：** 复用 P2 已有远端 `list(url:depth:auth:)` 能力，不新增 CLI 命令。新增 `BranchReference` 领域模型、URL 解析纯函数、`SvnService.branches(...)` 业务方法与 `BranchBrowserViewModel` 状态层；真实 svn 集成测试通过临时仓库中的 branch/tag 目录验证列表闭环。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation、svn CLI。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `BranchReferenceKind`、`BranchReference`、`BranchList`。
- 创建：`Sources/MacSvnCore/Services/BranchListService.swift`
  定义 `BranchListProviding`、`BranchListURLResolver`，并让 `SvnService` 使用现有 `list` 能力列出分支与标签。
- 创建：`Sources/MacSvnCore/ViewModels/BranchBrowserViewModel.swift`
  定义 `BranchBrowserState` 与 `BranchBrowserViewModel`。
- 创建：`Tests/MacSvnCoreTests/BranchListServiceTests.swift`
  覆盖 URL 拼接、分支/标签过滤、认证透传和错误容错。
- 创建：`Tests/MacSvnCoreTests/BranchBrowserViewModelTests.swift`
  覆盖加载成功、错误状态与自定义布局透传。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnIntegrationTestCase.swift`
  在测试仓库中预置一个 branch 和一个 tag。
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`
  覆盖真实 `SvnService.branches` 从远端列出 branch/tag。

## 任务 1：BranchReference 模型与 URL resolver

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/BranchListService.swift`
- 测试：`Tests/MacSvnCoreTests/BranchListServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `BranchListServiceTests`，先覆盖纯 URL 解析：

```swift
func testBranchLayoutURLResolverBuildsStandardUrlsFromRepositoryRoot() {
    let layout = BranchLayout()

    XCTAssertEqual(
        BranchListURLResolver.url(repositoryRoot: "file:///repo", path: layout.trunk),
        "file:///repo/trunk"
    )
    XCTAssertEqual(
        BranchListURLResolver.url(repositoryRoot: "file:///repo/", path: layout.branches),
        "file:///repo/branches"
    )
    XCTAssertEqual(
        BranchListURLResolver.url(repositoryRoot: "file:///repo", path: "release/tags"),
        "file:///repo/release/tags"
    )
}

func testBranchLayoutURLResolverKeepsAbsoluteLayoutPaths() {
    XCTAssertEqual(
        BranchListURLResolver.url(repositoryRoot: "file:///repo", path: "/custom/branches"),
        "file:///repo/custom/branches"
    )
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter BranchListServiceTests/testBranchLayoutURLResolver`
预期：编译失败，提示 `BranchListURLResolver` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `BranchReferenceKind`: `.trunk/.branch/.tag`。
- `BranchReference`: `name/url/kind/revision/author/date`。
- `BranchList`: `trunk/branches/tags`。
- `BranchListURLResolver.url(repositoryRoot:path:)`：裁剪首尾 `/`，将仓库根和布局路径拼成远端 URL。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter BranchListServiceTests/testBranchLayoutURLResolver`
预期：目标测试 PASS。

## 任务 2：SvnService 分支/标签列表

**文件：**
- 修改：`Sources/MacSvnCore/Services/BranchListService.swift`
- 测试：`Tests/MacSvnCoreTests/BranchListServiceTests.swift`

- [ ] **步骤 1：编写失败的测试**

在 `BranchListServiceTests` 中新增 fake provider，覆盖 service 行为：

```swift
func testBranchListProviderListsTrunkBranchesAndTagsWithImmediateDepth() async throws {
    let listProvider = FakeBranchRepoListProvider(results: [
        "file:///repo/trunk": .success([
            RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 4, revision: Revision(2), author: "a", date: nil)
        ]),
        "file:///repo/branches": .success([
            RemoteEntry(name: "feature-one", path: "feature-one", kind: .directory, size: nil, revision: Revision(3), author: "b", date: nil),
            RemoteEntry(name: "note.txt", path: "note.txt", kind: .file, size: 1, revision: Revision(4), author: "c", date: nil)
        ]),
        "file:///repo/tags": .success([
            RemoteEntry(name: "v1.0", path: "v1.0", kind: .directory, size: nil, revision: Revision(5), author: "d", date: nil)
        ])
    ])
    let auth = Credential(username: "u", password: "p")

    let branchList = try await BranchListService(listProvider: listProvider).branches(
        repositoryRoot: "file:///repo",
        layout: BranchLayout(),
        auth: auth
    )

    XCTAssertEqual(branchList.trunk?.url, "file:///repo/trunk")
    XCTAssertEqual(branchList.trunk?.kind, .trunk)
    XCTAssertEqual(branchList.branches.map(\.name), ["feature-one"])
    XCTAssertEqual(branchList.branches.map(\.url), ["file:///repo/branches/feature-one"])
    XCTAssertEqual(branchList.tags.map(\.name), ["v1.0"])
    XCTAssertEqual(await listProvider.recordedCalls(), [
        BranchRepoListCall(url: "file:///repo/trunk", depth: .immediates, auth: auth),
        BranchRepoListCall(url: "file:///repo/branches", depth: .immediates, auth: auth),
        BranchRepoListCall(url: "file:///repo/tags", depth: .immediates, auth: auth)
    ])
}

func testMissingTrunkStillReturnsBranchesAndTags() async throws {
    let listProvider = FakeBranchRepoListProvider(results: [
        "file:///repo/trunk": .failure(SvnError.environment(detail: "missing")),
        "file:///repo/branches": .success([
            RemoteEntry(name: "dev", path: "dev", kind: .directory, size: nil, revision: nil, author: nil, date: nil)
        ]),
        "file:///repo/tags": .success([])
    ])

    let branchList = try await BranchListService(listProvider: listProvider).branches(
        repositoryRoot: "file:///repo",
        layout: BranchLayout(),
        auth: nil
    )

    XCTAssertNil(branchList.trunk)
    XCTAssertEqual(branchList.branches.map(\.name), ["dev"])
    XCTAssertEqual(branchList.tags, [])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter BranchListServiceTests`
预期：编译失败或测试失败，提示 `BranchListService` 未实现。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `BranchRepositoryListing` 协议：`list(url:depth:auth:)`。
- `BranchListService.branches(repositoryRoot:layout:auth:)`，使用 `.immediates` 分别 list trunk、branches、tags。
- trunk URL 可访问即可产生一个 `.trunk` reference，元数据取 trunk list 结果中的最高 revision/author/date；trunk list 失败时 trunk 为 nil。
- branches/tags 只保留 `.directory` 条目，按远端返回顺序映射为 reference。
- `extension SvnService: BranchListProviding` 使用 `BranchListService(listProvider: self)`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter BranchListServiceTests`
预期：全部目标测试 PASS。

## 任务 3：BranchBrowserViewModel 状态层

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/BranchBrowserViewModel.swift`
- 测试：`Tests/MacSvnCoreTests/BranchBrowserViewModelTests.swift`

- [ ] **步骤 1：编写失败的测试**

创建 `BranchBrowserViewModelTests`：

```swift
@MainActor
func testLoadBranchesStoresBranchListAndPassesLayoutAuth() async {
    let branchList = BranchList(
        trunk: BranchReference(name: "trunk", url: "file:///repo/main", kind: .trunk, revision: Revision(1), author: nil, date: nil),
        branches: [BranchReference(name: "dev", url: "file:///repo/dev/dev", kind: .branch, revision: Revision(2), author: "a", date: nil)],
        tags: []
    )
    let provider = FakeBranchListProvider(result: .success(branchList))
    let viewModel = BranchBrowserViewModel(provider: provider)
    let layout = BranchLayout(trunk: "main", branches: "dev", tags: "releases")
    let auth = Credential(username: "u", password: "p")

    await viewModel.load(repositoryRoot: "file:///repo", layout: layout, auth: auth)

    XCTAssertEqual(viewModel.state, .loaded)
    XCTAssertEqual(viewModel.branchList, branchList)
    XCTAssertEqual(await provider.recordedCalls(), [
        BranchListCall(repositoryRoot: "file:///repo", layout: layout, auth: auth)
    ])
}

@MainActor
func testLoadBranchesFailureClearsListAndStoresError() async {
    let provider = FakeBranchListProvider(result: .failure(SvnError.network(detail: "offline")))
    let viewModel = BranchBrowserViewModel(provider: provider)

    await viewModel.load(repositoryRoot: "file:///repo", layout: BranchLayout(), auth: nil)

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertEqual(viewModel.branchList, BranchList())
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter BranchBrowserViewModelTests`
预期：编译失败，提示 `BranchBrowserViewModel` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现：
- `BranchBrowserState`: `.idle/.loading/.loaded/.error(String)`。
- `BranchBrowserViewModel`：依赖 `BranchListProviding`，暴露 `state`、`branchList` 和 `load(repositoryRoot:layout:auth:)`。

- [ ] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter BranchBrowserViewModelTests`
预期：全部目标测试 PASS。

## 任务 4：真实 SVN 集成验证

**文件：**
- 修改：`Tests/MacSvnCoreTests/Integration/SvnIntegrationTestCase.swift`
- 修改：`Tests/MacSvnCoreTests/Integration/SvnCliBackendIntegrationTests.swift`

- [ ] **步骤 1：编写失败的集成测试**

在 `SvnIntegrationTestCase.makeFixture()` 的 import 根中预置：
- `branches/feature-one/README.txt`
- `tags/v1.0/README.txt`

在 `SvnCliBackendIntegrationTests` 中新增：

```swift
func testServiceListsBranchesAndTagsFromRepositoryRoot() async throws {
    let fixture = try makeFixture()
    let service = SvnService(backend: fixture.backend)

    let branchList = try await service.branches(
        repositoryRoot: fixture.repositoryURL,
        layout: BranchLayout(),
        auth: nil
    )

    XCTAssertEqual(branchList.trunk?.url, fixture.trunkURL)
    XCTAssertEqual(branchList.branches.map(\.name), ["feature-one"])
    XCTAssertEqual(branchList.tags.map(\.name), ["v1.0"])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendIntegrationTests/testServiceListsBranchesAndTagsFromRepositoryRoot`
预期：实现前编译失败；实现错误时断言失败。

- [ ] **步骤 3：编写最少实现代码**

若前三个任务实现正确，只需要更新测试夹具和集成测试。

- [ ] **步骤 4：运行目标和全量验证**

运行：

```bash
swift test --filter "BranchListServiceTests|BranchBrowserViewModelTests|SvnCliBackendIntegrationTests/testServiceListsBranchesAndTagsFromRepositoryRoot"
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p2-branch-list.md
git commit -m "feat: add P2 branch list support"
```
