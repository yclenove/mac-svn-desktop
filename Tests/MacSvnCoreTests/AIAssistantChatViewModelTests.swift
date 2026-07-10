import XCTest
@testable import MacSvnCore

@MainActor
final class AIAssistantChatViewModelTests: XCTestCase {
    func testInferToolCallMapsStatusAndCommit() {
        let status = AIAssistantChatViewModel.inferToolCall(
            from: "查看状态",
            workingCopyPath: "/tmp/wc"
        )
        XCTAssertEqual(status?.name, AISVNToolName.svnStatus.rawValue)
        XCTAssertEqual(status?.arguments["wc"], "/tmp/wc")

        let commit = AIAssistantChatViewModel.inferToolCall(
            from: "执行提交",
            workingCopyPath: "/tmp/wc"
        )
        XCTAssertEqual(commit?.name, AISVNToolName.svnCommit.rawValue)

        XCTAssertNil(AIAssistantChatViewModel.inferToolCall(from: "你好", workingCopyPath: "/tmp/wc"))
        XCTAssertNil(AIAssistantChatViewModel.inferToolCall(from: "查看状态", workingCopyPath: nil))
    }
}
