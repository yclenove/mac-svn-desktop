import Foundation

/// Quick Look 预览文本生成（FR-EX-08）：优先 svn diff，冲突给三路提示，二进制给引导文案。
public struct QuickLookPreviewTextBuilder: Sendable {
    public enum DiffOutcome: Equatable, Sendable {
        case ok(String)
        case failed(String)
    }

    public typealias DiffRunner = @Sendable (_ workingCopy: URL, _ target: String) -> DiffOutcome

    private let diffRunner: DiffRunner

    public init(diffRunner: DiffRunner? = nil) {
        self.diffRunner = diffRunner ?? Self.defaultSvnDiffRunner
    }

    /// - Parameters:
    ///   - fileURL: Finder 选中的文件
    ///   - preferredRoots: 已知 WC 根（如 finder-sync-roots）；为空则向上查找 `.svn`
    public func build(for fileURL: URL, preferredRoots: [String] = []) -> String {
        let standardized = fileURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return "文件不存在：\n\(standardized.path)"
        }
        if isDirectory.boolValue {
            return "目录不支持 Diff 预览。请在 MacSVN 中打开工作副本。"
        }

        guard let workingCopy = Self.locateWorkingCopy(containing: standardized, preferredRoots: preferredRoots) else {
            return "该文件不在已登记的 SVN 工作副本内，无法生成 Diff 预览。\n\(standardized.path)"
        }

        if let conflict = Self.conflictSummary(for: standardized) {
            return conflict
        }

        guard let target = Self.relativeTarget(for: standardized, in: workingCopy) else {
            return "无法解析相对路径：\n\(standardized.path)"
        }

        switch diffRunner(workingCopy, target) {
        case .ok(let diff):
            let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isBinaryDiff(diff) {
                return "二进制文件，请在 MacSVN Diff 页查看：\n\(standardized.path)"
            }
            if trimmed.isEmpty {
                return "工作副本相对基线无文本差异（或文件未改动）。\n\(target)"
            }
            return "MacSVN Diff — \(target)\n\n\(diff)"
        case .failed(let message):
            return "无法生成 SVN Diff 预览：\(message)\n请在 MacSVN Diff 页打开：\n\(standardized.path)"
        }
    }

    public static func locateWorkingCopy(containing fileURL: URL, preferredRoots: [String]) -> URL? {
        let path = fileURL.standardizedFileURL.path
        let matched = preferredRoots
            .map { ($0 as NSString).standardizingPath }
            .filter { path == $0 || path.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
        if let matched {
            return URL(fileURLWithPath: matched, isDirectory: true)
        }

        var cursor = fileURL.standardizedFileURL.deletingLastPathComponent()
        for _ in 0..<64 {
            let svn = cursor.appendingPathComponent(".svn", isDirectory: true)
            if FileManager.default.fileExists(atPath: svn.path) {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }

    private static func relativeTarget(for fileURL: URL, in workingCopy: URL) -> String? {
        let wcPath = workingCopy.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(wcPath + "/") else { return nil }
        return String(filePath.dropFirst(wcPath.count + 1))
    }

    private static func isBinaryDiff(_ diff: String) -> Bool {
        let normalized = diff.lowercased()
        return (normalized.contains("cannot display") && normalized.contains("binary"))
            || normalized.contains("binary files")
    }

    private static func conflictSummary(for fileURL: URL) -> String? {
        let path = fileURL.path
        let mine = path + ".mine"
        let fm = FileManager.default
        let hasMine = fm.fileExists(atPath: mine)
        let parent = fileURL.deletingLastPathComponent()
        let name = fileURL.lastPathComponent
        let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
        let revSides = siblings.filter { $0.hasPrefix(name + ".r") }
        guard hasMine || !revSides.isEmpty else { return nil }

        var lines = ["检测到 SVN 冲突文件：\(name)", ""]
        if hasMine { lines.append("· 本地侧：\(name).mine") }
        for side in revSides.sorted() {
            lines.append("· 版本侧：\(side)")
        }
        lines.append("")
        lines.append("请在 MacSVN 冲突页完成三路合并。")
        return lines.joined(separator: "\n")
    }

    private static let defaultSvnDiffRunner: DiffRunner = { workingCopy, target in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["svn", "diff", "--non-interactive", "--", target]
        process.currentDirectoryURL = workingCopy
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
                + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
        ]) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            if process.terminationStatus == 0 {
                return .ok(text)
            }
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .ok(text)
            }
            return .failed(err.isEmpty ? "svn diff exit \(process.terminationStatus)" : err)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
