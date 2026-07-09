public enum MergeOutputParser {
    public static func parse(_ output: String) throws -> MergeSummary {
        var summary = MergeSummary()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let actionLine = parseActionLine(String(rawLine)) else {
                continue
            }

            summary.record(action: actionLine.action, path: actionLine.path)
        }

        return summary
    }

    private static func parseActionLine(_ line: String) -> (action: MergeAction, path: String)? {
        guard let statusIndex = statusIndex(in: line) else {
            return nil
        }

        let afterStatusIndex = line.index(after: statusIndex)
        guard
            afterStatusIndex < line.endIndex,
            line[afterStatusIndex].isWhitespace,
            let pathStart = line[afterStatusIndex...].firstIndex(where: { !$0.isWhitespace })
        else {
            return nil
        }

        return (MergeAction(rawStatus: line[statusIndex]), String(line[pathStart...]))
    }

    private static func statusIndex(in line: String) -> String.Index? {
        let searchableEnd = line.index(line.startIndex, offsetBy: min(7, line.count), limitedBy: line.endIndex) ?? line.endIndex
        var index = line.startIndex

        while index < searchableEnd {
            let character = line[index]

            if isMergeStatus(character) {
                let prefix = line[..<index]
                return prefix.allSatisfy(\.isWhitespace) ? index : nil
            }

            guard character.isWhitespace else {
                return nil
            }

            index = line.index(after: index)
        }

        return nil
    }

    private static func isMergeStatus(_ character: Character) -> Bool {
        switch character {
        case "A", "U", "D", "C", "G", "E", "R":
            return true
        default:
            return false
        }
    }
}
