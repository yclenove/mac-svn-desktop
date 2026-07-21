import Foundation
import MacSvnCore

enum MacSvnProjectPropertyLoader {
    static func ancestorTargets(for relativePaths: [String], workingCopy: URL) -> [String] {
        let directories = ancestorTargetChains(for: relativePaths, workingCopy: workingCopy)
            .compactMap(\.last)

        let commonDirectory = commonDirectoryTarget(for: directories)
        return targetChain(for: commonDirectory)
    }

    /// 每个选中路径都有自己的项目属性继承链；不能只读取它们的共同祖先。
    static func ancestorTargetChains(for relativePaths: [String], workingCopy: URL) -> [[String]] {
        let directories = relativePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
            .map { directoryTarget(for: $0, workingCopy: workingCopy) }

        guard !directories.isEmpty else { return [["."]] }
        var seen = Set<String>()
        return directories.compactMap { directory in
            guard seen.insert(directory).inserted else { return nil }
            return targetChain(for: directory)
        }
    }

    static func load(
        svnService: SvnService,
        workingCopy: URL,
        relativePaths: [String]
    ) async throws -> ProjectPropertyPolicy {
        async let infoRequest = try? svnService.info(wc: workingCopy, target: ".")
        let chains = ancestorTargetChains(for: relativePaths, workingCopy: workingCopy)
        let uniqueTargets = Array(Set(chains.flatMap { $0 })).sorted { lhs, rhs in
            if lhs == "." { return true }
            if rhs == "." { return false }
            return lhs < rhs
        }
        var propertiesByTarget: [String: [SvnProperty]] = [:]
        for target in uniqueTargets {
            propertiesByTarget[target] = try await svnService.properties(wc: workingCopy, target: target)
        }
        let info = await infoRequest
        let policies = chains.map { chain in
            ProjectPropertyPolicy(
                propertySets: chain.map { propertiesByTarget[$0] ?? [] },
                repositoryRoot: info?.repositoryRoot
            )
        }
        return ProjectPropertyPolicy.combining(policies)
    }

    private static func targetChain(for directory: String) -> [String] {
        guard directory != "." else { return ["."] }
        var targets = ["."]
        var current = ""
        for component in directory.split(separator: "/") {
            current = current.isEmpty ? String(component) : current + "/" + component
            targets.append(current)
        }
        return targets
    }

    private static func directoryTarget(for path: String, workingCopy: URL) -> String {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL = workingCopy.appendingPathComponent(normalizedPath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return normalizedPath
        }

        // Status records do not encode node kind. For absent paths, a parent is safer than guessing from an extension.
        let directory = (normalizedPath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "." : directory
    }

    private static func commonDirectoryTarget(for paths: [String]) -> String {
        guard var common = paths.first?.split(separator: "/").map(String.init) else { return "." }
        for path in paths.dropFirst() {
            let components = path.split(separator: "/").map(String.init)
            common = Array(zip(common, components).prefix { $0 == $1 }.map(\.0))
            if common.isEmpty { return "." }
        }
        return common.isEmpty ? "." : common.joined(separator: "/")
    }
}
