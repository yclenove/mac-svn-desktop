import Foundation
import Observation

public protocol PropertyProviding: Sendable {
    func properties(wc: URL, target: String) async throws -> [SvnProperty]
    func setProperty(wc: URL, target: String, name: String, value: String) async throws
    func deleteProperty(wc: URL, target: String, name: String) async throws
}

public enum PropertyViewState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case deleting
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class PropertyViewModel {
    nonisolated public static let commonTemplates: [SvnPropertyTemplate] = [
        SvnPropertyTemplate(name: "svn:ignore", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "svn:global-ignores", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "svn:externals", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "svn:mergeinfo", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "svn:eol-style", defaultValue: "native", appliesToDirectory: false, appliesToFile: true),
        SvnPropertyTemplate(name: "svn:keywords", defaultValue: "Id Author Date Rev HeadURL", appliesToDirectory: false, appliesToFile: true),
        SvnPropertyTemplate(name: "svn:executable", defaultValue: "*", appliesToDirectory: false, appliesToFile: true),
        SvnPropertyTemplate(name: "svn:needs-lock", defaultValue: "*", appliesToDirectory: false, appliesToFile: true),
        SvnPropertyTemplate(name: "tsvn:logminsize", defaultValue: "0", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logwidthmarker", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplate", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatecommit", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatebranch", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplateimport", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatedelete", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatemove", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatemkdir", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatepropset", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:logtemplatelock", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:projectlanguage", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "tsvn:lockmsgminsize", defaultValue: "0", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "bugtraq:url", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "bugtraq:message", defaultValue: "", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "bugtraq:number", defaultValue: "true", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "bugtraq:append", defaultValue: "false", appliesToDirectory: true, appliesToFile: false),
        SvnPropertyTemplate(name: "bugtraq:logregex", defaultValue: "", appliesToDirectory: true, appliesToFile: false)
    ]

    private let workingCopy: URL
    private let target: String
    private let provider: any PropertyProviding

    public private(set) var state: PropertyViewState = .idle
    public private(set) var properties: [SvnProperty] = []

    public init(workingCopy: URL, target: String, provider: any PropertyProviding) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
    }

    public func load() async {
        state = .loading
        await refreshProperties()
    }

    public func save(name: String, value: String) async {
        let propertyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propertyName.isEmpty else {
            state = .error("emptyPropertyName")
            return
        }

        state = .saving

        do {
            try await provider.setProperty(wc: workingCopy, target: target, name: propertyName, value: value)
            await refreshProperties()
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func delete(name: String) async {
        let propertyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propertyName.isEmpty else {
            state = .error("emptyPropertyName")
            return
        }

        state = .deleting

        do {
            try await provider.deleteProperty(wc: workingCopy, target: target, name: propertyName)
            await refreshProperties()
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func refreshProperties() async {
        do {
            properties = try await provider.properties(wc: workingCopy, target: target)
            state = .loaded
        } catch {
            properties = []
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: PropertyProviding {}
