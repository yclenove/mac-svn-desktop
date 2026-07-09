# P1 Backend Execution 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 P1 的纯模型/解析器推进到可执行的 SVN CLI 后端边界，实现 `ProcessRunning`、`ProcessRunner`、`SvnBackend` 和 `SvnCliBackend` 的首批真实方法。

**架构：** `ProcessRunner` 是唯一启动子进程的模块，负责环境变量、stdin、超时和输出采集；`SvnCliBackend` 只组装参数、调用 `ProcessRunning`、解析结果并映射错误。首批只实现 `version/status/update/commit`，为后续 `SvnService` 和 SwiftUI 页面提供真实数据来源。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest、Foundation `Process`。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Process/ProcessRunning.swift`
  定义 `ProcessResult` 和 `ProcessRunning` 协议。
- 创建：`Sources/MacSvnCore/Process/ProcessRunner.swift`
  实现真实 `Process` 执行，覆盖环境变量、stdin、currentDirectory、timeout 和 stdout/stderr 采集。
- 创建：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  定义 P1 首批 `version/status/update/commit` 协议。
- 创建：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 CLI 后端首批方法，复用已有 `SvnCommandBuilder`、`AuthArguments`、parsers、`SvnErrorMapper`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  新增 `version()`，并让 command 可携带 `stdin`。
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  为 `SvnVersion` 添加字符串解析，保持纯函数可测。
- 测试：`Tests/MacSvnCoreTests/SvnVersionTests.swift`
- 测试：`Tests/MacSvnCoreTests/ProcessRunnerTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`

## 任务 1：版本解析与 version 命令构造

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 测试：`Tests/MacSvnCoreTests/SvnVersionTests.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`

- [ ] **步骤 1：编写失败的版本解析和 version 命令测试**

```swift
import XCTest
@testable import MacSvnCore

final class SvnVersionTests: XCTestCase {
    func testParsesQuietVersionOutput() throws {
        XCTAssertEqual(try SvnVersion.parse("1.14.5\n"), SvnVersion(major: 1, minor: 14, patch: 5))
    }

