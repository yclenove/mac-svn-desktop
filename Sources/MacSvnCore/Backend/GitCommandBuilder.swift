import Foundation

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

    public static func logGitSvnMetadata() -> GitCommand {
        GitCommand(arguments: ["log", "--all", "--format=%B"])
    }

    public static func svnFetch() -> GitCommand {
        GitCommand(arguments: ["svn", "fetch"])
    }

    public static func pushAll(remote: String) -> GitCommand {
        GitCommand(arguments: ["push", remote, "--all"])
    }

    public static func pushTags(remote: String) -> GitCommand {
        GitCommand(arguments: ["push", remote, "--tags"])
    }

    public static func svnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    ) -> GitCommand {
        var arguments = ["svn", "clone", "--authors-file", authorsFile.path]

        switch layout.kind {
        case .standard:
            arguments.append("--stdlayout")
        case .custom:
            if let trunkPath = layout.trunkPath {
                arguments += ["--trunk", trunkPath]
            }
            if let branchesPath = layout.branchesPath {
                arguments += ["--branches", branchesPath]
            }
            if let tagsPath = layout.tagsPath {
                arguments += ["--tags", tagsPath]
            }
        }

        if let revisionRange {
            arguments += ["--revision", revisionRange.description]
        }

        if let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--username", username]
        }

        arguments += [sourceURL, destination.path]
        return GitCommand(arguments: arguments)
    }
}
