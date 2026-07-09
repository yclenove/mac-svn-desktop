public struct SvnCommand: Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public enum SvnCommandBuilder {
    public static func status() -> SvnCommand {
        SvnCommand(arguments: ["status", "--xml", "--non-interactive"])
    }

    public static func commit(paths: [String], message: String) -> SvnCommand {
        SvnCommand(arguments: [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", message
        ] + paths)
    }

    public static func update(paths: [String] = [], revision: Revision? = nil) -> SvnCommand {
        var arguments = ["update", "--accept", "postpone", "--non-interactive"]

        if let revision {
            arguments += ["-r", revision.description]
        }

        arguments += paths
        return SvnCommand(arguments: arguments)
    }
}
