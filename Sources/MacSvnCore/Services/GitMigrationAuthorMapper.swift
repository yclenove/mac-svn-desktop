import Foundation

public struct GitMigrationAuthorMapper: Sendable {
    public init() {}

    public func draftMappings(from authors: [GitMigrationAuthor]) -> [GitMigrationAuthorMapping] {
        let usernames = Set(authors.map(\.svnUsername))

        return usernames
            .sorted()
            .map { username in
                GitMigrationAuthorMapping(svnUsername: username, gitName: "", gitEmail: "")
            }
    }

    public func coverage(for mappings: [GitMigrationAuthorMapping]) -> GitMigrationAuthorMappingCoverage {
        let coveredCount = mappings.filter { mapping in
            !mapping.gitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !mapping.gitEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .count

        return GitMigrationAuthorMappingCoverage(
            totalCount: mappings.count,
            coveredCount: coveredCount
        )
    }

    public func validateComplete(_ mappings: [GitMigrationAuthorMapping]) throws {
        let incompleteAuthors = mappings
            .filter { mapping in
                mapping.gitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    mapping.gitEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map(\.svnUsername)
            .sorted()

        if !incompleteAuthors.isEmpty {
            throw GitMigrationAuthorMappingError.incompleteAuthors(incompleteAuthors)
        }
    }

    public func authorsFileContents(from mappings: [GitMigrationAuthorMapping]) throws -> String {
        try validateComplete(mappings)

        return mappings
            .sorted { $0.svnUsername < $1.svnUsername }
            .map { mapping in
                let svnUsername = mapping.svnUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                let gitName = mapping.gitName.trimmingCharacters(in: .whitespacesAndNewlines)
                let gitEmail = mapping.gitEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(svnUsername) = \(gitName) <\(gitEmail)>"
            }
            .joined(separator: "\n") + "\n"
    }

    public func parseAuthorsFile(_ text: String) throws -> [GitMigrationAuthorMapping] {
        var mappings: [GitMigrationAuthorMapping] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            guard
                let separatorRange = line.range(of: " = "),
                let emailStart = line.lastIndex(of: "<"),
                line.hasSuffix(">"),
                separatorRange.upperBound < emailStart
            else {
                throw GitMigrationAuthorMappingError.invalidAuthorsFileLine(line)
            }

            let svnUsername = String(line[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let gitName = String(line[separatorRange.upperBound..<emailStart])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let emailEnd = line.index(before: line.endIndex)
            let gitEmail = String(line[line.index(after: emailStart)..<emailEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !svnUsername.isEmpty, !gitName.isEmpty, !gitEmail.isEmpty else {
                throw GitMigrationAuthorMappingError.invalidAuthorsFileLine(line)
            }

            mappings.append(GitMigrationAuthorMapping(
                svnUsername: svnUsername,
                gitName: gitName,
                gitEmail: gitEmail
            ))
        }

        return mappings.sorted { $0.svnUsername < $1.svnUsername }
    }

    public func exportAuthorsFile(_ mappings: [GitMigrationAuthorMapping], to fileURL: URL) throws {
        let contents = try authorsFileContents(from: mappings)
        let directory = fileURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func importAuthorsFile(from fileURL: URL) throws -> [GitMigrationAuthorMapping] {
        try parseAuthorsFile(String(contentsOf: fileURL, encoding: .utf8))
    }
}
