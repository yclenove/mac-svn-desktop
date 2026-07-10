#if canImport(QuickLookUI)
import Cocoa
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look 预览骨架：供 Xcode QL 扩展 target 引用。
/// SwiftPM 阶段不编译；包装工程中实现 `QLPreviewProvider`。
enum MacSvnQuickLookPreviewBuilder {
    /// 根据文件路径生成纯文本预览（优先 svn diff）。
    static func plainTextPreview(for fileURL: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["svn", "diff", "--", fileURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
            if process.terminationStatus == 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        } catch {
            // fall through
        }
        return "无法生成 SVN Diff 预览。请在 MacSVN Diff 页打开：\n\(fileURL.path)"
    }
}
#endif
