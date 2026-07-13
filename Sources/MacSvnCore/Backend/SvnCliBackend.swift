import Foundation

public struct SvnCliBackend: SvnBackend {
    private let svnExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(svnExecutable: String, runner: any ProcessRunning, timeout: TimeInterval = 120) {
        self.svnExecutable = svnExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func version() async throws -> SvnVersion {
        let command = SvnCommandBuilder.version()
        let result = try await run(command, currentDirectory: nil, stdin: nil)
        return try SvnVersion.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func status(wc: URL) async throws -> [FileStatus] {
        let command = SvnCommandBuilder.status(verbose: true, showUpdates: false)
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try StatusXMLParser.parse(result.stdout)
    }

    public func statusAgainstRepository(wc: URL) async throws -> [FileStatus] {
        let command = SvnCommandBuilder.status(verbose: true, showUpdates: true)
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try StatusXMLParser.parse(result.stdout)
    }

    public func update(
        wc: URL,
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async throws -> UpdateSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.update(
            paths: paths,
            revision: revision,
            setDepth: setDepth,
            ignoreExternals: ignoreExternals,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try UpdateOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func switchTo(
        wc: URL,
        url: String,
        revision: Revision? = nil,
        auth: Credential? = nil
    ) async throws -> UpdateSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.switchTo(
            url: normalizedRemoteURL(url),
            revision: revision,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try UpdateOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func merge(
        wc: URL,
        source: String,
        range: RevisionRange? = nil,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.merge(
            source: normalizedRemoteURL(source),
            range: range,
            dryRun: dryRun,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try MergeOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.merge(
            from: normalizedRemoteURL(from),
            to: normalizedRemoteURL(to),
            dryRun: dryRun,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try MergeOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func mergeReintegrate(
        wc: URL,
        source: String,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.mergeReintegrate(
            source: normalizedRemoteURL(source),
            dryRun: dryRun,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try MergeOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func mergeRevisionTo(
        wc: URL,
        source: String,
        revision: Revision,
        dryRun: Bool,
        auth: Credential? = nil
    ) async throws -> MergeSummary {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.mergeRevisionTo(
            source: normalizedRemoteURL(source),
            revision: revision,
            dryRun: dryRun,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try MergeOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?,
        keepLocks: Bool = false
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.commit(
            paths: paths,
            message: message,
            authArguments: authArguments.arguments,
            keepLocks: keepLocks
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func add(wc: URL, paths: [String]) async throws {
        _ = try await run(SvnCommandBuilder.add(paths: paths), currentDirectory: wc.path, stdin: nil)
    }

    public func assignChangelist(
        wc: URL,
        name: String,
        paths: [String],
        depth: SvnDepth
    ) async throws {
        _ = try await run(
            SvnCommandBuilder.assignChangelist(name: name, paths: paths, depth: depth),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func removeFromChangelists(
        wc: URL,
        paths: [String],
        depth: SvnDepth
    ) async throws {
        _ = try await run(
            SvnCommandBuilder.removeFromChangelists(paths: paths, depth: depth),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func delete(wc: URL, paths: [String]) async throws {
        _ = try await run(SvnCommandBuilder.delete(paths: paths), currentDirectory: wc.path, stdin: nil)
    }

    public func deleteKeepingLocal(wc: URL, paths: [String]) async throws {
        _ = try await run(SvnCommandBuilder.deleteKeepingLocal(paths: paths), currentDirectory: wc.path, stdin: nil)
    }

    public func deleteUnversioned(wc: URL, paths: [String]) async throws {
        for path in paths {
            try FileManager.default.removeItem(at: wc.appendingPathComponent(path))
        }
    }

    public func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        // Repair Move：源常为 missing（磁盘上无文件）。先把未版本目标挪回源路径，再 svn move。
        let fileManager = FileManager.default
        let sourceURL = wc.appendingPathComponent(source)
        let destinationURL = wc.appendingPathComponent(destination)

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            _ = try await run(
                SvnCommandBuilder.workingCopyMove(source: source, destination: destination),
                currentDirectory: wc.path,
                stdin: nil
            )
            return
        }

        let asideURL = wc.appendingPathComponent(".svnstudio-repair-\(UUID().uuidString)")
        do {
            try fileManager.moveItem(at: destinationURL, to: asideURL)
            // 恢复 missing 源，使 svn move 能在 WC 内调度历史保留的移动
            if !fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.moveItem(at: asideURL, to: sourceURL)
            } else {
                try fileManager.moveItem(at: asideURL, to: destinationURL)
            }
            _ = try await run(
                SvnCommandBuilder.workingCopyMove(source: source, destination: destination),
                currentDirectory: wc.path,
                stdin: nil
            )
        } catch {
            // 失败时尽量恢复用户文件到目标路径
            if fileManager.fileExists(atPath: asideURL.path) {
                try? fileManager.moveItem(at: asideURL, to: destinationURL)
            } else if fileManager.fileExists(atPath: sourceURL.path),
                      !fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            throw error
        }
    }

    public func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        // 目标冲突已由 RenameValidationPolicy 拦截；直接 svn rename
        _ = try await run(
            SvnCommandBuilder.rename(source: source, destination: destination),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        try await repairCopyWithExistingDestination(
            wc: wc,
            destination: destination,
            command: SvnCommandBuilder.workingCopyCopy(source: source, destination: destination)
        )
    }

    public func repairFilenameCaseConflict(wc: URL, source: String, destination: String) async throws {
        let parent = (source as NSString).deletingLastPathComponent
        let temporaryName = ".svnstudio-case-repair-" + UUID().uuidString
        let temporary = parent.isEmpty || parent == "."
            ? temporaryName
            : (parent as NSString).appendingPathComponent(temporaryName)
        var staged = false

        do {
            _ = try await run(
                SvnCommandBuilder.rename(source: source, destination: temporary),
                currentDirectory: wc.path,
                stdin: nil
            )
            staged = true
            _ = try await run(
                SvnCommandBuilder.rename(source: temporary, destination: destination),
                currentDirectory: wc.path,
                stdin: nil
            )
        } catch {
            // 第二步失败时恢复原名，避免把工作副本留在隐藏临时路径。
            if staged {
                _ = try? await run(
                    SvnCommandBuilder.rename(source: temporary, destination: source),
                    currentDirectory: wc.path,
                    stdin: nil
                )
            }
            throw error
        }
    }

    /// Repair Copy：目标未版本文件先挪开，执行 `svn copy`，再盖回用户内容（`svn copy` 无 `--force`）。
    private func repairCopyWithExistingDestination(wc: URL, destination: String, command: SvnCommand) async throws {
        let fileManager = FileManager.default
        let destinationURL = wc.appendingPathComponent(destination)
        var asideURL: URL?

        if fileManager.fileExists(atPath: destinationURL.path) {
            let aside = wc.appendingPathComponent(".svnstudio-repair-\(UUID().uuidString)")
            try fileManager.moveItem(at: destinationURL, to: aside)
            asideURL = aside
        }

        do {
            _ = try await run(command, currentDirectory: wc.path, stdin: nil)
            if let asideURL {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: asideURL, to: destinationURL)
            }
        } catch {
            if let asideURL, fileManager.fileExists(atPath: asideURL.path) {
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    // svn 未写出目标：把用户文件放回原路径后继续抛出原错误
                    try? fileManager.moveItem(at: asideURL, to: destinationURL)
                } else {
                    // svn 可能已成功但盖回失败：用 aside 覆盖目标；成功则视为修复完成
                    do {
                        try fileManager.removeItem(at: destinationURL)
                        try fileManager.moveItem(at: asideURL, to: destinationURL)
                        return
                    } catch {
                        throw SvnError.other(
                            code: nil,
                            stderr: "修复复制后恢复用户文件失败，内容保留在 \(asideURL.lastPathComponent)：\(error)"
                        )
                    }
                }
            }
            throw error
        }
    }

    public func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        _ = try await run(SvnCommandBuilder.revert(paths: paths, recursive: recursive), currentDirectory: wc.path, stdin: nil)
    }

    public func cleanup(wc: URL, options: SvnCleanupOptions = .default) async throws {
        _ = try await run(SvnCommandBuilder.cleanup(options: options), currentDirectory: wc.path, stdin: nil)
    }

    public func resolve(wc: URL, path: String, accept: ResolveAccept) async throws {
        _ = try await run(
            SvnCommandBuilder.resolve(path: path, accept: accept),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        let result = try await run(SvnCommandBuilder.diff(target: target, r1: r1, r2: r2), currentDirectory: wc.path, stdin: nil)
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String {
        let request = try DiffWithURLValidationPolicy.validate(
            workingCopy: wc,
            target: target,
            url: url,
            revisionText: revision?.description ?? ""
        )
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.diffWithURL(
            url: normalizedRemoteURL(request.url),
            target: request.target,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        let result = try await run(
            SvnCommandBuilder.diffBetweenPaths(oldPath: oldPath, newPath: newPath),
            currentDirectory: wc.path,
            stdin: nil
        )
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func repositoryDiff(
        wc: URL,
        oldURL: String,
        oldRevision: Revision,
        newURL: String,
        newRevision: Revision,
        auth: Credential?
    ) async throws -> String {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.repositoryDiff(
                oldURL: normalizedRemoteURL(oldURL),
                oldRevision: oldRevision,
                newURL: normalizedRemoteURL(newURL),
                newRevision: newRevision,
                authArguments: authArguments.arguments
            ),
            currentDirectory: wc.path,
            stdin: authArguments.stdin
        )
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func diffAgainstBase(wc: URL, target: String) async throws -> String {
        let result = try await run(
            SvnCommandBuilder.diffAgainstBase(target: target),
            currentDirectory: wc.path,
            stdin: nil
        )
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func applyPatch(wc: URL, patchFile: URL) async throws {
        _ = try await run(
            SvnCommandBuilder.patch(patchFile: patchFile.path),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func blame(wc: URL, target: String) async throws -> [BlameLine] {
        try await blame(wc: wc, target: target, startRevision: nil, endRevision: nil)
    }

    public func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine] {
        let result = try await run(
            SvnCommandBuilder.blame(
                target: target,
                startRevision: startRevision,
                endRevision: endRevision
            ),
            currentDirectory: wc.path,
            stdin: nil
        )
        return try BlameXMLParser.parse(result.stdout)
    }

    public func properties(wc: URL, target: String) async throws -> [SvnProperty] {
        let result = try await run(SvnCommandBuilder.proplist(target: target), currentDirectory: wc.path, stdin: nil)
        return try PropertyXMLParser.parse(result.stdout)
    }

    public func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty? {
        let result = try await run(SvnCommandBuilder.propget(name: name, target: target), currentDirectory: wc.path, stdin: nil)
        return try PropertyXMLParser.parse(result.stdout).first
    }

    public func setProperty(wc: URL, target: String, name: String, value: String) async throws {
        _ = try await run(
            SvnCommandBuilder.propset(name: name, value: value, target: target),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func deleteProperty(wc: URL, target: String, name: String) async throws {
        _ = try await run(
            SvnCommandBuilder.propdel(name: name, target: target),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func revisionProperties(
        wc: URL,
        target: String,
        revision: Revision,
        auth: Credential?
    ) async throws -> [SvnProperty] {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.revisionProplist(
                target: target,
                revision: revision,
                authArguments: authArguments.arguments
            ),
            currentDirectory: wc.path,
            stdin: authArguments.stdin
        )
        return try PropertyXMLParser.parse(result.stdout)
    }

    public func setRevisionProperty(
        wc: URL,
        target: String,
        revision: Revision,
        name: String,
        value: String,
        auth: Credential?
    ) async throws {
        let authArguments = try AuthArguments.build(credential: auth)
        let valueFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("svnstudio-revprop-\(UUID().uuidString)")
        try Data(value.utf8).write(to: valueFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: valueFile.path
        )
        defer { try? FileManager.default.removeItem(at: valueFile) }
        _ = try await run(
            SvnCommandBuilder.revisionPropset(
                name: name,
                valueFile: valueFile.path,
                target: target,
                revision: revision,
                authArguments: authArguments.arguments
            ),
            currentDirectory: wc.path,
            stdin: authArguments.stdin
        )
    }

    public func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        let result = try await run(
            SvnCommandBuilder.lockStatus(targets: targets),
            currentDirectory: wc.path,
            stdin: nil
        )
        return try LockStatusXMLParser.parse(result.stdout)
    }

    public func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws {
        _ = try await run(
            SvnCommandBuilder.lock(paths: paths, message: message, force: force),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func unlock(wc: URL, paths: [String], force: Bool) async throws {
        _ = try await run(
            SvnCommandBuilder.unlock(paths: paths, force: force),
            currentDirectory: wc.path,
            stdin: nil
        )
    }

    public func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool = false
    ) async throws -> [LogEntry] {
        let command = SvnCommandBuilder.log(
            target: target,
            from: from,
            batch: batch,
            verbose: verbose,
            stopOnCopy: stopOnCopy
        )
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try LogXMLParser.parse(result.stdout)
    }

    public func remoteLog(
        url: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        auth: Credential? = nil
    ) async throws -> [LogEntry] {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.log(
            target: normalizedRemoteURL(url),
            from: from,
            batch: batch,
            verbose: verbose,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: nil, stdin: authArguments.stdin)
        return try LogXMLParser.parse(result.stdout)
    }

    public func remoteLogFromHead(
        url: String,
        batch: Int,
        verbose: Bool,
        auth: Credential? = nil
    ) async throws -> [LogEntry] {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.logFromHead(
            target: normalizedRemoteURL(url),
            batch: batch,
            verbose: verbose,
            authArguments: authArguments.arguments
        )
        let result = try await run(command, currentDirectory: nil, stdin: authArguments.stdin)
        return try LogXMLParser.parse(result.stdout)
    }

    public func list(
        url: String,
        depth: SvnDepth,
        auth: Credential? = nil
    ) async throws -> [RemoteEntry] {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.list(
                url: url,
                depth: depth,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try ListXMLParser.parse(result.stdout)
    }

    public func listWithLocks(
        url: String,
        depth: SvnDepth,
        auth: Credential? = nil
    ) async throws -> [RemoteEntry] {
        let authArguments = try AuthArguments.build(credential: auth)
        let normalizedURL = normalizedRemoteURL(url)
        let result = try await run(
            SvnCommandBuilder.remoteInfo(
                url: normalizedURL,
                depth: depth,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try RemoteInfoXMLParser.parseDirectoryEntries(result.stdout, targetURL: normalizedURL)
    }

    public func cat(
        url: String,
        revision: Revision? = nil,
        sizeLimit: Int,
        auth: Credential? = nil
    ) async throws -> Data {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.cat(
                url: normalizedRemoteURL(url),
                revision: revision,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )

        guard result.stdout.count <= sizeLimit else {
            throw SvnError.fileTooLarge(limit: sizeLimit, actual: result.stdout.count)
        }

        return result.stdout
    }

    public func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth = .infinity,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async throws {
        let authArguments = try AuthArguments.build(credential: auth)
        _ = try await run(
            SvnCommandBuilder.checkout(
                url: url,
                to: destination.path,
                depth: depth,
                revision: revision,
                ignoreExternals: ignoreExternals,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
    }

    public func export(
        url: String,
        to destination: URL,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async throws {
        let authArguments = try AuthArguments.build(credential: auth)
        _ = try await run(
            SvnCommandBuilder.export(
                url: normalizedRemoteURL(url),
                to: destination.path,
                revision: revision,
                ignoreExternals: ignoreExternals,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
    }

    public func importProject(
        path: URL,
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.`import`(
                path: path.path,
                url: normalizedRemoteURL(url),
                message: message,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func relocate(
        wc: URL,
        from: String,
        to: String,
        auth: Credential? = nil
    ) async throws {
        let authArguments = try AuthArguments.build(credential: auth)
        _ = try await run(
            SvnCommandBuilder.relocate(
                from: normalizedRemoteURL(from),
                to: normalizedRemoteURL(to),
                workingCopy: wc.path,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
    }

    public func removeFromVersionControl(path: URL, recursive: Bool) async throws {
        try VersionControlRemovalPolicy.validate(path)
        let fileManager = FileManager.default
        let metadata = path.appendingPathComponent(".svn")
        guard fileManager.fileExists(atPath: metadata.path) else { return }
        try fileManager.removeItem(at: metadata)
    }

    public func copy(
        source: String,
        destination: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.copy(
                source: normalizedRemoteURL(source),
                destination: normalizedRemoteURL(destination),
                message: message,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func mkdir(
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.mkdir(
                url: normalizedRemoteURL(url),
                message: message,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func delete(
        url: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.delete(
                url: normalizedRemoteURL(url),
                message: message,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func move(
        source: String,
        destination: String,
        message: String,
        auth: Credential? = nil
    ) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let result = try await run(
            SvnCommandBuilder.move(
                source: normalizedRemoteURL(source),
                destination: normalizedRemoteURL(destination),
                message: message,
                authArguments: authArguments.arguments
            ),
            currentDirectory: nil,
            stdin: authArguments.stdin
        )
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func info(wc: URL, target: String) async throws -> SvnInfo {
        let result = try await run(SvnCommandBuilder.info(target: target), currentDirectory: wc.path, stdin: nil)
        return try InfoXMLParser.parse(result.stdout)
    }

    public func repositoryHeadRevision(wc: URL, target: String) async throws -> Revision {
        let result = try await run(
            SvnCommandBuilder.info(target: target, revisionSpec: "HEAD"),
            currentDirectory: wc.path,
            stdin: nil
        )
        let info = try InfoXMLParser.parse(result.stdout)
        guard let revision = info.revision else {
            throw SvnError.parse(detail: "svn info -r HEAD 未返回 revision")
        }
        return revision
    }

    private func run(_ command: SvnCommand, currentDirectory: String?, stdin: Data?) async throws -> ProcessResult {
        let result = try await runner.run(
            executable: svnExecutable,
            arguments: command.arguments,
            stdin: stdin,
            currentDirectory: currentDirectory,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw SvnErrorMapper.map(exitCode: result.exitCode, stderr: result.stderr)
        }

        return result
    }

    private func normalizedRemoteURL(_ value: String) -> String {
        URL(string: value)?.absoluteString ?? value
    }
}