    func testRejectsInvalidVersionOutput() {
        XCTAssertThrowsError(try SvnVersion.parse("not-a-version")) { error in
            XCTAssertEqual(error as? SvnError, .parse(detail: "Unable to parse svn version: not-a-version"))
        }
    }
}
```

在 `SvnCommandBuilderTests` 增加：

```swift
func testVersionUsesQuietFlag() {
    let command = SvnCommandBuilder.version()
    XCTAssertEqual(command.arguments, ["--version", "--quiet"])
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnVersionTests && swift test --filter SvnCommandBuilderTests/testVersionUsesQuietFlag`
预期：FAIL 或编译失败，提示 `SvnVersion.parse` 或 `SvnCommandBuilder.version` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `SvnVersion.parse(_:)` 与 `SvnCommandBuilder.version()`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnVersionTests && swift test --filter SvnCommandBuilderTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Models/SvnModels.swift Sources/MacSvnCore/Backend/SvnCommandBuilder.swift Tests/MacSvnCoreTests/SvnVersionTests.swift Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift
git commit -m "feat: add svn version parsing and command"
```

## 任务 2：实现 ProcessRunning 与真实 ProcessRunner

**文件：**
- 创建：`Sources/MacSvnCore/Process/ProcessRunning.swift`
- 创建：`Sources/MacSvnCore/Process/ProcessRunner.swift`
- 测试：`Tests/MacSvnCoreTests/ProcessRunnerTests.swift`

- [ ] **步骤 1：编写失败的 ProcessRunner 行为测试**

```swift
import XCTest
@testable import MacSvnCore

final class ProcessRunnerTests: XCTestCase {
    func testRunCapturesStdoutStderrAndExitCode() async throws {
        let runner = ProcessRunner()

        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2; exit 7"],
            stdin: nil,
            currentDirectory: nil,
            timeout: 5
        )

        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "out")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertGreaterThanOrEqual(result.duration, 0)
    }

    func testRunWritesStdin() async throws {
        let runner = ProcessRunner()

        let result = try await runner.run(
            executable: "/bin/cat",
            arguments: [],
            stdin: Data("hello stdin".utf8),
            currentDirectory: nil,
            timeout: 5
        )

        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "hello stdin")
    }

    func testRunTimesOutAndThrowsNetworkError() async {
        let runner = ProcessRunner()

        do {
            _ = try await runner.run(
                executable: "/bin/sleep",
                arguments: ["5"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch let error as SvnError {
            guard case .network(let detail) = error else {
                return XCTFail("Expected network timeout, got \\(error)")
            }
            XCTAssertTrue(detail.contains("timed out"))
        } catch {
            XCTFail("Expected SvnError, got \\(error)")
        }
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter ProcessRunnerTests`
预期：FAIL 或编译失败，提示 `ProcessRunner` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `ProcessResult`、`ProcessRunning`、`ProcessRunner.run`。设置 `LC_ALL=C`、`LANG=C`，PATH 追加 Homebrew 路径；stdout/stderr 用 pipe `readDataToEndOfFile` 采集；timeout 触发 `terminate()` 并抛 `.network(detail:)`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter ProcessRunnerTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore/Process Tests/MacSvnCoreTests/ProcessRunnerTests.swift
git commit -m "feat: add process runner"
```

## 任务 3：实现 SvnBackend 协议与 SvnCliBackend 首批方法

**文件：**
- 创建：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 创建：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendTests.swift`

- [ ] **步骤 1：编写失败的 SvnCliBackend 测试**

```swift
import Foundation
import XCTest
@testable import MacSvnCore

final class SvnCliBackendTests: XCTestCase {
    func testVersionRunsQuietVersionAndParsesOutput() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("1.14.5\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let version = try await backend.version()

        XCTAssertEqual(version, SvnVersion(major: 1, minor: 14, patch: 5))
        XCTAssertEqual(runner.calls.single?.arguments, ["--version", "--quiet"])
    }

    func testStatusRunsInWorkingCopyAndParsesXml() async throws {
        let xml = """
        <status><target path="."><entry path="a.txt"><wc-status item="modified" revision="3"/></entry></target></status>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let statuses = try await backend.status(wc: wc)

        XCTAssertEqual(statuses, [FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(3), isTreeConflict: false)])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testCommitPassesAuthStdinAndParsesRevision() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("Committed revision 42.\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let revision = try await backend.commit(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["a.txt"],
            message: "修复：登录超时",
            auth: Credential(username: "u", password: "p")
        )

        XCTAssertEqual(revision, Revision(42))
        XCTAssertEqual(runner.calls.single?.stdin, Data("p\n".utf8))
        XCTAssertEqual(runner.calls.single?.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "修复：登录超时",
            "--username", "u", "--password-from-stdin",
            "a.txt"
        ])
    }

    func testNonZeroExitMapsSvnError() async {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 1, stdout: Data(), stderr: "svn: E170001: auth failed", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        do {
            _ = try await backend.version()
            XCTFail("Expected authentication error")
        } catch let error as SvnError {
            XCTAssertEqual(error, .authentication)
        } catch {
            XCTFail("Expected SvnError, got \\(error)")
        }
    }
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let stdin: Data?
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], stdin: Data?, currentDirectory: String?, timeout: TimeInterval) async throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments, stdin: stdin, currentDirectory: currentDirectory, timeout: timeout))
        return result
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendTests`
预期：FAIL 或编译失败，提示 `SvnCliBackend` 或 `ProcessRunning` 未定义。

- [ ] **步骤 3：编写最少实现代码**

实现 `SvnBackend` 的 `version/status/update/commit`，并在 `SvnCliBackend` 中统一检查非零 exit code：非零时调用 `SvnErrorMapper.map(exitCode:stderr:)`。`commit` 参数需将认证参数放在 message 后、paths 前，避免密码进入 argv。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnCliBackendTests`
预期：PASS。

- [ ] **步骤 5：运行全部测试并 Commit**

运行：`swift test`
预期：所有测试 PASS。

```bash
git add Sources/MacSvnCore/Backend/SvnBackend.swift Sources/MacSvnCore/Backend/SvnCliBackend.swift Tests/MacSvnCoreTests/SvnCliBackendTests.swift
git commit -m "feat: add svn cli backend core methods"
```
