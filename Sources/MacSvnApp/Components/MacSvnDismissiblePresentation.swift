import SwiftUI

private struct MacSvnDismissiblePresentationModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let compact: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .help("关闭")
                        .accessibilityLabel("关闭弹窗")
                        .accessibilityIdentifier("macSvn.modal.close")
                    }
                    .padding(.horizontal, compact ? 8 : 12)
                    .frame(height: compact ? 34 : 40)
                    Divider()
                }
                .background(.bar)
            }
    }
}

extension View {
    func macSvnDismissibleSheet() -> some View {
        modifier(MacSvnDismissiblePresentationModifier(compact: false))
    }

    func macSvnDismissiblePopover() -> some View {
        modifier(MacSvnDismissiblePresentationModifier(compact: true))
    }
}
