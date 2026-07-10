import Foundation
import Observation

public protocol LockProviding: Sendable {
    func locks(wc: URL, targets: [String]) async throws -> [SvnLock]
    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws
    func unlock(wc: URL, paths: [String], force: Bool) async throws
}

public enum LockOperation: Equatable, Sendable {
    case lock
    case unlock
    /// 夺锁：`svn lock --force`
    case stealLock
    /// 打断锁：`svn unlock --force`（#21）
    case breakLock
}

public enum LockViewState: Equatable, Sendable {
    case idle
    case loading
    case locking
    case unlocking
    case loaded
    case confirmationRequired(LockOperation, [String])
    case error(String)
}

@MainActor
@Observable
public final class LockViewModel {
    private let workingCopy: URL
    private let provider: any LockProviding
    private var lastTargets: [String] = []

    public private(set) var state: LockViewState = .idle
    public private(set) var locks: [SvnLock] = []

    public init(workingCopy: URL, provider: any LockProviding) {
        self.workingCopy = workingCopy
        self.provider = provider
    }

    public func load(targets: [String] = []) async {
        lastTargets = targets
        state = .loading
        await refreshLocks(targets: targets)
    }

    /// 获取锁（#19）。`force` 为夺锁时需 `confirmed`。
    public func lock(
        paths: [String],
        message: String?,
        force: Bool,
        confirmed: Bool = true
    ) async {
        let normalized = LockActionPolicy.pathsEligibleForGetLock(selected: paths)
        guard validate(paths: normalized) else {
            return
        }

        if force && !confirmed {
            state = .confirmationRequired(.stealLock, normalized)
            return
        }

        state = .locking

        do {
            try await provider.lock(wc: workingCopy, paths: normalized, message: message, force: force)
            lastTargets = normalized
            await refreshLocks(targets: normalized)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// 释放锁（#20）。
    public func unlock(
        paths: [String],
        force: Bool = false,
        confirmed: Bool = true
    ) async {
        let normalized = LockActionPolicy.pathsEligibleForRelease(selected: paths, locks: locks)
        guard validate(paths: normalized) else {
            return
        }

        // 非 break 的 unlock 不强制确认；force 路径请走 breakLock
        if force {
            await breakLock(paths: normalized, confirmed: confirmed)
            return
        }

        state = .unlocking

        do {
            try await provider.unlock(wc: workingCopy, paths: normalized, force: false)
            lastTargets = normalized
            await refreshLocks(targets: normalized)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// 打断锁（#21）：`svn unlock --force`，必须确认。
    public func breakLock(paths: [String], confirmed: Bool = false) async {
        let normalized = LockActionPolicy.pathsEligibleForBreak(selected: paths, locks: locks)
        guard validate(paths: normalized) else {
            return
        }

        guard confirmed else {
            state = .confirmationRequired(.breakLock, normalized)
            return
        }

        state = .unlocking

        do {
            try await provider.unlock(wc: workingCopy, paths: normalized, force: true)
            lastTargets = normalized
            await refreshLocks(targets: normalized)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// 确认门控后继续执行。
    public func confirmPending(message: String? = nil) async {
        guard case .confirmationRequired(let operation, let paths) = state else {
            return
        }
        switch operation {
        case .lock:
            await lock(paths: paths, message: message, force: false, confirmed: true)
        case .stealLock:
            await lock(paths: paths, message: message, force: true, confirmed: true)
        case .unlock:
            await unlock(paths: paths, force: false, confirmed: true)
        case .breakLock:
            await breakLock(paths: paths, confirmed: true)
        }
    }

    public func cancelConfirmation() {
        if case .confirmationRequired = state {
            state = locks.isEmpty ? .idle : .loaded
        }
    }

    private func validate(paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            state = .error("emptyLockPaths")
            return false
        }

        return true
    }

    private func refreshLocks(targets: [String]) async {
        do {
            locks = try await provider.locks(wc: workingCopy, targets: targets)
            state = .loaded
        } catch {
            locks = []
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: LockProviding {}
