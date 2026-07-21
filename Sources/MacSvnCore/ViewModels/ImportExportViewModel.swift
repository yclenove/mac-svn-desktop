import Foundation
import Observation

public protocol ImportExportProviding: Sendable {
    func export(url: String, to destination: URL, revision: Revision?, ignoreExternals: Bool, auth: Credential?) async throws
    func importProject(path: URL, url: String, message: String, auth: Credential?) async throws -> Revision
    func importInPlace(path: URL, url: String, message: String, auth: Credential?) async throws -> Revision
    func relocate(wc: URL, from: String, to: String, auth: Credential?) async throws
    func removeFromVersionControl(path: URL, recursive: Bool) async throws
}

public enum ImportExportState: Equatable, Sendable {
    case idle
    case running
    case completed(String)
    case error(String)
}

@MainActor
@Observable
public final class ImportExportViewModel {
    private let provider: any ImportExportProviding
    public private(set) var state: ImportExportState = .idle

    public init(provider: any ImportExportProviding) {
        self.provider = provider
    }

    public func export(
        url: String,
        to destination: URL,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential? = nil
    ) async {
        await perform {
            try await provider.export(url: url, to: destination, revision: revision, ignoreExternals: ignoreExternals, auth: auth)
            return "导出完成：(destination.path)"
        }
    }

    public func importProject(path: URL, url: String, message: String, auth: Credential? = nil) async {
        await perform {
            let revision = try await provider.importProject(path: path, url: url, message: message, auth: auth)
            return "导入完成：r\(revision.value)"
        }
    }

    public func importInPlace(path: URL, url: String, message: String, auth: Credential? = nil) async {
        await perform {
            let revision = try await provider.importInPlace(path: path, url: url, message: message, auth: auth)
            return "就地导入完成：r\(revision.value)"
        }
    }

    public func relocate(wc: URL, from: String, to: String, auth: Credential? = nil) async {
        await perform {
            try await provider.relocate(wc: wc, from: from, to: to, auth: auth)
            return "工作副本已重新定位"
        }
    }

    public func removeFromVersionControl(path: URL, recursive: Bool = true) async {
        await perform {
            try await provider.removeFromVersionControl(path: path, recursive: recursive)
            return "已移除版本控制元数据：(path.path)"
        }
    }

    private func perform(_ operation: () async throws -> String) async {
        state = .running
        do {
            state = .completed(try await operation())
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: ImportExportProviding {}
