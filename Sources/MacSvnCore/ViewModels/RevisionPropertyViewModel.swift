import Foundation
import Observation

public protocol RevisionPropertyProviding: Sendable {
    func revisionProperties(wc: URL, target: String, revision: Revision) async throws -> [SvnProperty]
    func setRevisionProperty(
        wc: URL,
        target: String,
        revision: Revision,
        name: String,
        value: String
    ) async throws
}

public enum RevisionPropertyViewState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class RevisionPropertyViewModel {
    private let workingCopy: URL
    public let target: String
    public let revision: Revision
    private let provider: any RevisionPropertyProviding

    public private(set) var state: RevisionPropertyViewState = .idle
    public private(set) var properties: [SvnProperty] = []
    public private(set) var author = ""
    public private(set) var message = ""

    public init(
        workingCopy: URL,
        target: String,
        revision: Revision,
        provider: any RevisionPropertyProviding
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.revision = revision
        self.provider = provider
    }

    public func load() async {
        state = .loading
        await refresh()
    }

    public func save(author: String, message: String) async {
        let normalizedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAuthor.isEmpty else {
            state = .error("emptyRevisionAuthor")
            return
        }

        state = .saving
        do {
            let authorChanged = normalizedAuthor != author
            let messageChanged = message != self.message
            if authorChanged {
                try await provider.setRevisionProperty(
                    wc: workingCopy,
                    target: target,
                    revision: revision,
                    name: "svn:author",
                    value: normalizedAuthor
                )
            }
            if messageChanged {
                try await provider.setRevisionProperty(
                    wc: workingCopy,
                    target: target,
                    revision: revision,
                    name: "svn:log",
                    value: message
                )
            }
            guard authorChanged || messageChanged else {
                state = .loaded
                return
            }
            await refresh()
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func refresh() async {
        do {
            properties = try await provider.revisionProperties(
                wc: workingCopy,
                target: target,
                revision: revision
            ).sorted { $0.name < $1.name }
            author = properties.first(where: { $0.name == "svn:author" })?.value ?? ""
            message = properties.first(where: { $0.name == "svn:log" })?.value ?? ""
            state = .loaded
        } catch {
            properties = []
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: RevisionPropertyProviding {
    public func revisionProperties(
        wc: URL,
        target: String,
        revision: Revision
    ) async throws -> [SvnProperty] {
        try await revisionProperties(wc: wc, target: target, revision: revision, auth: nil)
    }

    public func setRevisionProperty(
        wc: URL,
        target: String,
        revision: Revision,
        name: String,
        value: String
    ) async throws {
        try await setRevisionProperty(
            wc: wc,
            target: target,
            revision: revision,
            name: name,
            value: value,
            auth: nil
        )
    }
}
