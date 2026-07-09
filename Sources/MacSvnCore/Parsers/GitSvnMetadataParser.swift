import Foundation

public enum GitSvnMetadataParser {
    public static func parseRevisions(from text: String) -> [GitSvnRevisionMetadata] {
        let pattern = #"git-svn-id:\s+\S+@(\d+)\s+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let revisions = regex?.matches(in: text, range: range).compactMap { match -> Revision? in
            guard
                let matchRange = Range(match.range(at: 1), in: text),
                let value = Int(text[matchRange])
            else {
                return nil
            }

            return Revision(value)
        } ?? []

        return Set(revisions)
            .sorted { $0.value < $1.value }
            .map(GitSvnRevisionMetadata.init(revision:))
    }
}
