import XCTest
@testable import MacSvnCore

final class IgnorePatternPolicyTests: XCTestCase {
    func testExactFilenameUsesBasename() {
        XCTAssertEqual(
            IgnorePatternPolicy.pattern(forRelativePath: "src/build/cache.tmp", kind: .exactFilename),
            "cache.tmp"
        )
    }

    func testExtensionWildcard() {
        XCTAssertEqual(
            IgnorePatternPolicy.pattern(forRelativePath: "logs/app.log", kind: .extensionWildcard),
            "*.log"
        )
        XCTAssertNil(
            IgnorePatternPolicy.pattern(forRelativePath: "Makefile", kind: .extensionWildcard)
        )
        XCTAssertNil(
            IgnorePatternPolicy.pattern(forRelativePath: ".env", kind: .extensionWildcard)
        )
    }

    func testParentTarget() {
        XCTAssertEqual(IgnorePatternPolicy.parentTarget(forRelativePath: "a.txt"), ".")
        XCTAssertEqual(IgnorePatternPolicy.parentTarget(forRelativePath: "src/a.txt"), "src")
        XCTAssertEqual(IgnorePatternPolicy.parentTarget(forRelativePath: "src/nested/b.txt"), "src/nested")
    }

    func testMergeAppendsUniquePatterns() {
        let merged = IgnorePatternPolicy.mergeIgnoreProperty(
            existing: "*.o\nbuild\n",
            patterns: ["*.o", "*.log", "tmp"]
        )
        XCTAssertEqual(merged, "*.o\nbuild\n*.log\ntmp\n")
    }

    func testPlansGroupByParent() {
        let plans = IgnorePatternPolicy.plans(
            relativePaths: ["a.txt", "src/b.log", "src/c.log", "Makefile"],
            kind: .extensionWildcard
        )
        // Makefile 无扩展名被跳过；a.txt → 根 *.txt；src 下两个 .log → 一条 *.log
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.first { $0.target == "." }?.patterns, ["*.txt"])
        XCTAssertEqual(plans.first { $0.target == "src" }?.patterns, ["*.log"])
    }

    func testPlansExactKeepsPerFilePatterns() {
        let plans = IgnorePatternPolicy.plans(
            relativePaths: ["a.txt", "src/b.txt"],
            kind: .exactFilename
        )
        XCTAssertEqual(
            Set(plans.map(\.target)),
            Set([".", "src"])
        )
        XCTAssertEqual(
            plans.first { $0.target == "." }?.patterns,
            ["a.txt"]
        )
    }
}
