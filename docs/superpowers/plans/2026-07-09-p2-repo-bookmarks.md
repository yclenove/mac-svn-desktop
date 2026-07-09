# P2 Repo Bookmarks 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P2 仓库 URL 收藏列表的 Core 非 UI 部分，覆盖 FR-RB-07：收藏 URL、持久化恢复、移除收藏，并让 `RepoBrowserViewModel` 暴露书签状态。

**架构：** 复用现有 `PersistenceStore<T>` JSON 存储模式，新增 `RepoBookmarkStore` actor 管理 `bookmarks.json` 等价数据文件。`RepoBrowserViewModel` 通过轻量 `RepoBookmarkManaging` 协议可选接入 store，不改变已有 list/preview 调用栈。

**技术栈：** Swift 6.1、Foundation Codable、XCTest concurrency、Observation。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  新增 `RepoBookmark`、`RepoBookmarkListFile`。
- 创建：`Sources/MacSvnCore/Services/RepoBookmarkStore.swift`
  新增 `RepoBookmarkStoreError`、`RepoBookmarkManaging`、`RepoBookmarkStore` actor。
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
  接入可选 `bookmarkManager`，新增 `bookmarks`、`loadBookmarks()`、`addBookmark(url:name:username:)`、`removeBookmark(id:)`。
- 创建：`Tests/MacSvnCoreTests/RepoBookmarkStoreTests.swift`
  覆盖缺失文件默认值、添加/恢复、重复 URL 更新、移除、空 URL 阻断。
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`
  覆盖 ViewModel 加载、添加、移除书签和错误状态。
- 创建：`docs/superpowers/plans/2026-07-09-p2-repo-bookmarks.md`
  记录本切片计划。

## 任务 1：RepoBookmarkStore 持久化

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/RepoBookmarkStore.swift`
- 创建：`Tests/MacSvnCoreTests/RepoBookmarkStoreTests.swift`

- [x] **步骤 1：编写失败的测试**

创建 `RepoBookmarkStoreTests`：

```swift
func testLoadMissingFileReturnsEmptyBookmarks() async throws {
    let store = makeStore()

    let bookmarks = try await store.load()

    XCTAssertEqual(bookmarks, [])
}

func testAddBookmarkPersistsAndReloads() async throws {
    let root = temporaryRoot()
    let store = makeStore(root: root)

    let bookmark = try await store.addBookmark(
        url: "https://svn.example.com/repo/trunk",
        name: "Main Repo",
        username: "yangchao"
    )

    XCTAssertEqual(bookmark.name, "Main Repo")
    XCTAssertEqual(bookmark.url, "https://svn.example.com/repo/trunk")
    XCTAssertEqual(bookmark.username, "yangchao")

    let reloadedStore = makeStore(root: root)
    let reloaded = try await reloadedStore.load()
    XCTAssertEqual(reloaded, [bookmark])
}

func testAddBookmarkWithExistingURLUpdatesRecordInsteadOfDuplicating() async throws {
    let store = makeStore()

    let first = try await store.addBookmark(url: "file:///repo", name: "Old", username: nil)
    let second = try await store.addBookmark(url: "file:///repo", name: "New", username: "u")
    let bookmarks = await store.bookmarks()

    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(bookmarks.count, 1)
    XCTAssertEqual(bookmarks.first?.name, "New")
    XCTAssertEqual(bookmarks.first?.username, "u")
}

func testRemoveBookmarkDeletesOnlyMatchingRecord() async throws {
    let store = makeStore()
    let first = try await store.addBookmark(url: "file:///one", name: nil, username: nil)
    let second = try await store.addBookmark(url: "file:///two", name: nil, username: nil)

    try await store.removeBookmark(id: first.id)
    let bookmarks = await store.bookmarks()

    XCTAssertEqual(bookmarks, [second])
}

func testAddBookmarkRejectsEmptyURL() async {
    let store = makeStore()

    do {
        _ = try await store.addBookmark(url: "  ", name: nil, username: nil)
        XCTFail("Expected empty URL error")
    } catch let error as RepoBookmarkStoreError {
        XCTAssertEqual(error, .emptyURL)
    } catch {
        XCTFail("Expected RepoBookmarkStoreError, got \(error)")
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter RepoBookmarkStoreTests`
预期：编译失败，提示 `RepoBookmarkStore` 或 `RepoBookmark` 未定义。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RepoBookmark: Codable, Equatable, Identifiable, Sendable`，字段：`id/name/url/username/addedAt/lastOpenedAt`。
- `RepoBookmarkListFile: Codable, Equatable, Sendable`，字段：`version/bookmarks`。
- `RepoBookmarkStoreError.emptyURL`。
- `RepoBookmarkManaging` 协议：`loadBookmarks()`、`addBookmark(url:name:username:)`、`removeBookmark(id:)`。
- `RepoBookmarkStore` actor：`load()`、`bookmarks()`、`addBookmark`、`removeBookmark`；URL 使用 trim 后字符串；默认 name 用 URL lastPathComponent，取不到时用 URL 本身。
- 同 URL 再添加时更新原 record 的 name/username/lastOpenedAt，不追加新记录。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter RepoBookmarkStoreTests`
预期：全部 PASS。

