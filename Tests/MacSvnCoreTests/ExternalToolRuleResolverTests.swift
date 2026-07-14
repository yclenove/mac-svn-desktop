import Foundation
import XCTest
@testable import MacSvnCore

final class ExternalToolRuleResolverTests: XCTestCase {
    func testAppSettingsDefaultsToNoExternalToolRules() {
        XCTAssertEqual(AppSettings().externalToolRules, [])
    }

    func testResolverPrefersCaseInsensitiveExactExtensionOverDefaultRule() {
        let defaultTool = tool(named: "Default Diff")
        let pdfTool = tool(named: "Preview Diff")
        let rules = [
            ExternalToolRule(purpose: .diff, fileExtensions: [], tool: defaultTool),
            ExternalToolRule(purpose: .diff, fileExtensions: [".PDF", "*.pdf"], tool: pdfTool)
        ]

        let resolved = ExternalToolRuleResolver.tool(
            for: .diff,
            path: "Reports/Quarterly.PdF",
            rules: rules,
            legacyDiffTool: nil
        )

        XCTAssertEqual(resolved, pdfTool)
    }

    func testResolverUsesLegacyDiffToolWhenNoNewDiffRuleMatches() {
        let legacy = tool(named: "Legacy Diff")

        let resolved = ExternalToolRuleResolver.tool(
            for: .diff,
            path: "Sources/App.swift",
            rules: [ExternalToolRule(
                purpose: .diff,
                fileExtensions: ["pdf"],
                tool: tool(named: "PDF Diff")
            )],
            legacyDiffTool: legacy
        )

        XCTAssertEqual(resolved, legacy)
    }

    func testResolverTreatsTortoiseStyleWildcardAsDefaultRule() {
        let defaultMerge = tool(named: "Default Merge")

        let resolved = ExternalToolRuleResolver.tool(
            for: .merge,
            path: "Sources/App.swift",
            rules: [ExternalToolRule(
                purpose: .merge,
                fileExtensions: ["*.*"],
                tool: defaultMerge
            )],
            legacyDiffTool: nil
        )

        XCTAssertEqual(resolved, defaultMerge)
    }

    func testResolverDoesNotFallBackAcrossExternalToolPurposes() {
        let diffTool = tool(named: "Diff")
        let rules = [ExternalToolRule(purpose: .diff, fileExtensions: [], tool: diffTool)]

        XCTAssertNil(ExternalToolRuleResolver.tool(
            for: .merge,
            path: "Sources/App.swift",
            rules: rules,
            legacyDiffTool: diffTool
        ))
        XCTAssertNil(ExternalToolRuleResolver.tool(
            for: .blame,
            path: "Sources/App.swift",
            rules: rules,
            legacyDiffTool: diffTool
        ))
    }

    private func tool(named name: String) -> ExternalDiffToolConfiguration {
        ExternalDiffToolConfiguration(
            name: name,
            executablePath: "/Applications/\(name).app/Contents/MacOS/tool"
        )
    }
}
