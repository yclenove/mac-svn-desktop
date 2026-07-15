import Foundation
import XCTest

final class ReadmeParityTests: XCTestCase {
    func testRootReadmePublishesCompleteTortoiseParityMatrix() throws {
        let readme = try repositoryDocument("README.md")
        let requiredRows = [
            "| DUG 能力域 | D01–D28 | 28/28 ✅ |",
            "| 主命令 | #1–#46 | 46/46 ✅ |",
            "| Show Log 动作 | L01–L20 | 20/20 ✅ |",
            "| 设置页 | S01–S13 | 13/13 ✅ |",
            "| Overlay 7/7 | 全状态与策略 | 7/7 ✅ |",
            "| **总计** | **全部必须行** | **114/114（100%）** |"
        ]

        for row in requiredRows {
            XCTAssertTrue(readme.contains(row), "README 缺少 Tortoise 对标矩阵行：\(row)")
        }
    }

    func testRootReadmeLinksParityEvidenceAndDropsObsoleteDeliveryClaims() throws {
        let readme = try repositoryDocument("README.md")
        let requiredLinks = [
            "docs/superpowers/specs/2026-07-10-tortoisesvn-feature-inventory.md",
            "docs/acceptance/H-tortoise-parity.md",
            "docs/acceptance/parity-coverage.json"
        ]
        let obsoleteClaims = [
            "feat/long-loop-full-delivery",
            "SRS 缺口 Loop 已收口并合入 `main`",
            "Sparkle 自动更新"
        ]

        for link in requiredLinks {
            XCTAssertTrue(readme.contains("](\(link))"), "README 缺少 Markdown 对标证据链接：\(link)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(link).path),
                "README 对标证据链接目标不存在：\(link)"
            )
        }
        for claim in obsoleteClaims {
            XCTAssertFalse(readme.contains(claim), "README 仍包含过时交付声明：\(claim)")
        }
    }

    func testDocumentationIndexPublishesCurrentParityStatus() throws {
        let index = try repositoryDocument("docs/README.md")
        let plan = try repositoryDocument(
            "docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md"
        )
        let latestCompletedGP = try XCTUnwrap(
            (1...6)
                .map { "GP.\($0)" }
                .last { plan.contains("- [x] **\($0)**") }
        )

        XCTAssertTrue(index.contains("114/114"), "文档索引缺少当前覆盖率")
        XCTAssertTrue(
            index.contains("\(latestCompletedGP) 已完成"),
            "文档索引未精确发布当前已完成阶段：\(latestCompletedGP)"
        )
        XCTAssertFalse(index.contains("执行中（T0.1 已完成）"), "文档索引仍停留在 T0.1")
        XCTAssertFalse(index.contains("| 骨架 |"), "文档索引仍将 H-tortoise 标为骨架")
    }

    func testPerfectClosurePublishesRequiredEvidence() throws {
        let plan = try repositoryDocument(
            "docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md"
        )
        let checklist = try repositoryDocument("docs/acceptance/H-tortoise-parity.md")
        let legacyChecklist = try repositoryDocument("docs/acceptance/H1-manual-checklist.md")
        let index = try repositoryDocument("docs/README.md")
        let changelog = try repositoryDocument("CHANGELOG.md")

        for criterion in [
            "P-INV", "P-STUB", "P-TEST", "P-H1", "P-COV", "P-PERF", "P-DOC", "P-SHIP",
        ] {
            XCTAssertTrue(plan.contains("- [x] **\(criterion)**"), "PERFECT 尚未勾选：\(criterion)")
        }
        XCTAssertTrue(
            plan.contains("**P-H1**：[H-Tortoise]"),
            "P-H1 未明确绑定当前 Tortoise 手工验收清单"
        )
        XCTAssertTrue(
            legacyChecklist.contains("已由 [H-Tortoise](H-tortoise-parity.md) 接替"),
            "旧 H1 清单未声明已被当前 Tortoise 验收清单接替"
        )
        XCTAssertTrue(index.contains("旧版，已由 H-Tortoise 接替"), "文档索引仍将旧 H1 清单标为待跑通")
        XCTAssertTrue(plan.contains("- [x] **GP.5**"), "Perfect Loop 尚未完成 GP.5")
        XCTAssertTrue(
            checklist.contains("- [x] CHANGELOG 收口「Tortoise 全量对标完成」"),
            "H-Tortoise 尚未记录最终 CHANGELOG 收口"
        )
        XCTAssertTrue(changelog.contains("Tortoise 全量对标完成"), "CHANGELOG 缺少最终收口条目")
    }

    func testPerfectLoopPublishesTerminalStopState() throws {
        let plan = try repositoryDocument(
            "docs/superpowers/plans/2026-07-10-tortoise-parity-perfect-loop.md"
        )
        let longLoop = try repositoryDocument(
            "docs/superpowers/plans/2026-07-11-codex-tortoise-parity-long-loop.md"
        )
        let checklist = try repositoryDocument("docs/acceptance/H-tortoise-parity.md")
        let index = try repositoryDocument("docs/README.md")
        let changelog = try repositoryDocument("CHANGELOG.md")

        XCTAssertTrue(plan.contains("- [x] **GP.6**"), "Perfect Loop 尚未完成 GP.6")
        XCTAssertFalse(plan.contains("- [ ] **GP."), "Perfect Loop 仍有未完成 GP 项")
        XCTAssertTrue(plan.contains("| Loop 状态 | **已停止（GP.6）** |"), "Perfect Loop 未发布终止态")
        XCTAssertTrue(longLoop.contains("| Loop 状态 | **已停止（GP.6）** |"), "Long Loop 未发布终止态")
        XCTAssertFalse(
            longLoop.contains("当前首个未完成 Wave/Backlog 项："),
            "Long Loop 仍声明存在待执行项"
        )
        for forbiddenInstruction in [
            "取 §5 Wave Backlog 首个未完成",
            "继续 GP.6",
        ] {
            XCTAssertFalse(
                plan.contains(forbiddenInstruction) || longLoop.contains(forbiddenInstruction),
                "终止态文档仍包含可执行 wake/续跑指令：\(forbiddenInstruction)"
            )
        }
        let executableWakePattern =
            #"(?:while\s+true|sleep\s+[0-9]+|(?:echo|printf)\s+[^\n]*AGENT_LOOP_WAKE_svnstudio_tortoise_parity)"#
        for (name, document) in [("Perfect Loop", plan), ("Long Loop", longLoop)] {
            XCTAssertNil(
                document.range(of: executableWakePattern, options: .regularExpression),
                "\(name) 仍包含可执行 wake 命令"
            )
        }
        XCTAssertTrue(longLoop.contains("### 1.2 完成队列（历史顺序）"), "Long Loop 仍将完成队列标为未完成")
        XCTAssertTrue(plan.contains("## 3. 历史 Loop 规则（已停用）"), "Perfect Loop 仍将历史规则标为主动执行")
        XCTAssertTrue(
            checklist.contains("- [x] 停止 `AGENT_LOOP_WAKE_svnstudio_tortoise_parity` 唤醒"),
            "H-Tortoise 尚未记录停止唤醒"
        )
        XCTAssertTrue(index.contains("GP.6 已完成，Loop 已停止"), "文档索引未发布最终停止状态")
        XCTAssertTrue(changelog.contains("GP.6：停止 Loop"), "CHANGELOG 缺少 GP.6 停止条目")
    }

    private func repositoryDocument(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