## 任务 2：RepoBrowserViewModel 书签状态

**文件：**
- 修改：`Sources/MacSvnCore/ViewModels/RepoBrowserViewModel.swift`
- 修改：`Tests/MacSvnCoreTests/RepoBrowserViewModelTests.swift`

- [x] **步骤 1：编写失败的测试**

在 `RepoBrowserViewModelTests` 中新增：

```swift
@MainActor
func testLoadBookmarksStoresBookmarkList() async {
    let bookmark = RepoBookmark(id: UUID(), name: "Main", url: "file:///repo", username: "u", addedAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1))
    let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
    let manager = FakeRepoBookmarkManager(bookmarks: [bookmark])
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, bookmarkManager: manager)

    await viewModel.loadBookmarks()

    XCTAssertEqual(viewModel.bookmarks, [bookmark])
    XCTAssertEqual(viewModel.bookmarkState, .loaded)
}

@MainActor
func testAddAndRemoveBookmarkRefreshesViewModelState() async {
    let bookmark = RepoBookmark(id: UUID(), name: "Main", url: "file:///repo", username: nil, addedAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1))
    let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
    let manager = FakeRepoBookmarkManager(bookmarks: [], addResult: bookmark)
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, bookmarkManager: manager)

    await viewModel.addBookmark(url: "file:///repo", name: "Main", username: nil)
    await viewModel.removeBookmark(id: bookmark.id)

    XCTAssertEqual(await manager.recordedAddCalls(), [RepoBookmarkAddCall(url: "file:///repo", name: "Main", username: nil)])
    XCTAssertEqual(await manager.recordedRemoveCalls(), [bookmark.id])
    XCTAssertEqual(viewModel.bookmarks, [])
    XCTAssertEqual(viewModel.bookmarkState, .loaded)
}

@MainActor
func testBookmarkFailureStoresError() async {
    let provider = FakeRepoBrowserProvider(listResult: .success([]), catResult: .success(Data()))
    let manager = FakeRepoBookmarkManager(bookmarks: [], loadError: RepoBookmarkStoreError.emptyURL)
    let viewModel = RepoBrowserViewModel(listProvider: provider, previewProvider: provider, bookmarkManager: manager)

    await viewModel.loadBookmarks()

    XCTAssertEqual(viewModel.bookmarkState, .error(String(describing: RepoBookmarkStoreError.emptyURL)))
}
```

- [x] **步骤 2：运行测试验证失败**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：编译失败或新增测试失败，提示 ViewModel 书签 API 未实现。

- [x] **步骤 3：编写最少实现代码**

实现：

- `RepoBookmarkState`: `.idle/.loading/.loaded/.error(String)`。
- `RepoBrowserViewModel` 新增 `bookmarkManager`、`bookmarks`、`bookmarkState`。
- 初始化器新增可选 `bookmarkManager` 参数。
- `loadBookmarks()`、`addBookmark(url:name:username:)`、`removeBookmark(id:)`：无 manager 时置 `.error("bookmarksUnavailable")`；成功后同步 `bookmarks` 并置 `.loaded`；失败置 `.error(String(describing: error))`。

- [x] **步骤 4：运行目标测试验证通过**

运行：`swift test --filter RepoBrowserViewModelTests`
预期：全部 PASS。

## 任务 3：全量验证与提交

- [x] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [x] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p2-repo-bookmarks.md
git commit -m "feat: add P2 repo bookmarks"
```
