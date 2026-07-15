import Foundation
import XCTest

final class ModalDismissalAccessibilityTests: XCTestCase {
    func testEveryCustomModalUsesSharedDismissChrome() throws {
        var sheetCount = 0
        var popoverCount = 0

        for (url, source) in try Self.readAppSourceFiles() {
            for marker in [".sheet(", ".fullScreenCover("] {
                for block in try Self.presentationActionBlocks(marker: marker, in: source) {
                    sheetCount += 1
                    XCTAssertTrue(
                        block.contains(".macSvnDismissibleSheet()"),
                        "\(url.lastPathComponent) has a \(marker) presentation without shared dismiss chrome"
                    )
                }
            }
            for block in try Self.presentationActionBlocks(marker: ".popover(", in: source) {
                popoverCount += 1
                XCTAssertTrue(
                    block.contains(".macSvnDismissiblePopover()"),
                    "\(url.lastPathComponent) has a popover without an explicit close control"
                )
            }
        }

        XCTAssertGreaterThan(sheetCount, 0)
        XCTAssertGreaterThan(popoverCount, 0)
    }

    func testSharedDismissChromeIsVisibleAccessibleAndKeyboardOperable() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertTrue(source.contains(".help(\"关闭\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"关闭弹窗\")"))
        XCTAssertTrue(source.contains("@Environment(\\.dismiss)"))
    }

    func testEveryAlertAndConfirmationDialogExposesExplicitCancelAction() throws {
        for (url, source) in try Self.readAppSourceFiles() {
            for marker in [".alert(", ".confirmationDialog("] {
                let actionBlocks = try Self.presentationActionBlocks(marker: marker, in: source)
                for block in actionBlocks {
                    XCTAssertTrue(
                        block.contains("role: .cancel"),
                        "\(url.lastPathComponent) has a \(marker) presentation without an explicit cancel action"
                    )
                }
            }
        }
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func readAppSourceFiles() throws -> [(url: URL, source: String)] {
        let sourceRoot = repoRoot.appendingPathComponent("Sources/MacSvnApp")
        return try FileManager.default.recursiveSwiftFiles(below: sourceRoot).map { url in
            (url, try String(contentsOf: url, encoding: .utf8))
        }
    }

    private static func presentationActionBlocks(marker: String, in source: String) throws -> [String] {
        var blocks: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            guard let actionStart = source.range(
                of: ") {",
                range: markerRange.upperBound..<source.endIndex
            ) else {
                throw PresentationScanError.missingActionBlock(marker)
            }

            var depth = 1
            var cursor = actionStart.upperBound
            while cursor < source.endIndex, depth > 0 {
                switch source[cursor] {
                case "{": depth += 1
                case "}": depth -= 1
                default: break
                }
                cursor = source.index(after: cursor)
            }
            guard depth == 0 else {
                throw PresentationScanError.unbalancedActionBlock(marker)
            }

            blocks.append(String(source[actionStart.upperBound..<source.index(before: cursor)]))
            searchStart = cursor
        }

        return blocks
    }

}

private enum PresentationScanError: Error {
    case missingActionBlock(String)
    case unbalancedActionBlock(String)
}

private extension FileManager {
    func recursiveSwiftFiles(below root: URL) -> [URL] {
        guard let enumerator = enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
