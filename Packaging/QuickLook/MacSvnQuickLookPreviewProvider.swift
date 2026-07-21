import Cocoa
import Quartz
import UniformTypeIdentifiers
import MacSvnCore

/// Quick Look 预览扩展：空格显示 SVN Diff / 冲突摘要（FR-EX-08）。
@objc(MacSvnQuickLookPreviewProvider)
final class MacSvnQuickLookPreviewProvider: QLPreviewProvider {
    private let textBuilder = QuickLookPreviewTextBuilder()

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let roots = loadPreferredRoots()
        let text = textBuilder.build(for: fileURL, preferredRoots: roots)
        let data = Data(text.utf8)
        let contentType = UTType.plainText
        let reply = QLPreviewReply(
            dataOfContentType: contentType,
            contentSize: CGSize(width: 800, height: 600)
        ) { _ in
            data
        }
        reply.stringEncoding = .utf8
        reply.title = "\(ProductBranding.displayName) Diff — \(fileURL.lastPathComponent)"
        return reply
    }

    private func loadPreferredRoots() -> [String] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(ProductBranding.supportDirectoryName)", isDirectory: true)
        let fileURL = FinderSyncRootsExporter.fileURL(in: support)
        return (try? FinderSyncRootsExporter.load(from: fileURL)) ?? []
    }
}
