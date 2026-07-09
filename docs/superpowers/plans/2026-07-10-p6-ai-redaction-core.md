# P6 AI Redaction Core 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 P6 `FR-AI-01~04` 和 `NFR-11` 建立 AI 发送前脱敏 Core：默认识别常见密钥/私钥形态，支持用户自定义正则，并提供“默认只发送 diff、默认启用脱敏”的隐私设置模型。

**架构：** 新增独立 `AIModels.swift` 与 `AIDataRedactor`。Redactor 是纯 Swift 服务，不依赖真实 LLM、Keychain 或 UI；后续 `LLMClient`、AI 提交说明、AI 评审、AI Chat 统一先调用它处理 prompt 输入。

**技术栈：** Swift Package、Foundation `NSRegularExpression`、XCTest、TDD。

---

## 文件结构

- 创建：`Sources/MacSvnCore/Models/AIModels.swift`
  - 定义 `AIPrivacySettings`、`AIRedactionMatch`、`AIRedactionResult`、`AIRedactionError`。
- 创建：`Sources/MacSvnCore/Services/AIDataRedactor.swift`
  - 实现默认密钥/私钥脱敏、自定义正则脱敏、错误处理。
- 创建：`Tests/MacSvnCoreTests/AIDataRedactorTests.swift`
  - 覆盖默认规则、自定义规则、非法正则与隐私默认值。

## 任务 1：默认密钥与私钥脱敏

**文件：**
- 创建：`Sources/MacSvnCore/Models/AIModels.swift`
- 创建：`Sources/MacSvnCore/Services/AIDataRedactor.swift`
- 测试：`Tests/MacSvnCoreTests/AIDataRedactorTests.swift`

- [x] **步骤 1：编写失败测试**

创建 `AIDataRedactorTests`：

```swift
import XCTest
@testable import MacSvnCore

final class AIDataRedactorTests: XCTestCase {
    func testRedactsDefaultSecretPatternsAndReportsMatches() throws {
        let redactor = AIDataRedactor()
        let input = """
        token=sk-1234567890abcdef
        github=ghp_abcdefghijklmnopqrstuvwxyz123456
        aws=AKIAABCDEFGHIJKLMNOP
        -----BEGIN PRIVATE KEY-----
        secret
        -----END PRIVATE KEY-----
        """

        let result = try redactor.redact(input)

        XCTAssertFalse(result.redactedText.contains("sk-1234567890abcdef"))
        XCTAssertFalse(result.redactedText.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        XCTAssertFalse(result.redactedText.contains("AKIAABCDEFGHIJKLMNOP"))
        XCTAssertFalse(result.redactedText.contains("BEGIN PRIVATE KEY"))
        XCTAssertEqual(result.matches.map(\.ruleID), [
            "openai-api-key",
            "github-token",
            "aws-access-key-id",
            "private-key-block"
        ])
        XCTAssertTrue(result.didRedact)
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter AIDataRedactorTests/testRedactsDefaultSecretPatternsAndReportsMatches
```

预期：编译失败，提示 `AIDataRedactor` 未定义。

- [x] **步骤 3：实现最少代码**

新增模型：

```swift
public struct AIRedactionMatch: Codable, Equatable, Sendable {
    public let ruleID: String
    public let matchCount: Int
}

public struct AIRedactionResult: Codable, Equatable, Sendable {
    public let redactedText: String
    public let matches: [AIRedactionMatch]
    public var didRedact: Bool { !matches.isEmpty }
}

public enum AIRedactionError: Error, Equatable, Sendable {
    case invalidPattern(String)
}
```

新增 `AIDataRedactor.redact(_:)`：

- replacement 固定为 `***REDACTED***`；
- 默认规则：
  - `openai-api-key`: `sk-[A-Za-z0-9_-]{8,}`
  - `github-token`: `ghp_[A-Za-z0-9_]{20,}`
  - `aws-access-key-id`: `AKIA[0-9A-Z]{16}`
  - `private-key-block`: `-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----`
- 按规则顺序应用；某规则有匹配才写入 `matches`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 2：自定义正则与非法正则

**文件：**
- 修改：`Sources/MacSvnCore/Services/AIDataRedactor.swift`
- 测试：`Tests/MacSvnCoreTests/AIDataRedactorTests.swift`

- [x] **步骤 1：编写失败测试**

在测试文件增加：

