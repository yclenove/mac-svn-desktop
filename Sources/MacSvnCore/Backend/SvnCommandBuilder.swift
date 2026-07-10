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

    public static func commit(paths: [String], message: String, authArguments: [String] = []) -> SvnCommand {
        SvnCommand(arguments: [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + authArguments + paths)
    }

    public static func update(
        paths: [String] = [],
        revision: Revision? = nil,
        setDepth: SvnDepth? = nil,
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

        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func switchTo(url: String, authArguments: [String] = []) -> SvnCommand {
        SvnCommand(arguments: [
            "switch", "--accept", "postpone", "--non-interactive"
        ] + authArguments + [url])
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

    public static func resolve(path: String, accept: ResolveAccept) -> SvnCommand {
        SvnCommand(arguments: [
            "resolve", "--accept", accept.rawValue, "--non-interactive", path
        ])
    }

    public static func add(paths: [String]) -> SvnCommand {
        SvnCommand(arguments: ["add", "--non-interactive"] + paths)
    }

    public static func delete(paths: [String]) -> SvnCommand {
        SvnCommand(arguments: ["delete", "--non-interactive"] + paths)
    }

    public static func revert(paths: [String], recursive: Bool) -> SvnCommand {
        var arguments = ["revert", "--non-interactive"]
        if recursive {
            arguments.append("--recursive")
        }
        arguments += paths
        return SvnCommand(arguments: arguments)
    }

    public static func cleanup() -> SvnCommand {
        SvnCommand(arguments: ["cleanup", "--non-interactive"])
    }

    public static func diff(target: String, r1: Revision?, r2: Revision?) -> SvnCommand {
        var arguments = ["diff", "--non-interactive"]
        if let r1, let r2 {
            arguments += ["-r", "\(r1):\(r2)"]
        }
        arguments.append(target)
        return SvnCommand(arguments: arguments)
    }

    public static func patch(patchFile: String) -> SvnCommand {
        SvnCommand(arguments: ["patch", "--non-interactive", patchFile])
    }

    public static func blame(target: String) -> SvnCommand {
        SvnCommand(arguments: ["blame", "--xml", "--non-interactive", target])
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

        arguments += ["--non-interactive", name, value, target]
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
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["log", "--xml"]
        if verbose {
            arguments.append("-v")
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
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["log", "--xml"]
        if verbose {
            arguments.append("-v")
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
        authArguments: [String] = []
    ) -> SvnCommand {
        SvnCommand(arguments: [
            "checkout", "--non-interactive",
            "--depth", depth.rawValue
        ] + authArguments + [url, destination])
    }

    public static func export(
        url: String,
        to destination: String,
        revision: Revision? = nil,
        authArguments: [String] = []
    ) -> SvnCommand {
        var arguments = ["export", "--non-interactive"]

        if let revision {
            arguments += ["-r", revision.description]
        }

        arguments += authArguments
        arguments += [url, destination]
        return SvnCommand(arguments: arguments)
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

    public static func info(target: String) -> SvnCommand {
        SvnCommand(arguments: ["info", "--xml", "--non-interactive", target])
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
