import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let pageURL: URL

    public init(version: String, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }
}

public enum AppUpdateResult: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case updateAvailable(AppRelease)
}

public enum AppUpdateError: Error, Equatable, Sendable {
    case invalidCurrentVersion(String)
    case httpStatus(Int)
    case invalidReleaseMetadata
}

public struct AppVersion: Comparable, Sendable {
    private enum Identifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    private let core: [Int]
    private let prerelease: [Identifier]?
    public let isValid: Bool

    public init(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
        guard !normalized.isEmpty else {
            core = []
            prerelease = nil
            isValid = false
            return
        }
        let withoutBuild = normalized.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )[0]
        let portions = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreStrings = portions[0].split(separator: ".", omittingEmptySubsequences: false)
        let parsedCore = coreStrings.compactMap { Int($0) }
        guard !coreStrings.isEmpty,
              parsedCore.count == coreStrings.count,
              parsedCore.allSatisfy({ $0 >= 0 }) else {
            core = []
            prerelease = nil
            isValid = false
            return
        }

        core = parsedCore
        if portions.count == 2, !portions[1].isEmpty {
            prerelease = portions[1].split(separator: ".").map { value in
                if let number = Int(value) {
                    return .number(number)
                }
                return .text(value.lowercased())
            }
        } else {
            prerelease = nil
        }
        isValid = true
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.core.count, rhs.core.count)
        for index in 0..<componentCount {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (.some(let left), .some(let right)):
            for index in 0..<min(left.count, right.count) {
                guard left[index] != right[index] else { continue }
                switch (left[index], right[index]) {
                case (.number(let lhs), .number(let rhs)):
                    return lhs < rhs
                case (.number, .text):
                    return true
                case (.text, .number):
                    return false
                case (.text(let lhs), .text(let rhs)):
                    return lhs < rhs
                }
            }
            return left.count < right.count
        }
    }
}

public struct AppUpdateService: Sendable {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
        }
    }

    private let endpoint: URL
    private let dataLoader: DataLoader

    public init(
        endpoint: URL,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.endpoint = endpoint
        self.dataLoader = dataLoader
    }

    public func check(currentVersion: String) async throws -> AppUpdateResult {
        let installed = AppVersion(currentVersion)
        guard installed.isValid else {
            throw AppUpdateError.invalidCurrentVersion(currentVersion)
        }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SVNStudio-UpdateCheck", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await dataLoader(request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AppUpdateError.httpStatus(http.statusCode)
        }

        guard let metadata = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !metadata.draft,
              let pageURL = URL(string: metadata.htmlURL),
              let scheme = pageURL.scheme?.lowercased(),
              scheme == "https",
              pageURL.host != nil else {
            throw AppUpdateError.invalidReleaseMetadata
        }
        let available = AppVersion(metadata.tagName)
        guard available.isValid else {
            throw AppUpdateError.invalidReleaseMetadata
        }

        let normalizedVersion = metadata.tagName.drop(while: { $0 == "v" || $0 == "V" })
        if installed < available {
            return .updateAvailable(AppRelease(version: String(normalizedVersion), pageURL: pageURL))
        }
        return .upToDate(currentVersion: currentVersion)
    }
}
