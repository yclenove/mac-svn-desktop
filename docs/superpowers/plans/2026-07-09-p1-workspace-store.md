# P1 Workspace Store 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 实现 P1 工作副本列表核心状态层，覆盖 FR-WC-01 到 FR-WC-04 的非 UI 部分：校验合法 WC、添加/移除记录、持久化恢复、路径失效标记。

**架构：** 新增通用 `PersistenceStore<T: Codable>` 负责原子 JSON 读写；新增 `WorkspaceStore` actor 管理 `WorkingCopyRecord` 列表。UI 以后通过该 actor 获取数据；本切片不做文件选择器、拖拽或 SwiftUI 展示。

**技术栈：** Swift 6.1、Foundation Codable、XCTest。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  增加 `WorkingCopyRecord` 与 `WorkspaceListFile`，记录 id/name/localPath/repoURL/username/addedAt/lastOpenedAt/isValid/revision。
- 创建：`Sources/MacSvnCore/Persistence/PersistenceStore.swift`
  泛型 JSON 存储，支持缺失文件返回默认值、原子写入。
- 创建：`Sources/MacSvnCore/Services/WorkspaceStore.swift`
  actor，提供 `load()`、`addWorkingCopy(...)`、`removeWorkingCopy(id:)`、`records()`。
- 测试：`Tests/MacSvnCoreTests/PersistenceStoreTests.swift`
- 测试：`Tests/MacSvnCoreTests/WorkspaceStoreTests.swift`

## 任务 1：PersistenceStore JSON 读写

**文件：**
- 创建：`Sources/MacSvnCore/Persistence/PersistenceStore.swift`
- 测试：`Tests/MacSvnCoreTests/PersistenceStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

```swift
struct SamplePayload: Codable, Equatable {
    let version: Int
    let names: [String]
}

func testReadMissingFileReturnsDefaultValue() throws {
    let store = PersistenceStore<SamplePayload>(
        fileURL: temp.appendingPathComponent("sample.json"),
        defaultValue: SamplePayload(version: 1, names: [])
    )
    XCTAssertEqual(try store.load(), SamplePayload(version: 1, names: []))
}

func testSaveAndLoadRoundTripsJSON() throws {
    let store = PersistenceStore<SamplePayload>(fileURL: file, defaultValue: SamplePayload(version: 1, names: []))
    try store.save(SamplePayload(version: 1, names: ["中文", "space name"]))
    XCTAssertEqual(try store.load(), SamplePayload(version: 1, names: ["中文", "space name"]))
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter PersistenceStoreTests`
预期：编译失败，提示 `PersistenceStore` 未定义。

- [ ] **步骤 3：实现最少代码**

实现 `load()` 和 `save(_:)`。`save` 先写同目录临时文件，再用 `FileManager.replaceItemAt` 或 move 方式完成落盘。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter PersistenceStoreTests`
预期：PASS。

## 任务 2：WorkspaceStore 添加、移除与恢复

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 创建：`Sources/MacSvnCore/Services/WorkspaceStore.swift`
- 测试：`Tests/MacSvnCoreTests/WorkspaceStoreTests.swift`

- [ ] **步骤 1：编写失败测试**

测试覆盖：
- `addWorkingCopy` 拒绝不含 `.svn` 的目录并抛 `WorkspaceStoreError.invalidWorkingCopy`
- 合法 WC 添加后使用目录名作为默认 name，保存 repoURL/revision/username
- `removeWorkingCopy(id:)` 只移除记录，不删除磁盘目录
- 新建 store 后 `load()` 能恢复记录
- 恢复时如果目录已删除或不含 `.svn`，记录 `isValid=false`

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter WorkspaceStoreTests`
预期：编译失败，提示 `WorkspaceStore` 或模型未定义。

- [ ] **步骤 3：实现最少代码**

实现 `WorkingCopyRecord`、`WorkspaceListFile`、`WorkspaceStoreError` 和 `WorkspaceStore` actor。WC 合法性只检查目录存在且包含 `.svn` 子目录。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter WorkspaceStoreTests`
预期：PASS。

## 任务 3：全量验证与提交

- [ ] **步骤 1：运行全量验证**

运行：`swift test && git diff --check`
预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p1-workspace-store.md
git commit -m "feat: add P1 workspace store"
```
