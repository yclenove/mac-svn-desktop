import Foundation
import XCTest
@testable import MacSvnCore

final class TortoiseParitySettingsTests: XCTestCase {
    func testLanguagesExposeDisplayNamesAndLocales() {
        XCTAssertEqual(AppLanguage.allCases, [.system, .simplifiedChinese, .english])
        XCTAssertEqual(AppLanguage.system.displayName, "跟随系统")
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.simplifiedChinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
    }

    func testGeneralDialogAndNetworkDefaultsMatchTortoiseBehavior() {
        XCTAssertEqual(GeneralSettings(), GeneralSettings(
            language: .system,
            checkForUpdatesAutomatically: true,
            applyLocalExternalsPropertyChanges: false
        ))

        let dialogs = DialogSettings()
        XCTAssertNil(dialogs.logFontName)
        XCTAssertEqual(dialogs.logFontSize, 12)
        XCTAssertFalse(dialogs.useShortDateFormat)
        XCTAssertFalse(dialogs.doubleClickLogToComparePrevious)
        XCTAssertTrue(dialogs.useTrashWhenReverting)
        XCTAssertEqual(dialogs.defaultCheckoutPath, "")
        XCTAssertEqual(dialogs.defaultCheckoutURL, "")
        XCTAssertTrue(dialogs.recurseIntoUnversionedFolders)
        XCTAssertTrue(dialogs.enableCommitAutoCompletion)
        XCTAssertEqual(dialogs.autoCompletionTimeoutSeconds, 5)
        XCTAssertEqual(dialogs.commitMessageHistoryLimit, 25)
        XCTAssertTrue(dialogs.selectCommitItemsAutomatically)
        XCTAssertFalse(dialogs.reopenCommitAfterSuccessWithRemainingItems)
        XCTAssertFalse(dialogs.contactRepositoryOnChangesOpen)
        XCTAssertTrue(dialogs.showLockDialogBeforeLocking)
        XCTAssertFalse(dialogs.preFetchRepositoryDirectories)
        XCTAssertFalse(dialogs.showRepositoryExternals)

        XCTAssertEqual(SvnProxySettings(), SvnProxySettings(
            enabled: false,
            host: "",
            port: 8080,
            exceptions: [],
            username: ""
        ))
        XCTAssertEqual(SvnNetworkSettings(), SvnNetworkSettings(
            proxy: SvnProxySettings(),
            sshExecutablePath: nil,
            sshArguments: []
        ))
    }

    func testAdaptiveColourNormalizesHexAndUsesExplicitFallbackForInvalidValues() {
        let fallback = AdaptiveColour(lightHex: "#123456", darkHex: "#ABCDEF")
        let colour = AdaptiveColour(
            lightHex: "  aa11cc  ",
            darkHex: "not-a-colour",
            fallback: fallback
        )

        XCTAssertEqual(colour.lightHex, "#AA11CC")
        XCTAssertEqual(colour.darkHex, "#ABCDEF")
        XCTAssertEqual(colour.hex(for: .light), "#AA11CC")
        XCTAssertEqual(colour.hex(for: .dark), "#ABCDEF")
    }

    func testDialogSettingsDecodeLegacyPayloadWithNewRepositoryOptionsDisabled() throws {
        let data = Data(#"{"showLockDialogBeforeLocking":false}"#.utf8)

        let dialogs = try JSONDecoder().decode(DialogSettings.self, from: data)

        XCTAssertFalse(dialogs.showLockDialogBeforeLocking)
        XCTAssertFalse(dialogs.preFetchRepositoryDirectories)
        XCTAssertFalse(dialogs.showRepositoryExternals)
        XCTAssertTrue(dialogs.useTrashWhenReverting)
    }

    func testAdaptiveColourNormalizesValuesWhenDecoded() throws {
        let data = Data(#"{"lightHex":"abcdef","darkHex":"invalid"}"#.utf8)

        let decoded = try JSONDecoder().decode(AdaptiveColour.self, from: data)

        XCTAssertEqual(decoded.lightHex, "#ABCDEF")
        XCTAssertEqual(decoded.darkHex, AdaptiveColour.fallback.darkHex)
    }

    func testDefaultPaletteIsDistinctAndResolvesRolesWithoutAppKit() {
        let palette = ChangeColourPalette()
        let roles = ChangeColourRole.allCases

        let lightValues = roles.map { palette.hex(for: $0, appearance: .light) }
        let darkValues = roles.map { palette.hex(for: $0, appearance: .dark) }
        XCTAssertEqual(Set(lightValues).count, roles.count)
        XCTAssertEqual(Set(darkValues).count, roles.count)
        XCTAssertTrue(roles.allSatisfy {
            palette.hex(for: $0, appearance: .light) != palette.hex(for: $0, appearance: .dark)
        })

        XCTAssertEqual(palette.role(for: ItemStatus.modified), .modified)
        XCTAssertEqual(palette.role(for: ItemStatus.added), .added)
        XCTAssertEqual(palette.role(for: ItemStatus.deleted), .deleted)
        XCTAssertEqual(palette.role(for: ItemStatus.missing), .deleted)
        XCTAssertEqual(palette.role(for: ItemStatus.conflicted), .conflicted)
        XCTAssertNil(palette.role(for: ItemStatus.normal))
        XCTAssertEqual(
            palette.hex(forItemStatus: .conflicted, appearance: .dark),
            palette.conflicted.darkHex
        )
        XCTAssertEqual(palette.role(for: UnifiedDiffLineKind.addition), .added)
        XCTAssertEqual(palette.role(for: UnifiedDiffLineKind.deletion), .deleted)
        XCTAssertEqual(palette.role(for: SideBySideDiffCellKind.modified), .modified)
        XCTAssertEqual(palette.role(for: ChangedPathAction.added), .added)
        XCTAssertEqual(palette.role(for: ChangedPathAction.deleted), .deleted)
        XCTAssertEqual(palette.role(for: ChangedPathAction.replaced), .deleted)
        XCTAssertEqual(palette.role(for: MergeAction.merged), .merged)
        XCTAssertEqual(palette.role(for: MergeAction.conflicted), .conflicted)
        XCTAssertEqual(palette.role(for: MergeAction.updated), .modified)
    }
}
