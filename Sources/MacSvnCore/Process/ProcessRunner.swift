import Foundation

public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let control = RunningProcessControl()

        do {
            return try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try runProcess(
                        executable: executable,
                        arguments: arguments,
                        stdin: stdin,
                        currentDirectory: currentDirectory,
                        timeout: timeout,
                        control: control
                    )
                }.value
            } onCancel: {
                // 详设：取消 → SIGTERM，5s 未退出再 SIGKILL
                control.requestCancel()
            }
        } catch is CancellationError {
            // 外层 Task 已取消时，统一映射为业务可识别的 cancelled
            throw SvnError.cancelled
        }
    }
}

/// 可取消的异步 SVN/进程任务包装：调用方持有后可 `cancel()`，内部接到 `ProcessRunner` 取消路径。
public final class SvnCancellableTask<Success: Sendable>: Sendable {
    private let task: Task<Success, Error>

    public init(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () async throws -> Success
    ) {
        self.task = Task(priority: priority) {
            try await operation()
        }
    }

    public var isCancelled: Bool { task.isCancelled }

    public func cancel() {
        task.cancel()
    }

    public var value: Success {
        get async throws {
            do {
                return try await task.value
            } catch is CancellationError {
                throw SvnError.cancelled
            }
        }
    }
}

private func runProcess(
    executable: String,
    arguments: [String],
    stdin: Data?,
    currentDirectory: String?,
    timeout: TimeInterval,
    control: RunningProcessControl
) throws -> ProcessResult {
    if control.wasCancelled() {
        throw SvnError.cancelled
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = processEnvironment()

    if let currentDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdinPipe = Pipe()
    if stdin != nil {
        process.standardInput = stdinPipe
    }

    let startedAt = Date()
    try process.run()
    control.attach(process)

    if control.wasCancelled() {
        // attach 前就已取消：确保进程被终止
        control.requestCancel()
        process.waitUntilExit()
        throw SvnError.cancelled
    }

    if let stdin {
        stdinPipe.fileHandleForWriting.write(stdin)
        try? stdinPipe.fileHandleForWriting.close()
    }

    let timedOut = AtomicFlag()
    let timeoutThread = Thread {
        Thread.sleep(forTimeInterval: timeout)
        guard process.isRunning else {
            return
        }
        // 已被用户取消时，不再按超时路径报错
        guard !control.wasCancelled() else {
            return
        }

        timedOut.set()
        process.terminate()
    }
    timeoutThread.start()

    let stdoutReader = PipeReader(handle: stdoutPipe.fileHandleForReading)
    let stderrReader = PipeReader(handle: stderrPipe.fileHandleForReading)
    stdoutReader.start()
    stderrReader.start()

    process.waitUntilExit()

    let stdout = stdoutReader.waitForData()
    let stderrData = stderrReader.waitForData()

    if control.wasCancelled() {
        throw SvnError.cancelled
    }

    if timedOut.get() {
        throw SvnError.network(detail: "Process timed out after \(timeout) seconds.")
    }

    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: stdout,
        stderr: String(data: stderrData, encoding: .utf8) ?? String(decoding: stderrData, as: UTF8.self),
        duration: Date().timeIntervalSince(startedAt)
    )
}

/// 跨线程共享的进程控制：取消时 terminate，超时未退再 SIGKILL。
private final class RunningProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var killScheduled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldStop = cancelled
        lock.unlock()

        if shouldStop {
            terminateAndScheduleKill(process)
        }
    }

    func requestCancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()

        guard let process else { return }
        terminateAndScheduleKill(process)
    }

    func wasCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func terminateAndScheduleKill(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }

        lock.lock()
        let alreadyScheduled = killScheduled
        if !alreadyScheduled {
            killScheduled = true
        }
        lock.unlock()

        guard !alreadyScheduled else { return }

        // 详设：SIGTERM 后 5 秒仍存活则 SIGKILL
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

private func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "LC_ALL")
    environment["LANG"] = "en_US.UTF-8"
    environment["LC_CTYPE"] = "en_US.UTF-8"
    environment["LC_MESSAGES"] = "C"

    let extraPath = "/opt/homebrew/bin:/usr/local/bin"
    if let path = environment["PATH"], !path.isEmpty {
        environment["PATH"] = "\(path):\(extraPath)"
    } else {
        environment["PATH"] = extraPath
    }

    return environment
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}

private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data: Data?
    private var thread: Thread?

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        let thread = Thread { [handle, weak self] in
            let readData = handle.readDataToEndOfFile()
            self?.lock.lock()
            self?.data = readData
            self?.lock.unlock()
        }

        self.thread = thread
        thread.start()
    }

    func waitForData() -> Data {
        while true {
            lock.lock()
            if let data {
                lock.unlock()
                return data
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
}
