import Foundation
import XCTest
@testable import MacSvnCore

@MainActor
final class PatchViewModelTests: XCTestCase {
    func testCreatePatchPassesSelectedPathsAndStoresCompletion() async {
        let provider = FakePatchProvider()
        let vm = PatchViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("patch-(UUID().uuidString)")

        await vm.create(paths: ["README.txt", "src/main.swift"], to: destination)

        XCTAssertEqual(vm.state, .completed(.create))
        let createdPaths = await provider.createdPaths()
        XCTAssertEqual(createdPaths, ["README.txt", "src/main.swift"])
    }

    func testCreateRejectsEmptySelectionBeforeProviderCall() async {
        let provider = FakePatchProvider()
        let vm = PatchViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await vm.create(paths: [], to: URL(fileURLWithPath: "/tmp/out.patch"))

        XCTAssertEqual(vm.state, .error("noSelectedPaths"))
        let createCallCount = await provider.createCallCount()
        XCTAssertEqual(createCallCount, 0)
    }

    func testApplyRejectsMissingPatchFile() async {
        let provider = FakePatchProvider()
        let vm = PatchViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await vm.apply(patchFile: URL(fileURLWithPath: "/tmp/missing.patch"))

        XCTAssertEqual(vm.state, .error("patchFileNotFound"))
        let applyCallCount = await provider.applyCallCount()
        XCTAssertEqual(applyCallCount, 0)
    }
}

private actor FakePatchProvider: PatchProviding {
    private var paths: [String] = []
    private var createCalls = 0
    private var applyCalls = 0

    func createPatch(wc: URL, paths: [String], to destination: URL) async throws {
        _ = (wc, destination)
        self.paths = paths
        createCalls += 1
    }

    func applyPatch(wc: URL, patchFile: URL) async throws {
        _ = (wc, patchFile)
        applyCalls += 1
    }

    func createdPaths() -> [String] { paths }
    func createCallCount() -> Int { createCalls }
    func applyCallCount() -> Int { applyCalls }
}
