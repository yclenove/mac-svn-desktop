public struct SvnCommand: Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public enum SvnCommandBuilder {
    public static func version() -> SvnCommand {
        SvnCommand(arguments: ["--version", "--quiet"])
    }

    public static func status(verbose: Bool = true, showUpdates: Bool = false) -> SvnCommand {
        // 对齐小乌龟 CFM：本地 `status -v`；Check Repository 再加 `--show-updates`（-u）
        var arguments = ["status"]
        if verbose {
            arguments.append("-v")
        }
        arguments.append("--xml")
        if showUpdates {
            arguments.append("--show-updates")
        }
        arguments.append("--non-interactive")
        return SvnCommand(arguments: arguments)
    }

    public static func lockStatus(targets: [String]) -> SvnCommand {
        SvnCommand(arguments: [
            "status", "--xml", "--show-updates", "--non-interactive"
        ] + targets)
    }

    public static func commit(
        paths: [String],
        message: String,
        authArguments: [String] = [],
        keepLocks: Bool = false
    ) -> SvnCommand {
        var arguments = [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ]
        // Keep locks：提交后不释放锁（对齐 Tortoise `--no-unlock`）
        if keepLocks {
            arguments.append("--no-unlock")
        }
        arguments += authArguments
        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func update(
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil,
        ignoreExternals: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["update", "--accept", "postpone", "--non-interactive"]
        arguments += authArguments

        if let revision {
            arguments += ["-r", revision.description]
        }

        if let setDepth {
            arguments += ["--set-depth", setDepth.rawValue]
        }

        if ignoreExternals {
            arguments.append("--ignore-externals")
        }

        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func switchTo(
        url: String,
        revision: Revision? = nil,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = [
            "switch", "--accept", "postpone", "--non-interactive"
        ] + authArguments
        if let revision {
            arguments += ["-r", revision.description]
        }
        arguments.append(url)
        return SvnCommand(arguments: arguments)
    }

    public static func merge(
        source: String,
        range: RevisionRange? = nil,
        dryRun: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["merge", "--accept", "postpone", "--non-interactive"]

        if dryRun {
            arguments.append("--dry-run")
        }

        arguments += authArguments

        if let range {
            arguments += ["-r", range.description]
        }

        arguments.append(source)
        return SvnCommand(arguments: arguments)
    }

    public static func merge(
        from: String,
        to: String,
        dryRun: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["merge", "--accept", "postpone", "--non-interactive"]
        if dryRun {
            arguments.append("--dry-run")
        }
        arguments += authArguments
        arguments += [from, to]
        return SvnCommand(arguments: arguments)
    }

    /// SVN 1.8+ 的完整合并就是现代 reintegrate 语义；旧的 --reintegrate 已废弃。
    public static func mergeReintegrate(
        source: String,
        dryRun: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        merge(source: source, range: nil, dryRun: dryRun, authArguments: authArguments)
    }

    public static func mergeRevisionTo(
        source: String,
        revision: Revision,
        dryRun: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["merge", "--accept", "postpone", "--non-interactive"]
        if dryRun {
            arguments.append("--dry-run")
        }
        arguments += authArguments
        arguments += ["-c", revision.description, source]
        return SvnCommand(arguments: arguments)
    }

    public static func resolve(path: String, accept: ResolveAccept) -> SvnCommand {
        SvnCommand(arguments: [
            "resolve", "--accept", accept.rawValue, "--non-interactive", path
        ])
    }

    public static func add(paths: [String]) -> SvnCommand {
        SvnCommand(arguments: ["add", "--non-interactive"] + paths)
    }

    public static func assignChangelist(
        name: String,
        paths: [String],
        depth: SvnDepth = .empty
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "changelist", name, "--depth", depth.rawValue, "--non-interactive"
        ] + paths)
    }

    public static func removeFromChangelists(
        paths: [String],
        depth: SvnDepth = .empty
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "changelist", "--remove", "--depth", depth.rawValue, "--non-interactive"
        ] + paths)
    }

    public static func delete(paths: [String]) -> SvnCommand {
        SvnCommand(arguments: ["delete", "--non-interactive"] + paths)
    }

    /// 工作副本内修复移动（无提交说明）。目标已存在时由 CliBackend 先挪开再执行。
    public static func workingCopyMove(source: String, destination: String) -> SvnCommand {
        SvnCommand(arguments: ["move", "--non-interactive", source, destination])
    }

    /// 同目录重命名（`svn rename`，与 move 同义；对齐小乌龟 Rename）。
    public static func rename(source: String, destination: String) -> SvnCommand {
        SvnCommand(arguments: ["rename", "--non-interactive", source, destination])
    }

    /// 工作副本内修复复制（无提交说明；`svn copy` 不支持 `--force`）。
    public static func workingCopyCopy(source: String, destination: String) -> SvnCommand {
        SvnCommand(arguments: ["copy", "--non-interactive", source, destination])
    }

    public static func revert(paths: [String], recursive: Bool) -> SvnCommand {
        var arguments = ["revert", "--non-interactive"]
        if recursive {
            arguments.append("--recursive")
        }
        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func cleanup(options: SvnCleanupOptions = .default) -> SvnCommand {
        var arguments = ["cleanup", "--non-interactive"]
        if options.breakLocks {
            arguments.append("--break-locks")
        }
        if options.vacuumPristines {
            arguments.append("--vacuum-pristines")
        }
        if options.includeExternals {
            arguments.append("--include-externals")
        }
        return SvnCommand(arguments: arguments)
    }

    public static func diff(target: String, r1: Revision?, r2: Revision?) -> SvnCommand {
        var arguments = ["diff", "--non-interactive"]
        if let r1, let r2 {
            arguments += ["-r", "\(r1):\(r2)"]
        } else if let r1 {
            // 单端修订（含显式 BASE 语义由调用方传 Revision 或走默认 WC vs BASE）
            arguments += ["-r", r1.description]
        }
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    /// 双任意文件 Diff（对齐小乌龟「比较两个文件」：`svn diff --old --new`）
    public static func diffBetweenPaths(oldPath: String, newPath: String) -> SvnCommand {
        SvnCommand(arguments: [
            "diff", "--non-interactive",
            "--old", oldPath,
            "--new", newPath
        ])
    }

    /// 仓库两个位置的历史 Diff，使用独立 peg revision 保证跨分支复制可比较。
    public static func repositoryDiff(
        oldURL: String,
        oldRevision: Revision,
        newURL: String,
        newRevision: Revision,
        authArguments: [String] = []
    ) -> SvnCommand {
        let oldPeg = LogChangedPathPolicy.pegURL(
            workingCopyURL: LogContextActionPolicy.stripPegRevision(from: oldURL),
            revision: oldRevision
        )
        let newPeg = LogChangedPathPolicy.pegURL(
            workingCopyURL: LogContextActionPolicy.stripPegRevision(from: newURL),
            revision: newRevision
        )
        return SvnCommand(arguments: [
            "diff", "--non-interactive"
        ] + authArguments + [
            "--old", oldPeg,
            "--new", newPeg
        ])
    }

    /// 工作副本目标与任意仓库 URL（可带 peg revision）的 Diff。
    public static func diffWithURL(
        url: String,
        target: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "diff", "--non-interactive"
        ] + authArguments + [
            "--old", url,
            "--new", localTargetWithPegDisambiguator(target)
        ])
    }

    private static func localTargetWithPegDisambiguator(_ target: String) -> String {
        guard target.contains("@"), !target.hasSuffix("@") else { return target }
        return target + "@"
    }

    /// 工作副本相对 BASE 的 Diff（显式 `-r BASE`，与无 -r 默认行为一致，便于 UI「对比 BASE」）
    public static func diffAgainstBase(target: String) -> SvnCommand {
        SvnCommand(arguments: ["diff", "--non-interactive", "-r", "BASE", target])
    }

    public static func patch(patchFile: String) -> SvnCommand {
        SvnCommand(arguments: ["patch", "--non-interactive", patchFile])
    }

    public static func blame(
        target: String,
        startRevision: Revision? = nil,
        endRevision: Revision? = nil
    ) -> SvnCommand {
        var arguments = ["blame", "--xml", "--non-interactive"]
        if let startRevision, let endRevision {
            arguments += ["-r", "\(startRevision):\(endRevision)"]
        } else if let startRevision {
            arguments += ["-r", "\(startRevision):HEAD"]
        } else if let endRevision {
            arguments += ["-r", "1:\(endRevision)"]
        }
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    public static func proplist(target: String) -> SvnCommand {
        SvnCommand(arguments: ["proplist", "--xml", "--verbose", "--non-interactive", target])
    }

    public static func propget(name: String, target: String) -> SvnCommand {
        SvnCommand(arguments: ["propget", "--xml", "--non-interactive", name, target])
    }

    public static func propset(name: String, value: String, target: String) -> SvnCommand {
        var arguments = ["propset"]

        if usesUTF8Encoding(forPropertyNamed: name) {
            arguments += ["--encoding", "UTF-8"]
        }

        // 属性值可能以 `-r` 等连字符开头；`--` 防止 SVN 把值误解析为选项。
        arguments += ["--non-interactive", "--", name, value, target]
        return SvnCommand(arguments: arguments)
    }

    public static func propdel(name: String, target: String) -> SvnCommand {
        SvnCommand(arguments: ["propdel", "--non-interactive", name, target])
    }

    public static func lock(paths: [String], message: String?, force: Bool) -> SvnCommand {
        var arguments = ["lock", "--encoding", "UTF-8", "--non-interactive"]

        if force {
            arguments.append("--force")
        }

        if let message, !message.isEmpty {
            arguments += ["-m", message]
        }

        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func unlock(paths: [String], force: Bool) -> SvnCommand {
        var arguments = ["unlock", "--non-interactive"]

        if force {
            arguments.append("--force")
        }

        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func log(
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["log", "--xml"]
        if verbose {
            arguments.append("-v")
        }
        if stopOnCopy {
            arguments.append("--stop-on-copy")
        }
        arguments += ["--non-interactive", "-r", "\(from):0", "-l", svnLimitArgument(batch)]
        arguments += authArguments
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    public static func logFromHead(
        target: String,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["log", "--xml"]
        if verbose {
            arguments.append("-v")
        }
        if stopOnCopy {
            arguments.append("--stop-on-copy")
        }
        arguments += ["--non-interactive", "-r", "HEAD:0", "-l", svnLimitArgument(batch)]
        arguments += authArguments
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    public static func list(
        url: String,
        depth: SvnDepth,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "list", "--xml", "--non-interactive",
            "--depth", depth.rawValue
        ] + authArguments + [url])
    }

    public static func remoteInfo(
        url: String,
        depth: SvnDepth,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "info", "--xml", "--non-interactive",
            "--depth", depth.rawValue
        ] + authArguments + [url])
    }

    public static func cat(
        url: String,
        revision: Revision? = nil,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["cat", "--non-interactive"]

        if let revision {
            arguments += ["-r", revision.description]
        }

        arguments += authArguments
        arguments.append(url)
        return SvnCommand(arguments: arguments)
    }

    public static func checkout(
        url: String,
        to destination: String,
        depth: SvnDepth = .infinity,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = [
            "checkout", "--non-interactive",
            "--depth", depth.rawValue
        ]
        if let revision {
            arguments += ["-r", revision.description]
        }
        if ignoreExternals {
            arguments.append("--ignore-externals")
        }
        arguments += authArguments
        arguments += [url, destination]
        return SvnCommand(arguments: arguments)
    }

    public static func export(
        url: String,
        to destination: String,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["export", "--non-interactive"]

        if let revision {
            arguments += ["-r", revision.description]
        }

        if ignoreExternals {
            arguments.append("--ignore-externals")
        }

        arguments += authArguments
        arguments += [url, destination]
        return SvnCommand(arguments: arguments)
    }

    public static func `import`(
        path: String,
        url: String,
        message: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "import", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + [path, url])
    }

    public static func relocate(
        from: String,
        to: String,
        workingCopy: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "switch", "--relocate", "--non-interactive"
        ] + authArguments + [from, to, workingCopy])
    }

    public static func copy(
        source: String,
        destination: String,
        message: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "copy", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + [source, destination])
    }

    public static func mkdir(
        url: String,
        message: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "mkdir", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + [url])
    }

    public static func delete(
        url: String,
        message: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "delete", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + [url])
    }

    public static func move(
        source: String,
        destination: String,
        message: String,
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "move", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + [source, destination])
    }

    public static func info(target: String, revisionSpec: String? = nil) -> SvnCommand {
        var arguments = ["info", "--xml", "--non-interactive"]
        if let revisionSpec, !revisionSpec.isEmpty {
            arguments += ["-r", revisionSpec]
        }
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    public static func experimentalShelve(
        name: String,
        paths: [String],
        message: String,
        keepLocal: Bool
    ) -> SvnCommand {
        var arguments = ["x-shelve"]
        if keepLocal {
            arguments.append("--keep-local")
        }
        arguments += ["--encoding", "UTF-8", "-m", message, "--", name]
        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func experimentalUnshelve(
        name: String,
        version: Int?,
        drop: Bool
    ) -> SvnCommand {
        var arguments = ["x-unshelve"]
        if drop {
            arguments.append("--drop")
        }
        arguments += ["--", name]
        if let version {
            arguments.append(String(version))
        }
        return SvnCommand(arguments: arguments)
    }

    public static func experimentalShelfList() -> SvnCommand {
        SvnCommand(arguments: ["x-shelf-list", "--verbose", "."])
    }

    public static func experimentalShelfDiff(name: String, version: Int?) -> SvnCommand {
        var arguments = ["x-shelf-diff", "--", name]
        if let version {
            arguments.append(String(version))
        }
        return SvnCommand(arguments: arguments)
    }

    public static func experimentalShelfLog(name: String) -> SvnCommand {
        SvnCommand(arguments: ["x-shelf-log", "--", name])
    }

    public static func experimentalShelfDrop(name: String) -> SvnCommand {
        SvnCommand(arguments: ["x-shelf-drop", "--", name, "."])
    }

    private static func usesUTF8Encoding(forPropertyNamed name: String) -> Bool {
        let textProperties: Set<String> = [
            "svn:eol-style",
            "svn:externals",
            "svn:global-ignores",
            "svn:ignore",
            "svn:keywords",
            "svn:mergeinfo",
            "svn:mime-type"
        ]
        return textProperties.contains(name)
    }

    private static func svnLimitArgument(_ batch: Int) -> String {
        String(min(batch, Int(Int32.max)))
    }
}
