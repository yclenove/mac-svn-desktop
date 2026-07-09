# P2 Repo Checkout View Model 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 仓库浏览器从远端目录发起 checkout 并导入工作副本记录的 Core 状态层，覆盖 FR-RB-04 与 FR-WC-05/06 的非 UI 闭环。

**架构：** 新增 `CheckoutViewModel`，依赖小协议 `CheckoutProviding`、`WorkspaceImporting` 与既有 `WorkingCopyInfoProviding`。`SvnService` 负责真实 checkout 与认证重试，`WorkspaceStore` 负责导入和持久化；ViewModel 只负责状态、URL 拼接、目录条目保护、成功记录暴露与错误展示。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency、Observation。

---

## 文件结构

- 创建：`Sources/MacSvnCore/ViewModels/CheckoutViewModel.swift`
  定义 `CheckoutProviding`、`WorkspaceImporting`、`CheckoutViewState`、`CheckoutViewModel`，并让 `SvnService` / `WorkspaceStore` 遵循相关协议。
- 创建：`Tests/MacSvnCoreTests/CheckoutViewModelTests.swift`
  覆盖 URL checkout 后导入、远端目录条目 URL 拼接、远端文件拒绝 checkout、checkout 失败不导入、导入失败状态。
- 创建：`docs/superpowers/plans/2026-07-09-p2-repo-checkout-view-model.md`
  记录本切片计划。

## 任务 1：CheckoutViewModel URL checkout 与导入

