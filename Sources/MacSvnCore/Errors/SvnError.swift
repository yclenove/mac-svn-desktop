public enum SvnError: Error, Equatable, Sendable {
    case environment(detail: String)
    case authentication
    case outOfDate
    case wcLocked
    case conflict(paths: [String])
    case network(detail: String)
    case parse(detail: String)
    case cancelled
    case other(code: Int?, stderr: String)
}
