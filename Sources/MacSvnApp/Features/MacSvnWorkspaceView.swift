import SwiftUI
import MacSvnCore

/// 工作副本管理页：列表、添加、移除。
public struct MacSvnWorkspaceView: View {
    @ObservedObject var controller: MacSvnWorkspaceController
    @State private var confirmRemove = false

    public init(controller: MacSvnWorkspaceController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("工作副本")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("添加…") { controller.presentAddPanel() }
                Button("移除") { confirmRemove = true }
                    .disabled(controller.selectedID == nil)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            List(selection: $controller.selectedID) {
                ForEach(controller.records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.name)
                                .font(.headline)
                            if record.isValid == false {
                                Text("无效")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(record.localPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.repoURL)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let revision = record.revision {
                            Text("r\(revision.value)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tag(record.id)
                    .opacity(record.isValid == false ? 0.55 : 1)
                }
            }
        }
        .task { await controller.reload() }
        .confirmationDialog(
            "仅从列表移除记录，不会删除磁盘文件。确认移除？",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                Task { await controller.removeSelected() }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
