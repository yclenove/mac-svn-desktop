import Foundation

public enum MacSvnAutomationTarget: Equatable, Sendable {
    case path(String)
    case repositoryURL(String)
}

public enum MacSvnDeepLinkAction: Equatable, Sendable {
    case open(path: String)
    case log(target: MacSvnAutomationTarget, revision: Revision?)
    case diff(target: MacSvnAutomationTarget, range: RevisionRange?)
}

public enum MacSvnDeepLinkParserError: Error, Equatable, Sendable {
    case invalidScheme(String?)
    case missingRoute
    case unknownRoute(String)
    case missingTarget
    case missingParameter(String)
    case invalidRevision(String)
}
