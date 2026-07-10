import SwiftUI
import MacSvnCore

/// 启动门禁：检测本机 svn 可用性；不满足时展示安装/配置引导。
public struct MacSvnEnvironmentGateView: View {
    @ObservedObject private var session: MacSvnAppSession
    @ObservedObject private var navigator: MacSvnAppNavigator
    @State private var status: SvnEnvironmentStatus?
    @State private var isChecking = true
    @State private var customPath: String = ""

    public init(session: MacSvnAppSession, navigator: MacSvnAppNavigator) {
        self.session = session
        self.navigator = navigator
    }

    public var body: some View {
        Group {
            if isChecking {
                ProgressView("正在检测 Subversion…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .available = status {
                MacSvnRootView(session: session, navigator: navigator)
            } else {
                gateContent
            }
        }
        .task {
            await refresh()
        }
    }

    @ViewBuilder
    private var gateContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("需要 Subversion CLI")
                .font(.largeTitle.weight(.semibold))

            Text(statusMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("推荐安装命令：")
                .font(.headline)
            Text("brew install subversion")
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                TextField("或指定 svn 可执行路径", text: $customPath)
                    .textFieldStyle(.roundedBorder)
                Button("保存并重试") {
                    Task { await saveAndRetry() }
                }
                .keyboardShortcut(.defaultAction)
            }

            Button("重新检测") {
                Task { await refresh() }
            }
        }
        .padding(40)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusMessage: String {
        switch status {
        case .available(let path, let version):
            return "已找到 \(path)（\(version.description)）"
        case .unsupportedVersion(let path, let version, let minimum):
            return "已找到 \(path)，版本 \(version.description) 过低，需要 ≥ \(minimum.description)。"
        case .missing(let checkedPaths):
            return "未找到可用的 svn。已检查：\(checkedPaths.joined(separator: ", "))"
        case .none:
            return "尚未完成检测。"
        }
    }

    private func refresh() async {
        isChecking = true
        let settings = await session.settingsStore.settings()
        customPath = settings.svnPath ?? session.svnExecutablePath
        status = await session.environmentChecker.check(configuredPath: settings.svnPath)
        isChecking = false
    }

    private func saveAndRetry() async {
        var settings = await session.settingsStore.settings()
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.svnPath = trimmed.isEmpty ? nil : trimmed
        do {
            try await session.settingsStore.update(settings)
        } catch {
            // 保存失败仍继续检测，便于用户看到环境状态
        }
        await refresh()
    }
}

private extension SvnVersion {
    var description: String { "\(major).\(minor).\(patch)" }
}
