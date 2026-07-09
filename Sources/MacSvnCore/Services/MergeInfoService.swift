import Foundation

public protocol MergeInfoPropertyProviding: Sendable {
    func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty?
}

public protocol MergeInfoProviding: Sendable {
    func mergeInfo(wc: URL, target: String) async throws -> [MergeInfoEntry]
}

public struct MergeInfoService: MergeInfoProviding {
    private let propertyProvider: any MergeInfoPropertyProviding

    public init(propertyProvider: any MergeInfoPropertyProviding) {
        self.propertyProvider = propertyProvider
    }

    public func mergeInfo(wc: URL, target: String) async throws -> [MergeInfoEntry] {
        guard let property = try await propertyProvider.propertyValue(
            wc: wc,
            target: target,
            name: "svn:mergeinfo"
        ) else {
            return []
        }

        return try MergeInfoParser.parse(property.value)
    }
}

extension SvnService: MergeInfoPropertyProviding {}

extension SvnService: MergeInfoProviding {
    public func mergeInfo(wc: URL, target: String) async throws -> [MergeInfoEntry] {
        try await MergeInfoService(propertyProvider: self).mergeInfo(wc: wc, target: target)
    }
}
