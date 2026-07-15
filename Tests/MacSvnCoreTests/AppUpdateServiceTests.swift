import Foundation
import XCTest
@testable import MacSvnCore

final class AppUpdateServiceTests: XCTestCase {
    func testCheckReportsNewerGitHubReleaseAndUsesReleasePage() async throws {
        let endpoint = URL(string: "https://api.github.com/repos/example/app/releases/latest")!
        let releasePage = URL(string: "https://github.com/example/app/releases/tag/v2.4.0")!
        let recorder = RequestRecorder(
            data: Data(#"{"tag_name":"v2.4.0","html_url":"https://github.com/example/app/releases/tag/v2.4.0","draft":false,"prerelease":false}"#.utf8),
            response: HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let service = AppUpdateService(endpoint: endpoint, dataLoader: recorder.load)

        let result = try await service.check(currentVersion: "2.3.1")

        XCTAssertEqual(
            result,
            .updateAvailable(AppRelease(version: "2.4.0", pageURL: releasePage))
        )
        let recordedRequest = await recorder.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertFalse((request.value(forHTTPHeaderField: "User-Agent") ?? "").isEmpty)
    }

    func testCheckTreatsEqualAndOlderReleaseAsUpToDate() async throws {
        for remoteVersion in ["v2.3.1", "2.2.9"] {
            let endpoint = URL(string: "https://example.invalid/latest")!
            let recorder = RequestRecorder(
                data: Data("{\"tag_name\":\"\(remoteVersion)\",\"html_url\":\"https://example.invalid/release\",\"draft\":false,\"prerelease\":false}".utf8),
                response: HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
            let service = AppUpdateService(endpoint: endpoint, dataLoader: recorder.load)

            let result = try await service.check(currentVersion: "2.3.1")
            XCTAssertEqual(result, .upToDate(currentVersion: "2.3.1"))
        }
    }

    func testCheckComparesPrereleaseIdentifiersWithoutClaimingStableIsOlder() async throws {
        XCTAssertEqual(AppVersion("2.4.0-beta.2"), AppVersion("v2.4.0-beta.2"))
        XCTAssertLessThan(AppVersion("2.4.0-beta.2"), AppVersion("2.4.0"))
        XCTAssertLessThan(AppVersion("2.4.0-beta.2"), AppVersion("2.4.0-beta.10"))
        XCTAssertFalse(AppVersion("").isValid)
        XCTAssertFalse(AppVersion("v").isValid)
    }

    func testCheckRejectsHTTPFailureMalformedPayloadAndInvalidCurrentVersion() async {
        let endpoint = URL(string: "https://example.invalid/latest")!
        let failure = RequestRecorder(
            data: Data("not found".utf8),
            response: HTTPURLResponse(url: endpoint, statusCode: 404, httpVersion: nil, headerFields: nil)!
        )
        let malformed = RequestRecorder(
            data: Data(#"{"tag_name":"release","html_url":"not a url"}"#.utf8),
            response: HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await AppUpdateService(endpoint: endpoint, dataLoader: failure.load)
                .check(currentVersion: "1.0.0")
        } verify: { error in
            XCTAssertEqual(error as? AppUpdateError, .httpStatus(404))
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await AppUpdateService(endpoint: endpoint, dataLoader: malformed.load)
                .check(currentVersion: "1.0.0")
        } verify: { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidReleaseMetadata)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await AppUpdateService(endpoint: endpoint, dataLoader: malformed.load)
                .check(currentVersion: "development")
        } verify: { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidCurrentVersion("development"))
        }
    }

    func testCheckRejectsInsecureHTTPReleasePage() async {
        let endpoint = URL(string: "https://example.invalid/latest")!
        let recorder = RequestRecorder(
            data: Data(
                #"{"tag_name":"v2.4.0","html_url":"http://example.invalid/release","draft":false}"#.utf8
            ),
            response: HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await AppUpdateService(endpoint: endpoint, dataLoader: recorder.load)
                .check(currentVersion: "2.3.1")
        } verify: { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidReleaseMetadata)
        }
    }
}

private actor RequestRecorder {
    private let data: Data
    private let response: URLResponse
    private var request: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (data, response)
    }

    func lastRequest() -> URLRequest? { request }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}
