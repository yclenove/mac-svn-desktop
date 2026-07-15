import Foundation
import XCTest

final class ModalDismissalAccessibilityTests: XCTestCase {
    func testEveryCustomModalUsesSharedDismissChrome() throws {
        let sources = try Self.readAppSources()
        let sheetCount = Self.occurrenceCount(of: ".sheet(", in: sources)
            + Self.occurrenceCount(of: ".fullScreenCover(", in: sources)
        let popoverCount = Self.occurrenceCount(of: ".popover(", in: sources)

        XCTAssertGreaterThan(sheetCount, 0)
        XCTAssertGreaterThan(popoverCount, 0)
        XCTAssertEqual(
            Self.occurrenceCount(of: ".macSvnDismissibleSheet()", in: sources),
            sheetCount,
            "Every sheet must expose the shared visible close control and Escape shortcut."
        )
        XCTAssertEqual(
            Self.occurrenceCount(of: ".macSvnDismissiblePopover()", in: sources),
            popoverCount,
            "Every popover must expose an explicit close control."
        )
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

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func readAppSources() throws -> String {
        let sourceRoot = repoRoot.appendingPathComponent("Sources/MacSvnApp")
        let urls = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        ) + FileManager.default.recursiveSwiftFiles(
            below: sourceRoot.appendingPathComponent("App")
        ) + FileManager.default.recursiveSwiftFiles(
            below: sourceRoot.appendingPathComponent("Components")
        ) + FileManager.default.recursiveSwiftFiles(
            below: sourceRoot.appendingPathComponent("Features")
        )
        let uniqueURLs = Array(Set(urls.filter { $0.pathExtension == "swift" }))
        return try uniqueURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
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
