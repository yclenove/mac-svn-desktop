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
                        block.contains(".macSvnDismissibleSheet"),
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

        XCTAssertEqual(sheetCount, 28)
        XCTAssertEqual(popoverCount, 4)
    }

    func testSharedDismissChromeIsVisibleAccessibleAndKeyboardOperable() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Image(systemName: \"xmark.circle.fill\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertTrue(source.contains(".help(\"关闭\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"关闭弹窗\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"macSvn.modal.close\")"))
        XCTAssertTrue(source.contains(".frame(width: 30, height: 30)"))
        XCTAssertTrue(source.contains("@Environment(\\.dismiss)"))
    }

    func testSharedSheetDismissalRoutesCloseAndEscapeThroughOnePolicy() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent(
                "Sources/MacSvnApp/Components/MacSvnDismissiblePresentation.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let preventsDismissal: Bool"))
        XCTAssertTrue(source.contains("let onDismissalBlocked: () -> Void"))
        XCTAssertTrue(source.contains("private func requestDismiss()"))
        XCTAssertTrue(source.contains("Button(action: requestDismiss)"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertTrue(source.contains("if preventsDismissal"))
        XCTAssertTrue(source.contains("onDismissalBlocked()"))
        XCTAssertTrue(source.contains(".interactiveDismissDisabled(preventsDismissal)"))
        XCTAssertTrue(
            source.contains(
                "func macSvnDismissibleSheet(\n        preventsDismissal: Bool = false,\n        onDismissalBlocked: @escaping () -> Void = {}"
            )
        )
    }

    func testDirtyAuxiliarySheetsShareAbandonConfirmationForEveryDismissAction() throws {
        let contracts = [
            (
                file: "MacSvnPropertiesView.swift",
                snapshot: "ExternalsEditorDraftSnapshot",
                requestDismissal: "requestExternalsDismissal",
                preventsDismissal: "externalsPreventsDismissal"
            ),
            (
                file: "MacSvnLocksView.swift",
                snapshot: "GetLockDraftSnapshot",
                requestDismissal: "requestGetLockDismissal",
                preventsDismissal: "getLockPreventsDismissal"
            ),
            (
                file: "MacSvnShelveView.swift",
                snapshot: "CreateShelfDraftSnapshot",
                requestDismissal: "requestCreateShelfDismissal",
                preventsDismissal: "createShelfPreventsDismissal"
            ),
            (
                file: "MacSvnShelveView.swift",
                snapshot: "PatchDraftSnapshot",
                requestDismissal: "requestPatchDismissal",
                preventsDismissal: "patchPreventsDismissal"
            ),
        ]

        for contract in contracts {
            let source = try Self.readFeatureSource(named: contract.file)
            XCTAssertTrue(source.contains(contract.snapshot), "\(contract.file) needs an initial draft snapshot")
            XCTAssertTrue(source.contains("Button(\"取消\") { \(contract.requestDismissal)() }"))
            XCTAssertTrue(
                source.contains(
                    ".macSvnDismissibleSheet(\n                    preventsDismissal: \(contract.preventsDismissal),\n                    onDismissalBlocked: \(contract.requestDismissal)"
                )
            )
            XCTAssertTrue(source.contains("\"放弃未保存更改？\""))
            XCTAssertTrue(source.contains("Button(\"继续编辑\", role: .cancel)"))
            XCTAssertTrue(source.contains("Button(\"放弃更改\", role: .destructive)"))
        }
    }

    func testGetLockSheetStaysPresentedUntilAsyncLockSucceeds() throws {
        let source = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        let sheet = try Self.sourceSection(startingAt: "private var getLockSheet", in: source)

        XCTAssertFalse(sheet.contains("showGetLockSheet = false\n                    Task"))
        XCTAssertTrue(sheet.contains("Task { await runGetLock() }"))
        XCTAssertTrue(sheet.contains(".disabled") && sheet.contains("isBusy"))
        XCTAssertTrue(source.contains("guard case .loaded = viewModel?.state else { return }"))
        XCTAssertTrue(source.contains("completeGetLockSubmission()"))
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

    private static func readFeatureSource(named fileName: String) throws -> String {
        try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }

    private static func sourceSection(startingAt marker: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let remaining = source[start...]
        guard let nextDeclaration = remaining.dropFirst(marker.count).range(of: "\n    private ") else {
            return String(remaining)
        }
        return String(source[start..<nextDeclaration.lowerBound])
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
