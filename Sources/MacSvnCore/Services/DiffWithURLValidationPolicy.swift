import Foundation

public enum DiffWithURLValidationError: Error, Equatable, Sendable {
    case invalidWorkingCopy
    case emptyTarget
    case invalidURL
    case invalidRevision
    case conflictingRevisions
}

public struct DiffWithURLRequest: Equatable, Sendable {
    public let workingCopy: URL
    public let target: String
    public let url: String
    public let revision: Revision?

    public init(workingCopy: URL, target: String, url: String, revision: Revision?) {
        self.workingCopy = workingCopy
        self.target = target
        self.url = url
        self.revision = revision
    }
}

public enum DiffWithURLValidationPolicy {
    public static func validate(
        workingCopy: URL,
        target: String,
        url: String,
        revisionText: String
    ) throws -> DiffWithURLRequest {
        guard !workingCopy.path.isEmpty else {
            throw DiffWithURLValidationError.invalidWorkingCopy
        }

        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            throw DiffWithURLValidationError.emptyTarget
        }

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = URL(string: trimmedURL),
              parsedURL.password == nil,
              isSupported(parsedURL)
        else {
            throw DiffWithURLValidationError.invalidURL
        }

        let explicitRevision = try parseRevision(revisionText)
        let pegRevision = trailingPegRevision(in: trimmedURL)
        if let explicitRevision, let pegRevision, explicitRevision != pegRevision {
            throw DiffWithURLValidationError.conflictingRevisions
        }

        let effectiveRevision = explicitRevision ?? pegRevision
        let effectiveURL: String
        if pegRevision != nil {
            effectiveURL = trimmedURL
        } else if let effectiveRevision {
            effectiveURL = "\(trimmedURL)@\(effectiveRevision)"
        } else {
            effectiveURL = trimmedURL
        }

        return DiffWithURLRequest(
            workingCopy: workingCopy,
            target: trimmedTarget,
            url: effectiveURL,
            revision: effectiveRevision
        )
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["svn", "svn+ssh", "http", "https", "file"].contains(scheme)
        else {
            return false
        }

        if scheme == "file" {
            return !url.path.isEmpty
        }
        guard let host = url.host else { return false }
        return !host.isEmpty
    }

    private static func parseRevision(_ text: String) throws -> Revision? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value >= 0 else {
            throw DiffWithURLValidationError.invalidRevision
        }
        return Revision(value)
    }

    private static func trailingPegRevision(in url: String) -> Revision? {
        guard let at = url.lastIndex(of: "@"), at < url.index(before: url.endIndex) else {
            return nil
        }
        let suffix = String(url[url.index(after: at)...])
        guard let value = Int(suffix), value >= 0 else { return nil }
        return Revision(value)
    }
}
