import AppKit
import SwiftUI

/// 原生文本编辑器，保留系统拼写检查并按 Bugtraq 正则标注 issue 捕获组。
struct BugtraqIssueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let regexPatterns: [String]
    let spellcheckLanguage: String?
    let completionCandidates: [String]
    let isAutoCompletionEnabled: Bool
    let fontName: String?
    let fontSize: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        context.coordinator.attach(textView)
        context.coordinator.update(parent: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.restoreSpellcheckLanguage()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: BugtraqIssueTextEditor
        private weak var textView: NSTextView?
        private var isApplyingProgrammaticUpdate = false
        private var regexPatterns: [String] = []
        private var completionIndex = CommitMessageCompletionIndex(candidates: [])
        private var isAutoCompletionEnabled = false
        private var editorFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        private var originalSpellcheckLanguage: String?
        private var originalAutomaticLanguageDetection: Bool?
        private var appliedSpellcheckLanguage: String?

        init(parent: BugtraqIssueTextEditor) {
            self.parent = parent
        }

        func attach(_ textView: NSTextView) {
            self.textView = textView
        }

        func update(parent: BugtraqIssueTextEditor) {
            self.parent = parent
            regexPatterns = parent.regexPatterns
            if completionIndex.candidates != parent.completionCandidates {
                completionIndex = CommitMessageCompletionIndex(candidates: parent.completionCandidates)
            }
            isAutoCompletionEnabled = parent.isAutoCompletionEnabled
            editorFont = BugtraqIssueTextEditorFont.resolve(name: parent.fontName, size: parent.fontSize)
            configureSpellcheckLanguage(parent.spellcheckLanguage)
            guard let textView else { return }
            textView.isAutomaticTextCompletionEnabled = parent.isAutoCompletionEnabled
            textView.font = editorFont
            if textView.string != parent.text {
                let selection = textView.selectedRange()
                isApplyingProgrammaticUpdate = true
                textView.string = parent.text
                textView.setSelectedRange(NSRange(
                    location: min(selection.location, (parent.text as NSString).length),
                    length: 0
                ))
                isApplyingProgrammaticUpdate = false
            }
            applyHighlights(to: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate, let textView else { return }
            parent.text = textView.string
            applyHighlights(to: textView)
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard isAutoCompletionEnabled else { return [] }
            let text = textView.string as NSString
            guard charRange.location != NSNotFound, NSMaxRange(charRange) <= text.length else { return [] }
            let matches = completionIndex.matches(partial: text.substring(with: charRange))
            index?.pointee = matches.isEmpty ? -1 : 0
            return matches
        }

        func restoreSpellcheckLanguage() {
            guard originalSpellcheckLanguage != nil || originalAutomaticLanguageDetection != nil else { return }
            let spellChecker = NSSpellChecker.shared
            if let originalAutomaticLanguageDetection {
                spellChecker.automaticallyIdentifiesLanguages = originalAutomaticLanguageDetection
            }
            if let originalSpellcheckLanguage {
                _ = spellChecker.setLanguage(originalSpellcheckLanguage)
            }
            self.originalSpellcheckLanguage = nil
            self.originalAutomaticLanguageDetection = nil
            appliedSpellcheckLanguage = nil
        }

        private func configureSpellcheckLanguage(_ language: String?) {
            guard language != appliedSpellcheckLanguage else { return }
            let spellChecker = NSSpellChecker.shared
            if originalSpellcheckLanguage == nil {
                originalSpellcheckLanguage = spellChecker.language()
                originalAutomaticLanguageDetection = spellChecker.automaticallyIdentifiesLanguages
            }
            guard let language else {
                restoreSpellcheckLanguage()
                return
            }
            spellChecker.automaticallyIdentifiesLanguages = false
            guard spellChecker.setLanguage(language) else {
                restoreSpellcheckLanguage()
                return
            }
            appliedSpellcheckLanguage = language
        }

        private func applyHighlights(to textView: NSTextView) {
            let text = textView.string
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            storage.beginEditing()
            storage.setAttributes([
                .font: editorFont,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)
            for range in BugtraqIssueHighlighting.ranges(for: regexPatterns, in: text) {
                storage.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: range)
            }
            storage.endEditing()
        }

    }
}

