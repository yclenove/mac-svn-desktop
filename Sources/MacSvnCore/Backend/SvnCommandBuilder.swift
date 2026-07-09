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

    public static func status() -> SvnCommand {
        SvnCommand(arguments: ["status", "--xml", "--non-interactive"])
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
        arguments += ["--non-interactive", "-r", "\(from):0", "-l", String(batch)]
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

    public static func info(target: String) -> SvnCommand {
        SvnCommand(arguments: ["info", "--xml", "--non-interactive", target])
    }
}
