import SwiftUI
import MacSvnCore
import AppKit

public struct MacSvnRootView: View {
    @ObservedObject private var session: MacSvnAppSession
    @ObservedObject private var navigator: MacSvnAppNavigator
    @StateObject private var workspaceController: MacSvnWorkspaceController
    private let onWorkspaceReady: () -> Void
    @State private var showCommandPalette = false
    @State private var confirmRemove = false

    public init(
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator,
        sidebarModel: MacSvnSidebarModel = MacSvnSidebarModel(),
        onWorkspaceReady: @escaping () -> Void = {}
    ) {
        self.session = session
        self.navigator = navigator
        self.onWorkspaceReady = onWorkspaceReady
        // sidebarModel 保留参数以兼容旧调用方；新壳不再使用功能侧栏
        _ = sidebarModel
        _workspaceController = StateObject(
            wrappedValue: MacSvnWorkspaceController(
                workspaceStore: session.workspaceStore,
                infoProvider: session.svnService,
                finderSyncConfigurationFileURLs: session.finderSyncConfigurationFileURLs
            )
        )
    }

    public var body: some View {
        NavigationSplitView {
            workingCopySidebar
                .navigationTitle(ProductBranding.displayName)
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 320)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if let message = navigator.lastAutomationMessage {
                    automationBanner(message)
                }
                if case .updateAvailable(let release) = session.updateStatus {
                    updateBanner(release)
                }
                MacSvnWorkingCopyShellView(
                    session: session,
                    workspaceController: workspaceController,
                    navigator: navigator
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            await workspaceController.reload()
            await consumePendingOpenIfNeeded()
            // 首次进入默认落在变更工作区
            if MacSvnWorkspaceMode(route: navigator.selectedRoute) == .changes,
               navigator.selectedRoute == .workspace {
                navigator.selectMode(.changes)
            }
            onWorkspaceReady()
        }
        .onChange(of: navigator.pendingOpenPath) { _, _ in
            Task { await consumePendingOpenIfNeeded() }
        }
        .sheet(isPresented: $showCommandPalette) {
            MacSvnCommandPaletteView(
                navigator: navigator,
                workspaceController: workspaceController,
                session: session,
                isPresented: $showCommandPalette
            )
            .macSvnDismissibleSheet()
        }
        .background {
            Button("") { showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .confirmationDialog(
            "仅从列表移除记录，不会删除磁盘文件。确认移除？",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                Task { await workspaceController.removeSelected() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var workingCopySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作副本")
                    .font(.headline)
                Spacer()
                Button {
                    workspaceController.presentAddPanel()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("添加工作副本")
                .accessibilityLabel("添加工作副本")
                Button {
                    confirmRemove = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(workspaceController.selectedID == nil)
                .help("移除选中工作副本")
                .accessibilityLabel("移除选中工作副本")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let errorMessage = workspaceController.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            List(selection: $workspaceController.selectedID) {
                ForEach(workspaceController.records) { record in
                    sidebarRow(record)
                        .tag(record.id)
                        .contextMenu {
                            Button {
                                showInFinder(record)
                            } label: {
                                Label("在 Finder 中显示", systemImage: "folder")
                            }
                            Button {
                                copyToPasteboard(record.localPath)
                            } label: {
                                Label("复制本地路径", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button("移除工作副本…", role: .destructive) {
                                workspaceController.selectedID = record.id
                                confirmRemove = true
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }

            Text("拖入目录可添加")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }

    private func sidebarRow(_ record: WorkingCopyRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(record.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(record.name)
                if record.isValid == false {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("工作副本无效")
                        .accessibilityLabel("工作副本无效")
                }
            }
            Text(shortPath(record.localPath))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(record.localPath)
            HStack(spacing: 6) {
                if let revision = record.revision {
                    Text("r\(revision.value)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(repositorySummary(record.repoURL))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(record.repoURL)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 48, alignment: .leading)
        .opacity(record.isValid == false ? 0.55 : 1)
    }

    private func automationBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                navigator.dismissAutomationBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private func updateBanner(_ release: AppRelease) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
            Text("SVN Studio \(release.version) 可用")
                .frame(maxWidth: .infinity, alignment: .leading)
            Link("查看发布页", destination: release.pageURL)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private func shortPath(_ path: String) -> String {
        if path.hasPrefix(NSHomeDirectory()) {
            return "~" + path.dropFirst(NSHomeDirectory().count)
        }
        return path
    }

    private func repositorySummary(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        let repository = url.lastPathComponent
        guard let host = url.host, !host.isEmpty else {
            return repository.isEmpty ? value : repository
        }
        return repository.isEmpty ? host : "\(host)/\(repository)"
    }

    private func showInFinder(_ record: WorkingCopyRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: record.localPath)
        ])
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    await workspaceController.addWorkingCopy(at: url)
                }
            }
            accepted = true
        }
        return accepted
    }

    private func consumePendingOpenIfNeeded() async {
        guard let path = navigator.consumePendingOpenPath() else { return }
        await workspaceController.openLocalPath(path)
    }
}

public struct MacSvnSettingsLoadingView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("\(ProductBranding.displayName) 启动中…")
                .foregroundStyle(.secondary)
        }
        .frame(width: 420)
        .padding(32)
    }
}
