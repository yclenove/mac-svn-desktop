import Foundation

public enum MergeInfoParser {
    public static func parse(_ value: String) throws -> [MergeInfoEntry] {
        var entries: [MergeInfoEntry] = []

        for rawLine in value.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            guard let separator = line.firstIndex(of: ":") else {
                throw SvnError.parse(detail: "Invalid svn:mergeinfo entry: \(line)")
            }

            let sourcePath = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rangeList = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sourcePath.isEmpty else {
                throw SvnError.parse(detail: "Invalid svn:mergeinfo source path: \(line)")
            }

            let ranges = try parseRanges(rangeList)
            entries.append(MergeInfoEntry(sourcePath: sourcePath, ranges: ranges))
        }

        return entries
    }

    private static func parseRanges(_ rangeList: String) throws -> [MergeInfoRevisionRange] {
        guard !rangeList.isEmpty else {
            throw SvnError.parse(detail: "Invalid svn:mergeinfo revision range: \(rangeList)")
        }

        return try rangeList
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { token in
                try parseRange(String(token).trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    private static func parseRange(_ token: String) throws -> MergeInfoRevisionRange {
        guard !token.isEmpty else {
            throw SvnError.parse(detail: "Invalid svn:mergeinfo revision range: \(token)")
        }

        let parts = token.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        guard
            let startValue = Int(parts[0]),
            startValue > 0
        else {
            throw SvnError.parse(detail: "Invalid svn:mergeinfo revision range: \(token)")
        }

        let endValue: Int
        if parts.count == 1 {
            endValue = startValue
        } else if let parsedEnd = Int(parts[1]), parsedEnd >= startValue {
            endValue = parsedEnd
        } else {
            throw SvnError.parse(detail: "Invalid svn:mergeinfo revision range: \(token)")
        }

        return MergeInfoRevisionRange(start: Revision(startValue), end: Revision(endValue))
    }
}
