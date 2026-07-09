import Foundation

public struct MacSvnCLICommandParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> MacSvnCLICommand {
        guard let command = arguments.first else {
            throw MacSvnCLICommandParserError.emptyArguments
        }

        switch command {
        case "open":
            return .open(path: try singlePath(arguments))
        case "status":
            return .status(path: try singlePath(arguments))
        case "commit-ui":
            return try parseCommitUI(Array(arguments.dropFirst()))
        default:
            throw MacSvnCLICommandParserError.unknownCommand(command)
        }
    }

    private func singlePath(_ arguments: [String]) throws -> String {
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            throw MacSvnCLICommandParserError.missingValue("path")
        }
        guard arguments.count == 2 else {
            throw MacSvnCLICommandParserError.unexpectedArgument(arguments[2])
        }
        return arguments[1]
    }

    private func parseCommitUI(_ arguments: [String]) throws -> MacSvnCLICommand {
        guard let path = arguments.first, !path.isEmpty else {
            throw MacSvnCLICommandParserError.missingValue("path")
        }

        var message: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--message":
                let valueIndex = index + 1
                guard valueIndex < arguments.count, !arguments[valueIndex].isEmpty else {
                    throw MacSvnCLICommandParserError.missingValue("--message")
                }
                message = arguments[valueIndex]
                index += 2
            default:
                throw MacSvnCLICommandParserError.unexpectedArgument(argument)
            }
        }

        return .commitUI(path: path, initialMessage: message)
    }
}
