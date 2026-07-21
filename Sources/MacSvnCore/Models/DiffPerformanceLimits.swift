import Foundation

/// Diff / 变更工作区性能门禁常量与辅助方法。
///
/// 背景（2026-07-10）：嵌套 `VSplitView`+`HSplitView` 叠加数千行级 SwiftUI `Text` 子视图，
/// 会触发 AttributeGraph 无限更新（CPU 100%、UI 卡死）。
///
/// 约束：
/// 1. 变更工作区禁止嵌套 Split；用固定 `HStack`/`VStack` + `frame`
/// 2. 嵌入 Diff 禁止按行 `ForEach`；左右分栏使用两块完整 `Text` 列
/// 3. 超大 Diff 跳过逐行/并排结构解析，显示侧截断并引导外置工具
public enum DiffPerformanceLimits: Sendable {
    /// 超过此字符数时跳过 `parseLines` / `parseSideBySideRows`，避免构建海量模型对象。
    public static let maxParseCharacterCount = 200_000

    /// 嵌入或回退渲染时，界面最多展示的字符数（超出截断并提示）。
    public static let maxDisplayCharacterCount = 200_000

    /// 非嵌入模式下，允许按行 SwiftUI 子视图渲染的最大行数（含）。
    /// 超过则回退单块文本，防止 AttributeGraph 压力过大。
    public static let maxPerLineSwiftUIRowCount = 2_000

    /// 是否应对 unified diff 做逐行/并排结构解析。
    public static func shouldParseLineStructures(diffCharacterCount: Int) -> Bool {
        diffCharacterCount <= maxParseCharacterCount
    }

    /// 非嵌入且行数在安全阈值内时，才允许按行 SwiftUI 渲染。
    public static func shouldUsePerLineSwiftUI(lineOrRowCount: Int, embedded: Bool) -> Bool {
        guard !embedded else { return false }
        guard lineOrRowCount > 0 else { return false }
        return lineOrRowCount <= maxPerLineSwiftUIRowCount
    }

    public static func shouldUseEmbeddedSideBySide(rowCount: Int) -> Bool {
        rowCount > 0
    }

    /// 生成可安全塞进单个 `Text` 的展示字符串（超长截断）。
    public static func truncatedDisplayText(_ raw: String) -> String {
        guard raw.count > maxDisplayCharacterCount else { return raw }
        let idx = raw.index(raw.startIndex, offsetBy: maxDisplayCharacterCount)
        return String(raw[..<idx])
            + "\n\n… Diff 过长，已截断显示前 \(maxDisplayCharacterCount) 字符。请用外部 Diff 工具查看全文。"
    }
}
