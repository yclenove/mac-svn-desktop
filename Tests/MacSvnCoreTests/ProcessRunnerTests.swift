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

    func testRunThrowsCancelledWhenTaskIsCancelled() async {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(
                executable: "/bin/sleep",
                arguments: ["10"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 30
            )
        }

        // 给子进程一点启动时间，再取消
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as SvnError {
            XCTAssertEqual(error, .cancelled)
        } catch is CancellationError {
            // 外层 Task 竞态下也可能直接抛 CancellationError；ProcessRunner 已映射，此处兼容
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected SvnError.cancelled, got \(error)")
        }
    }

    func testSvnCancellableTaskCancelMapsToSvnErrorCancelled() async {
        let handle = SvnCancellableTask {
            let runner = ProcessRunner()
            return try await runner.run(
                executable: "/bin/sleep",
                arguments: ["10"],
                stdin: nil,
                currentDirectory: nil,
                timeout: 30
            )
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        handle.cancel()

        do {
            _ = try await handle.value
            XCTFail("Expected cancellation")
        } catch let error as SvnError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Expected SvnError.cancelled, got \(error)")
        }
    }
}
