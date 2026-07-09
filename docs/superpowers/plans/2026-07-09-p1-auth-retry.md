# P1 Auth Retry 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 `SvnService` 中实现 P1 认证失败后的凭据请求与一次重试，推进 FR-AU-01/02 的核心层闭环。

**架构：** 新增轻量 `CredentialProviding` 协议，由未来 UI 的凭据弹窗实现；当前核心层只在捕获 `SvnError.authentication` 后调用 provider 获取 `Credential` 并重试一次。`SvnBackend` 和 `AuthArguments` 继续负责密码安全传递，`SvnService` 不保存密码。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest concurrency。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  让 `update` 支持追加认证参数，默认保持现有无认证参数行为。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  让 `update` 协议方法接收 `auth: Credential?`。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  `update` 通过 `AuthArguments` 把密码写入 stdin，并传给 `ProcessRunning`。
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
  新增 `CredentialProviding` 协议，扩展 `SvnService` 初始化参数，并让 `update` 与 `commit` 在认证失败时请求凭据后重试一次。
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖 update 附加认证参数的 argv 顺序。
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
  覆盖 update 带认证凭据时 stdin 不泄漏到 argv。
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`
  扩展 mock backend 支持顺序抛错/成功，新增 fake credential provider，覆盖 update/commit 的认证重试和重试失败不再重复提示。
- 创建：`docs/superpowers/plans/2026-07-09-p1-auth-retry.md`
  记录此切片计划。

## 任务 1：SvnService 认证重试

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 修改：`Sources/MacSvnCore/Services/SvnService.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 修改：`Tests/MacSvnCoreTests/SvnServiceTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnServiceTests` 中新增：

```swift
func testUpdatePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.updateErrors = [.authentication]
    backend.updateResult = UpdateSummary(updated: 1, revision: Revision(9))
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)
    let wc = URL(fileURLWithPath: "/tmp/wc")

    let summary = try await service.update(wc: wc)

    XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
    XCTAssertEqual(provider.requestedWorkingCopies, [wc])
    XCTAssertEqual(backend.calls.map(\.name), ["update", "update"])
    XCTAssertEqual(backend.updateCredentials, [nil, Credential(username: "u", password: "p")])
}

func testCommitPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
    let backend = MockSvnBackend()
    backend.statusResult = [
        FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
    ]
    backend.commitErrors = [.authentication]
    backend.commitResult = Revision(42)
    let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
    let service = SvnService(backend: backend, credentialProvider: provider)

    let revision = try await service.commit(
        wc: URL(fileURLWithPath: "/tmp/wc"),
        paths: ["a.txt"],
        message: "fix",
        auth: nil
    )

    XCTAssertEqual(revision, Revision(42))
    XCTAssertEqual(provider.requestedWorkingCopies, [URL(fileURLWithPath: "/tmp/wc")])
    XCTAssertEqual(backend.calls.map(\.name), ["status", "commit", "commit"])
    XCTAssertEqual(backend.commitCredentials, [nil, Credential(username: "u", password: "p")])
}
```

同时新增重试失败测试：第一次和第二次 commit 都抛 `.authentication` 时，provider 只被调用一次，最终仍抛 `.authentication`。

- [ ] **步骤 2：运行测试验证失败**

同时在 `SvnCommandBuilderTests` 中新增 update auth argv 断言，在 `SvnCliBackendTests` 中新增 update auth stdin 断言。

运行：

```bash
swift test --filter SvnCommandBuilderTests
swift test --filter SvnCliBackendTests
swift test --filter SvnServiceTests
```

预期：编译失败或新增测试失败，提示 update auth / `SvnService(backend:credentialProvider:)` / credential tracking 未实现。

- [ ] **步骤 3：编写最少实现代码**

在 `SvnService.swift` 中新增：

```swift
public protocol CredentialProviding: Sendable {
    func credential(for wc: URL) async throws -> Credential?
}
```

`SvnCommandBuilder.update` 增加 `authArguments` 默认参数，`SvnBackend.update` 与所有实现/测试桩增加 `auth: Credential?`。`SvnService` 保存可选 provider。`update` 调用 backend 时初次 `auth: nil`，捕获 `.authentication` 后请求 provider；若 provider 返回凭据，则用该凭据重试一次。`commit` 沿用传入 `auth` 作为第一次调用凭据，失败后用 provider 返回的凭据重试一次。第二次失败原样抛出。

- [ ] **步骤 4：运行目标测试验证通过**

运行：

```bash
swift test --filter SvnCommandBuilderTests
swift test --filter SvnCliBackendTests
swift test --filter SvnServiceTests
```

预期：三个测试类全部 PASS。

## 任务 2：全量验证与提交

- [ ] **步骤 1：运行全量验证**

运行：

```bash
swift test
git diff --check
```

预期：全部测试 PASS，diff 检查无输出。

- [ ] **步骤 2：Commit**

```bash
git add Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Sources/MacSvnCore/Backend/SvnBackend.swift Sources/MacSvnCore/Backend/SvnCliBackend.swift Sources/MacSvnCore/Services/SvnService.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift Tests/MacSvnCoreTests/SvnServiceTests.swift docs/superpowers/plans/2026-07-09-p1-auth-retry.md
git commit -m "feat: add P1 auth retry service flow"
```
