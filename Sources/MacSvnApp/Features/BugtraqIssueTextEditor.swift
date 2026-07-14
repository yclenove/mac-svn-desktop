import AppKit
import SwiftUI

/// 原生文本编辑器，保留系统拼写检查并按 Bugtraq 正则标注 issue 捕获组。
struct BugtraqIssueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let regexPatterns: [String]
    let spellcheckLanguage: String?

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
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        context.coordinator.attach(textView)
        context.coordinator.update(text: text, regexPatterns: regexPatterns, spellcheckLanguage: spellcheckLanguage)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(text: text, regexPatterns: regexPatterns, spellcheckLanguage: spellcheckLanguage)
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
        private var originalSpellcheckLanguage: String?
        private var originalAutomaticLanguageDetection: Bool?
        private var appliedSpellcheckLanguage: String?

        init(parent: BugtraqIssueTextEditor) {
            self.parent = parent
        }

        func attach(_ textView: NSTextView) {
            self.textView = textView
        }

        func update(text: String, regexPatterns: [String], spellcheckLanguage: String?) {
            self.regexPatterns = regexPatterns
            configureSpellcheckLanguage(spellcheckLanguage)
            guard let textView else { return }
            if textView.string != text {
                let selection = textView.selectedRange()
                isApplyingProgrammaticUpdate = true
                textView.string = text
                textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
                isApplyingProgrammaticUpdate = false
            }
            applyHighlights(to: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate, let textView else { return }
            parent.text = textView.string
            applyHighlights(to: textView)
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
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
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