**文件：**
- 创建：`Sources/MacSvnCore/ViewModels/CheckoutViewModel.swift`
- 创建：`Tests/MacSvnCoreTests/CheckoutViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `CheckoutViewModelTests`：

```swift
@MainActor
func testCheckoutURLRunsProviderAndImportsWorkingCopy() async {
    let record = workingCopyRecord(path: "/tmp/wc", repoURL: "file:///repo/trunk")
    let checkoutProvider = FakeCheckoutProvider()
    let importer = FakeWorkspaceImporter(result: .success(record))
    let infoProvider = FakeInfoProvider()
    let viewModel = CheckoutViewModel(
        checkoutProvider: checkoutProvider,
        workspaceImporter: importer,
        infoProvider: infoProvider
    )
    let destination = URL(fileURLWithPath: "/tmp/wc")
    let auth = Credential(username: "u", password: "p")

    await viewModel.checkout(
        url: "file:///repo/trunk",
        to: destination,
        depth: .files,
        auth: auth,
        username: "u",
        name: "Main"
    )

    XCTAssertEqual(viewModel.state, .completed(record))
    XCTAssertEqual(viewModel.importedWorkingCopy, record)
    XCTAssertEqual(await checkoutProvider.recordedCalls(), [
        CheckoutCall(url: "file:///repo/trunk", destination: destination, depth: .files, auth: auth)
    ])
    XCTAssertEqual(await importer.recordedCalls(), [
        WorkspaceImportCall(localPath: destination, username: "u", name: "Main")
    ])
}
```

同时新增失败状态测试：

```swift
@MainActor
func testCheckoutFailureDoesNotImportWorkingCopy() async {
    let checkoutProvider = FakeCheckoutProvider(error: SvnError.network(detail: "offline"))
    let importer = FakeWorkspaceImporter(result: .success(workingCopyRecord(path: "/tmp/wc", repoURL: "file:///repo/trunk")))
    let viewModel = CheckoutViewModel(
        checkoutProvider: checkoutProvider,
        workspaceImporter: importer,
        infoProvider: FakeInfoProvider()
    )

    await viewModel.checkout(url: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/wc"), depth: .empty)

    XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    XCTAssertTrue(await importer.recordedCalls().isEmpty)
}

@MainActor
func testImportFailureStoresErrorAfterCheckout() async {
    let checkoutProvider = FakeCheckoutProvider()
    let importer = FakeWorkspaceImporter(result: .failure(WorkspaceStoreError.invalidWorkingCopy(path: "/tmp/wc")))
    let viewModel = CheckoutViewModel(
        checkoutProvider: checkoutProvider,
        workspaceImporter: importer,
        infoProvider: FakeInfoProvider()
    )

    await viewModel.checkout(url: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/wc"), depth: .empty)

    XCTAssertEqual(
        viewModel.state,
        .error(String(describing: WorkspaceStoreError.invalidWorkingCopy(path: "/tmp/wc")))
    )
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter CheckoutViewModelTests
```

预期：编译失败，提示 `CheckoutViewModel`、`CheckoutProviding` 或 `WorkspaceImporting` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `CheckoutProviding` 协议：`checkout(url:to:depth:auth:)`。
- `WorkspaceImporting` 协议：`addExistingWorkingCopy(localPath:infoProvider:username:name:)`。
- `CheckoutViewState`：`.idle/.checkingOut/.completed(WorkingCopyRecord)/.error(String)`。
- `CheckoutViewModel.checkout(url:to:depth:auth:username:name:)`：置 `.checkingOut`，调用 checkout provider，成功后调用 workspace importer 导入；成功保存 `importedWorkingCopy` 并置 `.completed(record)`；失败置 `.error(String(describing: error))`，checkout 失败时不调用 importer。
- `extension SvnService: CheckoutProviding {}`。
- `extension WorkspaceStore: WorkspaceImporting {}`。

- [x] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter CheckoutViewModelTests
```

预期：URL checkout 和错误状态测试 PASS。

## 任务 2：远端目录条目 checkout URL 拼接

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/CheckoutViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/CheckoutViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `CheckoutViewModelTests` 中新增：

```swift
@MainActor
func testCheckoutRemoteDirectoryEntryBuildsUrlAndUsesDepth() async {
    let record = workingCopyRecord(path: "/tmp/src", repoURL: "file:///repo/trunk/src")
    let checkoutProvider = FakeCheckoutProvider()
    let importer = FakeWorkspaceImporter(result: .success(record))
    let viewModel = CheckoutViewModel(
        checkoutProvider: checkoutProvider,
        workspaceImporter: importer,
        infoProvider: FakeInfoProvider()
    )
    let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

    await viewModel.checkout(entry: entry, baseURL: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/src"), depth: .immediates)

    XCTAssertEqual(await checkoutProvider.recordedCalls(), [
        CheckoutCall(url: "file:///repo/trunk/src", destination: URL(fileURLWithPath: "/tmp/src"), depth: .immediates, auth: nil)
    ])
    XCTAssertEqual(viewModel.state, .completed(record))
}

@MainActor
func testCheckoutRemoteFileEntryIsRejectedBeforeProviderCall() async {
    let checkoutProvider = FakeCheckoutProvider()
    let importer = FakeWorkspaceImporter(result: .success(workingCopyRecord(path: "/tmp/readme", repoURL: "file:///repo/trunk/README.txt")))
    let viewModel = CheckoutViewModel(
        checkoutProvider: checkoutProvider,
        workspaceImporter: importer,
        infoProvider: FakeInfoProvider()
    )
    let entry = RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 10, revision: nil, author: nil, date: nil)

    await viewModel.checkout(entry: entry, baseURL: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/readme"), depth: .files)

    XCTAssertEqual(viewModel.state, .error("checkoutRequiresDirectory"))
    XCTAssertTrue(await checkoutProvider.recordedCalls().isEmpty)
    XCTAssertTrue(await importer.recordedCalls().isEmpty)
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter CheckoutViewModelTests
```

预期：新增条目 checkout 方法缺失或行为不符。

- [x] **步骤 3：编写最少实现代码**

实现：

- `checkout(entry:baseURL:to:depth:auth:username:name:)`。
- `RemoteEntry.kind` 不是 `.directory` 时置 `.error("checkoutRequiresDirectory")` 并返回。
- 复用私有 `remoteURL(baseURL:entryPath:)` 拼接 URL，再调用 `checkout(url:to:depth:auth:username:name:)`。

- [x] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter CheckoutViewModelTests
```

预期：全部 `CheckoutViewModelTests` PASS。

## 任务 3：全量验证与提交

**文件：**
- 上述全部文件

- [x] **步骤 1：运行目标测试**

运行：

```bash
swift test --filter CheckoutViewModelTests
```

预期：全部目标测试 PASS。

- [x] **步骤 2：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/ViewModels/CheckoutViewModel.swift Tests/MacSvnCoreTests/CheckoutViewModelTests.swift docs/superpowers/plans/2026-07-09-p2-repo-checkout-view-model.md
git commit -m "feat: add P2 repo checkout view model"
```