enum BugtraqIssueTextEditorFont {
    static func resolve(name: String?, size: Double) -> NSFont {
        let resolvedSize = CGFloat(min(max(size, 9), 72))
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           let font = NSFont(name: name, size: resolvedSize) {
            return font
        }
        return NSFont.systemFont(ofSize: resolvedSize)
    }
}

enum CommitMessageCompletionCandidates {
    static func build(
        paths: [String],
        recentMessages: [String],
        timeout: TimeInterval,
        maxCandidates: Int = 512,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> [String] {
        guard timeout > 0, maxCandidates > 0 else { return [] }
        let deadline = now() + timeout
        var candidates: [String] = []
        var normalizedCandidates: Set<String> = []

        func append(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            let normalized = trimmed.lowercased()
            guard !normalizedCandidates.contains(normalized) else { return true }
            guard candidates.count < maxCandidates else { return false }
            normalizedCandidates.insert(normalized)
            candidates.append(trimmed)
            return true
        }

        for path in paths {
            guard now() < deadline else { return candidates }
            guard append(path) else { return candidates }
            let basename = (path as NSString).lastPathComponent
            guard append(basename) else { return candidates }
            guard append((basename as NSString).deletingPathExtension) else { return candidates }
        }

        let termRegex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}_-]{2,}"#)
        for message in recentMessages {
            guard now() < deadline else { return candidates }
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            var timedOut = false
            var reachedLimit = false
            termRegex?.enumerateMatches(in: message, range: range) { match, _, stop in
                guard now() < deadline else {
                    timedOut = true
                    stop.pointee = true
                    return
                }
                guard let match, let termRange = Range(match.range, in: message) else { return }
                guard append(String(message[termRange])) else {
                    reachedLimit = true
                    stop.pointee = true
                    return
                }
            }
            if timedOut || reachedLimit { return candidates }
        }
        return candidates
    }

    static func matches(candidates: [String], partial: String) -> [String] {
        CommitMessageCompletionIndex(candidates: candidates).matches(partial: partial)
    }
}

struct CommitMessageCompletionIndex {
    private struct Entry {
        let candidate: String
        let normalized: String
    }

    let candidates: [String]
    private let buckets: [Character: [Entry]]

    init(candidates: [String]) {
        self.candidates = candidates
        self.buckets = Dictionary(grouping: candidates.compactMap { candidate -> (Character, Entry)? in
            let normalized = Self.normalize(candidate)
            guard let first = normalized.first else { return nil }
            return (first, Entry(candidate: candidate, normalized: normalized))
        }, by: \.0).mapValues { $0.map(\.1) }
    }

    func matches(partial: String, maxResults: Int = 20) -> [String] {
        let normalizedPartial = Self.normalize(
            partial.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard maxResults > 0,
              let first = normalizedPartial.first,
              !normalizedPartial.isEmpty else { return [] }
        return buckets[first, default: []].lazy.compactMap { entry in
            guard entry.normalized != normalizedPartial,
                  entry.normalized.hasPrefix(normalizedPartial) else { return nil }
            return entry.candidate
        }.prefix(maxResults).map { $0 }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum BugtraqIssueHighlighting {
    static func ranges(for patterns: [String], in text: String) -> [NSRange] {
        switch patterns.count {
        case 1:
            return captureRanges(using: patterns[0], in: text)
        case 2:
            guard let outer = try? NSRegularExpression(pattern: patterns[0]) else { return [] }
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            return outer.matches(in: text, range: fullRange).flatMap { match -> [NSRange] in
                guard let range = Range(match.range, in: text) else { return [] }
                let matchedText = String(text[range])
                let offset = match.range.location
                return captureRanges(using: patterns[1], in: matchedText).map {
                    NSRange(location: offset + $0.location, length: $0.length)
                }
            }
        default:
            return []
        }
    }

    private static func captureRanges(using pattern: String, in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: fullRange).flatMap { match -> [NSRange] in
            guard match.numberOfRanges > 1 else { return [] }
            return (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : range
            }
        }
    }
}
