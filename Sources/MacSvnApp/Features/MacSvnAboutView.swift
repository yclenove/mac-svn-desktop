import AppKit
import SwiftUI
import MacSvnCore

public struct MacSvnAboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityLabel("\(ProductBranding.displayName) 图标")

            VStack(spacing: 6) {
                Text(ProductBranding.displayName)
                    .font(.title.weight(.semibold))
                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("面向 macOS 的 Subversion 桌面客户端")
                .font(.body)
                .foregroundStyle(.secondary)

            Link(destination: ProductBranding.sourceRepositoryURL) {
                Label("项目主页", systemImage: "safari")
            }

            Text("Copyright 2026 SVN Studio contributors")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 420, height: 430)
    }

    private var versionText: String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case (.some(let version), .some(let build)):
            return "版本 \(version)（\(build)）"
        case (.some(let version), .none):
            return "版本 \(version)"
        default:
            return "开发构建"
        }
    }
}
