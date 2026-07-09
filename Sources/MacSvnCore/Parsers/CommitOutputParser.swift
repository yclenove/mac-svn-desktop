import Foundation

public enum CommitOutputParser {
    public static func parseRevision(from output: String) throws -> Revision {
        let pattern = #"Committed revision ([0-9]+)\."#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)

        guard
            let match = regex.firstMatch(in: output, range: range),
            let revisionRange = Range(match.range(at: 1), in: output),
            let revision = Int(output[revisionRange])
        else {
            throw SvnError.parse(detail: "Unable to find committed revision in svn commit output.")
        }

        return Revision(revision)
    }
}
