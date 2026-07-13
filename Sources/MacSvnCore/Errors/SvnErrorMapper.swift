public enum SvnErrorMapper {
    public static func map(exitCode: Int32, stderr: String) -> SvnError {
        let code = firstErrorCode(in: stderr)

        switch code {
        case 170001, 215004:
            return .authentication
        case 155011, 160024:
            return .outOfDate
        case 155004:
            return .wcLocked
        case 170013, 175002:
            return .network(detail: stderr)
        default:
            return .other(code: code, stderr: stderr)
        }
    }

    private static func firstErrorCode(in stderr: String) -> Int? {
        guard let markerRange = stderr.range(of: ": E") else {
            return nil
        }

        let afterMarker = stderr[markerRange.upperBound...]
        let digits = afterMarker.prefix { character in
            character.isNumber
        }

        return Int(digits)
    }
}