```swift
func testRedactsCustomPatternsAfterDefaultRules() throws {
    let redactor = AIDataRedactor()

    let result = try redactor.redact(
        "server=10.0.1.8 employee=YC123",
        customPatterns: ["\\b10\\.0\\.\\d+\\.\\d+\\b", "YC\\d+"]
    )

    XCTAssertEqual(result.redactedText, "server=***REDACTED*** employee=***REDACTED***")
    XCTAssertEqual(result.matches.map(\.ruleID), ["custom:0", "custom:1"])
}

func testInvalidCustomPatternThrows() {
    let redactor = AIDataRedactor()

    XCTAssertThrowsError(try redactor.redact("text", customPatterns: ["["])) { error in
        XCTAssertEqual(error as? AIRedactionError, .invalidPattern("["))
    }
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter "AIDataRedactorTests/testRedactsCustomPatternsAfterDefaultRules|AIDataRedactorTests/testInvalidCustomPatternThrows"
```

预期：编译失败或测试失败，因为 `redact(_:customPatterns:)` 尚未支持自定义规则。

- [x] **步骤 3：实现最少代码**

扩展 `redact` 签名：

```swift
public func redact(_ text: String, customPatterns: [String] = []) throws -> AIRedactionResult
```

将 `customPatterns.enumerated()` 追加为规则 ID `custom:<index>`。构造 `NSRegularExpression` 失败时抛 `.invalidPattern(pattern)`。

- [x] **步骤 4：运行目标测试验证通过**

运行同上目标测试，预期 PASS。

## 任务 3：隐私默认设置模型

**文件：**
- 修改：`Sources/MacSvnCore/Models/AIModels.swift`
- 测试：`Tests/MacSvnCoreTests/AIDataRedactorTests.swift`

- [x] **步骤 1：编写失败测试**

```swift
func testAIPrivacySettingsDefaultsToDiffOnlyAndRedactionEnabled() {
    let settings = AIPrivacySettings()

    XCTAssertTrue(settings.isRedactionEnabled)
    XCTAssertTrue(settings.sendsDiffOnly)
    XCTAssertEqual(settings.customRedactionPatterns, [])
}
```

- [x] **步骤 2：运行测试验证失败**

运行：

```bash
swift test --filter AIDataRedactorTests/testAIPrivacySettingsDefaultsToDiffOnlyAndRedactionEnabled
```

预期：编译失败，提示 `AIPrivacySettings` 未定义。

- [x] **步骤 3：实现最少代码**

新增：

```swift
public struct AIPrivacySettings: Codable, Equatable, Sendable {
    public var isRedactionEnabled: Bool
    public var sendsDiffOnly: Bool
    public var customRedactionPatterns: [String]

    public init(
        isRedactionEnabled: Bool = true,
        sendsDiffOnly: Bool = true,
        customRedactionPatterns: [String] = []
    ) {
        self.isRedactionEnabled = isRedactionEnabled
        self.sendsDiffOnly = sendsDiffOnly
        self.customRedactionPatterns = customRedactionPatterns
    }
}
```

- [x] **步骤 4：运行 AI 目标集合**

运行：

```bash
swift test --filter AIDataRedactorTests
```

预期：4 个测试全部 PASS。

## 任务 4：全量验证与提交

- [x] **步骤 1：运行目标集合**

```bash
swift test --filter "AIDataRedactorTests|CommitGuardServiceTests|CommitViewModelTests"
```

预期：0 failures。这里额外覆盖已有提交守护/提交 ViewModel，确认新 AI 脱敏 Core 没破坏现有提交前检查链路。

- [x] **步骤 2：运行全量验证**

```bash
swift test
git diff --check
```

预期：测试 0 failures，空白检查无输出。

- [x] **步骤 3：Commit**

```bash
git add Sources/MacSvnCore/Models/AIModels.swift \
  Sources/MacSvnCore/Services/AIDataRedactor.swift \
  Tests/MacSvnCoreTests/AIDataRedactorTests.swift \
  docs/superpowers/plans/2026-07-10-p6-ai-redaction-core.md
git diff --cached --check
git commit -m "feat: add P6 AI redaction core"
git status --short --branch
```

## 自检

- 覆盖 `NFR-11` 的 Core 基础：默认仅发送 diff 的设置模型、默认启用脱敏、密钥/私钥脱敏、自定义正则脱敏。
- 为 `FR-AI-01~04` 提供发送前安全入口。
- 不覆盖真实 `LLMClient`、Provider 网络请求、Keychain、UI 告知弹窗、token 计费保护或 AI 工具调用审计；这些属于后续 P6 切片。
