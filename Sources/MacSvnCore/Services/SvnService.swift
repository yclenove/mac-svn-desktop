import Foundation

public enum SvnServiceError: Error, Equatable, Sendable {
    case emptyCommitMessage
    case wcBusy(operation: String)
    case localChangesPreventSwitch(paths: [String])
    case commitGuardWarnings([CommitGuardIssue])
    case commitGuardBlocked([CommitGuardIssue])
    case invalidRelocateURLs
}

public protocol CredentialProviding: Sendable {
    func credential(for wc: URL) async throws -> Credential?
}

public actor SvnService {
    private let backend: any SvnBackend
    private let credentialProvider: (any CredentialProviding)?
    private let commitGuard: (any CommitGuardChecking)?
    private var activeWriteOperations: [URL: String] = [:]

    public init(
        backend: any SvnBackend,
        credentialProvider: (any CredentialProviding)? = nil,
        commitGuard: (any CommitGuardChecking)? = nil
    ) {
        self.backend = backend
        self.credentialProvider = credentialProvider
        self.commitGuard = commitGuard
    }

    public func status(wc: URL) async throws -> [FileStatus] {
        try await backend.status(wc: wc)
    }

    public func statusAgainstRepository(wc: URL) async throws -> [FileStatus] {
        try await backend.statusAgainstRepository(wc: wc)
    }

    public func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        try await backend.diff(wc: wc, target: target, r1: r1, r2: r2)
    }

    public func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential? = nil
    ) async throws -> String {
        try await retryingAuthentication(wc: credentialScope(for: url), initialAuth: auth) { auth in
            try await backend.diffWithURL(
                wc: wc,
                target: target,
                url: url,
                revision: revision,
                auth: auth
            )
        }
    }

    public func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        try await backend.diffBetweenPaths(wc: wc, oldPath: oldPath, newPath: newPath)
    }

    public func repositoryDiff(
        wc: URL,
        oldURL: String,
        oldRevision: Revision,
        newURL: String,
        newRevision: Revision,
        auth: Credential? = nil
    ) async throws -> String {
        try await retryingAuthentication(wc: credentialScope(for: newURL), initialAuth: auth) { auth in
            try await backend.repositoryDiff(
                wc: wc,
                oldURL: oldURL,
                oldRevision: oldRevision,
                newURL: newURL,
                newRevision: newRevision,
                auth: auth
            )
        }
    }

    public func diffAgainstBase(wc: URL, target: String) async throws -> String {
        try await backend.diffAgainstBase(wc: wc, target: target)
    }

    /// 将选中路径的工作副本差异按选择顺序合并为单个 patch 文件。
    public func createPatch(wc: URL, paths: [String], to destination: URL) async throws {
        let normalizedPaths = try PatchPathPolicy.validate(paths)
        var diffs: [String] = []
        for path in normalizedPaths {
            let diff = try await backend.diff(wc: wc, target: path, r1: nil, r2: nil)
            if !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diffs.append(diff)
            }
        }

        let patchText = diffs.joined(separator: "\n")
        guard !patchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PatchPathError.emptyPatch
        }

        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".svnstudio-patch-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try patchText.write(to: temporary, atomically: true, encoding: .utf8)
        _ = try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    public func blame(wc: URL, target: String) async throws -> [BlameLine] {
        try await backend.blame(wc: wc, target: target)
    }

    public func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine] {
        try await backend.blame(
            wc: wc,
            target: target,
            startRevision: startRevision,
            endRevision: endRevision
        )
    }

    public func properties(wc: URL, target: String) async throws -> [SvnProperty] {
        try await backend.properties(wc: wc, target: target)
    }

    public func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty? {
        try await backend.propertyValue(wc: wc, target: target, name: name)
    }

    public func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        try await backend.locks(wc: wc, targets: targets)
    }

    public func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool
    ) async throws -> [LogEntry] {
        try await log(wc: wc, target: target, from: from, batch: batch, verbose: verbose, stopOnCopy: false)
    }

    public func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry] {
        if let url = URL(string: target), url.scheme != nil {
            return try await remoteLog(
                url: target,
                from: from,
                batch: batch,
                verbose: verbose,
                auth: nil
            )
        }
        return try await backend.log(
            wc: wc,
            target: target,
            from: from,
            batch: batch,
            verbose: verbose,
            stopOnCopy: stopOnCopy
        )
    }

    public func remoteLog(
        url: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        auth: Credential? = nil
    ) async throws -> [LogEntry] {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.remoteLog(url: url, from: from, batch: batch, verbose: verbose, auth: auth)
        }
    }

    public func remoteLogFromHead(
        url: String,
        batch: Int,
        verbose: Bool,
        auth: Credential? = nil
    ) async throws -> [LogEntry] {
        let credentialScope = credentialScope(for: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.remoteLogFromHead(url: url, batch: batch, verbose: verbose, auth: auth)
        }
    }

    public func list(url: String, depth: SvnDepth, auth: Credential? = nil) async throws -> [RemoteEntry] {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.list(url: url, depth: depth, auth: auth)
        }
    }

    public func listWithLocks(url: String, depth: SvnDepth, auth: Credential? = nil) async throws -> [RemoteEntry] {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.listWithLocks(url: url, depth: depth, auth: auth)
        }
    }

    public func cat(
        url: String,
        revision: Revision? = nil,
        sizeLimit: Int,
        auth: Credential? = nil
    ) async throws -> Data {
        let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.cat(url: url, revision: revision, sizeLimit: sizeLimit, auth: auth)
        }
    }

    public func info(wc: URL, target: String) async throws -> SvnInfo {
        try await backend.info(wc: wc, target: target)
    }

    /// 查询仓库 HEAD 修订号（供 L11「还原到此修订」等）。
    public func repositoryHeadRevision(wc: URL, target: String = "") async throws -> Revision {
        try await backend.repositoryHeadRevision(wc: wc, target: target)
    }

    public func update(
        wc: URL,
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil,
        ignoreExternals: Bool = false
    ) async throws -> UpdateSummary {
        try await withWriteLock(wc: wc, operation: "update") {
            try await retryingAuthentication(wc: wc, initialAuth: nil) { auth in
                var effectiveRevision = revision
                // 同仓多路径：先钉 HEAD，再统一 -r，避免更新间隙产生 mixed-rev（对齐小乌龟）
                if UpdateRevisionPolicy.shouldPinRepositoryHead(paths: paths, revision: revision) {
                    let probe = UpdateRevisionPolicy.headProbeTarget(paths: paths)
                    effectiveRevision = try await backend.repositoryHeadRevision(wc: wc, target: probe)
                }
                return try await backend.update(
                    wc: wc,
                    paths: paths,
                    revision: effectiveRevision,
                    setDepth: setDepth,
                    ignoreExternals: ignoreExternals,
                    auth: auth
                )
            }
        }
    }

    public func switchTo(
        wc: URL,
        url: String,
        revision: Revision? = nil,
        auth: Credential? = nil,
        allowLocalChanges: Bool = false
    ) async throws -> UpdateSummary {
        try await withWriteLock(wc: wc, operation: "switch") {
            let statuses = try await backend.status(wc: wc)
            let localChangePaths = localChangePaths(from: statuses)

            guard allowLocalChanges || localChangePaths.isEmpty else {
                throw SvnServiceError.localChangesPreventSwitch(paths: localChangePaths)
            }

            let credentialScope = URL(string: url) ?? URL(fileURLWithPath: url)
            return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
                try await backend.switchTo(wc: wc, url: url, revision: revision, auth: auth)
            }
        }
    }

    public func switchTo(
        wc: URL,
        url: String,
        auth: Credential?,
        allowLocalChanges: Bool
    ) async throws -> UpdateSummary {
        try await switchTo(
            wc: wc,
            url: url,
            revision: nil,
            auth: auth,
            allowLocalChanges: allowLocalChanges
        )
    }

    public func merge(
        wc: URL,
        source: String,
        range: RevisionRange? = nil,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        try await withWriteLock(wc: wc, operation: "merge") {
            let credentialScope = URL(string: source) ?? URL(fileURLWithPath: source)
            return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
                try await backend.merge(wc: wc, source: source, range: range, dryRun: dryRun, auth: auth)
            }
        }
    }

    public func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        try await withWriteLock(wc: wc, operation: "mergeTwoTrees") {
            let credentialScope = credentialScope(for: from)
            return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
                try await backend.mergeTwoTrees(
                    wc: wc,
                    from: from,
                    to: to,
                    dryRun: dryRun,
                    auth: auth
                )
            }
        }
    }

    public func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth = .infinity,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async throws {
        try await withWriteLock(wc: destination, operation: "checkout") {
            try await retryingAuthentication(wc: destination, initialAuth: auth) { auth in
                try await backend.checkout(
                    url: url,
                    to: destination,
                    depth: depth,
                    revision: revision,
                    ignoreExternals: ignoreExternals,
                    auth: auth
                )
            }
        }
    }

    public func export(
        url: String,
        to destination: URL,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async throws {
        try await withWriteLock(wc: destination, operation: "export") {
            let credentialScope = credentialScope(for: url)
            try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
                try await backend.export(
                    url: url,
                    to: destination,
                    revision: revision,
                    ignoreExternals: ignoreExternals,
                    auth: auth
                )
            }
        }
    }

    /// 兼容 Git 迁移模块的旧导出协议；默认保留外部定义。
    public func export(
        url: String,
        to destination: URL,
        revision: Revision?,
        auth: Credential?
    ) async throws {
        try await export(
            url: url,
            to: destination,
            revision: revision,
            ignoreExternals: false,
            auth: auth
        )
    }

    public func importProject(
        path: URL,
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)
        return try await retryingAuthentication(wc: credentialScope(for: url), initialAuth: auth) { auth in
            try await backend.importProject(path: path, url: url, message: message, auth: auth)
        }
    }

    /// 将普通目录导入后重新检出到原目录，使目录真正成为工作副本。
    /// `svn import` 本身不会写入 `.svn`，因此不能把它当作就地导入的完成态。
    public func importInPlace(
        path: URL,
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SvnServiceError.invalidRelocateURLs
        }
        guard !fileManager.fileExists(atPath: path.appendingPathComponent(".svn").path) else {
            throw SvnServiceError.invalidRelocateURLs
        }

        return try await withWriteLock(wc: path, operation: "importInPlace") {
            try await retryingAuthentication(wc: credentialScope(for: url), initialAuth: auth) { auth in
                let revision = try await backend.importProject(path: path, url: url, message: message, auth: auth)
                let parent = path.deletingLastPathComponent()
                let token = UUID().uuidString
                let checkoutPath = parent.appendingPathComponent(".svnstudio-import-\(token)")
                let backupPath = parent.appendingPathComponent(".svnstudio-import-backup-\(token)")
                defer {
                    try? fileManager.removeItem(at: checkoutPath)
                    try? fileManager.removeItem(at: backupPath)
                }

                try await backend.checkout(
                    url: url,
                    to: checkoutPath,
                    depth: .infinity,
                    revision: revision,
                    ignoreExternals: false,
                    auth: auth
                )

                try fileManager.moveItem(at: path, to: backupPath)
                do {
                    try fileManager.createDirectory(at: path, withIntermediateDirectories: false)
                    for child in try fileManager.contentsOfDirectory(at: checkoutPath, includingPropertiesForKeys: nil) {
                        try fileManager.moveItem(at: child, to: path.appendingPathComponent(child.lastPathComponent))
                    }
                    try fileManager.removeItem(at: backupPath)
                } catch {
                    try? fileManager.removeItem(at: path)
                    try? fileManager.moveItem(at: backupPath, to: path)
                    throw error
                }
                return revision
            }
        }
    }

    public func relocate(
        wc: URL,
        from: String,
        to: String,
        auth: Credential? = nil
    ) async throws {
        guard !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SvnServiceError.invalidRelocateURLs
        }
        try await withWriteLock(wc: wc, operation: "relocate") {
            try await retryingAuthentication(wc: credentialScope(for: to), initialAuth: auth) { auth in
                try await backend.relocate(wc: wc, from: from, to: to, auth: auth)
            }
        }
    }

    public func removeFromVersionControl(path: URL, recursive: Bool = true) async throws {
        try VersionControlRemovalPolicy.validate(path)
        try await backend.removeFromVersionControl(path: path, recursive: recursive)
    }

    public func copy(
        source: String,
        destination: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)

        let credentialScope = credentialScope(for: destination)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.copy(source: source, destination: destination, message: message, auth: auth)
        }
    }

    public func mkdir(
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)

        let credentialScope = credentialScope(for: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.mkdir(url: url, message: message, auth: auth)
        }
    }

    public func delete(
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)

        let credentialScope = credentialScope(for: url)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.delete(url: url, message: message, auth: auth)
        }
    }

    public func move(
        source: String,
        destination: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        try requireCommitMessage(message)

        let credentialScope = credentialScope(for: destination)
        return try await retryingAuthentication(wc: credentialScope, initialAuth: auth) { auth in
            try await backend.move(source: source, destination: destination, message: message, auth: auth)
        }
    }

    public func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?
    ) async throws -> Revision {
        try await commit(wc: wc, paths: paths, message: message, auth: auth, skipGuardWarnings: false, keepLocks: false)
    }

    public func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?,
        skipGuardWarnings: Bool = false,
        keepLocks: Bool = false
    ) async throws -> Revision {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SvnServiceError.emptyCommitMessage
        }

        return try await withWriteLock(wc: wc, operation: "commit") {
            let statuses = try await backend.status(wc: wc)
            let statusesByPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0) })
            let conflicts = conflictingSelectedPaths(paths: paths, statuses: statuses)

            guard conflicts.isEmpty else {
                throw SvnError.conflict(paths: conflicts)
            }

            // Guard 必须在 add 之前：取消警告/阻断时不应留下已 add 的未版本项
            let guardIssues = try await commitGuard?.evaluate(wc: wc, paths: paths) ?? []
            let blockingIssues = guardIssues.filter { $0.severity == .blocking }
            guard blockingIssues.isEmpty else {
                throw SvnServiceError.commitGuardBlocked(blockingIssues)
            }

            let warningIssues = guardIssues.filter { $0.severity == .warning }
            if !warningIssues.isEmpty, !skipGuardWarnings {
                throw SvnServiceError.commitGuardWarnings(warningIssues)
            }

            // 勾选未版本项：Guard 通过后、commit 前在同一写锁内 add
            let unversionedToAdd = paths.filter { statusesByPath[$0]?.itemStatus == .unversioned }
            if !unversionedToAdd.isEmpty {
                try await backend.add(wc: wc, paths: unversionedToAdd)
            }

            return try await retryingAuthentication(wc: wc, initialAuth: auth) { auth in
                try await backend.commit(
                    wc: wc,
                    paths: paths,
                    message: message,
                    auth: auth,
                    keepLocks: keepLocks
                )
            }
        }
    }

    public func add(wc: URL, paths: [String]) async throws {
        try await withWriteLock(wc: wc, operation: "add") {
            try await backend.add(wc: wc, paths: paths)
        }
    }

    public func assignChangelist(
        wc: URL,
        name: String,
        paths: [String],
        depth: SvnDepth = .empty
    ) async throws {
        let normalizedName = try ChangelistPolicy.validatedName(name)
        let normalizedPaths = try ChangelistPolicy.validatedPaths(paths)
        try await withWriteLock(wc: wc, operation: "assignChangelist") {
            try await backend.assignChangelist(
                wc: wc,
                name: normalizedName,
                paths: normalizedPaths,
                depth: depth
            )
        }
    }

    public func removeFromChangelists(
        wc: URL,
        paths: [String],
        depth: SvnDepth = .empty
    ) async throws {
        let normalizedPaths = try ChangelistPolicy.validatedPaths(paths)
        try await withWriteLock(wc: wc, operation: "removeFromChangelists") {
            try await backend.removeFromChangelists(wc: wc, paths: normalizedPaths, depth: depth)
        }
    }

    public func delete(wc: URL, paths: [String]) async throws {
        try await withWriteLock(wc: wc, operation: "delete") {
            try await backend.delete(wc: wc, paths: paths)
        }
    }

    public func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        try await withWriteLock(wc: wc, operation: "repairMove") {
            try await backend.moveInWorkingCopy(wc: wc, source: source, destination: destination)
        }
    }

    public func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        try await withWriteLock(wc: wc, operation: "rename") {
            try await backend.renameInWorkingCopy(wc: wc, source: source, destination: destination)
        }
    }

    public func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        try await withWriteLock(wc: wc, operation: "repairCopy") {
            try await backend.copyInWorkingCopy(wc: wc, source: source, destination: destination)
        }
    }

    public func repairFilenameCaseConflict(wc: URL, source: String, destination: String) async throws {
        try await withWriteLock(wc: wc, operation: "repairFilenameCaseConflict") {
            try await backend.repairFilenameCaseConflict(wc: wc, source: source, destination: destination)
        }
    }

    public func revert(wc: URL, paths: [String], recursive: Bool = false) async throws {
        try await withWriteLock(wc: wc, operation: "revert") {
            try await backend.revert(wc: wc, paths: paths, recursive: recursive)
        }
    }

    public func cleanup(wc: URL) async throws {
        try await cleanup(wc: wc, options: .default)
    }

    public func cleanup(wc: URL, options: SvnCleanupOptions) async throws {
        try await withWriteLock(wc: wc, operation: "cleanup") {
            try await backend.cleanup(wc: wc, options: options)
        }
    }

    public func resolve(wc: URL, path: String, accept: ResolveAccept) async throws {
        try await withWriteLock(wc: wc, operation: "resolve") {
            try await backend.resolve(wc: wc, path: path, accept: accept)
        }
    }

    public func applyPatch(wc: URL, patchFile: URL) async throws {
        try await withWriteLock(wc: wc, operation: "patch") {
            let beforeRejects = rejectFiles(in: wc)
            try await backend.applyPatch(wc: wc, patchFile: patchFile)
            let newRejects = rejectFiles(in: wc).subtracting(beforeRejects)
            if !newRejects.isEmpty {
                throw PatchPathError.rejectedPaths(newRejects.sorted())
            }
        }
    }

    private func rejectFiles(in workingCopy: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: workingCopy,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return Set(enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "rej" else { return nil }
            return url.path
        })
    }

    public func setProperty(wc: URL, target: String, name: String, value: String) async throws {
        try await withWriteLock(wc: wc, operation: "setProperty") {
            try await backend.setProperty(wc: wc, target: target, name: name, value: value)
        }
    }

    public func deleteProperty(wc: URL, target: String, name: String) async throws {
        try await withWriteLock(wc: wc, operation: "deleteProperty") {
            try await backend.deleteProperty(wc: wc, target: target, name: name)
        }
    }

    public func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws {
        try await withWriteLock(wc: wc, operation: "lock") {
            try await backend.lock(wc: wc, paths: paths, message: message, force: force)
        }
    }

    public func unlock(wc: URL, paths: [String], force: Bool) async throws {
        try await withWriteLock(wc: wc, operation: "unlock") {
            try await backend.unlock(wc: wc, paths: paths, force: force)
        }
    }

    private func withWriteLock<T: Sendable>(
        wc: URL,
        operation: String,
        body: () async throws -> T
    ) async throws -> T {
        if let activeOperation = activeWriteOperations[wc] {
            throw SvnServiceError.wcBusy(operation: activeOperation)
        }

        activeWriteOperations[wc] = operation
        defer {
            activeWriteOperations.removeValue(forKey: wc)
        }

        return try await body()
    }

    private func conflictingSelectedPaths(paths: [String], statuses: [FileStatus]) -> [String] {
        let statusesByPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0) })

        return paths.filter { path in
            guard let status = statusesByPath[path] else {
                return false
            }

            return status.itemStatus == .conflicted || status.isTreeConflict
        }
    }

    private func localChangePaths(from statuses: [FileStatus]) -> [String] {
        statuses.compactMap { status in
            if status.isTreeConflict {
                return status.path
            }

            switch status.itemStatus {
            case .normal, .none, .ignored, .external:
                return nil
            case .unversioned, .modified, .added, .deleted, .missing, .conflicted, .replaced, .incomplete, .obstructed:
                return status.path
            }
        }
    }

    private func requireCommitMessage(_ message: String) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SvnServiceError.emptyCommitMessage
        }
    }

    private func credentialScope(for value: String) -> URL {
        URL(string: value) ?? URL(fileURLWithPath: value)
    }

    private func retryingAuthentication<T: Sendable>(
        wc: URL,
        initialAuth: Credential?,
        operation: (Credential?) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(initialAuth)
        } catch SvnError.authentication {
            guard let credential = try await credentialProvider?.credential(for: wc) else {
                throw SvnError.authentication
            }

            return try await operation(credential)
        }
    }
}

extension SvnService: WorkingCopyInfoProviding {}
