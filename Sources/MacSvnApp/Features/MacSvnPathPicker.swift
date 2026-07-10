import SwiftUI
import MacSvnCore

/// 从当前 WC 的 status 列表选择目标路径（Blame/属性/锁定/搁置共用）。
struct MacSvnPathPicker: View {
    let paths: [String]
    @Binding var selection: Set<String>
    var allowsMultiple: Bool = true

    var body: some View {
        List(selection: $selection) {
            ForEach(paths, id: \.self) { path in
                Text(path).tag(path)
            }
        }
        .onChange(of: selection) { _, newValue in
            if !allowsMultiple, newValue.count > 1, let last = newValue.sorted().last {
                selection = [last]
            }
        }
    }
}

enum MacSvnPathLoader {
    static func loadPaths(svnService: SvnService, wc: URL) async -> [String] {
        (try? await svnService.status(wc: wc))?.map(\.path).sorted() ?? []
    }
}
