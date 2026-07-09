public struct GitCommand: Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }
}

public enum GitCommandBuilder {
    public static func initRepository() -> GitCommand {
        GitCommand(arguments: ["init"])
    }

    public static func addAll() -> GitCommand {
        GitCommand(arguments: ["add", "."])
    }

    public static func commit(message: String) -> GitCommand {
        GitCommand(arguments: ["commit", "-m", message])
    }
}
