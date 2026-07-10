import SwiftUI
import MacSvnCore

/// 选中 WC 后的工作区壳：Mode 顶栏 + 内容分发。
public struct MacSvnWorkingCopyShellView: View {
    @ObservedObject private var session: MacSvnAppSession
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator

    public init(
        session: MacSvnAppSession,
        workspaceController: MacSvnWorkspaceController,
        navigator: MacSvnAppNavigator
    ) {
        self.session = session
        self.workspaceController = workspaceController
        self.navigator = navigator
    }

    private var selectedMode: MacSvnWorkspaceMode {
        MacSvnWorkspaceMode(route: navigator.selectedRoute)
    }

    /// 设置 / AI 等全局工具不依赖有效 WC。
    private var allowsContentWithoutValidWC: Bool {
        MacSvnWorkspaceMode.toolModes.contains(selectedMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            modeToolbar
            Divider()
            contentArea
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if workspaceController.records.isEmpty, !allowsContentWithoutValidWC {
            emptyNoWorkingCopies
        } else if workspaceController.selectedRecord == nil, !allowsContentWithoutValidWC {
            ContentUnavailableView(
                "未选择工作副本",
                systemImage: "sidebar.left",
                description: Text("请从左侧列表选择一个工作副本")
            )
        } else if workspaceController.selectedRecord?.isValid == false, !allowsContentWithoutValidWC {
            ContentUnavailableView(
                "工作副本无效",
                systemImage: "exclamationmark.triangle",
                description: Text("本地路径可能已移动或不是合法 SVN 目录，请移除后重新添加")
            )
        } else {
            modeContent
        }
    }

    private var emptyNoWorkingCopies: some View {
        ContentUnavailableView {
            Label("添加工作副本", systemImage: "externaldrive.badge.plus")
        } description: {
            Text("将本地 SVN 目录拖到左侧列表，或点击下方按钮选择目录。也可先打开「工具 → 设置」。")
        } actions: {
            Button("添加工作副本…") {
                workspaceController.presentAddPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("打开设置") {
                navigator.selectMode(.settings)
            }
        }
    }

    private var modeToolbar: some View {
        HStack(spacing: 8) {
            // 仅当当前为 primary 时绑定 segmented；否则显示当前页标题，避免非法 tag
            if MacSvnWorkspaceMode.primaryModes.contains(selectedMode) {
                Picker("模式", selection: modeBinding) {
                    ForEach(MacSvnWorkspaceMode.primaryModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            } else {
                HStack(spacing: 8) {
                    Label(selectedMode.title, systemImage: selectedMode.systemImage)
                        .font(.headline)
                    Button("返回变更") {
                        navigator.selectMode(.changes)
                    }
                }
            }

            Menu("更多") {
                ForEach(MacSvnWorkspaceMode.advancedModes) { mode in
                    Button {
                        navigator.selectMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            }

            Menu("工具") {
                ForEach(MacSvnWorkspaceMode.toolModes) { mode in
                    Button {
                        navigator.selectMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            }

            Spacer()

            if let record = workspaceController.selectedRecord {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.name)
                        .font(.caption.weight(.semibold))
                    if let revision = record.revision {
                        Text("r\(revision.value)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modeBinding: Binding<MacSvnWorkspaceMode> {
        Binding(
            get: { selectedMode },
            set: { navigator.selectMode($0) }
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch selectedMode {
        case .changes:
            MacSvnWorkingCopyWorkspaceView(
                workspaceController: workspaceController,
                session: session,
                navigator: navigator
            )
        default:
            MacSvnFeatureHostView(
                route: selectedMode.primaryRoute,
                session: session,
                workspaceController: workspaceController,
                navigator: navigator
            )
        }
    }
}
