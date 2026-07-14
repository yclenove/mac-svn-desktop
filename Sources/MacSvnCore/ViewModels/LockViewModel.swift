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
    private let projectPropertyLoader: ProjectPropertyLoading?
    private var lastTargets: [String] = []
    private var projectPropertyLoadGeneration = 0
    private var pendingLockMessage: String?

    public private(set) var state: LockViewState = .idle
    public private(set) var locks: [SvnLock] = []
    public private(set) var projectProperties: ProjectPropertyPolicy
    public private(set) var projectPropertyLoadError: String?

    public init(
        workingCopy: URL,
        provider: any LockProviding,
        projectPropertyLoader: ProjectPropertyLoading? = nil,
        projectProperties: ProjectPropertyPolicy = ProjectPropertyPolicy(properties: [])
    ) {
        self.workingCopy = workingCopy
        self.provider = provider
        self.projectPropertyLoader = projectPropertyLoader
        self.projectProperties = projectProperties
    }

    public func load(targets: [String] = []) async {
        guard state != .locking, state != .unlocking else { return }
        lastTargets = targets
        state = .loading
        await refreshLocks(targets: targets)
    }

    /// 选择变化后刷新说明长度提示；获取锁前会再次读取当前目标，确保门控精确。
    public func refreshProjectProperties(for paths: [String]) async {
        let generation = beginProjectPropertyLoad()
        do {
            let properties = try await loadProjectProperties(for: paths)
            guard generation == projectPropertyLoadGeneration else { return }
            projectProperties = properties
            projectPropertyLoadError = nil
        } catch {
            guard generation == projectPropertyLoadGeneration else { return }
            projectPropertyLoadError = "projectPropertiesLoadFailed"
        }
    }

    /// 获取锁（#19）。`force` 为夺锁时需 `confirmed`。
    public func lock(
        paths: [String],
        message: String?,
        force: Bool,
        confirmed: Bool = true
    ) async {
        guard state != .locking, state != .unlocking else { return }
        let normalized = LockActionPolicy.pathsEligibleForGetLock(selected: paths)
        guard validate(paths: normalized) else {
            return
        }

        state = .locking
        let properties: ProjectPropertyPolicy
        let generation = beginProjectPropertyLoad()
        do {
            properties = try await loadProjectProperties(for: normalized)
            if generation == projectPropertyLoadGeneration {
                projectProperties = properties
                projectPropertyLoadError = nil
            }
        } catch {
            projectPropertyLoadError = "projectPropertiesLoadFailed"
            state = .error("projectPropertiesLoadFailed")
            return
        }
        if let validationError = LockMessagePolicy.validationError(for: message, properties: properties) {
            state = .error("lockMessageTooShort:\(validationError.required)")
            return
        }

        if force && !confirmed {
            pendingLockMessage = message
            state = .confirmationRequired(.stealLock, normalized)
            return
        }

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
        guard state != .locking, state != .unlocking else { return }
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
        guard state != .locking, state != .unlocking else { return }
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
            let pendingMessage = message ?? pendingLockMessage
            pendingLockMessage = nil
            await lock(paths: paths, message: pendingMessage, force: true, confirmed: true)
        case .unlock:
            await unlock(paths: paths, force: false, confirmed: true)
        case .breakLock:
            await breakLock(paths: paths, confirmed: true)
        }
    }

    public func cancelConfirmation() {
        if case .confirmationRequired = state {
            pendingLockMessage = nil
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

    private func loadProjectProperties(for paths: [String]) async throws -> ProjectPropertyPolicy {
        guard let projectPropertyLoader else { return projectProperties }
        return try await projectPropertyLoader(paths)
    }

    private func beginProjectPropertyLoad() -> Int {
        projectPropertyLoadGeneration += 1
        return projectPropertyLoadGeneration
    }
}

extension SvnService: LockProviding {}
