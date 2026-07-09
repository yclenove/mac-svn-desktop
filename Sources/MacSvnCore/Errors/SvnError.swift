public enum SvnError: Error, Equatable, Sendable {
    case environment(detail: String)
    case authentication
    case outOfDate
    case wcLocked
    case conflict(paths: [String])
    case network(detail: String)
    case fileTooLarge(limit: Int, actual: Int)
    case binaryFile
    case parse(detail: String)
    case cancelled
    case other(code: Int?, stderr: String)
}
