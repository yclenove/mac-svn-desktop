import SwiftUI
import MacSvnCore

/// AI Provider 设置：列表 / 新增 / Keychain 密钥 / 连通性测试 / 脱敏开关。
public struct MacSvnAIProviderSettingsView: View {
    private let session: MacSvnAppSession

    @State private var viewModel: AIProviderSettingsViewModel?
    @State private var draftName = "火山方舟 Coding"
    @State private var draftKind: AIProviderKind = .openAICompatible
    @State private var draftBaseURL = "https://ark.cn-beijing.volces.com/api/coding/v3"
    @State private var draftModel = "doubao-seed-code"
    @State private var draftAPIKey = ""
    @State private var draftMaxTokens = 2048
    @State private var draftTemperature = 0.2
    @State private var makeDefault = true
    @State private var redactionEnabled = true
    @State private var sendsDiffOnly = true
    @State private var statusText: String?

    public init(session: MacSvnAppSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            Section("隐私") {
                Toggle("发送前脱敏（密钥/证件等）", isOn: $redactionEnabled)
                Toggle("仅发送 Diff（不发送整文件）", isOn: $sendsDiffOnly)
                Button("保存隐私设置") {
                    Task { await savePrivacy() }
                }
            }

            Section("已配置 Provider") {
                if let viewModel {
                    ForEach(viewModel.providers) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(provider.name).font(.headline)
                                if viewModel.defaultProviderID == provider.id {
                                    Text("默认")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Button("设为默认") {
                                    Task { await viewModel.setDefaultProvider(provider.id) }
                                }
                                Button("测试连通性") {
                                    Task {
                                        await viewModel.testConnection(provider)
                                        if let result = viewModel.connectionTestResult {
                                            statusText = "连通成功：\(result.latencyMilliseconds) ms"
                                        }
                                    }
                                }
                                Button("删除", role: .destructive) {
                                    Task {
                                        if let ref = provider.apiKeyRef {
                                            try? await session.aiKeychainStore.deleteAPIKey(ref: ref)
                                        }
                                        await viewModel.deleteProvider(provider.id)
                                    }
                                }
                            }
                            Text("\(provider.kind.rawValue) · \(provider.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(provider.baseURL)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    ProgressView()
                }
            }

            Section("新增 / 更新 Provider") {
                HStack {
                    Button("填入火山方舟 Coding 预设") {
                        draftName = "火山方舟 Coding"
                        draftKind = .openAICompatible
                        draftBaseURL = "https://ark.cn-beijing.volces.com/api/coding/v3"
                        draftModel = "doubao-seed-code"
                        draftMaxTokens = 4096
                        draftTemperature = 0.2
                        makeDefault = true
                        statusText = "已填入预设；请粘贴 API Key 后保存（Key 只进 Keychain）"
                    }
                    Spacer()
                }
                TextField("名称", text: $draftName)
                Picker("类型", selection: $draftKind) {
                    Text("OpenAI Compatible").tag(AIProviderKind.openAICompatible)
                    Text("Anthropic").tag(AIProviderKind.anthropic)
                    Text("Ollama").tag(AIProviderKind.ollama)
                }
                TextField("Base URL", text: $draftBaseURL)
                TextField("Model", text: $draftModel)
                SecureField("API Key（写入 Keychain）", text: $draftAPIKey)
                Stepper("maxTokens \(draftMaxTokens)", value: $draftMaxTokens, in: 256...128_000, step: 256)
                Slider(value: $draftTemperature, in: 0...1, step: 0.05) {
                    Text("temperature \(draftTemperature, specifier: "%.2f")")
                }
                Toggle("保存后设为默认", isOn: $makeDefault)
                Button("保存 Provider") {
                    Task { await saveProvider() }
                }
                .keyboardShortcut(.defaultAction)
            }

            if let statusText {
                Text(statusText).foregroundStyle(.secondary)
            }
            if case .error(let message) = viewModel?.state {
                Text(message).foregroundStyle(.red)
            }
            if let result = viewModel?.connectionTestResult {
                Text("最近测试：latency \(result.latencyMilliseconds)ms / tokens \(result.promptTokens)+\(result.completionTokens)")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("AI Provider")
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        viewModel = AIProviderSettingsViewModel(
            manager: session.aiProviderStore,
            connectivityTester: session.aiProviderConnectivityTester
        )
        await viewModel?.loadProviders()
        let privacy = await session.currentAIPrivacy()
        redactionEnabled = privacy.isRedactionEnabled
        sendsDiffOnly = privacy.sendsDiffOnly
    }

    private func savePrivacy() async {
        var settings = await session.settingsStore.settings()
        settings.aiPrivacy = AIPrivacySettings(
            isRedactionEnabled: redactionEnabled,
            sendsDiffOnly: sendsDiffOnly,
            customRedactionPatterns: settings.aiPrivacy.customRedactionPatterns
        )
        do {
            try await session.settingsStore.update(settings)
            statusText = "隐私设置已保存"
        } catch {
            statusText = "隐私设置保存失败：\(error.localizedDescription)"
        }
    }

    private func saveProvider() async {
        guard let viewModel else { return }
        var provider = AIProvider(
            name: draftName,
            kind: draftKind,
            baseURL: draftBaseURL,
            model: draftModel,
            apiKeyRef: nil,
            maxTokens: draftMaxTokens,
            temperature: draftTemperature
        )

        let key = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do {
                provider.apiKeyRef = try await session.aiKeychainStore.saveAPIKey(key, for: provider.id)
            } catch {
                statusText = "Keychain 写入失败：\(error.localizedDescription)"
                return
            }
        }

        await viewModel.saveProvider(provider, makeDefault: makeDefault)
        if case .error(let message) = viewModel.state {
            statusText = message
        } else {
            draftAPIKey = ""
            statusText = "Provider 已保存"
            await viewModel.loadProviders()
        }
    }
}
