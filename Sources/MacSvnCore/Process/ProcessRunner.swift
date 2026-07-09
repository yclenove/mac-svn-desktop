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
        try await Task.detached(priority: .userInitiated) {
            try runProcess(
                executable: executable,
                arguments: arguments,
                stdin: stdin,
                currentDirectory: currentDirectory,
                timeout: timeout
            )
        }.value
    }
}

private func runProcess(
    executable: String,
    arguments: [String],
    stdin: Data?,
    currentDirectory: String?,
    timeout: TimeInterval
) throws -> ProcessResult {
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

private func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    environment["LANG"] = "C"

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
