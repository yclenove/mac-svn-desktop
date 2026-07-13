import Foundation
import MacSvnCore
import AppKit

/// 工作副本列表的 UI 控制器：加载、添加、移除，并跟踪当前选中项。
@MainActor
public final class MacSvnWorkspaceController: ObservableObject {
    @Published public private(set) var records: [WorkingCopyRecord] = []
    @Published public var selectedID: UUID?
    @Published public var errorMessage: String?

    private let workspaceStore: WorkspaceStore
    private let infoProvider: any WorkingCopyInfoProviding
    /// 用于导出 Finder Sync 根目录；测试可注入临时目录。
    private let supportDirectory: URL?

    public init(
        workspaceStore: WorkspaceStore,
        infoProvider: any WorkingCopyInfoProviding,
        supportDirectory: URL? = nil
    ) {
        self.workspaceStore = workspaceStore
        self.infoProvider = infoProvider
        self.supportDirectory = supportDirectory
    }

    public var selectedRecord: WorkingCopyRecord? {
        guard let selectedID else { return nil }
        return records.first(where: { $0.id == selectedID })
    }

    public func reload() async {
        do {
            records = try await workspaceStore.load()
            if let selectedID, !records.contains(where: { $0.id == selectedID }) {
                self.selectedID = records.first?.id
            } else if selectedID == nil {
                selectedID = records.first?.id
            }
            exportFinderSyncRootsIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "加载工作副本失败：\(error.localizedDescription)"
        }
    }

    public func addWorkingCopy(at url: URL) async {
        do {
            let record = try await workspaceStore.addExistingWorkingCopy(
                localPath: url,
                infoProvider: infoProvider
            )
            await reload()
            selectedID = record.id
            errorMessage = nil
        } catch let error as WorkspaceStoreError {
            switch error {
            case .invalidWorkingCopy(let path):
                errorMessage = "不是有效的 SVN 工作副本：\(path)"
            }
        } catch {
            errorMessage = "添加失败：\(error.localizedDescription)"
        }
    }

    public func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择本地 SVN 工作副本目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addWorkingCopy(at: url) }
    }

    public func removeSelected() async {
        guard let selectedID else { return }
        do {
            try await workspaceStore.removeWorkingCopy(id: selectedID)
            // removeWorkingCopy 为同步 throws；经 actor 隔离后以 async 调用
            await reload()
            errorMessage = nil
        } catch {
            errorMessage = "移除失败：\(error.localizedDescription)"
        }
    }

    /// 深链 / CLI 打开本地路径：已登记则选中，否则尝试添加为工作副本。
    public func openLocalPath(_ path: String) async {
        let normalized = (path as NSString).standardizingPath
        let existing = records.compactMap { record -> (record: WorkingCopyRecord, path: String)? in
            let workingCopyPath = (record.localPath as NSString).standardizingPath
            let prefix = workingCopyPath.hasSuffix("/") ? workingCopyPath : workingCopyPath + "/"
            guard normalized == workingCopyPath || normalized.hasPrefix(prefix) else { return nil }
            return (record, workingCopyPath)
        }.max { $0.path.count < $1.path.count }?.record
        if let existing {
            selectedID = existing.id
            errorMessage = nil
            return
        }

        await addWorkingCopy(at: URL(fileURLWithPath: normalized, isDirectory: true))
    }

    /// 将有效 WC 根目录导出给 Finder Sync 扩展读取。
    private func exportFinderSyncRootsIfPossible() {
        guard let supportDirectory else { return }
        let fileURL = FinderSyncRootsExporter.fileURL(in: supportDirectory)
        try? FinderSyncRootsExporter.export(records: records, to: fileURL)
    }
}
