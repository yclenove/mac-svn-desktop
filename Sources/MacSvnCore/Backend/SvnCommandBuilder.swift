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

    public static func update(paths: [String] = [], revision: Revision? = nil) -> SvnCommand {
        var arguments = ["update", "--accept", "postpone", "--non-interactive"]

        if let revision {
            arguments += ["-r", revision.description]
        }

        arguments += paths
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

    public static func log(target: String, from: Revision, batch: Int, verbose: Bool) -> SvnCommand {
        var arguments = ["log", "--xml"]
        if verbose {
            arguments.append("-v")
        }
        arguments += ["--non-interactive", "-r", "\(from):0", "-l", String(batch), target]
        return SvnCommand(arguments: arguments)
    }
}
