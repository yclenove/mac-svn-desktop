import Foundation
import SwiftUI

enum MacSvnAuxiliaryWorkflowMetrics {
    static let toolbarHeight: CGFloat = 48
    static let masterWidth: CGFloat = 300
    static let masterMinimumWidth: CGFloat = 280
    static let masterMaximumWidth: CGFloat = 340
    static let detailMinimumWidth: CGFloat = 420
    static let feedbackHeight: CGFloat = 30
}

enum MacSvnAuxiliaryPathPresentation {
    static func relativePath(_ path: String, workingCopy: URL) -> String {
        guard (path as NSString).isAbsolutePath else { return path }

        let rootPath = workingCopy.standardizedFileURL.path
        let targetPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if targetPath == rootPath { return "." }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix) else { return path }
        return String(targetPath.dropFirst(rootPrefix.count))
    }

    static func title(for path: String) -> String {
        path == "." ? "工作副本根目录" : path
    }
}

struct MacSvnAuxiliaryPathList: View {
    let paths: [String]
    @Binding var selection: Set<String>
    @Binding var searchText: String
    var allowsMultiple = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("筛选目标", text: $searchText)
                    .textFieldStyle(.plain)
                Text("\(filteredPaths.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filteredPaths.count) 个目标")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            if filteredPaths.isEmpty {
                ContentUnavailableView("没有匹配的目标", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(filteredPaths, id: \.self) { path in
                        Text(MacSvnAuxiliaryPathPresentation.title(for: path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                            .tag(path)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            guard !allowsMultiple, newValue.count > 1 else { return }
            let newlySelected = newValue.subtracting(oldValue).first
                ?? newValue.sorted().last
            selection = newlySelected.map { [$0] } ?? []
        }
    }

    private var filteredPaths: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return paths }
        return paths.filter {
            MacSvnAuxiliaryPathPresentation.title(for: $0)
                .localizedCaseInsensitiveContains(query)
        }
    }
}
