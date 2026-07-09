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

    public func lock(
        paths: [String],
        message: String?,
        force: Bool,
        confirmed: Bool = true
    ) async {
        guard validate(paths: paths) else {
            return
        }

        guard !force || confirmed else {
            state = .confirmationRequired(.lock, paths)
            return
        }

        state = .locking

        do {
            try await provider.lock(wc: workingCopy, paths: paths, message: message, force: force)
            lastTargets = paths
            await refreshLocks(targets: paths)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func unlock(
        paths: [String],
        force: Bool,
        confirmed: Bool = true
    ) async {
        guard validate(paths: paths) else {
            return
        }

        guard !force || confirmed else {
            state = .confirmationRequired(.unlock, paths)
            return
        }

        state = .unlocking

        do {
            try await provider.unlock(wc: workingCopy, paths: paths, force: force)
            lastTargets = paths
            await refreshLocks(targets: paths)
        } catch {
            state = .error(String(describing: error))
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
