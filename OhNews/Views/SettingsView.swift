import AppKit
import OhNewsKit
import SwiftUI

/// AI 设置。
///
/// 所有改动先落在本地 `config` / `apiKey` 上，点「保存」才写入 UserDefaults 与钥匙串，
/// 避免边输入边写钥匙串。
struct SettingsView: View {
    @Environment(AppState.self) private var state

    @State private var config = AIProviderConfig.default
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var status: StatusMessage?
    @State private var isTesting = false
    @State private var isLoaded = false

    private enum StatusMessage {
        case info(String)
        case success(String)
        case failure(String)

        var text: String {
            switch self {
            case .info(let text), .success(let text), .failure(let text): text
            }
        }

        var icon: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .failure: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .failure: .orange
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 摘要", isOn: $config.isEnabled)
            } footer: {
                Text("关闭后应用退回纯阅读器，不会发起任何 AI 请求。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("供应商") {
                Picker("预设", selection: $config.preset) {
                    ForEach(AIProviderPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: config.preset) { _, newValue in
                    config.applyPreset(newValue)
                    status = nil
                    loadStoredKey()
                }

                Text(presetHint)

                TextField("接口地址", text: $config.baseURL)

                if config.isInsecureTransport {
                    Label(
                        "该地址使用明文 http。除本机与局域网服务外，建议改用 https。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if config.preset.requiresAPIKey {
                    SecureField("API Key", text: $apiKey)
                    Text(
                        hasStoredKey
                            ? "已保存在系统钥匙串；留空并保存会删除已存的密钥。"
                            : "密钥只写入系统钥匙串，不会进入配置文件或日志。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label("本地服务不需要 API Key。", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("模型") {
                TextField("摘要模型", text: $config.summaryModel)
                Text("用于列表摘要，建议用便宜快速的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("深度分析模型", text: $config.analysisModel)
                Text("V0 尚未使用，后续做详情级解读时启用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OhNews")
                        .font(.headline)
                    Text("Hacker News 阅读器 · 版本 \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("专有软件 © 2026 Nipher")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("查看最终用户许可协议") {
                    openBundledDocument(named: "EULA")
                }

                Button("查看第三方组件声明") {
                    openBundledDocument(named: "THIRD_PARTY_NOTICES")
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button("测试连接") {
                        Task { await runConnectionTest() }
                    }
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    Button("保存") {
                        Task { await save() }
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if let status {
                    Label(status.text, systemImage: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("「测试连接」会用一条固定的极短内容真实调用一次接口，用来验证地址、密钥、模型名与输出格式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 520)
        .task { load() }
    }

    private var presetHint: String {
        config.preset.hint
    }

    /// 版本号来自 app bundle，避免与工程里的 `MARKETING_VERSION` 漂移。
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    private func load() {
        guard isLoaded == false else { return }
        config = state.config
        loadStoredKey()
        isLoaded = true
    }

    private func loadStoredKey() {
        let stored = KeychainStore().read(account: config.preset.keychainAccount) ?? ""
        apiKey = stored
        hasStoredKey = stored.isEmpty == false
    }

    private func save() async {
        let keychain = KeychainStore()
        do {
            if config.preset.requiresAPIKey {
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    try keychain.delete(account: config.preset.keychainAccount)
                    hasStoredKey = false
                } else {
                    try keychain.save(trimmed, account: config.preset.keychainAccount)
                    hasStoredKey = true
                }
            }
        } catch {
            status = .failure("写入钥匙串失败：\((error as NSError).localizedDescription)")
            return
        }

        await state.saveConfig(config)
        status = .success("已保存。")
    }

    private func openBundledDocument(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") else {
            status = .failure("找不到随应用附带的文档。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runConnectionTest() async {
        isTesting = true
        defer { isTesting = false }

        let result = await state.testAIConnection(config: config, apiKey: apiKey)
        switch result {
        case .success(let summary):
            status = .success("连接成功。模型返回的摘要：\(summary)")
        case .failure(let error):
            status = .failure(error.displayMessage)
        }
    }
}
