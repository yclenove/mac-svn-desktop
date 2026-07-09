import Foundation

public enum UpdateOutputParser {
    public static func parse(_ output: String) throws -> UpdateSummary {
        var summary = UpdateSummary()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            parseAction(from: line, into: &summary)
            parseRevision(from: line, into: &summary)
        }

        return summary
    }

    private static func parseAction(from line: String, into summary: inout UpdateSummary) {
        guard
            let first = line.first,
            line.dropFirst().first?.isWhitespace == true
        else {
            return
        }

        switch first {
        case "A":
            summary.added += 1
        case "U":
            summary.updated += 1
        case "D":
            summary.deleted += 1
        case "C":
            summary.conflicted += 1
        case "G":
            summary.merged += 1
        case "E":
            summary.existed += 1
        case "R":
            summary.replaced += 1
        default:
            return
        }
    }

    private static func parseRevision(from line: String, into summary: inout UpdateSummary) {
        let patterns = [
            #"Updated to revision ([0-9]+)\."#,
            #"At revision ([0-9]+)\."#
        ]

        for pattern in patterns {
            guard let revision = firstCapturedInt(in: line, pattern: pattern) else {
                continue
            }

            summary.revision = Revision(revision)
            return
        }
    }

    private static func firstCapturedInt(in value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard
            let match = regex.firstMatch(in: value, range: range),
            let captureRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }

        return Int(value[captureRange])
    }
}
