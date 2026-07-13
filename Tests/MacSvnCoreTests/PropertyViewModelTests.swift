import Foundation
import XCTest
@testable import MacSvnCore

final class PropertyViewModelTests: XCTestCase {
    @MainActor
    func testLoadSaveDeletePropertiesAndRefreshesList() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakePropertyProvider(results: [
            .success([SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")]),
            .success([SvnProperty(target: "README.txt", name: "custom:reviewer", value: "杨超")]),
            .success([])
        ])
        let viewModel = PropertyViewModel(workingCopy: wc, target: "README.txt", provider: provider)

        await viewModel.load()
        await viewModel.save(name: "custom:reviewer", value: "杨超")
        await viewModel.delete(name: "custom:reviewer")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.properties, [])
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil),
            PropertyProviderCall(operation: "set", wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超"),
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil),
            PropertyProviderCall(operation: "delete", wc: wc, target: "README.txt", name: "custom:reviewer", value: nil),
            PropertyProviderCall(operation: "properties", wc: wc, target: "README.txt", name: nil, value: nil)
        ])
    }

    @MainActor
    func testRejectsEmptyPropertyNameBeforeProviderCall() async {
        let provider = FakePropertyProvider(results: [.success([])])
        let viewModel = PropertyViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.save(name: "  ", value: "x")

        XCTAssertEqual(viewModel.state, .error("emptyPropertyName"))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    func testCommonTemplatesIncludeSvnIgnoreEolExecutableAndNeedsLock() {
        let names = PropertyViewModel.commonTemplates.map(\.name)
        XCTAssertTrue(names.contains("svn:ignore"))
        XCTAssertTrue(names.contains("svn:keywords"))
        XCTAssertTrue(names.contains("svn:externals"))
        XCTAssertTrue(names.contains("svn:global-ignores"))
        XCTAssertTrue(names.contains("svn:mergeinfo"))
        XCTAssertTrue(names.contains("tsvn:logminsize"))
        XCTAssertTrue(names.contains("bugtraq:url"))
    }

    func testTemplateScopeFlagsMatchSVNPropertySemantics() {
        let templates = Dictionary(uniqueKeysWithValues: PropertyViewModel.commonTemplates.map { ($0.name, $0) })

        XCTAssertEqual(templates["svn:ignore"]?.appliesToDirectory, true)
        XCTAssertEqual(templates["svn:ignore"]?.appliesToFile, false)
        XCTAssertEqual(templates["svn:keywords"]?.appliesToDirectory, false)
        XCTAssertEqual(templates["svn:keywords"]?.appliesToFile, true)
        XCTAssertEqual(templates["svn:externals"]?.appliesToDirectory, true)
        XCTAssertEqual(templates["tsvn:logminsize"]?.appliesToFile, false)
        XCTAssertEqual(templates["bugtraq:url"]?.appliesToFile, false)
    }
}

private struct PropertyProviderCall: Equatable {
    let operation: String
    let wc: URL
    let target: String
    let name: String?
    let value: String?
}

private actor FakePropertyProvider: PropertyProviding {
    private var results: [Result<[SvnProperty], Error>]
    private var calls: [PropertyProviderCall] = []

    init(results: [Result<[SvnProperty], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [PropertyProviderCall] {
        calls
    }

    func properties(wc: URL, target: String) async throws -> [SvnProperty] {
        calls.append(PropertyProviderCall(operation: "properties", wc: wc, target: target, name: nil, value: nil))
        return try results.removeFirst().get()
    }

    func setProperty(wc: URL, target: String, name: String, value: String) async throws {
        calls.append(PropertyProviderCall(operation: "set", wc: wc, target: target, name: name, value: value))
    }

    func deleteProperty(wc: URL, target: String, name: String) async throws {
        calls.append(PropertyProviderCall(operation: "delete", wc: wc, target: target, name: name, value: nil))
    }
}
