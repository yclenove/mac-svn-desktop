import Foundation
import Observation

/// 属性冲突解决：展示双方属性侧文件内容，并按 Mine/Theirs 整文件 resolve。
public protocol PropertyConflictResolving: Sendable {
    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws
}

public enum PropertyConflictResolution: Equatable, Sendable {
    case keepMine
    case keepTheirs
}

public enum PropertyConflictViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case resolving
    case resolved(PropertyConflictResolution)
    case error(String)
}

@MainActor
@Observable
public final class PropertyConflictViewModel {
    private let conflict: ConflictInfo
    private let workingCopy: URL
    private let resolver: any PropertyConflictResolving
    private let fileReader: (URL) throws -> String

    public private(set) var state: PropertyConflictViewState = .idle
    public private(set) var mineValue: String = ""
    public private(set) var theirsValue: String = ""
    public private(set) var baseValue: String = ""

    public init(
        conflict: ConflictInfo,
        workingCopy: URL,
        resolver: any PropertyConflictResolving,
        fileReader: @escaping (URL) throws -> String = { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    ) {
        self.conflict = conflict
        self.workingCopy = workingCopy
        self.resolver = resolver
        self.fileReader = fileReader
    }

    public var path: String {
        conflict.path
    }

    /// 加载属性冲突双方侧文件内容（相对 WC 路径或绝对路径）。
    public func load() async {
        state = .loading
        do {
            mineValue = try readSideFile(conflict.mineFile)
            theirsValue = try readSideFile(conflict.theirsFile)
            baseValue = try readSideFile(conflict.baseFile)
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func resolve(_ resolution: PropertyConflictResolution) async {
        state = .resolving
        let accept: ResolveAccept = resolution == .keepMine ? .mineFull : .theirsFull
        do {
            try await resolver.resolveWholeFile(conflict, wc: workingCopy, accept: accept)
            state = .resolved(resolution)
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func readSideFile(_ relativeOrAbsolute: String?) throws -> String {
        guard let relativeOrAbsolute, !relativeOrAbsolute.isEmpty else {
            return ""
        }
        let url: URL
        if relativeOrAbsolute.hasPrefix("/") {
            url = URL(fileURLWithPath: relativeOrAbsolute)
        } else {
            url = workingCopy.appendingPathComponent(relativeOrAbsolute)
        }
        return try fileReader(url)
    }
}

extension ConflictService: PropertyConflictResolving {}
