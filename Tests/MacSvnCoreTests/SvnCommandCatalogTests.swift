import XCTest
@testable import MacSvnCore

final class SvnCommandCatalogTests: XCTestCase {
    func testCatalogCoversAllPrimaryAndLogInventoryIDs() {
        XCTAssertEqual(SvnCommandCatalog.primaryCommands.count, SvnCommandCatalog.primaryCommandCount)
        XCTAssertEqual(SvnCommandCatalog.logActions.count, SvnCommandCatalog.logActionCount)
        XCTAssertEqual(
            SvnCommandCatalog.all.count,
            SvnCommandCatalog.primaryCommandCount + SvnCommandCatalog.logActionCount
        )
        XCTAssertEqual(SvnCommandID.allCases.count, SvnCommandCatalog.all.count)
    }

    func testEveryPrimaryNumberOneThroughFortySixIsPresentAndUnique() {
        let numbers = SvnCommandCatalog.primaryCommands.map(\.inventoryNumber).sorted()
        XCTAssertEqual(numbers, Array(1...46))
    }

    func testEveryLogActionNumberOneThroughTwentyIsPresentAndUnique() {
        let numbers = SvnCommandCatalog.logActions.map(\.inventoryNumber).sorted()
        XCTAssertEqual(numbers, Array(1...20))
    }

    func testExtendedMenuFlagsMatchTortoiseShiftCommands() {
        let extendedKeys = Set(SvnCommandCatalog.extendedMenuCommands.map(\.inventoryKey))
        XCTAssertEqual(
            extendedKeys,
            ["cmd.06", "cmd.15", "cmd.16", "cmd.21", "cmd.25"]
        )
    }

    func testLookupByIDAndInventoryKey() {
        let commit = SvnCommandCatalog.descriptor(for: .commit)
        XCTAssertEqual(commit?.displayName, "提交")
        XCTAssertEqual(commit?.inventoryKey, "cmd.04")
        XCTAssertEqual(SvnCommandCatalog.descriptor(inventoryKey: "cmd.04")?.id, .commit)
        XCTAssertEqual(SvnCommandCatalog.primary(number: 8)?.id, .checkForModifications)
        XCTAssertEqual(SvnCommandCatalog.logAction(number: 11)?.id, .logRevertToThisRevision)
        XCTAssertNil(SvnCommandCatalog.primary(number: 0))
        XCTAssertNil(SvnCommandCatalog.logAction(number: 99))
    }

    func testDisplayNamesAndKeywordsAreNonEmpty() {
        for descriptor in SvnCommandCatalog.all {
            XCTAssertFalse(descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(descriptor.id)")
            XCTAssertFalse(descriptor.keywords.isEmpty, "\(descriptor.id) should have search keywords")
        }
    }

    func testDailyCFMSubsetCoversWaveT1CommandsAndIsSearchable() {
        let ids = Set(SvnCommandCatalog.dailyCFMCommandIDs)
        XCTAssertEqual(SvnCommandCatalog.dailyCFMCommands.count, SvnCommandCatalog.dailyCFMCommandIDs.count)
        XCTAssertTrue(ids.isSuperset(of: [
            .update, .commit, .diff, .add, .delete, .revert, .cleanup,
            .rename, .addToIgnoreList, .copyMove, .repairMoveCopy,
            .branchTag, .switchBranch, .merge, .blame, .properties,
            .repairFilenameCaseConflict
        ]))
        let renameHits = SvnCommandCatalog.searchDailyCFM(query: "rename")
        XCTAssertEqual(renameHits.first?.id, .rename)
        XCTAssertEqual(
            SvnCommandCatalog.searchDailyCFM(query: "case conflict").first?.id,
            .repairFilenameCaseConflict
        )
        let ignoreHits = SvnCommandCatalog.searchDailyCFM(query: "ignore")
        XCTAssertEqual(ignoreHits.first?.id, .addToIgnoreList)
        XCTAssertTrue(SvnCommandCatalog.searchDailyCFM(query: "   ").isEmpty)
    }

    func testAllCasesHaveMatchingDescriptor() {
        for id in SvnCommandID.allCases {
            XCTAssertNotNil(SvnCommandCatalog.descriptor(for: id), "missing descriptor for \(id)")
        }
    }
}
