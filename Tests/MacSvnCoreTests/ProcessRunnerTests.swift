import XCTest
@testable import MacSvnCore

final class ProcessRunnerTests: XCTestCase {
    func testRunCapturesStdoutStderrAndExitCode() async throws {
        let runner = ProcessRunner()

        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2; exit 7"],
            stdin: nil,
            currentDirectory: nil,
            timeout: 5
        )

        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "out")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertGreaterThanOrEqual(result.duration, 0)
    }

    func testRunWritesStdin() async throws {
        let runner = ProcessRunner()

        let result = try await runner.run(
            executable: "/bin/cat",
            arguments: [],
            stdin: Data("hello stdin".utf8),
            currentDirectory: nil,
            timeout: 5
        )

        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "hello stdin")
    }

    func testRunDrainsStdoutAndStderrConcurrently() async throws {
        let runner = ProcessRunner()

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            arguments: ["-e", "print 'o' x 200000; print STDERR 'e' x 200000;"],
            stdin: nil,
            currentDirectory: nil,
            timeout: 2
        )

        XCTAssertEqual(result.stdout.count, 200000)
        XCTAssertEqual(result.stderr.count, 200000)
    }

    func testRunTimesOutAndThrowsNetworkError() async {
        let runner = ProcessRunner()

        do {
            _ = try await runner.run(
                executable: "/bin/sleep",
                arguments: ["5"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch let error as SvnError {
            guard case .network(let detail) = error else {
                return XCTFail("Expected network timeout, got \(error)")
            }
            XCTAssertTrue(detail.contains("timed out"))
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }
    }
}
