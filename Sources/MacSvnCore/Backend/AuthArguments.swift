import Foundation

public struct AuthArgumentResult: Equatable, Sendable {
    public let arguments: [String]
    public let stdin: Data?

    public init(arguments: [String], stdin: Data?) {
        self.arguments = arguments
        self.stdin = stdin
    }
}

public enum AuthArguments {
    public static func build(credential: Credential?) throws -> AuthArgumentResult {
        guard let credential else {
            return AuthArgumentResult(arguments: [], stdin: nil)
        }

        return AuthArgumentResult(
            arguments: ["--username", credential.username, "--password-from-stdin"],
            stdin: Data("\(credential.password)\n".utf8)
        )
    }
}
