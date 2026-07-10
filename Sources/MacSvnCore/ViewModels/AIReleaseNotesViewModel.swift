import Foundation
import Observation

public enum AIReleaseNotesViewState: Equatable, Sendable {
    case idle
    case loadingLogs
    case ready
    case generating
    case completed(AIReleaseNotesDraft)
    case error(String)
}

/// Release Notes 页状态：加载日志范围 → 调用 AI 生成 Markdown 草稿（FR-AI-05）。
@MainActor
@Observable
public final class AIReleaseNotesViewModel {
    private let logProvider: any LogProviding
    private let generator: any AIReleaseNotesGenerating

    public private(set) var state: AIReleaseNotesViewState = .idle
    public private(set) var entries: [LogEntry] = []
    public private(set) var draft: AIReleaseNotesDraft?

    public var title: String = "Release Notes"
    public var template: AIReleaseNotesTemplate = .standardMarkdown

    public init(logProvider: any LogProviding, generator: any AIReleaseNotesGenerating) {
        self.logProvider = logProvider
        self.generator = generator
    }

    /// 使用外部已选日志（例如从日志页带入）。
    public func loadEntries(_ entries: [LogEntry]) {
        self.entries = entries
        draft = nil
        state = entries.isEmpty ? .idle : .ready
    }

    /// 从工作副本拉取最近一批日志作为候选。
    public func loadRecentLogs(wc: URL, batch: Int = 50) async {
        state = .loadingLogs
        draft = nil
        do {
            let loaded = try await logProvider.log(
                wc: wc,
                target: ".",
                from: Revision(Int.max),
                batch: batch,
                verbose: true,
                stopOnCopy: false
            )
            entries = loaded
            state = loaded.isEmpty ? .idle : .ready
        } catch {
            entries = []
            state = .error(String(describing: error))
        }
    }

    public func generate(privacySettings: AIPrivacySettings) async {
        guard !entries.isEmpty else {
            state = .error(String(describing: AIReleaseNotesError.emptyLogSelection))
            return
        }

        state = .generating
        do {
            let result = try await generator.generate(
                entries: entries,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Release Notes"
                    : title,
                template: template,
                privacySettings: privacySettings
            )
            draft = result
            state = .completed(result)
        } catch {
            draft = nil
            state = .error(String(describing: error))
        }
    }
}
