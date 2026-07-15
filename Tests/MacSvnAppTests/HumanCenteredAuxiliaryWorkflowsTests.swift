import Foundation
import XCTest
@testable import MacSvnApp

final class HumanCenteredAuxiliaryWorkflowsTests: XCTestCase {
    func testAuxiliaryMetricsKeepMasterAndDetailReadable() {
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.toolbarHeight, 48)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.masterWidth, 300)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMinimumWidth, 280)
        XCTAssertLessThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMaximumWidth, 340)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth, 420)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.feedbackHeight, 30)
    }

    func testAuxiliaryPathPresentationOnlyRelativizesTargetsInsideWorkingCopy() {
        let workingCopy = URL(fileURLWithPath: "/tmp/wc", isDirectory: true)

        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc", workingCopy: workingCopy),
            "."
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc/src/a.swift",
                workingCopy: workingCopy
            ),
            "src/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc-other/a.swift",
                workingCopy: workingCopy
            ),
            "/tmp/wc-other/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("src/a.swift", workingCopy: workingCopy),
            "src/a.swift"
        )
    }

    func testAuxiliaryPathPresentationNamesWorkingCopyRootWithoutExposingDot() {
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "."), "工作副本根目录")
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "src/a.swift"), "src/a.swift")
    }

    func testPropertiesUseSearchableStableMasterDetailAndVisibleEditorAction() throws {
        let source = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")

        XCTAssertTrue(source.contains("@State private var searchText"))
        XCTAssertTrue(source.contains("@State private var selectedTemplateName"))
        XCTAssertTrue(source.contains("private var propertiesToolbar"))
        XCTAssertTrue(source.contains("private var propertiesWorkspace"))
        XCTAssertTrue(source.contains("private var propertiesMasterPane"))
        XCTAssertTrue(source.contains("private var propertyInspector"))
        XCTAssertTrue(source.contains("private var propertyList"))
        XCTAssertTrue(source.contains("private var propertyEditor"))
        XCTAssertTrue(source.contains("private var propertyEditorActions"))
        XCTAssertTrue(source.contains("Picker(\"模板\", selection: $selectedTemplateName)"))
        XCTAssertTrue(source.contains("HStack(spacing: 0)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains(".truncationMode(.middle)"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有属性\""))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryPathPresentation.relativePath("))
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    private static func readFeatureSource(named fileName: String) throws -> String {
        try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
