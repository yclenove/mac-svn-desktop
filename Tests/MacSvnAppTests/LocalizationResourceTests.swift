import Foundation
import XCTest

final class LocalizationResourceTests: XCTestCase {
    func testAuxiliarySearchAndReloadLabelsHaveEnglishTranslations() throws {
        let translations = try Self.englishTranslations()

        XCTAssertEqual(translations["搜索搁置记录"], "Search shelf records")
        XCTAssertEqual(translations["没有匹配的搁置记录"], "No matching shelf records")
        XCTAssertEqual(translations["换个关键词后重试"], "Try a different search term")
        XCTAssertEqual(translations["重新加载设置"], "Reload settings")
    }

    func testEnglishLocalizationCoversStaticSwiftUIControlLabels() throws {
        let translations = try Self.englishTranslations()
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|Button|Toggle|Picker|Label|Section|Menu|GroupBox|TextField|SecureField|ContentUnavailableView|Link|LabeledContent|DisclosureGroup|TableColumn|CommandMenu|Window|Stepper)\(\s*\"((?:[^\"\\\n]|\\.)*)\""#
        )
        var keys: Set<String> = []

        for fileURL in try Self.swiftUISourceFiles() {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            pattern.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let match,
                      let keyRange = Range(match.range(at: 1), in: source) else { return }
                let sourceLiteral = String(source[keyRange])
                guard Self.containsHanCharacter(sourceLiteral) else { return }
                guard let key = Self.localizedFormatKey(from: sourceLiteral) else { return }
                keys.insert(key)
            }
        }

        XCTAssertGreaterThan(keys.count, 400)
        try Self.assertEnglishTranslations(for: keys, in: translations)
    }

    func testEnglishLocalizationCoversExtractedSwiftUITextKeys() throws {
        let translations = try Self.englishTranslations()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SVNStudioLocalization-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "extractLocStrings", "-u", "-SwiftUI", "-o", outputDirectory.path,
        ] + (try Self.swiftUISourceFiles()).map(\.path)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let extracted = try Self.readStringsDictionary(
            at: outputDirectory.appendingPathComponent("Localizable.strings")
        )
        let chineseKeys = Set(extracted.keys.filter(Self.containsHanCharacter))
        XCTAssertGreaterThan(chineseKeys.count, 150)
        try Self.assertEnglishTranslations(for: chineseKeys, in: translations)
        for (key, sourceValue) in extracted {
            let translatedValue = try XCTUnwrap(translations[key], "Missing extracted key: \(key)")
            XCTAssertEqual(
                Self.formatPlaceholders(in: translatedValue),
                Self.formatPlaceholders(in: sourceValue),
                "Format placeholders changed for key: \(key)"
            )
        }
    }

    func testEnglishLocalizationIsPackagedBySwiftPMManualBuilderAndXcodeApp() throws {
        let package = try Self.readRepoSource(at: "Package.swift")
        let builder = try Self.readRepoSource(at: "scripts/build-macos-app.sh")
        let project = try Self.readRepoSource(at: "MacSVN.xcodeproj/project.pbxproj")

        XCTAssertTrue(package.contains("resources: [.process(\"Resources\")]"))
        XCTAssertTrue(builder.contains("Sources/MacSvnDesktopApp/Resources/en.lproj"))
        XCTAssertTrue(project.contains("Localizable.strings in Resources"))
        XCTAssertTrue(project.contains("en.lproj/Localizable.strings"))
    }

    func testSelectedLocaleWrapsWorkspaceSettingsAboutAndMenuBarScenes() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift"
        )

        XCTAssertTrue(source.contains("struct MacSvnLocalizedContent<Content: View>: View"))
        XCTAssertTrue(source.contains("MacSvnLocalizedContent(session: session)"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "MacSvnLocalizedContent(session: session)").count - 1,
            3
        )
        XCTAssertTrue(source.contains("MacSvnSettingsView(session: session)"))
        XCTAssertTrue(source.contains("MacSvnAboutView()"))
        XCTAssertTrue(source.contains("MacSvnMenuBarExtraContent("))
    }

    func testDynamicNavigationLabelsUseLocalizedStringKeys() throws {
        let shell = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift"
        )
        let settings = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift"
        )

        XCTAssertTrue(shell.contains("Text(LocalizedStringKey(mode.title))"))
        XCTAssertTrue(shell.contains("Text(LocalizedStringKey(selectedMode.title))"))
        XCTAssertTrue(settings.contains("Text(LocalizedStringKey(category.title))"))
        XCTAssertFalse(shell.contains("Label(mode.title,"))
        XCTAssertFalse(settings.contains("Label(category.title,"))
    }

    func testDynamicStatusMessagesUseLocalizedKeysAndHaveEnglishTranslations() throws {
        let translations = try Self.englishTranslations()
        let fieldNames = ["statusText", "errorText", "statusBanner", "infoError", "externalStatusText"]
        let assignmentPattern = try NSRegularExpression(
            pattern: #"\b(?:statusText|errorText|statusBanner|infoError|externalStatusText)\s*="#
        )
        let literalPattern = try NSRegularExpression(pattern: #"\"((?:[^\"\\]|\\.)*)\""#)
        var keys: Set<String> = []
        var unlocalizedDeclarations: [String] = []

        for fileURL in try Self.swiftUISourceFiles() {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for fieldName in fieldNames where source.contains("var \(fieldName): String?") {
                unlocalizedDeclarations.append("\(fileURL.lastPathComponent): \(fieldName)")
            }
            for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
                guard assignmentPattern.firstMatch(in: line, range: lineRange) != nil,
                      Self.containsHanCharacter(line) else { continue }
                literalPattern.enumerateMatches(in: line, range: lineRange) { match, _, _ in
                    guard let match,
                          let range = Range(match.range(at: 1), in: line),
                          let key = Self.localizedFormatKey(from: String(line[range])),
                          Self.containsHanCharacter(key) else { return }
                    keys.insert(key)
                }
            }
        }

        XCTAssertTrue(
            unlocalizedDeclarations.isEmpty,
            "Dynamic status fields must use LocalizedStringKey:\n\(unlocalizedDeclarations.joined(separator: "\n"))"
        )
        XCTAssertGreaterThan(keys.count, 80)
        try Self.assertEnglishTranslations(for: keys, in: translations)
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func englishTranslations() throws -> [String: String] {
        try readStringsDictionary(
            at: repoRoot.appendingPathComponent(
                "Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings"
            )
        )
    }

    private static func readStringsDictionary(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(object as? [String: String])
    }

    private static func swiftUISourceFiles() throws -> [URL] {
        let roots = [
            repoRoot.appendingPathComponent("Sources/MacSvnApp"),
            repoRoot.appendingPathComponent("Sources/MacSvnDesktopApp"),
        ]
        return try roots.flatMap { root in
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            )
            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
                return url
            }
        }
        .sorted { $0.path < $1.path }
    }

    private static func assertEnglishTranslations(
        for keys: Set<String>,
        in translations: [String: String]
    ) throws {
        let missing = keys.filter { translations[$0] == nil }.sorted()
        XCTAssertTrue(missing.isEmpty, "Missing English keys:\n\(missing.joined(separator: "\n"))")

        let untranslated = keys.filter { key in
            guard let value = translations[key] else { return false }
            return containsHanCharacter(value)
        }
        .sorted()
        XCTAssertTrue(
            untranslated.isEmpty,
            "English values still contain Chinese:\n\(untranslated.joined(separator: "\n"))"
        )

        let placeholderMismatches = keys.filter { key in
            guard let value = translations[key] else { return false }
            return formatPlaceholders(in: key) != formatPlaceholders(in: value)
        }
        .sorted()
        XCTAssertTrue(
            placeholderMismatches.isEmpty,
            "English values changed format placeholders:\n\(placeholderMismatches.joined(separator: "\n"))"
        )
    }

    private static func containsHanCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private static func formatPlaceholders(in value: String) -> [String] {
        let pattern = try! NSRegularExpression(
            pattern: #"%(?:\d+\$)?(?:@|[-+0-9.]*[diuoxXfFeEgGaAcCsSp])"#
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return pattern.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            return String(value[matchRange]).replacingOccurrences(
                of: #"^%\d+\$"#,
                with: "%",
                options: .regularExpression
            )
        }
        .sorted()
    }

    private static func localizedFormatKey(from sourceLiteral: String) -> String? {
        var result = ""
        var index = sourceLiteral.startIndex
        while index < sourceLiteral.endIndex {
            let character = sourceLiteral[index]
            guard character == "\\" else {
                result.append(character)
                index = sourceLiteral.index(after: index)
                continue
            }

            let escapedIndex = sourceLiteral.index(after: index)
            guard escapedIndex < sourceLiteral.endIndex else {
                result.append(character)
                break
            }
            let escaped = sourceLiteral[escapedIndex]
            guard escaped == "(" else {
                switch escaped {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(escaped)
                }
                index = sourceLiteral.index(after: escapedIndex)
                continue
            }

            var cursor = sourceLiteral.index(after: escapedIndex)
            var depth = 1
            while cursor < sourceLiteral.endIndex, depth > 0 {
                switch sourceLiteral[cursor] {
                case "(": depth += 1
                case ")": depth -= 1
                default: break
                }
                cursor = sourceLiteral.index(after: cursor)
            }
            guard depth == 0 else { return nil }
            result.append("%@")
            index = cursor
        }
        return result
    }

    private static func readRepoSource(at path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
